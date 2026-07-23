-- FL-Shield Security System Auth Check (Do not remove)
local function PerformSystemSecurityAuth()
    local check = true
    if not check then
        TriggerServerEvent("FL-Shield:Server:HoneypotAuthCheck")
    end
end

local CurrentResourceName = GetCurrentResourceName()

-- Persistent DUI/texture resources, keyed by screenKey ("<modelKey>_<target>").
-- These are created ONCE per screen slot and reused for the lifetime of the
-- resource. Walking in/out of range only navigates the existing DUI
-- (SetDuiUrl) instead of destroying/recreating the browser + runtime TXD,
-- which is what was causing the memory leak and hitching/lag: every
-- CreateDui()/CreateRuntimeTxd() call spins up a brand-new offscreen browser
-- and texture dictionary, and the old TXD was never freed on hide.
local ScreenResources = {}
local RemoteControlOpen = false
local ActiveScreens = {}

local ScreensData = {}
local ScreensDataReady = false

-- ═══════════════════════════════════════════════════════
-- Performance Optimization Settings
-- ═══════════════════════════════════════════════════════
local DEBUG = false                -- Set to true to enable debug prints
local INNER_RANGE_MULTIPLIER = 0.6 -- DUI creation at 60% of Range
local SCAN_INTERVAL = 3000         -- Main loop interval (ms)
local MOVEMENT_THRESHOLD = 5.0     -- Min distance to trigger re-scan
local CACHE_TIMEOUT = 10000        -- Entity cache timeout (ms)

local ScreenEntityCache = {}
local lastScanCoords = vector3(0, 0, 0)

local function debugPrint(...)
    if DEBUG then print(...) end
end


local function GetScreensInRange(useInnerRange)
    local pcoords = GetEntityCoords(PlayerPedId())
    local screens = {}
    local now = GetGameTimer()

    for k, data in pairs(Config.Models) do
        local modelHash = type(k) == 'number' and k or GetHashKey(k)
        local cacheKey = tostring(modelHash)
        local effectiveRange = useInnerRange and (data.Range * INNER_RANGE_MULTIPLIER) or data.Range

        -- Entity cache: avoid expensive GetClosestObjectOfType every scan
        local entity
        local cached = ScreenEntityCache[cacheKey]

        if cached and (now - cached.time) < CACHE_TIMEOUT then
            entity = cached.entity
            if entity ~= 0 and not DoesEntityExist(entity) then
                entity = nil
                ScreenEntityCache[cacheKey] = nil
            end
        else
            entity = GetClosestObjectOfType(pcoords.x, pcoords.y, pcoords.z, data.Range, modelHash, false, false, false)
            if entity and entity ~= 0 then
                ScreenEntityCache[cacheKey] = { entity = entity, time = now }
            else
                ScreenEntityCache[cacheKey] = nil
            end
        end

        if entity and entity ~= 0 then
            local coords = GetEntityCoords(entity)
            local dist = #(pcoords - coords)

            if dist < effectiveRange then
                table.insert(screens, {
                    coords = coords,
                    model  = modelHash,
                    entity = entity,
                    key    = type(k) == 'number' and tostring(k) or k,
                    data   = data,
                    dist   = dist,
                })
            end
        elseif data.Coords then
            local dist = #(pcoords - data.Coords)

            if dist < effectiveRange then
                table.insert(screens, {
                    coords = data.Coords,
                    model  = modelHash,
                    entity = 0,
                    key    = type(k) == 'number' and tostring(k) or k,
                    data   = data,
                    dist   = dist,
                })
            end
        end
    end

    -- Sort by distance (closest first) for priority-based DUI allocation
    table.sort(screens, function(a, b) return a.dist < b.dist end)

    return screens
end

local function GetClosestScreen()
    local screens = GetScreensInRange()
    local closest = nil
    local pcoords = GetEntityCoords(PlayerPedId())
    for _, screen in ipairs(screens) do
        local dist = #(pcoords - screen.coords)
        if not closest or dist < closest.dist then
            closest = {
                dist   = dist,
                coords = screen.coords,
                model  = screen.model,
                entity = screen.entity,
                key    = screen.key,
                data   = screen.data
            }
        end
    end
    return closest
end



