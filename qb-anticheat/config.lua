Config = {}

-- ==========================================================================
--  GENERAL
-- ==========================================================================
Config.Debug = false                -- print extra info to the server console
Config.ServerName = 'MaverickMtg'   -- shown in webhook footers / logs

-- Where flat-file logs are written (relative to the resource folder).
-- One JSON-line per detection is appended here as a permanent audit trail.
Config.LogFile = 'detections.log'

-- ==========================================================================
--  ADMIN BYPASS
--  Admins are never punished. Detections against them are still logged so
--  you can spot a compromised admin account, but no kick/ban is applied.
-- ==========================================================================
Config.AdminBypass = true
-- QBCore permission levels considered "admin" (see QBCore.Functions.HasPermission)
Config.AdminPermissions = { 'god', 'admin' }
-- Extra ACE permission that also counts as admin (leave '' to disable)
Config.AdminAce = 'qb-anticheat.bypass'

-- ==========================================================================
--  PUNISHMENT
--  Action per detection category: 'log' | 'kick' | 'ban'
--  'log'  -> record + webhook only
--  'kick' -> record + webhook + drop the player
--  'ban'  -> record + webhook + permanent ban (stored in bans.json)
-- ==========================================================================
Config.Actions = {
    explosionSpam   = 'ban',   -- boom-vehicle / crush / mass explosions
    entitySpam      = 'kick',  -- bot/vehicle flooding ("Crasher", black-hole, bus spam)
    blacklistEntity = 'ban',   -- spawning a blacklisted model
    weaponExploit   = 'ban',   -- modified weapon damage / illegal weapon
    eventFlood      = 'ban',   -- spamming a protected server event (revive-crash, cuff-all...)
    teleport        = 'log',   -- suspicious long-distance movement (log by default: many false positives)
    godMode         = 'kick',
    noclip          = 'kick',
    invisible       = 'log',
    tamper          = 'ban',   -- client anti-cheat stopped / heartbeat lost
}

-- Number of flags of the SAME category tolerated before the action escalates
-- to a ban (protects against one-off false positives for kick-level checks).
Config.MaxFlagsBeforeBan = {
    godMode = 3,
    noclip  = 3,
    entitySpam = 2,
}

Config.KickMessage = 'You were removed by %s Anti-Cheat.\nReason: %s'
Config.BanMessage  = 'You are banned from %s.\nReason: %s\nBan ID: %s'

-- ==========================================================================
--  DISCORD WEBHOOKS
--  Paste your webhook URLs. Any left blank falls back to `default`.
-- ==========================================================================
Config.Webhooks = {
    default    = '',
    bans       = '',
    explosions = '',
    entities   = '',
    weapons    = '',
    events     = '',
    movement   = '',
    tamper     = '',
}

Config.WebhookBotName = 'QB Anti-Cheat'
Config.WebhookAvatar  = ''  -- optional avatar image URL

-- Embed colour per severity (decimal Discord colour values)
Config.WebhookColors = {
    info = 3447003,   -- blue
    warn = 16776960,  -- yellow
    ban  = 15158332,  -- red
}

-- ==========================================================================
--  EXPLOSION PROTECTION (server-authoritative)
-- ==========================================================================
Config.Explosions = {
    enable = true,
    -- Explosion types that are ALWAYS cancelled (see explosion type list in docs).
    -- These are almost never legitimately caused by a normal player.
    blacklist = {
        [2]  = true,  -- MOLOTOV
        [4]  = true,  -- CAR (used by boom-vehicle troll)
        [7]  = true,  -- ROCKET-adjacent
        [8]  = true,  -- HI_OCTANE
        [24] = true,  -- EXTRA_LARGE
        [26] = true,  -- BUOY
        [27] = true,  -- FLARE-adjacent
        [28] = true,
        [29] = true,  -- RAYGUN
        [30] = true,
        [31] = true,
    },
    -- Rate limit for ANY explosion caused by one player.
    maxPerInterval = 4,
    interval = 10000, -- ms
}

-- ==========================================================================
--  ENTITY SPAWN PROTECTION (server-authoritative)
--  Counters bot/ped flooding, mass vehicle spawns, black-hole / bus attach.
-- ==========================================================================
Config.EntitySpawn = {
    enable = true,
    maxVehiclesPerInterval = 12,
    maxPedsPerInterval     = 15,
    maxObjectsPerInterval  = 25,
    interval = 10000, -- ms
    deleteOnFlag = true, -- delete the entities created during a burst
    -- Models that are never allowed to be spawned by a client.
    blacklistedModels = {
        [`bus`]   = true,
        [`airbus`]= true,
        [`coach`] = true,
    },
}

-- ==========================================================================
--  WEAPON DAMAGE PROTECTION (server-authoritative)
-- ==========================================================================
Config.WeaponDamage = {
    enable = true,
    -- Cancel any single hit above this damage value (super-punch / damage mod).
    maxDamage = 250.0,
    -- Weapons that a client should never be able to deal damage with.
    blacklistedWeapons = {
        [`WEAPON_STINGER`]   = true,
        [`WEAPON_RPG`]       = true,
        [`WEAPON_GRENADELAUNCHER`] = true,
        [`WEAPON_RAYMINIGUN`]= true,
        [`WEAPON_RAYPISTOL`] = true,
        [`WEAPON_RAYCARBINE`]= true,
        [`VEHICLE_WEAPON_TANK`] = true,
    },
    -- Cancel melee "super punch" (unarmed doing real damage).
    guardUnarmed = true,
    unarmedMaxDamage = 40.0,
}

-- ==========================================================================
--  PROTECTED EVENT FLOOD GUARD (server-authoritative)
--  These are the framework events the cheat abuses. We can't stop the owning
--  resource from also handling them, but we detect the *flood* and punish the
--  sender before real damage is done (e.g. revive-spam crash).
--  Tune max/interval to your server. `perTarget` guards args like a target id.
-- ==========================================================================
Config.EventFlood = {
    enable = true,
    events = {
        ['hospital:server:RevivePlayer']   = { max = 4,  interval = 10000 },
        ['police:server:CuffPlayer']       = { max = 6,  interval = 10000 },
        ['police:server:KidnapPlayer']     = { max = 4,  interval = 10000 },
        ['police:server:RobPlayer']        = { max = 4,  interval = 10000 },
        ['police:server:SearchPlayer']     = { max = 6,  interval = 10000 },
        ['inventory:server:OpenInventory'] = { max = 15, interval = 10000 },
        ['QBCore:server:Paymentcheck']     = { max = 5,  interval = 10000 },
    },
}

-- ==========================================================================
--  MOVEMENT / TELEPORT DETECTION (server-authoritative, best-effort)
-- ==========================================================================
Config.Movement = {
    enable = true,
    checkInterval = 2000, -- ms between position samples
    -- Speed (metres/second) above which movement is flagged. Legit teleports
    -- (menus, interiors, respawn) will trip this, hence default action is 'log'.
    maxSpeed = 120.0,
    -- Grace after connect / spawn before checks begin.
    graceMs = 15000,
}

-- ==========================================================================
--  HEARTBEAT / TAMPER DETECTION
--  The client sends a heartbeat. If it stops (cheat "MachoResourceStop",
--  killing the anti-cheat, or freezing the client script) we detect it.
-- ==========================================================================
Config.Heartbeat = {
    enable = true,
    clientInterval = 5000, -- how often the client beats
    serverTimeout  = 20000, -- flag a player after this long with no beat
    graceMs = 20000,        -- initial grace after connect
}
