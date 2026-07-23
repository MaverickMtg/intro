local QBCore = exports['FL-Core']:GetCoreObject()
if not QBCore then
    TriggerEvent('QBCore:GetObject', function(obj) QBCore = obj end)
end

local AdminMenuCache = {
    categories = nil,
    modalActions = nil,
    lastUpdate = 0,
    cacheDuration = 60000
}

local function IsCacheValid()
    return AdminMenuCache.categories ~= nil and AdminMenuCache.modalActions ~= nil and
        (GetGameTimer() - AdminMenuCache.lastUpdate) < AdminMenuCache.cacheDuration
end

local function UpdateCache(categories, modalActions)
    AdminMenuCache.categories = categories
    AdminMenuCache.modalActions = modalActions
    AdminMenuCache.lastUpdate = GetGameTimer()
end

local function ClearCache()
    AdminMenuCache.categories = nil
    AdminMenuCache.modalActions = nil
    AdminMenuCache.lastUpdate = 0
end

local OpenTeleportLocationsMenu

local isStaffCached = false

local function IsBlockedInGangLabsWorld()
    if GetResourceState('tg_ganglabs') ~= 'started' then return false end

    local inGangLabs = false
    local okIn = pcall(function()
        inGangLabs = exports['tg_ganglabs']:IsInGangWorld()
    end)
    if not okIn or not inGangLabs then return false end

    local isGangManager = false
    local okManager = pcall(function()
        isGangManager = exports['tg_ganglabs']:IsGangManager()
    end)
    if okManager and isGangManager then return false end

    local isGangTeam = false
    local okTeam = pcall(function()
        isGangTeam = exports['tg_ganglabs']:IsGangTeam()
    end)
    if okTeam and isGangTeam then return false end

    return true
end

local function IsBlockedInPursuitMatch()
    if GetResourceState('FL-Pursuits') ~= 'started' then return false end

    local inPursuit = false
    local ok = pcall(function()
        inPursuit = exports['FL-Pursuits']:IsInPursuitMatch()
    end)

    if ok and inPursuit then return true end

    return LocalPlayer.state.inPursuitMatch == true
end

local function IsAdminBlockedInEvent()
    if IsBlockedInGangLabsWorld() then
        return true, 'Gang Labs'
    end

    if IsBlockedInPursuitMatch() then
        return true, 'Pursuits'
    end

    return false
end

function ViktoIsAdmin()
    if IsAdminBlockedInEvent() then return false end
    if isStaffCached == true then return true end

    local state = false
    local success = pcall(function()
        local st = LocalPlayer.state.isStaff
        if st ~= nil then
            state = st
        else
            st = Entity(PlayerPedId()).state.isStaff
            if st ~= nil then
                state = st
            end
        end
    end)

    if state == true and isStaffCached ~= true then
        isStaffCached = true
    end

    if Config.Debug and not state and not isStaffCached then
        print(string.format('[VIKTO ADMIN DEBUG] ViktoIsAdmin Check - Cache: %s, StateBag: %s', tostring(isStaffCached),
            tostring(state)))
    end

    return isStaffCached == true
end

RegisterNetEvent('vikto_admin:client:syncStaffStatus', function(status)
    isStaffCached = status
    if Config.Debug then
        print(string.format('[VIKTO ADMIN] Received force sync: %s', tostring(status)))
    end
end)

-- RegisterCommand('checkadmin', function()
--     local src = GetPlayerServerId(PlayerId())
--     local stateBag = LocalPlayer.state.isStaff
--     print('^2--- VIKTO ADMIN STATUS ---^7')
--     print('Personal Source: ' .. tostring(src))
--     print('State Bag (LocalPlayer): ' .. tostring(stateBag))
--     print('Local Cache (isStaffCached): ' .. tostring(isStaffCached))
--     print('ViktoIsAdmin() Result: ' .. tostring(ViktoIsAdmin()))
--     print('^2-------------------------^7')
-- end, false)

local isJailed = false
local jailTimeRemaining = 0
local jailReason = ''
local jailAdmin = ''

local function FormatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    local text = ""
    if h > 0 then
        text = text .. h .. "h "
    end
    if m > 0 or h > 0 then
        text = text .. m .. "m "
    end
    text = text .. s .. "s"
    return text
end

local isMuted = false

local isGodMode = false
local superJumpEnabled = false
local isFrozen = false
local muteUIShown = false
local muteDuration = 0
local muteStartTime = 0
local sentBackTimer = 0
local sentBackCoords = nil
local sentBackBucket = nil
local FormatSmartTime
local AdminMenuState
local RefreshAdminMenuUi
local ApplyAdminMenuInputMode
local IsAdminMenuFocusActive
local GoBackAdminMenu
local TriggerMenuItemAction

local MasterLoop = {
    jailUIShown = false,
    jailLastTick = 0,
    muteLastUpdate = 0,
    sentBackLastTick = 0,
}

-- Open Player Modal Helper
local function OpenPlayerModal(targetData)
    if not targetData then return end

    SendNUIMessage({
        action = "openPlayerModal",
        player = {
            id = targetData.id or targetData.source,
            cid = targetData.cid,
            name = targetData.name,
            identifiers = targetData.identifiers or {},
            playtime = targetData.playtime or "0h 0m",
            job = targetData.job or "Unknown",
            group = targetData.group or "user",
            money = targetData.money or {}
        },
        modalConfig = targetData.modalConfig or Config.PlayerModalActions
    })
end

-- NUI Action Trigger
RegisterNUICallback('triggerPlayerAction', function(data, cb)
    local targetServerId = tonumber(data.id)
    local requestedAction = data.action

    if targetServerId and targetServerId > 0 then
        TriggerServerEvent('FL-Admin:server:executeAction', requestedAction, targetServerId, data.args)
    else
        print('^1[FL-Admin Error] Invalid Target Server ID passed from NUI!^7')
    end
    cb('ok')
end)

-- Live jail apply/release. This handler was missing entirely — jailing an
-- online player used to do nothing until they relogged.
RegisterNetEvent('vikto_admin:client:jail', function(state, data)
    if state then
        isJailed = true
        jailTimeRemaining = (data and data.remaining) or 0
        jailReason = (data and data.reason) or 'No reason provided'
        jailAdmin = (data and data.admin) or 'Unknown Admin'
        MasterLoop.jailUIShown = false
        MasterLoop.jailLastTick = GetGameTimer()

        local ped = cache.ped or PlayerPedId()
        local jc = Config.JailOptions.JailCoords
        DoScreenFadeOut(500)
        Wait(500)
        if cache.vehicle then TaskLeaveVehicle(ped, cache.vehicle, 16) Wait(200) end
        SetEntityCoords(ped, jc.x, jc.y, jc.z, false, false, false, false)
        ClearPedTasksImmediately(ped)
        RemoveAllPedWeapons(ped, true)
        DoScreenFadeIn(500)

        if GetResourceState('pma-voice') == 'started' then
            pcall(function()
                exports['pma-voice']:setVoiceProperty('radioEnabled', false)
                exports['pma-voice']:setRadioChannel(0)
            end)
        end
        if GetResourceState('FL-Chat') == 'started' then
            pcall(function() exports['FL-Chat']:setChatEnabled(false) end)
        end
    else
        isJailed = false
        jailTimeRemaining = 0
        SendNUIMessage({ action = 'hideJail' })
        MasterLoop.jailUIShown = false

        if GetResourceState('pma-voice') == 'started' then
            pcall(function() exports['pma-voice']:setVoiceProperty('radioEnabled', true) end)
        end
        if GetResourceState('FL-Chat') == 'started' then
            pcall(function()
                exports['FL-Chat']:setChatEnabled(true)
                exports['FL-Chat']:setChatVisible(true)
            end)
        end
        -- The server (ReleaseFromJail) teleports us to the lobby spawn.
    end
end)

CreateThread(function()
    MasterLoop.jailLastTick = GetGameTimer()
    MasterLoop.muteLastUpdate = GetGameTimer()
    MasterLoop.sentBackLastTick = GetGameTimer()

    while true do
        local now = GetGameTimer()
        local ped = cache.ped
        local needsFastTick = false

        if isJailed and jailTimeRemaining > 0 then
            needsFastTick = true

            if now - MasterLoop.jailLastTick >= 1000 then
                MasterLoop.jailLastTick = now
                jailTimeRemaining = jailTimeRemaining - 1

                if jailTimeRemaining <= 0 then
                    isJailed = false
                    jailTimeRemaining = 0
                end

                if isJailed then
                    if not MasterLoop.jailUIShown then
                        SendNUIMessage({
                            action = "showJail",
                            time = FormatTime(jailTimeRemaining),
                            reason = jailReason,
                            admin = jailAdmin
                        })
                        MasterLoop.jailUIShown = true
                    else
                        SendNUIMessage({
                            action = "updateJailTime",
                            time = FormatTime(jailTimeRemaining)
                        })
                    end
                end
            end

            if isJailed then
                local playerCoords = GetEntityCoords(ped)
                local jailCoords = Config.JailOptions.JailCoords
                if #(playerCoords - jailCoords) > Config.JailOptions.JailRadius then
                    SetEntityCoords(ped, jailCoords.x, jailCoords.y, jailCoords.z, false, false, false, false)
                    Notify('You cannot escape from jail!', 'error')
                end

                for _, control in ipairs(Config.JailOptions.DisabledControls) do
                    DisableControlAction(0, control, true)
                end
            end
        else
            MasterLoop.jailLastTick = now
            if MasterLoop.jailUIShown then
                SendNUIMessage({ action = "hideJail" })
                MasterLoop.jailUIShown = false
            end
        end

        if isGodMode then
            needsFastTick = true
            SetEntityInvincible(ped, true)
            SetPlayerInvincible(cache.playerId, true)
            SetEntityHealth(ped, 200)
            SetPedArmour(ped, 200)

            if cache.vehicle then
                SetEntityInvincible(cache.vehicle, true)
                SetVehicleFixed(cache.vehicle)
                SetVehicleEngineHealth(cache.vehicle, 1000.0)
                SetVehicleBodyHealth(cache.vehicle, 1000.0)
            end
        end

        if superJumpEnabled then
            needsFastTick = true
            SetSuperJumpThisFrame(cache.playerId)
        end

        if isFrozen then
            needsFastTick = true
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 47, true)
            DisableControlAction(0, 58, true)
            DisablePlayerFiring(ped, true)
        end

        if now - MasterLoop.muteLastUpdate >= 1000 then
            MasterLoop.muteLastUpdate = now

            if isMuted then
                local elapsed = (now - muteStartTime) / 1000
                local remaining = muteDuration - elapsed

                if remaining > 0 then
                    local timeText = FormatSmartTime(remaining)
                    if not muteUIShown then
                        SendNUIMessage({ action = "showMute", timeText = timeText })
                        muteUIShown = true
                    else
                        SendNUIMessage({ action = "updateMuteTime", timeText = timeText })
                    end
                else
                    if muteUIShown then
                        SendNUIMessage({ action = "hideMute" })
                        muteUIShown = false
                        isMuted = false
                    end
                end
            elseif not isMuted and muteUIShown then
                SendNUIMessage({ action = "hideMute" })
                muteUIShown = false
            end
        end

        if sentBackTimer > 0 then
            needsFastTick = true

            if now - MasterLoop.sentBackLastTick >= 1000 then
                MasterLoop.sentBackLastTick = now
                sentBackTimer = sentBackTimer - 1
                if sentBackTimer <= 0 then
                    lib.hideTextUI()
                    sentBackCoords = nil
                    sentBackBucket = nil
                end
            end

            if sentBackTimer > 0 and IsControlJustPressed(0, 38) then
                TriggerServerEvent('vikto_admin:server:restorePlayer', sentBackCoords, sentBackBucket)
                sentBackTimer = 0
                lib.hideTextUI()
                sentBackCoords = nil
                sentBackBucket = nil
            end
        else
            MasterLoop.sentBackLastTick = now
        end

        if AdminMenuState and AdminMenuState.isOpen then
            needsFastTick = true

            if IsAdminMenuFocusActive() then
                DisableAllControlActions(0)
                EnableControlAction(0, 1, true)
                EnableControlAction(0, 2, true)
                EnableControlAction(0, 24, true)
                EnableControlAction(0, 25, true)
                EnableControlAction(0, 18, true)
                EnableControlAction(0, 69, true)
                EnableControlAction(0, 92, true)
                EnableControlAction(0, 106, true)
                EnableControlAction(0, 237, true)
                EnableControlAction(0, 238, true)
                DisablePlayerFiring(ped, true)
            end

            if AdminMenuState.inputMode == 'arrows' then
                local altPressed = IsDisabledControlPressed(0, 19)
                if altPressed ~= AdminMenuState.altCursorActive then
                    AdminMenuState.altCursorActive = altPressed
                    ApplyAdminMenuInputMode()
                end

                DisableControlAction(0, 172, true)
                DisableControlAction(0, 173, true)
                DisableControlAction(0, 174, true)
                DisableControlAction(0, 175, true)
                DisableControlAction(0, 177, true)
                DisableControlAction(0, 200, true)
                DisableControlAction(0, 37, true)

                local currentMenu = AdminMenuState.menus[AdminMenuState.currentMenuId]
                local itemCount = currentMenu and #currentMenu.items or 0

                if not AdminMenuState.altCursorActive and itemCount > 0 then
                    local upPressed = IsDisabledControlPressed(0, 172)
                    local downPressed = IsDisabledControlPressed(0, 173)

                    if upPressed or downPressed then
                        if now > AdminMenuState.nextMoveTime then
                            if upPressed then
                                AdminMenuState.selectedIndex = AdminMenuState.selectedIndex - 1
                                if AdminMenuState.selectedIndex < 1 then
                                    AdminMenuState.selectedIndex = itemCount
                                end
                            elseif downPressed then
                                AdminMenuState.selectedIndex = AdminMenuState.selectedIndex + 1
                                if AdminMenuState.selectedIndex > itemCount then
                                    AdminMenuState.selectedIndex = 1
                                end
                            end

                            RefreshAdminMenuUi()

                            if IsDisabledControlJustPressed(0, 172) or IsDisabledControlJustPressed(0, 173) then
                                AdminMenuState.nextMoveTime = now + 250
                            else
                                AdminMenuState.nextMoveTime = now + 60
                            end
                        end
                    else
                        AdminMenuState.nextMoveTime = 0
                    end
                end

                if (not AdminMenuState.altCursorActive) and IsDisabledControlJustPressed(0, 175) then
                    if itemCount > 0 then
                        TriggerMenuItemAction(currentMenu.items[AdminMenuState.selectedIndex])
                    end
                elseif (not AdminMenuState.altCursorActive) and (IsDisabledControlJustPressed(0, 174) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200)) then
                    GoBackAdminMenu()
                end
            end
        end

        if needsFastTick then
            Wait(0)
        else
            Wait(500)
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    ClearCache()

    QBCore.Functions.TriggerCallback('vikto_admin:server:getJailStatus', function(jailData)
        if jailData and jailData.isJailed then
            isJailed = true
            jailTimeRemaining = jailData.timeRemaining
            jailReason = jailData.reason or 'No reason provided'
            jailAdmin = jailData.adminName or 'Unknown Admin'

            local playerPed = cache.ped
            local jailCoords = Config.JailOptions.JailCoords
            SetEntityCoords(playerPed, jailCoords.x, jailCoords.y, jailCoords.z, false, false, false, false)

            if GetResourceState('pma-voice') == 'started' then
                exports['pma-voice']:setVoiceProperty('radioEnabled', false)
                exports['pma-voice']:setRadioChannel(0)
            end
        end
    end)

    QBCore.Functions.TriggerCallback('vikto_admin:server:getMuteStatus', function(muteData)
        if muteData and muteData.isMuted then
            TriggerEvent('vikto_admin:client:setMuted', true, muteData.remaining)
        end
    end)

    TriggerEvent('Vikto:Admin:ToggleNames', false)
end)

RegisterNetEvent('FL-Core:playerLoaded', function()
    ClearCache()
    QBCore.Functions.TriggerCallback('vikto_admin:server:getJailStatus', function(jailData)
        if jailData and jailData.isJailed then
            isJailed = true
            jailTimeRemaining = jailData.timeRemaining
            jailReason = jailData.reason or 'No reason provided'
            jailAdmin = jailData.adminName or 'Unknown Admin'
            local playerPed = cache.ped
            local jailCoords = Config.JailOptions.JailCoords
            SetEntityCoords(playerPed, jailCoords.x, jailCoords.y, jailCoords.z, false, false, false, false)

            if GetResourceState('pma-voice') == 'started' then
                exports['pma-voice']:setVoiceProperty('radioEnabled', false)
                exports['pma-voice']:setRadioChannel(0)
            end
        end
    end)
    QBCore.Functions.TriggerCallback('vikto_admin:server:getMuteStatus', function(muteData)
        if muteData and muteData.isMuted then
            TriggerEvent('vikto_admin:client:setMuted', true, muteData.remaining)
        end
    end)

    TriggerEvent('Vikto:Admin:ToggleNames', false)
end)

CreateThread(function()
    Wait(1000)
    if QBCore and QBCore.Functions.GetPlayerData() and QBCore.Functions.GetPlayerData().citizenid then
        QBCore.Functions.TriggerCallback('vikto_admin:server:getJailStatus', function(jailData)
            if jailData and jailData.isJailed then
                isJailed = true
                jailTimeRemaining = jailData.timeRemaining
                jailReason = jailData.reason or 'No reason provided'
                jailAdmin = jailData.adminName or 'Unknown Admin'

                if GetResourceState('FL-Chat') == 'started' then
                    exports['FL-Chat']:setChatEnabled(false)
                end

                local playerPed = cache.ped
                local jailCoords = Config.JailOptions.JailCoords
                SetEntityCoords(playerPed, jailCoords.x, jailCoords.y, jailCoords.z, false, false, false, false)

                if GetResourceState('pma-voice') == 'started' then
                    exports['pma-voice']:setVoiceProperty('radioEnabled', false)
                    exports['pma-voice']:setRadioChannel(0)
                end

                if Config.Debug then
                    print('[VIKTO ADMIN] Restored jail status after script restart')
                end
            end
        end)

        QBCore.Functions.TriggerCallback('vikto_admin:server:getMuteStatus', function(muteData)
            if muteData and muteData.isMuted then
                TriggerEvent('vikto_admin:client:setMuted', true, muteData.remaining)

                if Config.Debug then
                    print('[VIKTO ADMIN] Restored mute status after script restart')
                end
            end
        end)

        TriggerEvent('Vikto:Admin:ToggleNames', false)
    end
end)

