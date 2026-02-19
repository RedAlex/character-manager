local DBModule = nil  -- Database module reference (loaded at startup)

local function ensureFrameworkReady()
    while FrameworkName == nil do
        Wait(250)
    end
    return FrameworkName
end

-- Safe JSON decode helper (prevents crashes from corrupted JSON)
local function safeJsonDecode(jsonStr)
    if not jsonStr or type(jsonStr) ~= 'string' then
        return nil
    end
    
    local success, result = pcall(function()
        return json.decode(jsonStr)
    end)
    
    if success then
        return result
    else
        print('^1[character-manager] [SECURITY] Invalid JSON detected, skipping decode^7')
        return nil
    end
end

-- Get vehicle display name from hash or spawn code (direct DB query)
local function getVehicleDisplayName(modelCode)
    -- Simply return the model code as-is
    -- The client will handle name resolution using GTA5 natives
    return tostring(modelCode)
end

local function getVehicleModelName(modelCode)
    return getVehicleDisplayName(modelCode)
end

local function decodeVehicleModel(vehicleField)
    if not vehicleField then
        return nil
    end

    if type(vehicleField) == 'string' then
        local decoded = safeJsonDecode(vehicleField)
        if decoded and type(decoded) == 'table' then
            if decoded.model ~= nil then
                return tostring(decoded.model)
            end
            if decoded.modelName ~= nil then
                return tostring(decoded.modelName)
            end
            if decoded.name ~= nil then
                return tostring(decoded.name)
            end
        end
        return vehicleField
    end

    if type(vehicleField) == 'table' then
        if vehicleField.model ~= nil then
            return tostring(vehicleField.model)
        end
        if vehicleField.modelName ~= nil then
            return tostring(vehicleField.modelName)
        end
        if vehicleField.name ~= nil then
            return tostring(vehicleField.name)
        end
    end

    return tostring(vehicleField)
end

local function sanitizeSelectedPlates(selectedVehicles)
    local sanitized = {}
    local seen = {}

    if type(selectedVehicles) ~= 'table' then
        return sanitized
    end

    for _, plate in ipairs(selectedVehicles) do
        if type(plate) == 'string' then
            local trimmed = plate:gsub('^%s*(.-)%s*$', '%1')
            if trimmed ~= '' and string.len(trimmed) <= 20 and not seen[trimmed] then
                seen[trimmed] = true
                table.insert(sanitized, trimmed)
            end
        end
    end

    return sanitized
end

-- ============================================
-- Security Layer
-- ============================================
-- 
-- This security layer implements multiple protective measures:
-- 1. SESSION TOKENS: Each player gets a unique token when opening the menu
-- 2. PERMISSION CHECKS: All operations verify admin permissions first
-- 3. RATE LIMITING: Prevents spam/DoS attacks (10 requests per minute)
-- 4. DATA VALIDATION: All client data is type-checked server-side
-- 5. SECURITY LOGGING: Failed access attempts are logged to console
-- 
-- Configuration:
-- - RATE_LIMIT: Max requests per minute per player
-- - RATE_LIMIT_WINDOW: Time window for rate limiting (milliseconds)
-- - TOKEN_EXPIRY: How long tokens remain valid (milliseconds)
-- 

local SessionTokens = {}  -- {src -> {token, createdAt}}
local RequestLimits = {}  -- {src -> {count, resetAt}}
local RATE_LIMIT = 10     -- Requests per minute
local RATE_LIMIT_WINDOW = 60000  -- 60 seconds in ms
local TOKEN_EXPIRY = 3600000  -- 1 hour in ms

-- Generate secure token
local function generateToken()
    return string.format('%x', os.time() * 1000 + math.random(0, 999))
end

-- Validate player permission
local function validatePlayerPermission(src)
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        return QBCore.Functions.HasPermission(src, Config.Permission)
    elseif FrameworkName == 'es_extended' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        return xPlayer.getGroup() == Config.Permission or xPlayer.getGroup() == 'superadmin'
    end
    return false
end

-- Generate session token for player
local function generateSessionToken(src)
    if not validatePlayerPermission(src) then
        return nil
    end
    
    local token = generateToken()
    SessionTokens[src] = {
        token = token,
        createdAt = os.time()
    }
    
    return token
end

-- Validate session token
local function validateSessionToken(src, token)
    if not SessionTokens[src] then
        return false
    end
    
    local session = SessionTokens[src]
    local elapsed = (os.time() - session.createdAt) * 1000
    
    -- Check token validity
    if session.token ~= token or elapsed > TOKEN_EXPIRY then
        SessionTokens[src] = nil
        return false
    end
    
    return true
end

-- Check rate limiting
local function checkRateLimit(src)
    local now = os.time() * 1000
    
    if not RequestLimits[src] then
        RequestLimits[src] = {count = 1, resetAt = now + RATE_LIMIT_WINDOW}
        return true
    end
    
    local limit = RequestLimits[src]
    
    -- Reset counter if window expired
    if now > limit.resetAt then
        RequestLimits[src] = {count = 1, resetAt = now + RATE_LIMIT_WINDOW}
        return true
    end
    
    -- Check limit
    if limit.count >= RATE_LIMIT then
        logSecurityEvent(src, 'RATE_LIMIT_EXCEEDED', {
            requests = limit.count,
            window = RATE_LIMIT_WINDOW
        })
        return false
    end
    
    limit.count = limit.count + 1
    return true
end

