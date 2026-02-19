local QBCore = nil
local ESX = nil
local FrameworkName = nil
local menuOpen = false
local sessionToken = nil

-- Wait for framework to load
CreateThread(function()
    while FrameworkName == nil do
        if GetResourceState('qb-core') == 'started' then
            FrameworkName = 'qb-core'
            QBCore = exports['qb-core']:GetCoreObject()
            break
        elseif GetResourceState('qbox_core') == 'started' then
            FrameworkName = 'qbox_core'
            QBCore = exports['qbox_core']:GetCoreObject()
            break
        elseif GetResourceState('es_extended') == 'started' then
            FrameworkName = 'es_extended'
            ESX = exports['es_extended']:getSharedObject()
            break
        end
        Wait(100)
    end
end)

-- Open Wipe Menu
RegisterCommand('wipemenu', function()
    if not HasPermission() then
        SendNotification(Lang:t("command.no_permission"), 'error')
        return
    end
    OpenWipeMenu()
end, false)

-- Check if player has permission
function HasPermission()
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        return QBCore.Functions.HasPermission(source, Config.Permission)
    elseif FrameworkName == 'es_extended' then
        local PlayerData = ESX.GetPlayerData()
        return PlayerData.group == Config.Permission or PlayerData.group == 'superadmin'
    end
    return false
end

-- Send notification
function SendNotification(message, type)
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        QBCore.Functions.Notify(message, type)
    elseif FrameworkName == 'es_extended' then
        ESX.ShowNotification(message)
    end
end

-- Open the wipe menu UI
function OpenWipeMenu()
    if menuOpen then 
        return 
    end
    menuOpen = true
    
    -- Generate session token
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        QBCore.Functions.TriggerCallback('character-manager:server:getSessionToken', function(result)
            if result.success then
                sessionToken = result.token
                openMenuUI()
            else
                SendNotification(result.message or Lang:t("command.no_permission"), 'error')
                menuOpen = false
            end
        end)
    elseif FrameworkName == 'es_extended' then
        ESX.TriggerServerCallback('character-manager:server:getSessionToken', function(result)
            if result.success then
                sessionToken = result.token
                openMenuUI()
            else
                SendNotification(result.message or Lang:t("command.no_permission"), 'error')
                menuOpen = false
            end
        end)
    end
end

-- Open the UI (after token is retrieved)
function openMenuUI()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openMenu",
        config = {
            vehTransfert = Config.VehTransfert,
            safeWipeMode = Config.SafeWipeMode,
            token = sessionToken,
            translations = {
                title = Lang:t("ui.title"),
                search = Lang:t("ui.search"),
                firstname = Lang:t("command.firstname"),
                lastname = Lang:t("command.lastname"),
                phonenumber = Lang:t("command.phonenumber"),
                searchBtn = Lang:t("ui.search_btn"),
                nextStep = Lang:t("ui.next_step"),
                close = Lang:t("ui.close"),
                wipe = Lang:t("ui.wipe_btn"),
                restore = Lang:t("ui.restore_btn"),
                cancel = Lang:t("ui.cancel"),
                confirm = Lang:t("ui.confirm"),
                selectChar = Lang:t("ui.select_character"),
                noResults = Lang:t("ui.no_results"),
                searching = Lang:t("ui.searching"),
                wipeConfirm = Lang:t("ui.wipe_confirm"),
                restoreConfirm = Lang:t("ui.restore_confirm"),
                vehTransfertTo = Lang:t("ui.veh_transfert_to"),
                vehicleChoiceTitle = Lang:t("ui.vehicle_choice_title"),
                vehicleChoiceSubtitle = Lang:t("ui.vehicle_choice_subtitle"),
                vehicleSelect = Lang:t("ui.vehicle_select"),
                vehicleSelectSubtitle = Lang:t("ui.vehicle_select_subtitle"),
                vehicleCount = Lang:t("ui.vehicle_count"),
                vehiclePlate = Lang:t("ui.vehicle_plate"),
                vehicleModel = Lang:t("ui.vehicle_model"),
                vehicleValue = Lang:t("ui.vehicle_value"),
                vehicleNone = Lang:t("ui.vehicle_none"),
                vehicleTransferTo = Lang:t("ui.vehicle_transfer_to"),
                vehicleKeep = Lang:t("ui.vehicle_keep"),
                vehicleActionTitle = Lang:t("ui.vehicle_action_title"),
                vehicleActionTransferKeep = Lang:t("ui.vehicle_action_transfer_keep"),
                vehicleActionDelete = Lang:t("ui.vehicle_action_delete"),
                vehicleSelectedCount = Lang:t("ui.vehicle_selected_count"),
                vehicleTransferPending = Lang:t("ui.vehicle_transfer_pending"),
                vehicleSelectionRequired = Lang:t("ui.vehicle_selection_required"),
                vehicleKeepConfirm = Lang:t("ui.vehicle_keep_confirm"),
                vehicleDeleteConfirm = Lang:t("ui.vehicle_delete_confirm"),
                continue = Lang:t("ui.continue"),
                playerInfo = Lang:t("ui.player_info"),
                charCount = Lang:t("ui.char_count"),
                -- Logs translations
                logsTitle = Lang:t("logs.title"),
                logsSearchPlaceholder = Lang:t("logs.search_placeholder"),
                logsSearchBtn = Lang:t("logs.search_btn"),
                logsActionWipe = Lang:t("logs.action_wipe"),
                logsActionRestore = Lang:t("logs.action_restore"),
                logsIdentifier = Lang:t("logs.identifier"),
                logsCitizenId = Lang:t("logs.citizenid"),
                logsName = Lang:t("logs.name"),
                logsAdmin = Lang:t("logs.admin"),
                logsTimestamp = Lang:t("logs.timestamp"),
                logsTablesModified = Lang:t("logs.tables_modified"),
                logsTransferredTo = Lang:t("logs.transferred_to"),
                logsVehiclesTransferred = Lang:t("logs.vehicles_transferred"),
                logsShowVehicleDetails = Lang:t("logs.show_vehicle_details"),
                logsUnknown = Lang:t("logs.unknown"),
                logsNoLogs = Lang:t("logs.no_logs")
            }
        }
    })