RegisterNetEvent('vikto_admin:client:clearCache', function()
    ClearCache()
    if Config.Debug then
        print('[VIKTO ADMIN] Cache cleared - permissions will be refreshed')
    end
end)

exports('isPlayerJailed', function()
    return isJailed
end)

exports('isPlayerMuted', function()
    return isMuted
end)

function Notify(message, type)
    lib.notify({
        description = message,
        type = type or 'inform',
        position = 'top-right',
        duration = 5000
    })
end

function CopyToClipboard(coordType)
    local coords = GetEntityCoords(cache.ped)
    local heading = GetEntityHeading(cache.ped)
    local clipboard = ''

    if coordType == 'coords2' then
        clipboard = ('vector2(%.2f, %.2f)'):format(coords.x, coords.y)
    elseif coordType == 'coords3' then
        clipboard = ('vector3(%.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z)
    elseif coordType == 'coords4' then
        clipboard = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z, heading)
    elseif coordType == 'heading' then
        clipboard = ('%.2f'):format(heading)
    end

    lib.setClipboard(clipboard)
    Notify('Copied to clipboard: ' .. clipboard, 'success')
end

local namesForcedByNoClip = false
local isPlayerIdsEnabled = false

local PTFX_DICT = 'core'
local PTFX_ASSET = 'ent_dst_elec_fire_sp'
local PTFX_SCALE = 1.75
local PTFX_DURATION = 1500
local PTFX_AUDIONAME = 'ent_amb_elec_crackle'
local PTFX_AUDIOREF = 0
local LOOP_AMOUNT = 7
local LOOP_DELAY = 75

local function PlayNoclipPtfx(tgtPedId)
    CreateThread(function()
        if not tgtPedId or tgtPedId <= 0 then return end
        RequestNamedPtfxAsset(PTFX_DICT)
        while not HasNamedPtfxAssetLoaded(PTFX_DICT) do
            Wait(5)
        end

        local particleTbl = {}
        for i = 0, LOOP_AMOUNT do
            UseParticleFxAsset(PTFX_DICT)
            PlaySoundFromEntity(-1, PTFX_AUDIONAME, tgtPedId, PTFX_AUDIOREF, false, 0)
            local partiResult = StartParticleFxLoopedOnEntity(
                PTFX_ASSET,
                tgtPedId,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                PTFX_SCALE,
                false, false, false
            )
            table.insert(particleTbl, partiResult)
            Wait(LOOP_DELAY)
        end

        Wait(PTFX_DURATION)
        for _, parti in ipairs(particleTbl) do
            StopParticleFxLooped(parti, true)
        end
        RemoveNamedPtfxAsset(PTFX_DICT)
    end)
end

RegisterNetEvent('vikto_admin:client:showPtfx', function(targetSrc)
    local player = GetPlayerFromServerId(targetSrc)
    if player ~= -1 then
        PlayNoclipPtfx(GetPlayerPed(player))
    end
end)

local noclipEnabled = false
local noclipCam = nil

local MOVE_SPEED = 1.0
local MAX_SPEED = 64.0
local MIN_SPEED = 0.1

local CONTROLS = {
    LOOK_LR = 1,
    LOOK_UD = 2,
    MOVE_UD = 31,
    MOVE_LR = 30,
    MOVE_UP = 152,
    MOVE_DOWN = 153,
    FAST = 21,
    SLOW = 19,
}

local function getFallImpulse(H)
    return 1.6428571428571428 * H + 3.5714285714285836
end

local function disableRagdollingWhileFall()
    CreateThread(function()
        local ped = cache.ped
        local pedHeight = GetEntityHeightAboveGround(ped)
        if pedHeight == nil or pedHeight < 4.0 then return end

        local pid = PlayerId()
        SetEntityInvincible(ped, true)
        SetPlayerFallDistance(pid, 9000.0)

        local downForce = getFallImpulse(pedHeight)
        ApplyForceToEntity(ped, 3, vector3(0.0, 0.0, -downForce), vector3(0.0, 0.0, 0.0), 0, true, true, true, false,
            true)

        local fallAwaitLimit = 1000
        local fallAwaitStep = 25
        local fallAwaitElapsed = 0
        while not IsPedFalling(ped) do
            if fallAwaitElapsed >= fallAwaitLimit then
                SetEntityInvincible(ped, isGodMode or false)
                SetPlayerFallDistance(pid, -1)
                return
            end
            fallAwaitElapsed = fallAwaitElapsed + fallAwaitStep
            Wait(fallAwaitStep)
        end

        repeat Wait(50) until not IsPedFalling(ped)

        Wait(750)
        SetEntityInvincible(ped, isGodMode or false)
        SetPlayerFallDistance(pid, -1)
    end)
end

local function toggleNoclip(forceMode, skipNames)
    local lastNoclipPos = nil
    local lastNoclipHeading = 0.0

    local targetState = false
    if forceMode ~= nil then
        if noclipEnabled == forceMode then return end
        targetState = forceMode
    else
        targetState = not noclipEnabled
    end

    if targetState then
        if GetResourceState('FL-Event') == 'started' then
            local isParticipant = false
            local ok = pcall(function()
                isParticipant = exports['FL-Event']:IsPlayerParticipantInEvent()
            end)
            if ok and isParticipant and not ViktoIsAdmin() then
                Notify('You cannot enable flight while in an event!', 'error')
                return
            end
        end
        if GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:isInMatch() then
            Notify('You cannot enable flight during a match!', 'error')
            return
        end
        if IsBlockedInPursuitMatch() then
            Notify('You cannot enable flight during Pursuits!', 'error')
            return
        end
        if GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
            Notify('You cannot enable flight during a gang world!', 'error')
            return
        end
        if IsBlockedInGangLabsWorld() then
            Notify('You cannot enable flight during Gang Labs!', 'error')
            return
        end
    end

    noclipEnabled = targetState

    local ped = cache.ped
    local vehicle = cache.vehicle

    TriggerServerEvent('vikto_admin:server:syncPtfx')

    if noclipEnabled then
        local pos = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, heading, true, false)

        local rot = GetGameplayCamRot(2)

        noclipCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, 75.0, true,
            2)
        SetCamActive(noclipCam, true)
        RenderScriptCams(true, true, 500, false, false)

        SetEntityVisible(ped, false, false)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        SetEntityCollision(ped, false, false)

        if vehicle and vehicle ~= 0 then
            SetEntityVisible(vehicle, false, false)
            SetEntityInvincible(vehicle, true)
            FreezeEntityPosition(vehicle, true)
            SetEntityCollision(vehicle, false, false)
        end

        SendNUIMessage({
            action = "showNoclip"
        })

        if not skipNames and not isPlayerIdsEnabled then
            namesForcedByNoClip = true
            TriggerEvent('Vikto:Admin:ToggleNames', true)
        end

        CreateThread(function()
            while noclipEnabled do
                Wait(0)
                local camPos = GetCamCoord(noclipCam)
                local camRot = GetCamRot(noclipCam, 2)
                local rv, fv, uv = GetCamMatrix(noclipCam)

                if IsDisabledControlPressed(0, 15) or IsControlPressed(0, 15) then
                    MOVE_SPEED = math.min(MOVE_SPEED + 0.1, MAX_SPEED)
                elseif IsDisabledControlPressed(0, 14) or IsControlPressed(0, 14) then
                    MOVE_SPEED = math.max(MIN_SPEED, MOVE_SPEED - 0.1)
                end

                local multiplier = 1.0
                if IsDisabledControlPressed(0, CONTROLS.FAST) then
                    multiplier = 8.0
                elseif IsDisabledControlPressed(0, CONTROLS.SLOW) then
                    multiplier = 0.1
                end

                local currentSpeed = MOVE_SPEED * multiplier * (GetFrameTime() * 60)

                local moveX = GetDisabledControlNormal(0, CONTROLS.MOVE_LR)
                local moveY = GetDisabledControlNormal(0, CONTROLS.MOVE_UD)
                local moveZ = 0.0

                if IsDisabledControlPressed(0, CONTROLS.MOVE_UP) then
                    moveZ = 1.0
                elseif IsDisabledControlPressed(0, CONTROLS.MOVE_DOWN) then
                    moveZ = -1.0
                end

                local newPos = camPos + (fv * -moveY * currentSpeed) + (rv * moveX * currentSpeed) +
                    (uv * moveZ * currentSpeed)

                local lookX = GetDisabledControlNormal(0, CONTROLS.LOOK_LR)
                local lookY = GetDisabledControlNormal(0, CONTROLS.LOOK_UD)
                local sensitivity = 4.0
                local newRotX = camRot.x - (lookY * sensitivity)
                local newRotZ = camRot.z - (lookX * sensitivity)

                if newRotX > 89.0 then newRotX = 89.0 elseif newRotX < -89.0 then newRotX = -89.0 end

                SetCamCoord(noclipCam, newPos.x, newPos.y, newPos.z)
                SetCamRot(noclipCam, newRotX, camRot.y, newRotZ, 2)

                SetEntityCoordsNoOffset(ped, newPos.x, newPos.y, newPos.z, false, false, false)
                SetEntityHeading(ped, newRotZ)

                if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                    SetEntityCoordsNoOffset(vehicle, newPos.x, newPos.y, newPos.z, false, false, false)
                    SetEntityHeading(vehicle, newRotZ)
                end

                lastNoclipPos = newPos
                lastNoclipHeading = newRotZ

                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
                DisableControlAction(0, 152, true)
                DisableControlAction(0, 153, true)
                DisablePlayerFiring(ped, true)
            end

            SendNUIMessage({
                action = "hideNoclip"
            })

            RenderScriptCams(false, true, 500, false, false)
            DestroyCam(noclipCam, false)
            noclipCam = nil

            if lastNoclipPos then
                NetworkResurrectLocalPlayer(lastNoclipPos.x, lastNoclipPos.y, lastNoclipPos.z, lastNoclipHeading or 0.0, true, false)
                SetEntityCoords(ped, lastNoclipPos.x, lastNoclipPos.y, lastNoclipPos.z, false, false, false, false)
            end

            SetEntityVisible(ped, true, false)
            FreezeEntityPosition(ped, false)
            SetEntityCollision(ped, true, true)

            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                if lastNoclipPos then
                    SetEntityCoords(vehicle, lastNoclipPos.x, lastNoclipPos.y, lastNoclipPos.z, false, false, false, false)
                end
                SetEntityVisible(vehicle, true, false)
                SetEntityInvincible(vehicle, false)
                FreezeEntityPosition(vehicle, false)
                SetEntityCollision(vehicle, true, true)
                SetPedIntoVehicle(ped, vehicle, -1)
            else
                disableRagdollingWhileFall()
            end

            if namesForcedByNoClip then
                TriggerEvent('Vikto:Admin:ToggleNames', false)
                namesForcedByNoClip = false
            end
        end)
    else

    end
end

RegisterNetEvent('Vikto:Admin:ToggleNoClip', function(forceMode)
    if Config.Debug then print('[VIKTO ADMIN] Received NoClip Event Trigger') end
    if not ViktoIsAdmin() then
        if Config.Debug then print('[VIKTO ADMIN] Access Denied: ViktoIsAdmin returned false') end
        return
    end
    toggleNoclip(forceMode)
    TriggerServerEvent('vikto_admin:server:logNoClip', noclipEnabled)
end)

exports('ToggleNoClip', function(forceMode, skipNames)
    toggleNoclip(forceMode, skipNames)
end)

RegisterNetEvent('vikto_admin:client:clearChat', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('vikto_admin:server:clearChat')
end)

RegisterNetEvent('Vikto:Admin:ReviveSelf', function()
    if not ViktoIsAdmin() then return end
    if IsBlockedInGangLabsWorld() then
        Notify('You cannot revive yourself while in Gang Labs!', 'error')
        return
    end
    local pos = GetEntityCoords(cache.ped)
    local heading = GetEntityHeading(cache.ped)
    NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, heading, true, false)
    TriggerEvent('hospital:client:Revive')
    Notify('You have been revived!', 'success')

    TriggerServerEvent('vikto_admin:server:logReviveSelf')
end)

local isInvisible = false

RegisterNetEvent('Vikto:Admin:ToggleInvisible', function()
    if not ViktoIsAdmin() then return end
    isInvisible = not isInvisible
    local playerPed = cache.ped

    SetEntityVisible(playerPed, not isInvisible, false)
    SetEntityAlpha(playerPed, isInvisible and 0 or 255, false)

    if isInvisible then
        Notify('You are now invisible!', 'success')
    else
        Notify('You are now visible!', 'success')
    end

    TriggerServerEvent('vikto_admin:server:logInvisible', isInvisible)
end)

isGodMode = false

RegisterNetEvent('Vikto:Admin:ToggleGodMode', function()
    if not ViktoIsAdmin() then return end
    isGodMode = not isGodMode
    local ped = cache.ped

    SetEntityInvincible(ped, isGodMode)
    SetPlayerInvincible(cache.playerId, isGodMode)

    if isGodMode then
        Notify('God Mode turned ON!', 'success')
        SetEntityCanBeDamaged(ped, false)
        SetPedCanRagdoll(ped, false)
        SetPedConfigFlag(ped, 149, true)
        SetPedConfigFlag(ped, 438, true)
    else
        Notify('God Mode turned OFF!', 'error')
        SetEntityCanBeDamaged(ped, true)
        SetPedCanRagdoll(ped, true)
        SetPedConfigFlag(ped, 149, false)
        SetPedConfigFlag(ped, 438, false)
    end

    TriggerServerEvent('vikto_admin:server:logGodMode', isGodMode)
end)

superJumpEnabled = false

RegisterNetEvent('Vikto:Admin:ToggleSuperJump', function()
    if not ViktoIsAdmin() then return end
    superJumpEnabled = not superJumpEnabled

    if superJumpEnabled then
        Notify('Super Jump turned ON!', 'success')

    else
        Notify('Super Jump turned OFF!', 'error')
    end

    TriggerServerEvent('vikto_admin:server:logSuperJump', superJumpEnabled)
end)

local fastRunEnabled = false

RegisterNetEvent('Vikto:Admin:ToggleFastRun', function()
    if not ViktoIsAdmin() then return end
    fastRunEnabled = not fastRunEnabled
    local player = cache.playerId

    if fastRunEnabled then
        SetRunSprintMultiplierForPlayer(player, 1.49)
        SetSwimMultiplierForPlayer(player, 1.49)
        Notify('Fast Run turned ON!', 'success')
    else
        SetRunSprintMultiplierForPlayer(player, 1.0)
        SetSwimMultiplierForPlayer(player, 1.0)
        Notify('Fast Run turned OFF!', 'error')
    end

    TriggerServerEvent('vikto_admin:server:logFastRun', fastRunEnabled)
end)

local isStreamerMode = false

RegisterNetEvent('Vikto:Admin:ToggleStreamerMode', function()
    if not ViktoIsAdmin() then return end
    isStreamerMode = not isStreamerMode
    LocalPlayer.state:set('streamerMode', isStreamerMode, true)

    if isStreamerMode then
        Notify('Streamer Mode turned ON! (Reports hidden)', 'success')
    else
        Notify('Streamer Mode turned OFF! (Reports visible)', 'error')
    end
end)

isFrozen = false

RegisterNetEvent('Vikto:Admin:FreezePlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Freeze Player',
        icon = 'id-card',
        fields = {
            { name = 'cid', type = 'text', label = 'Character ID (CID)', placeholder = 'Enter the CID of the player to freeze', isRequired = true }
        }
    })

    if not input then return end

    local cid = input.cid
    TriggerServerEvent('vikto_admin:server:freezePlayer', cid, true)
end)

RegisterNetEvent('Vikto:Admin:UnfreezePlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Unfreeze Player',
        icon = 'id-card',
        fields = {
            { name = 'cid', type = 'text', label = 'Character ID (CID)', placeholder = 'Enter the CID of the player to unfreeze', isRequired = true }
        }
    })

    if not input then return end

    local cid = input.cid
    TriggerServerEvent('vikto_admin:server:freezePlayer', cid, false)
end)

RegisterNetEvent('Vikto:Admin:AddMatchmakingXP', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Add Points',
        icon = 'trophy',
        fields = {
            { name = 'cid',    type = 'text',   label = 'Character ID (CID)', placeholder = 'Enter Player CID',    isRequired = true },
            { name = 'amount', type = 'number', label = 'Amount',             placeholder = 'Enter points amount', isRequired = true }
        }
    })

    if not input then return end

    TriggerServerEvent('vikto_admin:server:adjustMatchmakingXP', input.cid, input.amount, 'add')
end)

RegisterNetEvent('Vikto:Admin:RemoveMatchmakingXP', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Remove Points',
        icon = 'trophy',
        fields = {
            { name = 'cid',    type = 'text',   label = 'Character ID (CID)', placeholder = 'Enter Player CID',    isRequired = true },
            { name = 'amount', type = 'number', label = 'Amount',             placeholder = 'Enter points amount', isRequired = true }
        }
    })

    if not input then return end

    TriggerServerEvent('vikto_admin:server:adjustMatchmakingXP', input.cid, input.amount, 'remove')
end)

RegisterNetEvent('Vikto:Admin:CheckMatchmakingXP', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Check Points',
        icon = 'trophy',
        fields = {
            { name = 'cid', type = 'text', label = 'Character ID (CID)', placeholder = 'Enter Player CID', isRequired = true }
        }
    })

    if not input then return end

    TriggerServerEvent('vikto_admin:server:checkMatchmakingXP', input.cid)
end)

RegisterNetEvent('Vikto:Admin:AddTruckPoints', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Add Truck Points',
        icon = 'truck',
        fields = {
            { name = 'cid',    type = 'text',   label = 'Character ID (CID)', placeholder = 'Enter Player CID',    isRequired = true },
            { name = 'amount', type = 'number', label = 'Amount',             placeholder = 'Enter points amount', isRequired = true }
        }
    })

    if not input then return end

    TriggerServerEvent('vikto_admin:server:adjustTruckPoints', input.cid, input.amount, 'add')
end)

RegisterNetEvent('Vikto:Admin:RemoveTruckPoints', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Remove Truck Points',
        icon = 'truck',
        fields = {
            { name = 'cid',    type = 'text',   label = 'Character ID (CID)', placeholder = 'Enter Player CID',    isRequired = true },
            { name = 'amount', type = 'number', label = 'Amount',             placeholder = 'Enter points amount', isRequired = true }
        }
    })

    if not input then return end

    TriggerServerEvent('vikto_admin:server:adjustTruckPoints', input.cid, input.amount, 'remove')
