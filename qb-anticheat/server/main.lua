-- ==========================================================================
--  qb-anticheat :: server core
--  Server-authoritative detections. Everything here runs on the server and
--  cannot be patched out by a client-side injection.
-- ==========================================================================

AC = AC or {}

local QBCore = exports['qb-core']:GetCoreObject()

-- Per-player runtime state
local State = {}         -- src -> { flags = {}, connectTime =, lastPos =, lastPosTime =, lastBeat = }
-- Rate counters
local explosionCount = {} -- src -> { count, resetAt }
local entityCount = {}    -- owner src -> { veh, ped, obj, resetAt }
local eventCount = {}      -- src -> { [event] = { count, resetAt } }
local reportCount = {}     -- src -> { count, resetAt }  (anti-spam on client reports)

-- ==========================================================================
--  Helpers
-- ==========================================================================

local function dbg(msg)
    if Config.Debug then print('[qb-anticheat] ' .. msg) end
end

local function ensureState(src)
    if not State[src] then
        State[src] = {
            flags = {},
            connectTime = os.clock() * 1000,
            lastBeat = GetGameTimer(),
        }
    end
    return State[src]
end

function AC.IsAdmin(src)
    if not Config.AdminBypass then return false end
    if Config.AdminAce ~= '' and IsPlayerAceAllowed(src, Config.AdminAce) then
        return true
    end
    if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
        for _, perm in ipairs(Config.AdminPermissions) do
            if QBCore.Functions.HasPermission(src, perm) then
                return true
            end
        end
    end
    return false
end

-- Append a JSON line to the flat log file (permanent audit trail).
local function fileLog(entry)
    local existing = LoadResourceFile(GetCurrentResourceName(), Config.LogFile) or ''
    existing = existing .. json.encode(entry) .. '\n'
    SaveResourceFile(GetCurrentResourceName(), Config.LogFile, existing, -1)
end

-- Map category -> webhook channel key.
local WEBHOOK_CHANNEL = {
    explosionSpam = 'explosions',
    entitySpam = 'entities',
    blacklistEntity = 'entities',
    weaponExploit = 'weapons',
    eventFlood = 'events',
    teleport = 'movement',
    godMode = 'movement',
    noclip = 'movement',
    invisible = 'movement',
    tamper = 'tamper',
}

--- Central detection handler. Records, webhooks and punishes.
-- @param src number
-- @param category string  (key in Config.Actions)
-- @param detail string    human readable detail
function AC.Flag(src, category, detail)
    if not GetPlayerName(src) then return end -- player already gone
    local st = ensureState(src)
    st.flags[category] = (st.flags[category] or 0) + 1

    local isAdmin = AC.IsAdmin(src)
    local action = Config.Actions[category] or 'log'
    local name = GetPlayerName(src)
    local flagCount = st.flags[category]

    -- Escalate kicks to bans after repeated offences.
    if action == 'kick' then
        local threshold = Config.MaxFlagsBeforeBan[category]
        if threshold and flagCount >= threshold then
            action = 'ban'
        end
    end

    dbg(('FLAG %s [%s] %s (x%d, admin=%s, action=%s)'):format(name, category, detail, flagCount, tostring(isAdmin), action))

    -- File log (always)
    fileLog({
        time = os.date('%Y-%m-%d %H:%M:%S'),
        player = name,
        src = src,
        license = (function()
            for _, id in ipairs(AC.GetIdentifiers(src)) do
                if id:sub(1, 8) == 'license:' then return id end
            end
            return 'unknown'
        end)(),
        category = category,
        detail = detail,
        count = flagCount,
        admin = isAdmin,
        action = (isAdmin and 'log(admin-bypass)') or action,
    })

    -- Webhook
    local severity = (action == 'ban' and 'ban') or (action == 'kick' and 'warn') or 'info'
    local fields = {
        { name = 'Player', value = ('%s (id %d)'):format(name, src), inline = true },
        { name = 'Category', value = category, inline = true },
        { name = 'Count', value = tostring(flagCount), inline = true },
        { name = 'Detail', value = detail ~= '' and detail or 'n/a', inline = false },
        { name = 'Action', value = (isAdmin and '`log only (admin bypass)`') or ('`' .. action .. '`'), inline = true },
    }
    AC.SendWebhook(WEBHOOK_CHANNEL[category] or 'default',
        ('Detection: %s'):format(category), nil, fields, severity)

    if isAdmin then return end -- never punish admins

    local reason = ('%s (%s)'):format(category, detail)
    if action == 'ban' then
        local banId = AC.AddBan(src, reason, category, detail)
        AC.SendWebhook('bans', 'Player banned',
            ('**%s** was banned.'):format(name),
            { { name = 'Ban ID', value = banId, inline = true },
              { name = 'Reason', value = reason, inline = false } }, 'ban')
    elseif action == 'kick' then
        DropPlayer(src, Config.KickMessage:format(Config.ServerName, reason))
    end
