Config                    = {}

-- ═══════════════════════════════════════════════════════════
--  LT-SHOPS | Player Owned Shops (Grocery + Weapon Store)
--  Legends RP
-- ═══════════════════════════════════════════════════════════

-- Ped models (per shop type)
Config.Peds               = {
    grocery = {
        seller = 's_m_m_linecook',   -- staff / manage ped
        buyer  = 'mp_m_shopkeep_01', -- customer ped
    },
    weapon = {
        seller = 's_m_y_ammucity_01',
        buyer  = 's_m_m_ammucountry',
    },
}

-- Default blips (sprite/color per type) - owner chooses the NAME in-game
Config.Blips              = {
    grocery = { sprite = 59, color = 2, scale = 0.75 },
    weapon  = { sprite = 110, color = 1, scale = 0.75 },
}

-- qb-inventory image path for NUI
Config.InventoryImagePath = 'https://cfx-nui-qb-inventory/html/images/'

-- ═══════════════ PERMISSIONS MATRIX ═══════════════
-- grades: owner > manager > employee
Config.Permissions        = {
    owner = {
        listings = true,   -- add / edit / remove items for sale
        storage  = true,   -- deposit + withdraw from shop storage
        staff    = true,   -- hire / fire / promote (all grades)
        safe     = true,   -- view revenue + withdraw money
        settings = true,   -- rename blip
        toggle   = true,   -- open / close (weapon shops)
        craft    = true,   -- use crafting table (weapon shops)
        license  = true,   -- sign & issue weapon licenses
    },
    manager = {
        listings = true,
        storage  = true,
        staff    = 'employee',   -- can only hire/fire employees
        safe     = 'view',       -- can see revenue, cannot withdraw
        settings = false,
        toggle   = true,
        craft    = true,
        license  = false,
    },
    employee = {
        listings = true,        -- can restock / add items for sale
        storage  = 'deposit',   -- can only PUT items in (crafting materials etc)
        staff    = false,
        safe     = false,
        settings = false,
        toggle   = false,
        craft    = false,
        license  = false,
    },
}

-- ═══════════════ SAFE / ROBBERY ═══════════════
Config.Safe               = {
    lockpickItem     = 'lockpick', -- item required to rob
    removeOnFail     = true,       -- break lockpick on fail
    successChance    = 35,         -- % chance per attempt
    stealPercent     = 70,         -- % of safe money stolen on success
    cooldownMinutes  = 30,         -- per-shop cooldown between robbery attempts
    minMoney         = 500,        -- safe must have at least this to be lockpickable
    staffBlockRadius = 40.0,       -- cannot rob if shop staff is within this range ("in the premises")
    policeAlert      = true,       -- send police:server:policeAlert
    robTime          = 15000,      -- ms progressbar
}

-- ═══════════════ WEAPON LICENSE ═══════════════
Config.License            = {
    item = 'weaponlicense', -- add to qb-core shared items (see README)
    -- buyers at WEAPON shops must carry a SIGNED license, or they cannot buy
}

-- ═══════════════ WEAPON CRAFTING ═══════════════
-- Materials are consumed from the SHOP STORAGE (the stash employees fill),
-- NOT from the crafter's pockets.
-- >> Replace/extend these with the weapons you want <<

Config.Crafting           = {
    { item = 'weapon_pistol',        label = 'Pistol',         time = 15000, materials = { { item = 'iron', amount = 480 }, { item = 'aluminum', amount = 246 }, { item = 'rubber', amount = 342 }, { item = 'metalscrap', amount = 219 } } },
    { item = 'weapon_snspistol_mk2', label = 'SNS Pistol MK2', time = 20000, materials = { { item = 'iron', amount = 480 }, { item = 'aluminum', amount = 246 }, { item = 'rubber', amount = 342 }, { item = 'metalscrap', amount = 219 } } },
    { item = 'weapon_pistol_mk2',    label = 'Pistol MK2',     time = 20000, materials = { { item = 'iron', amount = 480 }, { item = 'aluminum', amount = 246 }, { item = 'rubber', amount = 342 }, { item = 'metalscrap', amount = 219 } } },
    { item = 'weapon_heavypistol',   label = 'Heacy Pistol',   time = 20000, materials = { { item = 'iron', amount = 480 }, { item = 'aluminum', amount = 246 }, { item = 'rubber', amount = 342 }, { item = 'metalscrap', amount = 219 } } },
    { item = 'weapon_vintagepistol', label = 'Vintage Pistol', time = 20000, materials = { { item = 'iron', amount = 480 }, { item = 'aluminum', amount = 246 }, { item = 'rubber', amount = 342 }, { item = 'metalscrap', amount = 219 } } },
    { item = 'weapon_ceramicpistol', label = 'Ceramic Pistol', time = 20000, materials = { { item = 'iron', amount = 480 }, { item = 'aluminum', amount = 246 }, { item = 'rubber', amount = 342 }, { item = 'metalscrap', amount = 219 } } },
}

-- ═══════════════ ADMIN ═══════════════
-- SUPER ADMINS (server owner) — full control + can add/remove shop admins from the panel.
-- Put your Discord ID and/or FiveM license here:
Config.SuperAdmins        = {
    'discord:1252054303657689149',
    -- 'license:1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b',
}
-- Extra shop admins are added from inside the panel ( /shops -> المشرفين )
-- by online player ID, Discord ID, or license — no QBCore 'god'/'admin' groups used.

Config.AdminCommand       = 'shops'

-- ═══════════════ MISC ═══════════════
Config.MaxListingsPerShop = 50
Config.SalesTax           = 15 -- % taken from every sale before it reaches the safe (0 = none)
Config.InteractDistance   = 2.5