end)

RegisterNetEvent('Vikto:Admin:CheckTruckPoints', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Check Truck Points',
        icon = 'truck',
        fields = {
            { name = 'cid', type = 'text', label = 'Character ID (CID)', placeholder = 'Enter Player CID', isRequired = true }
        }
    })

    if not input then return end

    TriggerServerEvent('vikto_admin:server:checkTruckPoints', input.cid)
end)

RegisterNetEvent('vikto_admin:client:freezePlayer', function(state)
    local ped = cache.ped
    isFrozen = state
    FreezeEntityPosition(ped, state)
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        FreezeEntityPosition(veh, state)
    end

    if state then
        Notify('You have been frozen by an admin!', 'error')

    else
        Notify('You have been unfrozen by an admin!', 'success')
    end
end)

RegisterNetEvent('Vikto:Admin:TeleportLocations', function()
    if not ViktoIsAdmin() then return end
    if OpenTeleportLocationsMenu then
        OpenTeleportLocationsMenu()
    end
end)

RegisterNetEvent('Vikto:Admin:TeleportTPM', function()
    if not ViktoIsAdmin() then return end
    local waypoint = GetFirstBlipInfoId(8)

    if not DoesBlipExist(waypoint) then
        Notify('No waypoint set on map!', 'error')
        return
    end

    local waypointCoords = GetBlipInfoIdCoord(waypoint)
    local x, y = waypointCoords.x, waypointCoords.y
    local ped = cache.ped
    local veh = cache.vehicle

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    if veh and veh ~= 0 then
        SetEntityCoords(veh, x, y, 100.0, false, false, false, false)
        FreezeEntityPosition(veh, true)
    else
        SetEntityCoords(ped, x, y, 100.0, false, false, false, false)
        FreezeEntityPosition(ped, true)
    end

    local timeout = 2500
    while IsEntityWaitingForWorldCollision(ped) and timeout > 0 do
        Wait(100)
        timeout = timeout - 100
    end

    local groundZ = 0.0
    local groundFound = false
    for i = 1, 15 do
        local found, z = GetGroundZFor_3dCoord(x, y, 1000.0, false)
        if found then
            groundZ = z
            groundFound = true
            break
        end
        Wait(100)
    end

    if veh and veh ~= 0 then
        SetEntityCoords(veh, x, y, groundZ + 1.0, false, false, false, false)
        SetVehicleOnGroundProperly(veh)
        FreezeEntityPosition(veh, false)
    else
        SetEntityCoords(ped, x, y, groundZ + 1.0, false, false, false, false)
        FreezeEntityPosition(ped, false)

        CreateThread(function()
            Wait(100)
            disableRagdollingWhileFall()
        end)
    end

    DoScreenFadeIn(500)
    TriggerServerEvent('vikto_admin:server:logTeleportWaypoint', vector3(x, y, groundZ))
    Notify('Teleported to waypoint!', 'success')
end)

RegisterNetEvent('Vikto:Admin:TeleportToCoords', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Teleport to Coords',
        icon = 'location-dot',
        fields = {
            { name = 'coords', type = 'text', label = 'Coordinates (X, Y, Z)', placeholder = '0.0, 0.0, 0.0', isRequired = true }
        }
    })

    if not input then return end

    local coordsStr = input.coords
    local coordsTable = {}

    for word in string.gmatch(coordsStr, "[%-]?%d+%.?%d*") do
        table.insert(coordsTable, tonumber(word))
    end

    local x, y, z = coordsTable[1], coordsTable[2], coordsTable[3]

    if x and y and z then
        local ped = cache.ped
        local vehicle = cache.vehicle

        if vehicle then
            SetEntityCoords(vehicle, x, y, z, false, false, false, false)
        else
            SetEntityCoords(ped, x, y, z, false, false, false, false)
        end

        Notify(('Teleported to: %.2f, %.2f, %.2f'):format(x, y, z), 'success')
        TriggerServerEvent('vikto_admin:server:logTeleportCoords', vector3(x, y, z))
    else
        Notify('Invalid format! Use: X, Y, Z or X Y Z', 'error')
    end
end)

RegisterNetEvent('Vikto:Admin:GoToPlayer', function()
    if not ViktoIsAdmin() then return end

    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Go To Player',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true }
        }
    })

    if not input then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:gotoPlayer', serverId)
end)

local isSpectating = false
local spectateTarget = -1
local lastSpectateCoords = nil

local function makeFivemInstructionalScaleform(keysTable)
    local scaleform = RequestScaleformMovie("instructional_buttons")
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(1)
    end
    BeginScaleformMovieMethod(scaleform, "CLEAR_ALL")
    EndScaleformMovieMethod()

    BeginScaleformMovieMethod(scaleform, "SET_CLEAR_SPACE")
    ScaleformMovieMethodAddParamInt(200)
    EndScaleformMovieMethod()

    for btnIndex, keyData in ipairs(keysTable) do
        local btn = GetControlInstructionalButton(0, keyData[2], true)

        BeginScaleformMovieMethod(scaleform, "SET_DATA_SLOT")
        ScaleformMovieMethodAddParamInt(btnIndex - 1)
        ScaleformMovieMethodAddParamPlayerNameString(btn)
        BeginTextCommandScaleformString("STRING")
        AddTextComponentSubstringKeyboardDisplay(keyData[1])
        EndTextCommandScaleformString()
        EndScaleformMovieMethod()
    end

    BeginScaleformMovieMethod(scaleform, "DRAW_INSTRUCTIONAL_BUTTONS")
    EndScaleformMovieMethod()

    BeginScaleformMovieMethod(scaleform, "SET_BACKGROUND_COLOUR")
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(80)
    EndScaleformMovieMethod()

    return scaleform
end

local function collisionTpCoordTransition(coords)
    if not IsScreenFadedOut() then DoScreenFadeOut(500) end
    while not IsScreenFadedOut() do Wait(5) end

    local playerPed = PlayerPedId()
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(playerPed, coords.x, coords.y, coords.z)
    local attempts = 0
    while not HasCollisionLoadedAroundEntity(playerPed) do
        Wait(5)
        attempts = attempts + 1
        if attempts > 1000 then break end
    end
end

RegisterNetEvent('Vikto:Admin:Spectate', function()
    if not ViktoIsAdmin() then return end

    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Spectate Player',
        icon = 'id-card',
        fields = {
            { name = 'cid', type = 'text', label = 'Character ID (CID)', placeholder = 'Enter the CID of the player to spectate', isRequired = true }
        }
    })

    if not input then return end

    local cid = input.cid
    if not cid or cid == '' then
        QBCore.Functions.Notify('Invalid CID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:spectatePlayer', cid)
end)

RegisterNetEvent('vikto_admin:client:spectatePlayer', function(targetId, targetCoords)
    local playerPed = PlayerPedId()

    if isSpectating and spectateTarget == targetId then
        TriggerServerEvent('vikto_admin:server:spectateEnd')
        return
    end

    if isSpectating then
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(5) end
    else
        lastSpectateCoords = GetEntityCoords(playerPed)
        isSpectating = true
    end

    spectateTarget = targetId

    local coordsUnderTransition = vec3(targetCoords.x, targetCoords.y, targetCoords.z - 15.0)
    collisionTpCoordTransition(coordsUnderTransition)

    local targetResolveAttempts = 0
    local resolvedPlayerId = -1
    local resolvedPed = 0
    while (resolvedPlayerId <= 0 or resolvedPed <= 0) and targetResolveAttempts < 300 do
        targetResolveAttempts = targetResolveAttempts + 1
        resolvedPlayerId = targetId and GetPlayerFromServerId(targetId) or -1
        resolvedPed = (resolvedPlayerId and resolvedPlayerId ~= -1) and GetPlayerPed(resolvedPlayerId) or 0
        Wait(50)
    end

    if (resolvedPlayerId <= 0 or resolvedPed <= 0) then
        TriggerServerEvent('vikto_admin:server:spectateEnd')
        QBCore.Functions.Notify('Failed to resolve target player!', 'error')
        return
    end

    NetworkSetInSpectatorMode(true, resolvedPed)
    SetEntityVisible(playerPed, false, 0)
    SetEntityCollision(playerPed, false, false)
    SetEntityInvincible(playerPed, true)
    FreezeEntityPosition(playerPed, true)

    DoScreenFadeIn(500)

    local keysTable = {
        { 'Back', 194 },
        { 'Prev', 188 },
        { 'Next', 187 },
    }

    CreateThread(function()
        local scaleform = makeFivemInstructionalScaleform(keysTable)
        while isSpectating and spectateTarget == targetId do
            DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)

            if IsControlJustPressed(0, 194) then
                TriggerEvent('vikto_admin:client:spectatePlayer', spectateTarget)
            elseif IsControlJustPressed(0, 188) then
                TriggerServerEvent('vikto_admin:server:spectateCycle', spectateTarget, false)
            elseif IsControlJustPressed(0, 187) then
                TriggerServerEvent('vikto_admin:server:spectateCycle', spectateTarget, true)
            end

            local targetPlayerId = spectateTarget and GetPlayerFromServerId(spectateTarget) or -1
            local targetPedId = (targetPlayerId and targetPlayerId ~= -1) and GetPlayerPed(targetPlayerId) or 0
            if DoesEntityExist(targetPedId) then
                local tCoords = GetEntityCoords(targetPedId)
                SetEntityCoords(PlayerPedId(), tCoords.x, tCoords.y, tCoords.z - 15.0, false, false, false, false)
            else
                QBCore.Functions.Notify('Target player lost!', 'error')
                TriggerEvent('vikto_admin:client:spectatePlayer', spectateTarget)
                break
            end

            Wait(0)
        end
        SetScaleformMovieAsNoLongerNeeded(scaleform)
    end)
end)

RegisterNetEvent('vikto_admin:client:spectateCleanup', function()
    local playerPed = PlayerPedId()
    isSpectating = false
    spectateTarget = -1
    NetworkSetInSpectatorMode(false, nil)

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(5) end

    SetEntityVisible(playerPed, true, 0)
    SetEntityCollision(playerPed, true, true)
    SetEntityInvincible(playerPed, false)
    FreezeEntityPosition(playerPed, false)

    if lastSpectateCoords then
        collisionTpCoordTransition(lastSpectateCoords)
        lastSpectateCoords = nil
    end

    DoScreenFadeIn(500)
    QBCore.Functions.Notify('Stopped spectating.', 'info')
end)

RegisterNetEvent('vikto_admin:client:spectateCycleFailed', function()
    QBCore.Functions.Notify('No other players online to cycle!', 'error')
end)

RegisterNetEvent('Vikto:Admin:BringPlayer', function()
    if not ViktoIsAdmin() then return end

    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Bring Player',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true }
        }
    })

    if not input then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:bringPlayer', serverId)
end)

RegisterNetEvent('Vikto:Admin:BringMultiple', function(args)
    local hasPerm = ViktoIsAdmin()
    if not hasPerm then
        local isStreamer = false
        local success = pcall(function()
            isStreamer = lib.callback.await('FL-Vipmenu:server:HasStreamerRole')
        end)
        if isStreamer then
            hasPerm = true
        end
    end
    if not hasPerm then return end
    if not args or #args == 0 then
        TriggerEvent('Vikto:Admin:BringPlayer')
        return
    end

    if #args > 20 then
        Notify('You can only bring a maximum of 20 players at once!', 'error')
        return
    end

    for _, idStr in ipairs(args) do
        local serverId = tonumber(idStr) or idStr
        if serverId then
            TriggerServerEvent('vikto_admin:server:bringPlayer', serverId)
        else
            Notify('Invalid player ID: ' .. tostring(idStr), 'error')
        end
    end
end)

RegisterNetEvent('Vikto:Admin:KillPlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Kill Player',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true }
        }
    })

    if not input then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:killPlayer', serverId)
end)

RegisterNetEvent('Vikto:Admin:RevivePlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Revive Player',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true }
        }
    })

    if not input then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:revivePlayer', serverId)
end)

RegisterNetEvent('Vikto:Admin:ReviveRadius', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Revive Radius',
        icon = 'circle-radiation',
        fields = {
            { name = 'radius', type = 'number', label = 'Select Radius', placeholder = 'Enter reach radius to revive players', isRequired = true }
        }
    })

    if not input then return end

    TriggerServerEvent('vikto_admin:server:reviveRadius', input.radius)
end)

RegisterNetEvent('Vikto:Admin:ReviveAll', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('vikto_admin:server:reviveAll')
end)

RegisterNetEvent('Vikto:Admin:KickPlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Kick Player',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true },
            { name = 'reason',   type = 'text',   label = 'Kick Reason',      placeholder = 'Enter reason here...',              isRequired = true }
        }
    })

    if not input then return end

    if not input.serverId or tostring(input.serverId) == '' then
        Notify('You must enter a player ID!', 'error')
        return
    end

    if not input.reason or input.reason == '' then
        Notify('You must provide a reason!', 'error')
        return
    end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID! Must be a number.', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:kickPlayer', serverId, input.reason)
end)

RegisterNetEvent('Vikto:Admin:BanPlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Ban Player',
        icon = 'id-card',
        fields = {
            { name = 'cid',    type = 'number', label = 'Citizen ID (CID)', placeholder = 'Enter the CID of the player to ban', isRequired = true },
            { name = 'reason', type = 'text',   label = 'Ban Reason',       placeholder = 'Enter reason here...',               isRequired = true },
            {
                name = 'duration',
                type = 'select',
                label = 'Ban Duration',
                isRequired = true,
                options = {
                    { label = '1 Hour',    value = '1' },
                    { label = '3 Hours',   value = '3' },
                    { label = '6 Hours',   value = '6' },
                    { label = '12 Hours',  value = '12' },
                    { label = '1 Day',     value = '24' },
                    { label = '3 Days',    value = '72' },
                    { label = '1 Week',    value = '168' },
                    { label = '2 Week',    value = '336' },
                    { label = '3 Week',    value = '504' },
                    { label = '1 Month',   value = '720' },
                    { label = 'Permanent', value = '0' }
                }
            }
        }
    })

    if not input then return end

    if not input.cid or input.cid == '' then
        Notify('You must enter a player ID!', 'error')
        return
    end

    if not input.reason or input.reason == '' then
        Notify('You must provide a ban reason!', 'error')
        return
    end

    local cid = tonumber(input.cid)
    if not cid then
        Notify('Invalid player ID! Must be a number.', 'error')
        return
    end

    local duration = tonumber(input.duration) or 0

    TriggerServerEvent('vikto_admin:server:banPlayer', cid, input.reason, duration)
end)

RegisterNetEvent('Vikto:Admin:UnbanPlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Unban Player',
        icon = 'id-card',
        fields = {
            { name = 'cid',    type = 'number', label = 'Citizen ID (CID)', placeholder = 'Enter the CID of the player to unban', isRequired = true },
            { name = 'reason', type = 'text',   label = 'Unban Reason',     placeholder = 'Enter reason here...',                 isRequired = true }
        }
    })

    if not input then return end

    if not input.cid or tostring(input.cid) == '' then
        Notify('You must enter a CID!', 'error')
        return
    end

    if not input.reason or input.reason == '' then
        Notify('You must provide a reason!', 'error')
        return
    end

    local inputCid = tonumber(input.cid)
    if not inputCid then
        Notify('Invalid CID! Must be a number.', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:unbanPlayer', inputCid, input.reason)
end)

RegisterNetEvent('vikto_admin:client:killPlayer', function()
    local playerPed = cache.ped
    SetEntityHealth(playerPed, 0)
end)

RegisterNetEvent('vikto_admin:client:sendToJail', function(time, reason, adminName, isSync)
    local playerPed = cache.ped

    local jailCoords = Config.JailOptions.JailCoords

    if not isSync then
        SetEntityCoords(playerPed, jailCoords.x, jailCoords.y, jailCoords.z, false, false, false, false)
    end

    isJailed = true
    jailTimeRemaining = time * 60
    jailReason = reason or 'No reason provided'
    jailAdmin = adminName or 'Unknown Admin'

    if not isSync then
        Notify('You have been jailed for ' .. FormatTime(time * 60) .. '! Reason: ' .. jailReason, 'error')

        if GetResourceState('FL-Chat') == 'started' then
            exports['FL-Chat']:setChatEnabled(false)
        end

        if GetResourceState('pma-voice') == 'started' then
            exports['pma-voice']:setVoiceProperty('radioEnabled', false)
            exports['pma-voice']:setRadioChannel(0)
        end
    end
end)

RegisterNetEvent('vikto_admin:client:releaseFromJail', function()
    local playerPed = cache.ped

    local releaseCoords = Config.JailOptions.UnJailCoords

    SetEntityCoords(playerPed, releaseCoords.x, releaseCoords.y, releaseCoords.z, false, false, false, false)

    isJailed = false
    jailTimeRemaining = 0
    jailReason = ''
    jailAdmin = ''

    Notify('You have been released from jail!', 'success')

    if GetResourceState('FL-Chat') == 'started' then
        exports['FL-Chat']:setChatEnabled(true)
    end

    if GetResourceState('pma-voice') == 'started' then
        exports['pma-voice']:setVoiceProperty('radioEnabled', true)
    end
end)

RegisterNetEvent('Vikto:Admin:JailPlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Jail Player',
        icon = 'clock',
        fields = {
            { name = 'targetId', type = 'number', label = 'Player ID', placeholder = 'Enter player server ID', isRequired = true },
            {
                name = 'reason_time',
                type = 'select',
                label = 'Jail Reason & Duration',
                isRequired = true,
                options = {
                    { label = 'Griefing (10 Minutes)', value = '10|Griefing' },
                    { label = 'Slander / Insults (15 Minutes)', value = '15|Slander / Insults' },
                    { label = 'Exploiting / Glitching (5 Minutes)', value = '5|Exploiting / Glitching' },
                    { label = 'Cheating / Hacks (120 Minutes)', value = '120|Cheating / Hacks' },
                    { label = 'Staff Disrespect (20 Minutes)', value = '20|Staff Disrespect' },
                    { label = 'Chat Spam / Toxicity (10 Minutes)', value = '10|Chat Spam / Toxicity' },
                    { label = 'Event Sabotage (30 Minutes)', value = '30|Event Sabotage' },
                    { label = 'Other / Custom Reason...', value = 'custom' }
                }
            }
        }
    })

    if not input or not input.targetId or not input.reason_time then return end

    local serverId = tonumber(input.targetId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    local minutes, reason

    if input.reason_time == 'custom' then
        local customInput = exports['FL-F1Menu']:OpenPrompt({
            title = 'Custom Jail Details',
            icon = 'pencil',
            fields = {
                { name = 'time',   type = 'number', label = 'Jail Time (Minutes)', placeholder = 'Enter duration in minutes', min = 1, max = Config.JailOptions.MaxJailTime, isRequired = true },
                { name = 'reason', type = 'text',   label = 'Custom Reason',       placeholder = 'Enter the custom reason', minLength = 1, maxLength = 50, isRequired = true }
            }
        })
        if not customInput or not customInput.time or not customInput.reason then return end
        minutes = tonumber(customInput.time)
        reason = customInput.reason
    else
        local split = {}
        for match in string.gmatch(input.reason_time, "[^|]+") do
            table.insert(split, match)
        end
        minutes = tonumber(split[1])
        reason = split[2]
    end

    if minutes and reason then
        TriggerServerEvent('vikto_admin:server:jailPlayer', serverId, minutes, reason)
    end
end)