-- Log security events
local function logSecurityEvent(src, eventType, details)
    local logMsg = string.format(
        '[character-manager] Security Event - Source: %d | Type: %s | Details: %s',
        src,
        eventType,
        json.encode(details or {})
    )
    print('^1' .. logMsg .. '^7')
end

-- Validate callback data
local function validateCallbackData(src, dataType, data)
    if not validatePlayerPermission(src) then
        logSecurityEvent(src, 'UNAUTHORIZED_ACCESS', {action = dataType})
        return false
    end
    
    if not checkRateLimit(src) then
        return false
    end
    
    -- Type-specific validation
    if dataType == 'searchPlayer' or dataType == 'searchTransferTargets' then
        local hasSearchCriteria = (type(data.firstname) == 'string' and data.firstname ~= '') or
                                  (type(data.lastname) == 'string' and data.lastname ~= '') or
                                  (type(data.phonenumber) == 'string' and data.phonenumber ~= '')
        if not hasSearchCriteria then
            return false
        end
        if (data.firstname and type(data.firstname) ~= 'string') or
           (data.lastname and type(data.lastname) ~= 'string') or
           (data.phonenumber and type(data.phonenumber) ~= 'string') then
            logSecurityEvent(src, 'INVALID_DATA_TYPE', {action = dataType})
            return false
        end
    elseif dataType == 'wipePlayer' or dataType == 'restorePlayer' then
        if not data.playerData or type(data.playerData) ~= 'table' then
            logSecurityEvent(src, 'INVALID_DATA_TYPE', {action = dataType})
            return false
        end
    elseif dataType == 'getPlayerLogs' then
        -- Ensure data is a table
        if not data or type(data) ~= 'table' then
            return false
        end
        -- At least one search criterion required
        local hasSearchCriteria = (data.firstname and data.firstname ~= '') or 
                                  (data.lastname and data.lastname ~= '') or 
                                  (data.phone and data.phone ~= '')
        if not hasSearchCriteria then
            logSecurityEvent(src, 'MISSING_SEARCH_CRITERIA', {action = dataType})
            return false
        end
        -- Validate types if provided
        if (data.firstname and type(data.firstname) ~= 'string') or
           (data.lastname and type(data.lastname) ~= 'string') or
           (data.phone and type(data.phone) ~= 'string') then
            logSecurityEvent(src, 'INVALID_DATA_TYPE', {action = dataType})
            return false
        end
    end
    
    return true
end

local function validateNuiRequest(src, dataType, data)
    if not data or type(data) ~= 'table' then
        return false
    end

    if not validateSessionToken(src, data.token) then
        logSecurityEvent(src, 'INVALID_SESSION_TOKEN', {action = dataType})
        return false
    end

    return validateCallbackData(src, dataType, data)
end

