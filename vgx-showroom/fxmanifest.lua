server_script '@ElectronAC/src/include/server.lua'
client_script '@ElectronAC/src/include/client.lua'
fx_version 'cerulean'
game 'gta5'

author      'VGX Development'
description 'VGX Showrooms - QBCore (multi-showroom, created in-game via /showrooms)'
version     '4.0.0'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/css/style.css',
    'ui/js/app.js',
}

lua54 'yes'
dependency 'qb-core'
dependency 'oxmysql'