RegisterNetEvent('Vikto:Admin:UnJailPlayer', function()
    if not ViktoIsAdmin() then return end
    QBCore.Functions.TriggerCallback('vikto_admin:server:getJailedPlayers', function(jailedPlayers)
        if not jailedPlayers or #jailedPlayers == 0 then
            Notify('No jailed players found!', 'error')
            return
        end

        local playerOptions = {}
        for _, player in ipairs(jailedPlayers) do
            table.insert(playerOptions, {
                value = player.serverId,
                label = player.label
            })
        end

        local input = exports['FL-F1Menu']:OpenPrompt({
            title = 'Unjail Player',
            icon = 'unlock',
            fields = {
                { name = 'serverId', type = 'number', label = 'Player ID / CID', placeholder = 'Server ID or CID of the jailed player (see list)', isRequired = true }
            }
        })

        if not input then return end

        TriggerServerEvent('vikto_admin:server:unjailPlayer', tonumber(input.serverId))
    end)
end)

RegisterCommand('jail', function()
    TriggerEvent('Vikto:Admin:JailPlayer')
end, false)

RegisterCommand('unjail', function()
    TriggerEvent('Vikto:Admin:UnJailPlayer')
end, false)

RegisterNetEvent('Vikto:Admin:MuteChat', function(args)
    if not ViktoIsAdmin() then return end
    if args and args[1] then
        local targetCid = tonumber(args[1])
        local duration = tonumber(args[2]) or Config.VoiceMute.DefaultDuration
        local reason = args[3] or 'No reason provided'
        if targetCid then
            TriggerServerEvent('vikto_admin:server:muteChatPlayer', targetCid, duration, reason)
            return
        end
    end

    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Mute Chat Player',
        icon = 'comment-slash',
        fields = {
            { name = 'cid',   type = 'number', label = 'Player CID', placeholder = 'Enter the CID of the player to mute chat', isRequired = true },
            { name = 'value', type = 'number', label = 'Value',      min = 1,                                                  isRequired = true, defaultValue = 1 },
            {
                name = 'unit',
                type = 'select',
                label = 'Unit',
                isRequired = true,
                options = {
                    { label = 'Minutes',   value = 'm' },
                    { label = 'Hours',     value = 'h' },
                    { label = 'Days',      value = 'd' },
                    { label = 'Weeks',     value = 'w' },
                    { label = 'Months',    value = 'month' },
                    { label = 'Permanent', value = 'p' }
                }
            },
            { name = 'reason', type = 'text', label = 'Reason', placeholder = 'Enter the reason for the chat mute', isRequired = true }
        }
    })

    if not input or not input.cid then return end

    local cid = tonumber(input.cid)
    local value = tonumber(input.value) or 0
    local unit = input.unit
    local reason = input.reason or 'No reason provided'

    local totalMinutes = value
    if unit == 'p' then
        totalMinutes = 0
    elseif unit == 'h' then
        totalMinutes = value * 60
    elseif unit == 'd' then
        totalMinutes = value * 1440
    elseif unit == 'w' then
        totalMinutes = value * 10080
    elseif unit == 'month' then
        totalMinutes = value * 43200
    end

    if totalMinutes <= 0 and unit ~= 'p' then
        totalMinutes = Config.VoiceMute.DefaultDuration
    end

    TriggerServerEvent('vikto_admin:server:muteChatPlayer', cid, totalMinutes, reason)
end)

RegisterNetEvent('Vikto:Admin:UnmuteChat', function(args)
    if not ViktoIsAdmin() then return end
    if args and args[1] then
        local targetCid = tonumber(args[1])
        if targetCid then
            TriggerServerEvent('vikto_admin:server:unmuteChatPlayer', targetCid)
            return
        end
    end

    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Unmute Chat Player',
        icon = 'comment',
        fields = {
            { name = 'cid', type = 'number', label = 'Player CID', placeholder = 'Enter the CID of the player', isRequired = true }
        }
    })

    if not input or not input.cid then return end

    TriggerServerEvent('vikto_admin:server:unmuteChatPlayer', tonumber(input.cid))
end)

RegisterNetEvent('Vikto:Admin:GiveItem', function()
    if not ViktoIsAdmin() then return end

    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Give Item',
        icon = 'box',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player',  isRequired = true },
            { name = 'item',     type = 'text',   label = 'Item Name',        placeholder = 'Enter item spawn name (e.g. water)', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Amount',           placeholder = 'Enter the amount',                   min = 1,          max = 9999, defaultValue = 1, isRequired = true }
        }
    })

    if not input then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:giveItem', serverId, input.item, input.amount)
end)

RegisterNetEvent('Vikto:Admin:RemoveItem', function()
    if not ViktoIsAdmin() then return end

    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Remove Item',
        icon = 'box-open',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player',  isRequired = true },
            { name = 'item',     type = 'text',   label = 'Item Name',        placeholder = 'Enter item spawn name (e.g. water)', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Amount',           placeholder = 'Enter the amount to remove',         min = 1,          max = 9999, defaultValue = 1, isRequired = true }
        }
    })

    if not input then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:removeItem', serverId, input.item, input.amount)
end)

RegisterNetEvent('Vikto:Admin:CheckRadio', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Check Radio Frequency',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true }
        }
    })

    if not input or not input.serverId then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:checkRadio', serverId)
end)

RegisterNetEvent('Vikto:Admin:CheckJailTime', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Check Jail Time',
        icon = 'id-card',
        fields = {
            { name = 'cid', type = 'number', label = 'Player CID', placeholder = 'Enter player Citizen ID (CID)', isRequired = true }
        }
    })

    if not input or not input.cid then return end

    local cid = tonumber(input.cid)
    if not cid then
        Notify('Invalid CID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:checkJailTime', cid)
end)

RegisterNetEvent('Vikto:Admin:ChangeCIDMenu', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Change Player CID',
        icon = 'id-card-clip',
        fields = {
            { name = 'id',     type = 'text',   label = 'Player ID or CID', placeholder = 'Enter Server ID or current CID', isRequired = true },
            { name = 'newcid', type = 'number', label = 'New CID',          placeholder = 'Enter the new CID',              isRequired = true }
        }
    })

    if not input or not input.id or not input.newcid then return end

    local confirmed1 = exports['FL-F1Menu']:ShowPrompt('Confirm CID Change (1/3)',
        'Are you sure you want to change CID for ' .. input.id .. ' to ' .. input.newcid .. '?', 'Next', 'Cancel',
        'id-card-clip')
    if not confirmed1 then return end

    local confirmed2 = exports['FL-F1Menu']:ShowPrompt('Confirm CID Change (2/3)', 'متاكد تبي تغيرله الايدي ؟؟ ',
        'Continue', 'Cancel', 'id-card-clip')
    if not confirmed2 then return end

    local confirmed3 = exports['FL-F1Menu']:ShowPrompt('Confirm CID Change (3/3)', 'صامل صامل مره تبي تغيره',
        'Change Now', 'Cancel', 'id-card-clip')
    if not confirmed3 then return end

    TriggerServerEvent('Vikto:Admin:Server:ChangeCID', input.id, tonumber(input.newcid))
end)

RegisterNetEvent('Vikto:Admin:CheckCIDMenu', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Check Player CID',
        icon = 'magnifying-glass',
        fields = {
            { name = 'cid', type = 'number', label = 'Citizen ID (CID)', placeholder = 'Enter the CID to check', isRequired = true }
        }
    })

    if not input or not input.cid then return end

    TriggerServerEvent('Vikto:Admin:Server:CheckCID', tonumber(input.cid))
end)

RegisterNetEvent('Vikto:Admin:DeleteCIDMenu', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Delete Player CID',
        icon = 'trash-can',
        fields = {
            { name = 'cid', type = 'number', label = 'Citizen ID (CID)', placeholder = 'Enter the CID to delete', isRequired = true }
        }
    })

    if not input or not input.cid then return end

    local confirmed1 = exports['FL-F1Menu']:ShowPrompt('Confirm Deletion (1/5)',
        'Are you sure you want to delete CID ' .. input.cid .. '?', 'Next', 'Cancel', 'trash-can')
    if not confirmed1 then return end

    local confirmed2 = exports['FL-F1Menu']:ShowPrompt('Confirm Deletion (2/5)',
        'للمعلوميه بس اذا مسحت ايديه كل شي يروح منه حتى ايتمات المتجر', 'ادري', 'لا', 'trash-can')
    if not confirmed2 then return end

    local confirmed3 = exports['FL-F1Menu']:ShowPrompt('Confirm Deletion (3/5)', 'صامل صامل مره تبي تمسح ايديه ؟',
        'يب صامل ', 'لا', 'trash-can')
    if not confirmed3 then return end

    local confirmed4 = exports['FL-F1Menu']:ShowPrompt('Confirm Deletion (4/5)', 'تأكد مره ثانيه تبي تمسح ايديه ؟',
        'متاكد', 'لا', 'trash-can')
    if not confirmed4 then return end

    local confirmed5 = exports['FL-F1Menu']:ShowPrompt('FINAL CONFIRMATION (5/5)', 'شكلك حاقد عليه تبي تمسح ايديه ؟',
        'يب حاقد', 'لا', 'trash-can')
    if not confirmed5 then return end

    TriggerServerEvent('Vikto:Admin:Server:DeleteCID', tonumber(input.cid))
end)

RegisterNetEvent('Vikto:Admin:ResetCIDMenu', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Reset Player CID',
        icon = 'sync',
        fields = {
            { name = 'id', type = 'text', label = 'Player ID or CID', placeholder = 'Enter Server ID or current CID', isRequired = true }
        }
    })

    if not input or not input.id then return end

    local confirmed1 = exports['FL-F1Menu']:ShowPrompt('Confirm CID Reset (1/3)',
        'Are you sure you want to reset the CID for ' .. input.id .. '?', 'Next', 'Cancel', 'sync')
    if not confirmed1 then return end

    local confirmed2 = exports['FL-F1Menu']:ShowPrompt('Confirm CID Reset (2/3)',
        'تره بيروح ايديه بس الداتا حقته نفسها يعني ما يروح منه شي', 'ادري', 'لا', 'sync')
    if not confirmed2 then return end

    local confirmed3 = exports['FL-F1Menu']:ShowPrompt('Confirm CID Reset (3/3)', 'صامل صامل مره تبي ترست ايديه ؟',
        'يب صامل ', 'لا', 'sync')
    if not confirmed3 then return end

    TriggerServerEvent('Vikto:Admin:Server:ResetCID', input.id)
end)

RegisterNetEvent('Vikto:Admin:AddHours', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Add Playtime (Minutes)',
        icon = 'clock',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Amount (Minutes)', placeholder = 'Enter minutes to add',              min = 1,          defaultValue = 30, isRequired = true }
        }
    })

    if not input or not input.serverId or not input.amount then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:addHours', serverId, input.amount)
end)

RegisterNetEvent('Vikto:Admin:RemoveHours', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Remove Playtime (Minutes)',
        icon = 'clock',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Amount (Minutes)', placeholder = 'Enter minutes to remove',           min = 1,          defaultValue = 30, isRequired = true }
        }
    })

    if not input or not input.serverId or not input.amount then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:removeHours', serverId, input.amount)
end)

RegisterNetEvent('Vikto:Admin:ResetHours', function()
    if not ViktoIsAdmin() then return end
    local alert = lib.alertDialog({
        header = 'Reset All Hours',
        content = 'Are you sure you want to reset ALL player playtime hours? This cannot be undone.',
        centered = true,
        cancel = true
    })

    if alert == 'confirm' then
        TriggerServerEvent('vikto_admin:server:resetAllHours')
    end
end)

RegisterNetEvent('Vikto:Admin:ViewHours', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'View Playtime',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true }
        }
    })

    if not input or not input.serverId then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:viewPlayerHours', serverId)
end)

RegisterNetEvent('Vikto:Admin:SendHoursLeaderboard', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('vikto_admin:server:sendHoursLeaderboard')
end)

RegisterNetEvent('vikto_admin:client:vehicleSpawned', function(netId, plate)
    local veh = NetToVeh(netId)

    if veh and veh ~= 0 then
        SetVehicleEngineOn(veh, true, true, false)

        TriggerEvent('vehiclekeys:client:SetOwner', plate)

        if Config.Debug then
            print('[VIKTO ADMIN CLIENT] Vehicle spawned with plate: ' .. plate)
        end
    end
end)

RegisterNetEvent('vikto_admin:client:spawnVehicle', function(args)
    if not ViktoIsAdmin() then return end
    local vehicleModel = nil

    if args and args[1] then
        vehicleModel = args[1]
    else
        local input = exports['FL-F1Menu']:OpenPrompt({
            title = 'Spawn Vehicle',
            icon = 'car',
            fields = {
                { name = 'model', type = 'text', label = 'Vehicle Model', placeholder = 'Enter vehicle spawn name', isRequired = true }
            }
        })

        if not input or not input.model then return end
        vehicleModel = input.model
    end

    if not vehicleModel then return end

    QBCore.Functions.TriggerCallback('vikto_admin:server:spawnVehicle', function(success)
        if success then
            Notify('Vehicle spawned successfully!', 'success')
        else
            Notify('Failed to spawn vehicle!', 'error')
        end
    end, vehicleModel)
end)

RegisterNetEvent('vikto_admin:client:deleteVehicle', function()
    if not ViktoIsAdmin() then return end
    local playerPed = cache.ped
    local vehicle = GetVehiclePedIsIn(playerPed, false)

    if vehicle == 0 then
        Notify('You must be in a vehicle!', 'error')
        return
    end

    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local plate = GetVehicleNumberPlateText(vehicle)

    DeleteEntity(vehicle)
    Notify('Vehicle deleted!', 'success')

    TriggerServerEvent('vikto_admin:server:logDeleteVehicle', model, plate)
end)

RegisterNetEvent('vikto_admin:client:fixVehicle', function()
    if not ViktoIsAdmin() then return end
    local playerPed = cache.ped
    local vehicle = GetVehiclePedIsIn(playerPed, false)

    if vehicle == 0 then
        Notify('You must be in a vehicle!', 'error')
        return
    end

    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local plate = GetVehicleNumberPlateText(vehicle)

    SetVehicleFixed(vehicle)
    SetVehicleDeformationFixed(vehicle)
    SetVehicleUndriveable(vehicle, false)
    SetVehicleEngineOn(vehicle, true, true)
    SetVehicleDirtLevel(vehicle, 0.0)
    Notify('Vehicle fixed!', 'success')

    TriggerServerEvent('vikto_admin:server:logFixVehicle', model, plate)
end)

RegisterNetEvent('Vikto:Admin:ChangePlate', function()
    if not ViktoIsAdmin() then return end
    local playerPed = cache.ped
    local vehicle = GetVehiclePedIsIn(playerPed, false)

    if vehicle == 0 then
        Notify('You must be in a vehicle!', 'error')
        return
    end

    local oldPlate = GetVehicleNumberPlateText(vehicle)
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))

    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Change Vehicle Plate',
        icon = 'id-card',
        fields = {
            { name = 'plate', type = 'text', label = 'New Plate', placeholder = 'Enter new plate number (max 8 chars)', maxLength = 8, isRequired = true }
        }
    })

    if not input or not input.plate then return end

    local newPlate = input.plate
    SetVehicleNumberPlateText(vehicle, newPlate)
    Notify('Plate changed to: ' .. newPlate, 'success')

    TriggerServerEvent('vikto_admin:server:logChangePlate', oldPlate, newPlate, model)
end)

RegisterNetEvent('Vikto:Admin:AddPoints', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Add Points',
        icon = 'plus',
        fields = {
            { name = 'playerId', type = 'number', label = 'Player ID',     placeholder = 'Enter player server ID', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Points Amount', placeholder = 'Enter points to add',    min = 1,          max = 999999, defaultValue = 1, isRequired = true }
        }
    })

    if not input or not input.playerId or not input.amount then return end

    local playerId = tonumber(input.playerId)
    if not playerId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:addPoints', playerId, input.amount)
end)

RegisterNetEvent('Vikto:Admin:RemovePoints', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Remove Points',
        icon = 'minus',
        fields = {
            { name = 'playerId', type = 'number', label = 'Player ID',     placeholder = 'Enter player server ID', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Points Amount', placeholder = 'Enter points to remove', min = 1,          max = 999999, defaultValue = 1, isRequired = true }
        }
    })

    if not input or not input.playerId or not input.amount then return end

    local playerId = tonumber(input.playerId)
    if not playerId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:removePoints', playerId, input.amount)
end)

RegisterNetEvent('Vikto:Admin:RemoveAllPoints', function()
    if not ViktoIsAdmin() then return end

    local confirm = lib.alertDialog({
        header = 'Confirm Global Points Reset',
        content =
        'Are you sure you want to reset ALL points for ALL players? This action is irreversible and will set everyone\'s balance to 0.',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Yes, Reset All',
            cancel = 'Cancel'
        }
    })

    if confirm == 'confirm' then
        TriggerServerEvent('vikto_admin:server:resetAllPoints')
    end
end)

RegisterNetEvent('Vikto:Admin:ViewPlayerPoints', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'View Player Points',
        icon = 'user',
        fields = {
            { name = 'playerId', type = 'number', label = 'Player ID', placeholder = 'Enter player server ID', isRequired = true }
        }
    })

    if not input or not input.playerId then return end

    local playerId = tonumber(input.playerId)
    if not playerId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:viewPlayerPoints', playerId)
end)

RegisterNetEvent('Vikto:Admin:SendLeaderboard', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('vikto_admin:server:sendLeaderboard')
end)

