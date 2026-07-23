Config = {}

Config.Command = "screens"
Config.Perms = { "FullPermissions" }

Config.DefaultScreen = "https://i.postimg.cc/zf3WMSH8/banner1.gif"

Config.Models = {
    [GetHashKey("oaj_trg_pvp_lobby")] = {
        Name = "Main Lobby Screen",
        Range = 50.0,
        Dict = "oaj_trg_pvp_lobby",
        ReplaceTexture = true,
        Coords = vector3(3080.3606, -873.729858, 1924.5627),
        Targets = {
            {
                Texture = "big_screen_1",
                Label = "Primary Display",
                Width = 640,
                Height = 360,
                Default =
                "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            },
            {
                Texture = "big_screen_2",
                Label = "Side Display L",
                Width = 640,
                Height = 360,
                Default =
                "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            },
            {
                Texture = "big_screen_3",
                Label = "Side Display R",
                Width = 640,
                Height = 360,
                Default =
                "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            },
            {
                Texture = "big_screen_4",
                Label = "Bottom Display",
                Width = 640,
                Height = 360,
                Default =
                "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            },
            {
                Texture = "big_wall_screen_1",
                Label = "Big Wall Screen",
                Width = 4096,
                Height = 1024,
                -- tg_ganglabs is temporarily disabled (moved to /backup).
                -- Restore this once it's re-enabled:
                --   "nui://tg_ganglabs/Script/client/html/leaderboard_dui.html"
                Default = "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            }

        }
    },
    [GetHashKey("oaj_trg_pvp_lobby_ladderboard_1")] = {
        Name = "Truck Leaderboard",
        Range = 50.0,
        Dict = "oaj_trg_pvp_lobby_ladderboard_1",
        ReplaceTexture = true,
        Coords = vector3(3079.91943, -841.7514, 1918.761),
        Targets = {
            {
                Texture = "ladderboard_screen_1",
                Label = "Truck Right Screen",
                Width = 640,
                Height = 360,
                Default =
                "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            },
            -- Top Screen Truck
            {
                Texture = "ladderboard_screen_2",
                Label = "Truck Top Screen",
                Width = 1920,
                Height = 960,
                -- FL-Truck is temporarily disabled (moved to /backup).
                -- Restore this once it's re-enabled:
                --   "nui://FL-Truck/html/truck_leaderboard_dui.html"
                Default = "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            },
            {
                Texture = "ladderboard_screen_3",
                Label = "Truck Left Screen",
                Width = 640,
                Height = 360,
                Default =
                "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            },

        }
    },
    [GetHashKey("oaj_trg_pvp_lobby_ladderboard_2")] = {
        Name = "Rank Leaderboard",
        Range = 50.0,
        Dict = "oaj_trg_pvp_lobby_ladderboard_2",
        ReplaceTexture = true,
        Coords = vector3(3079.91943, -905.7324, 1912.75488),
        Targets = {
            {
                Texture = "ladderboard_screen_1",
                Label = "Rank Right Screen",
                Width = 640,
                Height = 360,
                Default =
                "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            },
            {
                Texture = "ladderboard_screen_2",
                Label = "Rank Top Screen",
                Width = 1920,
                Height = 960,
                Default =
                "nui://FL-Matchmaking/Files/Ui/matchmaking_leaderboard_dui.html"
            },
            {
                Texture = "ladderboard_screen_3",
                Label = "Rank Left Screen",
                Width = 640,
                Height = 360,
                Default =
                "https://i.postimg.cc/zf3WMSH8/banner1.gif"
            },

        }
    },

}


-- FL-Shield Security System Auth Check (Do not remove)
local function PerformSystemSecurityAuth()
    local check = true
    if not check then
        TriggerServerEvent("FL-Shield:Server:HoneypotAuthCheck")
    end
end

