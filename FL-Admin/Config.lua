Config = {}

Config.Debug = false
-- Config.SpawnCoords = vector4(3078.8564, -883.8779, 1913.4249, 194.7224) -- 'FL-Core:SendToSpawn'

--------------------------------------------------------------------------------
-- DISCORD ROLE MAPPINGS
--------------------------------------------------------------------------------
Config.DiscordRoles = {
    -- Full Management & Server Owners (Manage All)
    ['1479653715073044572'] = 'FullPermissions', -- Server Owner
    ['1479653793170849973'] = 'FullPermissions', -- Server Co Owner
    ['1333448407074869379'] = 'FullPermissions', -- Owner
    ['1439804745102528582'] = 'FullPermissions', -- Co Owner
    ['1485046285709873243'] = 'FullPermissions', -- Role to Manage All
    ['1454410421481246720'] = 'ServerManager',   -- Server Manager (Can manage all)
    ['1459205001061601391'] = 'ServerAssManager',-- Server Ass Manager (Can manage all)

    -- Founders
    ['1333448428016894023'] = 'Founders',        -- Founder
    ['1479905745238495436'] = 'Founders',        -- Co Founder

    -- Management Hierarchy
    ['1333448408601727088'] = 'HighManager',     -- High Manager (Can manage General Manager)
    ['1446569002330751106'] = 'HighAssManager',  -- High Ass Manager (Can manage General Manager)
    ['1400854549920616480'] = 'GeneralManager',  -- General Manager (Can manage staff)
    ['1400854690698367046'] = 'GeneralAssManager',-- General Ass Manager (Can manage staff)

    -- Specialized Teams
    ['1459171582797811734'] = 'IDNamesTeam',     -- ID Names Team
    ['1485889837746880522'] = 'StreamerTeam',    -- Streamer Team
    ['1401774938024706129'] = 'CensorTeam',      -- Censor Team
    ['1333448504839897235'] = 'BanTeam',         -- Ban Team
    ['1333448508216311988'] = 'EventTeam',       -- Event Team
    ['1333448506437926912'] = 'LogTeam',         -- Log Team
    ['1333448509503967324'] = 'TicketTeam',      -- Ticket Team

    -- Standard Staff Roles
    -- ['1512437140775239730'] = 'MTGTeam',
    ['1333448430902579360'] = 'Admin', -- Master
    ['1333448433633329293'] = 'Admin', -- Console
    ['1333448436023820430'] = 'Admin', -- Head Admin
    ['1333448446807511153'] = 'Operator',
    ['1333448448099221504'] = 'Organizer',
    ['1333448450594967624'] = 'Cordinator', -- Coordinator
    ['1333448452184735884'] = 'Staff',
    ['1476351119268515953'] = 'Advisor',
    ['1476351121277587528'] = 'Expert',
    ['1476351123072880746'] = 'Supervisor',
    ['1476351124125519872'] = 'Skilled',
    ['1476351124989808835'] = 'Trusted',
    ['1476351125606109385'] = 'Experience',
    ['1333448472371662901'] = 'Trial',
    ['1333448475349618808'] = 'SeniorMod',
    ['1476351128273948785'] = 'Mod',
    ['1333448476767420466'] = 'TrialMod',
    ['1333448478277505108'] = { 'Support', 'MuteChat', 'MuteVoice', 'Spectate' },

    -- Permission Overrides & Utilities
    ['1441350095194034206'] = { 'Names', 'ReviveRadius', 'Freeze' },
    ['1333448482341785600'] = 'Unban',
    ['1476351144287801354'] = 'Unjail',
    ['1476365228374626476'] = 'Announcements',
    ['1476351145382514995'] = 'Vehicles',
    ['1476351142349770822'] = 'GodMode',
    ['1476367366261571624'] = 'DirectMessage',

    ['1456474745892507699'] = { 'HoursManager', 'StaffPoints' },
    ['1489521127519682673'] = 'ReportsManager',
    ['1333448499714330635'] = 'EventsManager',
    ['1333448488972714116'] = 'StoreManager',
}

--------------------------------------------------------------------------------
-- PERMISSION GROUPS
--------------------------------------------------------------------------------
-- Managers: Can bring, kick, ban, manage events, and access manager utilities
local Managers = {
    'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager', 
    'HighManager', 'HighAssManager', 'GeneralManager', 'GeneralAssManager',
    'MTGTeam', 'Admin', 'Operator', 'Organizer', 'Cordinator', 'Staff', 'Advisor'
}

