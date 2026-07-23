local cam = nil
local charPed = nil
local previewPeds = {}
local pedRequest = 0 -- generation counter: any bump invalidates in-flight ped creations
local loadScreenCheckState = false
local QBCore = exports['qb-core']:GetCoreObject({ 'Functions' })
local cached_player_skins = {}

local randommodels = { -- models possible to load when choosing empty slot
    'mp_m_freemode_01',
    'mp_f_freemode_01',
}

-- Main Thread

CreateThread(function()
    while true do
        Wait(0)
        if NetworkIsSessionStarted() then
            TriggerEvent('qb-multicharacter:client:chooseChar')
            return
        end
    end
end)

-- Functions

local function loadModel(model)
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end
end

-- Deletes every preview ped we have ever created and invalidates any
-- ped creation that is still in flight (model loading / skin callback).
local function deletePreviewPeds()
    pedRequest = pedRequest + 1
    for i = #previewPeds, 1, -1 do
        local ped = previewPeds[i]
        if DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
        end
        previewPeds[i] = nil
    end
    charPed = nil
end

-- Safety net: removes any leftover non-player clone peds around the preview
-- spot, even if we somehow lost their handle (e.g. after a resource restart).
local function sweepPreviewArea()
    local previewCoords = vector3(Config.PedCoords.x, Config.PedCoords.y, Config.PedCoords.z)
    local playerPed = PlayerPedId()
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= playerPed and not IsPedAPlayer(ped) and DoesEntityExist(ped) then
            if #(GetEntityCoords(ped) - previewCoords) < 5.0 then
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            end
        end
    end
end

local function destroyPreviewPeds()
    deletePreviewPeds()
    sweepPreviewArea()
end

