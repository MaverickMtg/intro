-- =============================================
-- FL-Admin Server Side (Files/Server.lua)
-- Full admin panel server logic
-- =============================================

local AdminStates = {} -- [source] = { menuOpen, spectating, etc }
local HoursData = {}
local ReportsData = {}
local PointsData = {}
local MutedPlayers = {}
local ChatMutedPlayers = {}
local JailedPlayers = {}
local PlayerNotes = {}
local PendingRestore = {} -- [source] = os.time() grant for the "Sent Back [E]" restore

-- Staff hours/points/reports + notes persist via resource KVP so they
-- survive restarts (they used to live only in memory).
local function LoadStaffData()
    local raw = GetResourceKvpString('tg_admin_staffdata')
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            HoursData = data.hours or {}
            PointsData = data.points or {}
            ReportsData = data.reports or {}
            PlayerNotes = data.notes or {}
        end
    end
end

local function SaveStaffData()
    SetResourceKvp('tg_admin_staffdata', json.encode({
        hours = HoursData, points = PointsData, reports = ReportsData, notes = PlayerNotes,
    }))
end

LoadStaffData()
CreateThread(function()
    while true do
        Wait(300000) -- autosave every 5 minutes
        SaveStaffData()
    end
end)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then SaveStaffData() end
end)

