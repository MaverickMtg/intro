-- ============================================================
--  VGX Showroom v4 — Client
--  Multi-showroom, everything (showrooms / parking slots /
--  entrance / drop-off) is created in-game via /showrooms.
-- ============================================================

local QBCore       = exports['qb-core']:GetCoreObject()
local isUIOpen     = false
local Showroom     = {}   -- [id] = { id, name, points, slots }
local Blips        = {}   -- [id] = blip handle
local spawnedVehs  = {}   -- ["sid:slot"] = vehicle handle
local spawnGen     = {}   -- ["sid:slot"] = spawn generation (anti ghost-duplicate)
local listingsBusy = false
local camEntity    = nil
local testDriveVeh = nil
local isLoggedIn   = false
local MyRoles      = {}   -- [showroomId(string)] = role
local rolesAt      = 0
local currentSR    = nil  -- showroom id the open UI belongs to

local function SlotKey(sid, slotNo) return tostring(sid) .. ':' .. tostring(slotNo) end

-- ── Notify ────────────────────────────────────────────────
RegisterNetEvent('vgx-showroom:notify', function(msg, ntype)
    QBCore.Functions.Notify(msg, ntype or 'primary', Config.NotifyDuration)
end)

-- ── NUI helpers ───────────────────────────────────────────
local function SendUI(action, data)
    SendNUIMessage({ action = action, data = data or {} })
end

local function CloseUI()
    isUIOpen = false
    SetNuiFocus(false, false)
    SendUI('close')
    ReleaseCamera()
end

-- ── Camera ────────────────────────────────────────────────
local function FocusOnVehicle(veh)
    if not veh or not DoesEntityExist(veh) then return end
    ReleaseCamera()
    local pos    = GetEntityCoords(veh)
    local fwd    = GetEntityForwardVector(veh)
    local camPos = vector3(pos.x - fwd.x * 6.5, pos.y - fwd.y * 6.5, pos.z + 1.8)
    camEntity    = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(camEntity, camPos.x, camPos.y, camPos.z)
    PointCamAtEntity(camEntity, veh, 0.0, 0.0, 0.3, true)
    SetCamFov(camEntity, 55.0)
    RenderScriptCams(true, true, 600, true, true)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleLights(veh, 2)
end

function ReleaseCamera()
    if camEntity then
        RenderScriptCams(false, true, 600, true, true)
        DestroyCam(camEntity, true)
        camEntity = nil
    end
    for _, v in pairs(spawnedVehs) do
        if DoesEntityExist(v) then
            SetVehicleLights(v, 0)
            SetVehicleEngineOn(v, false, true, true)
        end
    end
end

-- ── Slot lookup ───────────────────────────────────────────
local function GetSlot(sid, slotNo)
    local sr = Showroom[tonumber(sid)]
    if not sr then return nil end
    slotNo = tonumber(slotNo)
    for _, s in ipairs(sr.slots or {}) do
        if s.slot_no == slotNo then return s end
    end
    return nil
end

