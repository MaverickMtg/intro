local QBCore     = exports['qb-core']:GetCoreObject()

local ShopList   = {} -- public shop data from server
local Spawned    = {} -- [shopId] = { peds = {..}, blip = handle }
local isCrafting = false
local isRobbing  = false

-- ═══════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════

local function SpawnPed(model, pt)
    local hash = joaat(model)
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 50 do
        Wait(100)
        t = t + 1
    end
    if not HasModelLoaded(hash) then return nil end

    local ped = CreatePed(0, hash, pt.x, pt.y, pt.z - 1.0, pt.w or 0.0, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedFleeAttributes(ped, 0, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetModelAsNoLongerNeeded(hash)
    return ped
end

local function GetPlayerItems()
    local pd = QBCore.Functions.GetPlayerData()
    local items = {}
    if pd and pd.items then
        for slot, item in pairs(pd.items) do
            if item and item.name and item.amount and item.amount > 0 then
                items[#items + 1] = {
                    slot   = slot,
                    name   = item.name,
                    label  = item.label or item.name,
                    amount = item.amount,
                    image  = item.image or (item.name .. '.png'),
                }
            end
        end
    end
    return items
end

local function ClearShop(id)
    local s = Spawned[id]
    if not s then return end
    for _, ped in pairs(s.peds or {}) do
        if DoesEntityExist(ped) then
            exports['qb-target']:RemoveTargetEntity(ped)
            DeleteEntity(ped)
        end
    end
    for _, zone in ipairs(s.zones or {}) do
        exports['qb-target']:RemoveZone(zone)
    end
    if s.blip then RemoveBlip(s.blip) end
    Spawned[id] = nil
end

local function ClearAll()
    for id in pairs(Spawned) do ClearShop(id) end
end

-- ═══════════════════════════════════════
--  BUILD SHOPS (PEDS / BLIPS / TARGETS)
-- ═══════════════════════════════════════

local function BuildShop(shop)
    ClearShop(shop.id)
    local models = Config.Peds[shop.type] or Config.Peds.grocery
    local entry = { peds = {}, zones = {}, blip = nil }
    local c = shop.coords or {}

    -- SELLER PED (staff/manage)
    if c.seller then
        local ped = SpawnPed(models.seller, c.seller)
        if ped then
            entry.peds[#entry.peds + 1] = ped
            exports['qb-target']:AddTargetEntity(ped, {
                options = { {
                    type   = 'client',
                    event  = 'lt-shops:client:openManage',
                    icon   = 'fas fa-briefcase',
                    label  = 'إدارة المتجر | ' .. shop.blip_name,
                    shopId = shop.id,
                } },
                distance = Config.InteractDistance,
            })
        end
    end

    -- BUYER PED (customers)
    if c.buyer then
        local ped = SpawnPed(models.buyer, c.buyer)
        if ped then
            entry.peds[#entry.peds + 1] = ped
            exports['qb-target']:AddTargetEntity(ped, {
                options = { {
                    type   = 'client',
                    event  = 'lt-shops:client:openBuyer',
                    icon   = 'fas fa-shopping-cart',
                    label  = shop.type == 'weapon' and ('شراء أسلحة | ' .. shop.blip_name) or
                    ('شراء بقالة | ' .. shop.blip_name),
                    shopId = shop.id,
                } },
                distance = Config.InteractDistance,
            })
        end
    end

    -- STASH / SAFE ZONE
    if c.stash then
        local zoneName = 'ltshop_stash_' .. shop.id
        exports['qb-target']:AddCircleZone(zoneName, vector3(c.stash.x, c.stash.y, c.stash.z), 1.0, {
            name = zoneName,
            useZ = true,
        }, {
            options = {
                {
                    type   = 'client',
                    event  = 'lt-shops:client:openStorage',
                    icon   = 'fas fa-boxes-stacked',
                    label  = 'مخزن المتجر',
                    shopId = shop.id,
                },
                {
                    type   = 'client',
                    event  = 'lt-shops:client:robSafe',
                    icon   = 'fas fa-user-secret',
                    label  = 'فتح الخزنة (Lockpick)',
                    shopId = shop.id,
                },
            },
            distance = Config.InteractDistance,
        })
        entry.zones[#entry.zones + 1] = zoneName
    end

    -- CRAFTING ZONE (weapon shops)
    if shop.type == 'weapon' and c.crafting then
        local zoneName = 'ltshop_craft_' .. shop.id
        exports['qb-target']:AddCircleZone(zoneName, vector3(c.crafting.x, c.crafting.y, c.crafting.z), 1.2, {
            name = zoneName,
            useZ = true,
        }, {
            options = { {
                type   = 'client',
                event  = 'lt-shops:client:openCrafting',
                icon   = 'fas fa-wrench',
                label  = 'طاولة تصنيع الأسلحة',
                shopId = shop.id,
            } },
            distance = Config.InteractDistance,
        })
        entry.zones[#entry.zones + 1] = zoneName
    end

    -- BLIP (custom owner-chosen name)
    if c.buyer or c.seller then
        local pt = c.buyer or c.seller
        local bcfg = Config.Blips[shop.type] or Config.Blips.grocery
        local blip = AddBlipForCoord(pt.x, pt.y, pt.z)
        SetBlipSprite(blip, bcfg.sprite)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, bcfg.scale)
        -- Weapon shop: green if open, red if closed. Grocery: always green
        if shop.type == 'weapon' then
            SetBlipColour(blip, shop.is_open and 2 or 1) -- 2=green, 1=red
        else
            SetBlipColour(blip, 2)               -- 2=green (always open)
        end
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(shop.blip_name ..
        (shop.type == 'weapon' and (shop.is_open and ' (مفتوح)' or ' (مغلق)') or ''))
        EndTextCommandSetBlipName(blip)
        entry.blip = blip
    end

    Spawned[shop.id] = entry
end

RegisterNetEvent('lt-shops:client:syncShops', function(shops)
    ShopList = shops or {}
    local seen = {}
    for _, shop in ipairs(ShopList) do
        seen[shop.id] = true
        BuildShop(shop)
    end
    for id in pairs(Spawned) do
        if not seen[id] then ClearShop(id) end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('lt-shops:server:requestSync')
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('lt-shops:server:requestSync')
end)

-- ═══════════════════════════════════════
--  OPEN UIs
-- ═══════════════════════════════════════

RegisterNetEvent('lt-shops:client:openManage', function(data)
    local shopId = data.shopId
    QBCore.Functions.TriggerCallback('lt-shops:server:openManage', function(res)
        if not res then return end
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'openManage',
            data   = res,
            items  = GetPlayerItems(),
        })
    end, shopId)
end)

RegisterNetEvent('lt-shops:client:openBuyer', function(data)
    local shopId = data.shopId
    QBCore.Functions.TriggerCallback('lt-shops:server:openBuyer', function(res)
        if not res then return end
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openBuyer', data = res })
    end, shopId)
end)

RegisterNetEvent('lt-shops:client:openStorage', function(data)
    local shopId = data.shopId
    QBCore.Functions.TriggerCallback('lt-shops:server:openStorage', function(res)
        if not res then return end
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'openStorage',
            data   = res,
            items  = GetPlayerItems(),
        })
    end, shopId)
end)

RegisterNetEvent('lt-shops:client:openCrafting', function(data)
    local shopId = data.shopId
    QBCore.Functions.TriggerCallback('lt-shops:server:openCrafting', function(res)
        if not res then return end
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openCrafting', data = res })
    end, shopId)
end)

RegisterNetEvent('lt-shops:client:openAdmin', function()
    QBCore.Functions.TriggerCallback('lt-shops:server:getAdminData', function(res)
        if not res then return end
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openAdmin', data = res })
    end)
end)

-- ═══════════════════════════════════════
--  CRAFTING PROGRESS
-- ═══════════════════════════════════════

RegisterNetEvent('lt-shops:client:doCraft', function(label, time)
    if isCrafting then return end
    isCrafting = true
    SetNuiFocus(false, false)

    QBCore.Functions.Progressbar('ltshop_craft', 'تصنيع ' .. label .. '...', time, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = 'mini@repair',
        anim = 'fixing_a_ped',
        flags = 49,
    }, {}, {}, function() -- done
        isCrafting = false
        StopAnimTask(PlayerPedId(), 'mini@repair', 'fixing_a_ped', 1.0)
        TriggerServerEvent('lt-shops:server:finishCraft')
    end, function() -- cancel
        isCrafting = false
        StopAnimTask(PlayerPedId(), 'mini@repair', 'fixing_a_ped', 1.0)
        TriggerServerEvent('lt-shops:server:cancelCraft')
        QBCore.Functions.Notify('تم إلغاء التصنيع', 'error')
    end)
end)

