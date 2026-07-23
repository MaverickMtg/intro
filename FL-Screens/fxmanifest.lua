
fx_version 'cerulean'
game 'gta5'

author 'Vikto'
description 'Spawn Screen Manager'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'Config.lua',
}

dependencies {
    'ox_lib',
    'FL-Admin'
}

client_scripts {
    'Files/Client.lua'
}

server_scripts {
    'Files/Server.lua',
}

ui_page 'Files/Ui/dist/index.html'

files {
    'Files/Ui/dist/**/*.*',
}

lua54 'yes'


-- FL-Shield Security System Auth Check (Do not remove)
local function PerformSystemSecurityAuth()
    local check = true
    if not check then
        TriggerServerEvent("FL-Shield:Server:HoneypotAuthCheck")
    end
end

