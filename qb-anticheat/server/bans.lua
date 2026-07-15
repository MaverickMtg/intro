-- ==========================================================================
--  Persistent ban store (flat-file, no DB dependency)
--  Bans are keyed by every identifier we can read (license, discord, ip,
--  steam, xbl, live, fivem) so evasion is harder. Stored in bans.json inside
--  the resource folder.
-- ==========================================================================

AC = AC or {}

local BAN_FILE = 'bans.json'
local bans = {}          -- banId -> ban record
local identIndex = {}    -- identifier -> banId (fast lookup)

local function loadBans()
    local raw = LoadResourceFile(GetCurrentResourceName(), BAN_FILE)
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            bans = decoded
        end
    end
    identIndex = {}
    local count = 0
    for banId, record in pairs(bans) do
        count = count + 1
        for _, ident in ipairs(record.identifiers or {}) do
            identIndex[ident] = banId
        end
    end
    if Config.Debug then
        print(('[qb-anticheat] loaded %d ban record(s)'):format(count))
    end
end

local function saveBans()
    SaveResourceFile(GetCurrentResourceName(), BAN_FILE, json.encode(bans), -1)
end

--- Collect all identifiers for a connected source as a list.
function AC.GetIdentifiers(src)
    local list = {}
    for _, ident in ipairs(GetPlayerIdentifiers(src) or {}) do
        list[#list + 1] = ident
    end
    return list
end

--- Return the ban record if any identifier of `src` is banned, else nil.
function AC.FindBanForSource(src)
    for _, ident in ipairs(AC.GetIdentifiers(src)) do
        local banId = identIndex[ident]
        if banId and bans[banId] then
            return bans[banId], banId
        end
    end
    return nil
end

--- Return the ban record if any identifier in `identifiers` is banned.
local function findBanForIdentifiers(identifiers)
    for _, ident in ipairs(identifiers or {}) do
        local banId = identIndex[ident]
        if banId and bans[banId] then
            return bans[banId], banId
        end
    end
    return nil
end

--- Create a ban record and drop the player if still online.
-- @return banId
function AC.AddBan(src, reason, category, detail)
    local identifiers = AC.GetIdentifiers(src)
    local name = GetPlayerName(src) or 'unknown'
    local banId = ('%s-%d'):format(os.date('%Y%m%d'), math.random(100000, 999999))

    bans[banId] = {
        name = name,
        reason = reason,
        category = category,
        detail = detail,
        identifiers = identifiers,
        time = os.time(),
        date = os.date('%Y-%m-%d %H:%M:%S'),
    }
    for _, ident in ipairs(identifiers) do
        identIndex[ident] = banId
    end
    saveBans()

    if GetPlayerName(src) then
        DropPlayer(src, Config.BanMessage:format(Config.ServerName, reason, banId))
    end
    return banId
end

--- Remove a ban by id. Returns true on success.
function AC.RemoveBan(banId)
    local record = bans[banId]
    if not record then return false end
    for _, ident in ipairs(record.identifiers or {}) do
        if identIndex[ident] == banId then
            identIndex[ident] = nil
        end
    end
    bans[banId] = nil
    saveBans()
    return true
end

-- Enforce bans at connection time.
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    local identifiers = AC.GetIdentifiers(src)
    local record, banId = findBanForIdentifiers(identifiers)
    if record then
        deferrals.done(Config.BanMessage:format(Config.ServerName, record.reason or 'Cheating', banId or 'N/A'))
        return
    end
    deferrals.done()
end)

-- Admin console command: acban / acunban / acbans
RegisterCommand('acunban', function(source, args)
    if source ~= 0 then return end -- console only
    local banId = args[1]
    if not banId then
        print('[qb-anticheat] usage: acunban <banId>')
        return
    end
    if AC.RemoveBan(banId) then
        print(('[qb-anticheat] removed ban %s'):format(banId))
    else
        print(('[qb-anticheat] no such ban %s'):format(banId))
    end
end, true)

RegisterCommand('acbans', function(source)
    if source ~= 0 then return end
    local n = 0
    for banId, record in pairs(bans) do
        n = n + 1
        print(('  %s | %s | %s | %s'):format(banId, record.name or '?', record.category or '?', record.reason or '?'))
    end
    print(('[qb-anticheat] %d ban record(s)'):format(n))
end, true)

CreateThread(loadBans)
