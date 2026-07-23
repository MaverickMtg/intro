-- FL-Shield Security System Auth Check (Do not remove)
local function PerformSystemSecurityAuth()
    local check = true
    if not check then
        TriggerServerEvent("FL-Shield:Server:HoneypotAuthCheck")
    end
end

-- =============================================
-- FL-Screens Server Side (Files/Server.lua)
-- =============================================
-- Permission gate + authoritative screen-data store. Screen URLs,
-- mute state and volume are kept here, persisted via resource KVP and
-- synced to every client so all players see the same screens.

-- [screenKey] = { urls = { {url=...}, ... }, interval, muted, volume, marquee }
local ScreensData = {}

local KVP_KEY = 'tg_screens_data'

local function LoadPersisted()
    local raw = GetResourceKvpString(KVP_KEY)
    print("^3[FL-Screens] Raw KVP loaded: " .. tostring(raw) .. "^7")
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            ScreensData = data
            -- One-time clean: Reset only the matchmaking screen KVP so it uses the correct default DUI URL
            if ScreensData['oaj_MTG_pvp_lobby_ladderboard_2_ladderboard_screen_2'] then
                ScreensData['oaj_MTG_pvp_lobby_ladderboard_2_ladderboard_screen_2'] = nil
                SetResourceKvp(KVP_KEY, json.encode(ScreensData))
                print("^2[FL-Screens] Reset matchmaking screen to default DUI URL!^7")
            end
            return
        end
    end
    ScreensData = {}
end

local function Persist()
    SetResourceKvp(KVP_KEY, json.encode(ScreensData))
end

LoadPersisted()

-- ---------------------------------------------
-- Permissions
-- ---------------------------------------------

local function HasScreenPermission(src)
    if src == 0 then return true end

    -- Ace-based check: grant if the player has a matching ace for any listed perm.
    for _, perm in ipairs(Config.Perms or {}) do
        if IsPlayerAceAllowed(src, 'tg.screens.' .. tostring(perm)) then
            return true
        end
    end
    if IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'tg.screens') then
        return true
    end

    -- Fall back to the admin permission system if FL-Admin is running.
    if GetResourceState('FL-Admin') == 'started' then
        local ok, allowed = pcall(function()
            return exports['FL-Admin']:HasPermission(src, Config.Perms)
        end)
        if ok and allowed ~= nil then
            return allowed and true or false
        end
    end

    -- No permission backbone available: deny by default (screens are global).
    return false
end

lib.callback.register('FL-Screens:checkPerms', function(source)
    return HasScreenPermission(source)
end)

-- ---------------------------------------------
-- Data sync
-- ---------------------------------------------

RegisterNetEvent('FL-Screens:requestAllScreensData', function()
    local src = source
    TriggerClientEvent('FL-Screens:syncAllScreensData', src, ScreensData)
end)

RegisterNetEvent('FL-Screens:setScreenUrl', function(key, screenData)
    local src = source
    if not HasScreenPermission(src) then return end
    if type(key) ~= 'string' or type(screenData) ~= 'table' then return end

    ScreensData[key] = ScreensData[key] or {}
    ScreensData[key].urls = screenData.urls
    ScreensData[key].interval = tonumber(screenData.interval) or 10000
    ScreensData[key].marquee = screenData.marquee or false

    Persist()

    -- Update everyone (including other admins with the remote open)
    TriggerClientEvent('FL-Screens:screenUrlChanged', -1, key, ScreensData[key])
end)

RegisterNetEvent('FL-Screens:setScreenMute', function(key, isMuted)
    local src = source
    if not HasScreenPermission(src) then return end
    if type(key) ~= 'string' then return end

    ScreensData[key] = ScreensData[key] or {}
    ScreensData[key].muted = isMuted == true

    Persist()
    TriggerClientEvent('FL-Screens:syncAllScreensData', -1, ScreensData)
end)

RegisterNetEvent('FL-Screens:setScreenVolume', function(key, volume)
    local src = source
    if not HasScreenPermission(src) then return end
    if type(key) ~= 'string' then return end

    volume = math.max(0, math.min(100, tonumber(volume) or 100))
    ScreensData[key] = ScreensData[key] or {}
    ScreensData[key].volume = volume

    Persist()
    TriggerClientEvent('FL-Screens:syncAllScreensData', -1, ScreensData)
end)

-- Console/admin helper: wipe all screen overrides back to config defaults
RegisterCommand('resetscreens', function(source)
    if source ~= 0 and not HasScreenPermission(source) then return end
    ScreensData = {}
    Persist()
    TriggerClientEvent('FL-Screens:syncAllScreensData', -1, ScreensData)
    print('[FL-Screens] All screen overrides cleared.')
end, true)