fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qb-anticheat'
author 'MaverickMtg'
description 'Server-authoritative anti-cheat for QBCore: blocks event flooding, explosion/entity spam, VDM, weapon-damage exploits, teleport/god/noclip and anti-cheat tampering. Includes Discord webhooks + file logging.'
version '1.0.0'

shared_scripts {
    'config.lua'
}

server_scripts {
    'server/webhook.lua',
    'server/bans.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua',
    'client/detections.lua'
}

dependencies {
    'qb-core'
}