end

-- ==========================================================================
--  EXPLOSION PROTECTION
-- ==========================================================================
if Config.Explosions.enable then
    AddEventHandler('explosionEvent', function(sender, ev)
        local src = tonumber(sender)
        if not src or not GetPlayerName(src) then return end

        local etype = ev.explosionType
        if Config.Explosions.blacklist[etype] then
            CancelEvent()
            AC.Flag(src, 'explosionSpam', ('blacklisted explosion type %s'):format(tostring(etype)))
            return
        end

        local now = GetGameTimer()
        local c = explosionCount[src]
        if not c or now >= c.resetAt then
            c = { count = 0, resetAt = now + Config.Explosions.interval }
            explosionCount[src] = c
        end
        c.count = c.count + 1
        if c.count > Config.Explosions.maxPerInterval then
            CancelEvent()
            AC.Flag(src, 'explosionSpam', ('%d explosions in %dms'):format(c.count, Config.Explosions.interval))
        end
    end)
end

-- ==========================================================================
--  ENTITY SPAWN PROTECTION
-- ==========================================================================
if Config.EntitySpawn.enable then
    -- Cancel blacklisted models as early as possible.
    AddEventHandler('entityCreating', function(entity)
        local model = GetEntityModel(entity)
        if Config.EntitySpawn.blacklistedModels[model] then
            CancelEvent()
        end
    end)

    AddEventHandler('entityCreated', function(entity)
        if not DoesEntityExist(entity) then return end
        local etype = GetEntityType(entity) -- 1 ped, 2 vehicle, 3 object
        if etype == 0 then return end

        local owner = NetworkGetEntityOwner(entity)
        if not owner or owner < 0 or not GetPlayerName(owner) then return end

        local model = GetEntityModel(entity)
        if Config.EntitySpawn.blacklistedModels[model] then
            DeleteEntity(entity)
            AC.Flag(owner, 'blacklistEntity', ('spawned blacklisted model %s'):format(tostring(model)))
            return
        end

        local now = GetGameTimer()
        local c = entityCount[owner]
        if not c or now >= c.resetAt then
            c = { veh = 0, ped = 0, obj = 0, resetAt = now + Config.EntitySpawn.interval, burst = {} }
            entityCount[owner] = c
        end

        local overLimit = false
        if etype == 2 then
            c.veh = c.veh + 1
            overLimit = c.veh > Config.EntitySpawn.maxVehiclesPerInterval
        elseif etype == 1 then
            c.ped = c.ped + 1
            overLimit = c.ped > Config.EntitySpawn.maxPedsPerInterval
        elseif etype == 3 then
            c.obj = c.obj + 1
            overLimit = c.obj > Config.EntitySpawn.maxObjectsPerInterval
        end

        c.burst[#c.burst + 1] = entity
        if overLimit then
            if Config.EntitySpawn.deleteOnFlag then
                for _, ent in ipairs(c.burst) do
                    if DoesEntityExist(ent) then DeleteEntity(ent) end
                end
                c.burst = {}
            end
            AC.Flag(owner, 'entitySpam', ('entity flood v:%d p:%d o:%d in %dms'):format(c.veh, c.ped, c.obj, Config.EntitySpawn.interval))
        end
    end)
end

-- ==========================================================================
--  WEAPON DAMAGE PROTECTION
-- ==========================================================================
if Config.WeaponDamage.enable then
    AddEventHandler('weaponDamageEvent', function(sender, data)
        local src = tonumber(sender)
        if not src or not GetPlayerName(src) then return end

        local weapon = data.weaponType
        if Config.WeaponDamage.blacklistedWeapons[weapon] then
            CancelEvent()
            AC.Flag(src, 'weaponExploit', ('blacklisted weapon %s'):format(tostring(weapon)))
            return
        end

        -- Damage override (super punch / damage modifier).
        if data.overrideDefaultDamage and data.weaponDamage then
            if data.weaponDamage > Config.WeaponDamage.maxDamage then
                CancelEvent()
                AC.Flag(src, 'weaponExploit', ('damage override %.0f'):format(data.weaponDamage))
                return
            end
        end

        -- Unarmed doing real damage.
        if Config.WeaponDamage.guardUnarmed and weapon == `WEAPON_UNARMED` then
            if data.weaponDamage and data.weaponDamage > Config.WeaponDamage.unarmedMaxDamage then
                CancelEvent()
                AC.Flag(src, 'weaponExploit', ('unarmed damage %.0f'):format(data.weaponDamage))
            end
        end
    end)
end

-- ==========================================================================
--  PROTECTED EVENT FLOOD GUARD
-- ==========================================================================
if Config.EventFlood.enable then
    for eventName, limit in pairs(Config.EventFlood.events) do
        -- Make sure the event can be received from clients even if the owning
        -- resource has not started yet; registering twice is harmless.
        RegisterNetEvent(eventName)
        AddEventHandler(eventName, function()
            local src = source
            if src == 0 or not GetPlayerName(src) then return end -- server-triggered

            local now = GetGameTimer()
            eventCount[src] = eventCount[src] or {}
            local c = eventCount[src][eventName]
            if not c or now >= c.resetAt then
                c = { count = 0, resetAt = now + limit.interval }
                eventCount[src][eventName] = c
            end
            c.count = c.count + 1
            if c.count > limit.max then
                AC.Flag(src, 'eventFlood', ('%s x%d in %dms'):format(eventName, c.count, limit.interval))
            end
        end)
    end
end

-- ==========================================================================
--  MOVEMENT / TELEPORT DETECTION
-- ==========================================================================
if Config.Movement.enable then
    CreateThread(function()
        while true do
            Wait(Config.Movement.checkInterval)
            local now = GetGameTimer()
            for _, src in ipairs(GetPlayers()) do
                src = tonumber(src)
                local st = ensureState(src)
                local ped = GetPlayerPed(src)
                if ped and ped ~= 0 and DoesEntityExist(ped) then
                    local px, py, pz = table.unpack(GetEntityCoords(ped))
                    if st.lastPos and (now - st.connectTime) > Config.Movement.graceMs then
                        local dx, dy, dz = px - st.lastPos[1], py - st.lastPos[2], pz - st.lastPos[3]
                        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                        local dt = (now - st.lastPosTime) / 1000.0
                        if dt > 0 then
                            local speed = dist / dt
                            local inVeh = GetVehiclePedIsIn(ped, false) ~= 0
                            if speed > Config.Movement.maxSpeed and not inVeh then
                                AC.Flag(src, 'teleport', ('moved %.0fm in %.1fs (%.0f m/s)'):format(dist, dt, speed))
                            end
                        end
                    end
                    st.lastPos = { px, py, pz }
                    st.lastPosTime = now
                end
            end
        end
    end)
end

-- ==========================================================================
--  HEARTBEAT / TAMPER DETECTION
-- ==========================================================================
if Config.Heartbeat.enable then
    RegisterNetEvent('qb-anticheat:server:heartbeat', function()
        local src = source
        local st = ensureState(src)
        st.lastBeat = GetGameTimer()
        st.beatSeen = true
    end)

    CreateThread(function()
        while true do
            Wait(Config.Heartbeat.serverTimeout)
            local now = GetGameTimer()
            for _, src in ipairs(GetPlayers()) do
                src = tonumber(src)
                local st = ensureState(src)
                local connectedFor = now - (st.joinTick or now)
                if connectedFor > Config.Heartbeat.graceMs then
                    if (now - (st.lastBeat or 0)) > Config.Heartbeat.serverTimeout then
                        AC.Flag(src, 'tamper', 'client heartbeat lost (anti-cheat stopped/frozen)')
                        st.lastBeat = now -- avoid immediate re-flag loop
                    end
                end
            end
        end
    end)
end

-- ==========================================================================
--  CLIENT-REPORTED DETECTIONS (best-effort layer)
--  A client can only report ITSELF (uses `source`), so a spoofed report only
--  harms the sender. We still rate-limit to stop webhook spam.
-- ==========================================================================
local ALLOWED_CLIENT_CATEGORIES = {
    godMode = true, noclip = true, invisible = true,
}

RegisterNetEvent('qb-anticheat:server:report', function(category, detail)
    local src = source
    if not ALLOWED_CLIENT_CATEGORIES[category] then return end

    local now = GetGameTimer()
    local rc = reportCount[src]
    if not rc or now >= rc.resetAt then
        rc = { count = 0, resetAt = now + 10000 }
        reportCount[src] = rc
    end
    rc.count = rc.count + 1
    if rc.count > 20 then return end -- ignore obvious report spam

    AC.Flag(src, category, tostring(detail or 'client report'))
end)

-- ==========================================================================
--  LIFECYCLE / CLEANUP
-- ==========================================================================
AddEventHandler('playerJoining', function()
    local src = source
    local st = ensureState(src)
    st.joinTick = GetGameTimer()
    st.lastBeat = GetGameTimer()
end)

AddEventHandler('playerDropped', function()
    local src = source
    State[src] = nil
    explosionCount[src] = nil
    entityCount[src] = nil
    eventCount[src] = nil
    reportCount[src] = nil
end)

CreateThread(function()
    Wait(1000)
    print(('[qb-anticheat] loaded. server-authoritative protections active for "%s".'):format(Config.ServerName))
end)
