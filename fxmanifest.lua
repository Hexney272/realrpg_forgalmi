fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'realrpg_forgalmi'
author 'ChatGPT'
description 'Forgalmi engedély + műszaki vizsga rendszer ESX Legacy / ox_inventory / ox_target szerverekhez'
version '3.0.0'

ui_page 'html/index.html'

shared_scripts {
    '@es_extended/imports.lua',
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_inventory',
    'ox_target'
}