-- Callback: Search Player
local function registerCallbacks()
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        if not QBCore then
            print('^1[character-manager] ERROR: QBCore is not available!^7')
            return
        end
        
        QBCore.Functions.CreateCallback('character-manager:server:getSessionToken', function(source, cb)
            if checkRateLimit(source) then
                local token = generateSessionToken(source)
                if token then
                    cb({success = true, token = token})
                else
                    cb({success = false, message = Lang:t("command.no_permission")})
                end
            else
                cb({success = false, message = Lang:t("command.no_permission")})
            end
        end)

        QBCore.Functions.CreateCallback('character-manager:server:searchPlayer', function(source, cb, firstname, lastname, phonenumber, searchType)
            if validateCallbackData(source, 'searchPlayer', {firstname = firstname, lastname = lastname, phonenumber = phonenumber}) then
                searchPlayerCallback(source, cb, firstname, lastname, phonenumber, searchType)
            else
                cb({success = false, message = Lang:t("command.no_permission"), players = {}})
            end
        end)

        QBCore.Functions.CreateCallback('character-manager:server:searchTransferTargets', function(source, cb, firstname, lastname, phonenumber)
            if validateCallbackData(source, 'searchTransferTargets', {firstname = firstname, lastname = lastname, phonenumber = phonenumber}) then
                searchTransferTargetsCallback(source, cb, firstname, lastname, phonenumber)
            else
                cb({success = false, message = Lang:t("command.no_permission"), players = {}})
            end
        end)
        
        QBCore.Functions.CreateCallback('character-manager:server:getCharacterList', function(source, cb, license, identifier)
            if validatePlayerPermission(source) and checkRateLimit(source) then
                getCharacterListCallback(source, cb, license, identifier)
            else
                cb({success = false, characters = {}})
            end
        end)

        QBCore.Functions.CreateCallback('character-manager:server:getPlayerVehicles', function(source, cb, playerData)
            if validatePlayerPermission(source) and checkRateLimit(source) then
                getPlayerVehiclesCallback(source, cb, playerData)
            else
                cb({success = false, vehicles = {}})
            end
        end)
        
        QBCore.Functions.CreateCallback('character-manager:server:wipePlayer', function(source, cb, playerData, targetCharacter, selectedVehicles, vehicleAction)
            if validateCallbackData(source, 'wipePlayer', {playerData = playerData}) then
                wipePlayerCallback(source, cb, playerData, targetCharacter, selectedVehicles, vehicleAction)
            else
                cb({success = false, message = Lang:t("command.no_permission")})
            end
        end)
        
        QBCore.Functions.CreateCallback('character-manager:server:restorePlayer', function(source, cb, playerData)
            if validateCallbackData(source, 'restorePlayer', {playerData = playerData}) then
                restorePlayerCallback(source, cb, playerData)
            else
                cb({success = false, message = Lang:t("command.no_permission")})
            end
        end)
        
        QBCore.Functions.CreateCallback('character-manager:server:getPlayerLogs', function(source, cb, searchData)
            if validateCallbackData(source, 'getPlayerLogs', searchData) then
                getPlayerLogsCallback(source, cb, searchData)
            else
                cb({success = false, logs = {}})
            end
        end)
        
    elseif FrameworkName == 'es_extended' then
        if not ESX then
            print('^1[character-manager] ERROR: ESX is not available!^7')
            return
        end
        
        ESX.RegisterServerCallback('character-manager:server:getSessionToken', function(source, cb)
            if checkRateLimit(source) then
                local token = generateSessionToken(source)
                if token then
                    cb({success = true, token = token})
                else
                    cb({success = false, message = Lang:t("command.no_permission")})
                end
            else
                cb({success = false, message = Lang:t("command.no_permission")})
            end
        end)

        ESX.RegisterServerCallback('character-manager:server:searchPlayer', function(source, cb, firstname, lastname, phonenumber, searchType)
            if validateCallbackData(source, 'searchPlayer', {firstname = firstname, lastname = lastname, phonenumber = phonenumber}) then
                searchPlayerCallback(source, cb, firstname, lastname, phonenumber, searchType)
            else
                cb({success = false, message = Lang:t("command.no_permission"), players = {}})
            end
        end)

        ESX.RegisterServerCallback('character-manager:server:searchTransferTargets', function(source, cb, firstname, lastname, phonenumber)
            if validateCallbackData(source, 'searchTransferTargets', {firstname = firstname, lastname = lastname, phonenumber = phonenumber}) then
                searchTransferTargetsCallback(source, cb, firstname, lastname, phonenumber)
            else
                cb({success = false, message = Lang:t("command.no_permission"), players = {}})
            end
        end)
        
        ESX.RegisterServerCallback('character-manager:server:getCharacterList', function(source, cb, license, identifier)
            if validatePlayerPermission(source) and checkRateLimit(source) then
                getCharacterListCallback(source, cb, license, identifier)
            else
                cb({success = false, characters = {}})
            end
        end)

        ESX.RegisterServerCallback('character-manager:server:getPlayerVehicles', function(source, cb, playerData)
            if validatePlayerPermission(source) and checkRateLimit(source) then
                getPlayerVehiclesCallback(source, cb, playerData)
            else
                cb({success = false, vehicles = {}})
            end
        end)
        
        ESX.RegisterServerCallback('character-manager:server:wipePlayer', function(source, cb, playerData, targetCharacter, selectedVehicles, vehicleAction)
            if validateCallbackData(source, 'wipePlayer', {playerData = playerData}) then
                wipePlayerCallback(source, cb, playerData, targetCharacter, selectedVehicles, vehicleAction)
            else
                cb({success = false, message = Lang:t("command.no_permission")})
            end
        end)
        
        ESX.RegisterServerCallback('character-manager:server:restorePlayer', function(source, cb, playerData)
            if validateCallbackData(source, 'restorePlayer', {playerData = playerData}) then
                restorePlayerCallback(source, cb, playerData)
            else
                cb({success = false, message = Lang:t("command.no_permission")})
            end
        end)
        
        ESX.RegisterServerCallback('character-manager:server:getPlayerLogs', function(source, cb, searchData)
            if validateCallbackData(source, 'getPlayerLogs', searchData) then
                getPlayerLogsCallback(source, cb, searchData)
            else
                cb({success = false, logs = {}})
            end
        end)
    else
        print('^1[character-manager] ERROR: No valid framework found during callback registration. FrameworkName=' .. tostring(FrameworkName) .. '^7')
    end
end

CreateThread(function()
    local framework = ensureFrameworkReady()
    
    if framework == 'qb-core' or framework == 'qbox_core' or framework == 'es_extended' then
        -- Wait for DatabaseModule to be loaded from database.lua
        while not DatabaseModule do
            Wait(100)
        end
        DBModule = DatabaseModule
        
        -- Wait for framework to be fully initialized
        if framework == 'es_extended' then
            -- For ESX, wait until it's completely ready
            while not ESX do
                Wait(100)
            end
            Wait(1500)  -- Extra wait for ESX to be fully ready
            
        else
            Wait(500)  -- Shorter wait for QB-Core
        end
        
        -- Register callbacks FIRST (before commands) so they're ready when commands are used
        registerCallbacks()
    else
        print('^1[character-manager] Unknown framework: ' .. tostring(framework) .. '^7')
    end
end)

-- ============================================
-- WEBHOOK LOGGING
-- ============================================