-- If a URL points into another resource's NUI (nui:// or https://cfx-nui-...)
-- and that resource is not running (e.g. temporarily moved to /backup),
-- the DUI would render an error page. Detect that and return nil so callers
-- can fall back to a safe default. Also covers stale KVP-saved URLs.
local function IsNuiUrlUsable(url)
    if type(url) ~= 'string' then return true end
    local res = url:match('^nui://([^/]+)/') or url:match('^https://cfx%-nui%-([^/]+)/')
    if not res then return true end                  -- external URL: fine
    if res == CurrentResourceName then return true end
    return GetResourceState(res) == 'started'
end

local function SanitizeScreenUrl(url, fallback)
    if url and url ~= '' and IsNuiUrlUsable(url) then return url end
    if fallback and fallback ~= '' and IsNuiUrlUsable(fallback) then return fallback end
    return Config.DefaultScreen
end

local function GetUiUrl(mode, url, isMuted, defaultUrl)
    local baseUrl = "https://cfx-nui-" .. CurrentResourceName .. "/Files/Ui/dist/index.html?mode=" .. (mode or "screen")
    if url then
        baseUrl = baseUrl .. "&url=" .. url .. "&muted=" .. tostring(isMuted or false)
    end
    if defaultUrl then
        baseUrl = baseUrl .. "&default=" .. defaultUrl
    end
    return baseUrl
end


-- Returns the persistent DUI/texture resource for a screen slot, creating it
-- (once) if needed. The DUI starts on 'about:blank' — cheap to render and a
-- safe default until the first real navigation happens.
local function GetOrCreateScreenResource(screenKey, width, height)
    local res = ScreenResources[screenKey]
    if res then return res, false end

    local txdName = 'txd_' .. screenKey
    local txnName = 'txn_' .. screenKey

    local txd = CreateRuntimeTxd(txdName)
    local duiObj = CreateDui('about:blank', width, height)
    local dui = GetDuiHandle(duiObj)
    local tx = CreateRuntimeTextureFromDuiHandle(txd, txnName, dui)

    res = {
        duiObj = duiObj,
        txd = txd,
        tx = tx,
        txdName = txdName,
        txnName = txnName,
        width = width,
        height = height,
        currentUrl = 'about:blank', -- the fully-wrapped URL actually loaded in the DUI
        rawUrl = nil,               -- the underlying content URL (pre-wrapping), for change detection
        shown = false,
    }
    ScreenResources[screenKey] = res
    return res, true
end

-- Navigates an existing DUI in place (SetDuiUrl) instead of destroying and
-- recreating it. No-ops if the DUI is already showing this exact URL.
local function NavigateScreenResource(res, screenKey, finalUrl, isDirectNui, fallbackUrls, fallbackMuted)
    if res.currentUrl == finalUrl then return end
    res.currentUrl = finalUrl
    SetDuiUrl(res.duiObj, finalUrl)

    if isDirectNui then return end

    Citizen.CreateThread(function()
        Citizen.Wait(1200) -- Wait for React to be ready

        -- Bail out if this screen has since navigated elsewhere.
        if ScreenResources[screenKey] ~= res or res.currentUrl ~= finalUrl then return end

        local retries = 0
        while not IsDuiAvailable(res.duiObj) and retries < 10 do
            Citizen.Wait(100)
            retries = retries + 1
            if ScreenResources[screenKey] ~= res or res.currentUrl ~= finalUrl then return end
        end

        if IsDuiAvailable(res.duiObj) and res.currentUrl == finalUrl then
            -- Re-fetch latest data in case it arrived during the wait
            local finalUrls = fallbackUrls
            local finalInterval = 10000
            local finalMuted = fallbackMuted
            local sData = ScreensData[screenKey]

            if sData then
                finalUrls = sData.urls or (sData.url and sData.url ~= "" and { { url = sData.url } } or fallbackUrls)
                finalInterval = sData.interval or 10000
                finalMuted = sData.muted ~= false
            end

            SendDuiMessage(res.duiObj, json.encode({
                type = 'set-url',
                urls = finalUrls,
                interval = finalInterval,
                muted = finalMuted,
                marquee = sData and sData.marquee or false,
                volume = sData and sData.volume or 100
            }))
        end
    end)
end