-- ── Spawn / despawn display vehicles ──────────────────────
local function SpawnSlot(data)
    local sid    = tonumber(data.showroomId)
    local slotNo = tonumber(data.slotNo)
    if not sid or not slotNo then return end

    -- coords come with the event (server) or from the synced slot data
    local c, heading = data.coords, data.heading
    if not c then
        local slot = GetSlot(sid, slotNo)
        if not slot then return end
        c, heading = { x = slot.x, y = slot.y, z = slot.z }, slot.heading
    end

    local key = SlotKey(sid, slotNo)

    -- generation guard
    spawnGen[key] = (spawnGen[key] or 0) + 1
    local myGen = spawnGen[key]

    if spawnedVehs[key] and DoesEntityExist(spawnedVehs[key]) then
        DeleteEntity(spawnedVehs[key])
        spawnedVehs[key] = nil
    end

    local model = data.model
    if type(model) == 'string' then
        model = joaat(model)
    end

    RequestModel(model)
    local t = GetGameTimer() + 10000
    while not HasModelLoaded(model) do
        Wait(100)
        if GetGameTimer() > t then
            print('[vgx-showroom] model timeout: ' .. tostring(model))
            return
        end
    end

    -- a newer spawn started for this slot while we were loading — abort
    if spawnGen[key] ~= myGen then
        SetModelAsNoLongerNeeded(model)
        return
    end

    if spawnedVehs[key] and DoesEntityExist(spawnedVehs[key]) then
        DeleteEntity(spawnedVehs[key])
        spawnedVehs[key] = nil
    end

    -- Spawn slightly higher so it can drop down cleanly
    local veh = CreateVehicle(model, c.x, c.y, c.z + 0.2, heading or 0.0, false, false)

    RequestCollisionAtCoord(c.x, c.y, c.z)
    local colTimeout = GetGameTimer() + 1500
    while not HasCollisionLoadedAroundEntity(veh) and GetGameTimer() < colTimeout do
        Wait(10)
    end

    SetEntityCoordsNoOffset(veh, c.x, c.y, c.z + 0.2, false, false, false)
    Wait(100) -- let the physics engine register the ground geometry
    PlaceObjectOnGroundProperly(veh)

    SetVehicleNumberPlateText(veh, data.plate or 'SHOWRM')
    SetEntityAsMissionEntity(veh, true, true)
    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 10)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehicleModKit(veh, 0)

    if data.mods and next(data.mods) then
        QBCore.Functions.SetVehicleProperties(veh, data.mods)
    end

    FreezeEntityPosition(veh, true)

    spawnedVehs[key] = veh
    SetModelAsNoLongerNeeded(model)
end

local function DespawnSlot(sid, slotNo)
    local key = SlotKey(tonumber(sid), tonumber(slotNo))
    spawnGen[key] = (spawnGen[key] or 0) + 1 -- abort any in-flight spawn
    if spawnedVehs[key] and DoesEntityExist(spawnedVehs[key]) then
        DeleteEntity(spawnedVehs[key])
    end
    spawnedVehs[key] = nil
end

RegisterNetEvent('vgx-showroom:spawnSlot', function(data) SpawnSlot(data) end)
RegisterNetEvent('vgx-showroom:despawnSlot', function(sid, slotNo) DespawnSlot(sid, slotNo) end)

-- ── Blips ─────────────────────────────────────────────────
local function RebuildBlips()
    for _, b in pairs(Blips) do RemoveBlip(b) end
    Blips = {}
    for id, sr in pairs(Showroom) do
        local e = sr.points and sr.points.entrance
        if e then
            local blip = AddBlipForCoord(e.x, e.y, e.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipColour(blip, Config.Blip.color)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(sr.name or 'Showroom')
            EndTextCommandSetBlipName(blip)
            Blips[id] = blip
        end
    end
end

-- ── Sync from server ──────────────────────────────────────
function LoadListings()
    if listingsBusy then return end
    listingsBusy = true
    QBCore.Functions.TriggerCallback('vgx-showroom:getListings', function(listings)
        -- full resync: clear everything currently spawned, then spawn fresh
        for key in pairs(spawnedVehs) do
            local sid, slotNo = key:match('^(%d+):(%d+)$')
            DespawnSlot(sid, slotNo)
        end
        for _, l in ipairs(listings or {}) do
            SpawnSlot({
                showroomId = l.showroom_id,
                slotNo     = l.slot_id,
                model      = l.model,
                plate      = l.plate,
                mods       = l.mods and json.decode(l.mods) or {},
            })
        end
        listingsBusy = false
    end)
end

RegisterNetEvent('vgx-showroom:client:sync', function(list)
    Showroom = {}
    for _, sr in ipairs(list or {}) do
        Showroom[sr.id] = sr
    end
    if isLoggedIn then
        RebuildBlips()
        LoadListings()
    end
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    isLoggedIn = true
    Wait(2000)
    TriggerServerEvent('vgx-showroom:server:requestSync')
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    isLoggedIn = false
end)

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(500) end
    isLoggedIn = true
    Wait(2000)
    TriggerServerEvent('vgx-showroom:server:requestSync')
end)

