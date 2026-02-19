fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'character-manager'
version '1.0.0'
author 'Alex Garcio'

shared_scripts {
	'locale.lua',
	'config.lua',
	'locales/*.lua'
}

client_scripts {
	'client.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'framework.lua',
	'database.lua',
    'update.lua',
    'server.lua',
}

ui_page 'html/index.html'

files {
	'html/index.html',
	'html/style.css',
	'html/script.js',
}

dependencies {
	'oxmysql',
}

-- At least one of these frameworks must be installed
optional_dependencies {
    'es_extended',
    'qb-core',
    'qbox_core',
}