-- ═══════════════════════════════════════
--  SAFE ROBBERY
-- ═══════════════════════════════════════

RegisterNetEvent('lt-shops:client:robSafe', function(data)
    if isRobbing then return end
    TriggerServerEvent('lt-shops:server:startRobSafe', data.shopId)
end)

RegisterNetEvent('lt-shops:client:doRobSafe', function(time)
    if isRobbing then return end
    isRobbing = true

    QBCore.Functions.Progressbar('ltshop_rob', 'محاولة فتح الخزنة...', time, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
        anim = 'machinic_loop_mechandplayer',
        flags = 49,
    }, {}, {}, function() -- done
        isRobbing = false
        StopAnimTask(PlayerPedId(), 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer', 1.0)
        TriggerServerEvent('lt-shops:server:finishRobSafe')
    end, function() -- cancel
        isRobbing = false
        StopAnimTask(PlayerPedId(), 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer', 1.0)
        TriggerServerEvent('lt-shops:server:cancelRobSafe')
        QBCore.Functions.Notify('تراجعت عن السرقة', 'error')
    end)
end)

RegisterNetEvent('lt-shops:client:policeBlip', function(pt, name)
    local pd = QBCore.Functions.GetPlayerData()
    if not pd or not pd.job or pd.job.name ~= 'police' or not pd.job.onduty then return end
    local blip = AddBlipForCoord(pt.x, pt.y, pt.z)
    SetBlipSprite(blip, 161)
    SetBlipScale(blip, 1.2)
    SetBlipColour(blip, 1)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('سرقة خزنة: ' .. (name or 'متجر'))
    EndTextCommandSetBlipName(blip)
    SetTimeout(60000, function() RemoveBlip(blip) end)
end)

-- ═══════════════════════════════════════
--  NUI CALLBACKS
-- ═══════════════════════════════════════

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

local function RefreshManage(shopId)
    Wait(350)
    QBCore.Functions.TriggerCallback('lt-shops:server:openManage', function(res)
        if not res then return end
        SendNUIMessage({ action = 'refreshManage', data = res, items = GetPlayerItems() })
    end, shopId)
end

RegisterNUICallback('addListing', function(data, cb)
    TriggerServerEvent('lt-shops:server:addListing', tonumber(data.shopId), {
        itemName = data.itemName,
        quantity = tonumber(data.quantity),
        price    = tonumber(data.price),
        slot     = tonumber(data.slot),
        image    = data.image,
    })
    RefreshManage(tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('removeListing', function(data, cb)
    TriggerServerEvent('lt-shops:server:removeListing', tonumber(data.shopId), tonumber(data.id))
    RefreshManage(tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('updateListing', function(data, cb)
    TriggerServerEvent('lt-shops:server:updateListing', tonumber(data.shopId), tonumber(data.id), tonumber(data.price))
    RefreshManage(tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('hireStaff', function(data, cb)
    TriggerServerEvent('lt-shops:server:hireStaff', tonumber(data.shopId), tonumber(data.targetId), data.grade)
    RefreshManage(tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('fireStaff', function(data, cb)
    TriggerServerEvent('lt-shops:server:fireStaff', tonumber(data.shopId), data.citizenid)
    RefreshManage(tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('setGrade', function(data, cb)
    TriggerServerEvent('lt-shops:server:setGrade', tonumber(data.shopId), data.citizenid, data.grade)
    RefreshManage(tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('setBlipName', function(data, cb)
    TriggerServerEvent('lt-shops:server:setBlipName', tonumber(data.shopId), data.name)
    RefreshManage(tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('toggleOpen', function(data, cb)
    TriggerServerEvent('lt-shops:server:toggleOpen', tonumber(data.shopId))
    RefreshManage(tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('withdrawSafe', function(data, cb)
    TriggerServerEvent('lt-shops:server:withdrawSafe', tonumber(data.shopId), tonumber(data.amount))
    RefreshManage(tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('issueLicense', function(data, cb)
    TriggerServerEvent('lt-shops:server:issueLicense', tonumber(data.shopId), tonumber(data.targetId), data.signature)
    cb('ok')
end)

RegisterNUICallback('depositStorage', function(data, cb)
    -- ✅ FIXED: Add slot parameter
    TriggerServerEvent('lt-shops:server:depositStorage', tonumber(data.shopId), data.itemName, tonumber(data.amount), tonumber(data.slot))
    Wait(350)
    QBCore.Functions.TriggerCallback('lt-shops:server:openStorage', function(res)
        if res then SendNUIMessage({ action = 'refreshStorage', data = res, items = GetPlayerItems() }) end
    end, tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('withdrawStorage', function(data, cb)
    TriggerServerEvent('lt-shops:server:withdrawStorage', tonumber(data.shopId), data.itemName, tonumber(data.amount))
    Wait(350)
    QBCore.Functions.TriggerCallback('lt-shops:server:openStorage', function(res)
        if res then SendNUIMessage({ action = 'refreshStorage', data = res, items = GetPlayerItems() }) end
    end, tonumber(data.shopId))
    cb('ok')
end)

RegisterNUICallback('buyItem', function(data, cb)
    QBCore.Functions.TriggerCallback('lt-shops:server:buyItem', function(success)
        QBCore.Functions.TriggerCallback('lt-shops:server:openBuyer', function(res)
            if res then SendNUIMessage({ action = 'refreshBuyer', data = res }) end
        end, tonumber(data.shopId))
    end, tonumber(data.shopId), tonumber(data.id), tonumber(data.quantity))
    cb('ok')
end)

RegisterNUICallback('startCraft', function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent('lt-shops:server:startCraft', tonumber(data.shopId), tonumber(data.index))
    cb('ok')
end)

-- ADMIN NUI callbacks
RegisterNUICallback('getMyCoords', function(_, cb)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    cb({ x = math.floor(p.x * 10000) / 10000, y = math.floor(p.y * 10000) / 10000, z = math.floor(p.z * 10000) / 10000, w =
    math.floor(h * 10000) / 10000 })
end)

local function RefreshAdmin()
    Wait(350)
    QBCore.Functions.TriggerCallback('lt-shops:server:getAdminData', function(res)
        if res then SendNUIMessage({ action = 'refreshAdmin', data = res }) end
    end)
end

RegisterNUICallback('adminCreateShop', function(data, cb)
    TriggerServerEvent('lt-shops:server:adminCreateShop', data)
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminDeleteShop', function(data, cb)
    TriggerServerEvent('lt-shops:server:adminDeleteShop', tonumber(data.id))
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminSetOwner', function(data, cb)
    TriggerServerEvent('lt-shops:server:adminSetOwner', tonumber(data.id), tonumber(data.targetId))
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminIssueLicense', function(data, cb)
    TriggerServerEvent('lt-shops:server:adminIssueLicense', tonumber(data.targetId), data.signature)
    cb('ok')
end)

RegisterNUICallback('adminAddAdmin', function(data, cb)
    TriggerServerEvent('lt-shops:server:adminAddAdmin', tostring(data.input))
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminRemoveAdmin', function(data, cb)
    TriggerServerEvent('lt-shops:server:adminRemoveAdmin', data.identifier)
    RefreshAdmin()
    cb('ok')
end)

RegisterNUICallback('adminUpdateShopCoords', function(data, cb)
    TriggerServerEvent('lt-shops:server:adminUpdateShopCoords', data)
    cb('ok')
end)

-- ═══════════════════════════════════════
--  CLEANUP
-- ═══════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ClearAll()
end)