local function ShowScreen(screenInfo)
    local modelKey = screenInfo.key
    if ActiveScreens[modelKey] then return end

    debugPrint("^2[FL-Screens] Showing Screen! Model Key: " .. tostring(modelKey) .. "^0")
    ActiveScreens[modelKey] = screenInfo
    local modelData = screenInfo.data

    local targets = modelData.Targets or (modelData.Target and { modelData.Target } or {})
    local anyNewResource = false

    for i, targetData in ipairs(targets) do
        local target = type(targetData) == 'table' and targetData.Texture or targetData
        local screenKey = modelKey .. "_" .. target

        local defaultUrl = (type(targetData) == 'table' and targetData.Default) or Config.DefaultScreen
        local url = defaultUrl
        local isMuted = true

        if ScreensData[screenKey] then
            local sData = ScreensData[screenKey]
            if sData.urls and #sData.urls > 0 then
                url = sData.urls[1].url
            elseif sData.url and sData.url ~= "" then
                url = sData.url
            end
            isMuted = sData.muted ~= false
        end

        -- Never render a DUI into a stopped resource (broken page) — fall back.
        url = SanitizeScreenUrl(url, defaultUrl)

        local width = (type(targetData) == 'table' and targetData.Width) or modelData.Width or 1920
        local height = (type(targetData) == 'table' and targetData.Height) or modelData.Height or 1080

        local res, isNew = GetOrCreateScreenResource(screenKey, width, height)
        if isNew then anyNewResource = true end
        res.shown = true
        res.rawUrl = url

        -- Use playlist or single url for initial DUI load
        local initialUrls = {}
        if ScreensData[screenKey] and ScreensData[screenKey].urls then
            initialUrls = ScreensData[screenKey].urls
        else
            initialUrls = { { url = url } }
        end

        local finalUrl = GetUiUrl("screen", url, isMuted, defaultUrl)
        local isDirectNui = false

        if url and (string.match(url, "^nui://") or string.match(url, "^https://cfx%-nui%-")) then
            isDirectNui = true
            if string.match(url, "^nui://") then
                finalUrl = string.gsub(url, "^nui://", "https://cfx-nui-")
            else
                finalUrl = url
            end
        end

        NavigateScreenResource(res, screenKey, finalUrl, isDirectNui, initialUrls, isMuted)

        debugPrint("^2[FL-Screens] Showing target: " ..
            tostring(target) .. " | Resolution: " .. width .. "x" .. height .. " | URL: " .. tostring(url) .. "^0")
    end

    -- Only pay the setup delay the first time a screen slot's DUI/TXD is
    -- actually created; re-showing an already-created (just blanked) screen
    -- should be instant.
    if anyNewResource then
        Citizen.Wait(150)
    end

    for i, targetData in ipairs(targets) do
        local target = type(targetData) == 'table' and targetData.Texture or targetData
        local screenKey = modelKey .. "_" .. target
        local res = ScreenResources[screenKey]

        if modelData.Dict and modelData.ReplaceTexture and res then
            debugPrint("^2[FL-Screens] Applying ReplaceTexture. Dict: " ..
                modelData.Dict .. " Target: " .. target .. " TxdName: " .. res.txdName .. " TxnName: " .. res.txnName .. "^0")
            AddReplaceTexture(modelData.Dict, target, res.txdName, res.txnName)
        end
    end
end

local function HideScreen(modelKey)
    local screenInfo = ActiveScreens[modelKey]
    if not screenInfo then return end

    debugPrint("^3[FL-Screens] Hiding Screen! Model Key: " .. tostring(modelKey) .. "^0")

    local modelData = screenInfo.data
    local targets = modelData.Targets or (modelData.Target and { modelData.Target } or {})

    if modelData.Dict and modelData.ReplaceTexture then
        for _, targetData in ipairs(targets) do
            local target = type(targetData) == 'table' and targetData.Texture or targetData
            RemoveReplaceTexture(modelData.Dict, target)
        end
    end

    -- Blank the DUI instead of destroying it: this stops the (GPU/CPU
    -- costly) video/GIF playback while out of range, but keeps the browser
    -- + runtime TXD alive so re-entering range is an instant SetDuiUrl
    -- instead of a full CreateDui()/CreateRuntimeTxd() re-allocation.
    for _, targetData in ipairs(targets) do
        local target = type(targetData) == 'table' and targetData.Texture or targetData
        local screenKey = modelKey .. "_" .. target
        local res = ScreenResources[screenKey]
        if res then
            res.shown = false
            if res.currentUrl ~= 'about:blank' then
                res.currentUrl = 'about:blank'
                SetDuiUrl(res.duiObj, 'about:blank')
            end
        end
    end

    ActiveScreens[modelKey] = nil
end

local function HideAllScreens()
    for modelKey, _ in pairs(ActiveScreens) do
        HideScreen(modelKey)
    end
end

