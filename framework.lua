FrameworkName = nil
ESX = nil
QBCore = nil

-- Thanks to optional_dependencies, frameworks are already started if present
-- No need to wait or loop, we can detect directly
if GetResourceState('es_extended') == 'started' then
    FrameworkName = 'es_extended'
    ESX = exports['es_extended']:getSharedObject()
    print('[character-manager] Using es_extended')
elseif GetResourceState('qb-core') == 'started' then
    FrameworkName = 'qb-core'
    QBCore = exports['qb-core']:GetCoreObject()
    print('[character-manager] Using qb-core')
elseif GetResourceState('qbox_core') == 'started' then
    FrameworkName = 'qbox_core'
    QBCore = exports['qbox_core']:GetCoreObject()
    print('[character-manager] Using qbox_core')
else
    print('^1[character-manager] No framework detected. Please install es_extended, qb-core or qbox_core.^7')
end