RegisterNetEvent('Vikto:Admin:CopyVector2', function()
    if not ViktoIsAdmin() then return end
    local playerPed = cache.ped
    local coords = GetEntityCoords(playerPed)
    local vec2 = string.format("vector2(%.2f, %.2f)", coords.x, coords.y)

    lib.setClipboard(vec2)
    Notify('Copied: ' .. vec2, 'success')

    if Config.Debug then
        print('[VIKTO ADMIN] Copied Vector2: ' .. vec2)
    end
end)

RegisterNetEvent('Vikto:Admin:CopyVector3', function()
    if not ViktoIsAdmin() then return end
    local playerPed = cache.ped
    local coords = GetEntityCoords(playerPed)
    local vec3 = string.format("vector3(%.2f, %.2f, %.2f)", coords.x, coords.y, coords.z)

    lib.setClipboard(vec3)
    Notify('Copied: ' .. vec3, 'success')

    if Config.Debug then
        print('[VIKTO ADMIN] Copied Vector3: ' .. vec3)
    end
end)

RegisterNetEvent('Vikto:Admin:CopyVector4', function()
    if not ViktoIsAdmin() then return end
    local playerPed = cache.ped
    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    local vec4 = string.format("vector4(%.2f, %.2f, %.2f, %.2f)", coords.x, coords.y, coords.z, heading)

    lib.setClipboard(vec4)
    Notify('Copied: ' .. vec4, 'success')

    if Config.Debug then
        print('[VIKTO ADMIN] Copied Vector4: ' .. vec4)
    end
end)

RegisterNetEvent('Vikto:Admin:CopyHeading', function()
    if not ViktoIsAdmin() then return end
    local playerPed = cache.ped
    local heading = GetEntityHeading(playerPed)
    local headingStr = string.format("%.2f", heading)

    lib.setClipboard(headingStr)
    Notify('Copied: ' .. headingStr, 'success')

    if Config.Debug then
        print('[VIKTO ADMIN] Copied Heading: ' .. headingStr)
    end
end)

AdminMenuState = {
    isOpen = false,
    menus = {},
    currentMenuId = nil,
    selectedIndex = 1,
    history = {},
    inputMode = 'mouse',
    altCursorActive = false,
    nextMoveTime = 0,
    playerModalActions = nil
}

local function SanitizeMenuId(value)
    local id = tostring(value or 'menu'):lower():gsub('%s+', '_'):gsub('[^%w_%-]', '')
    return id ~= '' and id or 'menu'
end

RefreshAdminMenuUi = function()
    if not AdminMenuState.isOpen or not AdminMenuState.currentMenuId then
        return
    end

    local menu = AdminMenuState.menus[AdminMenuState.currentMenuId]
    if not menu or not menu.items then
        return
    end

    if #menu.items == 0 then
        AdminMenuState.selectedIndex = 1
    elseif AdminMenuState.selectedIndex > #menu.items then
        AdminMenuState.selectedIndex = #menu.items
    elseif AdminMenuState.selectedIndex < 1 then
        AdminMenuState.selectedIndex = 1
    end

    if Config.Debug then
        print(string.format('[VIKTO ADMIN] Sending adminMenuUpdate: %s (Items: %d)', menu.title, #menu.items))
    end

    SendNUIMessage({
        action = 'adminMenuUpdate',
        title = menu.title or 'Admin Menu',
        subtitle = '',
        items = menu.items,
        selected = AdminMenuState.selectedIndex,
        canGoBack = #AdminMenuState.history > 0,
        inputMode = AdminMenuState.inputMode
    })
end

ApplyAdminMenuInputMode = function()
    if not AdminMenuState.isOpen then
        return
    end

    local keepInput = not AdminMenuState.isTyping

    if AdminMenuState.inputMode == 'mouse' then
        SetNuiFocus(true, true)

        SetNuiFocusKeepInput(false)
        AdminMenuState.altCursorActive = false
    else
        if AdminMenuState.altCursorActive then
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(keepInput)
        else

            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
        end
    end
end

IsAdminMenuFocusActive = function()
    if AdminMenuState.inputMode == 'mouse' then
        return true
    end

    if AdminMenuState.inputMode == 'arrows' and AdminMenuState.altCursorActive then
        return true
    end

    return false
end

local function SetAdminMenuInputMode(mode, notify)
    if mode ~= 'mouse' and mode ~= 'arrows' then
        mode = AdminMenuState.inputMode == 'mouse' and 'arrows' or 'mouse'
    end

    AdminMenuState.inputMode = mode
    SetResourceKvp('tg_admin_menu_mode', mode)

    if AdminMenuState.isOpen then
        ApplyAdminMenuInputMode()
        RefreshAdminMenuUi()
    end
end

local function OpenAdminMenu(menuId, pushHistory, startTab)
    local menu = AdminMenuState.menus[menuId]
    if not menu then
        return
    end

    if pushHistory and AdminMenuState.currentMenuId then
        table.insert(AdminMenuState.history, {
            menuId = AdminMenuState.currentMenuId,
            selectedIndex = AdminMenuState.selectedIndex
        })
    end

    AdminMenuState.currentMenuId = menuId
    AdminMenuState.selectedIndex = 1
    AdminMenuState.isOpen = true
    ApplyAdminMenuInputMode()

    if Config.Debug then
        print(string.format('[VIKTO ADMIN] Opening Menu: %s (startTab: %s)', menuId, tostring(startTab)))
    end

    SendNUIMessage({
        action = 'adminMenuOpen',
        startTab = startTab,
        toggleTabKey = 'CapsLock',
        modalConfig = AdminMenuCache.modalActions or Config.PlayerModalActions
    })
    RefreshAdminMenuUi()
end

local function CloseAdminMenu()
    if not AdminMenuState.isOpen then
        return
    end

    AdminMenuState.isOpen = false
    AdminMenuState.currentMenuId = nil
    AdminMenuState.selectedIndex = 1
    AdminMenuState.history = {}
    AdminMenuState.altCursorActive = false
    AdminMenuState.nextMoveTime = 0
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)

    TriggerServerEvent('vikto_admin:server:setMenuOpen', false)

    SendNUIMessage({
        action = 'adminMenuClose'
    })
end

GoBackAdminMenu = function()
    if #AdminMenuState.history == 0 then
        CloseAdminMenu()
        return
    end

    local previous = table.remove(AdminMenuState.history)
    AdminMenuState.currentMenuId = previous.menuId
    AdminMenuState.selectedIndex = previous.selectedIndex or 1
    RefreshAdminMenuUi()
end

local function CalculateDurationInMinutes(value, unit)
    if unit == 'p' then return 0 end
    local val = tonumber(value) or 0
    if unit == 'm' then
        return val
    elseif unit == 'h' then
        return val * 60
    elseif unit == 'd' then
        return val * 1440
    elseif unit == 'w' then
        return val * 10080
    elseif unit == 'month' then
        return val * 43200
    end
    return val
end

TriggerMenuItemAction = function(item)
    if not item then return end

    if Config.Debug then
        TriggerServerEvent('vikto_admin:server:debugAction', item.title or 'Unknown', item.event or 'None')
        print(string.format('[VIKTO ADMIN] Menu Action triggered: %s (Event: %s, Command: %s, TargetMenu: %s)',
            tostring(item.title), tostring(item.event), tostring(item.command), tostring(item.targetMenu)))
    end

    if item.targetMenu then
        OpenAdminMenu(item.targetMenu, true)
        return
    end

    if item.special == 'teleport_locations' then
        OpenTeleportLocationsMenu()
        return
    end

    if item.event then
        if item.args ~= nil then
            TriggerEvent(item.event, item.args)
        else
            TriggerEvent(item.event)
        end
    elseif item.command and item.command ~= '' then
        ExecuteCommand(item.command)
    end
end

local function BuildMenusFromCategories(categories)
    AdminMenuState.menus = {}

    local mainMenu = {
        id = 'main',
        title = 'MTG ADMIN',
        subtitle = 'MTG Fights',
        items = {}
    }

    for _, category in ipairs(categories or {}) do
        local categoryId = 'category_' .. SanitizeMenuId(category.title)
        local categoryItems = {}

        for _, option in ipairs(category.options or {}) do
            local entry = {
                title = option.title or 'Unknown',
                description = option.description or '',
                icon = option.icon or 'fa-solid fa-circle',
                event = option.event,
                args = option.args,
                command = option.command,
                targetMenu = option.targetMenu
            }

            if option.event == 'Vikto:Admin:TeleportLocations' then
                entry.special = 'teleport_locations'
                entry.event = nil
            end

            table.insert(categoryItems, entry)
        end

        AdminMenuState.menus[categoryId] = {
            id = categoryId,
            title = category.title or 'Category',
            subtitle = '',
            items = categoryItems
        }

        if not category.hidden then
            if category.title == 'Quick Options' then
                for _, entry in ipairs(categoryItems) do
                    table.insert(mainMenu.items, entry)
                end
            else
                table.insert(mainMenu.items, {
                    title = category.title or 'Category',
                    description = category.description or '',
                    icon = category.icon or 'fa-solid fa-folder',
                    targetMenu = categoryId
                })
            end
        end
    end

    AdminMenuState.menus.main = mainMenu
end

OpenTeleportLocationsMenu = function()
    local menuId = 'teleport_locations'
    local items = {}

    for _, location in ipairs(Config.TeleportLocations or {}) do
        table.insert(items, {
            title = location.name,
            description = 'Teleport to ' .. location.name,
            icon = location.icon or 'fa-solid fa-location-dot',
            event = 'vikto_admin:client:menuTeleportToLocation',
            args = {
                x = location.coords.x,
                y = location.coords.y,
                z = location.coords.z,
                w = location.coords.w,
                name = location.name
            }
        })
    end

    AdminMenuState.menus[menuId] = {
        id = menuId,
        title = 'Teleport Locations',
        subtitle = '',
        items = items
    }

    OpenAdminMenu(menuId, true)
end

RegisterNetEvent('vikto_admin:client:menuTeleportToLocation', function(data)
    if not ViktoIsAdmin() then return end
    if not data then return end

    SetEntityCoords(cache.ped, data.x, data.y, data.z, false, false, false, false)
    SetEntityHeading(cache.ped, data.w or 0.0)
    Notify('Teleported successfully!', 'success')
    TriggerServerEvent('vikto_admin:server:logTeleportLocation', vector4(data.x, data.y, data.z, data.w or 0.0),
        data.name or 'Unknown')
end)

local function BuildAdminMenu(callback)
    if IsCacheValid() then
        BuildMenusFromCategories(AdminMenuCache.categories)
        if callback then callback() end
        return
    end

    QBCore.Functions.TriggerCallback('vikto_admin:server:getMenuCategories', function(allowedCategories, allowedModalActions)
        if not allowedCategories or #allowedCategories == 0 then
            Notify('You do not have permission to access the admin menu!', 'error')
            return
        end

        UpdateCache(allowedCategories, allowedModalActions)
        BuildMenusFromCategories(allowedCategories)
        if callback then callback() end
    end)
end

local function OpenMainAdminMenu()
    if GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:isInMatch() then
        Notify('You cannot open the admin menu during a match!', 'error')
        return
    end
    if IsBlockedInPursuitMatch() then
        Notify('You cannot open the admin menu during Pursuits!', 'error')
        return
    end
    if GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
        if not exports['FL-Sprays']:IsGangManager() then
            Notify('You cannot open the admin menu during a gang world!', 'error')
            return
        end
    end

    if IsBlockedInGangLabsWorld() then
        Notify('You cannot open the admin menu during Gang Labs!', 'error')
        return
    end
    BuildAdminMenu(function()
        OpenAdminMenu('main', false)
    end)
end

CreateThread(function()
    Wait(1000)

    local savedMode = GetResourceKvpString('tg_admin_menu_mode')
    if savedMode == 'mouse' or savedMode == 'arrows' then
        AdminMenuState.inputMode = savedMode
        if Config.Debug then
            print('[VIKTO ADMIN] Loaded saved menu mode: ' .. savedMode)
        end
    end

    RegisterKeybinds()
end)

function RegisterKeybinds()
    for _, category in ipairs(Config.AdminMenuCategories) do
        for _, option in ipairs(category.options) do
            if option.keybind and option.keybind ~= '' and option.event then
                lib.addKeybind({
                    name = 'vikto_' .. option.title:gsub('%s+', '_'):lower(),
                    description = option.title,
                    defaultKey = option.keybind,
                    onPressed = function()
                        if GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:isInMatch() then
                            Notify('You cannot use admin keybinds during a match!', 'error')
                            return
                        end
                        if IsBlockedInPursuitMatch() then
                            Notify('You cannot use admin keybinds during Pursuits!', 'error')
                            return
                        end
                        if GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
                            if not exports['FL-Sprays']:IsGangManager() then
                                Notify('You cannot use admin keybinds during a Gang World!', 'error')
                                return
                            end
                        end
                        if IsBlockedInGangLabsWorld() then
                            Notify('You cannot use admin keybinds during Gang Labs!', 'error')
                            return
                        end
                        if GetResourceState('FL-Truck') == 'started' and exports['FL-Truck']:IsOnJob() then
                            Notify('You cannot use admin keybinds while on a truck!', 'error')
                            return
                        end
                        TriggerServerEvent('vikto_admin:server:checkOptionPermission', {
                            event = option.event,
                            permission = option.permission,
                            args = option.args
                        })
                    end
                })

            end
        end
    end

    TriggerEvent('chat:addSuggestion', '/' .. Config.AdminMenu.Command, 'Open Admin Menu', {
        { name = "cid", help = "(Optional) Player CID or Name to open modal" }
    })
    TriggerEvent('chat:addSuggestion', '/' .. Config.AdminMenu.Command2, 'Open Admin Menu', {
        { name = "cid", help = "(Optional) Player CID or Name to open modal" }
    })
    TriggerEvent('chat:addSuggestion', '/' .. Config.AdminMenu.PlayersCommand, 'Open Admin Players List')
    TriggerEvent('chat:addSuggestion', '/' .. Config.AdminMenu.RecordsCommand, 'Open Admin Records List')

    lib.addKeybind({
        name = 'admin_toggle_tabs',
        description = 'Switch Admin Menu Tabs',
        defaultKey = 'CAPITAL',
        onPressed = function()
            if AdminMenuState.isOpen then
                SendNUIMessage({ action = 'toggleTabs' })
            end
        end
    })
end

RegisterNetEvent('vikto_admin:client:openMenu', function()
    if GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:isInMatch() then
        Notify('You cannot open the admin menu during a match!', 'error')
        return
    end
    if IsBlockedInPursuitMatch() then
        Notify('You cannot open the admin menu during Pursuits!', 'error')
        return
    end
    if GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
        Notify('You cannot open the admin menu during a gang world!', 'error')
        return
    end
    if IsBlockedInGangLabsWorld() then
        Notify('You cannot open the admin menu during Gang Labs!', 'error')
        return
    end
    OpenMainAdminMenu()
end)

RegisterNetEvent('vikto_admin:client:openPanel', function(players)
    local startTab = 'main'
    if players and #players > 0 then
        startTab = 'players'
    end
    BuildAdminMenu(function()
        OpenAdminMenu('main', false, startTab)
    end)
end)

RegisterNetEvent('vikto_admin:client:openRecords', function()
    BuildAdminMenu(function()
        OpenAdminMenu('main', false, 'records')
    end)
end)

RegisterNetEvent('vikto_admin:client:openPlayerModal', function(playerData)
    if not playerData then return end

    -- Fallback for modal action configurations
    local modalConfig = playerData.modalConfig or AdminMenuCache.modalActions or Config.PlayerModalActions

    -- Filter actions if permission check (canAct) returns false
    if playerData.canAct == false then
        local filtered = {}
        for _, category in ipairs(modalConfig) do
            if category.category == "Quick Actions" or category.category == "Utilities" then
                filtered[#filtered + 1] = category
            end
        end
        modalConfig = filtered
    end

    -- Send NUI Payload with both 'id' and 'serverId' for total NUI compatibility
    SendNUIMessage({
        action = "openPlayerModal",
        id = playerData.id or playerData.serverId,            -- Ensures frontend reads player ID
        serverId = playerData.serverId or playerData.id,      -- Backup key for secondary components
        cid = playerData.cid,
        name = playerData.name,
        identifiers = playerData.identifiers or {},          -- Fixes search bar filter
        playtime = playerData.playtime or "0h 0m",            -- Fixes playtime counter
        modalConfig = modalConfig
    })
end)

RegisterNetEvent('vikto_admin:client:historyUpdate', function(cid, item)
    SendNUIMessage({
        action = "historyUpdate",
        cid = cid,
        item = item
    })
end)

RegisterNetEvent('vikto_admin:client:openMenuWithData', function(allowedCategories, allowedModalActions, startTab)
    if GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:isInMatch() then
        Notify('You cannot open the admin menu during a match!', 'error')
        return
    end
    if IsBlockedInPursuitMatch() then
        Notify('You cannot open the admin menu during Pursuits!', 'error')
        return
    end
    if GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
        Notify('You cannot open the admin menu during a gang world!', 'error')
        return
    end
    if IsBlockedInGangLabsWorld() then
        Notify('You cannot open the admin menu during Gang Labs!', 'error')
        return
    end
    if not allowedCategories or #allowedCategories == 0 then
        Notify('You do not have permission to access the admin menu!', 'error')
        return
    end

    UpdateCache(allowedCategories, allowedModalActions)
    BuildMenusFromCategories(allowedCategories)
    OpenAdminMenu('main', false, startTab)
end)

RegisterNUICallback('adminMenuSelect', function(data, cb)
    if not AdminMenuState.isOpen then
        cb('ok')
        return
    end

    local currentMenu = AdminMenuState.menus[AdminMenuState.currentMenuId]
    local itemCount = currentMenu and #currentMenu.items or 0
    if itemCount == 0 then
        cb('ok')
        return
    end

    local index = tonumber(data and data.index)
    if index and index >= 1 and index <= itemCount then
        AdminMenuState.selectedIndex = index
    end

    RefreshAdminMenuUi()
    TriggerMenuItemAction(currentMenu.items[AdminMenuState.selectedIndex])
    cb('ok')
end)

local LOCAL_PLAYERLIST = {}
local maxPlayersLimit = 48

RegisterNUICallback('getPlayers', function(data, cb)

    TriggerServerEvent('vikto_admin:server:setMenuOpen', true)
    cb('ok')
end)

RegisterNUICallback('signalPlayersPageOpen', function(data, cb)

    QBCore.Functions.TriggerCallback('vikto_admin:server:getPlayers', function(result)
        if result then
            if result.maxPlayers then
                maxPlayersLimit = result.maxPlayers
            end
            SendNUIMessage({
                action = "setPlayerList",
                players = result.players or {},
                maxPlayers = maxPlayersLimit,
            })
        end
    end)
    cb({})
end)

RegisterNUICallback('getTxAdminPlayers', function(data, cb)
    TriggerServerEvent('vikto_admin:server:getTxAdminPlayers', data)
    cb('ok')
end)

RegisterNUICallback('getGlobalHistory', function(data, cb)
    TriggerServerEvent('vikto_admin:server:getGlobalHistory', data)
    cb('ok')
end)

RegisterNetEvent('vikto_admin:client:receiveTxAdminPlayers', function(data)
    if Config.Debug then
        local count = 0
        if data and data.players then count = #data.players end
        print('[VIKTO ADMIN] Client received receiveTxAdminPlayers, count: ' .. count)
    end

    SendNUIMessage({
        action  = 'receiveTxAdminPlayers',
        players = data and data.players or {},
        total   = data and data.total or 0,
        page    = data and data.page or 1,
        isSearch = data and data.isSearch or false
    })
end)

RegisterNetEvent('vikto_admin:client:receiveGlobalHistory', function(data)
    if Config.Debug then print('[VIKTO ADMIN] Client received receiveGlobalHistory, count: ' ..
        (data and data.history and #data.history or 0) .. ' total: ' .. (data and data.total or 0)) end
    SendNUIMessage({
        action   = 'receiveGlobalHistory',
        history  = data and data.history  or {},
        total    = data and data.total    or 0,
        page     = data and data.page     or 1,
        pageSize = data and data.pageSize or 20,
    })
end)

RegisterNUICallback('adminPlayerAction', function(data, cb)
    local targetServerId = tonumber(data.id)
    local targetCid = data.cid
    local event = data.event

    if not event or (not targetServerId and not targetCid) then
        cb('ok')
        return
    end

    if not targetCid then
        targetCid = targetServerId
    end

    if Config.Debug then
        print(string.format('[VIKTO ADMIN] Executing modal action: %s for serverId: %s, cid: %s', event, tostring(targetServerId),
            tostring(targetCid)))
    end

    TriggerEvent('Vikto:Admin:ExecuteModalAction', event, targetCid)

    cb('ok')
end)

RegisterNUICallback('adminMenuHover', function(data, cb)
    if not AdminMenuState.isOpen then
        cb('ok')
        return
    end

    local currentMenu = AdminMenuState.menus[AdminMenuState.currentMenuId]
    local itemCount = currentMenu and #currentMenu.items or 0
    local index = tonumber(data and data.index)
    if index and itemCount > 0 and index >= 1 and index <= itemCount and index ~= AdminMenuState.selectedIndex then
        AdminMenuState.selectedIndex = index
        RefreshAdminMenuUi()
    end

    cb('ok')
end)

RegisterNUICallback('adminMenuBack', function(_, cb)
    if AdminMenuState.isOpen then
        GoBackAdminMenu()
    end
    cb('ok')
end)

RegisterNUICallback('adminMenuClose', function(_, cb)
    CloseAdminMenu()
    cb('ok')
end)

RegisterNUICallback('adminMenuToggleInput', function(data, cb)
    SetAdminMenuInputMode(data and data.mode)
    cb('ok')
end)

RegisterNUICallback('openPlayerModalByCid', function(data, cb)
    if data and data.cid then
        TriggerServerEvent('vikto_admin:server:openPlayerModalByCid', data.cid)
    end
    cb('ok')
end)

RegisterNUICallback('setTypingState', function(data, cb)
    AdminMenuState.isTyping = data and data.isTyping or false
    ApplyAdminMenuInputMode()
    cb('ok')
end)

RegisterNUICallback('adminMenuToggleFocus', function(data, cb)
    AdminMenuState.isTyping = data.active
    ApplyAdminMenuInputMode()
    cb('ok')
end)

RegisterNUICallback('fetchHistoryMore', function(data, cb)
    TriggerServerEvent('vikto_admin:server:fetchHistoryMore', data.cid, data.offset, data.filter)
    cb('ok')
end)

lib.addKeybind({
    name = 'admin_menu_confirm',
    description = 'Admin Menu Confirm',
    defaultKey = 'RETURN',
    onPressed = function()
        if not AdminMenuState.isOpen then return end
        if AdminMenuState.inputMode ~= 'arrows' then return end
        if AdminMenuState.altCursorActive then return end

        local currentMenu = AdminMenuState.menus[AdminMenuState.currentMenuId]
        local itemCount = currentMenu and #currentMenu.items or 0
        if itemCount > 0 then
            TriggerMenuItemAction(currentMenu.items[AdminMenuState.selectedIndex])
        end
    end
})

local function OpenMainAdminMenu(_, args)
    if GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:IsInMatch() then
        Notify('You cannot open the admin menu during a match!', 'error')
        return
    end
    if IsBlockedInPursuitMatch() then
        Notify('You cannot open the admin menu during Pursuits!', 'error')
        return
    end
    if GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
        Notify('You cannot open the admin menu during a gang world!', 'error')
        return
    end
    if IsBlockedInGangLabsWorld() then
        Notify('You cannot open the admin menu during Gang Labs!', 'error')
        return
    end
    if GetResourceState('FL-Truck') == 'started' and exports['FL-Truck']:IsOnJob() then
        Notify('You cannot open the admin menu while on a truck!', 'error')
        return
    end

    if args and args[1] then
        QBCore.Functions.TriggerCallback('vikto_admin:server:getTargetInfo', function(targetData)
            if targetData then
                TriggerServerEvent('vikto_admin:server:checkPermission', 'playerModal', targetData)
            else
                Notify('Player not found!', 'error')
            end
        end, args[1])
    else
        TriggerServerEvent('vikto_admin:server:checkPermission')
    end
end

RegisterCommand(Config.AdminMenu.Command, OpenMainAdminMenu, false)
RegisterCommand(Config.AdminMenu.Command2, OpenMainAdminMenu, false)

if Config.AdminMenu.Key then
    lib.addKeybind({
        name = Config.AdminMenu.Command,
        description = 'Open Admin Menu',
        defaultKey = Config.AdminMenu.Key,
        onPressed = OpenMainAdminMenu
    })
end

local function OpenPlayersAdminMenu()
    if GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:isInMatch() then
        Notify('You cannot open the players menu during a match!', 'error')
        return
    end
    if IsBlockedInPursuitMatch() then
        Notify('You cannot open the players menu during Pursuits!', 'error')
        return
    end
    if GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
        Notify('You cannot open the players menu during a gang world!', 'error')
        return
    end
    if IsBlockedInGangLabsWorld() then
        Notify('You cannot open the players menu during Gang Labs!', 'error')
        return
    end
    TriggerServerEvent('vikto_admin:server:checkPermission', 'players')
end

RegisterCommand(Config.AdminMenu.PlayersCommand, OpenPlayersAdminMenu, false)

if Config.AdminMenu.PlayersKey then
    lib.addKeybind({
        name = Config.AdminMenu.PlayersCommand,
        description = 'Open Admin Players List',
        defaultKey = Config.AdminMenu.PlayersKey,
        onPressed = OpenPlayersAdminMenu
    })
end

local function OpenRecordsAdminMenu()
    if GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:isInMatch() then
        Notify('You cannot open the records menu during a match!', 'error')
        return
    end
    if IsBlockedInPursuitMatch() then
        Notify('You cannot open the records menu during Pursuits!', 'error')
        return
    end
    if GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
        Notify('You cannot open the records menu during a gang world!', 'error')
        return
    end
    if IsBlockedInGangLabsWorld() then
        Notify('You cannot open the records menu during Gang Labs!', 'error')
        return
    end
    TriggerServerEvent('vikto_admin:server:checkPermission', 'records')
end

RegisterCommand(Config.AdminMenu.RecordsCommand, OpenRecordsAdminMenu, false)

if Config.AdminMenu.RecordsKey then
    lib.addKeybind({
        name = Config.AdminMenu.RecordsCommand,
        description = 'Open Admin Records List',
        defaultKey = Config.AdminMenu.RecordsKey,
        onPressed = OpenRecordsAdminMenu
    })
end

RegisterNetEvent('Vikto:Admin:SendEventLB', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('Vikto:Admin:SendEventLB')
end)

RegisterNetEvent('Vikto:Admin:UpdateEventLB', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('Vikto:Admin:UpdateEventLB')
end)

RegisterNetEvent('Vikto:Admin:SendReportsLB', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('Vikto:Admin:SendReportsLB')
end)

RegisterNetEvent('Vikto:Admin:UpdateReportsLB', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('Vikto:Admin:UpdateReportsLB')
end)

RegisterNetEvent('Vikto:Admin:SendHoursLB', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('Vikto:Admin:SendHoursLB')
end)

RegisterNetEvent('Vikto:Admin:UpdateHoursLB', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('Vikto:Admin:UpdateHoursLB')
end)

RegisterNetEvent('Vikto:Admin:SendStaffLB', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('Vikto:Admin:SendStaffLB')
end)

RegisterNetEvent('Vikto:Admin:UpdateStaffLB', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('Vikto:Admin:UpdateStaffLB')
end)

local Reports = {}

function ShowAdminReport(reportId, serverid, playerName, autoHideTime)
    local id = tonumber(reportId)
    Reports[id] = true
    SendNUIMessage({
        action = 'DrawText',
        Id = reportId,
        playerId = serverid,
        playerName = playerName or 'Unknown',
        autoHideTime = autoHideTime or 300,
        message = '[ ID: ' .. serverid .. ' ] ' .. (playerName or 'Unknown') .. ' ( Report #' .. reportId .. ' )',
    })
end

function HideAdminReport(reportId)
    Reports[reportId] = nil
    SendNUIMessage({
        action = 'HideDrawText',
        Id = reportId,
        type = 'Accept'
    })
end

RegisterNetEvent('adminreport:server:ShowReport', function(reportId, serverid, playerName, autoHideTime)
    ShowAdminReport(reportId, serverid, playerName, autoHideTime)
end)

RegisterNetEvent('adminreport:client:HideReport', function(reportId)
    local id = tonumber(reportId)
    if not Reports[id] then return end
    HideAdminReport(id)
end)

RegisterNetEvent('adminreport:client:MakeEffect', function(coords)
    local PTFX_DICT = 'core'
    local PTFX_ASSET = 'ent_dst_elec_fire_sp'
    local PTFX_SCALE = 1.75
    local PTFX_DURATION = 1500
    local LOOP_AMOUNT = 7
    local LOOP_DELAY = 75

    CreateThread(function()
        RequestNamedPtfxAsset(PTFX_DICT)
        while not HasNamedPtfxAssetLoaded(PTFX_DICT) do
            Wait(5)
        end

        local particleTbl = {}
        for i = 0, LOOP_AMOUNT do
            UseParticleFxAsset(PTFX_DICT)
            local partiResult = StartParticleFxLoopedAtCoord(
                PTFX_ASSET,
                coords.x, coords.y, coords.z,
                0.0, 0.0, 0.0,
                PTFX_SCALE,
                false, false, false
            )
            particleTbl[#particleTbl + 1] = partiResult
            Wait(LOOP_DELAY)
        end

        Wait(PTFX_DURATION)
        for _, parti in ipairs(particleTbl) do
            StopParticleFxLooped(parti, true)
        end
        RemoveNamedPtfxAsset(PTFX_DICT)
    end)
end)

lib.addKeybind({
    name = 'admin_accept_report',
    description = 'Accept Admin Report',
    defaultKey = 'F5',
    onPressed = function()
        SendNUIMessage({ action = "keyPressed", key = "F5" })
    end
})

lib.addKeybind({
    name = 'admin_reject_report',
    description = 'Reject Admin Report',
    defaultKey = 'F6',
    onPressed = function()
        SendNUIMessage({ action = "keyPressed", key = "F6" })
    end
})

RegisterNUICallback('AcceptReport', function(data, cb)
    local reportId = tonumber(data.Id)
    if reportId then
        TriggerServerEvent('adminreport:server:HideReport', 'Accept', reportId)
    else
        Notify('Invalid report ID.', 'error')
    end
    cb('ok')
end)

RegisterNUICallback('RejectReport', function(data, cb)
    local reportId = tonumber(data.Id)
    if reportId then
        TriggerServerEvent('adminreport:server:HideReport', 'Reject', reportId)
        SendNUIMessage({ action = "HideDrawText", Id = reportId, type = 'Reject' })
    else
        Notify('Invalid report ID.', 'error')
    end
    cb('ok')
end)

RegisterNUICallback('Notify', function(data, cb)
    Notify(data.message, data.type)
    cb('ok')
end)

RegisterNetEvent('adminreport:client:TeleportToCoords')
AddEventHandler('adminreport:client:TeleportToCoords', function(coords)
    local ped = PlayerPedId()
    if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    end
end)

RegisterNetEvent('Vikto:Admin:GiveNewID', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Change Player ID',
        icon = 'hashtag',
        fields = {
            { name = 'currentId', type = 'number', label = 'Current Player Server ID (Metadata)', placeholder = 'Enter the current server ID from metadata', isRequired = true },
            { name = 'newId',     type = 'number', label = 'New Server ID',                       placeholder = 'Enter the new server ID for this player',   isRequired = true }
        }
    })

    if not input or not input.currentId or not input.newId then return end

    local currentServerID = tonumber(input.currentId)
    local newID = tonumber(input.newId)

    if not currentServerID or not newID then
        Notify('Invalid input!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:changePlayerIDByMetadata', currentServerID, newID)
end)

RegisterNetEvent('Vikto:Admin:DeleteID', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Delete Player ID',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID (Metadata)', placeholder = 'Enter the server ID from metadata to remove', isRequired = true }
        }
    })

    if not input or not input.serverId then return end

    local currentServerID = tonumber(input.serverId)
    if not currentServerID then
        Notify('Invalid input!', 'error')
        return
    end

    local alert = lib.alertDialog({
        header = 'Confirm ID Deletion',
        content = 'Are you sure you want to DELETE the Server ID (' ..
            currentServerID .. ') for this player? This will remove it from metadata.',
        centered = true,
        cancel = true
    })

    if alert == 'confirm' then
        TriggerServerEvent('vikto_admin:server:deletePlayerIDByMetadata', currentServerID)
    end
