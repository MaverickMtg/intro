-- =============================================
-- FL-Admin Server Config (ConfigS.lua)
-- Kept separate from shared Config.lua
-- =============================================

ConfigS = {}

-- Admin permission levels (higher = more power)
-- IMPORTANT: every role name used in Config.DiscordRoles MUST have a level
-- here. A missing role resolves to level 0, which means the holder can't
-- open the panel, fails every numeric HasPermission() check, AND — much
-- worse — lower staff could act on them because CanActOnTarget() compares
-- these levels (a Manager at level 0 was "outranked" by a TrialMod at 10).
ConfigS.PermissionLevels = {
    ['FullPermissions']   = 100,
    -- Manager hierarchy (previously missing -> level 0)
    ['ServerManager']     = 95,
    ['ServerAssManager']  = 94,
    ['MTGTeam']           = 90,
    ['Founders']          = 85,
    ['HighManager']       = 82,
    ['HighAssManager']    = 81,
    ['StaffManagers']     = 80,
    ['GeneralManager']    = 78,
    ['GeneralAssManager'] = 77,
    ['Management']        = 75,
    ['Admin']             = 70,
    ['Operator']          = 65,
    ['Organizer']         = 60,
    -- Specialized teams (previously missing -> level 0)
    ['BanTeam']           = 60, -- needs >= 60 to ban/unban
    ['Cordinator']        = 55,
    ['Staff']             = 50,
    ['CensorTeam']        = 50,
    ['EventTeam']         = 50,
    ['LogTeam']           = 50,
    ['TicketTeam']        = 50,
    ['IDNamesTeam']       = 50,
    ['StreamerTeam']      = 50,
    ['StoreManager']      = 50,
    ['Advisor']           = 45,
    ['Expert']            = 40,
    ['Supervisor']        = 35,
    ['Skilled']           = 30,
    ['Trusted']           = 25,
    ['Experience']        = 20,
    ['Trial']             = 18,
    ['SeniorMod']         = 15,
    ['Mod']               = 12,
    ['TrialMod']          = 10,
    ['Support']           = 5,
}

-- Extra named permissions referenced by Config.AdminMenuCategories (feature flags).
-- They are given a level so HasPermission(level) style checks still work.
for _, name in ipairs({
    'EventsManager', 'ReportsManager', 'HoursManager', 'StaffPoints', 'Names',
    'Vehicles', 'MuteChat', 'MuteVoice', 'ReviveRadius', 'Unban', 'Unjail',
    'Freeze', 'Spectate', 'Announcements', 'GodMode', 'DirectMessage', 'Trial',
}) do
    if not ConfigS.PermissionLevels[name] then
        ConfigS.PermissionLevels[name] = 50
    end
end

-- Minimum permission level required to open admin panel
ConfigS.MinPermissionLevel = 5

-- =============================================
-- DISCORD PERMISSION SOURCE
-- =============================================
-- Map each Discord ROLE ID to one of the permission names above.
-- Fill this in to grant staff access by Discord role. Example:
--   ['1311849668560551952'] = 'FullPermissions',
--   ['967564341618565143']  = 'EventsManager',
-- The full role -> permission mapping is maintained in Config.lua (shared_script,
-- loaded before this file) so there's a single source of truth. Previously this
-- table was left as an empty stub, meaning no Discord role ever resolved to any
-- permission on the live server.
ConfigS.DiscordRoles = (Config and Config.DiscordRoles) or {}

-- Bot credentials used to read a player's Discord roles.
-- Set via server.cfg:  setr tg_admin_bot_token "xxx"  /  setr tg_admin_guild_id "xxx"
ConfigS.BotToken = GetConvar('tg_admin_bot_token', '')
ConfigS.GuildId  = GetConvar('tg_admin_guild_id', '')
ConfigS.RoleCacheTime = 300 -- seconds

-- SAFETY: if no Discord roles are configured AND the bot token is empty,
-- fall back to ACE permissions only (server console + players with the "admin"
-- or "command" ace). Set this to true ONLY for local testing to make everyone
-- an admin (NEVER on a live server).
ConfigS.AllowEveryoneWhenUnconfigured = false


