
fx_version 'cerulean'
game 'gta5'

author 'Vikto'
description 'Admin System By Vikto'
version '1.0.0'

escrow_ignore {
    'Config.lua',
    'ConfigS.lua',
}

shared_scripts {
    '@ox_lib/init.lua',
    'Config.lua',
}

client_scripts {
    'Files/Client.lua',
    'Config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'ConfigS.lua',
    'Files/Server.lua',
}

ui_page 'Files/Ui/index.html'

files {
    'Files/Ui/index.html',
    'Files/Ui/assets/*.*',
    'Files/Ui/sounds/*.*',
    'Files/Ui/avatar.png',
    'Config.js',
}

lua54 'yes'