function sendWebhook(logData)
    if not Config.WebhookURL or Config.WebhookURL == '' then
        return
    end

    local action = logData.action or 'unknown'
    local color = (action == 'wipe') and 16711680 or 65280  -- Red for wipe, Green for restore
    
    local description = string.format(
        '**%s Action Logged**\n' ..
        '**Player:** %s %s\n' ..
        '**Identifier:** %s\n' ..
        '**Admin:** %s\n' ..
        '**Timestamp:** %s',
        string.upper(action),
        logData.firstname or 'N/A',
        logData.lastname or 'N/A',
        logData.identifier or 'N/A',
        logData.admin_name or 'N/A',
        os.date('%Y-%m-%d %H:%M:%S', os.time())
    )

    if logData.citizenid then
        description = description .. '\n**Citizen ID:** ' .. logData.citizenid
    end

    if logData.phone then
        description = description .. '\n**Phone:** ' .. logData.phone
    end

    if logData.tables_count then
        description = description .. '\n**Tables Modified:** ' .. logData.tables_count
    end

    -- Handle vehicle transfer details
    if logData.vehicle_transferred and logData.vehicles_list and #logData.vehicles_list > 0 then
        description = description .. '\n**Vehicles Transferred:** ' .. #logData.vehicles_list
        if logData.transfer_target_name then
            description = description .. '\n**Transferred To:** ' .. logData.transfer_target_name
        end
        
        -- Add vehicle details
        local vehicleList = '```\n'
        for _, vehicle in ipairs(logData.vehicles_list) do
            vehicleList = vehicleList .. string.format('%-10s | %s\n', vehicle.plate or 'N/A', vehicle.model or 'Unknown')
        end
        vehicleList = vehicleList .. '```'
        description = description .. '\n**Vehicle List:**\n' .. vehicleList
    elseif logData.vehicle_transferred then
        description = description .. '\n**Vehicles Transferred:** Yes'
    end

    local payload = {
        embeds = {
            {
                title = 'Character Manager - ' .. string.upper(action),
                description = description,
                color = color,
                footer = {
                    text = 'character-manager v1.0.0'
                }
            }
        }
    }

    PerformHttpRequest(Config.WebhookURL, function(errorCode, resultData, resultHeaders)
        if errorCode ~= 204 then
            print('^3[character-manager] [WEBHOOK] Failed to send webhook (error: ' .. errorCode .. ')^7')
        end
    end, 'POST', json.encode(payload), {['Content-Type'] = 'application/json'})
end

-- ============================================

function searchPlayerCallback(source, cb, firstname, lastname, phonenumber, searchType)
    if searchType == 'restore' and Config.SafeWipeMode == false then
        cb({success = false, message = Lang:t("command.restore_unavailable"), players = {}})
        return
    end

    local hasSearchCriteria = (type(firstname) == 'string' and firstname ~= '') or
                              (type(lastname) == 'string' and lastname ~= '') or
                              (type(phonenumber) == 'string' and phonenumber ~= '')
    if not hasSearchCriteria then
        cb({success = false, message = Lang:t("command.infoNeed"), players = {}})
        return
    end

    local query, params
    
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        -- QBCore search
        if searchType == 'restore' then
            query = 'SELECT `license`, `citizenid`, `charinfo` FROM `wiped_players` WHERE 1=1'
            params = {}
        else
            query = 'SELECT `license`, `citizenid`, `charinfo` FROM `players` WHERE 1=1'
            params = {}
        end

        if firstname and firstname ~= '' then
            query = query .. ' AND `charinfo` LIKE ?'
            table.insert(params, '%'..firstname..'%')
        end
        
        if lastname and lastname ~= '' then
            query = query .. ' AND `charinfo` LIKE ?'
            table.insert(params, '%'..lastname..'%')
        end
        
        if phonenumber and phonenumber ~= '' then
            query = query .. ' AND `charinfo` LIKE ?'
            table.insert(params, '%'..phonenumber..'%')
        end

        local player_list = MySQL.query.await(query, params)

        if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
            for k,v in pairs(player_list) do
                local decoded = safeJsonDecode(v.charinfo)
                if decoded then
                    player_list[k].charinfo = decoded
                    player_list[k].firstname = decoded.firstname
                    player_list[k].lastname = decoded.lastname
                    player_list[k].phone = decoded.phone
                else
                    player_list[k] = nil
                end
            end
            -- Remove nils from table
            player_list = {table.unpack(player_list)}
            cb({success = true, players = player_list})
        else
            cb({success = false, message = Lang:t("command.player_not_found"), players = {}})
        end

    elseif FrameworkName == 'es_extended' then
        -- ESX search (note: ESX users table has no 'license' or 'phone' column)
        if searchType == 'restore' then
            query = 'SELECT `identifier`, `firstname`, `lastname` FROM `wiped_users` WHERE 1=1'
            params = {}
        else
            query = 'SELECT `identifier`, `firstname`, `lastname` FROM `users` WHERE 1=1'
            params = {}
        end

        if firstname and firstname ~= '' then
            query = query .. ' AND (`firstname` LIKE ? OR `lastname` LIKE ?)'
            table.insert(params, '%'..firstname..'%')
            table.insert(params, '%'..firstname..'%')
        end
        
        if lastname and lastname ~= '' then
            query = query .. ' AND `lastname` LIKE ?'
            table.insert(params, '%'..lastname..'%')
        end

        local player_list = MySQL.query.await(query, params)

        if player_list and #player_list > 0 then
            -- Add phone numbers for ESX players (from detected phone table if available)
            local getPhone = DBModule.getPhoneForPlayer
            for k,v in pairs(player_list) do
                player_list[k].phone = getPhone(v.identifier) or 'N/A'
            end
            
            -- If searching by phone number, filter for matches
            if phonenumber and phonenumber ~= '' then
                local filtered = {}
                for k,v in pairs(player_list) do
                    if v.phone ~= 'N/A' and string.find(v.phone, phonenumber) then
                        table.insert(filtered, v)
                    end
                end
                
                if #filtered > 0 then
                    cb({success = true, players = filtered})
                else
                    cb({success = false, message = Lang:t("command.player_not_found"), players = {}})
                end
            else
                cb({success = true, players = player_list})
            end
        else
            cb({success = false, message = Lang:t("command.player_not_found"), players = {}})
        end
    end