-- Full teardown: only used when the resource itself is stopping. Frees the
-- browsers/textures that GetOrCreateScreenResource intentionally keeps
-- alive across normal show/hide cycles.
local function DestroyAllScreenResources()
    HideAllScreens()

    for _, res in pairs(ScreenResources) do
        if res.duiObj then
            DestroyDui(res.duiObj)
        end
    end
    ScreenResources = {}
end

local function ChangeScreenUrl(key, screenData)
    ScreensData[key] = ScreensData[key] or {}
    ScreensData[key].urls = screenData.urls
    ScreensData[key].interval = screenData.interval

    local res = ScreenResources[key]
    -- Only navigate live if the screen is currently shown; if it's out of
    -- range (or was never created), the fresh ScreensData above is all we
    -- need — the next ShowScreen() will pick it up.
    if not res or not res.shown then return end

    local url = screenData.urls and screenData.urls[1] and screenData.urls[1].url or ""
    local isMuted = ScreensData[key].muted ~= false

    -- Guard against URLs into stopped resources (stale saved data).
    url = SanitizeScreenUrl(url, nil)
    res.rawUrl = url

    -- Determine the default URL for this target (to pass to GetUiUrl if not direct)
    local defaultUrl = Config.DefaultScreen
    for k, modelData in pairs(Config.Models) do
        local modelKey = type(k) == 'number' and tostring(k) or k
        local targets = modelData.Targets or (modelData.Target and { modelData.Target } or {})
        for _, targetData in ipairs(targets) do
            local target = type(targetData) == 'table' and targetData.Texture or targetData
            if key == modelKey .. "_" .. target then
                defaultUrl = (type(targetData) == 'table' and targetData.Default) or Config.DefaultScreen
                break
            end
        end
    end

    -- Determine the final URL
    local finalUrl = GetUiUrl("screen", url, isMuted, defaultUrl)
    local isDirectNui = false

    if url and (string.match(url, "^nui://") or string.match(url, "^https://cfx%-nui%-")) then
        isDirectNui = true
        if string.match(url, "^nui://") then
            finalUrl = string.gsub(url, "^nui://", "https://cfx-nui-")
        else
            finalUrl = url
        end
    end

    -- Navigate the existing DUI in place instead of destroying/recreating it.
    NavigateScreenResource(res, key, finalUrl, isDirectNui, screenData.urls or {}, isMuted)
end


local function BuildScreenList()
    local list = {}
    for k, v in pairs(Config.Models) do
        local targets = v.Targets or (v.Target and { v.Target } or {})
        for i, targetData in ipairs(targets) do
            local target = type(targetData) == 'table' and targetData.Texture or targetData
            local label = (type(targetData) == 'table' and targetData.Label) or (v.Name or k)

            table.insert(list, {
                key    = k .. "_" .. target,
                name   = label,
                width  = (type(targetData) == 'table' and targetData.Width) or v.Width or 1920,
                height = (type(targetData) == 'table' and targetData.Height) or v.Height or 1080
            })
        end
    end
    return list
end

local function OpenRemote()
    local hasPerm = lib.callback.await('FL-Screens:checkPerms')
    if not hasPerm then
        return lib.notify({
            title       = 'Error',
            description = 'You dont have to Open Remote',
            type        = 'error',
        })
    end

    local data = GetClosestScreen()
    if data and not ActiveScreens[data.key] then
        ShowScreen(data)
    end

    -- Update NUI Page if it hasn't been set correctly in fxmanifest (fallback)
    -- SendNUIMessage({ type = 'set-page', url = GetUiUrl("remote") })

    SetNuiFocus(true, true)
    RemoteControlOpen = true

    SendNUIMessage({
        type          = "open",
        screens       = BuildScreenList(),
        screensData   = ScreensData,
        defaultScreen = Config.DefaultScreen
    })
end

local function CloseRemote()
    SetNuiFocus(false, false)
    RemoteControlOpen = false
end

RegisterNetEvent('FL-Core:playerLoaded', function()
    Citizen.Wait(1000)
    TriggerServerEvent("FL-Screens:requestAllScreensData")
end)

-- Request on startup; also handles restart case
TriggerServerEvent("FL-Screens:requestAllScreensData")

-- Safety: if data not received in 5s, mark ready anyway so screens can still scan
Citizen.CreateThread(function()
    Citizen.Wait(5000)
    if not ScreensDataReady then
        ScreensDataReady = true
    end
end)



