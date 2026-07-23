-- ============================================================
--  VGX Showroom v4 — Server
--  Multi-showroom. Showrooms, parking slots, entrance,
--  drop-off and test-drive points are all created IN-GAME
--  from the /showrooms admin panel and stored in the DB.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

-- ── STATE ───────────────────────────────────────────────────
local Showrooms      = {}  -- [id] = row (points decoded, slots attached)
local ShowroomAdmins = {}  -- [identifier] = true

-- ── Ensure database tables exist ────────────────────────────
CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `showrooms` (
            `id`         INT AUTO_INCREMENT PRIMARY KEY,
            `name`       VARCHAR(100) NOT NULL DEFAULT 'Showroom',
            `owner_cid`  VARCHAR(64) DEFAULT NULL,
            `owner_name` VARCHAR(128) DEFAULT NULL,
            `points`     LONGTEXT NOT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]], {})
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `showroom_slots` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `showroom_id` INT NOT NULL,
            `slot_no`     INT NOT NULL,
            `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL,
            `heading` DOUBLE NOT NULL DEFAULT 0,
            UNIQUE KEY `uq_showroom_slot` (`showroom_id`, `slot_no`)
        )
    ]], {})
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `showroom_admins` (
            `identifier` VARCHAR(120) PRIMARY KEY,
            `name`       VARCHAR(100) DEFAULT 'Unknown'
        )
    ]], {})
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `showroom_treasury_log` (
            `id`         INT AUTO_INCREMENT PRIMARY KEY,
            `treasury`   VARCHAR(64) NOT NULL,
            `type`       VARCHAR(16) NOT NULL,
            `amount`     INT NOT NULL,
            `cid`        VARCHAR(64) NOT NULL,
            `name`       VARCHAR(128) NOT NULL,
            `note`       VARCHAR(255) DEFAULT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]], {})
    LoadShowrooms()
    SyncAll()
    print('^2[vgx-showroom]^7 loaded ' .. tostring(TableCount(Showrooms)) .. ' showroom(s)')
end)

function TableCount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ── Load / sync ─────────────────────────────────────────────
function LoadShowrooms()
    Showrooms = {}
    local rows = MySQL.query.await('SELECT * FROM showrooms', {}) or {}
    for _, row in ipairs(rows) do
        row.points = json.decode(row.points) or {}
        row.slots  = {}
        Showrooms[row.id] = row
    end
    local slots = MySQL.query.await('SELECT * FROM showroom_slots ORDER BY showroom_id ASC, slot_no ASC', {}) or {}
    for _, s in ipairs(slots) do
        local sr = Showrooms[s.showroom_id]
        if sr then
            sr.slots[#sr.slots + 1] = { slot_no = s.slot_no, x = s.x, y = s.y, z = s.z, heading = s.heading }
        end
    end
    local admins = MySQL.query.await('SELECT * FROM showroom_admins', {}) or {}
    ShowroomAdmins = {}
    for _, a in ipairs(admins) do ShowroomAdmins[a.identifier] = true end
end

local function PublicData()
    local out = {}
    for id, sr in pairs(Showrooms) do
        out[#out + 1] = {
            id     = id,
            name   = sr.name,
            points = sr.points,
            slots  = sr.slots,
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function SyncAll()
    TriggerClientEvent('vgx-showroom:client:sync', -1, PublicData())
end

RegisterNetEvent('vgx-showroom:server:requestSync', function()
    TriggerClientEvent('vgx-showroom:client:sync', source, PublicData())
end)

-- ── Helpers ─────────────────────────────────────────────────
local function GP(src) return QBCore.Functions.GetPlayer(src) end

local function Notify(src, msg, ntype)
    TriggerClientEvent('vgx-showroom:notify', src, msg, ntype or 'primary')
end

local function GetShowroom(id)
    return Showrooms[tonumber(id)]
end

local function GetSlot(sr, slotNo)
    slotNo = tonumber(slotNo)
    for _, s in ipairs(sr.slots or {}) do
        if s.slot_no == slotNo then return s end
    end
    return nil
end

local function NearShowroom(src, sr, maxDist)
    if not sr then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local p = GetEntityCoords(ped)
    maxDist = maxDist or 60.0
    for _, pt in pairs(sr.points or {}) do
        if pt and pt.x and #(p - vector3(pt.x, pt.y, pt.z)) <= maxDist then return true end
    end
    for _, s in ipairs(sr.slots or {}) do
        if #(p - vector3(s.x, s.y, s.z)) <= maxDist then return true end
    end
    return false
end

local function PName(P)
    if not P then return 'Unknown' end
    return (P.PlayerData.charinfo.firstname or '') .. ' ' .. (P.PlayerData.charinfo.lastname or '')
end

local function Money(n) return '$' .. tostring(n or 0) end

-- ── Admin identity (identifier based, like lt-shops) ────────
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

local function IsShowroomAdmin(src)
    if IsSuperAdmin(src) then return true end
    local disc, lic = GetIdent(src, 'discord'), GetIdent(src, 'license')
    if disc and ShowroomAdmins[disc] then return true end
    if lic and ShowroomAdmins[lic] then return true end
    return false
end

-- ── Discord webhook (rich embed) ────────────────────────────
local WH_COLORS = {
    purchase = 3066993,  -- green
    listing  = 3447003,  -- blue
    removal  = 15158332, -- red
    price    = 15844367, -- gold
    staff    = 10181046, -- purple
    admin    = 15105570, -- orange
}

local function SendWebhook(kind, title, fields, description, footerName)
    local W = Config.Webhooks
    if not W or not W.enabled then return end
    local url = W[kind]
    if not url or url == '' or url:find('XXXX') then return end

    local embedFields = {}
    for _, f in ipairs(fields or {}) do
        embedFields[#embedFields + 1] = {
            name   = f[1],
            value  = tostring(f[2] == nil and '—' or f[2]),
            inline = f[3] ~= false,
        }
    end

    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username   = W.botName or 'Showroom',
        avatar_url = (W.avatar ~= '' and W.avatar) or nil,
        embeds = { {
            title       = title,
            description = description or nil,
            color       = WH_COLORS[kind] or 5814783,
            fields      = embedFields,
            footer      = { text = (footerName or 'Showrooms') .. ' • ' .. os.date('%Y-%m-%d %H:%M:%S') },
        } }
    }), { ['Content-Type'] = 'application/json' })
end

-- ══════════════════════════════════════════════════════════
--  RICE-BANKING INTEGRATION (unchanged from v3)
-- ══════════════════════════════════════════════════════════
local function RiceBank_GetPersonalAccount(cid)
    local acc = MySQL.query.await(
        "SELECT * FROM bank_accounts WHERE citizenid = ? AND account_type = 'personal' LIMIT 1", { cid })
    if acc and acc[1] then return acc[1] end

    local accNum = 'ACC' .. tostring(math.random(100000, 999999))
    MySQL.insert.await(
        "INSERT INTO bank_accounts (citizenid, account_number, account_type, balance) VALUES (?, ?, 'personal', 0)",
        { cid, accNum })
    return MySQL.query.await(
        "SELECT * FROM bank_accounts WHERE citizenid = ? AND account_type = 'personal' LIMIT 1", { cid })[1]
end

local function RiceBank_AdjustBalance(cid, amount, txType, description)
    local acc = RiceBank_GetPersonalAccount(cid)
    if not acc then return false end

    local newBal = (tonumber(acc.balance) or 0) + amount
    if newBal < 0 then return false, tonumber(acc.balance) end

    MySQL.update.await('UPDATE bank_accounts SET balance = ? WHERE id = ?', { newBal, acc.id })
    MySQL.insert(
        'INSERT INTO bank_transactions (account_id, type, amount, description, balance_after) VALUES (?,?,?,?,?)',
        { acc.id, txType, math.abs(amount), description or '', newBal })

    return true, newBal
end

-- ── Roles / permissions (per showroom) ──────────────────────
local function GetRole(sr, cid)
    if not sr or not cid then return nil end
    if sr.owner_cid and tostring(sr.owner_cid) == tostring(cid) then return 'owner' end
    local r = MySQL.query.await('SELECT role FROM showroom_staff WHERE showroom_id = ? AND citizenid = ?',
        { sr.id, cid })
    return (r and r[1]) and r[1].role or nil
end

local function HasPerm(sr, cid, perm)
    local role = GetRole(sr, cid)
    if not role then return false end
    return Config.Roles[role] and Config.Roles[role][perm] == true
end

-- ── Pay a player reliably (online OR offline) ───────────────
local function PayPlayer(cid, amount, account, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    account = (account == 'cash') and 'cash' or 'bank'

    local P = QBCore.Functions.GetPlayerByCitizenId(tostring(cid))
    if P then
        P.Functions.AddMoney(account, amount, reason or 'showroom')
        return true
    end

    local row = MySQL.query.await('SELECT money FROM players WHERE citizenid = ?', { tostring(cid) })
    if not row or not row[1] then
        print(('[vgx-showroom] ^1PAYOUT FAILED^7 — citizenid %s not found in players table (amount $%s)'):format(cid, amount))
        return false
    end

    local ok, money = pcall(json.decode, row[1].money or '{}')
    if not ok or type(money) ~= 'table' then money = {} end
    money[account] = math.floor((tonumber(money[account]) or 0) + amount)

    local affected = MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?',
        { json.encode(money), tostring(cid) })

    if not affected or affected < 1 then
        print(('[vgx-showroom] ^1PAYOUT FAILED^7 — update affected 0 rows for %s (amount $%s)'):format(cid, amount))
        return false
    end
    return true
end

-- ══════════════════════════════════════════════════════════
--  TREASURY — one society-backed balance PER showroom
-- ══════════════════════════════════════════════════════════
local function TreasuryName(showroomId)
    return 'showroom_' .. tostring(showroomId)
end

local function GetTreasuryBalance(showroomId)
    local name = TreasuryName(showroomId)
    local bal = MySQL.scalar.await('SELECT money FROM society WHERE name = ?', { name })
    if bal == nil then
        MySQL.insert.await('INSERT INTO society (name, money) VALUES (?, 0)', { name })
        return 0
    end
    return math.floor(tonumber(bal) or 0)
end

local function ChangeTreasury(showroomId, delta, txType, cid, name, note)
    local tname = TreasuryName(showroomId)
    GetTreasuryBalance(showroomId) -- ensure row exists

    if delta < 0 then
        local affected = MySQL.update.await(
            'UPDATE society SET money = money + ? WHERE name = ? AND money >= ?',
            { delta, tname, -delta })
        if not affected or affected < 1 then return false end
    else
        MySQL.update.await('UPDATE society SET money = money + ? WHERE name = ?', { delta, tname })
    end

    MySQL.insert('INSERT INTO showroom_treasury_log (treasury, type, amount, cid, name, note) VALUES (?,?,?,?,?,?)',
        { tname, txType, math.abs(delta), tostring(cid or 'system'), tostring(name or 'System'), note })

    TriggerEvent('qb-bossmenu:server:AddExternalTransaction', tname, {
        type     = (delta < 0) and 'withdraw' or 'deposit',
        amount   = math.abs(delta),
        employee = name or 'System',
        note     = note or txType,
    })
    return true
end

local function TreasuryLog(showroomId)
    return MySQL.query.await(
        'SELECT type, amount, name, note, created_at FROM showroom_treasury_log WHERE treasury = ? ORDER BY id DESC LIMIT 30',
        { TreasuryName(showroomId) }) or {}
end

-- ── Get all data for ONE showroom ───────────────────────────
QBCore.Functions.CreateCallback('vgx-showroom:getData', function(source, cb, showroomId)
    local P = GP(source)
    local sr = GetShowroom(showroomId)
    if not P or not sr then return cb(nil) end
    local cid  = P.PlayerData.citizenid
    local role = GetRole(sr, cid)

    cb({
        showroomId = sr.id,
        name       = sr.name,
        ownerName  = sr.owner_name,
        slots      = sr.slots,
        listings   = MySQL.query.await('SELECT * FROM showroom_listings WHERE showroom_id = ? ORDER BY slot_id ASC', { sr.id }),
        staff      = MySQL.query.await('SELECT * FROM showroom_staff WHERE showroom_id = ? ORDER BY hired_at ASC', { sr.id }),
        sales      = MySQL.query.await('SELECT * FROM showroom_sales WHERE showroom_id = ? ORDER BY sold_at DESC LIMIT 50', { sr.id }),
        role       = role,
        cid        = cid,
        treasury   = {
            enabled = Config.Payments.useTreasury == true,
            balance = GetTreasuryBalance(sr.id),
            log     = TreasuryLog(sr.id),
        },
    })
end)

-- ── The player's role in every showroom (for client prompts) ─
QBCore.Functions.CreateCallback('vgx-showroom:getMyRoles', function(source, cb)
    local P = GP(source)
    if not P then return cb({}) end
    local cid = P.PlayerData.citizenid
    local out = {}
    for id, sr in pairs(Showrooms) do
        local role = GetRole(sr, cid)
        if role then out[tostring(id)] = role end
    end
    cb(out)
end)

-- ── Treasury: deposit / withdraw (owner & manager only) ─────
QBCore.Functions.CreateCallback('vgx-showroom:treasuryAction', function(source, cb, showroomId, data)
    local P = GP(source)
    local sr = GetShowroom(showroomId)
    if not P or not sr then return cb({ success = false, message = 'Showroom not found' }) end
    if not Config.Payments.useTreasury then
        return cb({ success = false, message = 'Treasury is disabled' })
    end

    local cid  = P.PlayerData.citizenid
    local role = GetRole(sr, cid)
    if role ~= 'owner' and role ~= 'manager' then
        return cb({ success = false, message = 'Only the owner or a manager can do that' })
    end

    local action = tostring(data.action)
    local amount = math.floor(tonumber(data.amount) or 0)
    if amount <= 0 then return cb({ success = false, message = 'Enter a valid amount' }) end

    local pName = PName(P)

    if action == 'withdraw' then
        local ok = ChangeTreasury(sr.id, -amount, 'withdraw', cid, pName, 'Withdrawn to bank')
        if not ok then
            return cb({ success = false, message = 'Not enough money in the treasury' })
        end

        local rbOk, newBal = RiceBank_AdjustBalance(cid, amount, 'deposit', 'Showroom treasury withdrawal')
        if not rbOk then
            ChangeTreasury(sr.id, amount, 'deposit', cid, pName, 'Refunded — bank credit failed')
            return cb({ success = false, message = 'Could not credit your bank account. Refunded to treasury.' })
        end

        return cb({
            success = true,
            message = 'Withdrew $' .. amount .. ' — new bank balance: $' .. string.format('%.2f', newBal),
            balance = GetTreasuryBalance(sr.id),
            log     = TreasuryLog(sr.id),
        })

    elseif action == 'deposit' then
        local rbOk = RiceBank_AdjustBalance(cid, -amount, 'withdraw', 'Deposit into showroom treasury')
        if not rbOk then
            return cb({ success = false, message = 'Not enough money in your bank account' })
        end

        ChangeTreasury(sr.id, amount, 'deposit', cid, pName, 'Deposited from bank')
        return cb({
            success = true,
            message = 'Deposited $' .. amount .. ' into the treasury',
            balance = GetTreasuryBalance(sr.id),
            log     = TreasuryLog(sr.id),
        })
    end

    cb({ success = false, message = 'Unknown action' })
end)

-- ── Drive-in listing (store the vehicle you're sitting in) ──
RegisterNetEvent('vgx-showroom:storeVehicle', function(showroomId, price, props)
    local src = source
    local P = GP(src)
    local sr = GetShowroom(showroomId)
    if not P or not sr then return end
    if not NearShowroom(src, sr) then return end

    local cid = P.PlayerData.citizenid
    if not HasPerm(sr, cid, 'canAddVehicle') then
        Notify(src, 'You do not work at this showroom', 'error')
        return
    end

    if not sr.slots or #sr.slots == 0 then
        Notify(src, 'This showroom has no parking slots yet — ask an admin to add some', 'error')
        return
    end

    local plate = props and props.plate
    if not plate then return end

    local veh = MySQL.query.await(
        'SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', { plate, cid })
    if not veh or not veh[1] then
        Notify(src, 'This vehicle is not registered to you', 'error')
        return
    end

    local modelName = veh[1].vehicle
    local label = modelName
    if QBCore.Shared.Vehicles and QBCore.Shared.Vehicles[modelName] and QBCore.Shared.Vehicles[modelName].name then
        label = QBCore.Shared.Vehicles[modelName].name
    end

    price = math.max(0, math.floor(tonumber(price) or 0))

    local existingPlate = MySQL.query.await('SELECT id FROM showroom_listings WHERE plate = ?', { plate })
    if existingPlate and existingPlate[1] then
        Notify(src, 'This vehicle is already listed', 'error')
        return
    end

    -- pick the first FREE slot of THIS showroom
    local occupied = {}
    local rows = MySQL.query.await('SELECT slot_id FROM showroom_listings WHERE showroom_id = ?', { sr.id })
    for _, r in ipairs(rows or {}) do occupied[r.slot_id] = true end

    local freeSlot = nil
    for _, s in ipairs(sr.slots) do
        if not occupied[s.slot_no] then freeSlot = s.slot_no break end
    end

    if not freeSlot then
        Notify(src, 'The showroom is full — no free slots', 'error')
        return
    end

    MySQL.insert.await([[
        INSERT INTO showroom_listings
        (showroom_id, slot_id, owner_cid, model, label, price, plate, mods, added_by)
        VALUES (?,?,?,?,?,?,?,?,?)
    ]], { sr.id, freeSlot, cid, modelName, label, price, plate, json.encode(props), cid })

    MySQL.update.await('UPDATE player_vehicles SET state = 3, in_garage = 1, impound = 0 WHERE plate = ?', { plate })

    local slot = GetSlot(sr, freeSlot)
    TriggerClientEvent('vgx-showroom:spawnSlot', -1, {
        showroomId = sr.id,
        slotNo     = freeSlot,
        model      = modelName,
        plate      = plate,
        mods       = props,
        coords     = { x = slot.x, y = slot.y, z = slot.z },
        heading    = slot.heading,
    })

    SendWebhook('listing', '📥 Vehicle Listed (drive-in)', {
        { 'Showroom', sr.name .. ' (#' .. sr.id .. ')', false },
        { 'Vehicle', tostring(modelName), false },
        { 'Plate',   plate },
        { 'Slot',    '#' .. tostring(freeSlot) },
        { 'Price',   Money(price) },
        { 'Listed by', PName(P) .. '\n`' .. cid .. '`' },
    }, nil, sr.name)

    Notify(src, ('%s parked in slot #%s — open the showroom to set its price'):format(label, freeSlot), 'success')
    TriggerClientEvent('vgx-showroom:vehicleStored', src, sr.id)
end)

-- ── All listings of all showrooms (for spawn on join) ───────
QBCore.Functions.CreateCallback('vgx-showroom:getListings', function(source, cb)
    cb(MySQL.query.await('SELECT * FROM showroom_listings', {}) or {})
end)

-- ── Get player's own vehicles ───────────────────────────────
QBCore.Functions.CreateCallback('vgx-showroom:getMyVehicles', function(source, cb)
    local P = GP(source)
    if not P then return cb({}) end
    local cid = P.PlayerData.citizenid

    local listed = MySQL.query.await('SELECT plate FROM showroom_listings WHERE owner_cid = ?', { cid })
    local listedPlates = {}
    for _, l in ipairs(listed or {}) do listedPlates[l.plate] = true end

    local vehs = MySQL.query.await('SELECT vehicle, plate, mods FROM player_vehicles WHERE citizenid = ? AND state = 0',
        { cid })
    local result = {}
    for _, v in ipairs(vehs or {}) do
        if not listedPlates[v.plate] then
            result[#result + 1] = {
                model = v.vehicle,
                plate = v.plate,
                mods  = v.mods and json.decode(v.mods) or {},
                label = v.vehicle,
            }
        end
    end
    cb(result)
end)

-- ── Add vehicle (from the UI garage picker) ─────────────────
QBCore.Functions.CreateCallback('vgx-showroom:addVehicle', function(source, cb, data)
    local P = GP(source)
    local sr = GetShowroom(data.showroomId)
    if not P or not sr then return cb({ success = false, message = 'Showroom not found' }) end
    local cid = P.PlayerData.citizenid

    if not HasPerm(sr, cid, 'canAddVehicle') then
        return cb({ success = false, message = 'No permission' })
    end

    local slotId = tonumber(data.slotId)
    if not GetSlot(sr, slotId) then
        return cb({ success = false, message = 'That slot does not exist' })
    end

    local taken = MySQL.query.await('SELECT id FROM showroom_listings WHERE showroom_id = ? AND slot_id = ?',
        { sr.id, slotId })
    if taken and #taken > 0 then
        return cb({ success = false, message = 'Slot already occupied' })
    end

    local vehRow = MySQL.query.await('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?',
        { data.plate, cid })
    if not vehRow or not vehRow[1] then
        return cb({ success = false, message = 'Vehicle not found in your garage' })
    end

    local mods = vehRow[1].mods or '{}'
    MySQL.insert.await(
        'INSERT INTO showroom_listings (showroom_id, slot_id, owner_cid, model, label, price, plate, mods, added_by) VALUES (?,?,?,?,?,?,?,?,?)',
        { sr.id, slotId, cid, data.model, data.label, tonumber(data.price) or 0, data.plate, mods, cid })

    MySQL.update('UPDATE player_vehicles SET state = 3 WHERE plate = ?', { data.plate })

    SendWebhook('listing', '📥 Vehicle Listed', {
        { 'Showroom', sr.name .. ' (#' .. sr.id .. ')', false },
        { 'Vehicle', tostring(data.label) .. ' (' .. tostring(data.model) .. ')', false },
        { 'Plate',   tostring(data.plate) },
        { 'Slot',    '#' .. tostring(slotId) },
        { 'Price',   Money(tonumber(data.price) or 0) },
        { 'Listed by', PName(P) .. '\n`' .. cid .. '`' },
    }, nil, sr.name)

    local slot = GetSlot(sr, slotId)
    TriggerClientEvent('vgx-showroom:spawnSlot', -1, {
        showroomId = sr.id,
        slotNo     = slotId,
        model      = data.model,
        plate      = data.plate,
        mods       = json.decode(mods),
        coords     = { x = slot.x, y = slot.y, z = slot.z },
        heading    = slot.heading,
    })

    cb({
        success = true,
        message = data.label .. ' listed in slot ' .. slotId,
        listings = MySQL.query.await('SELECT * FROM showroom_listings WHERE showroom_id = ? ORDER BY slot_id ASC', { sr.id })
    })
end)

-- ── Remove vehicle ──────────────────────────────────────────
QBCore.Functions.CreateCallback('vgx-showroom:removeVehicle', function(source, cb, listingId)
    local P = GP(source)
    if not P then return cb({ success = false, message = 'Player not found' }) end

    local row = MySQL.query.await('SELECT * FROM showroom_listings WHERE id = ?', { listingId })
    if not row or not row[1] then return cb({ success = false, message = 'Listing not found' }) end
    local listing = row[1]

    local sr = GetShowroom(listing.showroom_id)
    if not sr then return cb({ success = false, message = 'Showroom not found' }) end
    if not HasPerm(sr, P.PlayerData.citizenid, 'canRemoveVehicle') then
        return cb({ success = false, message = 'No permission' })
    end

    MySQL.query.await('DELETE FROM showroom_listings WHERE id = ?', { listingId })
    MySQL.update('UPDATE player_vehicles SET state = 1 WHERE plate = ?', { listing.plate })
    TriggerClientEvent('vgx-showroom:despawnSlot', -1, sr.id, listing.slot_id)

    SendWebhook('removal', '🗑️ Vehicle Removed', {
        { 'Showroom', sr.name .. ' (#' .. sr.id .. ')', false },
        { 'Vehicle', tostring(listing.label), false },
        { 'Plate',   tostring(listing.plate) },
        { 'Slot',    '#' .. tostring(listing.slot_id) },
        { 'Removed by', PName(P) .. '\n`' .. P.PlayerData.citizenid .. '`' },
    }, nil, sr.name)

    cb({
        success = true,
        message = 'Vehicle removed',
        listings = MySQL.query.await('SELECT * FROM showroom_listings WHERE showroom_id = ? ORDER BY slot_id ASC', { sr.id })
    })
end)

-- ── Set price ───────────────────────────────────────────────
QBCore.Functions.CreateCallback('vgx-showroom:setPrice', function(source, cb, listingId, price)
    local P = GP(source)
    if not P then return cb({ success = false, message = 'Player not found' }) end

    local before = MySQL.query.await('SELECT * FROM showroom_listings WHERE id = ?', { listingId })
    if not before or not before[1] then return cb({ success = false, message = 'Listing not found' }) end
    local l = before[1]

    local sr = GetShowroom(l.showroom_id)
    if not sr then return cb({ success = false, message = 'Showroom not found' }) end
    if not HasPerm(sr, P.PlayerData.citizenid, 'canSetPrice') then
        return cb({ success = false, message = 'No permission' })
    end

    price = math.max(0, math.floor(tonumber(price) or 0))
    MySQL.update('UPDATE showroom_listings SET price = ? WHERE id = ?', { price, listingId })

    SendWebhook('price', '🏷️ Price Changed', {
        { 'Showroom', sr.name .. ' (#' .. sr.id .. ')', false },
        { 'Vehicle', tostring(l.label), false },
        { 'Plate',   tostring(l.plate) },
        { 'Slot',    '#' .. tostring(l.slot_id) },
        { 'Old Price', Money(l.price) },
        { 'New Price', Money(price) },
        { 'Changed by', PName(P) .. '\n`' .. P.PlayerData.citizenid .. '`' },
    }, nil, sr.name)

    cb({
        success = true,
        message = 'Price updated',
        listings = MySQL.query.await('SELECT * FROM showroom_listings WHERE showroom_id = ? ORDER BY slot_id ASC', { sr.id })
    })
end)

-- ── Change a listing's slot ─────────────────────────────────
QBCore.Functions.CreateCallback('vgx-showroom:changeSlot', function(source, cb, listingId, newSlot)
    local P = GP(source)
    if not P then return cb({ success = false, message = 'Player not found' }) end

    listingId = tonumber(listingId)
    newSlot   = tonumber(newSlot)
    if not listingId or not newSlot then
        return cb({ success = false, message = 'Invalid request' })
    end

    local row = MySQL.query.await('SELECT * FROM showroom_listings WHERE id = ?', { listingId })
    if not row or not row[1] then return cb({ success = false, message = 'Listing not found' }) end
    local l = row[1]

    local sr = GetShowroom(l.showroom_id)
    if not sr then return cb({ success = false, message = 'Showroom not found' }) end
    if not HasPerm(sr, P.PlayerData.citizenid, 'canSetPrice') then
        return cb({ success = false, message = 'No permission' })
    end

    local slot = GetSlot(sr, newSlot)
    if not slot then return cb({ success = false, message = 'That slot does not exist' }) end

    if l.slot_id == newSlot then
        return cb({ success = false, message = 'Vehicle is already in that slot' })
    end

    local taken = MySQL.query.await('SELECT id FROM showroom_listings WHERE showroom_id = ? AND slot_id = ?',
        { sr.id, newSlot })
    if taken and taken[1] then
        return cb({ success = false, message = 'Slot #' .. newSlot .. ' is already occupied' })
    end

    local oldSlot = l.slot_id
    MySQL.update.await('UPDATE showroom_listings SET slot_id = ? WHERE id = ?', { newSlot, listingId })

    TriggerClientEvent('vgx-showroom:despawnSlot', -1, sr.id, oldSlot)
    TriggerClientEvent('vgx-showroom:spawnSlot', -1, {
        showroomId = sr.id,
        slotNo     = newSlot,
        model      = l.model,
        plate      = l.plate,
        mods       = l.mods and json.decode(l.mods) or {},
        coords     = { x = slot.x, y = slot.y, z = slot.z },
        heading    = slot.heading,
    })

    SendWebhook('price', '↔️ Vehicle Moved', {
        { 'Showroom', sr.name .. ' (#' .. sr.id .. ')', false },
        { 'Vehicle',  tostring(l.label), false },
        { 'Plate',    tostring(l.plate) },
        { 'From Slot','#' .. tostring(oldSlot) },
        { 'To Slot',  '#' .. tostring(newSlot) },
        { 'Moved by', PName(P) .. '\n`' .. P.PlayerData.citizenid .. '`' },
    }, nil, sr.name)

    cb({
        success = true,
        message = l.label .. ' moved to slot #' .. newSlot,
        newSlot = newSlot,
        listings = MySQL.query.await('SELECT * FROM showroom_listings WHERE showroom_id = ? ORDER BY slot_id ASC', { sr.id })
    })
end)

-- ── Buy vehicle ─────────────────────────────────────────────
QBCore.Functions.CreateCallback('vgx-showroom:buyVehicle', function(source, cb, listingId)
    local P = GP(source)
    if not P then return cb({ success = false, message = 'Player not found' }) end

    local row = MySQL.query.await('SELECT * FROM showroom_listings WHERE id = ?', { listingId })
    if not row or not row[1] then return cb({ success = false, message = 'Vehicle no longer available' }) end
    local l = row[1]

    local sr = GetShowroom(l.showroom_id)
    if not sr then return cb({ success = false, message = 'Showroom not found' }) end

    local price = math.floor(tonumber(l.price) or 0)
    local tax   = math.floor(price * Config.TaxRate)
    local total = price + tax

    if price <= 0 then return cb({ success = false, message = 'No price set yet' }) end

    local buyerCid  = P.PlayerData.citizenid
    local buyerName = PName(P)

    if tostring(buyerCid) == tostring(l.owner_cid) then
        return cb({ success = false, message = 'You cannot buy your own vehicle' })
    end

    if P.PlayerData.money['bank'] < total then
        return cb({
            success = false,
            message = 'Not enough bank balance. Need $' .. total .. ' (incl. $' .. tax .. ' tax)'
        })
    end

    local paid = P.Functions.RemoveMoney('bank', total, 'showroom-purchase')
    if paid == false then
        return cb({ success = false, message = 'Payment failed' })
    end

    local ownerCid      = sr.owner_cid and tostring(sr.owner_cid) or nil
    local sellerCid     = tostring(l.owner_cid)
    local sellerIsOwner = ownerCid ~= nil and sellerCid == ownerCid

    local commission   = sellerIsOwner and 0 or math.floor(price * (Config.Payments.ownerCommission or 0))
    local sellerAmount = price - commission
    local ownerAmount  = commission + (Config.Payments.taxToOwner and tax or 0)
    if sellerIsOwner then
        sellerAmount = price + (Config.Payments.taxToOwner and tax or 0)
        ownerAmount  = 0
    end

    local sellerPaid = PayPlayer(sellerCid, sellerAmount, Config.Payments.sellerAccount, 'showroom-sale')
    if not sellerPaid then
        P.Functions.AddMoney('bank', total, 'showroom-refund')
        return cb({ success = false, message = 'Sale failed — seller account not found. You were refunded.' })
    end

    if ownerAmount > 0 then
        if Config.Payments.useTreasury then
            ChangeTreasury(sr.id, ownerAmount, 'sale', sellerCid, buyerName,
                ('Sale tax/commission from %s'):format(l.label))
        elseif ownerCid then
            PayPlayer(ownerCid, ownerAmount, Config.Payments.ownerAccount, 'showroom-tax')
        end
    end

    MySQL.update.await(
        'UPDATE player_vehicles SET citizenid = ?, license = ?, state = 1, garage = ? WHERE plate = ?',
        { buyerCid, P.PlayerData.license, Config.Payments.buyerGarage, l.plate })

    MySQL.insert(
        'INSERT INTO showroom_sales (showroom_id, buyer_cid, buyer_name, seller_cid, model, label, price, tax, plate) VALUES (?,?,?,?,?,?,?,?,?)',
        { sr.id, buyerCid, buyerName, sellerCid, l.model, l.label, price, tax, l.plate })

    MySQL.query.await('DELETE FROM showroom_listings WHERE id = ?', { listingId })
    TriggerClientEvent('vgx-showroom:despawnSlot', -1, sr.id, l.slot_id)

    local sellerP = QBCore.Functions.GetPlayerByCitizenId(sellerCid)
    if sellerP then
        Notify(sellerP.PlayerData.source,
            buyerName .. ' bought your ' .. l.label .. ' for $' .. sellerAmount, 'success')
    end
    if ownerCid and not sellerIsOwner and ownerAmount > 0 then
        local ownerP = QBCore.Functions.GetPlayerByCitizenId(ownerCid)
        if ownerP then
            Notify(ownerP.PlayerData.source,
                ('Showroom sale: %s bought %s — you received $%s (tax/commission)'):format(buyerName, l.label, ownerAmount),
                'success')
        end
    end

    print(('[vgx-showroom] SALE @%s: %s bought %s ($%s) | seller %s +$%s | owner %s +$%s')
        :format(sr.name, buyerName, l.label, total, sellerCid, sellerAmount, ownerCid or '—', ownerAmount))

    local sellerName = sellerCid
    if sellerP then
        sellerName = PName(sellerP)
    else
        local sRow = MySQL.query.await('SELECT charinfo FROM players WHERE citizenid = ?', { sellerCid })
        if sRow and sRow[1] and sRow[1].charinfo then
            local ci = json.decode(sRow[1].charinfo)
            if ci then sellerName = (ci.firstname or '') .. ' ' .. (ci.lastname or '') end
        end
    end

    SendWebhook('purchase', '🚗 Vehicle Sold', {
        { 'Showroom',      sr.name .. ' (#' .. sr.id .. ')', false },
        { 'Vehicle',       l.label .. ' (' .. l.model .. ')', false },
        { 'Plate',         l.plate },
        { 'Slot',          '#' .. l.slot_id },
        { 'Buyer',         buyerName .. '\n`' .. buyerCid .. '`' },
        { 'Seller',        sellerName .. '\n`' .. sellerCid .. '`' },
        { 'Showroom Owner','`' .. (ownerCid or '—') .. '`' },
        { 'Price',         Money(price) },
        { 'Tax (' .. math.floor(Config.TaxRate * 100) .. '%)', Money(tax) },
        { 'Total Paid',    Money(total) },
        { 'Seller Received', Money(sellerAmount) },
        { 'Owner Received',  Money(ownerAmount) .. (sellerIsOwner and ' (sold own car)' or ' (tax/commission)') },
    }, nil, sr.name)

    cb({
        success = true,
        message = l.label .. ' purchased! Check your garage.',
        listings = MySQL.query.await('SELECT * FROM showroom_listings WHERE showroom_id = ? ORDER BY slot_id ASC', { sr.id })
    })
end)

-- ── Hire staff ──────────────────────────────────────────────
QBCore.Functions.CreateCallback('vgx-showroom:hireStaff', function(source, cb, data)
    local P = GP(source)
    local sr = GetShowroom(data.showroomId)
    if not P or not sr then return cb({ success = false, message = 'Showroom not found' }) end
    if not HasPerm(sr, P.PlayerData.citizenid, 'canManageStaff') then
        return cb({ success = false, message = 'Only the owner can manage staff' })
    end

    local role = tostring(data.role)
    if not Config.Roles[role] or role == 'owner' then
        return cb({ success = false, message = 'Invalid role' })
    end

    local targetCid  = tostring(data.citizenid)
    local targetName = tostring(data.name)

    if sr.owner_cid and targetCid == tostring(sr.owner_cid) then
        return cb({ success = false, message = 'Cannot hire the owner as staff' })
    end

    local existing = MySQL.query.await('SELECT id FROM showroom_staff WHERE showroom_id = ? AND citizenid = ?',
        { sr.id, targetCid })
    if existing and #existing > 0 then
        MySQL.update('UPDATE showroom_staff SET role = ?, name = ? WHERE showroom_id = ? AND citizenid = ?',
            { role, targetName, sr.id, targetCid })
    else
        MySQL.insert('INSERT INTO showroom_staff (showroom_id, citizenid, name, role, hired_by) VALUES (?,?,?,?,?)',
            { sr.id, targetCid, targetName, role, P.PlayerData.citizenid })
    end

    local targetP = QBCore.Functions.GetPlayerByCitizenId(targetCid)
    if targetP then
        Notify(targetP.PlayerData.source,
            'You have been hired as ' .. Config.Roles[role].label .. ' at ' .. sr.name, 'success')
    end

    SendWebhook('staff', '🧑‍💼 Staff Hired', {
        { 'Showroom', sr.name .. ' (#' .. sr.id .. ')', false },
        { 'Employee', targetName .. '\n`' .. targetCid .. '`' },
        { 'Role',     Config.Roles[role].label },
        { 'Hired by', PName(P) .. '\n`' .. P.PlayerData.citizenid .. '`' },
    }, nil, sr.name)

    cb({
        success = true,
        message = targetName .. ' hired as ' .. Config.Roles[role].label,
        staff = MySQL.query.await('SELECT * FROM showroom_staff WHERE showroom_id = ? ORDER BY hired_at ASC', { sr.id })
    })
end)

-- ── Fire staff ──────────────────────────────────────────────
QBCore.Functions.CreateCallback('vgx-showroom:fireStaff', function(source, cb, staffId)
    local P = GP(source)
    if not P then return cb({ success = false, message = 'Player not found' }) end

    local row = MySQL.query.await('SELECT * FROM showroom_staff WHERE id = ?', { staffId })
    if not row or not row[1] then return cb({ success = false, message = 'Staff not found' }) end

    local sr = GetShowroom(row[1].showroom_id)
    if not sr then return cb({ success = false, message = 'Showroom not found' }) end
    if not HasPerm(sr, P.PlayerData.citizenid, 'canManageStaff') then
        return cb({ success = false, message = 'Only the owner can manage staff' })
    end

    MySQL.query.await('DELETE FROM showroom_staff WHERE id = ?', { staffId })

    local firedP = QBCore.Functions.GetPlayerByCitizenId(row[1].citizenid)
    if firedP then
        Notify(firedP.PlayerData.source, 'You have been removed from ' .. sr.name, 'error')
    end

    SendWebhook('staff', '🚫 Staff Fired', {
        { 'Showroom', sr.name .. ' (#' .. sr.id .. ')', false },
        { 'Employee', tostring(row[1].name) .. '\n`' .. tostring(row[1].citizenid) .. '`' },
        { 'Was',      tostring(row[1].role) },
        { 'Fired by', PName(P) .. '\n`' .. P.PlayerData.citizenid .. '`' },
    }, nil, sr.name)

    cb({
        success = true,
        message = row[1].name .. ' has been fired',
        staff = MySQL.query.await('SELECT * FROM showroom_staff WHERE showroom_id = ? ORDER BY hired_at ASC', { sr.id })
    })
end)

-- ── Online players (for the hire picker) ────────────────────
QBCore.Functions.CreateCallback('vgx-showroom:getOnlinePlayers', function(source, cb, showroomId)
    local P = GP(source)
    local sr = GetShowroom(showroomId)
    if not P or not sr then return cb({}) end
    if not HasPerm(sr, P.PlayerData.citizenid, 'canManageStaff') then return cb({}) end

    local list = {}
    for _, p in pairs(QBCore.Functions.GetQBPlayers()) do
        local pd = p.PlayerData
        if not sr.owner_cid or tostring(pd.citizenid) ~= tostring(sr.owner_cid) then
            list[#list + 1] = {
                citizenid = pd.citizenid,
                name      = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
            }
        end
    end
    cb(list)
end)

-- ══════════════════════════════════════════════════════════
--  ADMIN — /showrooms panel: create everything IN-GAME
-- ══════════════════════════════════════════════════════════

QBCore.Functions.CreateCallback('vgx-showroom:getAdminData', function(source, cb)
    local P = GP(source)
    if not P or not IsShowroomAdmin(source) then return cb(nil) end

    local out = {}
    for id, sr in pairs(Showrooms) do
        local listingCount = MySQL.scalar.await('SELECT COUNT(*) FROM showroom_listings WHERE showroom_id = ?', { id }) or 0
        out[#out + 1] = {
            id         = id,
            name       = sr.name,
            owner_cid  = sr.owner_cid,
            owner_name = sr.owner_name,
            points     = sr.points,
            slots      = sr.slots,
            listings   = listingCount,
            treasury   = GetTreasuryBalance(id),
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)

    local admins = MySQL.query.await('SELECT * FROM showroom_admins', {}) or {}

    cb({ showrooms = out, admins = admins, isSuper = IsSuperAdmin(source) })
end)

RegisterCommand(Config.AdminCommand, function(source)
    if source == 0 then return end
    if not IsShowroomAdmin(source) then
        return Notify(source, 'You do not have permission', 'error')
    end
    TriggerClientEvent('vgx-showroom:client:openAdmin', source)
end, false)

local function CleanPoint(v, withHeading)
    if type(v) ~= 'table' or not tonumber(v.x) then return nil end
    local pt = { x = tonumber(v.x) + 0.0, y = tonumber(v.y) + 0.0, z = tonumber(v.z) + 0.0 }
    if withHeading then pt.w = tonumber(v.w) or 0.0 end
    return pt
end

-- Create a showroom: name + entrance/dropoff points + parking slots
RegisterNetEvent('vgx-showroom:server:adminCreate', function(data)
    local src = source
    local P = GP(src)
    if not P or not IsShowroomAdmin(src) then return end

    local name = tostring(data.name or 'Showroom'):sub(1, 80)
    if name == '' then name = 'Showroom' end

    local points = {
        entrance = CleanPoint((data.points or {}).entrance),
        dropoff  = CleanPoint((data.points or {}).dropoff),
        tdspawn  = CleanPoint((data.points or {}).tdspawn, true),
        tdreturn = CleanPoint((data.points or {}).tdreturn),
    }
    if not points.entrance or not points.dropoff then
        return Notify(src, 'You must capture the entrance and drop-off points', 'error')
    end

    local slots = {}
    for _, s in ipairs(data.slots or {}) do
        local pt = CleanPoint(s, true)
        if pt then slots[#slots + 1] = pt end
    end
    if #slots == 0 then
        return Notify(src, 'Capture at least one vehicle parking slot', 'error')
    end

    local id = MySQL.insert.await('INSERT INTO showrooms (name, points) VALUES (?, ?)',
        { name, json.encode(points) })

    for i, s in ipairs(slots) do
        MySQL.insert.await('INSERT INTO showroom_slots (showroom_id, slot_no, x, y, z, heading) VALUES (?,?,?,?,?,?)',
            { id, i, s.x, s.y, s.z, s.w or 0.0 })
    end

    GetTreasuryBalance(id) -- create the society treasury row

    LoadShowrooms()
    SyncAll()
    SendWebhook('admin', '🏗️ Showroom Created', {
        { 'Showroom', name .. ' (#' .. id .. ')', false },
        { 'Slots',    tostring(#slots) },
        { 'Created by', PName(P) .. '\n`' .. P.PlayerData.citizenid .. '`' },
    }, nil, name)
    Notify(src, ('Showroom "%s" created (#%s) with %s parking slots'):format(name, id, #slots), 'success')
end)

-- Delete a showroom (returns all listed vehicles to their owners)
RegisterNetEvent('vgx-showroom:server:adminDelete', function(showroomId)
    local src = source
    local P = GP(src)
    if not P or not IsShowroomAdmin(src) then return end

    local sr = GetShowroom(showroomId)
    if not sr then return end

    -- give listed cars back to their owners' garages
    local listings = MySQL.query.await('SELECT plate, slot_id FROM showroom_listings WHERE showroom_id = ?', { sr.id }) or {}
    for _, l in ipairs(listings) do
        MySQL.update.await('UPDATE player_vehicles SET state = 1 WHERE plate = ?', { l.plate })
        TriggerClientEvent('vgx-showroom:despawnSlot', -1, sr.id, l.slot_id)
    end

    MySQL.update.await('DELETE FROM showroom_listings WHERE showroom_id = ?', { sr.id })
    MySQL.update.await('DELETE FROM showroom_staff WHERE showroom_id = ?', { sr.id })
    MySQL.update.await('DELETE FROM showroom_slots WHERE showroom_id = ?', { sr.id })
    MySQL.update.await('DELETE FROM showrooms WHERE id = ?', { sr.id })

    LoadShowrooms()
    SyncAll()
    SendWebhook('admin', '💥 Showroom Deleted', {
        { 'Showroom', sr.name .. ' (#' .. sr.id .. ')', false },
        { 'Deleted by', PName(P) .. '\n`' .. P.PlayerData.citizenid .. '`' },
    }, nil, sr.name)
    Notify(src, 'Showroom #' .. sr.id .. ' deleted — listed vehicles returned to their owners', 'success')
end)

-- Rename
RegisterNetEvent('vgx-showroom:server:adminRename', function(showroomId, name)
    local src = source
    local P = GP(src)
    if not P or not IsShowroomAdmin(src) then return end

    local sr = GetShowroom(showroomId)
    if not sr then return end

    name = tostring(name or ''):sub(1, 80)
    if name == '' then return end

    MySQL.update.await('UPDATE showrooms SET name = ? WHERE id = ?', { name, sr.id })
    LoadShowrooms()
    SyncAll()
    Notify(src, 'Showroom renamed to ' .. name, 'success')
end)

-- Assign / clear owner by online server ID
RegisterNetEvent('vgx-showroom:server:adminSetOwner', function(showroomId, targetId)
    local src = source
    local P = GP(src)
    if not P or not IsShowroomAdmin(src) then return end

    local sr = GetShowroom(showroomId)
    if not sr then return end

    if not targetId or tonumber(targetId) == 0 then
        MySQL.update.await('UPDATE showrooms SET owner_cid = NULL, owner_name = NULL WHERE id = ?', { sr.id })
        LoadShowrooms()
        SyncAll()
        return Notify(src, 'Owner removed from showroom #' .. sr.id, 'success')
    end

    local Target = QBCore.Functions.GetPlayer(tonumber(targetId))
    if not Target then return Notify(src, 'Player is not online', 'error') end

    local name = PName(Target)
    MySQL.update.await('UPDATE showrooms SET owner_cid = ?, owner_name = ? WHERE id = ?',
        { Target.PlayerData.citizenid, name, sr.id })
    -- if they were staff of this showroom, remove that row
    MySQL.update.await('DELETE FROM showroom_staff WHERE showroom_id = ? AND citizenid = ?',
        { sr.id, Target.PlayerData.citizenid })

    LoadShowrooms()
    SyncAll()
    SendWebhook('admin', '🔑 Showroom Owner Assigned', {
        { 'Showroom', sr.name .. ' (#' .. sr.id .. ')', false },
        { 'New Owner', name .. '\n`' .. Target.PlayerData.citizenid .. '`' },
        { 'Assigned by', PName(P) .. '\n`' .. P.PlayerData.citizenid .. '`' },
    }, nil, sr.name)
    Notify(src, name .. ' is now the owner of ' .. sr.name, 'success')
    Notify(Target.PlayerData.source, 'You are now the owner of showroom: ' .. sr.name, 'success')
end)

-- Update the interaction points of an existing showroom
RegisterNetEvent('vgx-showroom:server:adminUpdatePoints', function(showroomId, pointsIn)
    local src = source
    local P = GP(src)
    if not P or not IsShowroomAdmin(src) then return end

    local sr = GetShowroom(showroomId)
    if not sr then return end

    local points = {
        entrance = CleanPoint((pointsIn or {}).entrance),
        dropoff  = CleanPoint((pointsIn or {}).dropoff),
        tdspawn  = CleanPoint((pointsIn or {}).tdspawn, true),
        tdreturn = CleanPoint((pointsIn or {}).tdreturn),
    }
    if not points.entrance or not points.dropoff then
        return Notify(src, 'Entrance and drop-off points are required', 'error')
    end

    MySQL.update.await('UPDATE showrooms SET points = ? WHERE id = ?', { json.encode(points), sr.id })
    LoadShowrooms()
    SyncAll()
    Notify(src, 'Showroom #' .. sr.id .. ' points updated', 'success')
end)

-- Add ONE parking slot at the given position to an existing showroom
RegisterNetEvent('vgx-showroom:server:adminAddSlot', function(showroomId, point)
    local src = source
    local P = GP(src)
    if not P or not IsShowroomAdmin(src) then return end

    local sr = GetShowroom(showroomId)
    if not sr then return end

    local pt = CleanPoint(point, true)
    if not pt then return Notify(src, 'Invalid position', 'error') end

    local maxNo = MySQL.scalar.await('SELECT MAX(slot_no) FROM showroom_slots WHERE showroom_id = ?', { sr.id }) or 0
    local slotNo = maxNo + 1

    MySQL.insert.await('INSERT INTO showroom_slots (showroom_id, slot_no, x, y, z, heading) VALUES (?,?,?,?,?,?)',
        { sr.id, slotNo, pt.x, pt.y, pt.z, pt.w or 0.0 })

    LoadShowrooms()
    SyncAll()
    Notify(src, ('Parking slot #%s added to %s'):format(slotNo, sr.name), 'success')
end)

-- Remove a parking slot (only if empty)
RegisterNetEvent('vgx-showroom:server:adminRemoveSlot', function(showroomId, slotNo)
    local src = source
    local P = GP(src)
    if not P or not IsShowroomAdmin(src) then return end

    local sr = GetShowroom(showroomId)
    slotNo = tonumber(slotNo)
    if not sr or not slotNo then return end

    local taken = MySQL.query.await('SELECT id FROM showroom_listings WHERE showroom_id = ? AND slot_id = ?',
        { sr.id, slotNo })
    if taken and taken[1] then
        return Notify(src, 'Slot #' .. slotNo .. ' has a vehicle in it — remove the listing first', 'error')
    end

    MySQL.update.await('DELETE FROM showroom_slots WHERE showroom_id = ? AND slot_no = ?', { sr.id, slotNo })
    LoadShowrooms()
    SyncAll()
    Notify(src, 'Parking slot #' .. slotNo .. ' removed', 'success')
end)

-- Add / remove extra showroom-admins (super admins only)
RegisterNetEvent('vgx-showroom:server:adminAddAdmin', function(input)
    local src = source
    if not IsSuperAdmin(src) then return Notify(src, 'Only super admins can add admins', 'error') end

    input = tostring(input or ''):gsub('%s', '')
    if input == '' then return end

    local identifier, name

    if input:find('^discord:') or input:find('^license:') then
        identifier, name = input, input
    elseif input:match('^%d+$') and #input >= 15 then
        identifier, name = 'discord:' .. input, 'Discord: ' .. input
    else
        local Target = QBCore.Functions.GetPlayer(tonumber(input))
        if not Target then return Notify(src, 'Player not online — use a Discord ID or license directly', 'error') end
        local tsrc = Target.PlayerData.source
        identifier = GetIdent(tsrc, 'discord') or GetIdent(tsrc, 'license')
        if not identifier then return Notify(src, 'No identifier found for this player', 'error') end
        name = PName(Target)
    end

    MySQL.query.await('INSERT INTO showroom_admins (identifier, name) VALUES (?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name)',
        { identifier, name })
    ShowroomAdmins[identifier] = true
    Notify(src, name .. ' is now a showroom admin', 'success')
end)

RegisterNetEvent('vgx-showroom:server:adminRemoveAdmin', function(identifier)
    local src = source
    if not IsSuperAdmin(src) then return Notify(src, 'Only super admins can remove admins', 'error') end
    MySQL.update.await('DELETE FROM showroom_admins WHERE identifier = ?', { identifier })
    ShowroomAdmins[identifier] = nil
    Notify(src, 'Admin removed', 'success')
end)
