local QBCore = exports['qb-core']:GetCoreObject()

-- ═══════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════

local Shops        = {}   -- [id] = shop row (coords decoded)
local ShopAdmins   = {}   -- [citizenid] = true (DB admins)
local PendingCraft = {}   -- [src] = { shopId, recipe, started }
local PendingRob   = {}   -- [src] = { shopId, started }
local RobCooldown  = {}   -- [shopId] = os.time() of last attempt

-- ═══════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════

local function LoadShops()
    Shops = {}
    local rows = MySQL.query.await('SELECT * FROM lt_shops', {})
    for _, row in ipairs(rows or {}) do
        row.coords = json.decode(row.coords) or {}
        Shops[row.id] = row
    end
    local admins = MySQL.query.await('SELECT * FROM lt_shop_admins', {})
    ShopAdmins = {}
    for _, a in ipairs(admins or {}) do ShopAdmins[a.identifier] = true end
end

local function PublicShopData()
    local out = {}
    for id, s in pairs(Shops) do
        out[#out + 1] = {
            id        = id,
            type      = s.type,
            label     = s.label,
            blip_name = s.blip_name,
            is_open   = s.is_open == 1 or s.is_open == true,
            coords    = s.coords,
        }
    end
    return out
end

local function SyncAll()
    TriggerClientEvent('lt-shops:client:syncShops', -1, PublicShopData())
end

local function GetShop(id)
    return Shops[tonumber(id)]
end

local function GetRole(shop, citizenid)
    if not shop or not citizenid then return nil end
    if shop.owner_cid == citizenid then return 'owner' end
    local row = MySQL.query.await('SELECT grade FROM lt_shop_employees WHERE shop_id = ? AND citizenid = ?', { shop.id, citizenid })
    if row and row[1] then return row[1].grade end
    return nil
end

local function Perm(role, key)
    if not role then return false end
    local grade = Config.Permissions[role]
    if not grade then return false end
    return grade[key]
end

local function GetIdent(src, kind)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, #kind + 1) == kind .. ':' then return id end
    end
    return nil
end

local function IsSuperAdmin(src)
    local disc, lic = GetIdent(src, 'discord'), GetIdent(src, 'license')
    for _, ident in ipairs(Config.SuperAdmins) do
        if ident == disc or ident == lic then return true end
    end
    return false
end

local function IsShopAdmin(src)
    if IsSuperAdmin(src) then return true end
    local disc, lic = GetIdent(src, 'discord'), GetIdent(src, 'license')
    if disc and ShopAdmins[disc] then return true end
    if lic and ShopAdmins[lic] then return true end
    return false
end

local function NearShop(src, shop, maxDist)
    if not shop or not shop.coords then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local p = GetEntityCoords(ped)
    maxDist = maxDist or 15.0
    for _, pt in pairs(shop.coords) do
        if pt and pt.x then
            local d = #(p - vector3(pt.x, pt.y, pt.z))
            if d <= maxDist then return true end
        end
    end
    return false
end

local function CharName(Player)
    local ci = Player.PlayerData.charinfo or {}
    return (ci.firstname or '') .. ' ' .. (ci.lastname or '')
end

local function Notify(src, msg, typ)
    TriggerClientEvent('QBCore:Notify', src, msg, typ or 'primary')
end

local function GetEmployees(shopId)
    return MySQL.query.await('SELECT citizenid, name, grade FROM lt_shop_employees WHERE shop_id = ?', { shopId }) or {}
end

local function GetListings(shopId)
    return MySQL.query.await('SELECT * FROM lt_shop_items WHERE shop_id = ? ORDER BY item_label ASC', { shopId }) or {}
end

local function GetStorage(shopId)
    return MySQL.query.await('SELECT item_name, item_label, amount FROM lt_shop_storage WHERE shop_id = ? AND amount > 0 ORDER BY item_label ASC', { shopId }) or {}
end

local function StorageAmount(shopId, itemName)
    local n = MySQL.scalar.await('SELECT amount FROM lt_shop_storage WHERE shop_id = ? AND item_name = ?', { shopId, itemName })
    return n or 0
end

local function StorageAdd(shopId, itemName, amount)
    local shared = QBCore.Shared.Items[itemName]
    local label = shared and shared.label or itemName
    MySQL.query.await([[
        INSERT INTO lt_shop_storage (shop_id, item_name, item_label, amount) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
    ]], { shopId, itemName, label, amount })
end

local function StorageRemove(shopId, itemName, amount)
    local cur = StorageAmount(shopId, itemName)
    if cur < amount then return false end
    MySQL.update.await('UPDATE lt_shop_storage SET amount = amount - ? WHERE shop_id = ? AND item_name = ?', { amount, shopId, itemName })
    return true
end

local function StaffNearby(shop)
    -- returns true if any staff member of this shop is within Config.Safe.staffBlockRadius of the stash point
    local pt = shop.coords.stash or shop.coords.seller
    if not pt then return false end
    local center = vector3(pt.x, pt.y, pt.z)
    local staff = {}
    if shop.owner_cid then staff[shop.owner_cid] = true end
    for _, e in ipairs(GetEmployees(shop.id)) do staff[e.citizenid] = true end
    for _, pid in ipairs(QBCore.Functions.GetPlayers()) do
        local P = QBCore.Functions.GetPlayer(pid)
        if P and staff[P.PlayerData.citizenid] then
            local ped = GetPlayerPed(pid)
            if ped ~= 0 and #(GetEntityCoords(ped) - center) <= Config.Safe.staffBlockRadius then
                return true
            end
        end
    end
    return false
