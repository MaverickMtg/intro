-- ============================================================
--  VGX Showroom v4 — Config
--  Showrooms are now created ENTIRELY IN-GAME via /showrooms
--  (like lt-shops): create showroom, capture parking slots,
--  entrance / drop-off / test-drive points, assign owners.
--  Nothing location-related lives in this file anymore.
-- ============================================================

Config = {}

Config.TaxRate        = 0.10
Config.TestDriveTime  = 1     -- minutes
Config.AllowTestDrive = false
Config.NotifyDuration = 5000

-- ══════════════════════════════════════════════════════════
--  ADMINS — identifier based, no QBCore god/admin groups
--  Super admins can open /showrooms, create/delete showrooms,
--  assign owners AND add extra showroom-admins from the panel.
-- ══════════════════════════════════════════════════════════
Config.SuperAdmins = {
    'discord:1252054303657689149',
    -- 'license:1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b',
}

Config.AdminCommand = 'showrooms'

-- ══════════════════════════════════════════════════════════
--  DISCORD WEBHOOKS — logs every action with full details
-- ══════════════════════════════════════════════════════════
Config.Webhooks = {
    enabled  = true,
    botName  = 'Showrooms',
    avatar   = '', -- optional image URL for the webhook avatar

    purchase = 'https://discord.com/api/webhooks/1515177720328356002/_39hLx7pzrbQKMexWieFas42Ijc-mUYHqL8o0j-MhbHDl_ZsqcuJM_cZmswgYm_efkdQ', -- car sold / bought
    listing  = 'https://discord.com/api/webhooks/1515178548623704228/TOkORB_ycoS--iDac8agqbTKcSboXSzTDKkbfG2h0hbCetCFuop6vlyAoPw6mgQBU9Nn', -- vehicle added to showroom
    removal  = 'https://discord.com/api/webhooks/1515177720328356002/_39hLx7pzrbQKMexWieFas42Ijc-mUYHqL8o0j-MhbHDl_ZsqcuJM_cZmswgYm_efkdQ', -- vehicle removed
    price    = 'https://discord.com/api/webhooks/1515178694069587999/iczrlA873JjqpIlaXwxCSmZYVKslE2vb_NGMEIxOXcYoWyIX9K4r-nRKG5SQxxoY4heB', -- price changed
    staff    = 'https://discord.com/api/webhooks/1515178741888847893/6BmdxAnVQD-v6qLf8hJGiLDA1H4Q8lW0VGtqKCQ7z_3beW9LOcaHD4oR3hPtfAyePoBA', -- hire / fire
    admin    = '', -- showroom created / deleted / owner changed (leave '' to disable)
}

-- ── Payments ───────────────────────────────────────────────
Config.Payments = {
    sellerAccount   = 'bank',  -- 'bank' or 'cash' — where the car seller receives the price
    ownerAccount    = 'bank',  -- 'bank' or 'cash' — where the showroom owner receives tax/commission

    -- When enabled, every showroom's tax/commission pools into its OWN
    -- society-backed treasury ('showroom_<id>') that the owner withdraws
    -- from the showroom UI on demand.
    useTreasury     = true,
    taxToOwner      = true,    -- the tax on every sale is paid to the showroom's owner
    ownerCommission = 0.0,     -- extra % of price (0.0 - 1.0) the owner takes from staff sales
    buyerGarage     = 'pillboxgarage', -- garage where the purchased vehicle appears for the buyer
}

-- ── Map blip for every showroom (name is per-showroom, set in-game) ──
Config.Blip = { sprite = 326, color = 3, scale = 0.8 }

-- ── Interaction ────────────────────────────────────────────
Config.EntranceRadius = 2.0   -- press-E radius at the entrance marker
Config.DropOffRadius  = 3.0   -- press-E radius at the vehicle drop-off marker

-- Staff roles and permissions (same for every showroom)
Config.Roles = {
    owner    = { label = 'Owner',    canManageStaff = true,  canAddVehicle = true,  canSetPrice = true,  canRemoveVehicle = true  },
    manager  = { label = 'Manager',  canManageStaff = false, canAddVehicle = true,  canSetPrice = true,  canRemoveVehicle = true  },
    employee = { label = 'Employee', canManageStaff = false, canAddVehicle = true,  canSetPrice = false, canRemoveVehicle = false },
}