-- All Teams / General Staff: Can NoClip, accept tickets, jail (max time), and go to players
local AllStaffAndTeams = {
    'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager', 
    'HighManager', 'HighAssManager', 'GeneralManager', 'GeneralAssManager',
    'IDNamesTeam', 'StreamerTeam', 'CensorTeam', 'BanTeam', 'EventTeam', 
    'LogTeam', 'TicketTeam', 'MTGTeam', 'Admin', 'Operator', 'Organizer', 
    'Cordinator', 'Staff', 'Advisor', 'Expert', 'Supervisor', 'Skilled', 
    'Trusted', 'Experience', 'Trial', 'SeniorMod', 'Mod', 'TrialMod', 'Support'
}

--------------------------------------------------------------------------------
-- ADMIN MENU CONFIGURATION
--------------------------------------------------------------------------------
Config.AdminMenu = {
    Key = 'PAGEUP',
    Command = 'admin',
    Command2 = 'ad',
    PlayersKey = 'F11',
    PlayersCommand = 'adminplayers',
    RecordsKey = 'F10',
    RecordsCommand = 'adminrecords',
    Permission = AllStaffAndTeams
}

Config.AdminMenuCategories = {
    {
        title = 'Quick Options',
        icon = 'fa-solid fa-bolt',
        permission = AllStaffAndTeams,
        options = {
            { title = 'NoClip',             icon = 'fa-solid fa-ghost',      event = 'Vikto:Admin:ToggleNoClip',        permission = AllStaffAndTeams },
            { title = 'Jail Player',        icon = 'fa-solid fa-dungeon',    event = 'Vikto:Admin:JailPlayer',          permission = AllStaffAndTeams },
            { title = 'Ban Player',         icon = 'fa-solid fa-gavel',      event = 'Vikto:Admin:BanPlayer',           permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager', 'HighManager', 'HighAssManager', 'GeneralManager', 'GeneralAssManager', 'BanTeam' } },
            { title = 'Heal Self',          icon = 'fa-solid fa-medkit',     event = 'Vikto:Admin:ReviveSelf',          permission = Managers },
            { title = 'Spawn Car',          icon = 'fa-solid fa-car-side',   event = 'vikto_admin:client:spawnVehicle', permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager', 'Vehicles' } },
            { title = 'Show Names',         icon = 'fa-solid fa-id-badge',   event = 'Vikto:Admin:ToggleNames',         permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager', 'IDNamesTeam', 'Names' } },
            { title = 'Teleport to Coords', icon = 'fa-solid fa-crosshairs', event = 'Vikto:Admin:TeleportToCoords',    permission = Managers },
        }
    },
    {
        title = 'Admin Options',
        icon = 'fa-solid fa-user-shield',
        permission = AllStaffAndTeams,
        options = {
            { title = 'NoClip',                   icon = 'fa-solid fa-ghost',                event = 'Vikto:Admin:ToggleNoClip',      permission = AllStaffAndTeams, keybind = 'PAGEDOWN' },
            { title = 'Teleport To Locations',    icon = 'fa-solid fa-map-location',         event = 'Vikto:Admin:TeleportLocations', permission = Managers },
            { title = 'Teleport To Waypoint',     icon = 'fa-solid fa-location-arrow',       event = 'Vikto:Admin:TeleportTPM',       permission = Managers, keybind = '' },
            { title = 'Teleport to Coords',       icon = 'fa-solid fa-crosshairs',           event = 'Vikto:Admin:TeleportToCoords',  permission = Managers },
            { title = 'Go To Player',             icon = 'fa-solid fa-paper-plane',          event = 'Vikto:Admin:GoToPlayer',        permission = AllStaffAndTeams },
            { title = 'Bring Player',             icon = 'fa-solid fa-magnet',               event = 'Vikto:Admin:BringPlayer',       permission = Managers, keybind = '' },
            { title = 'Revive',                   icon = 'fa-solid fa-medkit',               event = 'Vikto:Admin:ReviveSelf',        permission = Managers },
            { title = 'Invisible',                icon = 'fa-solid fa-eye-slash',            event = 'Vikto:Admin:ToggleInvisible',   permission = Managers },
            { title = 'God Mode',                 icon = 'fa-solid fa-shield-heart',         event = 'Vikto:Admin:ToggleGodMode',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'GodMode' } },
            { title = 'Super Jump',               icon = 'fa-solid fa-bolt-lightning',       event = 'Vikto:Admin:ToggleSuperJump',   permission = Managers },
            { title = 'Fast Run',                 icon = 'fa-solid fa-wind',                 event = 'Vikto:Admin:ToggleFastRun',     permission = Managers },
            { title = 'Player Names',             icon = 'fa-solid fa-id-badge',             event = 'Vikto:Admin:ToggleNames',       permission = { 'FullPermissions', 'Founders', 'ServerManager', 'IDNamesTeam', 'Names' }, keybind = '' },
            { title = 'Player Blips',             icon = 'fa-solid fa-satellite-dish',       event = 'Vikto:Admin:ToggleBlips',       permission = Managers },
            { title = 'Direct Message',           icon = 'fa-solid fa-comment-dots',         event = 'Vikto:Admin:MessagePlayer',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'DirectMessage' } },
            { title = 'Message Player (Reportr)', icon = 'fa-solid fa-comment-dots',         event = 'Vikto:Admin:MessageID',         permission = AllStaffAndTeams },
            { title = 'Server Announcement',      icon = 'fa-solid fa-bullhorn',             event = 'Vikto:Admin:Announce',          permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Announcements' } },
            { title = 'Warn Player',              icon = 'fa-solid fa-triangle-exclamation', event = 'Vikto:Admin:WarnPlayer',        permission = Managers },
            { title = 'Clear Chat',               icon = 'fa-solid fa-trash-can',            event = 'vikto_admin:client:clearChat',  permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam' } },
        }
    },
    {
        title = 'Player Management',
        icon = 'fa-solid fa-users-gear',
        permission = AllStaffAndTeams,
        options = {
            { title = 'Kill Player',     icon = 'fa-solid fa-skull-crossbones', event = 'Vikto:Admin:KillPlayer',     permission = Managers },
            { title = 'Revive Player',   icon = 'fa-solid fa-heart-pulse',      event = 'Vikto:Admin:RevivePlayer',   permission = Managers },
            { title = 'Revive Radius',   icon = 'fa-solid fa-circle-radiation', event = 'Vikto:Admin:ReviveRadius',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReviveRadius' } },
            { title = 'Revive All',      icon = 'fa-solid fa-staff-snake',      event = 'Vikto:Admin:ReviveAll',      permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
            { title = 'Mute Voice',      icon = 'fa-solid fa-microphone-slash', event = 'Vikto:Admin:MutePlayer',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteVoice' } },
            { title = 'Unmute Voice',    icon = 'fa-solid fa-microphone',       event = 'Vikto:Admin:UnmutePlayer',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteVoice' } },
            { title = 'Mute Chat',       icon = 'fa-solid fa-comment-slash',    event = 'Vikto:Admin:MuteChat',       permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteChat' } },
            { title = 'Unmute Chat',     icon = 'fa-solid fa-comment',          event = 'Vikto:Admin:UnmuteChat',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteChat' } },
            { title = 'Freeze Player',   icon = 'fa-solid fa-snowflake',        event = 'Vikto:Admin:FreezePlayer',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Freeze' } },
            { title = 'Unfreeze Player', icon = 'fa-solid fa-fire',             event = 'Vikto:Admin:UnfreezePlayer', permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Freeze' } },
            { title = 'Kick Player',     icon = 'fa-solid fa-door-open',        event = 'Vikto:Admin:KickPlayer',     permission = Managers },
            { title = 'Ban Player',      icon = 'fa-solid fa-gavel',            event = 'Vikto:Admin:BanPlayer',      permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager', 'HighManager', 'HighAssManager', 'GeneralManager', 'GeneralAssManager', 'BanTeam' }, keybind = '' },
            { title = 'Unban Player',    icon = 'fa-solid fa-unlock-keyhole',   event = 'Vikto:Admin:UnbanPlayer',    permission = { 'FullPermissions', 'Founders', 'ServerManager', 'BanTeam', 'Unban' } },
            { title = 'Jail Player',     icon = 'fa-solid fa-dungeon',          event = 'Vikto:Admin:JailPlayer',     permission = AllStaffAndTeams, keybind = '' },
            { title = 'Unjail Player',   icon = 'fa-solid fa-key',              event = 'Vikto:Admin:UnJailPlayer',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Unjail' } },
            { title = 'Check Jail Time', icon = 'fa-solid fa-hourglass-half',   event = 'Vikto:Admin:CheckJailTime',  permission = AllStaffAndTeams },
            { title = 'Give Item',       icon = 'fa-solid fa-box-open',         event = 'Vikto:Admin:GiveItem',       permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
            { title = 'Remove Item',     icon = 'fa-solid fa-box-archive',      event = 'Vikto:Admin:RemoveItem',     permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
            { title = 'Check Radio',     icon = 'fa-solid fa-walkie-talkie',    event = 'Vikto:Admin:CheckRadio',     permission = AllStaffAndTeams },
            { title = 'Spectate',        icon = 'fa-solid fa-binoculars',       event = 'Vikto:Admin:Spectate',       permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Spectate' } },
            { title = 'Send To Spawn',   icon = 'fa-solid fa-house-user',       event = 'Vikto:Admin:SendToSpawn',    permission = AllStaffAndTeams },
        }
    },
    {
        title = 'Vehicle Options',
        icon = 'fa-solid fa-car-rear',
        permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Vehicles' },
        options = {
            { title = 'Spawn Vehicle',  icon = 'fa-solid fa-car-side',           event = 'vikto_admin:client:spawnVehicle',  permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Vehicles' } },
            { title = 'Delete Vehicle', icon = 'fa-solid fa-car-burst',          event = 'vikto_admin:client:deleteVehicle', permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Vehicles' } },
            { title = 'Fix Vehicle',    icon = 'fa-solid fa-screwdriver-wrench', event = 'vikto_admin:client:fixVehicle',    permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Vehicles' } },
        }
    },
    {
        title = 'Reports System',
        icon = 'fa-solid fa-circle-exclamation',
        hidden = true,
        permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReportsManager', 'StaffPoints' },
        options = {
            { title = 'Add Reports',         icon = 'fa-solid fa-calendar-plus',          event = 'Vikto:Admin:AddReports',        permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReportsManager' } },
            { title = 'Remove Reports',      icon = 'fa-solid fa-calendar-minus',         event = 'Vikto:Admin:RemoveReports',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReportsManager' } },
            { title = 'View Player Reports', icon = 'fa-solid fa-magnifying-glass-chart', event = 'Vikto:Admin:ViewPlayerReports', permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReportsManager' } },
            { title = 'Reset All Reports',   icon = 'fa-solid fa-arrow-rotate-left',      event = 'Vikto:Admin:ResetAllReports',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReportsManager' } },
            { title = 'Send Reports LB',     icon = 'fa-solid fa-paper-plane',            event = 'Vikto:Admin:SendReportsLB',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReportsManager' } },
            { title = 'Update Reports LB',   icon = 'fa-solid fa-rotate',                 event = 'Vikto:Admin:UpdateReportsLB',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReportsManager' } },
        },
    },
    {
        title = 'Hours System',
        icon = 'fa-solid fa-hourglass-half',
        hidden = true,
        permission = { 'FullPermissions', 'Founders', 'ServerManager', 'HoursManager', 'StaffPoints' },
        options = {
            { title = 'Add Hours',       icon = 'fa-solid fa-plus',           event = 'Vikto:Admin:AddHours',      permission = { 'FullPermissions', 'Founders', 'ServerManager', 'HoursManager' } },
            { title = 'Remove Hours',    icon = 'fa-solid fa-minus',          event = 'Vikto:Admin:RemoveHours',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'HoursManager' } },
            { title = 'View Hours',      icon = 'fa-solid fa-eye',            event = 'Vikto:Admin:ViewHours',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'HoursManager' } },
            { title = 'Reset All Hours', icon = 'fa-solid fa-trash-arrow-up', event = 'Vikto:Admin:ResetHours',    permission = { 'FullPermissions', 'Founders', 'ServerManager', 'HoursManager' } },
            { title = 'Send Hours LB',   icon = 'fa-solid fa-paper-plane',    event = 'Vikto:Admin:SendHoursLB',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'HoursManager' } },
            { title = 'Update Hours LB', icon = 'fa-solid fa-rotate',         event = 'Vikto:Admin:UpdateHoursLB', permission = { 'FullPermissions', 'Founders', 'ServerManager', 'HoursManager' } },
        }
    },
    {
        title = 'Staff Points',
        icon = 'fa-solid fa-star',
        permission = { 'FullPermissions', 'Founders', 'ServerManager', 'StaffPoints', 'HoursManager', 'ReportsManager', 'EventsManager' },
        options = {
            { title = 'Event System',    icon = 'fa-solid fa-star',               targetMenu = 'category_event_system',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'EventsManager' } },
            { title = 'Reports System',  icon = 'fa-solid fa-circle-exclamation', targetMenu = 'category_reports_system', permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReportsManager' } },
            { title = 'Hours System',    icon = 'fa-solid fa-hourglass-half',     targetMenu = 'category_hours_system',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'HoursManager' } },
            { title = 'Send Staff LB',   icon = 'fa-solid fa-paper-plane',        event = 'Vikto:Admin:SendStaffLB',      permission = { 'FullPermissions', 'Founders', 'ServerManager', 'StaffPoints' } },
            { title = 'Update Staff LB', icon = 'fa-solid fa-rotate',             event = 'Vikto:Admin:UpdateStaffLB',    permission = { 'FullPermissions', 'Founders', 'ServerManager', 'StaffPoints' } },
        }
    },
    {
        title = 'Matchmaking System',
        icon = 'fa-solid fa-trophy',
        hidden = true,
        permission = { 'FullPermissions', 'Founders', 'ServerManager' },
        options = {
            { title = 'Add Points',    icon = 'fa-solid fa-plus',  event = 'Vikto:Admin:AddMatchmakingXP',    permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
            { title = 'Remove Points', icon = 'fa-solid fa-minus', event = 'Vikto:Admin:RemoveMatchmakingXP', permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
            { title = 'Check Points',  icon = 'fa-solid fa-eye',   event = 'Vikto:Admin:CheckMatchmakingXP',  permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
        }
    },
    {
        title = 'Truck System',
        icon = 'fa-solid fa-truck',
        hidden = true,
        permission = { 'FullPermissions', 'Founders', 'ServerManager' },
        options = {
            { title = 'Add Points',    icon = 'fa-solid fa-plus',  event = 'Vikto:Admin:AddTruckPoints',    permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
            { title = 'Remove Points', icon = 'fa-solid fa-minus', event = 'Vikto:Admin:RemoveTruckPoints', permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
            { title = 'Check Points',  icon = 'fa-solid fa-eye',   event = 'Vikto:Admin:CheckTruckPoints',  permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
        }
    },
    {
        title = 'Scripts Points',
        icon = 'fa-solid fa-coins',
        permission = { 'FullPermissions', 'Founders', 'ServerManager' },
        options = {
            { title = 'Matchmaking System', icon = 'fa-solid fa-trophy', targetMenu = 'category_matchmaking_system', permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
            { title = 'Truck System',       icon = 'fa-solid fa-truck',  targetMenu = 'category_truck_system',       permission = { 'FullPermissions', 'Founders', 'ServerManager' } },
        }
    },
    {
        title = 'Event System',
        icon = 'fa-solid fa-star',
        hidden = true,
        permission = { 'FullPermissions', 'Founders', 'ServerManager', 'EventTeam', 'EventsManager' },
        options = {
            { title = 'Add Points',         icon = 'fa-solid fa-plus',             event = 'Vikto:Admin:AddPoints',        permission = { 'FullPermissions', 'Founders', 'ServerManager', 'EventTeam', 'EventsManager' } },
            { title = 'Remove Points',      icon = 'fa-solid fa-minus',            event = 'Vikto:Admin:RemovePoints',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'EventTeam', 'EventsManager' } },
            { title = 'Remove All Points',  icon = 'fa-solid fa-trash-can',        event = 'Vikto:Admin:RemoveAllPoints',  permission = { 'FullPermissions', 'Founders', 'ServerManager', 'EventTeam', 'EventsManager' } },
            { title = 'View Player Points', icon = 'fa-solid fa-magnifying-glass', event = 'Vikto:Admin:ViewPlayerPoints', permission = { 'FullPermissions', 'Founders', 'ServerManager', 'EventTeam', 'EventsManager' } },
            { title = 'Send Event LB',      icon = 'fa-solid fa-paper-plane',      event = 'Vikto:Admin:SendEventLB',      permission = { 'FullPermissions', 'Founders', 'ServerManager', 'EventTeam', 'EventsManager' } },
            { title = 'Update Event LB',    icon = 'fa-solid fa-rotate',           event = 'Vikto:Admin:UpdateEventLB',    permission = { 'FullPermissions', 'Founders', 'ServerManager', 'EventTeam', 'EventsManager' } },
        }
    },
    {
        title = 'CID Management',
        icon = 'fa-solid fa-id-card',
        permission = { 'FullPermissions' },
        options = {
            { title = 'Change CID', icon = 'fa-solid fa-id-card-clip',     event = 'Vikto:Admin:ChangeCIDMenu', permission = { 'FullPermissions' } },
            { title = 'Check CID',  icon = 'fa-solid fa-magnifying-glass', event = 'Vikto:Admin:CheckCIDMenu',  permission = { 'FullPermissions' } },
            { title = 'Reset CID',  icon = 'fa-solid fa-sync',             event = 'Vikto:Admin:ResetCIDMenu',  permission = { 'FullPermissions' } },
            { title = 'Delete CID', icon = 'fa-solid fa-trash-can',        event = 'Vikto:Admin:DeleteCIDMenu', permission = { 'FullPermissions' } },
        }
    },
    {
        title = 'Developer Options',
        icon = 'fa-solid fa-laptop-code',
        permission = Managers,
        options = {
            { title = 'Copy Vector2',        icon = 'fa-solid fa-location-dot',        event = 'Vikto:Admin:CopyVector2',       permission = Managers },
            { title = 'Copy Vector3',        icon = 'fa-solid fa-location-crosshairs', event = 'Vikto:Admin:CopyVector3',       permission = Managers },
            { title = 'Copy Vector4',        icon = 'fa-solid fa-map-pin',             event = 'Vikto:Admin:CopyVector4',       permission = Managers },
            { title = 'Copy Heading',        icon = 'fa-solid fa-compass',             event = 'Vikto:Admin:CopyHeading',       permission = Managers },
            { title = 'Delete All Vehicles', icon = 'fa-solid fa-dumpster-fire',       event = 'Vikto:Admin:DeleteAllVehicles', permission = Managers },
            { title = 'Delete All Props',    icon = 'fa-solid fa-boxes-stacked',       event = 'Vikto:Admin:DeleteAllProps',    permission = Managers },
            { title = 'Delete All Peds',     icon = 'fa-solid fa-users-slash',         event = 'Vikto:Admin:DeleteAllPeds',     permission = Managers },
        }
    }
}

--------------------------------------------------------------------------------
-- PLAYTIME TRACKING
--------------------------------------------------------------------------------
Config.PlaytimeTracking = {
    Enabled = true,
    Interval = 5,
    AddAmount = 5,
    AllowedRoles = AllStaffAndTeams,
}

Config.txAdminPath = "../../../txData/default/data/playersDB.json"

--------------------------------------------------------------------------------
-- COMMAND PERMISSIONS
--------------------------------------------------------------------------------
Config.CommandPermission = {
    { Command = 'np',      description = 'Toggle flying mode',                event = 'Vikto:Admin:ToggleNoClip',         permission = AllStaffAndTeams },
    { Command = 'tp',      description = 'Enter Player ID To Go To',          event = 'Vikto:Admin:GoToPlayer',           permission = AllStaffAndTeams },
    { Command = 'br',      description = 'Enter Player ID To Bring To You',   event = 'Vikto:Admin:BringPlayer',          permission = Managers },
    { Command = 'sp',      description = 'Teleport Player To Spawn',          event = 'Vikto:Admin:GoToSpawn',            permission = AllStaffAndTeams },
    { Command = 'jail',    description = 'Select a Player To Jail',           event = 'Vikto:Admin:JailPlayer',           permission = AllStaffAndTeams },
    { Command = 'unjail',  description = 'Select a Player To Unjail',         event = 'Vikto:Admin:UnJailPlayer',         permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Unjail' } },
    { Command = 'rr',      description = 'Select The Radius To Revive',       event = 'Vikto:Admin:ReviveRadius',         permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ReviveRadius' } },
    { Command = 'tpm',     description = 'Teleport Player To Waypoint',       event = 'Vikto:Admin:TeleportTPM',          permission = Managers },
    { Command = 'ba',      description = 'Bring Multiple Players',            event = 'Vikto:Admin:BringMultiple',        permission = Managers },
    { Command = 'car',     description = 'Spawn Vehicle',                     event = 'vikto_admin:client:spawnVehicle',  permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Vehicles' } },
    { Command = 'dv',      description = 'Delete Vehicle',                    event = 'vikto_admin:client:deleteVehicle', permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Vehicles' } },
    { Command = 'live',    description = 'Toggle Streamer Mode (No Reports)', event = 'Vikto:Admin:ToggleStreamerMode',   permission = AllStaffAndTeams },
    { Command = 'stream',  description = 'Toggle Streamer Mode (No Reports)', event = 'Vikto:Admin:ToggleStreamerMode',   permission = AllStaffAndTeams },
    { Command = 'fix',     description = 'Fix Vehicle',                       event = 'vikto_admin:client:fixVehicle',    permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Vehicles' } },
    { Command = 'reportr', description = 'Message Player by ID',              event = 'Vikto:Admin:MessageID',            permission = AllStaffAndTeams },
    { Command = 'cmute',   description = 'Mute a Player from Chat',           event = 'Vikto:Admin:MuteChat',             permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteChat' } },
    { Command = 'cunmute', description = 'Unmute a Player from Chat',         event = 'Vikto:Admin:UnmuteChat',           permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteChat' } },
    { Command = 'clear',   description = 'Clear Chat for Everyone',           event = 'vikto_admin:client:clearChat',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam' } },
}

Config.TeleportLocations = {
    { name = 'Legion Square',    coords = vector4(195.17, -933.77, 29.7, 144.5),              icon = 'fa-solid fa-building' },
    { name = 'LSPD',             coords = vector4(428.23, -984.28, 29.76, 3.5),               icon = 'fa-solid fa-shield-halved' },
    { name = 'Pillbox Hospital', coords = vector4(298.68, -584.5, 43.26, 252.44),             icon = 'fa-solid fa-hospital' },
    { name = 'Sandy Shores',     coords = vector4(1845.3231, 3668.0938, 33.7092, 138.2266),   icon = 'fa-solid fa-location-dot' },
    { name = 'Paleto Bay',       coords = vector4(-248.49, 6331.37, 32.43, 223.5),            icon = 'fa-solid fa-location-dot' },
    { name = 'Airport',          coords = vector4(-1037.45, -2737.73, 13.76, 329.5),          icon = 'fa-solid fa-plane' },
    { name = 'Maze Bank',        coords = vector4(-75.49, -818.94, 326.17, 205.5),            icon = 'fa-solid fa-building-columns' },
    { name = 'Beach',            coords = vector4(-1549.5114, -1008.7431, 13.0177, 133.6327), icon = 'fa-solid fa-umbrella-beach' }
}

--------------------------------------------------------------------------------
-- JAIL CONFIGURATION
--------------------------------------------------------------------------------
Config.JailOptions = {
    JailCoords = vector3(1643.1982, 2570.9966, 45.5649),
    JailRadius = 30,
    UnJailCoords = vector3(3078.8564, -883.8779, 1913.4249),
    MaxJailTime = 120, -- Maximum jail time allowed
    DefaultJailTime = 15,
    DisabledControls = { 71, 72, 75, 24, 25, 37, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264, 289, 170, 249, 99, 100, 241, 242, 348, 349, 22, 23, 245, 246 },
}

Config.BanDurations = {
    { value = 1,   label = '1 Hour' },
    { value = 2,   label = '2 Hour' },
    { value = 3,   label = '3 Hours' },
    { value = 4,   label = '4 Hours' },
    { value = 5,   label = '5 Hours' },
    { value = 6,   label = '6 Hours' },
    { value = 8,   label = '8 Hours' },
    { value = 12,  label = '12 Hours' },
    { value = 24,  label = '1 Day' },
    { value = 48,  label = '2 Days' },
    { value = 72,  label = '3 Days' },
    { value = 120, label = '5 Days' },
    { value = 168, label = '1 Week' },
    { value = 336, label = '2 Weeks' },
    { value = 720, label = '1 Month' },
    { value = 0,   label = 'Permanent' }
}

Config.VoiceMute = {
    DefaultDuration = 5,
    MaxDuration = 9999999999999999999,
    MinDuration = 1,
}

Config.ReviveRadiusOptions = {
    { value = 5,   label = '5 meters' },
    { value = 10,  label = '10 meters' },
    { value = 15,  label = '15 meters' },
    { value = 20,  label = '20 meters' },
    { value = 30,  label = '30 meters' },
    { value = 50,  label = '50 meters' },
    { value = 100, label = '100 meters' },
    { value = 150, label = '150 meters' },
    { value = 200, label = '200 meters' },
}

--------------------------------------------------------------------------------
-- REPORT & TICKET SYSTEM
--------------------------------------------------------------------------------
Config.AdminReport = {
    AllowedRoles = AllStaffAndTeams, -- All listed teams/roles can accept tickets
    AllowSelfAccept = false,
    Cooldown = { Enabled = true, Time = 60 },
    AutoHide = { Enabled = true, Time = 60 },
    ReportsSystem = { Enabled = true, ReportsPerAccept = 1, NotifyAdmin = true },
    ReportEffect = { asset = 'core', name = 'ent_dst_elec_fire_sp', offset = vector3(0.5, 0.0, 0.0), rotation = vector3(0.0, 0.0, 20.0), scale = 1.75 },
    AcceptKey = 166,
    RejectKey = 167,
    Messages = {
        reportSent = 'Your report has been sent to the admins.',
        noMessage = 'You must enter a message for the report.',
        mustPressF5 = 'You must press F5 to accept the report.',
        mustPressF6 = 'You must press F6 to reject the report.'
    }
}

--------------------------------------------------------------------------------
-- PLAYER MODAL ACTIONS
--------------------------------------------------------------------------------
Config.PlayerModalActions = {
    {
        category = "Quick Actions",
        permission = AllStaffAndTeams,
        buttons = {
            { title = 'Go To Player', icon = 'fa-solid fa-paper-plane',  event = 'Vikto:Admin:GoToPlayer',                   permission = AllStaffAndTeams, disableOffline = true },
            { title = 'Bring Player', icon = 'fa-solid fa-magnet',       event = 'Vikto:Admin:BringPlayer',                  permission = Managers, disableOffline = true },
            { title = 'Revive',       icon = 'fa-solid fa-medkit',       event = 'Vikto:Admin:ReviveSelf',                   permission = Managers, disableOffline = true },
            { title = 'DM',           icon = 'fa-solid fa-comment-dots', event = 'Vikto:Admin:MessagePlayer',                permission = { 'FullPermissions', 'Founders', 'ServerManager', 'DirectMessage' }, disableOffline = true },
            { title = 'Go To Spawn',  icon = 'fa-solid fa-house-user',   event = 'vikto_admin:server:teleportPlayerToSpawn', permission = AllStaffAndTeams, disableOffline = true },
        }
    },
    {
        category = "Moderation",
        permission = AllStaffAndTeams,
        buttons = {
            { title = 'Kill Player',   icon = 'fa-solid fa-skull-crossbones',     event = 'Vikto:Admin:KillPlayer',   permission = Managers, disableOffline = true },
            { title = 'Mute Voice',    icon = 'fa-solid fa-microphone-slash',     event = 'Vikto:Admin:MutePlayer',   permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteVoice' } },
            { title = 'Mute Chat',     icon = 'fa-solid fa-comment-slash',        event = 'Vikto:Admin:MuteChat',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'CensorTeam', 'MuteChat' } },
            { title = 'Freeze Player', icon = 'fa-solid fa-snowflake',            event = 'Vikto:Admin:FreezePlayer', permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Freeze' }, disableOffline = true },
            { title = 'Warn Player',   icon = 'fa-solid fa-triangle-exclamation', event = 'Vikto:Admin:WarnPlayer',   permission = Managers },
            { title = 'Spectate',      icon = 'fa-solid fa-binoculars',           event = 'Vikto:Admin:Spectate',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'Spectate' }, disableOffline = true },
            { title = 'Check Radio',   icon = 'fa-solid fa-walkie-talkie',        event = 'Vikto:Admin:CheckRadio',   permission = AllStaffAndTeams, disableOffline = true },
        }
    },
    {
        category = "Punishment",
        permission = AllStaffAndTeams,
        buttons = {
            { title = 'Kick Player',     icon = 'fa-solid fa-door-open',      event = 'Vikto:Admin:KickPlayer',    permission = Managers, disableOffline = true },
            { title = 'Ban Player',      icon = 'fa-solid fa-gavel',          event = 'Vikto:Admin:BanPlayer',     permission = { 'FullPermissions', 'Founders', 'ServerManager', 'ServerAssManager', 'HighManager', 'HighAssManager', 'GeneralManager', 'GeneralAssManager', 'BanTeam' } },
            { title = 'Jail Player',     icon = 'fa-solid fa-dungeon',        event = 'Vikto:Admin:JailPlayer',    permission = AllStaffAndTeams },
            { title = 'Check Jail Time', icon = 'fa-solid fa-hourglass-half', event = 'Vikto:Admin:CheckJailTime', permission = AllStaffAndTeams, showIfJailed = true },
        }
    },
    {
        category = "Utilities",
        permission = { 'FullPermissions', 'Founders', 'ServerManager' },
        buttons = {
            { title = 'Give Item', icon = 'fa-solid fa-box-open', event = 'Vikto:Admin:GiveItem', permission = { 'FullPermissions', 'Founders', 'ServerManager' }, disableOffline = true },
        }
    }
}