end)

RegisterNetEvent('Vikto:Admin:ResetAllReports', function()
    if not ViktoIsAdmin() then return end
    local alert = lib.alertDialog({
        header = 'Reset All Admin Reports',
        content =
        'Are you sure you want to RESET ALL reports handled for ALL administrators? This action cannot be undone.',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'RESET ALL',
            cancel = 'Cancel'
        }
    })

    if alert == 'confirm' then
        TriggerServerEvent('vikto_admin:server:resetAllReports')
    end
end)

RegisterNetEvent('Vikto:Admin:Coins:Add', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Add Vikto Coins',
        icon = 'coins',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Coin Amount',      isRequired = true }
        }
    })

    if not input then return end

    local targetId = tonumber(input.serverId)
    local amount = tonumber(input.amount)

    TriggerServerEvent('vikto_admin:server:coins:add', targetId, amount)
end)

RegisterNetEvent('Vikto:Admin:Coins:Remove', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Remove Vikto Coins',
        icon = 'coins',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Coin Amount',      isRequired = true }
        }
    })

    if not input then return end

    local targetId = tonumber(input.serverId)
    local amount = tonumber(input.amount)

    TriggerServerEvent('vikto_admin:server:coins:remove', targetId, amount)
end)

RegisterNetEvent('Vikto:Admin:Coins:Check', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Check Vikto Coins',
        icon = 'coins',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', isRequired = true }
        }
    })

    if not input then return end

    local targetId = tonumber(input.serverId)

    TriggerServerEvent('vikto_admin:server:coins:check', targetId)
end)

RegisterNetEvent('Vikto:Admin:CheckID', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Check Player ID',
        icon = 'search',
        fields = {
            { name = 'checkId', type = 'number', label = 'Server ID', placeholder = 'Enter the server ID to check if it exists', isRequired = true }
        }
    })

    if not input or not input.checkId then return end

    local checkID = tonumber(input.checkId)
    if not checkID then
        Notify('Invalid ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:checkPlayerID', checkID)
end)

RegisterNetEvent('Vikto:Admin:GoToSpawn', function()
    if not ViktoIsAdmin() then return end

    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Teleport Player To Spawn',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', placeholder = 'Enter the server ID of the player', isRequired = true }
        }
    })

    if not input or not input.serverId then return end

    local serverId = tonumber(input.serverId)
    if not serverId then
        Notify('Invalid player ID!', 'error')
        return
    end

    TriggerServerEvent('vikto_admin:server:teleportPlayerToSpawn', serverId)
end)

local muteTextUIShown = false

RegisterNetEvent('Vikto:Admin:MutePlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Mute Player',
        icon = 'microphone-slash',
        fields = {
            { name = 'cid',   type = 'number', label = 'Player CID', placeholder = 'Enter the CID of the player to mute', isRequired = true },
            { name = 'value', type = 'number', label = 'Value',      min = 1,                                             isRequired = true, defaultValue = 1 },
            {
                name = 'unit',
                type = 'select',
                label = 'Unit',
                isRequired = true,
                options = {
                    { label = 'Minutes',   value = 'm' },
                    { label = 'Hours',     value = 'h' },
                    { label = 'Days',      value = 'd' },
                    { label = 'Weeks',     value = 'w' },
                    { label = 'Months',    value = 'month' },
                    { label = 'Permanent', value = 'p' }
                }
            },
            { name = 'reason', type = 'text', label = 'Reason', placeholder = 'Enter the reason for muting', isRequired = true }
        }
    })

    if not input or not input.cid then return end

    local cid = tonumber(input.cid)
    local value = tonumber(input.value) or 0
    local unit = input.unit
    local reason = input.reason or 'No reason provided'

    local totalMinutes = value
    if unit == 'p' then
        totalMinutes = 0
    elseif unit == 'h' then
        totalMinutes = value * 60
    elseif unit == 'd' then
        totalMinutes = value * 1440
    elseif unit == 'w' then
        totalMinutes = value * 10080
    elseif unit == 'month' then
        totalMinutes = value * 43200
    end

    if totalMinutes <= 0 and unit ~= 'p' then
        totalMinutes = Config.VoiceMute.DefaultDuration
    end

    TriggerServerEvent('vikto_admin:server:mutePlayer', cid, totalMinutes, reason)
    TriggerServerEvent('vikto_admin:server:muteChatPlayer', cid, totalMinutes, reason)
end)

