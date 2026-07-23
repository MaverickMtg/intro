-- Test harness: loads the REAL FL-Admin config + server code under stubbed
-- FiveM natives and verifies:
--   1) only admins can open the panel / use server events
--   2) the menu is tiered (FullPermissions > managers > staff > mods)
--   3) lower staff cannot act on manager-tier players (CanActOnTarget)
--   4) the player-modal status payload carries source/serverId so the
--      disableOffline buttons stay ENABLED for online targets
--
-- Run from the FL-Admin folder:  lua5.4 tests/fl_admin_harness.lua

-- ---------------- json stub ----------------
-- Server code only json.decode()s Discord member payloads and staff-data KVP.
-- Our PerformHttpRequest stub passes the discord id as the "body", and decode
-- turns it into the member->roles table for that id.
local DISCORD_MEMBER_ROLES = {} -- [discordId] = { roleId, roleId, ... }
json = {
    encode = function() return '{}' end,
    decode = function(body)
        if DISCORD_MEMBER_ROLES[body] then return { roles = DISCORD_MEMBER_ROLES[body] } end
        return {}
    end,
}

-- ---------------- promise / Citizen ----------------
promise = { new = function() return { resolve = function(self, v) self.v = v end } end }
Citizen = { Await = function(p) return p.v end }

-- ---------------- misc natives ----------------
function GetCurrentResourceName() return 'FL-Admin' end
function GetResourceKvpString() return nil end
function SetResourceKvp() end
function GetConvar(name, def)
    if name == 'tg_admin_bot_token' then return 'TEST_TOKEN' end
    if name == 'tg_admin_guild_id' then return '42' end
    return def
end
function GetConvarInt(_, def) return def end
function GetHashKey(s) return 0 end
function RegisterCommand() end
function SetTimeout() end
function vector3(x, y, z) return { x = x, y = y, z = z } end
function vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end

-- threads: run in coroutines; Wait() parks them (never resumed again)
Wait = coroutine.yield
function CreateThread(fn)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co)
    if not ok then error('thread failed: ' .. tostring(err)) end
end

function PerformHttpRequest(url, cb)
    local discordId = url:match('/members/(%d+)$')
    if discordId and DISCORD_MEMBER_ROLES[discordId] then
        cb(200, discordId)
    else
        cb(404, nil)
    end
end