end

-- ═══════════════════════════════════════
--  STARTUP / SYNC
-- ═══════════════════════════════════════

CreateThread(function()
    LoadShops()
    SyncAll()
end)

RegisterNetEvent('lt-shops:server:requestSync', function()
    TriggerClientEvent('lt-shops:client:syncShops', source, PublicShopData())
end)

-- ═══════════════════════════════════════
--  MANAGE (SELLER PED)
-- ═══════════════════════════════════════

QBCore.Functions.CreateCallback('lt-shops:server:openManage', function(source, cb, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    local shop = GetShop(shopId)
    if not Player or not shop then return cb(nil) end
    if not NearShop(source, shop) then return cb(nil) end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not role then
        Notify(source, 'أنت لا تعمل في هذا المتجر', 'error')
        return cb(nil)
    end

    local perms = Config.Permissions[role]
    cb({
        role      = role,
        perms     = perms,
        shop      = {
            id        = shop.id,
            type      = shop.type,
            label     = shop.label,
            blip_name = shop.blip_name,
            is_open   = shop.is_open == 1 or shop.is_open == true,
            owner     = shop.owner_name,
            safe      = (perms.safe and shop.safe_money) or nil,
        },
        listings  = GetListings(shop.id),
        storage   = GetStorage(shop.id),
        employees = (perms.staff and GetEmployees(shop.id)) or nil,
        imagePath = Config.InventoryImagePath,
    })
end)

-- ═══════════════════════════════════════
--  LISTINGS
-- ═══════════════════════════════════════

RegisterNetEvent('lt-shops:server:addListing', function(shopId, data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not Perm(role, 'listings') then return Notify(src, 'ليس لديك صلاحية', 'error') end

    local itemName = tostring(data.itemName or '')
    local quantity = math.floor(tonumber(data.quantity) or 0)
    local price    = math.floor(tonumber(data.price) or 0)
    if itemName == '' or quantity < 1 or price < 1 then
        return Notify(src, 'كمية أو سعر غير صالح', 'error')
    end

    local count = MySQL.scalar.await('SELECT COUNT(*) FROM lt_shop_items WHERE shop_id = ?', { shop.id })
    if count and count >= Config.MaxListingsPerShop then
        return Notify(src, 'وصلت للحد الأقصى من المنتجات (' .. Config.MaxListingsPerShop .. ')', 'error')
    end

    local playerItem = Player.Functions.GetItemByName(itemName)
    if not playerItem or playerItem.amount < quantity then
        return Notify(src, 'لا تملك هذه الكمية', 'error')
    end

    if not Player.Functions.RemoveItem(itemName, quantity, data.slot) then
        return Notify(src, 'فشل سحب العنصر', 'error')
    end
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'remove', quantity)

    local shared = QBCore.Shared.Items[itemName]
    local label  = shared and shared.label or itemName

    -- merge into existing listing with same item + price
    local existing = MySQL.query.await('SELECT id FROM lt_shop_items WHERE shop_id = ? AND item_name = ? AND price = ?', { shop.id, itemName, price })
    if existing and existing[1] then
        MySQL.update.await('UPDATE lt_shop_items SET quantity = quantity + ? WHERE id = ?', { quantity, existing[1].id })
    else
        MySQL.insert.await(
            'INSERT INTO lt_shop_items (shop_id, item_name, item_label, item_image, quantity, price, added_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { shop.id, itemName, label, data.image or (itemName .. '.png'), quantity, price, CharName(Player) }
        )
    end

    Notify(src, 'تم إضافة ' .. quantity .. 'x ' .. label .. ' بسعر $' .. price, 'success')
end)

RegisterNetEvent('lt-shops:server:removeListing', function(shopId, listingId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not Perm(role, 'listings') then return Notify(src, 'ليس لديك صلاحية', 'error') end

    local rows = MySQL.query.await('SELECT * FROM lt_shop_items WHERE id = ? AND shop_id = ?', { listingId, shop.id })
    if not rows or not rows[1] then return Notify(src, 'المنتج غير موجود', 'error') end
    local listing = rows[1]

    if not Player.Functions.AddItem(listing.item_name, listing.quantity) then
        return Notify(src, 'حقيبتك ممتلئة', 'error')
    end
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[listing.item_name], 'add', listing.quantity)

    MySQL.update.await('DELETE FROM lt_shop_items WHERE id = ?', { listing.id })
    Notify(src, 'تمت إزالة المنتج وإرجاع العناصر', 'success')
end)

RegisterNetEvent('lt-shops:server:updateListing', function(shopId, listingId, newPrice)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not Perm(role, 'listings') then return end

    newPrice = math.floor(tonumber(newPrice) or 0)
    if newPrice < 1 then return Notify(src, 'سعر غير صالح', 'error') end

    MySQL.update.await('UPDATE lt_shop_items SET price = ? WHERE id = ? AND shop_id = ?', { newPrice, listingId, shop.id })
    Notify(src, 'تم تحديث السعر', 'success')
end)

-- ═══════════════════════════════════════
--  STORAGE (STASH)
-- ═══════════════════════════════════════

QBCore.Functions.CreateCallback('lt-shops:server:openStorage', function(source, cb, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(source, shop) then return cb(nil) end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    local perm = Perm(role, 'storage')
    if not perm then
        Notify(source, 'أنت لا تعمل في هذا المتجر', 'error')
        return cb(nil)
    end

    cb({
        role        = role,
        canWithdraw = perm == true,   -- 'deposit' means deposit-only
        storage     = GetStorage(shop.id),
        shopLabel   = shop.blip_name,
        shopId      = shop.id,
        imagePath   = Config.InventoryImagePath,
    })
end)

RegisterNetEvent('lt-shops:server:depositStorage', function(shopId, itemName, amount, slot)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not Perm(role, 'storage') then return Notify(src, 'ليس لديك صلاحية', 'error') end

    itemName = tostring(itemName or '')
    amount = math.floor(tonumber(amount) or 0)
    if itemName == '' or amount < 1 then return end

    local playerItem = Player.Functions.GetItemByName(itemName)
    if not playerItem or playerItem.amount < amount then
        return Notify(src, 'لا تملك هذه الكمية', 'error')
    end

    -- ✅ FIXED: Add slot parameter
    if not Player.Functions.RemoveItem(itemName, amount, slot) then 
        return Notify(src, 'فشل إزالة العنصر من حقيبتك', 'error')
    end
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'remove', amount)

    StorageAdd(shop.id, itemName, amount)
    Notify(src, 'تم إيداع ' .. amount .. 'x في مخزن المتجر', 'success')
end)

RegisterNetEvent('lt-shops:server:withdrawStorage', function(shopId, itemName, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if Perm(role, 'storage') ~= true then return Notify(src, 'الموظفين يمكنهم الإيداع فقط', 'error') end

    itemName = tostring(itemName or '')
    amount = math.floor(tonumber(amount) or 0)
    if itemName == '' or amount < 1 then return end

    if not StorageRemove(shop.id, itemName, amount) then
        return Notify(src, 'الكمية غير متوفرة في المخزن', 'error')
    end

    if not Player.Functions.AddItem(itemName, amount) then
        StorageAdd(shop.id, itemName, amount) -- rollback
        return Notify(src, 'حقيبتك ممتلئة', 'error')
    end
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'add', amount)
    Notify(src, 'تم سحب ' .. amount .. 'x من المخزن', 'success')
end)

-- ═══════════════════════════════════════
--  STAFF
-- ═══════════════════════════════════════

RegisterNetEvent('lt-shops:server:hireStaff', function(shopId, targetId, grade)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    local staffPerm = Perm(role, 'staff')
    if not staffPerm then return Notify(src, 'ليس لديك صلاحية', 'error') end

    grade = (grade == 'manager') and 'manager' or 'employee'
    if staffPerm == 'employee' and grade ~= 'employee' then
        return Notify(src, 'يمكنك توظيف موظفين فقط', 'error')
    end

    local Target = QBCore.Functions.GetPlayer(tonumber(targetId))
    if not Target then return Notify(src, 'اللاعب غير متصل', 'error') end

    local tcid = Target.PlayerData.citizenid
    if tcid == shop.owner_cid then return Notify(src, 'هذا هو مالك المتجر', 'error') end

    MySQL.query.await([[
        INSERT INTO lt_shop_employees (shop_id, citizenid, name, grade) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE grade = VALUES(grade), name = VALUES(name)
    ]], { shop.id, tcid, CharName(Target), grade })

    Notify(src, 'تم توظيف ' .. CharName(Target) .. ' كـ ' .. grade, 'success')
    Notify(Target.PlayerData.source, 'تم توظيفك في ' .. shop.blip_name .. ' (' .. grade .. ')', 'success')
end)

RegisterNetEvent('lt-shops:server:fireStaff', function(shopId, citizenid)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    local staffPerm = Perm(role, 'staff')
    if not staffPerm then return Notify(src, 'ليس لديك صلاحية', 'error') end

    local rows = MySQL.query.await('SELECT grade FROM lt_shop_employees WHERE shop_id = ? AND citizenid = ?', { shop.id, citizenid })
    if not rows or not rows[1] then return end
    if staffPerm == 'employee' and rows[1].grade ~= 'employee' then
        return Notify(src, 'لا يمكنك طرد مدير', 'error')
    end

    MySQL.update.await('DELETE FROM lt_shop_employees WHERE shop_id = ? AND citizenid = ?', { shop.id, citizenid })
    Notify(src, 'تم الطرد من العمل', 'success')
end)

RegisterNetEvent('lt-shops:server:setGrade', function(shopId, citizenid, grade)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if Perm(role, 'staff') ~= true then return Notify(src, 'المالك فقط يمكنه الترقية', 'error') end

    grade = (grade == 'manager') and 'manager' or 'employee'
    MySQL.update.await('UPDATE lt_shop_employees SET grade = ? WHERE shop_id = ? AND citizenid = ?', { grade, shop.id, citizenid })
    Notify(src, 'تم تغيير الرتبة إلى ' .. grade, 'success')
end)

-- ═══════════════════════════════════════
--  SETTINGS / SAFE / OPEN-CLOSE / LICENSE
-- ═══════════════════════════════════════

RegisterNetEvent('lt-shops:server:setBlipName', function(shopId, name)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not Perm(role, 'settings') then return Notify(src, 'المالك فقط', 'error') end

    name = tostring(name or ''):sub(1, 60)
    if name == '' then return end

    MySQL.update.await('UPDATE lt_shops SET blip_name = ? WHERE id = ?', { name, shop.id })
    shop.blip_name = name
    SyncAll()
    Notify(src, 'تم تغيير اسم المتجر على الخريطة', 'success')
end)

RegisterNetEvent('lt-shops:server:toggleOpen', function(shopId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not Perm(role, 'toggle') then return Notify(src, 'ليس لديك صلاحية', 'error') end
    if shop.type ~= 'weapon' then return Notify(src, 'متاجر البقالة مفتوحة دائماً', 'error') end

    local newState = (shop.is_open == 1 or shop.is_open == true) and 0 or 1
    MySQL.update.await('UPDATE lt_shops SET is_open = ? WHERE id = ?', { newState, shop.id })
    shop.is_open = newState
    SyncAll()
    
    -- ✅ NEW: Send global chat message
    if newState == 1 then
        TriggerClientEvent('chat:addMessage', -1, {
            args = {'🏪 ' .. shop.blip_name, '✅ المتجر الآن مفتوح للعملاء'},
            color = {0, 255, 0}
        })
        Notify(src, '✅ تم فتح المتجر - الجميع سيرى الإعلان', 'success')
    else
        TriggerClientEvent('chat:addMessage', -1, {
            args = {'🏪 ' .. shop.blip_name, '❌ المتجر الآن مغلق'},
            color = {255, 0, 0}
        })
        Notify(src, '❌ تم إغلاق المتجر', 'success')
    end
end)

RegisterNetEvent('lt-shops:server:withdrawSafe', function(shopId, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if Perm(role, 'safe') ~= true then return Notify(src, 'المالك فقط يمكنه السحب', 'error') end

    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > (shop.safe_money or 0) then
        return Notify(src, 'مبلغ غير صالح', 'error')
    end

    MySQL.update.await('UPDATE lt_shops SET safe_money = safe_money - ? WHERE id = ? AND safe_money >= ?', { amount, shop.id, amount })
    shop.safe_money = shop.safe_money - amount
    Player.Functions.AddMoney('cash', amount, 'shop-safe-withdraw')
    Notify(src, 'سحبت $' .. amount .. ' من الخزنة', 'success')
end)

RegisterNetEvent('lt-shops:server:issueLicense', function(shopId, targetId, signature)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop) then return end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not Perm(role, 'license') then return Notify(src, 'المالك فقط يمكنه توقيع الرخص', 'error') end
    if shop.type ~= 'weapon' then return end

    signature = tostring(signature or ''):sub(1, 50)
    if signature == '' then return Notify(src, 'يجب كتابة التوقيع', 'error') end

    local Target = QBCore.Functions.GetPlayer(tonumber(targetId))
    if not Target then return Notify(src, 'اللاعب غير متصل', 'error') end

    local info = {
        store     = shop.blip_name,
        owner     = CharName(Player),
        holder    = CharName(Target),
        signature = signature,
        signed    = true,
        date      = os.date('%d/%m/%Y'),
        description = 'رخصة سلاح موقعة | Store: ' .. shop.blip_name .. ' | Signed: ' .. signature .. ' | Holder: ' .. CharName(Target),
    }

    if not Target.Functions.AddItem(Config.License.item, 1, false, info) then
        return Notify(src, 'حقيبة اللاعب ممتلئة', 'error')
    end
    TriggerClientEvent('inventory:client:ItemBox', Target.PlayerData.source, QBCore.Shared.Items[Config.License.item], 'add', 1)

    Notify(src, 'تم توقيع وتسليم رخصة سلاح لـ ' .. CharName(Target), 'success')
    Notify(Target.PlayerData.source, 'استلمت رخصة سلاح موقعة من ' .. CharName(Player), 'success')
end)

local function HasSignedLicense(Player)
    local items = Player.PlayerData.items or {}
    for _, item in pairs(items) do
        if item and item.name == Config.License.item and item.info and item.info.signed then
            return true
        end
    end
    return false
end

-- ═══════════════════════════════════════
--  BUYER
-- ═══════════════════════════════════════

QBCore.Functions.CreateCallback('lt-shops:server:openBuyer', function(source, cb, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(source, shop) then return cb(nil) end

    if shop.type == 'weapon' then
        if not (shop.is_open == 1 or shop.is_open == true) then
            Notify(source, 'متجر الأسلحة مغلق حالياً', 'error')
            return cb(nil)
        end
    end

    cb({
        shop = {
            id        = shop.id,
            type      = shop.type,
            blip_name = shop.blip_name,
            owner     = shop.owner_name,
        },
        listings  = GetListings(shop.id),
        imagePath = Config.InventoryImagePath,
    })
end)

QBCore.Functions.CreateCallback('lt-shops:server:buyItem', function(source, cb, shopId, listingId, buyQty)
    local Buyer = QBCore.Functions.GetPlayer(source)
    local shop = GetShop(shopId)
    if not Buyer or not shop or not NearShop(source, shop) then return cb(false) end

    if shop.type == 'weapon' then
        if not (shop.is_open == 1 or shop.is_open == true) then return cb(false) end
        if not HasSignedLicense(Buyer) then
            Notify(source, 'تحتاج رخصة سلاح موقعة', 'error')
            return cb(false)
        end
    end

    buyQty = math.floor(tonumber(buyQty) or 1)
    if buyQty < 1 then return cb(false) end

    local rows = MySQL.query.await('SELECT * FROM lt_shop_items WHERE id = ? AND shop_id = ? AND quantity > 0', { listingId, shop.id })
    if not rows or not rows[1] then
        Notify(source, 'المنتج لم يعد متوفراً', 'error')
        return cb(false)
    end
    local listing = rows[1]

    if buyQty > listing.quantity then
        Notify(source, 'الكمية غير متوفرة', 'error')
        return cb(false)
    end

    local totalCost = listing.price * buyQty
    if (Buyer.PlayerData.money['cash'] or 0) < totalCost then
        Notify(source, 'لا تملك كاش كافي ($' .. totalCost .. ')', 'error')
        return cb(false)
    end

    if not Buyer.Functions.AddItem(listing.item_name, buyQty) then
        Notify(source, 'حقيبتك ممتلئة', 'error')
        return cb(false)
    end
    TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[listing.item_name], 'add', buyQty)

    Buyer.Functions.RemoveMoney('cash', totalCost, 'shop-purchase')

    local tax = math.floor(totalCost * (Config.SalesTax / 100))
    local payout = totalCost - tax

    -- revenue goes to the SHOP SAFE
    MySQL.update.await('UPDATE lt_shops SET safe_money = safe_money + ? WHERE id = ?', { payout, shop.id })
    shop.safe_money = (shop.safe_money or 0) + payout

    local newQty = listing.quantity - buyQty
    if newQty <= 0 then
        MySQL.update.await('DELETE FROM lt_shop_items WHERE id = ?', { listing.id })
    else
        MySQL.update.await('UPDATE lt_shop_items SET quantity = ? WHERE id = ?', { newQty, listing.id })
    end

    -- notify online owner
    if shop.owner_cid then
        local Owner = QBCore.Functions.GetPlayerByCitizenId(shop.owner_cid)
        if Owner then
            Notify(Owner.PlayerData.source, 'متجرك ' .. shop.blip_name .. ': بيع ' .. buyQty .. 'x ' .. listing.item_label .. ' بـ $' .. totalCost, 'success')
        end
    end

    cb(true)
end)

-- ═══════════════════════════════════════
--  CRAFTING (WEAPON SHOPS)
-- ═══════════════════════════════════════

QBCore.Functions.CreateCallback('lt-shops:server:openCrafting', function(source, cb, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    local shop = GetShop(shopId)
    if not Player or not shop or shop.type ~= 'weapon' or not NearShop(source, shop) then return cb(nil) end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not Perm(role, 'craft') then
        Notify(source, 'ليس لديك صلاحية استخدام طاولة التصنيع', 'error')
        return cb(nil)
    end

    local recipes = {}
    for i, r in ipairs(Config.Crafting) do
        local mats, can = {}, true
        for _, m in ipairs(r.materials) do
            local have = StorageAmount(shop.id, m.item)
            local shared = QBCore.Shared.Items[m.item]
            mats[#mats + 1] = { item = m.item, label = shared and shared.label or m.item, need = m.amount, have = have }
            if have < m.amount then can = false end
        end
        local shared = QBCore.Shared.Items[r.item]
        recipes[#recipes + 1] = {
            index = i, item = r.item,
            label = r.label or (shared and shared.label) or r.item,
            image = (shared and shared.image) or (r.item .. '.png'),
            time = r.time, materials = mats, canCraft = can,
        }
    end

    cb({ shopId = shop.id, recipes = recipes, imagePath = Config.InventoryImagePath })
end)

RegisterNetEvent('lt-shops:server:startCraft', function(shopId, recipeIndex)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    
    if not Player then return end
    if not shop or shop.type ~= 'weapon' then
        Notify(src, 'متجر غير صحيح', 'error')
        return
    end
    if not NearShop(src, shop) then
        Notify(src, 'أنت بعيد جداً عن طاولة التصنيع', 'error')
        return
    end
    if PendingCraft[src] then
        Notify(src, 'أنت بالفعل تقوم بتصنيع شيء ما', 'error')
        return
    end

    local role = GetRole(shop, Player.PlayerData.citizenid)
    if not Perm(role, 'craft') then
        Notify(src, 'ليس لديك صلاحية التصنيع', 'error')
        return
    end

    local recipe = Config.Crafting[tonumber(recipeIndex)]
    if not recipe then
        Notify(src, 'وصفة غير موجودة', 'error')
        return
    end

    local missingMats = {}
    for _, m in ipairs(recipe.materials) do
        local available = StorageAmount(shop.id, m.item)
        if available < m.amount then
            table.insert(missingMats, string.format('%s (%d/%d)', m.item, available, m.amount))
        end
    end
    
    if #missingMats > 0 then
        Notify(src, '❌ مواد غير كافية: ' .. table.concat(missingMats, ', '), 'error')
        return
    end

    for _, m in ipairs(recipe.materials) do
        StorageRemove(shop.id, m.item, m.amount)
    end

    PendingCraft[src] = { shopId = shop.id, recipeIndex = tonumber(recipeIndex), started = GetGameTimer() }
    Notify(src, '🔧 جاري التصنيع: ' .. recipe.label, 'info')
    TriggerClientEvent('lt-shops:client:doCraft', src, recipe.label, recipe.time)
end)

RegisterNetEvent('lt-shops:server:finishCraft', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local pending = PendingCraft[src]
    if not Player or not pending then return end
    PendingCraft[src] = nil

    local recipe = Config.Crafting[pending.recipeIndex]
    if not recipe then return end

    if GetGameTimer() - pending.started < (recipe.time - 1500) then
        return
    end

    if not Player.Functions.AddItem(recipe.item, 1) then
        StorageAdd(pending.shopId, recipe.item, 1)
        return Notify(src, 'حقيبتك ممتلئة - تم وضع القطعة في المخزن', 'primary')
    end
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[recipe.item], 'add', 1)
    Notify(src, '✅ تم تصنيع ' .. recipe.label, 'success')
end)

RegisterNetEvent('lt-shops:server:cancelCraft', function()
    local src = source
    local pending = PendingCraft[src]
    if not pending then return end
    PendingCraft[src] = nil

    local recipe = Config.Crafting[pending.recipeIndex]
    if not recipe then return end
    for _, m in ipairs(recipe.materials) do
        StorageAdd(pending.shopId, m.item, m.amount)
    end
end)

-- ═══════════════════════════════════════
--  SAFE ROBBERY (LOCKPICK)
-- ═══════════════════════════════════════

RegisterNetEvent('lt-shops:server:startRobSafe', function(shopId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local shop = GetShop(shopId)
    if not Player or not shop or not NearShop(src, shop, 8.0) then return end
    if PendingRob[src] then return end

    -- staff cannot rob their own shop
    if GetRole(shop, Player.PlayerData.citizenid) then
        return Notify(src, 'لا يمكنك سرقة خزنة متجرك', 'error')
    end

    -- cooldown
    local last = RobCooldown[shop.id]
    if last and (os.time() - last) < (Config.Safe.cooldownMinutes * 60) then
        return Notify(src, 'الخزنة تم العبث بها مؤخراً... حاول لاحقاً', 'error')
    end

    if (shop.safe_money or 0) < Config.Safe.minMoney then
        return Notify(src, 'الخزنة تبدو فارغة', 'error')
    end

    -- staff nearby = cannot rob ("only if it's not being watched")
    if StaffNearby(shop) then
        return Notify(src, 'موظفو المتجر في المكان! لا يمكنك السرقة الآن', 'error')
    end

    local lockpick = Player.Functions.GetItemByName(Config.Safe.lockpickItem)
    if not lockpick then
        return Notify(src, 'تحتاج أداة فتح أقفال', 'error')
    end

    RobCooldown[shop.id] = os.time()
    PendingRob[src] = { shopId = shop.id, started = GetGameTimer() }

    -- police alert
    if Config.Safe.policeAlert then
        local pt = shop.coords.stash or shop.coords.seller
        TriggerEvent('police:server:policeAlert', 'محاولة سرقة خزنة متجر - ' .. shop.blip_name)
        TriggerClientEvent('lt-shops:client:policeBlip', -1, pt, shop.blip_name)
    end

    TriggerClientEvent('lt-shops:client:doRobSafe', src, Config.Safe.robTime)
end)

RegisterNetEvent('lt-shops:server:finishRobSafe', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local pending = PendingRob[src]
    if not Player or not pending then return end
    PendingRob[src] = nil

    if GetGameTimer() - pending.started < (Config.Safe.robTime - 1500) then return end

    local shop = GetShop(pending.shopId)
    if not shop then return end

    local roll = math.random(1, 100)
    if roll <= Config.Safe.successChance then
        local stolen = math.floor((shop.safe_money or 0) * (Config.Safe.stealPercent / 100))
        if stolen > 0 then
            MySQL.update.await('UPDATE lt_shops SET safe_money = safe_money - ? WHERE id = ? AND safe_money >= ?', { stolen, shop.id, stolen })
            shop.safe_money = math.max(0, (shop.safe_money or 0) - stolen)
            Player.Functions.AddItem('markedbills', 1, false, { worth = stolen })
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['markedbills'], 'add', 1)
            Notify(src, 'فتحت الخزنة وسرقت $' .. stolen .. ' (أموال مؤشرة)', 'success')
        else
            Notify(src, 'الخزنة فارغة!', 'error')
        end
    else
        Notify(src, 'فشلت في فتح القفل', 'error')
        if Config.Safe.removeOnFail then
            Player.Functions.RemoveItem(Config.Safe.lockpickItem, 1)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.Safe.lockpickItem], 'remove', 1)
        end
    end
end)

RegisterNetEvent('lt-shops:server:cancelRobSafe', function()
    PendingRob[source] = nil
end)

-- ═══════════════════════════════════════
--  ADMIN
-- ═══════════════════════════════════════

QBCore.Functions.CreateCallback('lt-shops:server:getAdminData', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player or not IsShopAdmin(source) then return cb(nil) end

    local shops = {}
    for id, s in pairs(Shops) do
        shops[#shops + 1] = {
            id = id, type = s.type, label = s.label, blip_name = s.blip_name,
            owner_cid = s.owner_cid, owner_name = s.owner_name,
            is_open = s.is_open == 1 or s.is_open == true,
            safe_money = s.safe_money, coords = s.coords,
        }
    end
    table.sort(shops, function(a, b) return a.id < b.id end)

    local admins = MySQL.query.await('SELECT * FROM lt_shop_admins', {}) or {}
    local isSuper = IsSuperAdmin(source)

    cb({ shops = shops, admins = admins, isSuper = isSuper })
end)

RegisterCommand(Config.AdminCommand, function(source)
    if source == 0 then return end
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player or not IsShopAdmin(source) then
        return Notify(source, 'ليس لديك صلاحية', 'error')
    end
    TriggerClientEvent('lt-shops:client:openAdmin', source)
end, false)

RegisterNetEvent('lt-shops:server:adminCreateShop', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not IsShopAdmin(src) then return end

    local typ = (data.type == 'weapon') and 'weapon' or 'grocery'
    local label = tostring(data.label or 'Shop'):sub(1, 80)
    local coords = data.coords or {}

    -- must have seller, buyer, stash (crafting required for weapon)
    if not (coords.seller and coords.buyer and coords.stash) then
        return Notify(src, 'يجب تحديد جميع النقاط (بائع/مشتري/مخزن)', 'error')
    end
    if typ == 'weapon' and not coords.crafting then
        return Notify(src, 'متجر السلاح يحتاج نقطة تصنيع', 'error')
    end

    local clean = {}
    for k, v in pairs(coords) do
        if type(v) == 'table' and tonumber(v.x) then
            clean[k] = { x = tonumber(v.x) + 0.0, y = tonumber(v.y) + 0.0, z = tonumber(v.z) + 0.0, w = tonumber(v.w) or 0.0 }
        end
    end

    local id = MySQL.insert.await(
        'INSERT INTO lt_shops (type, label, blip_name, is_open, coords) VALUES (?, ?, ?, ?, ?)',
        { typ, label, label, typ == 'grocery' and 1 or 0, json.encode(clean) }
    )
    LoadShops()
    SyncAll()
    Notify(src, 'تم إنشاء متجر #' .. id .. ' (' .. typ .. ')', 'success')
end)

RegisterNetEvent('lt-shops:server:adminDeleteShop', function(shopId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not IsShopAdmin(src) then return end

    shopId = tonumber(shopId)
    if not Shops[shopId] then return end

    MySQL.update.await('DELETE FROM lt_shops WHERE id = ?', { shopId })
    MySQL.update.await('DELETE FROM lt_shop_employees WHERE shop_id = ?', { shopId })
    MySQL.update.await('DELETE FROM lt_shop_items WHERE shop_id = ?', { shopId })
    MySQL.update.await('DELETE FROM lt_shop_storage WHERE shop_id = ?', { shopId })
    LoadShops()
    SyncAll()
    Notify(src, 'تم حذف المتجر #' .. shopId, 'success')
end)

RegisterNetEvent('lt-shops:server:adminUpdateShopCoords', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not IsShopAdmin(src) then return end

    local shopId = tonumber(data.shopId)
    if not Shops[shopId] then return end

    local coords = data.coords or {}
    if not (coords.seller and coords.buyer and coords.stash) then
        return Notify(src, 'يجب تحديد جميع النقاط (بائع/مشتري/مخزن)', 'error')
    end

    local clean = {}
    for k, v in pairs(coords) do
        if type(v) == 'table' and tonumber(v.x) then
            clean[k] = { x = tonumber(v.x) + 0.0, y = tonumber(v.y) + 0.0, z = tonumber(v.z) + 0.0, w = tonumber(v.w) or 0.0 }
        end
    end

    MySQL.update.await('UPDATE lt_shops SET coords = ? WHERE id = ?', { json.encode(clean), shopId })
    LoadShops()
    SyncAll()
    Notify(src, 'تم تحديث إحداثيات المتجر #' .. shopId, 'success')
end)

RegisterNetEvent('lt-shops:server:adminSetOwner', function(shopId, targetId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not IsShopAdmin(src) then return end

    local shop = GetShop(shopId)
    if not shop then return end

    if not targetId or tonumber(targetId) == 0 then
        -- clear owner
        MySQL.update.await('UPDATE lt_shops SET owner_cid = NULL, owner_name = NULL WHERE id = ?', { shop.id })
        shop.owner_cid, shop.owner_name = nil, nil
        SyncAll()
        return Notify(src, 'تمت إزالة مالك المتجر #' .. shop.id, 'success')
    end

    local Target = QBCore.Functions.GetPlayer(tonumber(targetId))
    if not Target then return Notify(src, 'اللاعب غير متصل', 'error') end

    local name = CharName(Target)
    MySQL.update.await('UPDATE lt_shops SET owner_cid = ?, owner_name = ? WHERE id = ?', { Target.PlayerData.citizenid, name, shop.id })
    -- if they were an employee, remove that row
    MySQL.update.await('DELETE FROM lt_shop_employees WHERE shop_id = ? AND citizenid = ?', { shop.id, Target.PlayerData.citizenid })
    shop.owner_cid, shop.owner_name = Target.PlayerData.citizenid, name
    SyncAll()
    Notify(src, 'أصبح ' .. name .. ' مالك المتجر #' .. shop.id, 'success')
    Notify(Target.PlayerData.source, 'أصبحت مالك متجر: ' .. shop.blip_name, 'success')
end)

-- input: online server ID (small number), raw Discord ID (15+ digits),
-- or a full identifier string like discord:xxxx / license:xxxx
local function AddShopAdmin(src, input)
    if not IsSuperAdmin(src) then return Notify(src, 'المالك فقط يمكنه إضافة مشرفين', 'error') end

    input = tostring(input or ''):gsub('%s', '')
    if input == '' then return end

    local identifier, name

    if input:find('^discord:') or input:find('^license:') then
        identifier, name = input, input
    elseif input:match('^%d+$') and #input >= 15 then
        identifier, name = 'discord:' .. input, 'Discord: ' .. input
    else
        local Target = QBCore.Functions.GetPlayer(tonumber(input))
        if not Target then return Notify(src, 'اللاعب غير متصل - استخدم Discord ID أو license مباشرة', 'error') end
        local tsrc = Target.PlayerData.source
        identifier = GetIdent(tsrc, 'discord') or GetIdent(tsrc, 'license')
        if not identifier then return Notify(src, 'لا يوجد معرف لهذا اللاعب', 'error') end
        name = CharName(Target)
    end

    MySQL.query.await('INSERT INTO lt_shop_admins (identifier, name) VALUES (?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name)',
        { identifier, name })
    ShopAdmins[identifier] = true
    Notify(src, name .. ' أصبح مشرف متاجر', 'success')
end

RegisterNetEvent('lt-shops:server:adminIssueLicense', function(targetId, signature)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not IsShopAdmin(src) then return end

    signature = tostring(signature or ''):sub(1, 50)
    if signature == '' then return Notify(src, 'يجب كتابة التوقيع', 'error') end

    local Target = QBCore.Functions.GetPlayer(tonumber(targetId))
    if not Target then return Notify(src, 'اللاعب غير متصل', 'error') end

    local info = {
        store     = 'إدارة السيرفر',
        owner     = CharName(Player),
        holder    = CharName(Target),
        signature = signature,
        signed    = true,
        date      = os.date('%d/%m/%Y'),
        description = 'رخصة سلاح موقعة | إدارة السيرفر | Signed: ' .. signature .. ' | Holder: ' .. CharName(Target),
    }

    if not Target.Functions.AddItem(Config.License.item, 1, false, info) then
        return Notify(src, 'حقيبة اللاعب ممتلئة', 'error')
    end
    TriggerClientEvent('inventory:client:ItemBox', Target.PlayerData.source, QBCore.Shared.Items[Config.License.item], 'add', 1)

    Notify(src, 'تم توقيع وتسليم رخصة سلاح لـ ' .. CharName(Target), 'success')
    Notify(Target.PlayerData.source, 'استلمت رخصة سلاح موقعة من الإدارة', 'success')
end)

RegisterNetEvent('lt-shops:server:adminAddAdmin', function(input)
    AddShopAdmin(source, input)
end)

RegisterNetEvent('lt-shops:server:adminRemoveAdmin', function(identifier)
    local src = source
    if not IsSuperAdmin(src) then return Notify(src, 'المالك فقط يمكنه إزالة مشرفين', 'error') end
    MySQL.update.await('DELETE FROM lt_shop_admins WHERE identifier = ?', { identifier })
    ShopAdmins[identifier] = nil
    Notify(src, 'تمت إزالة المشرف', 'success')
end)

-- ═══════════════════════════════════════
--  DISCONNECT CLEANUP (refund pending craft materials)
-- ═══════════════════════════════════════

AddEventHandler('playerDropped', function()
    local src = source
    local pending = PendingCraft[src]
    if pending then
        PendingCraft[src] = nil
        local recipe = Config.Crafting[pending.recipeIndex]
        if recipe then
            for _, m in ipairs(recipe.materials) do
                StorageAdd(pending.shopId, m.item, m.amount)
            end
        end
    end
    PendingRob[src] = nil
end)

-- ═══════════════════════════════════════
--  USEABLE LICENSE (show info when used)
-- ═══════════════════════════════════════

CreateThread(function()
    QBCore.Functions.CreateUseableItem(Config.License.item, function(source, item)
        local info = item.info or {}
        if info.signed then
            Notify(source, 'رخصة سلاح | المتجر: ' .. (info.store or '?') .. ' | التوقيع: ' .. (info.signature or '?') .. ' | التاريخ: ' .. (info.date or '?'), 'primary')
        else
            Notify(source, 'ورقة A4 فارغة - غير موقعة', 'error')
        end
    end)
end)