-- ── My roles (per showroom, cached) ───────────────────────
local function RefreshMyRoles()
    QBCore.Functions.TriggerCallback('vgx-showroom:getMyRoles', function(roles)
        MyRoles = roles or {}
        rolesAt = GetGameTimer()
    end)
end

local function IsStaffOf(sid)
    if (GetGameTimer() - rolesAt) > 15000 then
        rolesAt = GetGameTimer()
        RefreshMyRoles()
    end
    return MyRoles[tostring(sid)] ~= nil
end

-- ── Entrance markers + E key (every showroom) ─────────────
CreateThread(function()
    local inZone = false
    while true do
        local sleep = 1000

        if isLoggedIn and not isUIOpen then
            local playerCoords = GetEntityCoords(PlayerPedId())
            for id, sr in pairs(Showroom) do
                local e = sr.points and sr.points.entrance
                if e then
                    local coords = vector3(e.x, e.y, e.z)
                    local dist = #(playerCoords - coords)

                    if dist < 15.0 then
                        sleep = 0
                        DrawMarker(
                            27,
                            coords.x, coords.y, coords.z - 1.0,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            1.2, 1.2, 0.8,
                            79, 142, 247, 180,
                            false, false, 2, false, nil, nil, false
                        )

                        if dist < Config.EntranceRadius then
                            BeginTextCommandDisplayHelp('STRING')
                            AddTextComponentSubstringPlayerName('[ E ] Browse ' .. (sr.name or 'Showroom'))
                            EndTextCommandDisplayHelp(0, false, true, -1)

                            if IsControlJustReleased(0, 38) and not inZone then
                                inZone = true
                                TriggerEvent('vgx-showroom:openMain', id)
                            end
                        else
                            inZone = false
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- ── Vehicle slot interact loop ────────────────────────────
CreateThread(function()
    while true do
        local sleep = 1000

        if isLoggedIn and not isUIOpen and next(spawnedVehs) ~= nil then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local nearKey  = nil
            local nearDist = 3.0

            for key, veh in pairs(spawnedVehs) do
                if DoesEntityExist(veh) then
                    local d = #(playerCoords - GetEntityCoords(veh))
                    if d < nearDist then
                        nearDist = d
                        nearKey = key
                    end
                end
            end

            if nearKey then
                sleep = 0
                local sid, slotNo = nearKey:match('^(%d+):(%d+)$')
                sid, slotNo = tonumber(sid), tonumber(slotNo)

                if IsStaffOf(sid) then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('[ E ] Inspect / Manage  |  [ G ] Test Drive')
                    EndTextCommandDisplayHelp(0, false, true, -1)
                else
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('[ E ] Inspect Vehicle  |  [ G ] Test Drive')
                    EndTextCommandDisplayHelp(0, false, true, -1)
                end

                if IsControlJustReleased(0, 38) then -- E
                    TriggerEvent('vgx-showroom:inspectSlot', sid, slotNo)
                    Wait(500)
                elseif IsControlJustReleased(0, 47) then -- G
                    TriggerEvent('vgx-showroom:testDrive', sid, slotNo)
                    Wait(500)
                end
            end
        end

        Wait(sleep)
    end
end)

-- ── Open main UI ──────────────────────────────────────────
AddEventHandler('vgx-showroom:openMain', function(showroomId)
    QBCore.Functions.TriggerCallback('vgx-showroom:getData', function(d)
        if not d then
            QBCore.Functions.Notify('Could not load showroom', 'error')
            return
        end
        currentSR = d.showroomId
        isUIOpen = true
        SetNuiFocus(true, true)
        SendUI('openMain', {
            data         = d,
            showroomName = d.name,
            taxRate      = Config.TaxRate,
        })
    end, showroomId)
end)

-- ── Inspect slot ──────────────────────────────────────────
AddEventHandler('vgx-showroom:inspectSlot', function(sid, slotNo)
    QBCore.Functions.TriggerCallback('vgx-showroom:getData', function(d)
        if not d then return end

        local listing = nil
        for _, l in ipairs(d.listings) do
            if l.slot_id == slotNo then
                listing = l
                break
            end
        end

        if not listing then
            QBCore.Functions.Notify('No vehicle listed in this slot', 'error')
            return
        end

        local veh     = spawnedVehs[SlotKey(sid, slotNo)]
        local details = {}
        if veh and DoesEntityExist(veh) then
            details.suspension   = GetVehicleMod(veh, 15)
            details.transmission = GetVehicleMod(veh, 13)
            details.engine       = GetVehicleMod(veh, 11)
            details.brakes       = GetVehicleMod(veh, 12)
            details.turbo        = IsToggleModOn(veh, 18)
            details.maxSpeed     = GetVehicleEstimatedMaxSpeed(veh) * 3.6
            details.class        = GetVehicleClass(veh)
        end

        currentSR = d.showroomId
        FocusOnVehicle(veh)
        isUIOpen = true
        SetNuiFocus(true, true)
        SendUI('openInspect', {
            listing    = listing,
            details    = details,
            role       = d.role,
            taxRate    = Config.TaxRate,
            showroomId = d.showroomId,
        })
    end, sid)
end)

-- ── Test drive ────────────────────────────────────────────
AddEventHandler('vgx-showroom:testDrive', function(sid, slotNo)
    if not Config.AllowTestDrive then
        QBCore.Functions.Notify('Test drives not available', 'error')
        return
    end

    local sr = Showroom[tonumber(sid)]
    if not sr then return end

    -- test-drive spawn point captured in-game (fallback: the entrance)
    local td = sr.points and (sr.points.tdspawn or sr.points.entrance)
    if not td then
        QBCore.Functions.Notify('This showroom has no test-drive point', 'error')
        return
    end
    local testCoords  = vector3(td.x, td.y, td.z)
    local testHeading = td.w or 0.0

    QBCore.Functions.TriggerCallback('vgx-showroom:getData', function(d)
        if not d then return end
        local listing = nil
        for _, l in ipairs(d.listings) do
            if l.slot_id == slotNo then
                listing = l
                break
            end
        end
        if not listing then return end

        local model = listing.model
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(100) end

        -- networked entity so it is stable across frameworks
        testDriveVeh = CreateVehicle(model, testCoords.x, testCoords.y, testCoords.z + 0.5, testHeading, true, false)

        local netId = NetworkGetNetworkIdFromEntity(testDriveVeh)
        SetNetworkIdCanMigrate(netId, true)
        SetNetworkIdExistsOnAllMachines(netId, true)

        local plate = 'TESTDRV'
        SetVehicleNumberPlateText(testDriveVeh, plate)

        -- copy showroom vehicle properties & liveries
        local showroomVeh = spawnedVehs[SlotKey(sid, slotNo)]
        if showroomVeh and DoesEntityExist(showroomVeh) then
            local showroomProps = QBCore.Functions.GetVehicleProperties(showroomVeh)
            QBCore.Functions.SetVehicleProperties(testDriveVeh, showroomProps)

            SetVehicleModKit(testDriveVeh, 0)
            if showroomProps.livery then
                SetVehicleLivery(testDriveVeh, showroomProps.livery)
            end
        end

        SetPedIntoVehicle(PlayerPedId(), testDriveVeh, -1)
        SetModelAsNoLongerNeeded(model)

        -- give the network engine a moment to register the entity globally
        Wait(200)

        SetVehicleNeedsToBeHotwired(testDriveVeh, false)
        SetVehicleHasBeenOwnedByPlayer(testDriveVeh, true)

        if GetResourceState('qb-vehiclekeys') == 'started' then
            pcall(function()
                exports['qb-vehiclekeys']:GiveKeys(plate)
            end)
        elseif GetResourceState('wasabi_carlock') == 'started' then
            pcall(function()
                exports.wasabi_carlock:GiveKeys(plate)
            end)
        else
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        end

        QBCore.Functions.Notify('Test drive started! Drive for ' .. Config.TestDriveTime .. ' minutes.', 'primary')

        SetTimeout(Config.TestDriveTime * 60 * 1000, function()
            if testDriveVeh and DoesEntityExist(testDriveVeh) then
                TaskLeaveVehicle(PlayerPedId(), testDriveVeh, 0)
                Wait(1500)

                -- return the player to the showroom
                local ret = sr.points and (sr.points.tdreturn or sr.points.entrance)
                if ret then
                    SetEntityCoords(PlayerPedId(), ret.x, ret.y, ret.z)
                end

                if GetResourceState('qb-vehiclekeys') == 'started' then
                    pcall(function() exports['qb-vehiclekeys']:RemoveKeys(plate) end)
                else
                    TriggerEvent('vehiclekeys:client:RemoveKeys', plate)
                end

                DeleteEntity(testDriveVeh)
                testDriveVeh = nil
                QBCore.Functions.Notify('Test drive ended. Returned to showroom.', 'primary')
            end
        end)
    end, sid)
end)

-- ── Drive-in listing (store the vehicle you're in) ────────
RegisterNetEvent('vgx-showroom:parkVehicle', function(showroomId)
    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        QBCore.Functions.Notify('You must be inside a vehicle', 'error')
        return
    end

    local veh   = GetVehiclePedIsIn(ped, false)
    local props = QBCore.Functions.GetVehicleProperties(veh)

    TriggerServerEvent('vgx-showroom:storeVehicle', showroomId, 0, props)
end)

CreateThread(function()
    while true do
        local sleep = 1000
        local ped   = PlayerPedId()

        if isLoggedIn and IsPedInAnyVehicle(ped, false) then
            local pos = GetEntityCoords(ped)

            for id, sr in pairs(Showroom) do
                local dp = sr.points and sr.points.dropoff
                if dp then
                    local dropCoords = vector3(dp.x, dp.y, dp.z)
                    local dist = #(pos - dropCoords)

                    if dist < 25.0 then
                        if dist < 10.0 then
                            sleep = 0
                            DrawMarker(
                                1,
                                dropCoords.x, dropCoords.y, dropCoords.z - 1.0,
                                0.0, 0.0, 0.0,
                                0.0, 0.0, 0.0,
                                3.0, 3.0, 1.0,
                                0, 255, 0, 150,
                                false, false, 2, false
                            )

                            if dist < Config.DropOffRadius then
                                BeginTextCommandDisplayHelp('STRING')
                                AddTextComponentSubstringPlayerName('[ E ] Store Showroom Vehicle — ' .. (sr.name or ''))
                                EndTextCommandDisplayHelp(0, false, true, -1)

                                if IsControlJustReleased(0, 38) then
                                    TriggerEvent('vgx-showroom:parkVehicle', id)
                                end
                            end
                        elseif sleep > 300 then
                            sleep = 300
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

RegisterNetEvent('vgx-showroom:vehicleStored', function(showroomId)
    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)

    TaskLeaveVehicle(ped, veh, 16)

    Wait(1500)

    NetworkRequestControlOfEntity(veh)

    local timeout = GetGameTimer() + 5000
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < timeout do
        Wait(0)
        NetworkRequestControlOfEntity(veh)
    end

    SetEntityAsMissionEntity(veh, true, true)

    DeleteVehicle(veh)
    DeleteEntity(veh)

    local sr = Showroom[tonumber(showroomId)]
    local dp = sr and sr.points and sr.points.dropoff
    if dp then
        SetEntityCoords(ped, dp.x, dp.y, dp.z + 1.0)
    end

    RefreshMyRoles()
end)

-- ══════════════════════════════════════════════════════════
--  ADMIN PANEL (/showrooms)
-- ══════════════════════════════════════════════════════════

RegisterNetEvent('vgx-showroom:client:openAdmin', function()
    QBCore.Functions.TriggerCallback('vgx-showroom:getAdminData', function(res)
        if not res then return end
        isUIOpen = true
        SetNuiFocus(true, true)
        SendUI('openAdmin', res)
    end)
end)

local function RefreshAdmin()
    Wait(350)
    QBCore.Functions.TriggerCallback('vgx-showroom:getAdminData', function(res)
        if res then SendUI('refreshAdmin', res) end
    end)
end

-- current position; uses the VEHICLE when the player is driving
-- (perfect for capturing parking-slot spots with the right heading)
RegisterNUICallback('getMyCoords', function(_, cb)
    local ped = PlayerPedId()
    local ent = ped
    if IsPedInAnyVehicle(ped, false) then
        ent = GetVehiclePedIsIn(ped, false)
    end
    local p = GetEntityCoords(ent)
    local h = GetEntityHeading(ent)
    cb({
        x = math.floor(p.x * 10000) / 10000,
        y = math.floor(p.y * 10000) / 10000,
        z = math.floor(p.z * 10000) / 10000,
        w = math.floor(h * 10000) / 10000,
    })
end)

RegisterNUICallback('adminCreate', function(data, cb)
    TriggerServerEvent('vgx-showroom:server:adminCreate', data)
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminDelete', function(data, cb)
    TriggerServerEvent('vgx-showroom:server:adminDelete', tonumber(data.id))
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminRename', function(data, cb)
    TriggerServerEvent('vgx-showroom:server:adminRename', tonumber(data.id), data.name)
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminSetOwner', function(data, cb)
    TriggerServerEvent('vgx-showroom:server:adminSetOwner', tonumber(data.id), tonumber(data.targetId))
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminUpdatePoints', function(data, cb)
    TriggerServerEvent('vgx-showroom:server:adminUpdatePoints', tonumber(data.id), data.points)
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminAddSlot', function(data, cb)
    TriggerServerEvent('vgx-showroom:server:adminAddSlot', tonumber(data.id), data.point)
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminRemoveSlot', function(data, cb)
    TriggerServerEvent('vgx-showroom:server:adminRemoveSlot', tonumber(data.id), tonumber(data.slotNo))
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminAddAdmin', function(data, cb)
    TriggerServerEvent('vgx-showroom:server:adminAddAdmin', tostring(data.input))
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminRemoveAdmin', function(data, cb)
    TriggerServerEvent('vgx-showroom:server:adminRemoveAdmin', data.identifier)
    RefreshAdmin()
    cb('ok')
end)

-- ── NUI Callbacks (main UI) ───────────────────────────────
RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb('ok')
end)

RegisterNUICallback('inspectSlot', function(body, cb)
    CloseUI()
    Wait(200)
    TriggerEvent('vgx-showroom:inspectSlot', tonumber(body.showroomId) or currentSR, tonumber(body.slotId))
    cb('ok')
end)

RegisterNUICallback('buyVehicle', function(body, cb)
    QBCore.Functions.TriggerCallback('vgx-showroom:buyVehicle', function(res)
        if res.success then
            QBCore.Functions.Notify(res.message, 'success')
            SendUI('updateListings', { listings = res.listings })
            CloseUI()
        else
            QBCore.Functions.Notify(res.message, 'error')
        end
        cb('ok')
    end, tonumber(body.listingId))
end)

RegisterNUICallback('getMyVehicles', function(_, cb)
    QBCore.Functions.TriggerCallback('vgx-showroom:getMyVehicles', function(vehs)
        cb(vehs)
    end)
end)

RegisterNUICallback('addVehicle', function(body, cb)
    body.showroomId = tonumber(body.showroomId) or currentSR
    QBCore.Functions.TriggerCallback('vgx-showroom:addVehicle', function(res)
        if res.success then
            QBCore.Functions.Notify(res.message, 'success')
            SendUI('updateListings', { listings = res.listings })
        else
            QBCore.Functions.Notify(res.message, 'error')
        end
        cb('ok')
    end, body)
end)

RegisterNUICallback('removeVehicle', function(body, cb)
    QBCore.Functions.TriggerCallback('vgx-showroom:removeVehicle', function(res)
        if res.success then
            QBCore.Functions.Notify(res.message, 'success')
            SendUI('updateListings', { listings = res.listings })
        else
            QBCore.Functions.Notify(res.message, 'error')
        end
        cb('ok')
    end, tonumber(body.listingId))
end)

RegisterNUICallback('setPrice', function(body, cb)
    QBCore.Functions.TriggerCallback('vgx-showroom:setPrice', function(res)
        if res.success then
            QBCore.Functions.Notify(res.message, 'success')
            SendUI('updateListings', { listings = res.listings })
        else
            QBCore.Functions.Notify(res.message, 'error')
        end
        cb('ok')
    end, tonumber(body.listingId), tonumber(body.price))
end)

RegisterNUICallback('changeSlot', function(body, cb)
    QBCore.Functions.TriggerCallback('vgx-showroom:changeSlot', function(res)
        if res.success then
            QBCore.Functions.Notify(res.message, 'success')
            SendUI('updateListings', { listings = res.listings })
            SendUI('slotChanged', { newSlot = res.newSlot })
        else
            QBCore.Functions.Notify(res.message, 'error')
        end
        cb('ok')
    end, tonumber(body.listingId), tonumber(body.newSlot))
end)

RegisterNUICallback('treasuryAction', function(body, cb)
    QBCore.Functions.TriggerCallback('vgx-showroom:treasuryAction', function(res)
        if res.success then
            QBCore.Functions.Notify(res.message, 'success')
            SendUI('updateTreasury', { balance = res.balance, log = res.log })
        else
            QBCore.Functions.Notify(res.message, 'error')
        end
        cb('ok')
    end, tonumber(body.showroomId) or currentSR, { action = body.action, amount = tonumber(body.amount) })
end)

RegisterNUICallback('hireStaff', function(body, cb)
    body.showroomId = tonumber(body.showroomId) or currentSR
    QBCore.Functions.TriggerCallback('vgx-showroom:hireStaff', function(res)
        if res.success then
            QBCore.Functions.Notify(res.message, 'success')
            SendUI('updateStaff', { staff = res.staff })
        else
            QBCore.Functions.Notify(res.message, 'error')
        end
        cb('ok')
    end, body)
end)

RegisterNUICallback('fireStaff', function(body, cb)
    QBCore.Functions.TriggerCallback('vgx-showroom:fireStaff', function(res)
        if res.success then
            QBCore.Functions.Notify(res.message, 'success')
            SendUI('updateStaff', { staff = res.staff })
        else
            QBCore.Functions.Notify(res.message, 'error')
        end
        cb('ok')
    end, tonumber(body.staffId))
end)

RegisterNUICallback('getOnlinePlayers', function(body, cb)
    QBCore.Functions.TriggerCallback('vgx-showroom:getOnlinePlayers', function(players)
        cb(players)
    end, tonumber(body and body.showroomId) or currentSR)
end)

RegisterNUICallback('focusSlot', function(body, cb)
    local veh = spawnedVehs[SlotKey(tonumber(body.showroomId) or currentSR, tonumber(body.slotId))]
    if veh and DoesEntityExist(veh) then FocusOnVehicle(veh) end
    cb('ok')
end)

RegisterNUICallback('releaseCamera', function(_, cb)
    ReleaseCamera()
    cb('ok')
end)

-- ── ESC to close ──────────────────────────────────────────
CreateThread(function()
    while true do
        if isUIOpen then
            if IsControlJustReleased(0, 200) then CloseUI() end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ── Cleanup ───────────────────────────────────────────────
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, veh in pairs(spawnedVehs) do
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end
    for _, b in pairs(Blips) do RemoveBlip(b) end
    if testDriveVeh and DoesEntityExist(testDriveVeh) then DeleteEntity(testDriveVeh) end
    ReleaseCamera()
end)