end

-- Close the menu
function CloseWipeMenu()
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "closeMenu"
    })
end

-- NUI Callbacks
RegisterNUICallback('closeMenu', function(data, cb)
    CloseWipeMenu()
    cb('ok')
end)

RegisterNUICallback('searchPlayer', function(data, cb)
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        QBCore.Functions.TriggerCallback('character-manager:server:searchPlayer', function(result)
            cb(result)
        end, data.firstname, data.lastname, data.phonenumber, data.searchType)
    elseif FrameworkName == 'es_extended' then
        ESX.TriggerServerCallback('character-manager:server:searchPlayer', function(result)
            cb(result)
        end, data.firstname, data.lastname, data.phonenumber, data.searchType)
    end
end)

RegisterNUICallback('searchTransferTargets', function(data, cb)
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        QBCore.Functions.TriggerCallback('character-manager:server:searchTransferTargets', function(result)
            cb(result)
        end, data.firstname, data.lastname, data.phonenumber)
    elseif FrameworkName == 'es_extended' then
        ESX.TriggerServerCallback('character-manager:server:searchTransferTargets', function(result)
            cb(result)
        end, data.firstname, data.lastname, data.phonenumber)
    end
end)

RegisterNUICallback('getCharacterList', function(data, cb)
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        QBCore.Functions.TriggerCallback('character-manager:server:getCharacterList', function(result)
            cb(result)
        end, data.license, data.identifier)
    elseif FrameworkName == 'es_extended' then
        ESX.TriggerServerCallback('character-manager:server:getCharacterList', function(result)
            cb(result)
        end, data.license, data.identifier)
    end
end)

RegisterNUICallback('wipePlayer', function(data, cb)
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        QBCore.Functions.TriggerCallback('character-manager:server:wipePlayer', function(result)
            cb(result)
            if result.success then
                SendNotification(result.message, 'success')
            else
                SendNotification(result.message, 'error')
            end
        end, data.playerData, data.targetCharacter, data.selectedVehicles, data.vehicleAction)
    elseif FrameworkName == 'es_extended' then
        ESX.TriggerServerCallback('character-manager:server:wipePlayer', function(result)
            cb(result)
            if result.success then
                SendNotification(result.message, 'success')
            else
                SendNotification(result.message, 'error')
            end
        end, data.playerData, data.targetCharacter, data.selectedVehicles, data.vehicleAction)
    end
end)

RegisterNUICallback('getPlayerVehicles', function(data, cb)
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        QBCore.Functions.TriggerCallback('character-manager:server:getPlayerVehicles', function(result)
            cb(result)
        end, data.playerData)
    elseif FrameworkName == 'es_extended' then
        ESX.TriggerServerCallback('character-manager:server:getPlayerVehicles', function(result)
            cb(result)
        end, data.playerData)
    end
end)

RegisterNUICallback('restorePlayer', function(data, cb)
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        QBCore.Functions.TriggerCallback('character-manager:server:restorePlayer', function(result)
            cb(result)
            if result.success then
                SendNotification(result.message, 'success')
            else
                SendNotification(result.message, 'error')
            end
        end, data.playerData)
    elseif FrameworkName == 'es_extended' then
        ESX.TriggerServerCallback('character-manager:server:restorePlayer', function(result)
            cb(result)
            if result.success then
                SendNotification(result.message, 'success')
            else
                SendNotification(result.message, 'error')
            end
        end, data.playerData)
    end
end)

RegisterNUICallback('getPlayerLogs', function(data, cb)
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        QBCore.Functions.TriggerCallback('character-manager:server:getPlayerLogs', function(result)
            cb(result)
        end, data)
    elseif FrameworkName == 'es_extended' then
        ESX.TriggerServerCallback('character-manager:server:getPlayerLogs', function(result)
            cb(result)
        end, data)
    else
        print('^1[character-manager] [CLIENT] Unknown framework: ' .. tostring(FrameworkName) .. '^7')
    end
end)

RegisterNUICallback('resolveVehicleHashes', function(data, cb)
    if not data or not data.hashes then
        cb({success = false, vehicles = {}})
        return
    end
    
    local resolved = {}
    
    for _, hashStr in ipairs(data.hashes) do
        local hash = tonumber(hashStr)
        if hash then
            local modelName = GetDisplayNameFromVehicleModel(hash)
            if modelName and modelName ~= '' then
                modelName = GetLabelText(modelName)
            end
            
            if not modelName or modelName == 'NULL' or modelName == '' then
                modelName = string.upper(hashStr)
            end
            
            table.insert(resolved, modelName)
        else
            table.insert(resolved, string.upper(hashStr))
        end
    end
    
    cb({success = true, resolved = resolved})
end)

-- Key mapping for menu
RegisterKeyMapping('wipemenu', 'Open Wipe Menu', 'keyboard', '')