RegisterNetEvent('Vikto:Admin:UnmutePlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Unmute Player',
        icon = 'microphone',
        fields = {
            { name = 'cid', type = 'number', label = 'Player CID', placeholder = 'Enter the CID of the player to unmute', isRequired = true }
        }
    })

    if not input or not input.cid then return end

    local cid = tonumber(input.cid)

    TriggerServerEvent('vikto_admin:server:unmutePlayer', cid)
    TriggerServerEvent('vikto_admin:server:unmuteChatPlayer', cid)
end)

FormatSmartTime = function(totalSeconds)
    local days = math.floor(totalSeconds / 86400)
    local hours = math.floor((totalSeconds % 86400) / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = math.floor(totalSeconds % 60)

    if days > 0 then
        if hours > 0 then
            return string.format("%d Days, %d Hours", days, hours)
        else
            return string.format("%d Days", days)
        end
    elseif hours > 0 then
        if minutes > 0 then
            return string.format("%d Hours, %d Mins", hours, minutes)
        else
            return string.format("%d Hours", hours)
        end
    elseif minutes > 0 then
        if seconds > 0 then
            return string.format("%d Mins, %d Secs", minutes, seconds)
        else
            return string.format("%d Mins", minutes)
        end
    else
        return string.format("%d Secs", seconds)
    end
end

muteUIShown = false
muteDuration = 0
muteStartTime = 0

RegisterNetEvent('vikto_admin:client:setMuted', function(muted, duration)
    isMuted = muted
    muteDuration = duration or 0
    muteStartTime = GetGameTimer()

    if muted then
        -- NOTE: this used to call overrideProximityCheck(function() return false end),
        -- which controls who THIS client can hear (proximity filtering on the
        -- listener's own end) — it does not stop this client's own mic from being
        -- heard by others. That's why muted players' voices were never actually
        -- silenced. setVoiceProperty('muted', ...) is the correct call — it mirrors
        -- how 'radioEnabled' is already toggled elsewhere in this file.
        if GetResourceState('pma-voice') == 'started' then
            exports['pma-voice']:setVoiceProperty('muted', true)
        end

        if not muteUIShown then
            local timeText = FormatSmartTime(muteDuration)
            SendNUIMessage({
                action = "showMute",
                timeText = timeText
            })
            muteUIShown = true
        end

        Notify('You have been muted by an admin!', 'error')
    else
        if GetResourceState('pma-voice') == 'started' then
            exports['pma-voice']:setVoiceProperty('muted', false)
        end

        if muteUIShown then
            SendNUIMessage({ action = "hideMute" })
            muteUIShown = false
        end

        muteDuration = 0
        muteStartTime = 0

        Notify('You have been unmuted!', 'success')
    end
end)

RegisterNetEvent('Vikto:Admin:AddReports', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Add Reports Handled',
        icon = 'star',
        fields = {
            { name = 'serverId', type = 'number', label = 'Admin Server ID', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Amount',          isRequired = true }
        }
    })
    if not input then return end
    TriggerServerEvent('vikto_admin:server:addReports', tonumber(input.serverId), tonumber(input.amount))
end)

RegisterNetEvent('Vikto:Admin:RemoveReports', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Remove Reports Handled',
        icon = 'star',
        fields = {
            { name = 'serverId', type = 'number', label = 'Admin Server ID', isRequired = true },
            { name = 'amount',   type = 'number', label = 'Amount',          isRequired = true }
        }
    })
    if not input then return end
    TriggerServerEvent('vikto_admin:server:removeReports', tonumber(input.serverId), tonumber(input.amount))
end)

RegisterNetEvent('Vikto:Admin:ViewPlayerReports', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'View Admin Reports',
        icon = 'hashtag',
        fields = {
            { name = 'serverId', type = 'number', label = 'Admin Server ID', isRequired = true }
        }
    })
    if not input then return end
    TriggerServerEvent('vikto_admin:server:viewPlayerReports', tonumber(input.serverId))
end)

RegisterNetEvent('Vikto:Admin:SendReportsLeaderboard', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('vikto_admin:server:sendReportsLeaderboard')
end)

local playerGamerTags = {}
local distanceToCheck = 200.0

local fivemGamerTagCompsEnum = {
    GamerName = 0,
    CrewTag = 1,
    HealthArmour = 2,
    BigText = 3,
    AudioIcon = 4,
    UsingMenu = 5,
    PassiveMode = 6,
    WantedStars = 7,
    Driver = 8,
    CoDriver = 9,
    Tagged = 12,
    GamerNameNearby = 13,
    Arrow = 14,
    Packages = 15,
    InvIfPedIsFollowing = 16,
    RankText = 17,
    Typing = 18
}

cleanAllGamerTags = function()
    for k, v in pairs(playerGamerTags) do
        if v.gamerTag then
            RemoveMpGamerTag(v.gamerTag)
        end
    end
    playerGamerTags = {}
end

local function setGamerTag(targetTag, pid)
    SetMpGamerTagVisibility(targetTag, fivemGamerTagCompsEnum.GamerName, true)

    SetMpGamerTagHealthBarColor(targetTag, 129)
    SetMpGamerTagAlpha(targetTag, fivemGamerTagCompsEnum.HealthArmour, 255)
    SetMpGamerTagVisibility(targetTag, fivemGamerTagCompsEnum.HealthArmour, true)

    SetMpGamerTagAlpha(targetTag, fivemGamerTagCompsEnum.AudioIcon, 255)
    if NetworkIsPlayerTalking(pid) then
        SetMpGamerTagVisibility(targetTag, fivemGamerTagCompsEnum.AudioIcon, true)
        SetMpGamerTagColour(targetTag, fivemGamerTagCompsEnum.AudioIcon, 12)
        SetMpGamerTagColour(targetTag, fivemGamerTagCompsEnum.GamerName, 12)
    else
        SetMpGamerTagVisibility(targetTag, fivemGamerTagCompsEnum.AudioIcon, false)
        SetMpGamerTagColour(targetTag, fivemGamerTagCompsEnum.AudioIcon, 0)
        SetMpGamerTagColour(targetTag, fivemGamerTagCompsEnum.GamerName, 0)
    end
end

local function clearGamerTag(targetTag)
    SetMpGamerTagVisibility(targetTag, fivemGamerTagCompsEnum.GamerName, false)
    SetMpGamerTagVisibility(targetTag, fivemGamerTagCompsEnum.HealthArmour, false)
    SetMpGamerTagVisibility(targetTag, fivemGamerTagCompsEnum.AudioIcon, false)
end

local function showGamerTags()
    local curCoords = GetEntityCoords(PlayerPedId())
    local allActivePlayers = GetActivePlayers()
    local currentPlayers = {}

    for _, pid in ipairs(allActivePlayers) do
        local targetPed = GetPlayerPed(pid)
        local serverId = GetPlayerServerId(pid)
        currentPlayers[pid] = true

        if DoesEntityExist(targetPed) then
            local charId = Player(serverId).state.cid or ".."
            local playerName = GetPlayerName(pid) or "unknown"
            local playerStr = '[' .. charId .. '] ' .. playerName

            if
                not playerGamerTags[pid]
                or playerGamerTags[pid].ped ~= targetPed
                or not IsMpGamerTagActive(playerGamerTags[pid].gamerTag)
            then
                if playerGamerTags[pid] and playerGamerTags[pid].gamerTag then
                    RemoveMpGamerTag(playerGamerTags[pid].gamerTag)
                end
                playerGamerTags[pid] = {
                    gamerTag = CreateFakeMpGamerTag(targetPed, playerStr, false, false, 0),
                    ped = targetPed,
                    cid = charId,
                    sid = serverId
                }
            elseif playerGamerTags[pid].cid ~= charId or playerGamerTags[pid].sid ~= serverId then
                if playerGamerTags[pid].gamerTag then
                    RemoveMpGamerTag(playerGamerTags[pid].gamerTag)
                end
                playerGamerTags[pid] = {
                    gamerTag = CreateFakeMpGamerTag(targetPed, playerStr, false, false, 0),
                    ped = targetPed,
                    cid = charId,
                    sid = serverId
                }
            end

            local targetTag = playerGamerTags[pid].gamerTag
            local targetPedCoords = GetEntityCoords(targetPed)
            if #(targetPedCoords - curCoords) <= distanceToCheck then
                setGamerTag(targetTag, pid)
            else
                clearGamerTag(targetTag)
            end
        end
    end

    for pid, data in pairs(playerGamerTags) do
        if not currentPlayers[pid] then
            if data.gamerTag then
                RemoveMpGamerTag(data.gamerTag)
            end
            playerGamerTags[pid] = nil
        end
    end
end

RegisterNetEvent('Vikto:Admin:ToggleNames', function(forcedState)
    if forcedState == nil and not ViktoIsAdmin() and not isPlayerIdsEnabled then return end
    local newState = isPlayerIdsEnabled
    if forcedState == nil then
        if not isPlayerIdsEnabled and GetResourceState('FL-Shipment') == 'started' and exports['FL-Shipment']:isInShipment() then
            Notify('You cannot use this during a Shipment!', 'error')
            return
        end
        if not isPlayerIdsEnabled and GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:isInMatch() then
            Notify('You cannot use this during a match!', 'error')
            return
        end
        if not isPlayerIdsEnabled and IsBlockedInPursuitMatch() then
            Notify('You cannot use this during Pursuits!', 'error')
            return
        end
        if not isPlayerIdsEnabled and GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
            Notify('You cannot use this during a gang world!', 'error')
            return
        end
        if not isPlayerIdsEnabled and IsBlockedInGangLabsWorld() then
            Notify('You cannot use this during Gang Labs!', 'error')
            return
        end

        newState = not isPlayerIdsEnabled
    else
        newState = forcedState
    end

    if newState == isPlayerIdsEnabled then
        if newState == false then
            cleanAllGamerTags()
        end
        return
    end

    isPlayerIdsEnabled = newState

    if isPlayerIdsEnabled then
        Notify('Player Names ENABLED', 'success')
        CreateThread(function()
            while isPlayerIdsEnabled do
                if GetResourceState('FL-Shipment') == 'started' and exports['FL-Shipment']:isInShipment() then
                    TriggerEvent('Vikto:Admin:ToggleNames', false)
                    break
                elseif GetResourceState('FL-Matchmaking') == 'started' and exports['FL-Matchmaking']:isInMatch() then
                    TriggerEvent('Vikto:Admin:ToggleNames', false)
                    break
                elseif IsBlockedInPursuitMatch() then
                    TriggerEvent('Vikto:Admin:ToggleNames', false)
                    break
                elseif GetResourceState('FL-Sprays') == 'started' and exports['FL-Sprays']:IsInSprayWorld() then
                    TriggerEvent('Vikto:Admin:ToggleNames', false)
                    break
                elseif IsBlockedInGangLabsWorld() then
                    TriggerEvent('Vikto:Admin:ToggleNames', false)
                    break
                end

                showGamerTags()
                Wait(250)
            end
            cleanAllGamerTags()
        end)
    else
        cleanAllGamerTags()
        Notify('Player Names DISABLED', 'error')
    end

    TriggerServerEvent('vikto_admin:server:logNames', isPlayerIdsEnabled)
end)

RegisterNetEvent('Vikto:Admin:MessagePlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Message Player',
        icon = 'comment',
        fields = {
            { name = 'cid',     type = 'text', label = 'Player CID', isRequired = true },
            { name = 'message', type = 'text', label = 'Message',    isRequired = true }
        }
    })
    if not input then return end
    TriggerServerEvent('vikto_admin:server:messagePlayer', input.cid, input.message)
end)

RegisterNetEvent('Vikto:Admin:MessageID', function(args)
    if not ViktoIsAdmin() then return end
    if args and args[1] and args[2] then
        local targetId = tonumber(args[1])
        local message = table.concat(args, " ", 2)
        if targetId and message ~= "" then
            TriggerServerEvent('vikto_admin:server:messageID', targetId, message)
            return
        end
    end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Message Player (ID)',
        icon = 'comment',
        fields = {
            { name = 'serverId', type = 'number', label = 'Player Server ID', isRequired = true },
            { name = 'message',  type = 'text',   label = 'Message',          isRequired = true }
        }
    })
    if not input then return end
    TriggerServerEvent('vikto_admin:server:messageID', input.serverId, input.message)
end)

RegisterNetEvent('Vikto:Admin:Announce', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Server Announcement',
        icon = 'bullhorn',
        fields = {
            { name = 'announcement', type = 'text', label = 'Announcement', isRequired = true }
        }
    })
    if not input then return end
    TriggerServerEvent('vikto_admin:server:announce', input.announcement)
end)

RegisterNetEvent('Vikto:Admin:WarnPlayer', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Warn Player',
        icon = 'triangle-exclamation',
        fields = {
            { name = 'cid',    type = 'text', label = 'Player CID', isRequired = true },
            { name = 'reason', type = 'text', label = 'Reason',     isRequired = true }
        }
    })
    if not input then return end
    TriggerServerEvent('vikto_admin:server:warnPlayer', input.cid, input.reason)
end)

local showBlips = false
local playerBlips = {}