local function initializePedModel(model, data)
    deletePreviewPeds()
    local request = pedRequest
    CreateThread(function()
        if not model then
            model = joaat(randommodels[math.random(#randommodels)])
        end
        loadModel(model)
        if request ~= pedRequest then -- superseded while the model was loading
            SetModelAsNoLongerNeeded(model)
            return
        end
        local ped = CreatePed(2, model, Config.PedCoords.x, Config.PedCoords.y, Config.PedCoords.z - 0.98, Config.PedCoords.w, false, true)
        previewPeds[#previewPeds + 1] = ped
        charPed = ped
        SetModelAsNoLongerNeeded(model)
        if request ~= pedRequest then -- superseded while the ped was being created
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
            return
        end
        SetPedComponentVariation(ped, 0, 0, 0, 2)
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, true)
        PlaceObjectOnGroundProperly(ped)
        SetBlockingOfNonTemporaryEvents(ped, true)
        if data then
            TriggerEvent('qb-clothing:client:loadPlayerClothing', data, ped)
        end
    end)
end

local function skyCam(bool)
    TriggerEvent('qb-weathersync:client:DisableSync')
    if bool then
        DoScreenFadeIn(1000)
        SetTimecycleModifier('hud_def_blur')
        SetTimecycleModifierStrength(1.0)
        FreezeEntityPosition(PlayerPedId(), false)
        cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', Config.CamCoords.x, Config.CamCoords.y, Config.CamCoords.z, 0.0, 0.0, Config.CamCoords.w, 60.00, false, 0)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 1, true, true)
    else
        SetTimecycleModifier('default')
        SetCamActive(cam, false)
        DestroyCam(cam, true)
        RenderScriptCams(false, false, 1, true, true)
        FreezeEntityPosition(PlayerPedId(), false)
    end
end

local function openCharMenu(bool)
    QBCore.Functions.TriggerCallback('qb-multicharacter:server:GetNumberOfCharacters', function(result, countries)
        local translations = {}
        for k in pairs(Lang.fallback and Lang.fallback.phrases or Lang.phrases) do
            if k:sub(0, ('ui.'):len()) then
                translations[k:sub(('ui.'):len() + 1)] = Lang:t(k)
            end
        end
        SetNuiFocus(bool, bool)
        SendNUIMessage({
            action = 'ui',
            customNationality = Config.customNationality,
            toggle = bool,
            nChar = result,
            enableDeleteButton = Config.EnableDeleteButton,
            translations = translations,
            countries = countries,
        })
        skyCam(bool)
        if not loadScreenCheckState then
            ShutdownLoadingScreenNui()
            loadScreenCheckState = true
        end
    end)
end

-- Events

RegisterNetEvent('qb-multicharacter:client:closeNUIdefault', function() -- This event is only for no starting apartments
    destroyPreviewPeds()
    SetNuiFocus(false, false)
    DoScreenFadeOut(500)
    Wait(2000)
    destroyPreviewPeds() -- catch any ped that finished spawning during the fade
    SetEntityCoords(PlayerPedId(), Config.DefaultSpawn.x, Config.DefaultSpawn.y, Config.DefaultSpawn.z)
    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerServerEvent('qb-houses:server:SetInsideMeta', 0, false)
    TriggerServerEvent('qb-apartments:server:SetInsideMeta', 0, 0, false)
    Wait(500)
    openCharMenu()
    SetEntityVisible(PlayerPedId(), true)
    Wait(500)
    DoScreenFadeIn(250)
    TriggerEvent('qb-weathersync:client:EnableSync')
    TriggerEvent('qb-clothes:client:CreateFirstCharacter')
end)

RegisterNetEvent('qb-multicharacter:client:closeNUI', function()
    destroyPreviewPeds()
    SetNuiFocus(false, false)
end)

RegisterNetEvent('qb-multicharacter:client:chooseChar', function()
    SetNuiFocus(false, false)
    DoScreenFadeOut(10)
    Wait(1000)
    local interior = GetInteriorAtCoords(Config.Interior.x, Config.Interior.y, Config.Interior.z - 18.9)
    LoadInterior(interior)
    while not IsInteriorReady(interior) do
        Wait(1000)
    end
    FreezeEntityPosition(PlayerPedId(), true)
    SetEntityCoords(PlayerPedId(), Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z)
    Wait(1500)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    openCharMenu(true)
end)

RegisterNetEvent('qb-multicharacter:client:spawnLastLocation', function(coords, cData)
    QBCore.Functions.TriggerCallback('apartments:GetOwnedApartment', function(result)
        if result then
            TriggerEvent('apartments:client:SetHomeBlip', result.type)
            local ped = PlayerPedId()
            SetEntityCoords(ped, coords.x, coords.y, coords.z)
            SetEntityHeading(ped, coords.w)
            FreezeEntityPosition(ped, false)
            SetEntityVisible(ped, true)
            local PlayerData = QBCore.Functions.GetPlayerData()
            local insideMeta = PlayerData.metadata['inside']
            DoScreenFadeOut(500)

            if insideMeta.house then
                TriggerEvent('qb-houses:client:LastLocationHouse', insideMeta.house)
            elseif insideMeta.apartment.apartmentType and insideMeta.apartment.apartmentId then
                TriggerEvent('qb-apartments:client:LastLocationHouse', insideMeta.apartment.apartmentType, insideMeta.apartment.apartmentId)
            else
                SetEntityCoords(ped, coords.x, coords.y, coords.z)
                SetEntityHeading(ped, coords.w)
                FreezeEntityPosition(ped, false)
                SetEntityVisible(ped, true)
            end

            TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
            Wait(2000)
            destroyPreviewPeds()
            DoScreenFadeIn(250)
        end
    end, cData.citizenid)
end)

-- Make sure no preview ped survives a resource restart
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for i = 1, #previewPeds do
        if DoesEntityExist(previewPeds[i]) then
            SetEntityAsMissionEntity(previewPeds[i], true, true)
            DeleteEntity(previewPeds[i])
        end
    end
end)

-- NUI Callbacks

RegisterNUICallback('closeUI', function(_, cb)
    destroyPreviewPeds()
    SetNuiFocus(false, false)
    skyCam(false)
    cb('ok')
end)

RegisterNUICallback('disconnectButton', function(_, cb)
    destroyPreviewPeds()
    TriggerServerEvent('qb-multicharacter:server:disconnect')
    cb('ok')
end)

RegisterNUICallback('selectCharacter', function(data, cb)
    local cData = data.cData
    DoScreenFadeOut(10)
    TriggerServerEvent('qb-multicharacter:server:loadUserData', cData)
    openCharMenu(false)
    destroyPreviewPeds()
    cb('ok')
end)

RegisterNUICallback('cDataPed', function(nData, cb)
    local cData = nData.cData
    deletePreviewPeds()
    if cData ~= nil then
        if not cached_player_skins[cData.citizenid] then
            local temp_model = promise.new()
            local temp_data = promise.new()

            QBCore.Functions.TriggerCallback('qb-multicharacter:server:getSkin', function(model, data)
                temp_model:resolve(model)
                temp_data:resolve(data)
            end, cData.citizenid)

            local resolved_model = Citizen.Await(temp_model)
            local resolved_data = Citizen.Await(temp_data)

            cached_player_skins[cData.citizenid] = { model = resolved_model, data = resolved_data }
        end

        local model = cached_player_skins[cData.citizenid].model
        local data = cached_player_skins[cData.citizenid].data

        model = model ~= nil and tonumber(model) or false

        if model then
            initializePedModel(model, json.decode(data))
        else
            initializePedModel()
        end
        cb('ok')
    else
        initializePedModel()
        cb('ok')
    end
end)

RegisterNUICallback('setupCharacters', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-multicharacter:server:setupCharacters', function(result)
        cached_player_skins = {}
        SendNUIMessage({
            action = 'setupCharacters',
            characters = result
        })
        cb('ok')
    end)
end)

RegisterNUICallback('removeBlur', function(_, cb)
    SetTimecycleModifier('default')
    cb('ok')
end)

RegisterNUICallback('createNewCharacter', function(data, cb)
    local cData = data
    DoScreenFadeOut(150)
    if cData.gender == Lang:t('ui.male') then
        cData.gender = 0
    elseif cData.gender == Lang:t('ui.female') then
        cData.gender = 1
    end
    TriggerServerEvent('qb-multicharacter:server:createCharacter', cData)
    Wait(500)
    cb('ok')
end)

RegisterNUICallback('removeCharacter', function(data, cb)
    TriggerServerEvent('qb-multicharacter:server:deleteCharacter', data.citizenid)
    destroyPreviewPeds()
    TriggerEvent('qb-multicharacter:client:chooseChar')
    cb('ok')
end)
