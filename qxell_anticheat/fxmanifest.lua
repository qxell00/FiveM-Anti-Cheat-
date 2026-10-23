fx_version 'cerulean'
game 'gta5'

name        'qxell AntiCheat'
description 'Advanced FiveM Anti-Cheat System'
version     '6.3.8'
author      'qxell'

-- Shared files (loaded first on both sides)
shared_scripts {
    'shared/utils.lua',
    'config.lua',
}

-- Server-side scripts
server_scripts {
    '@oxmysql/lib/MySQL.lua',       -- Remove if not using oxmysql
    'server/webhook.lua',
    'server/ban_system.lua',
    'server/detections.lua',
    'server/main.lua',
    'server/menu.lua',
}

-- Client-side scripts
client_scripts {
    'client/bypass.lua',
    'client/combat.lua',
    'client/main.lua',
    'client/menu.lua',
}

-- NUI files
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'oxmysql',   -- Remove if not using oxmysql
}

lua54 'yes'