local function cleanAllBlips()
    for _, blip in pairs(playerBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    playerBlips = {}
end

local function updatePlayerBlips()
    local allActivePlayers = GetActivePlayers()
    local curPlayers = {}

    for _, pid in ipairs(allActivePlayers) do
        local targetPed = GetPlayerPed(pid)
        local serverId = GetPlayerServerId(pid)

        if DoesEntityExist(targetPed) then
            curPlayers[pid] = true
            local charId = Player(serverId).state.cid or ".."
            local playerName = GetPlayerName(pid) or "unknown"
            local playerStr = '[' .. charId .. '] ' .. playerName

            if not playerBlips[pid] or not DoesBlipExist(playerBlips[pid]) then
                local blip = AddBlipForEntity(targetPed)
                SetBlipSprite(blip, 1)
                SetBlipColour(blip, 0)
                SetBlipScale(blip, 0.8)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(playerStr)
                EndTextCommandSetBlipName(blip)
                playerBlips[pid] = blip
            else
                local blip = playerBlips[pid]
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(playerStr)
                EndTextCommandSetBlipName(blip)
            end
        end
    end

    for pid, blip in pairs(playerBlips) do
        if not curPlayers[pid] then
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
            playerBlips[pid] = nil
        end
    end
end

RegisterNetEvent('Vikto:Admin:ToggleBlips', function()
    if not ViktoIsAdmin() then return end
    showBlips = not showBlips

    if showBlips then
        Notify('Player Blips ENABLED', 'success')
        CreateThread(function()
            while showBlips do
                updatePlayerBlips()
                Wait(2000)
            end
            cleanAllBlips()
        end)
    else
        Notify('Player Blips DISABLED', 'error')
    end

    TriggerServerEvent('vikto_admin:server:logBlips', showBlips)
end)

RegisterNetEvent('Vikto:Admin:DeleteAllVehicles', function()
    if not ViktoIsAdmin() then return end
    local vehicles = GetGamePool('CVehicle')
    local count = 0
    for i = 1, #vehicles do
        local veh = vehicles[i]
        if DoesEntityExist(veh) then
            SetEntityAsMissionEntity(veh, true, true)
            DeleteEntity(veh)
            count = count + 1
        end
    end
    Notify('Cleared ' .. count .. ' vehicles!', 'success')
end)

RegisterNetEvent('Vikto:Admin:DeleteAllProps', function()
    if not ViktoIsAdmin() then return end
    local objects = GetGamePool('CObject')
    local count = 0
    for i = 1, #objects do
        local obj = objects[i]
        if DoesEntityExist(obj) then
            SetEntityAsMissionEntity(obj, true, true)
            DeleteEntity(obj)
            count = count + 1
        end
    end
    Notify('Cleared ' .. count .. ' objects/props!', 'success')
end)

RegisterNetEvent('Vikto:Admin:DeleteAllPeds', function()
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('vikto_admin:server:RequestDeleteAllPeds')
end)

RegisterNetEvent('vikto_admin:client:DoDeleteAllPeds', function()
    local peds = GetGamePool('CPed')
    for i = 1, #peds do
        local ped = peds[i]
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            NetworkRequestControlOfEntity(ped)
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
            if DoesEntityExist(ped) then
                DeletePed(ped)
            end
        end
    end
end)

sentBackTimer = 0
sentBackCoords = nil
sentBackBucket = nil

RegisterNetEvent('vikto_admin:client:sentBackOption', function(coords, bucket)
    sentBackCoords = coords
    sentBackBucket = bucket
    sentBackTimer = 30

    lib.showTextUI('Sent Back [E]', {
        position = "right-center",
        icon = 'reply',
        style = {
            borderRadius = 0,
            backgroundColor = 'FF0F1411',
            color = 'white'
        }
    })

end)

RegisterNUICallback('fetchPlayerDetail', function(data, cb)
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('vikto_admin:server:fetchPlayerDetail', data.id, data.tab)
    cb('ok')
end)

RegisterNUICallback('savePlayerNote', function(data, cb)
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('vikto_admin:server:savePlayerNote', data.id, data.note)
    cb('ok')
end)

RegisterNUICallback('addPlayerWhitelist', function(data, cb)
    if not ViktoIsAdmin() then return end
    TriggerServerEvent('vikto_admin:server:addPlayerWhitelist', data.id)
    cb('ok')
end)

local currentModalPlayerStatus = {
    isJailed = false,
    isMutedVoice = false,
    isMutedChat = false,
    isFrozen = false
}

RegisterNetEvent('vikto_admin:client:playerDetailUpdate', function(tab, data)
    if tab == 'status' then
        currentModalPlayerStatus = data
    end
    SendNUIMessage({
        action = 'playerDetailUpdate',
        tab = tab,
        data = data
    })
end)

RegisterNetEvent('Vikto:Admin:ExecuteModalAction', function(eventName, targetCid)
    if not ViktoIsAdmin() then return end

    if not targetCid then return end

    if eventName == 'Vikto:Admin:WarnPlayer' then
        local input = exports['FL-F1Menu']:OpenPrompt({
            title = 'Warn Player',
            icon = 'triangle-exclamation',
            fields = {
                { name = 'reason', type = 'text', label = 'Reason', isRequired = true }
            }
        })
        if input then TriggerServerEvent('vikto_admin:server:warnPlayer', targetCid, input.reason) end
    elseif eventName == 'Vikto:Admin:KickPlayer' then
        local input = exports['FL-F1Menu']:OpenPrompt({
            title = 'Kick Player',
            icon = 'door-open',
            fields = {
                { name = 'reason', type = 'text', label = 'Reason', isRequired = true }
            }
        })
        if input then TriggerServerEvent('vikto_admin:server:kickPlayer', targetCid, input.reason) end
    elseif eventName == 'Vikto:Admin:BanPlayer' then
        local input = exports['FL-F1Menu']:OpenPrompt({
            title = 'Ban Player',
            icon = 'gavel',
            fields = {
                { name = 'value',  type = 'number', label = 'Value',  min = 1,          isRequired = true, defaultValue = 1 },
                {
                    name = 'unit',
                    type = 'select',
                    label = 'Unit',
                    isRequired = true,
                    options = {
                        { label = 'Minutes',   value = 'm' },
                        { label = 'Hours',     value = 'h' },
                        { label = 'Days',      value = 'd' },
                        { label = 'Weeks',     value = 'w' },
                        { label = 'Months',    value = 'month' },
                        { label = 'Permanent', value = 'p' }
                    }
                },
                { name = 'reason', type = 'text',   label = 'Reason', isRequired = true }
            }
        })
        if input then
            local minutes = CalculateDurationInMinutes(input.value, input.unit)
            local hours = minutes / 60
            TriggerServerEvent('vikto_admin:server:banPlayer', targetCid, input.reason, hours)
        end
    elseif eventName == 'Vikto:Admin:JailPlayer' then
        if currentModalPlayerStatus.isJailed then
            TriggerServerEvent('vikto_admin:server:unjailPlayer', targetCid)
        else
            local input = exports['FL-F1Menu']:OpenPrompt({
                title = 'Jail Player',
                icon = 'dungeon',
                fields = {
                    { name = 'value',  type = 'number', label = 'Value',  min = 1,          isRequired = true, defaultValue = 30 },
                    {
                        name = 'unit',
                        type = 'select',
                        label = 'Unit',
                        isRequired = true,
                        options = {
                            { label = 'Minutes',   value = 'm' },
                            { label = 'Hours',     value = 'h' },
                            { label = 'Days',      value = 'd' },
                            { label = 'Weeks',     value = 'w' },
                            { label = 'Months',    value = 'month' },
                            { label = 'Permanent', value = 'p' }
                        }
                    },
                    { name = 'reason', type = 'text',   label = 'Reason', isRequired = true }
                }
            })
            if input then
                local minutes = CalculateDurationInMinutes(input.value, input.unit)
                TriggerServerEvent('vikto_admin:server:jailPlayer', targetCid, minutes, input.reason)
            end
        end
    elseif eventName == 'Vikto:Admin:MutePlayer' then
        if currentModalPlayerStatus.isMutedVoice then
            TriggerServerEvent('vikto_admin:server:unmutePlayer', targetCid)
        else
            local input = exports['FL-F1Menu']:OpenPrompt({
                title = 'Mute Voice',
                icon = 'microphone-slash',
                fields = {
                    { name = 'value',  type = 'number', label = 'Value',  min = 1,          isRequired = true, defaultValue = 60 },
                    {
                        name = 'unit',
                        type = 'select',
                        label = 'Unit',
                        isRequired = true,
                        options = {
                            { label = 'Minutes',   value = 'm' },
                            { label = 'Hours',     value = 'h' },
                            { label = 'Days',      value = 'd' },
                            { label = 'Weeks',     value = 'w' },
                            { label = 'Months',    value = 'month' },
                            { label = 'Permanent', value = 'p' }
                        }
                    },
                    { name = 'reason', type = 'text',   label = 'Reason', isRequired = true }
                }
            })
            if input then
                local minutes = CalculateDurationInMinutes(input.value, input.unit)
                TriggerServerEvent('vikto_admin:server:mutePlayer', targetCid, minutes, input.reason)
            end
        end
    elseif eventName == 'Vikto:Admin:MuteChat' then
        if currentModalPlayerStatus.isMutedChat then
            TriggerServerEvent('vikto_admin:server:unmuteChatPlayer', targetCid)
        else
            local input = exports['FL-F1Menu']:OpenPrompt({
                title = 'Mute Chat',
                icon = 'comment-slash',
                fields = {
                    { name = 'value',  type = 'number', label = 'Value',  min = 1,          isRequired = true, defaultValue = 60 },
                    {
                        name = 'unit',
                        type = 'select',
                        label = 'Unit',
                        isRequired = true,
                        options = {
                            { label = 'Minutes',   value = 'm' },
                            { label = 'Hours',     value = 'h' },
                            { label = 'Days',      value = 'd' },
                            { label = 'Weeks',     value = 'w' },
                            { label = 'Months',    value = 'month' },
                            { label = 'Permanent', value = 'p' }
                        }
                    },
                    { name = 'reason', type = 'text',   label = 'Reason', isRequired = true }
                }
            })
            if input then
                local minutes = CalculateDurationInMinutes(input.value, input.unit)
                TriggerServerEvent('vikto_admin:server:muteChatPlayer', targetCid, minutes, input.reason)
            end
        end
    elseif eventName == 'Vikto:Admin:MessagePlayer' then
        local input = exports['FL-F1Menu']:OpenPrompt({
            title = 'Direct Message',
            icon = 'comment-dots',
            fields = {
                { name = 'message', type = 'text', label = 'Message', isRequired = true }
            }
        })
        if input then TriggerServerEvent('vikto_admin:server:messagePlayer', targetCid, input.message) end
    elseif eventName == 'Vikto:Admin:GiveItem' then
        local input = exports['FL-F1Menu']:OpenPrompt({
            title = 'Give Item',
            icon = 'box-open',
            fields = {
                { name = 'item',   type = 'text',   label = 'Item Name', isRequired = true },
                { name = 'amount', type = 'number', label = 'Amount',    isRequired = true, defaultValue = 1 }
            }
        })
        if input then TriggerServerEvent('vikto_admin:server:giveItem', targetCid, input.item, tonumber(input.amount)) end
    elseif eventName == 'Vikto:Admin:GoToPlayer' then
        TriggerServerEvent('vikto_admin:server:gotoPlayer', targetCid)
    elseif eventName == 'Vikto:Admin:BringPlayer' then
        TriggerServerEvent('vikto_admin:server:bringPlayer', targetCid)
    elseif eventName == 'Vikto:Admin:ReviveSelf' then
        TriggerServerEvent('vikto_admin:server:revivePlayer', targetCid)
    elseif eventName == 'Vikto:Admin:KillPlayer' then
        TriggerServerEvent('vikto_admin:server:killPlayer', targetCid)
    elseif eventName == 'Vikto:Admin:FreezePlayer' then
        local targetState = not currentModalPlayerStatus.isFrozen
        TriggerServerEvent('vikto_admin:server:freezePlayer', targetCid, targetState)
    elseif eventName == 'Vikto:Admin:Spectate' then
        TriggerServerEvent('vikto_admin:server:spectatePlayer', targetCid)
    else
        TriggerServerEvent(eventName, targetCid)
    end
end)

RegisterNetEvent('vikto_admin:client:syncPlayers', function(players, maxPlayers)
    local list = players or {}
    if maxPlayers then
        maxPlayersLimit = maxPlayers
    end

    LOCAL_PLAYERLIST = {}
    for _, p in ipairs(list) do
        LOCAL_PLAYERLIST[tostring(p.source)] = p
    end
    SendNUIMessage({
        action = 'setPlayerList',
        players = list,
        maxPlayers = maxPlayersLimit
    })
    if Config.Debug then
        print('[VIKTO ADMIN] syncPlayers received: ' .. #list .. ' players')
    end
end)

RegisterNetEvent('vikto_admin:client:playerJoinLeave', function(srcId, nameOrFalse)
    local pids = tostring(srcId)
    if nameOrFalse == false then

        LOCAL_PLAYERLIST[pids] = nil
        if Config.Debug then
            print('[VIKTO ADMIN] playerJoinLeave: ' .. srcId .. ' disconnected')
        end
    else

        LOCAL_PLAYERLIST[pids] = {
            source  = srcId,
            name    = nameOrFalse,
            serverId = srcId,
            cid     = 'N/A',
            health  = -1,
            isStaff = false,
            isJailed = false,
            isFrozen = false,
            isMutedVoice = false,
            isMutedChat  = false,
        }
        if Config.Debug then
            print('[VIKTO ADMIN] playerJoinLeave: ' .. srcId .. ' joined as ' .. nameOrFalse)
        end
    end

    local upload = {}
    for _, p in pairs(LOCAL_PLAYERLIST) do
        table.insert(upload, p)
    end
    SendNUIMessage({
        action = 'setPlayerList',
        players = upload,
        maxPlayers = maxPlayersLimit
    })
end)

if Config.Debug then
    RegisterCommand('testplayers', function(source, args)
        local count = tonumber(args[1]) or 50
        TriggerServerEvent('vikto_admin:server:testplayers_cmd', count)
    end, false)

    RegisterCommand('testplayers_clear', function(source, args)
        TriggerServerEvent('vikto_admin:server:testplayers_clear_cmd')
    end, false)
end

RegisterNetEvent('vikto_admin:client:playMentionSound', function()
    PlaySoundFrontend(-1, "Event_Message_Purple", "GTAO_FM_Events_Soundset", true)
end)

-- =====================================================================
-- ACTION & RESULT RECEIVERS
-- The server fires all of these, but none of them had a client handler —
-- which is why revive/freeze/teleport/spectate and every "Check ..."
-- action silently did nothing. Full wiring below.
-- =====================================================================

-- Admin actions applied TO this player
RegisterNetEvent('vikto_admin:client:revive', function()
    TriggerEvent('hospital:client:Revive')
    Notify('You have been revived by an admin.', 'success')
end)

RegisterNetEvent('vikto_admin:client:freeze', function(state)
    local ped = cache.ped or PlayerPedId()
    FreezeEntityPosition(ped, state == true)
    if state then
        ClearPedTasksImmediately(ped)
        Notify('You have been frozen by an admin.', 'error')
    else
        Notify('You have been unfrozen.', 'success')
    end
end)

RegisterNetEvent('vikto_admin:client:teleport', function(coords)
    if not coords then return end
    local ped = cache.ped or PlayerPedId()
    DoScreenFadeOut(300)
    Wait(300)
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    if coords.w then SetEntityHeading(ped, coords.w) end
    DoScreenFadeIn(300)
end)

-- Radius revive: server broadcasts (adminSrc, radius); revive if we're close.
RegisterNetEvent('vikto_admin:client:reviveRadius', function(adminSrc, radius)
    local adminPlayer = GetPlayerFromServerId(adminSrc)
    if adminPlayer == -1 then return end
    local adminPed = GetPlayerPed(adminPlayer)
    if not adminPed or adminPed == 0 then return end
    local dist = #(GetEntityCoords(cache.ped or PlayerPedId()) - GetEntityCoords(adminPed))
    if dist <= (tonumber(radius) or 10.0) then
        TriggerEvent('hospital:client:Revive')
        Notify('You have been revived by an admin.', 'success')
    end
end)

-- Spectate (server sends the target source + coords)
local spectateTarget = nil
local spectateReturnPos = nil

RegisterNetEvent('vikto_admin:client:spectate', function(target, coords)
    local ped = cache.ped or PlayerPedId()
    if not spectateReturnPos then
        spectateReturnPos = GetEntityCoords(ped)
    end
    spectateTarget = tonumber(target)

    DoScreenFadeOut(300)
    Wait(300)
    if coords then
        SetEntityCoords(ped, coords.x, coords.y, coords.z + 10.0, false, false, false, true)
    end
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    DoScreenFadeIn(300)
    Notify('Spectating started. Use the menu again to stop.', 'inform')

    CreateThread(function()
        while spectateTarget do
            local tp = GetPlayerFromServerId(spectateTarget)
            local tped = (tp ~= -1) and GetPlayerPed(tp) or 0
            if tped ~= 0 and DoesEntityExist(tped) then
                local tc = GetEntityCoords(tped)
                SetEntityCoords(cache.ped or PlayerPedId(), tc.x, tc.y, tc.z + 8.0, false, false, false, true)
            end
            Wait(500)
        end
    end)
end)

RegisterNetEvent('vikto_admin:client:spectateEnd', function()
    spectateTarget = nil
    local ped = cache.ped or PlayerPedId()
    DoScreenFadeOut(300)
    Wait(300)
    if spectateReturnPos then
        SetEntityCoords(ped, spectateReturnPos.x, spectateReturnPos.y, spectateReturnPos.z, false, false, false, true)
        spectateReturnPos = nil
    end
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(300)
    Notify('Spectating stopped.', 'inform')
end)

-- World cleanup broadcast
RegisterNetEvent('vikto_admin:client:deleteAllPeds', function()
    local handle, ped = FindFirstPed()
    local ok
    repeat
        if ped ~= (cache.ped or PlayerPedId()) and not IsPedAPlayer(ped) then
            DeleteEntity(ped)
        end
        ok, ped = FindNextPed(handle)
    until not ok
    EndFindPed(handle)
end)

-- Report accept effect at the reporter's position (broadcast)
RegisterNetEvent('vikto_admin:client:syncPtfx', function(adminSrc)
    local p = GetPlayerFromServerId(tonumber(adminSrc) or -1)
    if p == -1 then return end
    local pped = GetPlayerPed(p)
    if pped and pped ~= 0 then
        local c = GetEntityCoords(pped)
        TriggerEvent('adminreport:client:MakeEffect', { x = c.x, y = c.y, z = c.z })
    end
end)

RegisterNetEvent('vikto_admin:client:syncStaffStatus', function(has)
    isStaffCached = has == true
end)

-- ------------------------------------------------------------------
-- "Check / View" result displays (all were black holes before)
-- ------------------------------------------------------------------
RegisterNetEvent('vikto_admin:client:jailTimeResult', function(cid, remaining, reason)
    if (tonumber(remaining) or 0) > 0 then
        local mins = math.ceil(remaining / 60)
        Notify(('Jail %s: %d min left (%s)'):format(tostring(cid), mins, reason or 'no reason'), 'inform')
    else
        Notify(('Player %s is not jailed.'):format(tostring(cid)), 'inform')
    end
end)

RegisterNetEvent('vikto_admin:client:radioResult', function(targetId, channel)
    if (tonumber(channel) or 0) > 0 then
        Notify(('Player %s is on radio channel %s.'):format(tostring(targetId), tostring(channel)), 'inform')
    else
        Notify(('Player %s is not in any radio channel.'):format(tostring(targetId)), 'inform')
    end
end)

RegisterNetEvent('vikto_admin:client:coinsResult', function(cid, amount)
    Notify(('Coins of %s: %d'):format(tostring(cid), tonumber(amount) or 0), 'inform')
end)

RegisterNetEvent('vikto_admin:client:matchmakingXPResult', function(cid, xp)
    Notify(('Matchmaking XP of %s: %d'):format(tostring(cid), tonumber(xp) or 0), 'inform')
end)

RegisterNetEvent('vikto_admin:client:truckPointsResult', function(cid, points)
    Notify(('Truck points of %s: %d'):format(tostring(cid), tonumber(points) or 0), 'inform')
end)

RegisterNetEvent('vikto_admin:client:viewHoursResult', function(targetId, hours)
    Notify(('Staff hours of %s: %s'):format(tostring(targetId), tostring(hours or 0)), 'inform')
end)

RegisterNetEvent('vikto_admin:client:viewPointsResult', function(targetId, points)
    Notify(('Staff points of %s: %s'):format(tostring(targetId), tostring(points or 0)), 'inform')
end)

RegisterNetEvent('vikto_admin:client:viewReportsResult', function(targetId, reports)
    Notify(('Staff reports of %s: %s'):format(tostring(targetId), tostring(reports or 0)), 'inform')
end)

RegisterNetEvent('vikto_admin:client:playerIDResult', function(id, online, name)
    if online then
        Notify(('Player %s is ONLINE%s.'):format(tostring(id), name and (' as ' .. name) or ''), 'success')
    else
        Notify(('Player %s is offline / not found.'):format(tostring(id)), 'error')
    end
end)

RegisterNetEvent('Vikto:Admin:Client:CIDResult', function(cid, online)
    Notify(('CID %s is %s.'):format(tostring(cid), online and 'ONLINE' or 'offline'), online and 'success' or 'inform')
end)

RegisterNetEvent('vikto_admin:client:optionPermissionResult', function(data, allowed)
    if not allowed then
        Notify('You do not have permission for this action.', 'error')
    end
end)

-- ------------------------------------------------------------------
-- Data feeds for the NUI pages (history / leaderboards)
-- ------------------------------------------------------------------
local function TopListNotify(title, dataSet)
    local list = {}
    for key, value in pairs(dataSet or {}) do
        list[#list + 1] = { id = key, value = tonumber(value) or 0 }
    end
    table.sort(list, function(a, b) return a.value > b.value end)
    local top = {}
    for i = 1, math.min(#list, 5) do
        top[#top + 1] = ('%d. %s: %d'):format(i, tostring(list[i].id), list[i].value)
    end
    Notify(title .. ' — ' .. (#top > 0 and table.concat(top, ' | ') or 'no entries'), 'inform')
end

RegisterNetEvent('vikto_admin:client:leaderboardData', function(data)
    TopListNotify('Staff Points', data)
end)

RegisterNetEvent('vikto_admin:client:hoursLeaderboardData', function(data)
    TopListNotify('Staff Hours', data)
end)

RegisterNetEvent('vikto_admin:client:reportsLeaderboardData', function(data)
    TopListNotify('Staff Reports', data)
end)

RegisterNetEvent('vikto_admin:client:historyData', function(rows)
    SendNUIMessage({ action = 'playerDetailUpdate', tab = 'history', data = rows or {} })
end)

RegisterNetEvent('vikto_admin:client:globalHistoryData', function(rows)
    SendNUIMessage({ action = 'playerDetailUpdate', tab = 'globalHistory', data = rows or {} })
    SendNUIMessage({ action = 'setState', key = 'globalHistory', value = rows or {} })
end)

RegisterNetEvent('vikto_admin:client:txAdminPlayersResult', function(list)
    SendNUIMessage({ action = 'setPlayerList', players = list or {}, maxPlayers = maxPlayersLimit })
end)

-- Menu option: send any player back to the lobby spawn.
RegisterNetEvent('Vikto:Admin:SendToSpawn', function()
    if not ViktoIsAdmin() then return end
    local input = exports['FL-F1Menu']:OpenPrompt({
        title = 'Send To Spawn',
        icon = 'house-user',
        fields = {
            { name = 'id', type = 'text', label = 'Player ID / CID', placeholder = 'Server ID or CID', isRequired = true }
        }
    })
    if not input or not input.id then return end
    TriggerServerEvent('vikto_admin:server:teleportPlayerToSpawn', input.id)
end)