-- ---------------- players ----------------
local players = {} -- [src] = { name=, discord=, ace=false }
function GetPlayers()
    local t = {}
    for s in pairs(players) do t[#t + 1] = tostring(s) end
    table.sort(t)
    return t
end
function GetPlayerName(src)
    src = tonumber(src)
    return players[src] and players[src].name or nil
end
local function identsOf(src)
    local p = players[src]
    if not p then return {} end
    local ids = { 'license:aaaa' .. src }
    if p.discord then ids[#ids + 1] = 'discord:' .. p.discord end
    return ids
end
function GetNumPlayerIdentifiers(src) return #identsOf(tonumber(src)) end
function GetPlayerIdentifier(src, i) return identsOf(tonumber(src))[i + 1] end
function GetPlayerPing() return 50 end
function GetPlayerPed() return 0 end
function GetEntityCoords() return vector3(0, 0, 0) end
function GetEntityHeading() return 0.0 end
function SetEntityHealth() end
function IsPlayerAceAllowed() return false end
function Player(src) return { state = {} } end

local droppedPlayers = {}
function DropPlayer(src, reason) droppedPlayers[tonumber(src)] = reason end

local routingBuckets = {}
function SetPlayerRoutingBucket(src, b) routingBuckets[tonumber(src)] = b end

-- ---------------- event system ----------------
local netHandlers = {}
function RegisterNetEvent(name, fn) if fn then netHandlers[name] = netHandlers[name] or {}; table.insert(netHandlers[name], fn) end end
function AddEventHandler(name, fn) netHandlers[name] = netHandlers[name] or {}; table.insert(netHandlers[name], fn) end
source = 0
local function triggerFrom(src, name, ...)
    assert(netHandlers[name], 'no handler for ' .. name)
    source = src
    for _, fn in ipairs(netHandlers[name]) do fn(...) end
    source = 0
end

local clientEvents = {} -- captured TriggerClientEvent calls
function TriggerClientEvent(name, target, ...)
    clientEvents[#clientEvents + 1] = { name = name, target = target, args = { ... } }
end
local function lastClientEvent(name, target)
    for i = #clientEvents, 1, -1 do
        local e = clientEvents[i]
        if e.name == name and (target == nil or e.target == target) then return e end
    end
    return nil
end
local function clearCaptures()
    clientEvents = {}
    droppedPlayers = {}
    routingBuckets = {}
    sqlInserts = {}
end
local function countBanRows()
    local n = 0
    for _, ins in ipairs(sqlInserts) do
        if ins.q:find('vikto_admin_bans') then n = n + 1 end
    end
    return n
end

-- ---------------- MySQL stub ----------------
sqlInserts = {}
MySQL = {
    ready = function(fn) fn() end,
    query = function(q, params, cb) if type(params) == 'function' then params({}) elseif cb then cb({}) end end,
    scalar = function(q, params, cb) if cb then cb(0) end end,
    insert = function(q, params) sqlInserts[#sqlInserts + 1] = { q = q, params = params } end,
    update = function() end,
}

-- ---------------- exports / FL-Core ----------------
local coreCallbacks = {}
local resourceStates = { ['FL-Core'] = 'started' }
function GetResourceState(name) return resourceStates[name] or 'missing' end
exports = setmetatable({}, {
    __index = function(_, resName)
        return setmetatable({}, { __index = function(_, fnName)
            if fnName == 'GetCoreObject' then
                return function()
                    return { Functions = { CreateCallback = function(_, name, fn)
                        -- called as Core.Functions.CreateCallback(name, fn)
                    end } }
                end
            end
            return function() end
        end })
    end,
    __call = function() end,
})
-- exports('name', fn) style used by the resource itself:
local exportedFns = {}
setmetatable(exports, {
    __index = function(_, resName)
        -- resource code calls these with ':' so the first arg is self
        return {
            GetCoreObject = function(_)
                return { Functions = { CreateCallback = function(name, fn) coreCallbacks[name] = fn end } }
            end,
            GetPlayer = function(_, src)
                src = tonumber(src)
                if players[src] then return { PlayerData = { citizenid = 'CID' .. src } } end
                return nil
            end,
            SendToSpawn = function(_, _) end,
        }
    end,
    __call = function(_, name, fn) exportedFns[name] = fn end,
})

-- ================= load the REAL resource files =================
dofile('Config.lua')
dofile('ConfigS.lua')
dofile('Files/Server.lua')

-- ================= scenario setup =================
-- Real Discord role ids straight from Config.DiscordRoles:
local ROLE_OWNER          = '1479653715073044572' -- FullPermissions
local ROLE_SERVER_MANAGER = '1454410421481246720' -- ServerManager
local ROLE_ADMIN          = '1333448430902579360' -- Admin
local ROLE_MOD            = '1476351128273948785' -- Mod
local ROLE_SUPPORT        = '1333448478277505108' -- Support + MuteChat/MuteVoice/Spectate

players[1] = { name = 'Owner',         discord = '101' }
players[2] = { name = 'ServerManager', discord = '102' }
players[3] = { name = 'NormalAdmin',   discord = '103' }
players[4] = { name = 'Moderator',     discord = '104' }
players[5] = { name = 'RandomPlayer',  discord = '105' }
players[6] = { name = 'SupportGuy',    discord = '106' }
DISCORD_MEMBER_ROLES['101'] = { ROLE_OWNER }
DISCORD_MEMBER_ROLES['102'] = { ROLE_SERVER_MANAGER }
DISCORD_MEMBER_ROLES['103'] = { ROLE_ADMIN }
DISCORD_MEMBER_ROLES['104'] = { ROLE_MOD }
DISCORD_MEMBER_ROLES['105'] = {}
DISCORD_MEMBER_ROLES['106'] = { ROLE_SUPPORT }

-- ================= assertions =================
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 print(('PASS  %s'):format(label))
    else failed = failed + 1 print(('FAIL  %s'):format(label)) end
end

print('\n--- 1) Only admins can open the panel ---')
clearCaptures()
triggerFrom(5, 'vikto_admin:server:checkPermission', 'players')
check(lastClientEvent('vikto_admin:client:openPanel', 5) == nil, 'random player: panel does NOT open')
local deny = lastClientEvent('QBCore:Notify', 5)
check(deny and deny.args[1] == 'You do not have permission!', 'random player: gets permission-denied notify')

clearCaptures()
triggerFrom(1, 'vikto_admin:server:checkPermission', 'players')
local open = lastClientEvent('vikto_admin:client:openPanel', 1)
check(open ~= nil, 'FullPermissions admin: panel opens')
check(open and open.args[1] and open.args[1][1] and open.args[1][1].serverId ~= nil,
    'player list entries now include serverId (modal online detection)')

clearCaptures()
triggerFrom(4, 'vikto_admin:server:checkPermission', 'players')
check(lastClientEvent('vikto_admin:client:openPanel', 4) ~= nil, 'Moderator (staff tier): panel opens')

print('\n--- 2) Modal status payload fix (greyed-out buttons) ---')
clearCaptures()
triggerFrom(1, 'vikto_admin:server:fetchPlayerDetail', 5, 'status')
local st = lastClientEvent('vikto_admin:client:playerDetailUpdate', 1)
check(st ~= nil, 'status payload delivered to admin')
local data = st and st.args[2]
check(data and data.source == 5, 'status payload contains source = online server id (fix)')
check(data and data.serverId == 5, 'status payload contains serverId (fix)')
check(data and data.citizenid == 'CID5', 'status payload contains citizenid (fix)')

clearCaptures()
triggerFrom(5, 'vikto_admin:server:fetchPlayerDetail', 1, 'status')
check(lastClientEvent('vikto_admin:client:playerDetailUpdate', 5) == nil,
    'random player can NOT fetch player details (new gate)')

print('\n--- 3) Tier hierarchy: normal admin cannot touch managers ---')
clearCaptures()
triggerFrom(3, 'vikto_admin:server:kickPlayer', 2, 'test')
check(droppedPlayers[2] == nil, 'NormalAdmin kick ServerManager: BLOCKED')
local msg = lastClientEvent('QBCore:Notify', 3)
check(msg and tostring(msg.args[1]):find('equal or higher rank') ~= nil,
    'NormalAdmin gets "equal or higher rank" notify')

clearCaptures()
triggerFrom(2, 'vikto_admin:server:kickPlayer', 4, 'test')
check(droppedPlayers[4] ~= nil, 'ServerManager kick Moderator: allowed')
players[4] = { name = 'Moderator', discord = '104' } -- reconnect for later tests

clearCaptures()
triggerFrom(3, 'vikto_admin:server:kickPlayer', 1, 'test')
check(droppedPlayers[1] == nil, 'NormalAdmin kick FullPermissions owner: BLOCKED')

-- Ban is limited to the manager/ban-team list, NOT normal Admin
clearCaptures()
triggerFrom(3, 'vikto_admin:server:banPlayer', 'CID4', 'test', 1)
check(countBanRows() == 0 and droppedPlayers[4] == nil, 'NormalAdmin ban: BLOCKED (not in ban tier)')
clearCaptures()
triggerFrom(2, 'vikto_admin:server:banPlayer', 'CID4', 'test', 1)
check(countBanRows() == 1, 'ServerManager ban: allowed (writes ban row)')
players[4] = { name = 'Moderator', discord = '104' } -- reconnect

print('\n--- 4) Tier hierarchy on give item / CID / delete-all-peds ---')
clearCaptures()
triggerFrom(3, 'vikto_admin:server:giveItem', 4, 'weapon_pistol', 1)
check(lastClientEvent('QBCore:Notify', 3) == nil, 'NormalAdmin give item: BLOCKED (top-manager only)')
clearCaptures()
triggerFrom(1, 'vikto_admin:server:giveItem', 4, 'weapon_pistol', 1)
local gi = lastClientEvent('QBCore:Notify', 1)
check(gi and gi.args[1] == 'Item given!', 'FullPermissions give item: allowed')

clearCaptures()
triggerFrom(2, 'Vikto:Admin:Server:DeleteCID', 'CID4')
check(lastClientEvent('QBCore:Notify', 2) == nil, 'ServerManager delete CID: BLOCKED (FullPermissions only)')
clearCaptures()
triggerFrom(1, 'Vikto:Admin:Server:DeleteCID', 'CID4')
local dc = lastClientEvent('QBCore:Notify', 1)
check(dc and dc.args[1] == 'CID deleted!', 'FullPermissions delete CID: allowed')

clearCaptures()
triggerFrom(5, 'vikto_admin:server:RequestDeleteAllPeds')
check(lastClientEvent('vikto_admin:client:deleteAllPeds') == nil, 'random player delete-all-peds: BLOCKED')
clearCaptures()
triggerFrom(3, 'vikto_admin:server:RequestDeleteAllPeds')
check(lastClientEvent('vikto_admin:client:deleteAllPeds') ~= nil, 'manager-tier delete-all-peds: allowed')

print('\n--- 5) Feature-role tiers (Support can mute, cannot kick) ---')
clearCaptures()
triggerFrom(6, 'vikto_admin:server:mutePlayer', 5, 10, 'toxic')
local mu = lastClientEvent('QBCore:Notify', 6)
check(mu and mu.args[1] == 'Player voice muted!', 'Support (MuteVoice role): mute allowed')
clearCaptures()
triggerFrom(6, 'vikto_admin:server:kickPlayer', 5, 'test')
check(droppedPlayers[5] == nil, 'Support: kick BLOCKED (managers only)')

print('\n--- 6) Staff points / hours exploit closed ---')
clearCaptures()
triggerFrom(5, 'vikto_admin:server:addPoints', 'CID5', 999)
check(lastClientEvent('QBCore:Notify', 5) == nil, 'random player self-award points: BLOCKED')
clearCaptures()
triggerFrom(5, 'vikto_admin:server:addHours', 'CID5', 999)
check(lastClientEvent('QBCore:Notify', 5) == nil, 'random player self-award hours: BLOCKED')

print('\n--- 7) restorePlayer teleport exploit closed ---')
clearCaptures()
triggerFrom(5, 'vikto_admin:server:restorePlayer', vector3(999, 999, 50), 7)
check(lastClientEvent('vikto_admin:client:teleport', 5) == nil and routingBuckets[5] == nil,
    'random player arbitrary teleport/bucket: BLOCKED')
-- but after an admin sends them to spawn, the one-shot restore grant works:
clearCaptures()
triggerFrom(1, 'vikto_admin:server:teleportPlayerToSpawn', 5)
triggerFrom(5, 'vikto_admin:server:restorePlayer', vector3(10, 10, 10), nil)
check(lastClientEvent('vikto_admin:client:teleport', 5) ~= nil, 'sent-to-spawn player: one-shot restore works')
clearCaptures()
triggerFrom(5, 'vikto_admin:server:restorePlayer', vector3(999, 999, 50), 7)
check(lastClientEvent('vikto_admin:client:teleport', 5) == nil, 'restore grant is single-use')

print('\n--- 8) Menu category tiers (getMenuCategories) ---')
local function menuTitlesFor(src)
    local titles = {}
    assert(coreCallbacks['vikto_admin:server:getMenuCategories'], 'getMenuCategories callback registered')
    source = src
    coreCallbacks['vikto_admin:server:getMenuCategories'](src, function(allowed)
        for _, cat in ipairs(allowed or {}) do titles[cat.title] = #cat.options end
    end)
    source = 0
    return titles
end
local ownerMenu = menuTitlesFor(1)
local adminMenu = menuTitlesFor(3)
local modMenu   = menuTitlesFor(4)
local randMenu  = menuTitlesFor(5)
check(ownerMenu['CID Management'] ~= nil, 'FullPermissions sees CID Management category')
check(adminMenu['CID Management'] == nil, 'Normal Admin does NOT see CID Management')
check(adminMenu['Scripts Points'] == nil, 'Normal Admin does NOT see Scripts Points (top managers only)')
check(adminMenu['Developer Options'] ~= nil, 'Normal Admin sees Developer Options (manager tier)')
check(modMenu['Developer Options'] == nil, 'Moderator does NOT see Developer Options')
check(modMenu['Player Management'] ~= nil and modMenu['Player Management'] < ownerMenu['Player Management'],
    'Moderator sees fewer Player Management options than FullPermissions')
check(next(randMenu) == nil, 'random player gets an EMPTY menu (cannot open)')

print('\n--- 9) Permission levels sanity (tier ladder) ---')
check(ConfigS.PermissionLevels['ServerManager'] == 95 and ConfigS.PermissionLevels['ServerManager'] > ConfigS.PermissionLevels['Admin'],
    'ServerManager level exists and outranks normal Admin')
check(ConfigS.PermissionLevels['HighManager'] and ConfigS.PermissionLevels['GeneralManager'] and ConfigS.PermissionLevels['BanTeam'],
    'all manager/team roles from Config.DiscordRoles have levels now')
local missing = {}
local function collect(v) if type(v) == 'table' then for _, n in ipairs(v) do if not ConfigS.PermissionLevels[n] then missing[#missing + 1] = n end end elseif not ConfigS.PermissionLevels[v] then missing[#missing + 1] = v end end
for _, permName in pairs(Config.DiscordRoles) do collect(permName) end
check(#missing == 0, 'every role in Config.DiscordRoles resolves to a level (missing: ' .. table.concat(missing, ',') .. ')')

print(('\n================ RESULTS: %d passed, %d failed ================'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