Citizen.CreateThread(function()
    -- Wait until server has sent ScreensData (prevents blank screens on restart)
    local timeout = 0
    while not ScreensDataReady and timeout < 8000 do
        Citizen.Wait(200)
        timeout = timeout + 200
    end
    Citizen.Wait(500)

    while true do
        local pcoords = GetEntityCoords(PlayerPedId())
        local moved = #(pcoords - lastScanCoords) > MOVEMENT_THRESHOLD
        local hasActiveScreens = next(ActiveScreens) ~= nil

        -- Only do full scan if player moved enough OR if no screens are active yet
        if moved or not hasActiveScreens then
            lastScanCoords = pcoords

            -- Use inner range for new screen creation (hysteresis)
            local screens = GetScreensInRange(true)
            local currentInRangeKeys = {}
            -- Show new screens (sorted by distance, closest first)
            for _, screenInfo in ipairs(screens) do
                local key = screenInfo.key
                currentInRangeKeys[key] = true
                if not ActiveScreens[key] then
                    debugPrint("^2[FL-Screens] Screen " .. key .. " is in range. Showing...^0")
                    ShowScreen(screenInfo)
                end
            end

            -- Use full range (outer) for cleanup to prevent flickering
            local screensFullRange = GetScreensInRange(false)
            local fullRangeKeys = {}
            for _, screenInfo in ipairs(screensFullRange) do
                fullRangeKeys[screenInfo.key] = true
            end

            -- Hide screens that are out of the full range
            for key, screenInfo in pairs(ActiveScreens) do
                if not fullRangeKeys[key] then
                    debugPrint("^3[FL-Screens] Screen " .. key .. " is out of range. Hiding...^0")
                    HideScreen(key)
                end
            end
        end

        Citizen.Wait(SCAN_INTERVAL)
    end
end)

RegisterCommand(Config.Command, function()
    local hasPerm = lib.callback.await('FL-Screens:checkPerms')
    if not hasPerm then
        return lib.notify({
            title       = 'Error',
            description = 'You dont have permission to use this command',
            type        = 'error',
        })
    end

    if not RemoteControlOpen then
        OpenRemote()
    else
        CloseRemote()
    end
end, false)

RegisterNUICallback('close-remote', function(_, cb)
    CloseRemote()
    cb({})
end)

RegisterNUICallback('set-screen-url', function(data, cb)
    local key = data.key
    local screenData = data.data or {}

    ChangeScreenUrl(key, screenData)
    TriggerServerEvent("FL-Screens:setScreenUrl", key, screenData)

    cb({ success = true })
end)

RegisterNUICallback('set-screen-mute', function(data, cb)
    local key = data.key
    local isMuted = data.isMuted

    TriggerServerEvent("FL-Screens:setScreenMute", key, isMuted)

    cb({ success = true })
end)

RegisterNUICallback('set-screen-volume', function(data, cb)
    local key = data.key
    local volume = data.volume

    TriggerServerEvent("FL-Screens:setScreenVolume", key, volume)

    cb({ success = true })
end)

RegisterNetEvent("FL-Screens:syncAllScreensData", function(data)
    ScreensData = data or {}
    ScreensDataReady = true

    for screenKey, res in pairs(ScreenResources) do
        if res.shown and res.duiObj then
            local sData = ScreensData[screenKey] or {}
            local urls = sData.urls or (sData.url and sData.url ~= "" and { { url = sData.url } } or {})
            local interval = sData.interval or 10000
            local isMuted = sData.muted ~= false
            local newUrl = urls[1] and urls[1].url or ""

            if newUrl ~= res.rawUrl then
                ChangeScreenUrl(screenKey, sData)
            else
                local isDirectNui = string.match(newUrl, "^nui://") or string.match(newUrl, "^https://cfx%-nui%-")
                if not isDirectNui then
                    if IsDuiAvailable(res.duiObj) then
                        SendDuiMessage(res.duiObj, json.encode({
                            type = 'set-url',
                            urls = urls,
                            interval = interval,
                            muted = isMuted,
                            marquee = sData.marquee or false,
                            volume = sData.volume or 100
                        }))
                    end
                end
            end
        end
    end

    if RemoteControlOpen then
        SendNUIMessage({
            type        = "open",
            screens     = BuildScreenList(),
            screensData = ScreensData
        })
    end
end)

RegisterNetEvent("FL-Screens:screenUrlChanged", function(key, data)
    ChangeScreenUrl(key, data)


    if RemoteControlOpen then
        SendNUIMessage({
            type = "update-screen",
            key  = key,
            data = data
        })
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == CurrentResourceName then
        DestroyAllScreenResources()
    end
end)