-- =============================================
-- DATABASE INIT
-- =============================================
MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vikto_admin_history` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid` VARCHAR(50) DEFAULT NULL,
            `action` VARCHAR(100) NOT NULL,
            `details` TEXT DEFAULT NULL,
            `admin_source` INT DEFAULT NULL,
            `admin_name` VARCHAR(100) DEFAULT NULL,
            `timestamp` DATETIME DEFAULT CURRENT_TIMESTAMP
        );
    ]])
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vikto_admin_bans` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid` VARCHAR(50) NOT NULL,
            `reason` TEXT DEFAULT NULL,
            `banned_by` VARCHAR(100) DEFAULT NULL,
            `expires` DATETIME DEFAULT NULL,
            `permanent` TINYINT(1) DEFAULT 0
        );
    ]])
    -- Persistent jail records: keyed by citizenid so they survive relogs
    -- AND server restarts.
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vikto_admin_jails` (
            `citizenid` VARCHAR(50) NOT NULL PRIMARY KEY,
            `until_time` BIGINT NOT NULL DEFAULT 0,
            `reason` TEXT DEFAULT NULL,
            `admin_name` VARCHAR(100) DEFAULT NULL
        );
    ]], {}, function()
        MySQL.query('SELECT * FROM vikto_admin_jails WHERE until_time > ?', { os.time() }, function(rows)
            for _, row in ipairs(rows or {}) do
                JailedPlayers[row.citizenid] = {
                    until_time = row.until_time,
                    reason = row.reason,
                    adminName = row.admin_name,
                }
            end
            if rows and #rows > 0 then
                print(('^3[FL-Admin] Restored %d active jail record(s) from database.^7'):format(#rows))
            end
        end)
        -- Clean out expired leftovers
        MySQL.query('DELETE FROM vikto_admin_jails WHERE until_time <= ?', { os.time() })
    end)
    print("^2[FL-Admin] Database tables initialized!^7")
end)

-- =============================================
-- HELPER: Log admin action to DB
-- =============================================
local function LogAction(adminSource, action, details, targetCid)
    local adminName = adminSource > 0 and GetPlayerName(adminSource) or "Console"
    MySQL.insert('INSERT INTO vikto_admin_history (citizenid, action, details, admin_source, admin_name) VALUES (?, ?, ?, ?, ?)', {
        targetCid or 'N/A', action, details or '', adminSource, adminName
    })
    print(("^3[FL-Admin] %s (Source: %s) -> %s: %s^7"):format(adminName, adminSource, action, details or ''))
end

-- =============================================
-- HELPER: Get player CID
-- =============================================
local function GetCid(source)
    if GetResourceState('FL-Core') == 'started' then
        local p = exports['FL-Core']:GetPlayer(source)
        if p then return p.PlayerData.citizenid end
    end
    return tostring(source)
end

-- =============================================
-- HELPER: Get source by CID
-- =============================================
local function GetSourceByCid(cid)
    cid = tostring(cid)
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local playerCid = GetCid(src)
        if tostring(playerCid) == cid then
            return src
        end
    end
    return nil
end

-- =============================================
-- HELPER: Check permission
-- =============================================
-- =============================================
-- DISCORD ROLE RESOLUTION (permission backbone)
-- =============================================
local RoleCache = {} -- [discordId] = { roles = {...}, fetchedAt = os.time() }

local function IsHardcodedAdmin(src)
    if src == 0 then return true end
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id == 'license:79ae3802639b533e2c7b37c3a7f54d01bcde8a92' or id == 'license:25ebfc36ecd8a38a7a14dcc016f315753758cc3b' or id == 'license:3f15b5191f208f9b829465073f605d2974467971' then
            return true
        end
    end
    return false
end

local function GetDiscordId(src)
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:sub(1, 8) == 'discord:' then
            return id:gsub('discord:', '')
        end
    end
    return nil
end

local function FetchDiscordRoles(discordId)
    if not discordId then return {} end
    local cached = RoleCache[discordId]
    if cached and (os.time() - cached.fetchedAt) < (ConfigS.RoleCacheTime or 300) then
        return cached.roles
    end
    if not ConfigS.BotToken or ConfigS.BotToken == '' or not ConfigS.GuildId or ConfigS.GuildId == '' then
        return {}
    end
    local p = promise.new()
    PerformHttpRequest(
        ('https://discord.com/api/v10/guilds/%s/members/%s'):format(ConfigS.GuildId, discordId),
        function(status, body)
            local roles = {}
            if status == 200 and body then
                local ok, data = pcall(json.decode, body)
                if ok and data and data.roles then roles = data.roles end
            end
            RoleCache[discordId] = { roles = roles, fetchedAt = os.time() }
            p:resolve(roles)
        end,
        'GET', '',
        { ['Authorization'] = 'Bot ' .. ConfigS.BotToken, ['Content-Type'] = 'application/json' }
    )
    return Citizen.Await(p)
end

-- Returns a set { [permissionName] = true } of the roles the player holds.
local function GetPlayerRoleNames(src)
    local names = {}
    if IsHardcodedAdmin(src) then
        names['FullPermissions'] = true
        return names
    end
    local discordId = GetDiscordId(src)
    if discordId then
        if discordId == '1483297687326687417' then
            names['FullPermissions'] = true
            return names
        end
        for _, roleId in ipairs(FetchDiscordRoles(discordId)) do
            local permName = ConfigS.DiscordRoles[tostring(roleId)]
            if type(permName) == 'table' then
                for _, name in ipairs(permName) do
                    names[name] = true
                end
            elseif permName then
                names[permName] = true
            end
        end
    end
    return names
end

-- Highest permission level the player has (0 if none).
local function GetPlayerLevel(src)
    if src == 0 then return math.huge end
    if IsHardcodedAdmin(src) then
        return ConfigS.PermissionLevels['FullPermissions'] or 100
    end
    if IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'admin') then
        return ConfigS.PermissionLevels['FullPermissions'] or 100
    end
    local level = 0
    for name in pairs(GetPlayerRoleNames(src)) do
        local lv = ConfigS.PermissionLevels[name] or 0
        if lv > level then level = lv end
    end
    if level == 0 then
        local unconfigured = (not ConfigS.BotToken or ConfigS.BotToken == '') and next(ConfigS.DiscordRoles) == nil
        if unconfigured and ConfigS.AllowEveryoneWhenUnconfigured then
            return ConfigS.PermissionLevels['FullPermissions'] or 100
        end
    end
    return level
end

-- Does the player hold ANY of the given permission names (or an ace override)?
local function PlayerHasAnyRoleName(src, roleList)
    if src == 0 then return true end
    if IsHardcodedAdmin(src) then return true end
    if IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'admin') then return true end
    local held = GetPlayerRoleNames(src)
    if held['FullPermissions'] then return true end
    if type(roleList) ~= 'table' then return false end
    for _, name in ipairs(roleList) do
        if held[name] then return true end
    end
    return false
end

local function HasPermission(source, minLevel)
    if source == 0 then return true end
    local level = GetPlayerLevel(source)
    local has = level >= (tonumber(minLevel) or 0)
    if level >= (ConfigS.MinPermissionLevel or 5) then
        local ply = Player(source)
        if ply and ply.state then
            ply.state.isStaff = true
            TriggerClientEvent('vikto_admin:client:syncStaffStatus', source, true)
        end
    end
    return has
end

-- Prevents a lower- or equal-ranked staff member from taking punitive/invasive
-- actions (kick, ban, kill, freeze, mute, jail, etc.) against a higher-or-equal
-- ranked player. Only meaningful when the target is currently online (rank of
-- an offline citizenid can't be checked); acting on yourself is always allowed.
local function CanActOnTarget(src, targetSrc)
    if src == 0 then return true end -- server console
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == 0 then return true end
    if targetSrc == src then return true end
    return GetPlayerLevel(src) > GetPlayerLevel(targetSrc)
end

-- =============================================
-- PERMISSION GROUPS (server-side source of truth)
-- =============================================
-- These mirror the role lists used in Config.AdminMenuCategories. The menu
-- already hides options by role, but the actual net events used to be gated
-- only by LOW numeric levels (e.g. Give Item at level 40), so any staff
-- member who fired the event directly bypassed the menu's tier restrictions.
-- Every sensitive handler below now enforces the same role list as the menu.
local PERM = {}
PERM.Top3 = { 'FullPermissions', 'Founders', 'ServerManager' }
PERM.Managers = {
    'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager',
    'HighManager', 'HighAssManager', 'GeneralManager', 'GeneralAssManager',
    'MTGTeam', 'Admin', 'Operator', 'Organizer', 'Cordinator', 'Staff', 'Advisor'
}
PERM.AllStaff = {
    'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager',
    'HighManager', 'HighAssManager', 'GeneralManager', 'GeneralAssManager',
    'IDNamesTeam', 'StreamerTeam', 'CensorTeam', 'BanTeam', 'EventTeam',
    'LogTeam', 'TicketTeam', 'MTGTeam', 'Admin', 'Operator', 'Organizer',
    'Cordinator', 'Staff', 'Advisor', 'Expert', 'Supervisor', 'Skilled',
    'Trusted', 'Experience', 'Trial', 'SeniorMod', 'Mod', 'TrialMod', 'Support'
}
PERM.Ban = {
    'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager',
    'HighManager', 'HighAssManager', 'GeneralManager', 'GeneralAssManager', 'BanTeam'
}
PERM.Unban        = { 'FullPermissions', 'Founders', 'ServerManager', 'BanTeam', 'Unban' }
PERM.Unjail       = { 'FullPermissions', 'Founders', 'ServerManager', 'Unjail' }
PERM.MuteVoice    = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteVoice' }
PERM.MuteChat     = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteChat' }
PERM.Freeze       = { 'FullPermissions', 'Founders', 'ServerManager', 'Freeze' }
PERM.Spectate     = { 'FullPermissions', 'Founders', 'ServerManager', 'Spectate' }
PERM.ReviveRadius = { 'FullPermissions', 'Founders', 'ServerManager', 'ReviveRadius' }
PERM.Announce     = { 'FullPermissions', 'Founders', 'ServerManager', 'Announcements' }
PERM.DM           = { 'FullPermissions', 'Founders', 'ServerManager', 'DirectMessage' }
PERM.ClearChat    = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam' }
PERM.Vehicles     = { 'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager', 'Vehicles' }
PERM.Hours        = { 'FullPermissions', 'Founders', 'ServerManager', 'HoursManager' }
PERM.Reports      = { 'FullPermissions', 'Founders', 'ServerManager', 'ReportsManager' }
PERM.EventPoints  = { 'FullPermissions', 'Founders', 'ServerManager', 'EventTeam', 'EventsManager' }
PERM.StaffLB      = { 'FullPermissions', 'Founders', 'ServerManager', 'StaffPoints', 'HoursManager', 'ReportsManager', 'EventsManager', 'EventTeam' }
PERM.CID          = { 'FullPermissions' }

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function(src)
    src = src or source
    if not src then return end
    local has = HasPermission(src, ConfigS.MinPermissionLevel)
    local ply = Player(src)
    if ply and ply.state then
        ply.state.isStaff = has
        TriggerClientEvent('vikto_admin:client:syncStaffStatus', src, has)
    end
end)

exports('HasPermission', function(source, minLevel)
    -- Accept either a numeric level or a role-name list from other resources.
    if type(minLevel) == 'table' then
        return PlayerHasAnyRoleName(source, minLevel)
    end
    return HasPermission(source, minLevel or ConfigS.MinPermissionLevel)
end)

local function NotifyPlayer(source, text, type, duration)
    TriggerClientEvent('QBCore:Notify', source, text, type or 'inform', duration or 5000)
end

-- =============================================
-- PERMISSION CHECKS
-- =============================================
RegisterNetEvent('vikto_admin:server:checkPermission', function(action, data)
    local src = source
    if not HasPermission(src, ConfigS.MinPermissionLevel) then
        NotifyPlayer(src, 'You do not have permission!', 'error')
        return
    end
    
    if action == 'players' then
        local players = {}
        for _, playerId in ipairs(GetPlayers()) do
            local s = tonumber(playerId)
            players[#players + 1] = {
                id = s,
                serverId = s, -- the NUI player card / modal read `serverId`
                name = GetPlayerName(s) or "Unknown",
                cid = GetCid(s),
                ping = GetPlayerPing(s)
            }
        end
        TriggerClientEvent('vikto_admin:client:openPanel', src, players)
    elseif action == 'playerModal' and data then
        local allowedModal = {}
        for _, category in ipairs(Config.PlayerModalActions or {}) do
            if PlayerHasAnyRoleName(src, category.permission) then
                local filteredCat = {
                    category = category.category,
                    permission = category.permission,
                    buttons = {}
                }
                for _, btn in ipairs(category.buttons or {}) do
                    if not btn.permission or PlayerHasAnyRoleName(src, btn.permission) then
                        filteredCat.buttons[#filteredCat.buttons + 1] = btn
                    end
                end
                if #filteredCat.buttons > 0 then
                    allowedModal[#allowedModal + 1] = filteredCat
                end
            end
        end
        data.modalConfig = allowedModal
        TriggerClientEvent('vikto_admin:client:openPlayerModal', src, data)
    elseif action == 'records' then
        TriggerClientEvent('vikto_admin:client:openRecords', src)
    else
        TriggerClientEvent('vikto_admin:client:openPanel', src, {})
    end
end)

-- Look up an option's permission list by its event name in the SHARED config,
-- so keybind/command permission checks can't be spoofed by a client sending a
-- fake `permission` field (the old code trusted client-supplied data and only
-- verified "is staff at all").
local function FindConfigPermissionForEvent(eventName)
    if not eventName then return nil end
    for _, category in ipairs(Config.AdminMenuCategories or {}) do
        for _, opt in ipairs(category.options or {}) do
            if opt.event == eventName then return opt.permission end
        end
    end
    for _, cmd in ipairs(Config.CommandPermission or {}) do
        if cmd.event == eventName then return cmd.permission end
    end
    for _, category in ipairs(Config.PlayerModalActions or {}) do
        for _, btn in ipairs(category.buttons or {}) do
            if btn.event == eventName then return btn.permission end
        end
    end
    return nil
end

RegisterNetEvent('vikto_admin:server:checkOptionPermission', function(data)
    local src = source
    local allowed = false
    if HasPermission(src, ConfigS.MinPermissionLevel) then
        local configPerm = FindConfigPermissionForEvent(data and data.event)
        if configPerm then
            allowed = PlayerHasAnyRoleName(src, configPerm)
        else
            allowed = true -- staff-only option with no explicit role list
        end
    end
    TriggerClientEvent('vikto_admin:client:optionPermissionResult', src, data, allowed)
end)

RegisterNetEvent('vikto_admin:server:setMenuOpen', function(state)
    local src = source
    AdminStates[src] = AdminStates[src] or {}
    AdminStates[src].menuOpen = state
end)

-- =============================================
-- PLAYER ACTIONS
-- =============================================

RegisterNetEvent('vikto_admin:server:kickPlayer', function(targetId, reason)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Managers) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if target then
        DropPlayer(target, reason or "Kicked by admin")
        LogAction(src, 'KICK', ('Kicked player %s: %s'):format(targetId, reason or 'No reason'), tostring(targetId))
    end
end)

RegisterNetEvent('vikto_admin:server:banPlayer', function(cid, reason, duration)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Ban) then return end
    local target = GetSourceByCid(cid)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    
    local expires = nil
    local permanent = false
    if duration and tonumber(duration) and tonumber(duration) > 0 then
        expires = os.date('%Y-%m-%d %H:%M:%S', os.time() + (tonumber(duration) * 3600))
    else
        permanent = true
    end
    
    MySQL.insert('INSERT INTO vikto_admin_bans (citizenid, reason, banned_by, expires, permanent) VALUES (?, ?, ?, ?, ?)', {
        tostring(cid), reason, GetPlayerName(src), expires, permanent and 1 or 0
    })
    
    if target then
        DropPlayer(target, "Banned: " .. (reason or "No reason"))
    end
    LogAction(src, 'BAN', ('Banned %s: %s (Duration: %s)'):format(cid, reason or 'No reason', duration or 'permanent'), tostring(cid))
    NotifyPlayer(src, 'Player banned!', 'success')
end)

RegisterNetEvent('vikto_admin:server:unbanPlayer', function(cid, reason)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Unban) then return end
    MySQL.update('DELETE FROM vikto_admin_bans WHERE citizenid = ?', { tostring(cid) })
    LogAction(src, 'UNBAN', ('Unbanned %s: %s'):format(cid, reason or 'No reason'), tostring(cid))
    NotifyPlayer(src, 'Player unbanned!', 'success')
end)

RegisterNetEvent('vikto_admin:server:warnPlayer', function(cid, reason)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Managers) then return end
    local target = GetSourceByCid(cid)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if target then
        NotifyPlayer(target, 'WARNING: ' .. (reason or 'Watch your behavior'), 'error', 10000)
    end
    LogAction(src, 'WARN', ('Warned %s: %s'):format(cid, reason or 'No reason'), tostring(cid))
    NotifyPlayer(src, 'Player warned!', 'success')
end)

RegisterNetEvent('vikto_admin:server:killPlayer', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Managers) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if target then
        local ped = GetPlayerPed(target)
        if ped and ped ~= 0 then
            SetEntityHealth(ped, 0)
        end
    end
    LogAction(src, 'KILL', ('Killed player %s'):format(targetId), tostring(targetId))
end)

RegisterNetEvent('vikto_admin:server:revivePlayer', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Managers) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if target then
        TriggerClientEvent('vikto_admin:client:revive', target)
    end
    LogAction(src, 'REVIVE', ('Revived player %s'):format(targetId))
end)

RegisterNetEvent('vikto_admin:server:reviveAll', function()
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Top3) then return end
    TriggerClientEvent('vikto_admin:client:revive', -1)
    LogAction(src, 'REVIVE_ALL', 'Revived all players')
end)

RegisterNetEvent('vikto_admin:server:reviveRadius', function(radius)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.ReviveRadius) then return end
    TriggerClientEvent('vikto_admin:client:reviveRadius', -1, src, radius)
    LogAction(src, 'REVIVE_RADIUS', ('Revived in radius: %s'):format(radius))
end)

FrozenPlayers = {} -- [src] = true while frozen (server-side truth for the modal)

RegisterNetEvent('vikto_admin:server:freezePlayer', function(targetId, state)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Freeze) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if target then
        FrozenPlayers[target] = state and true or nil
        TriggerClientEvent('vikto_admin:client:freeze', target, state)
    end
    LogAction(src, state and 'FREEZE' or 'UNFREEZE', ('Player %s'):format(targetId))
end)

-- The player modal's "Unfreeze" button fires this event directly; it had no
-- handler, so unfreezing from the modal silently did nothing.
RegisterNetEvent('vikto_admin:server:unfreezePlayer', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Freeze) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if target then
        FrozenPlayers[target] = nil
        TriggerClientEvent('vikto_admin:client:freeze', target, false)
    end
    LogAction(src, 'UNFREEZE', ('Player %s'):format(targetId))
end)

RegisterNetEvent('vikto_admin:server:gotoPlayer', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.AllStaff) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if target then
        local ped = GetPlayerPed(target)
        if ped and ped ~= 0 then
            local coords = GetEntityCoords(ped)
            TriggerClientEvent('vikto_admin:client:teleport', src, coords)
        end
    end
end)

RegisterNetEvent('vikto_admin:server:bringPlayer', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Managers) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if target then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local coords = GetEntityCoords(ped)
            TriggerClientEvent('vikto_admin:client:teleport', target, coords)
        end
    end
    LogAction(src, 'BRING', ('Brought player %s'):format(targetId))
end)

-- NOTE: 'vikto_admin:server:teleportPlayerToSpawn' used to be registered TWICE
-- (here and further below) — RegisterNetEvent stacks handlers, so one admin
-- click ran both bodies and everything was logged twice. Only the complete
-- handler (near the leaderboard section) remains.

-- =============================================
-- SPECTATE
-- =============================================
RegisterNetEvent('vikto_admin:server:spectatePlayer', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Spectate) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if target then
        local ped = GetPlayerPed(target)
        if ped and ped ~= 0 then
            local coords = GetEntityCoords(ped)
            TriggerClientEvent('vikto_admin:client:spectate', src, target, coords)
        end
    end
end)

RegisterNetEvent('vikto_admin:server:spectateEnd', function()
    local src = source
    TriggerClientEvent('vikto_admin:client:spectateEnd', src)
end)

RegisterNetEvent('vikto_admin:server:spectateCycle', function(currentTarget, forward)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Spectate) then return end
    local players = GetPlayers()
    if #players <= 1 then return end
    -- Simple cycle: pick next/prev
    local idx = 1
    for i, p in ipairs(players) do
        if tonumber(p) == tonumber(currentTarget) then idx = i break end
    end
    if forward then idx = idx + 1 else idx = idx - 1 end
    if idx > #players then idx = 1 end
    if idx < 1 then idx = #players end
    local newTarget = tonumber(players[idx])
    if newTarget == src then
        if forward then idx = idx + 1 else idx = idx - 1 end
        if idx > #players then idx = 1 end
        if idx < 1 then idx = #players end
        newTarget = tonumber(players[idx])
    end
    local ped = GetPlayerPed(newTarget)
    if ped and ped ~= 0 then
        TriggerClientEvent('vikto_admin:client:spectate', src, newTarget, GetEntityCoords(ped))
    end
end)

-- =============================================
-- COMMUNICATION
-- =============================================
-- Announcements go through the systems players actually see:
-- a prominent FL-Essentials notification for everyone + a message in FL-Chat.
-- (The old 'chat:addMessage' broadcast had no listener on this server.)
local ANNOUNCE_AVATAR = 'https://raw.githubusercontent.com/hussein15alnajar-wq/TRG/refs/heads/main/BOT.png'

local function BroadcastAnnouncement(text)
    if GetResourceState('FL-Essentials') == 'started' then
        TriggerClientEvent('FL-Essentials:client:Notify', -1, 'primary', 'ANNOUNCEMENT', text, 12000)
    end
    if GetResourceState('FL-Chat') == 'started' then
        TriggerClientEvent('chat:client:ReceiveMessage', -1, {
            id = false,
            roleName = 'ANNOUNCEMENT',
            roleColor = 'rgb(180, 180, 180)',
            isSystem = true,
            name = 'ANNOUNCEMENT',
            message = text,
            avatar = ANNOUNCE_AVATAR,
        })
    end
end

RegisterNetEvent('vikto_admin:server:announce', function(text)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Announce) then return end
    if type(text) ~= 'string' or text == '' then return end
    BroadcastAnnouncement(text)
    LogAction(src, 'ANNOUNCE', text)
    NotifyPlayer(src, 'Announcement sent!', 'success')
end)

local function SendAdminDM(src, target, message)
    if not target or not GetPlayerName(target) then
        return NotifyPlayer(src, 'Player not found or offline.', 'error')
    end
    if GetResourceState('FL-Essentials') == 'started' then
        TriggerClientEvent('FL-Essentials:client:Notify', target, 'primary', 'ADMIN MESSAGE', message, 12000)
    end
    if GetResourceState('FL-Chat') == 'started' then
        TriggerClientEvent('chat:client:ReceiveMessage', target, {
            id = false,
            roleName = 'ADMIN DM',
            roleColor = 'rgb(255, 75, 75)',
            isSystem = true,
            name = 'ADMIN DM',
            message = message,
            avatar = ANNOUNCE_AVATAR,
        })
    end
    LogAction(src, 'ADMIN_DM', message, GetCid(target))
    NotifyPlayer(src, 'Message delivered.', 'success')
end

-- Resolve any admin-typed id (server id / real CID / IdSystem custom ID)
-- to an online source. Defined here so every handler below can use it.
local function ResolveAnyTargetSource(targetId)
    if GetResourceState('FL-IdSystem') == 'started' then
        local ok, s = pcall(function() return exports['FL-IdSystem']:GetSourceByAnyId(targetId) end)
        if ok and s then return tonumber(s) end
    end
    local byCid = GetSourceByCid(tostring(targetId))
    if byCid then return byCid end
    local n = tonumber(targetId)
    if n and GetPlayerName(n) then return n end
    return nil
end

RegisterNetEvent('vikto_admin:server:messageID', function(targetId, message)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.AllStaff) then return end
    if type(message) ~= 'string' or message == '' then return end
    SendAdminDM(src, ResolveAnyTargetSource(targetId), message)
end)

RegisterNetEvent('vikto_admin:server:messagePlayer', function(cid, message)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.DM) then return end
    if type(message) ~= 'string' or message == '' then return end
    SendAdminDM(src, ResolveAnyTargetSource(cid), message)
end)

RegisterNetEvent('vikto_admin:server:clearChat', function()
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.ClearChat) then return end
    -- This server runs FL-Chat, which listens to its own clear event.
    TriggerClientEvent('chat:client:ClearChat', -1)
    LogAction(src, 'CLEAR_CHAT', 'Cleared chat for everyone')
    NotifyPlayer(src, 'Chat cleared.', 'success')
end)

-- =============================================
-- MUTE / JAIL
-- =============================================
RegisterNetEvent('vikto_admin:server:mutePlayer', function(targetId, minutes, reason)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.MuteVoice) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    -- minutes == 0 means "Permanent" from the UI's unit picker — that used to
    -- compute until_time = now + 0, so the mute expired within the same second
    -- it was issued. Use a far-future sentinel instead.
    local durationMin = tonumber(minutes)
    local untilTime = (durationMin and durationMin > 0) and (os.time() + durationMin * 60) or (os.time() + 100 * 365 * 24 * 60 * 60)
    MutedPlayers[tostring(targetId)] = { until_time = untilTime, reason = reason }
    if target then NotifyPlayer(target, 'You have been voice muted! Reason: ' .. (reason or 'N/A'), 'error', 10000) end
    LogAction(src, 'MUTE_VOICE', ('Muted %s for %s min: %s'):format(targetId, minutes, reason or ''))
    NotifyPlayer(src, 'Player voice muted!', 'success')
end)

RegisterNetEvent('vikto_admin:server:unmutePlayer', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.MuteVoice) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    MutedPlayers[tostring(targetId)] = nil
    NotifyPlayer(src, 'Player voice unmuted!', 'success')
end)

RegisterNetEvent('vikto_admin:server:muteChatPlayer', function(targetId, minutes, reason)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.MuteChat) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    local durationMin = tonumber(minutes)
    local untilTime = (durationMin and durationMin > 0) and (os.time() + durationMin * 60) or (os.time() + 100 * 365 * 24 * 60 * 60)
    ChatMutedPlayers[tostring(targetId)] = { until_time = untilTime, reason = reason }
    if target then NotifyPlayer(target, 'You have been chat muted! Reason: ' .. (reason or 'N/A'), 'error', 10000) end
    LogAction(src, 'MUTE_CHAT', ('Chat muted %s for %s min: %s'):format(targetId, minutes, reason or ''))
    NotifyPlayer(src, 'Player chat muted!', 'success')
end)

RegisterNetEvent('vikto_admin:server:unmuteChatPlayer', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.MuteChat) then return end
    local target = GetSourceByCid(targetId) or tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    ChatMutedPlayers[tostring(targetId)] = nil
    NotifyPlayer(src, 'Player chat unmuted!', 'success')
end)

-- Chat mute must be queryable by other resources (FL-Chat) — nothing outside
-- this file could previously see ChatMutedPlayers, so a mute never actually
-- blocked a message; it only changed what the admin panel displayed.
local function IsChatMutedServer(src)
    local cid = GetCid(src)
    local rec = ChatMutedPlayers[tostring(cid)] or ChatMutedPlayers[tostring(src)]
    if rec and rec.until_time > os.time() then
        return true, rec.reason
    end
    return false
end
exports('IsChatMuted', IsChatMutedServer)

-- Resolve whatever an admin typed (server id / real CID / IdSystem custom ID)
-- to { onlineSource or nil, citizenid or nil }. Jail records are ALWAYS keyed
-- by citizenid so they survive relogs and server restarts.
local function ResolveJailTarget(targetId)
    local target = nil
    if GetResourceState('FL-IdSystem') == 'started' then
        local ok, s = pcall(function() return exports['FL-IdSystem']:GetSourceByAnyId(targetId) end)
        if ok and s then target = tonumber(s) end
    end
    if not target then
        target = GetSourceByCid(tostring(targetId))
    end
    if not target and tonumber(targetId) and GetPlayerName(tostring(targetId)) then
        target = tonumber(targetId)
    end

    local cid = target and GetCid(target) or nil
    if not cid and not tonumber(targetId) then
        cid = tostring(targetId) -- offline player referenced by citizenid string
    end
    if not cid and tonumber(targetId) then
        cid = tostring(targetId) -- last resort: raw value (offline numeric cid)
    end
    return target, cid
end

local function GetJailRecord(cid)
    local rec = cid and JailedPlayers[tostring(cid)] or nil
    if rec and rec.until_time <= os.time() then
        JailedPlayers[tostring(cid)] = nil
        MySQL.query('DELETE FROM vikto_admin_jails WHERE citizenid = ?', { tostring(cid) })
        return nil
    end
    return rec
end

local function IsJailedServer(src)
    local cid = GetCid(src)
    return GetJailRecord(cid) ~= nil
end

local function ApplyJailToClient(target, rec)
    TriggerClientEvent('vikto_admin:client:jail', target, true, {
        remaining = math.max(0, rec.until_time - os.time()),
        reason = rec.reason or 'No reason provided',
        admin = rec.adminName or 'Unknown Admin',
    })
end

local function ReleaseFromJail(cid, target, silent)
    JailedPlayers[tostring(cid)] = nil
    MySQL.query('DELETE FROM vikto_admin_jails WHERE citizenid = ?', { tostring(cid) })
    if target and GetPlayerName(target) then
        TriggerClientEvent('vikto_admin:client:jail', target, false)
        -- Back to the lobby spawn like the end of any gamemode.
        if GetResourceState('FL-Core') == 'started' then
            pcall(function() exports['FL-Core']:SendToSpawn(target) end)
        end
        if not silent then
            NotifyPlayer(target, 'You have been unjailed!', 'success')
        end
    end
end

local function JailPlayer(src, targetId, time, reason)
    local target, cid = ResolveJailTarget(targetId)
    if not cid then
        return NotifyPlayer(src, 'Player not found!', 'error')
    end
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end

    local minutes = math.max(1, math.min(tonumber(time) or 30, Config.JailOptions and Config.JailOptions.MaxJailTime or 120))
    local adminName = GetPlayerName(src) or 'Console'
    local rec = {
        until_time = os.time() + minutes * 60,
        reason = reason,
        adminName = adminName,
    }
    JailedPlayers[tostring(cid)] = rec
    MySQL.query([[INSERT INTO vikto_admin_jails (citizenid, until_time, reason, admin_name)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE until_time = VALUES(until_time), reason = VALUES(reason), admin_name = VALUES(admin_name)]],
        { tostring(cid), rec.until_time, rec.reason or '', adminName })

    if target then
        NotifyPlayer(target, 'You have been jailed! Reason: ' .. (reason or 'N/A'), 'error', 10000)
        ApplyJailToClient(target, rec)
    end
    LogAction(src, 'JAIL', ('Jailed %s for %s min: %s'):format(tostring(cid), minutes, reason or ''), tostring(cid))
    NotifyPlayer(src, 'Player jailed!', 'success')
end

local function UnjailPlayer(src, targetId)
    local target, cid = ResolveJailTarget(targetId)
    if not cid or not JailedPlayers[tostring(cid)] then
        return NotifyPlayer(src, 'No jail record found for that player.', 'error')
    end
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end

    ReleaseFromJail(cid, target)
    LogAction(src, 'UNJAIL', ('Unjailed %s'):format(tostring(cid)), tostring(cid))
    NotifyPlayer(src, 'Player unjailed!', 'success')
end

RegisterNetEvent('vikto_admin:server:jailPlayer', function(targetId, time, reason)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.AllStaff) then return end
    JailPlayer(src, targetId, time, reason)
end)

RegisterNetEvent('vikto_admin:server:unjailPlayer', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Unjail) then return end
    UnjailPlayer(src, targetId)
end)



RegisterNetEvent('vikto_admin:server:checkJailTime', function(cidOrId)
    local src = source
    if not HasPermission(src, ConfigS.MinPermissionLevel) then return end
    local _, cid = ResolveJailTarget(cidOrId)
    local jailed = cid and GetJailRecord(cid) or nil
    if jailed then
        local remaining = math.max(0, jailed.until_time - os.time())
        TriggerClientEvent('vikto_admin:client:jailTimeResult', src, cidOrId, remaining, jailed.reason)
    else
        TriggerClientEvent('vikto_admin:client:jailTimeResult', src, cidOrId, 0, nil)
    end
end)

-- Authoritative expiry watcher: releases online players the moment their
-- sentence ends (client timer is cosmetic; this is the source of truth).
CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for cid, rec in pairs(JailedPlayers) do
            if rec.until_time <= now then
                local target = GetSourceByCid(cid)
                ReleaseFromJail(cid, target)
                if target then
                    NotifyPlayer(target, 'Your jail sentence is over.', 'success')
                end
            end
        end
    end
end)

-- Jail status must be queryable by OTHER resources (matchmaking rank queue,
-- F1 menu, FL-Core spawn) — server-side and cheat-proof.
exports('IsPlayerJailed', IsJailedServer)
exports('isPlayerJailed', IsJailedServer)

-- =============================================
-- ITEMS / COINS
-- =============================================
RegisterNetEvent('vikto_admin:server:giveItem', function(targetId, item, amount)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Top3) then return end
    local target = tonumber(targetId)
    if target and GetResourceState('FL-Inventory') == 'started' then
        exports['FL-Inventory']:AddItem(target, item, tonumber(amount) or 1)
    end
    LogAction(src, 'GIVE_ITEM', ('Gave %sx %s to %s'):format(amount, item, targetId))
    NotifyPlayer(src, 'Item given!', 'success')
end)

RegisterNetEvent('vikto_admin:server:removeItem', function(targetId, item, amount)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Top3) then return end
    local target = tonumber(targetId)
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if target and GetResourceState('FL-Inventory') == 'started' then
        exports['FL-Inventory']:RemoveItem(target, item, tonumber(amount) or 1)
    end
    LogAction(src, 'REMOVE_ITEM', ('Removed %sx %s from %s'):format(amount, item, targetId))
    NotifyPlayer(src, 'Item removed!', 'success')
end)

-- Coins actions actually touch the shared `coins` table now
-- (via the ak4y exports when running, direct SQL otherwise).
local function ResolveCoinsCid(targetId)
    local target = ResolveAnyTargetSource(targetId)
    if target then return GetCid(target) end
    return tostring(targetId) -- offline: assume a citizenid was typed
end

RegisterNetEvent('vikto_admin:server:coins:add', function(targetId, amount)
    local src = source
    if not PlayerHasAnyRoleName(src, { 'FullPermissions', 'Founders', 'ServerManager', 'StoreManager' }) then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return NotifyPlayer(src, 'Invalid amount.', 'error') end
    local cid = ResolveCoinsCid(targetId)
    if GetResourceState('ak4y-vipSystemv2') == 'started' then
        pcall(function() exports['ak4y-vipSystemv2']:AddPlayerCoins(cid, amount) end)
    else
        MySQL.query('INSERT INTO coins (cid, amount) VALUES (?, ?) ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)', { cid, amount })
    end
    LogAction(src, 'COINS_ADD', ('%s coins to %s'):format(amount, cid), cid)
    NotifyPlayer(src, ('Added %d coins to %s.'):format(amount, cid), 'success')
end)

RegisterNetEvent('vikto_admin:server:coins:remove', function(targetId, amount)
    local src = source
    if not PlayerHasAnyRoleName(src, { 'FullPermissions', 'Founders', 'ServerManager', 'StoreManager' }) then return end
    local rankTarget = ResolveAnyTargetSource(targetId)
    if not CanActOnTarget(src, rankTarget) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return NotifyPlayer(src, 'Invalid amount.', 'error') end
    local cid = ResolveCoinsCid(targetId)
    if GetResourceState('ak4y-vipSystemv2') == 'started' then
        pcall(function() exports['ak4y-vipSystemv2']:RemovePlayerCoins(cid, amount) end)
    else
        MySQL.query('UPDATE coins SET amount = GREATEST(0, amount - ?) WHERE cid = ?', { amount, cid })
    end
    LogAction(src, 'COINS_REMOVE', ('%s coins from %s'):format(amount, cid), cid)
    NotifyPlayer(src, ('Removed %d coins from %s.'):format(amount, cid), 'success')
end)

RegisterNetEvent('vikto_admin:server:coins:check', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, { 'FullPermissions', 'Founders', 'ServerManager', 'StoreManager' }) then return end
    local cid = ResolveCoinsCid(targetId)
    MySQL.query('SELECT amount FROM coins WHERE cid = ?', { cid }, function(rows)
        local amount = rows and rows[1] and rows[1].amount or 0
        TriggerClientEvent('vikto_admin:client:coinsResult', src, cid, amount)
    end)
end)

-- =============================================
-- HOURS / POINTS / REPORTS
-- =============================================
-- These staff hours/points/reports mutations had NO permission checks at all:
-- ANY connected player could fire the events and hand themselves staff points.
RegisterNetEvent('vikto_admin:server:addHours', function(targetId, amount) if not PlayerHasAnyRoleName(source, PERM.Hours) then return end HoursData[tostring(targetId)] = (HoursData[tostring(targetId)] or 0) + (tonumber(amount) or 0) NotifyPlayer(source, 'Hours added!', 'success') end)
RegisterNetEvent('vikto_admin:server:removeHours', function(targetId, amount) if not PlayerHasAnyRoleName(source, PERM.Hours) then return end HoursData[tostring(targetId)] = math.max(0, (HoursData[tostring(targetId)] or 0) - (tonumber(amount) or 0)) NotifyPlayer(source, 'Hours removed!', 'success') end)
RegisterNetEvent('vikto_admin:server:viewPlayerHours', function(targetId) if not PlayerHasAnyRoleName(source, PERM.Hours) then return end TriggerClientEvent('vikto_admin:client:viewHoursResult', source, targetId, HoursData[tostring(targetId)] or 0) end)
RegisterNetEvent('vikto_admin:server:addPoints', function(targetId, amount) if not PlayerHasAnyRoleName(source, PERM.EventPoints) then return end PointsData[tostring(targetId)] = (PointsData[tostring(targetId)] or 0) + (tonumber(amount) or 0) NotifyPlayer(source, 'Points added!', 'success') end)
RegisterNetEvent('vikto_admin:server:removePoints', function(targetId, amount) if not PlayerHasAnyRoleName(source, PERM.EventPoints) then return end PointsData[tostring(targetId)] = math.max(0, (PointsData[tostring(targetId)] or 0) - (tonumber(amount) or 0)) NotifyPlayer(source, 'Points removed!', 'success') end)
RegisterNetEvent('vikto_admin:server:viewPlayerPoints', function(targetId) if not PlayerHasAnyRoleName(source, PERM.EventPoints) then return end TriggerClientEvent('vikto_admin:client:viewPointsResult', source, targetId, PointsData[tostring(targetId)] or 0) end)
RegisterNetEvent('vikto_admin:server:addReports', function(targetId, amount) if not PlayerHasAnyRoleName(source, PERM.Reports) then return end ReportsData[tostring(targetId)] = (ReportsData[tostring(targetId)] or 0) + (tonumber(amount) or 0) NotifyPlayer(source, 'Reports added!', 'success') end)
RegisterNetEvent('vikto_admin:server:removeReports', function(targetId, amount) if not PlayerHasAnyRoleName(source, PERM.Reports) then return end ReportsData[tostring(targetId)] = math.max(0, (ReportsData[tostring(targetId)] or 0) - (tonumber(amount) or 0)) NotifyPlayer(source, 'Reports removed!', 'success') end)
RegisterNetEvent('vikto_admin:server:viewPlayerReports', function(targetId) if not PlayerHasAnyRoleName(source, PERM.Reports) then return end TriggerClientEvent('vikto_admin:client:viewReportsResult', source, targetId, ReportsData[tostring(targetId)] or 0) end)

RegisterNetEvent('vikto_admin:server:resetAllHours', function() if not PlayerHasAnyRoleName(source, PERM.Hours) then return end HoursData = {} NotifyPlayer(source, 'All hours reset!', 'success') end)
RegisterNetEvent('vikto_admin:server:resetAllPoints', function() if not PlayerHasAnyRoleName(source, PERM.EventPoints) then return end PointsData = {} NotifyPlayer(source, 'All points reset!', 'success') end)
RegisterNetEvent('vikto_admin:server:resetAllReports', function() if not PlayerHasAnyRoleName(source, PERM.Reports) then return end ReportsData = {} NotifyPlayer(source, 'All reports reset!', 'success') end)

-- =============================================
-- LEADERBOARDS
-- =============================================
RegisterNetEvent('vikto_admin:server:sendLeaderboard', function() if not HasPermission(source, ConfigS.MinPermissionLevel) then return end TriggerClientEvent('vikto_admin:client:leaderboardData', source, PointsData) end)
RegisterNetEvent('vikto_admin:server:sendHoursLeaderboard', function() if not HasPermission(source, ConfigS.MinPermissionLevel) then return end TriggerClientEvent('vikto_admin:client:hoursLeaderboardData', source, HoursData) end)
RegisterNetEvent('vikto_admin:server:sendReportsLeaderboard', function() if not HasPermission(source, ConfigS.MinPermissionLevel) then return end TriggerClientEvent('vikto_admin:client:reportsLeaderboardData', source, ReportsData) end)

-- Staff leaderboards: build a top list from the data set and either post it
-- to a Discord webhook (convar `tg_admin_lb_webhook` in server.cfg) or show
-- it to the requesting admin. Send = post/show; Update = same rebuild.
-- (The old handlers bounced client<->server in a circle and did nothing.)
local function BuildStaffTopList(title, dataSet)
    local list = {}
    for key, value in pairs(dataSet or {}) do
        list[#list + 1] = { id = key, value = tonumber(value) or 0 }
    end
    table.sort(list, function(a, b) return a.value > b.value end)

    local lines = { ('**%s — Top %d**'):format(title, math.min(#list, 10)) }
    for i = 1, math.min(#list, 10) do
        local e = list[i]
        local s = GetSourceByCid(e.id) or tonumber(e.id)
        local name = (s and GetPlayerName(s)) or ('CID ' .. tostring(e.id))
        lines[#lines + 1] = ('%d. %s — %d'):format(i, name, e.value)
    end
    if #list == 0 then lines[#lines + 1] = 'No entries yet.' end
    return table.concat(lines, '\n')
end

local function DeliverStaffLB(src, title, dataSet)
    if not PlayerHasAnyRoleName(src, PERM.StaffLB) then return end
    local text = BuildStaffTopList(title, dataSet)
    local webhook = GetConvar('tg_admin_lb_webhook', '')
    if webhook ~= '' then
        PerformHttpRequest(webhook, function() end, 'POST',
            json.encode({ username = 'FL Staff Leaderboards', content = text }),
            { ['Content-Type'] = 'application/json' })
        NotifyPlayer(src, title .. ' posted to Discord!', 'success')
    else
        -- No webhook configured: show it to the admin in chat instead.
        if GetResourceState('FL-Chat') == 'started' then
            TriggerClientEvent('chat:client:ReceiveMessage', src, {
                id = 0, cid = 'SYSTEM', name = '📊 ' .. title,
                message = text:gsub('%*%*', ''), avatar = ANNOUNCE_AVATAR,
            })
        end
        NotifyPlayer(src, 'No webhook set (tg_admin_lb_webhook) — showing in chat.', 'inform')
    end
    LogAction(src, 'STAFF_LB', title)
end

RegisterNetEvent('Vikto:Admin:SendStaffLB', function() DeliverStaffLB(source, 'Staff Points Leaderboard', PointsData) end)
RegisterNetEvent('Vikto:Admin:SendHoursLB', function() DeliverStaffLB(source, 'Staff Hours Leaderboard', HoursData) end)
RegisterNetEvent('Vikto:Admin:SendReportsLB', function() DeliverStaffLB(source, 'Staff Reports Leaderboard', ReportsData) end)
RegisterNetEvent('Vikto:Admin:SendEventLB', function() DeliverStaffLB(source, 'Staff Events Leaderboard', PointsData) end)
RegisterNetEvent('Vikto:Admin:UpdateStaffLB', function() DeliverStaffLB(source, 'Staff Points Leaderboard', PointsData) end)
RegisterNetEvent('Vikto:Admin:UpdateHoursLB', function() DeliverStaffLB(source, 'Staff Hours Leaderboard', HoursData) end)
RegisterNetEvent('Vikto:Admin:UpdateReportsLB', function() DeliverStaffLB(source, 'Staff Reports Leaderboard', ReportsData) end)
RegisterNetEvent('Vikto:Admin:UpdateEventLB', function() DeliverStaffLB(source, 'Staff Events Leaderboard', PointsData) end)

-- Player-context modal "Go To Spawn": send the selected player to the lobby spawn.
RegisterNetEvent('vikto_admin:server:teleportPlayerToSpawn', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.AllStaff) then return end
    local target = ResolveAnyTargetSource(targetId)
    if not target then return NotifyPlayer(src, 'Player not found or offline.', 'error') end
    if not CanActOnTarget(src, target) then
        return NotifyPlayer(src, 'You cannot use this on a player of equal or higher rank.', 'error')
    end
    if GetResourceState('FL-Core') == 'started' then
        pcall(function() exports['FL-Core']:SendToSpawn(target) end)
        PendingRestore[target] = os.time() -- allow the target's "Sent Back [E]" restore
        LogAction(src, 'SEND_TO_SPAWN', ('Sent %s to spawn'):format(GetPlayerName(target) or target), GetCid(target))
        NotifyPlayer(src, 'Player sent to spawn.', 'success')
    else
        NotifyPlayer(src, 'FL-Core is not running.', 'error')
    end
end)

-- =============================================
-- PLAYER DETAILS / HISTORY / NOTES
-- =============================================
RegisterNetEvent('vikto_admin:server:fetchPlayerDetail', function(playerId, tab)
    local src = source
    if not HasPermission(src, ConfigS.MinPermissionLevel) then return end
    local target = ResolveAnyTargetSource(playerId)
    tab = tab or 'status'

    -- The 'status' tab drives the modal's jail/mute/freeze toggle buttons, which
    -- only make sense for a currently-connected player.
    if tab == 'status' then
        if not target then return end
        local cid = GetCid(target)
        local data = {
            id = target,
            -- The NUI modal reads `source` from the status payload as the
            -- target's online server id and DISABLES every button flagged
            -- `disableOffline` when it's missing. This field was never sent,
            -- so Kill/Kick/Freeze/Give Item/etc. showed up greyed out even
            -- for FullPermissions admins looking at an ONLINE player.
            source = target,
            serverId = target,
            name = GetPlayerName(target) or 'Unknown',
            cid = cid,
            citizenid = cid,
            ping = GetPlayerPing(target),
            isJailed = (cid and JailedPlayers[tostring(cid)] and JailedPlayers[tostring(cid)].until_time > os.time()) or false,
            isMutedVoice = (MutedPlayers[tostring(cid)] or MutedPlayers[tostring(target)]) ~= nil,
            isMutedChat = (ChatMutedPlayers[tostring(cid)] or ChatMutedPlayers[tostring(target)]) ~= nil,
            isFrozen = FrozenPlayers and FrozenPlayers[target] == true or false,
            note = PlayerNotes[tostring(cid)] or PlayerNotes[tostring(target)] or '',
        }
        TriggerClientEvent('vikto_admin:client:playerDetailUpdate', src, tab, data)
        return
    end

    -- The modal's History tab expects { history = rows }; it used to receive
    -- the generic info payload (no `history` key) and stayed empty forever.
    if tab == 'history' then
        local cid = target and GetCid(target) or tostring(playerId)
        MySQL.query('SELECT * FROM vikto_admin_history WHERE citizenid = ? ORDER BY id DESC LIMIT 20', { tostring(cid) }, function(rows)
            TriggerClientEvent('vikto_admin:client:playerDetailUpdate', src, tab, { history = rows or {}, citizenid = cid })
        end)
        return
    end

    -- The modal's IDs tab expects { ids = {...} } (identifier strings).
    if tab == 'ids' then
        local ids = {}
        if target then
            for i = 0, GetNumPlayerIdentifiers(target) - 1 do
                ids[#ids + 1] = GetPlayerIdentifier(target, i)
            end
        end
        TriggerClientEvent('vikto_admin:client:playerDetailUpdate', src, tab, { ids = ids })
        return
    end

    -- Every other tab (the Info panel, etc.) is keyed by citizenid so it also
    -- works for offline players — previously this whole handler returned early
    -- (and sent nothing back) whenever the target wasn't currently connected,
    -- which is why the Info tab was blank for anyone shown as "Offline".
    local cid = target and GetCid(target) or tostring(playerId)

    MySQL.scalar('SELECT COUNT(*) FROM vikto_admin_bans WHERE citizenid = ?', { cid }, function(totalBans)
        MySQL.scalar("SELECT COUNT(*) FROM vikto_admin_history WHERE citizenid = ? AND action = 'WARN'", { cid }, function(totalWarns)
            local data = {
                id = target,
                source = target,
                serverId = target,
                name = target and GetPlayerName(target) or nil,
                cid = cid,
                citizenid = cid,
                online = target ~= nil,
                ping = target and GetPlayerPing(target) or nil,
                totalBans = totalBans or 0,
                totalWarns = totalWarns or 0,
                notes = PlayerNotes[tostring(cid)] or '',
                -- NOTE: playTime and joined are not implemented anywhere in this
                -- resource yet (Config.PlaytimeTracking has no code behind it, and
                -- there's no join-date source here) — see chat.
            }
            TriggerClientEvent('vikto_admin:client:playerDetailUpdate', src, tab, data)
        end)
    end)
end)

RegisterNetEvent('vikto_admin:server:fetchHistoryMore', function(cid, offset, filter)
    local src = source
    if not HasPermission(src, ConfigS.MinPermissionLevel) then return end
    MySQL.query('SELECT * FROM vikto_admin_history WHERE citizenid = ? ORDER BY id DESC LIMIT 20 OFFSET ?', { tostring(cid), tonumber(offset) or 0 }, function(rows)
        TriggerClientEvent('vikto_admin:client:historyData', src, rows or {})
    end)
end)

RegisterNetEvent('vikto_admin:server:getGlobalHistory', function(data)
    local src = source
    if not HasPermission(src, ConfigS.MinPermissionLevel) then return end
    local page = (data and tonumber(data.page)) or 1
    local pageSize = (data and tonumber(data.pageSize)) or 20
    local offset = (page - 1) * pageSize

    MySQL.scalar('SELECT COUNT(*) FROM vikto_admin_history', {}, function(total)
        MySQL.query('SELECT * FROM vikto_admin_history ORDER BY id DESC LIMIT ? OFFSET ?', { pageSize, offset }, function(rows)
            -- NOTE: the client (and current UI build) listens for 'receiveGlobalHistory' —
            -- the old 'globalHistoryData' event had no matching handler in the current UI,
            -- so the History tab never received data and just spun forever.
            TriggerClientEvent('vikto_admin:client:receiveGlobalHistory', src, {
                history = rows or {},
                total = total or 0,
                page = page,
                pageSize = pageSize,
            })
        end)
    end)
end)

RegisterNetEvent('vikto_admin:server:savePlayerNote', function(playerId, note)
    local src = source
    if not HasPermission(src, ConfigS.MinPermissionLevel) then return end
    PlayerNotes[tostring(playerId)] = note
    NotifyPlayer(src, 'Note saved!', 'success')
end)

RegisterNetEvent('vikto_admin:server:addPlayerWhitelist', function(playerId) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end NotifyPlayer(source, 'Player whitelisted!', 'success') end)

-- =============================================
-- CID MANAGEMENT
-- =============================================
RegisterNetEvent('Vikto:Admin:Server:ChangeCID', function(oldCid, newCid)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.CID) then return end
    local target = GetSourceByCid(oldCid)
    if not target then
        return NotifyPlayer(src, 'Player must be online to migrate CID!', 'error')
    end
    local success, err = exports['FL-Core']:MigratePlayerCid(target, newCid)
    if success then
        LogAction(src, 'CHANGE_CID', ('Changed CID %s -> %s for target source %s'):format(oldCid, newCid, tostring(target)))
        NotifyPlayer(src, 'CID changed successfully to ' .. newCid, 'success')
    else
        NotifyPlayer(src, 'Failed to change CID: ' .. (err or 'Unknown error'), 'error')
    end
end)

RegisterNetEvent('Vikto:Admin:Server:CheckCID', function(cid)
    if not PlayerHasAnyRoleName(source, PERM.CID) then return end
    TriggerClientEvent('Vikto:Admin:Client:CIDResult', source, cid, GetSourceByCid(cid) ~= nil)
end)

RegisterNetEvent('Vikto:Admin:Server:DeleteCID', function(cid)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.CID) then return end
    LogAction(src, 'DELETE_CID', ('Deleted CID %s'):format(cid))
    NotifyPlayer(src, 'CID deleted!', 'success')
end)

RegisterNetEvent('Vikto:Admin:Server:ResetCID', function(playerId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.CID) then return end
    LogAction(src, 'RESET_CID', ('Reset CID for %s'):format(playerId))
    NotifyPlayer(src, 'CID reset!', 'success')
end)

RegisterNetEvent('vikto_admin:server:checkPlayerID', function(id)
    local src = source
    if not HasPermission(src, ConfigS.MinPermissionLevel) then return end
    local target = ResolveAnyTargetSource(id)
    TriggerClientEvent('vikto_admin:client:playerIDResult', src, id, target ~= nil, target and GetPlayerName(target) or nil)
end)
RegisterNetEvent('vikto_admin:server:changePlayerIDByMetadata', function(currentId, newId) if not HasPermission(source, 80) then return end NotifyPlayer(source, 'Player ID changed!', 'success') end)
RegisterNetEvent('vikto_admin:server:deletePlayerIDByMetadata', function(currentId) if not HasPermission(source, 80) then return end NotifyPlayer(source, 'Player ID deleted!', 'success') end)

-- =============================================
-- XP / TRUCK POINTS
-- =============================================
-- Matchmaking XP / Truck points — real DB reads & writes (were dead stubs).
local function ResolveStatsCid(anyId)
    local target = ResolveAnyTargetSource(anyId)
    if target then return GetCid(target) end
    return tostring(anyId)
end

RegisterNetEvent('vikto_admin:server:checkMatchmakingXP', function(cid)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Top3) then return end
    local realCid = ResolveStatsCid(cid)
    MySQL.query('SELECT xp FROM tg_matchmaking WHERE citizenid = ?', { realCid }, function(rows)
        TriggerClientEvent('vikto_admin:client:matchmakingXPResult', src, realCid, rows and rows[1] and rows[1].xp or 0)
    end)
end)

RegisterNetEvent('vikto_admin:server:adjustMatchmakingXP', function(cid, amount, action)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Top3) then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return NotifyPlayer(src, 'Invalid amount.', 'error') end
    local realCid = ResolveStatsCid(cid)
    if action == 'remove' then
        MySQL.query('UPDATE tg_matchmaking SET xp = GREATEST(0, xp - ?) WHERE citizenid = ?', { amount, realCid })
    else
        MySQL.query('UPDATE tg_matchmaking SET xp = xp + ? WHERE citizenid = ?', { amount, realCid })
    end
    LogAction(src, 'MATCHMAKING_XP', ('%s %d XP for %s'):format(action == 'remove' and 'Removed' or 'Added', amount, realCid), realCid)
    NotifyPlayer(src, ('Matchmaking XP %s (%d).'):format(action == 'remove' and 'removed' or 'added', amount), 'success')
end)

RegisterNetEvent('vikto_admin:server:checkTruckPoints', function(cid)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Top3) then return end
    local realCid = ResolveStatsCid(cid)
    MySQL.query('SELECT score FROM tg_truck_stats WHERE citizenid = ?', { realCid }, function(rows)
        TriggerClientEvent('vikto_admin:client:truckPointsResult', src, realCid, rows and rows[1] and rows[1].score or 0)
    end)
end)

RegisterNetEvent('vikto_admin:server:adjustTruckPoints', function(cid, amount, action)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.Top3) then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return NotifyPlayer(src, 'Invalid amount.', 'error') end
    local realCid = ResolveStatsCid(cid)
    if action == 'remove' then
        MySQL.query('UPDATE tg_truck_stats SET score = GREATEST(0, score - ?) WHERE citizenid = ?', { amount, realCid })
    else
        MySQL.query('UPDATE tg_truck_stats SET score = score + ? WHERE citizenid = ?', { amount, realCid })
    end
    LogAction(src, 'TRUCK_POINTS', ('%s %d points for %s'):format(action == 'remove' and 'Removed' or 'Added', amount, realCid), realCid)
    NotifyPlayer(src, ('Truck points %s (%d).'):format(action == 'remove' and 'removed' or 'added', amount), 'success')
end)

-- =============================================
-- LOGGING EVENTS (Admin actions log)
-- =============================================
-- Gated so random players can't flood vikto_admin_history with fake entries.
RegisterNetEvent('vikto_admin:server:logGodMode', function(state) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'GODMODE', tostring(state)) end)
RegisterNetEvent('vikto_admin:server:logNoClip', function(state) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'NOCLIP', tostring(state)) end)
RegisterNetEvent('vikto_admin:server:logInvisible', function(state) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'INVISIBLE', tostring(state)) end)
RegisterNetEvent('vikto_admin:server:logFastRun', function(state) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'FASTRUN', tostring(state)) end)
RegisterNetEvent('vikto_admin:server:logSuperJump', function(state) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'SUPERJUMP', tostring(state)) end)
RegisterNetEvent('vikto_admin:server:logNames', function(state) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'NAMES', tostring(state)) end)
RegisterNetEvent('vikto_admin:server:logBlips', function(state) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'BLIPS', tostring(state)) end)
RegisterNetEvent('vikto_admin:server:logReviveSelf', function() if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'REVIVE_SELF', '') end)
RegisterNetEvent('vikto_admin:server:logTeleportWaypoint', function(coords) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'TP_WAYPOINT', tostring(coords)) end)
RegisterNetEvent('vikto_admin:server:logTeleportCoords', function(coords) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'TP_COORDS', tostring(coords)) end)
RegisterNetEvent('vikto_admin:server:logTeleportLocation', function(coords, name) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'TP_LOCATION', tostring(name or coords)) end)
RegisterNetEvent('vikto_admin:server:logFixVehicle', function(model, plate) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'FIX_VEHICLE', tostring(model) .. ' ' .. tostring(plate)) end)
RegisterNetEvent('vikto_admin:server:logDeleteVehicle', function(model, plate) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'DELETE_VEHICLE', tostring(model) .. ' ' .. tostring(plate)) end)
RegisterNetEvent('vikto_admin:server:logChangePlate', function(old, new, model) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'CHANGE_PLATE', tostring(old) .. ' -> ' .. tostring(new)) end)
RegisterNetEvent('vikto_admin:server:debugAction', function(title, event) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end LogAction(source, 'DEBUG', tostring(title) .. ': ' .. tostring(event)) end)

-- =============================================
-- MISC
-- =============================================
RegisterNetEvent('vikto_admin:server:syncPtfx', function() if not HasPermission(source, ConfigS.MinPermissionLevel) then return end TriggerClientEvent('vikto_admin:client:syncPtfx', -1, source) end)
RegisterNetEvent('vikto_admin:server:checkRadio', function(targetId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.AllStaff) then return end
    local target = ResolveAnyTargetSource(targetId)
    local channel = 0
    if target then
        -- pma-voice keeps the current radio channel in the player's state bag.
        local ok, ch = pcall(function() return Player(target).state.radioChannel end)
        if ok and tonumber(ch) then channel = tonumber(ch) end
    end
    TriggerClientEvent('vikto_admin:client:radioResult', src, targetId, channel)
end)
-- restorePlayer ("Sent Back [E]" after an admin sends you to spawn) used to be
-- completely open: ANY player could trigger it to teleport themselves to
-- arbitrary coordinates and switch their routing bucket. It is now only
-- honored for staff, or for players this resource just sent to spawn (a
-- short-lived server-side grant set by teleportPlayerToSpawn below).
RegisterNetEvent('vikto_admin:server:restorePlayer', function(coords, bucket)
    local src = source
    local grant = PendingRestore[src]
    local isStaff = HasPermission(src, ConfigS.MinPermissionLevel)
    if not isStaff and (not grant or (os.time() - grant) > 60) then
        PendingRestore[src] = nil
        return
    end
    PendingRestore[src] = nil
    TriggerClientEvent('vikto_admin:client:teleport', src, coords)
    if bucket then SetPlayerRoutingBucket(src, tonumber(bucket) or 0) end
end)
-- Delete-all-peds is a Developer Options action; it was triggerable by anyone.
RegisterNetEvent('vikto_admin:server:RequestDeleteAllPeds', function() if not PlayerHasAnyRoleName(source, PERM.Managers) then return end TriggerClientEvent('vikto_admin:client:deleteAllPeds', -1) end)
RegisterNetEvent('vikto_admin:server:getTxAdminPlayers', function(data) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end TriggerClientEvent('vikto_admin:client:txAdminPlayersResult', source, {}) end)
RegisterNetEvent('vikto_admin:server:testplayers_cmd', function(count) if not HasPermission(source, ConfigS.MinPermissionLevel) then return end NotifyPlayer(source, 'Test players: ' .. tostring(count), 'inform') end)
RegisterNetEvent('vikto_admin:server:testplayers_clear_cmd', function() if not HasPermission(source, ConfigS.MinPermissionLevel) then return end NotifyPlayer(source, 'Test players cleared', 'inform') end)

-- =============================================
-- CLEANUP
-- =============================================
AddEventHandler('playerDropped', function()
    AdminStates[source] = nil
    PendingRestore[source] = nil
end)

-- =============================================
-- QBCORE CALLBACKS (panel data)
-- =============================================
CreateThread(function()
    while GetResourceState('FL-Core') ~= 'started' do Wait(100) end
    local Core = exports['FL-Core']:GetCoreObject()
    if not Core or not Core.Functions or not Core.Functions.CreateCallback then
        print("^1[FL-Admin] FL-Core callback API unavailable — panel callbacks disabled!^7")
        return
    end

    -- Full online player list for the panel.
    Core.Functions.CreateCallback('vikto_admin:server:getPlayers', function(src, cb)
        if not HasPermission(src, ConfigS.MinPermissionLevel) then return cb({ players = {}, maxPlayers = 0 }) end
        local players = {}
        for _, playerId in ipairs(GetPlayers()) do
            local s = tonumber(playerId)
            players[#players + 1] = {
                id = s,
                serverId = s, -- the NUI player card / modal read `serverId`
                name = GetPlayerName(s) or 'Unknown',
                cid = GetCid(s),
                ping = GetPlayerPing(s),
            }
        end
        cb({ players = players, maxPlayers = GetConvarInt('sv_maxclients', 48) })
    end)

    -- Info about a single target (feeds the player modal).
    Core.Functions.CreateCallback('vikto_admin:server:getTargetInfo', function(src, cb, targetId)
        if not HasPermission(src, ConfigS.MinPermissionLevel) then return cb(nil) end
        local target = GetSourceByCid(targetId) or tonumber(targetId)
        if not target or not GetPlayerName(target) then return cb(nil) end
        cb({
            id = target,
            serverId = target,
            name = GetPlayerName(target) or 'Unknown',
            cid = GetCid(target),
            ping = GetPlayerPing(target),
            canAct = CanActOnTarget(src, target),
        })
    end)

    -- Categories the calling admin is allowed to see (filtered by role names).
    Core.Functions.CreateCallback('vikto_admin:server:getMenuCategories', function(src, cb)
        local allowed = {}
        for _, category in ipairs(Config.AdminMenuCategories or {}) do
            if PlayerHasAnyRoleName(src, category.permission) then
                local filtered = {
                    title = category.title,
                    icon = category.icon,
                    targetMenu = category.targetMenu,
                    permission = category.permission,
                    options = {},
                    items = {},
                }
                for _, opt in ipairs(category.options or category.items or {}) do
                    if not opt.permission or PlayerHasAnyRoleName(src, opt.permission) then
                        filtered.options[#filtered.options + 1] = opt
                    end
                end
                filtered.items = filtered.options
                allowed[#allowed + 1] = filtered
            end
        end

        local allowedModal = {}
        for _, category in ipairs(Config.PlayerModalActions or {}) do
            if PlayerHasAnyRoleName(src, category.permission) then
                local filteredCat = {
                    category = category.category,
                    permission = category.permission,
                    buttons = {}
                }
                for _, btn in ipairs(category.buttons or {}) do
                    if not btn.permission or PlayerHasAnyRoleName(src, btn.permission) then
                        filteredCat.buttons[#filteredCat.buttons + 1] = btn
                    end
                end
                if #filteredCat.buttons > 0 then
                    allowedModal[#allowedModal + 1] = filteredCat
                end
            end
        end

        cb(allowed, allowedModal)
    end)

    -- Self mute status.
    Core.Functions.CreateCallback('vikto_admin:server:getMuteStatus', function(src, cb)
        local rec = MutedPlayers[GetCid(src)] or MutedPlayers[tostring(src)]
        if rec and rec.until_time > os.time() then
            cb({ isMuted = true, remaining = rec.until_time - os.time(), reason = rec.reason })
        else
            cb({ isMuted = false })
        end
    end)

    -- Self jail status. Records are keyed by citizenid (survives relogs).
    Core.Functions.CreateCallback('vikto_admin:server:getJailStatus', function(src, cb)
        local cid = GetCid(src)
        local rec = cid and JailedPlayers[tostring(cid)] or nil
        if rec and rec.until_time > os.time() then
            cb({ isJailed = true, timeRemaining = rec.until_time - os.time(), reason = rec.reason, adminName = rec.adminName })
        else
            cb({ isJailed = false })
        end
    end)

    -- List of currently jailed players (records are cid-keyed; also shows offline ones).
    Core.Functions.CreateCallback('vikto_admin:server:getJailedPlayers', function(src, cb)
        if not PlayerHasAnyRoleName(src, PERM.Unjail) then return cb({}) end
        local list = {}
        for cid, rec in pairs(JailedPlayers) do
            if rec.until_time > os.time() then
                local s = GetSourceByCid(cid)
                local name = s and GetPlayerName(s) or 'Offline'
                local remaining = math.floor((rec.until_time - os.time()) / 60)
                list[#list + 1] = {
                    serverId = s or cid,
                    cid = cid,
                    label = ('[%s] %s — %dm left'):format(tostring(s or cid), name, remaining),
                }
            end
        end
        cb(list)
    end)

    -- Spawn a vehicle at the admin's position.
    Core.Functions.CreateCallback('vikto_admin:server:spawnVehicle', function(src, cb, model)
        if not PlayerHasAnyRoleName(src, PERM.Vehicles) then return cb(false) end
        if not model then return cb(false) end

        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return cb(false) end
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)

        local hash = type(model) == 'number' and model or GetHashKey(model)
        local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, true)
        if not veh or veh == 0 then return cb(false) end

        local tries = 0
        while not DoesEntityExist(veh) and tries < 50 do Wait(10) tries = tries + 1 end
        if not DoesEntityExist(veh) then return cb(false) end

        SetVehicleNumberPlateText(veh, 'ADMIN' .. math.random(100, 999))
        SetPedIntoVehicle(ped, veh, -1)
        LogAction(src, 'SPAWN_VEHICLE', tostring(model))
        cb(true)
    end)
end)

-- =============================================
-- PLAYER /report SYSTEM
-- The Accept/Reject UI already existed client-side but had NO backend:
-- no /report command created reports and 'adminreport:server:HideReport'
-- had no handler. This wires the whole flow.
-- =============================================
local ActiveReports = {}  -- [reportId] = { reporter, name, coords, at }
local ReportCooldown = {} -- [src] = os.time of last report
local nextReportId = 0

local function ForEachStaff(fn)
    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        if s and PlayerHasAnyRoleName(s, PERM.AllStaff) then fn(s) end
    end
end

RegisterCommand('report', function(source, args)
    local src = source
    if src == 0 then return end

    local cdTime = (Config.Report and Config.Report.Cooldown and Config.Report.Cooldown.Time) or 60
    local last = ReportCooldown[src] or 0
    if os.time() - last < cdTime then
        return NotifyPlayer(src, ('Please wait %d seconds before reporting again.'):format(cdTime - (os.time() - last)), 'error')
    end

    local message = table.concat(args or {}, ' ')
    if message == '' then
        return NotifyPlayer(src, (Config.Report and Config.Report.Messages and Config.Report.Messages.noMessage) or 'You must enter a message for the report.', 'error')
    end

    ReportCooldown[src] = os.time()
    nextReportId = nextReportId + 1
    local reportId = nextReportId
    local ped = GetPlayerPed(src)
    local coords = ped and ped ~= 0 and GetEntityCoords(ped) or nil
    local name = GetPlayerName(src) or ('Player ' .. src)

    ActiveReports[reportId] = {
        reporter = src,
        name = name,
        message = message,
        coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
        at = os.time(),
    }

    local autoHide = (Config.Report and Config.Report.AutoHide and Config.Report.AutoHide.Time) or 60
    ForEachStaff(function(s)
        TriggerClientEvent('adminreport:server:ShowReport', s, reportId, src, name, autoHide)
        NotifyPlayer(s, ('Report #%d from %s: %s'):format(reportId, name, message), 'inform')
        TriggerClientEvent('vikto_admin:client:playMentionSound', s)
    end)

    NotifyPlayer(src, (Config.Report and Config.Report.Messages and Config.Report.Messages.reportSent) or 'Your report has been sent to the admins.', 'success')
    LogAction(src, 'REPORT_CREATED', message, GetCid(src))

    -- Auto-expire
    SetTimeout(autoHide * 1000, function()
        if ActiveReports[reportId] then
            ActiveReports[reportId] = nil
            ForEachStaff(function(s)
                TriggerClientEvent('adminreport:client:HideReport', s, reportId)
            end)
        end
    end)
end, false)

RegisterNetEvent('adminreport:server:HideReport', function(action, reportId)
    local src = source
    if not PlayerHasAnyRoleName(src, PERM.AllStaff) then return end
    reportId = tonumber(reportId)
    local report = reportId and ActiveReports[reportId]
    if not report then return end
    ActiveReports[reportId] = nil

    ForEachStaff(function(s)
        TriggerClientEvent('adminreport:client:HideReport', s, reportId)
    end)

    if action == 'Accept' then
        -- Staff report-points for handling it
        local perAccept = (Config.Report and Config.Report.ReportsSystem and Config.Report.ReportsSystem.ReportsPerAccept) or 1
        local adminCid = GetCid(src)
        if adminCid then
            ReportsData[tostring(adminCid)] = (ReportsData[tostring(adminCid)] or 0) + perAccept
        end
        -- Teleport the admin to the reporter + effect
        if report.coords then
            TriggerClientEvent('adminreport:client:TeleportToCoords', src, report.coords)
            TriggerClientEvent('adminreport:client:MakeEffect', src, report.coords)
        end
        if GetPlayerName(report.reporter) then
            NotifyPlayer(report.reporter, 'An admin accepted your report and is on the way.', 'success')
        end
        LogAction(src, 'REPORT_ACCEPT', ('Report #%d from %s'):format(reportId, report.name), adminCid)
    else
        if GetPlayerName(report.reporter) then
            NotifyPlayer(report.reporter, 'Your report was reviewed and closed.', 'inform')
        end
        LogAction(src, 'REPORT_REJECT', ('Report #%d from %s'):format(reportId, report.name))
    end
end)

AddEventHandler('playerDropped', function()
    ReportCooldown[source] = nil
end)

AddEventHandler('FL-Core:Server:CidMigrated', function(source, oldCid, newCid)
    if JailedPlayers[oldCid] then
        JailedPlayers[newCid] = JailedPlayers[oldCid]
        JailedPlayers[oldCid] = nil
    end
    MySQL.update('UPDATE vikto_admin_jails SET citizenid = ? WHERE citizenid = ?', { newCid, oldCid })
    MySQL.update('UPDATE vikto_admin_bans SET citizenid = ? WHERE citizenid = ?', { newCid, oldCid })
    MySQL.update('UPDATE vikto_admin_history SET citizenid = ? WHERE citizenid = ?', { newCid, oldCid })
end)

print("^2[FL-Admin] Server-side loaded successfully!^7")