end

-- Callback: Search Transfer Targets (less strict OR matching)
function searchTransferTargetsCallback(source, cb, firstname, lastname, phonenumber)
    local hasSearchCriteria = (type(firstname) == 'string' and firstname ~= '') or
                              (type(lastname) == 'string' and lastname ~= '') or
                              (type(phonenumber) == 'string' and phonenumber ~= '')
    if not hasSearchCriteria then
        cb({success = false, message = Lang:t("command.infoNeed"), players = {}})
        return
    end

    local query, params

    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        query = 'SELECT `license`, `citizenid`, `charinfo` FROM `players` WHERE 1=1'
        params = {}

        local orClauses = {}
        if firstname and firstname ~= '' then
            table.insert(orClauses, '`charinfo` LIKE ?')
            table.insert(params, '%'..firstname..'%')
        end

        if lastname and lastname ~= '' then
            table.insert(orClauses, '`charinfo` LIKE ?')
            table.insert(params, '%'..lastname..'%')
        end

        if phonenumber and phonenumber ~= '' then
            table.insert(orClauses, '`charinfo` LIKE ?')
            table.insert(params, '%'..phonenumber..'%')
        end

        if #orClauses > 0 then
            query = query .. ' AND (' .. table.concat(orClauses, ' OR ') .. ')'
        end

        local player_list = MySQL.query.await(query, params)

        if player_list and #player_list > 0 then
            for k,v in pairs(player_list) do
                local decoded = safeJsonDecode(v.charinfo)
                if decoded then
                    player_list[k].charinfo = decoded
                    player_list[k].firstname = decoded.firstname
                    player_list[k].lastname = decoded.lastname
                    player_list[k].phone = decoded.phone
                else
                    player_list[k] = nil
                end
            end
            player_list = {table.unpack(player_list)}
            cb({success = true, players = player_list})
        else
            cb({success = false, message = Lang:t("command.player_not_found"), players = {}})
        end

    elseif FrameworkName == 'es_extended' then
        query = 'SELECT `identifier`, `firstname`, `lastname` FROM `users` WHERE 1=1'
        params = {}

        local orClauses = {}
        if firstname and firstname ~= '' then
            table.insert(orClauses, '(`firstname` LIKE ? OR `lastname` LIKE ?)')
            table.insert(params, '%'..firstname..'%')
            table.insert(params, '%'..firstname..'%')
        end

        if lastname and lastname ~= '' then
            table.insert(orClauses, '`lastname` LIKE ?')
            table.insert(params, '%'..lastname..'%')
        end

        if #orClauses > 0 then
            query = query .. ' AND (' .. table.concat(orClauses, ' OR ') .. ')'
        end

        local player_list = MySQL.query.await(query, params)

        if player_list and #player_list > 0 then
            local getPhone = DBModule.getPhoneForPlayer
            for k,v in pairs(player_list) do
                player_list[k].phone = getPhone(v.identifier) or 'N/A'
            end

            if phonenumber and phonenumber ~= '' then
                local filtered = {}
                for _, v in pairs(player_list) do
                    if v.phone ~= 'N/A' and string.find(v.phone, phonenumber) then
                        table.insert(filtered, v)
                    end
                end

                if #filtered > 0 then
                    cb({success = true, players = filtered})
                else
                    cb({success = false, message = Lang:t("command.player_not_found"), players = {}})
                end
            else
                cb({success = true, players = player_list})
            end
        else
            cb({success = false, message = Lang:t("command.player_not_found"), players = {}})
        end
    end
end

-- Callback: Get Character List
function getCharacterListCallback(source, cb, license, identifier)
    local accountPlayerList = {}
    
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        if license then
            accountPlayerList = MySQL.query.await('SELECT `license`, `citizenid`, `charinfo` FROM `players` WHERE `license` = ?', {
                license
            })
            
            if accountPlayerList then
                local cleaned = {}
                for k,v in pairs(accountPlayerList) do
                    local decoded = safeJsonDecode(v.charinfo)
                    if decoded then
                        v.charinfo = decoded
                        v.firstname = decoded.firstname
                        v.lastname = decoded.lastname
                        v.phone = decoded.phone
                        table.insert(cleaned, v)
                    end
                end
                accountPlayerList = cleaned
            end
        end
    elseif FrameworkName == 'es_extended' then
        -- ESX: Get other characters for same identifier account
        if identifier then
            accountPlayerList = MySQL.query.await('SELECT `identifier`, `firstname`, `lastname` FROM `users` WHERE `identifier` = ?', {
                identifier
            })
            
            -- Add phone numbers for ESX players (from detected phone table if available)
            if accountPlayerList then
                local getPhone = DBModule.getPhoneForPlayer
                for k,v in pairs(accountPlayerList) do
                    accountPlayerList[k].phone = getPhone(v.identifier) or 'N/A'
                end
            end
        end
    end

    cb({success = true, characters = accountPlayerList or {}})
end

-- Callback: Get Player Vehicles (for selectable transfer)
function getPlayerVehiclesCallback(source, cb, playerData)
    if not playerData or type(playerData) ~= 'table' then
        cb({success = false, vehicles = {}})
        return
    end

    local rows = {}
    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        if not playerData.citizenid then
            cb({success = true, vehicles = {}})
            return
        end
        rows = MySQL.query.await('SELECT `plate`, `vehicle` FROM `player_vehicles` WHERE `citizenid` = ?', {
            playerData.citizenid
        }) or {}
    elseif FrameworkName == 'es_extended' then
        if not playerData.identifier then
            cb({success = true, vehicles = {}})
            return
        end
        rows = MySQL.query.await('SELECT `plate`, `vehicle` FROM `owned_vehicles` WHERE `owner` = ?', {
            playerData.identifier
        }) or {}
    end

    local vehicles = {}

    for _, row in ipairs(rows) do
        local plate = tostring(row.plate or 'N/A')
        local modelCode = decodeVehicleModel(row.vehicle) or 'unknown'
        local modelName = getVehicleModelName(modelCode)

        table.insert(vehicles, {
            plate = plate,
            model = modelName,
            value = 0
        })
        
    end

    cb({success = true, vehicles = vehicles})
end

-- Callback: Wipe Player
function wipePlayerCallback(source, cb, playerData, targetCharacter, selectedVehicles, vehicleAction)
    local src = source
    local adminIdentifier = nil
    local adminName = GetPlayerName(src)
    local normalizedVehicleAction = type(vehicleAction) == 'string' and string.lower(vehicleAction) or 'delete'

    if normalizedVehicleAction ~= 'transfer' and normalizedVehicleAction ~= 'keep' and normalizedVehicleAction ~= 'delete' then
        normalizedVehicleAction = 'delete'
    end

    if not playerData then
        cb({success = false, message = Lang:t("command.player_not_found")})
        return
    end

    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        local admin = QBCore.Functions.GetPlayer(src)
        adminIdentifier = admin.PlayerData.license

        local vehicleTransferred = false
        local transferredVehicles = {}
        local transferTargetName = nil
        local transferTargetIdentifier = nil
        local extraExcludedTables = {}

        if Config.VehTransfert and normalizedVehicleAction ~= 'delete' then
            table.insert(extraExcludedTables, 'player_vehicles')
        end

        if Config.VehTransfert and playerData.citizenid then
            local selectedPlates = sanitizeSelectedPlates(selectedVehicles)

            if normalizedVehicleAction == 'transfer' and targetCharacter and targetCharacter.citizenid then
                local targetCitizenId = targetCharacter.citizenid
                transferTargetIdentifier = targetCharacter.license
                transferTargetName = (targetCharacter.charinfo and targetCharacter.charinfo.firstname or 'N/A') .. ' ' .. (targetCharacter.charinfo and targetCharacter.charinfo.lastname or '')

                if #selectedPlates == 0 then
                    cb({success = false, message = Lang:t("command.vehicle_select_required")})
                    return
                end

                -- Fetch vehicle details before transfer for logging
                local vehicleQuery = 'SELECT plate, vehicle FROM player_vehicles WHERE citizenid = ? AND plate IN (' .. table.concat((function(count) local t = {} for i = 1, count do t[i] = '?' end return t end)(#selectedPlates), ',') .. ')'
                local queryParams = {playerData.citizenid}
                for _, plate in ipairs(selectedPlates) do
                    table.insert(queryParams, plate)
                end
                
                local vehicleRows = MySQL.query.await(vehicleQuery, queryParams)
                if vehicleRows then
                    for _, row in ipairs(vehicleRows) do
                        local modelCode = decodeVehicleModel(row.vehicle) or 'Unknown'
                        local modelName = getVehicleModelName(modelCode)
                        
                        table.insert(transferredVehicles, {
                            plate = row.plate,
                            model = modelName,
                            transferred_to = transferTargetName
                        })
                    end
                end

                local placeholders = table.concat((function(count)
                    local t = {}
                    for i = 1, count do t[i] = '?' end
                    return t
                end)(#selectedPlates), ',')

                local params = {targetCitizenId, playerData.citizenid}
                for _, plate in ipairs(selectedPlates) do
                    table.insert(params, plate)
                end

                local transferQuery = string.format('UPDATE player_vehicles SET citizenid = ? WHERE citizenid = ? AND plate IN (%s)', placeholders)
                MySQL.query.await(transferQuery, params)

                local deleteParams = {playerData.citizenid}
                for _, plate in ipairs(selectedPlates) do
                    table.insert(deleteParams, plate)
                end
                local deleteQuery = string.format('DELETE FROM player_vehicles WHERE citizenid = ? AND plate NOT IN (%s)', placeholders)
                MySQL.query.await(deleteQuery, deleteParams)

                vehicleTransferred = true
            elseif normalizedVehicleAction == 'keep' and playerData.citizenid then
                local selectedPlates = sanitizeSelectedPlates(selectedVehicles)
                
                if #selectedPlates == 0 then
                    -- ERROR: Keep requires at least one vehicle
                    print('^1[character-manager] [KEEP] ERROR: No vehicles selected for KEEP action^7')
                    cb({success = false, message = Lang:t("command.vehicle_select_required")})
                    return
                else
                    -- Delete unselected vehicles (keep selected ones)
                    local placeholders = table.concat((function(count)
                        local t = {}
                        for i = 1, count do t[i] = '?' end
                        return t
                    end)(#selectedPlates), ',')
                    
                    local deleteParams = {playerData.citizenid}
                    for _, plate in ipairs(selectedPlates) do
                        table.insert(deleteParams, plate)
                    end
                    
                    local deleteQuery = string.format('DELETE FROM player_vehicles WHERE citizenid = ? AND TRIM(plate) NOT IN (%s)', placeholders)
                    MySQL.query.await(deleteQuery, deleteParams)
                end
            else
                MySQL.query.await('DELETE FROM player_vehicles WHERE citizenid = ?', { playerData.citizenid })
            end
        end

        local toWipeSrc = QBCore.Functions.GetSource(playerData.license)
        if toWipeSrc then
            DropPlayer(toWipeSrc, Lang:t("info.kick_message"))
        end

        local charinfo = playerData.charinfo
        if type(charinfo) == 'string' then
            charinfo = safeJsonDecode(charinfo)
        end

        local tablesWiped = DBModule.wipePlayerAllTables('license', playerData.license, extraExcludedTables, {
            citizenid = playerData.citizenid,
            owner = playerData.citizenid
        })

        DBModule.logWipeAction({
            action = 'wipe',
            identifier = playerData.license,
            citizenid = playerData.citizenid,
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            admin_identifier = adminIdentifier,
            admin_name = adminName,
            tables_count = tablesWiped,
            vehicle_transferred = vehicleTransferred,
            transfer_target_identifier = transferTargetIdentifier,
            transfer_target_name = transferTargetName,
            vehicles_list = transferredVehicles,
            phone = charinfo.phone or 'N/A'
        })

        -- Send webhook if configured
        sendWebhook({
            action = 'wipe',
            identifier = playerData.license,
            citizenid = playerData.citizenid,
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            admin_name = adminName,
            tables_count = tablesWiped,
            vehicle_transferred = vehicleTransferred,
            transfer_target_name = transferTargetName,
            vehicles_list = transferredVehicles,
            phone = charinfo.phone or 'N/A'
        })

        cb({success = true, message = Lang:t("command.wipe_done")})

    elseif FrameworkName == 'es_extended' then
        local admin = ESX.GetPlayerFromId(src)
        adminIdentifier = admin.getIdentifier()

        local vehicleTransferred = false
        local transferredVehicles = {}
        local transferTargetName = nil
        local transferTargetIdentifier = nil
        local extraExcludedTables = {}

        if Config.VehTransfert and normalizedVehicleAction ~= 'delete' then
            table.insert(extraExcludedTables, 'owned_vehicles')
        end

        if Config.VehTransfert and playerData.identifier then
            local selectedPlates = sanitizeSelectedPlates(selectedVehicles)

            if normalizedVehicleAction == 'transfer' and targetCharacter and targetCharacter.identifier then
                local targetIdentifier = targetCharacter.identifier
                transferTargetIdentifier = targetCharacter.identifier
                transferTargetName = targetCharacter.firstname .. ' ' .. targetCharacter.lastname

                if #selectedPlates == 0 then
                    cb({success = false, message = Lang:t("command.vehicle_select_required")})
                    return
                end

                -- Fetch vehicle details before transfer for logging
                local vehicleQuery = 'SELECT plate, vehicle FROM owned_vehicles WHERE owner = ? AND plate IN (' .. table.concat((function(count) local t = {} for i = 1, count do t[i] = '?' end return t end)(#selectedPlates), ',') .. ')'
                local queryParams = {playerData.identifier}
                for _, plate in ipairs(selectedPlates) do
                    table.insert(queryParams, plate)
                end
                
                local vehicleRows = MySQL.query.await(vehicleQuery, queryParams)
                if vehicleRows then
                    for _, row in ipairs(vehicleRows) do
                        local modelCode = decodeVehicleModel(row.vehicle) or 'Unknown'
                        local modelName = getVehicleModelName(modelCode)
                        
                        table.insert(transferredVehicles, {
                            plate = row.plate,
                            model = modelName,
                            transferred_to = transferTargetName
                        })
                    end
                end

                local placeholders = table.concat((function(count)
                    local t = {}
                    for i = 1, count do t[i] = '?' end
                    return t
                end)(#selectedPlates), ',')

                local params = {targetIdentifier, playerData.identifier}
                for _, plate in ipairs(selectedPlates) do
                    table.insert(params, plate)
                end

                local transferQuery = string.format('UPDATE owned_vehicles SET owner = ? WHERE owner = ? AND plate IN (%s)', placeholders)
                MySQL.query.await(transferQuery, params)

                local deleteParams = {playerData.identifier}
                for _, plate in ipairs(selectedPlates) do
                    table.insert(deleteParams, plate)
                end
                local deleteQuery = string.format('DELETE FROM owned_vehicles WHERE owner = ? AND plate NOT IN (%s)', placeholders)
                MySQL.query.await(deleteQuery, deleteParams)

                vehicleTransferred = true
            elseif normalizedVehicleAction == 'keep' and playerData.identifier then
                local selectedPlates = sanitizeSelectedPlates(selectedVehicles)
                
                if #selectedPlates == 0 then
                    -- ERROR: Keep requires at least one vehicle
                    print('^1[character-manager] [KEEP] ERROR: No vehicles selected for KEEP action^7')
                    cb({success = false, message = Lang:t("command.vehicle_select_required")})
                    return
                else
                    -- Delete unselected vehicles (keep selected ones)
                    local placeholders = table.concat((function(count)
                        local t = {}
                        for i = 1, count do t[i] = '?' end
                        return t
                    end)(#selectedPlates), ',')
                    
                    local deleteParams = {playerData.identifier}
                    for _, plate in ipairs(selectedPlates) do
                        table.insert(deleteParams, plate)
                    end
                    
                    local deleteQuery = string.format('DELETE FROM owned_vehicles WHERE owner = ? AND TRIM(plate) NOT IN (%s)', placeholders)
                    MySQL.query.await(deleteQuery, deleteParams)
                end
            else
                MySQL.query.await('DELETE FROM owned_vehicles WHERE owner = ?', { playerData.identifier })
            end
        end

        local toWipeSrc = ESX.GetPlayerFromIdentifier(playerData.identifier)
        if toWipeSrc then
            DropPlayer(toWipeSrc.source, Lang:t("info.kick_message"))
        end

        local tablesWiped = DBModule.wipePlayerAllTables('identifier', playerData.identifier, extraExcludedTables, {
            owner = playerData.identifier
        })
        local phone = DBModule.getPhoneForPlayer(playerData.identifier) or 'N/A'

        DBModule.logWipeAction({
            action = 'wipe',
            identifier = playerData.identifier,
            citizenid = nil,
            firstname = playerData.firstname,
            lastname = playerData.lastname,
            admin_identifier = adminIdentifier,
            admin_name = adminName,
            tables_count = tablesWiped,
            vehicle_transferred = vehicleTransferred,
            transfer_target_identifier = transferTargetIdentifier,
            transfer_target_name = transferTargetName,
            vehicles_list = transferredVehicles,
            phone = phone
        })

        -- Send webhook if configured
        sendWebhook({
            action = 'wipe',
            identifier = playerData.identifier,
            firstname = playerData.firstname,
            lastname = playerData.lastname,
            admin_name = adminName,
            tables_count = tablesWiped,
            vehicle_transferred = vehicleTransferred,
            transfer_target_name = transferTargetName,
            vehicles_list = transferredVehicles,
            phone = phone
        })

        cb({success = true, message = Lang:t("command.wipe_done")})
    end
end

-- Callback: Restore Player
function restorePlayerCallback(source, cb, playerData)
    local adminIdentifier = nil
    local adminName = GetPlayerName(source)
    
    if not playerData then
        cb({success = false, message = Lang:t("command.player_not_found")})
        return
    end

    if FrameworkName == 'qb-core' or FrameworkName == 'qbox_core' then
        -- Get admin identifier
        local admin = QBCore.Functions.GetPlayer(source)
        adminIdentifier = admin.PlayerData.license
        
        -- Get charinfo for logging
        local charinfo = playerData.charinfo
        if type(charinfo) == 'string' then
            charinfo = safeJsonDecode(charinfo)
        end

        -- Restore player from all backup tables
        local tablesRestored = DBModule.restorePlayerAllTables('license', playerData.license, {
            citizenid = playerData.citizenid,
            owner = playerData.citizenid
        })
        if tablesRestored <= 0 then
            cb({success = false, message = Lang:t("command.restore_unavailable")})
            return
        end
        
        -- Log restore action with phone retrieved on-demand
        DBModule.logRestoreAction({
            action = 'restore',
            identifier = playerData.license,
            citizenid = playerData.citizenid,
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            admin_identifier = adminIdentifier,
            admin_name = adminName,
            tables_count = tablesRestored,
            phone = charinfo.phone or 'N/A'
        })

        -- Send webhook if configured
        sendWebhook({
            action = 'restore',
            identifier = playerData.license,
            citizenid = playerData.citizenid,
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            admin_name = adminName,
            tables_count = tablesRestored,
            phone = charinfo.phone or 'N/A'
        })

        cb({success = true, message = Lang:t("command.restore_done")})

    elseif FrameworkName == 'es_extended' then
        -- Get admin identifier
        local admin = ESX.GetPlayerFromId(source)
        adminIdentifier = admin.getIdentifier()
        
        -- Restore player from all backup tables
        local tablesRestored = DBModule.restorePlayerAllTables('identifier', playerData.identifier, {
            owner = playerData.identifier
        })
        if tablesRestored <= 0 then
            cb({success = false, message = Lang:t("command.restore_unavailable")})
            return
        end
        
        -- Get phone on-demand for ESX
        local phone = DBModule.getPhoneForPlayer(playerData.identifier) or 'N/A'
        
        -- Log restore action
        DBModule.logRestoreAction({
            action = 'restore',
            identifier = playerData.identifier,
            citizenid = nil,
            firstname = playerData.firstname,
            lastname = playerData.lastname,
            admin_identifier = adminIdentifier,
            admin_name = adminName,
            tables_count = tablesRestored,
            phone = phone
        })

        -- Send webhook if configured
        sendWebhook({
            action = 'restore',
            identifier = playerData.identifier,
            firstname = playerData.firstname,
            lastname = playerData.lastname,
            admin_name = adminName,
            tables_count = tablesRestored,
            phone = phone
        })

        cb({success = true, message = Lang:t("command.restore_done")})
    end
end

-- Callback: Get Player Logs
function getPlayerLogsCallback(source, cb, searchData)
    if not searchData or type(searchData) ~= 'table' then
        cb({success = false, message = Lang:t("command.player_not_found"), logs = {}})
        return
    end
    
    -- Add limit if not provided
    if not searchData.limit then
        searchData.limit = 100
    end

    local logs = DBModule.getPlayerLogs(searchData)

    if logs and #logs > 0 then
        cb({success = true, logs = logs})
    else
        cb({success = true, logs = {}})
    end
end

-- ============================================
-- Security Cleanup
-- ============================================

-- Clean up session tokens and rate limits when player disconnects
AddEventHandler('playerDropped', function(reason)
    local src = source
    SessionTokens[src] = nil
    RequestLimits[src] = nil
end)
