-- Database configuration and table detection based on framework

local TableMetadata = {} -- Cache to store table metadata
local ClonedTables = {} -- Track tables already cloned to avoid duplicate messages
local InitializationLogs = {} -- Accumulated logs during initialization
local PhoneTableSource = nil -- Where phone numbers are stored {table: 'name', column: 'number_column', id_column: 'id_column'}

-- Helper functions defined first (before use)

local function tableExists(tableName)
    local result = MySQL.query.await('SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { tableName })
    return result and #result > 0
end

local function getTableColumns(tableName)
    local result = MySQL.query.await([[
        SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_KEY, EXTRA
        FROM information_schema.COLUMNS 
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION
    ]], { tableName })
    
    if not result or #result == 0 then
        return {}
    end
    
    return result
end

-- Detect phone table/column during initialization
local function detectPhoneSource()
    -- Common phone table patterns from popular FiveM resources
    local phoneTablePatterns = {
        -- QB-Core resources
        { table = 'player_phones', number_col = 'phone_number', id_col = 'citizenid' },
        { table = 'player_phones', number_col = 'number', id_col = 'citizenid' },
        -- ESX resources
        { table = 'user_phones', number_col = 'phone_number', id_col = 'identifier' },
        { table = 'users_phones', number_col = 'phone_number', id_col = 'identifier' },
        -- Generic resources
        { table = 'phone_numbers', number_col = 'phone_number', id_col = 'player_id' },
        { table = 'phones', number_col = 'phone_number', id_col = 'user_id' },
        { table = 'phone_contacts', number_col = 'number', id_col = 'owner_id' },
    }
    
    for _, pattern in ipairs(phoneTablePatterns) do
        if tableExists(pattern.table) then
            -- Verify the expected columns exist
            local columns = getTableColumns(pattern.table)
            local hasNumberCol = false
            local hasIdCol = false
            
            for _, col in ipairs(columns) do
                if string.lower(col.COLUMN_NAME) == string.lower(pattern.number_col) then
                    hasNumberCol = true
                end
                if string.lower(col.COLUMN_NAME) == string.lower(pattern.id_col) then
                    hasIdCol = true
                end
            end
            
            if hasNumberCol and hasIdCol then
                PhoneTableSource = {
                    table = pattern.table,
                    number_col = pattern.number_col,
                    id_col = pattern.id_col
                }
                print(string.format('^2[character-manager] Phone source detected: %s.%s (indexed by %s)^7', 
                    pattern.table, pattern.number_col, pattern.id_col))
                return
            end
        end
    end
    
    print('^3[character-manager] No phone table found - phone search will be disabled^7')
end

-- Get phone number for a player (used in search)
local function getPhoneForPlayer(identifier)
    if not PhoneTableSource then
        return nil
    end
    
    local success, result = pcall(function()
        return MySQL.query.await(
            string.format('SELECT `%s` FROM `%s` WHERE `%s` = ? LIMIT 1',
                PhoneTableSource.number_col,
                PhoneTableSource.table,
                PhoneTableSource.id_col
            ),
            { identifier }
        )
    end)
    
    if success and result and #result > 0 then
        return result[1][PhoneTableSource.number_col]
    end
    
    return nil
end

-- Tables to exclude from cloning and wiping (ban tables, critical logs, whitelist, etc.)
local function getExcludedTables()
    return {
        -- Character Manager
        'character_manager_logs',
        -- Ban systems
        'bans',
        'banlist',
        'baninfo',
        'banlisthistory',
        'ban_list',
        'player_bans',
        'banned_players',
        -- Whitelist
        'whitelist',
        'whitelists',
        'player_whitelist',
        'user_whitelist',
        'whitelist_users',
        'whitelist_players',
        -- Critical logs
        'audit_logs',
        'server_logs',
        'admin_logs'
    }
end

local function shouldExcludeTable(tableName)
    local excludedTables = getExcludedTables()
    local lowerTableName = string.lower(tableName)
    
    -- Check exact matches first
    for _, excludedTable in ipairs(excludedTables) do
        if string.lower(excludedTable) == lowerTableName then
            return true
        end
    end
    
    -- Exclude tables by pattern
    local excludePatterns = {
        'ban',              -- Bans/blacklist tables
        'whitelist',        -- Whitelist tables
        'wiped_',           -- Our backup tables
        'character_manager',-- Our own tables
        'audit',            -- Audit logs
        'log',              -- Log tables
        '_temp',            -- Temporary tables
        '_cache',           -- Cache tables
        'migrations',       -- Migration tables
        'sessions',         -- Session tables (often temporary)
        'tokens',           -- Token tables (sensitive)
        'permission',       -- Permission systems (critical)
        'admin'            -- Admin tables (critical)
    }
    
    for _, pattern in ipairs(excludePatterns) do
        if string.find(lowerTableName, pattern) then
            return true
        end
    end
    
    -- Exclude system/metadata tables
    if string.sub(lowerTableName, 1, 1) == '_' then
        return true  -- Tables starting with underscore are usually system tables
    end
    
    return false
end

local function findIdentifierColumn(tableName)
    -- Common identifier columns to search by priority
    -- Order matters: most specific/common first
    local identifierPatterns = {
        'citizenid',    -- QB-Core primary (check first due to popularity)
        'identifier',   -- Generic/ESX primary
        'license',      -- Common fallback
        'owner',        -- Used in stash/property tables
        'steam',
        'discord',
        'fivem',
        'xbl',
        'live',
        'ip'
    }
    
    local columns = getTableColumns(tableName)
    
    if not columns or #columns == 0 then
        return nil
    end
    
    -- First pass: exact match (case-insensitive)
    for _, pattern in ipairs(identifierPatterns) do
        for _, column in ipairs(columns) do
            local columnLower = string.lower(column.COLUMN_NAME)
            local patternLower = string.lower(pattern)
            
            if columnLower == patternLower then
                -- Verify it's a string type suitable for identifiers
                local colType = string.lower(column.COLUMN_TYPE)
                if string.find(colType, 'varchar') or string.find(colType, 'char') or string.find(colType, 'text') then
                    return column.COLUMN_NAME
                end
            end
        end
    end
    
    -- Second pass: pattern matching (contains)
    for _, pattern in ipairs(identifierPatterns) do
        for _, column in ipairs(columns) do
            local columnLower = string.lower(column.COLUMN_NAME)
            local patternLower = string.lower(pattern)
            
            if string.find(columnLower, patternLower) then
                -- Verify it's a string type suitable for identifiers
                local colType = string.lower(column.COLUMN_TYPE)
                if string.find(colType, 'varchar') or string.find(colType, 'char') or string.find(colType, 'text') then
                    return column.COLUMN_NAME
                end
            end
        end
    end
    
    return nil
end

local function validateIdentifierColumn(tableName, columnName)
    -- Wrap in pcall for safety
    local success, result = pcall(function()
        -- Check if table has any data
        local countQuery = string.format('SELECT COUNT(*) as count FROM `%s` LIMIT 1', tableName)
        local countResult = MySQL.query.await(countQuery)
        
        if not countResult or #countResult == 0 or countResult[1].count == 0 then
            return false  -- Empty table, skip
        end
        
        -- Sample a few rows to validate identifier format
        local sampleQuery = string.format(
            'SELECT `%s` FROM `%s` WHERE `%s` IS NOT NULL AND `%s` != "" LIMIT 5',
            columnName, tableName, columnName, columnName
        )
        
        local sampleResult = MySQL.query.await(sampleQuery)
        
        if not sampleResult or #sampleResult == 0 then
            return false  -- No valid identifiers found
        end
        
        -- Check if identifiers look valid (not too short, not empty)
        for _, row in ipairs(sampleResult) do
            local identifier = row[columnName]
            if identifier and type(identifier) == 'string' and string.len(identifier) >= 3 then
                return true  -- Found at least one valid-looking identifier
            end
        end
        
        return false
    end)
    
    if not success then
        print(string.format('^3[character-manager] Warning: Failed to validate table %s column %s: %s^7', tableName, columnName, tostring(result)))
        return false
    end
    
    return result
end

local function getAllTablesWithIdentifiers()
    local tables = {}
    local result = MySQL.query.await([[
        SELECT DISTINCT TABLE_NAME 
        FROM information_schema.COLUMNS 
        WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME NOT LIKE 'wiped_%'
        ORDER BY TABLE_NAME
    ]])
    
    if not result or #result == 0 then
        return tables
    end
    
    for _, row in ipairs(result) do
        local tableName = row.TABLE_NAME
        
        -- Skip excluded tables
        if not shouldExcludeTable(tableName) then
            local identifierColumn = findIdentifierColumn(tableName)
            
            -- If identifier column found, validate it has usable data
            if identifierColumn then
                local isValid = validateIdentifierColumn(tableName, identifierColumn)
                if isValid then
                    table.insert(tables, tableName)
                end
            end
        end
    end
    
    return tables
end

local function getTablesToBackup()
    -- Auto-detection of all tables with identifier columns
    local allTables = getAllTablesWithIdentifiers()
    
    if #allTables > 0 then
        return allTables
    end
    
    -- Fallback if nothing is found
    print('[character-manager] Warning: No tables with identifiers found')
    return {}
end

-- Character Manager Logs System
local function createLogsTable()
    local query = [[
        CREATE TABLE IF NOT EXISTS `character_manager_logs` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `action` VARCHAR(50) NOT NULL,
            `identifier` VARCHAR(100) NOT NULL,
            `citizenid` VARCHAR(50) DEFAULT NULL,
            `firstname` VARCHAR(50) DEFAULT NULL,
            `lastname` VARCHAR(50) DEFAULT NULL,
            `phone` VARCHAR(20) DEFAULT NULL,
            `admin_identifier` VARCHAR(100) DEFAULT NULL,
            `admin_name` VARCHAR(100) DEFAULT NULL,
            `tables_count` INT(11) DEFAULT 0,
            `vehicle_transferred` TINYINT(1) DEFAULT 0,
            `transfer_target_identifier` VARCHAR(100) DEFAULT NULL,
            `transfer_target_name` VARCHAR(100) DEFAULT NULL,
            `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(),
            `details` TEXT DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_identifier` (`identifier`),
            KEY `idx_action` (`action`),
            KEY `idx_timestamp` (`timestamp`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]]
    
    MySQL.query.await(query)
end

local function logWipeAction(data)
    local query = [[
        INSERT INTO `character_manager_logs` 
        (`action`, `identifier`, `citizenid`, `firstname`, `lastname`, `phone`, `admin_identifier`, `admin_name`, `tables_count`, `vehicle_transferred`, `transfer_target_identifier`, `transfer_target_name`, `details`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]
    
    -- Build transfer details JSON if vehicles were transferred
    local transferDetails = nil
    if data.vehicle_transferred and data.vehicles_list and #data.vehicles_list > 0 then
        transferDetails = json.encode(data.vehicles_list)
    end
    
    MySQL.query.await(query, {
        data.action or 'wipe',
        data.identifier,
        data.citizenid,
        data.firstname,
        data.lastname,
        data.phone,
        data.admin_identifier,
        data.admin_name,
        data.tables_count or 0,
        data.vehicle_transferred and 1 or 0,
        data.transfer_target_identifier,
        data.transfer_target_name,
        transferDetails or data.details
    })
end

local function logRestoreAction(data)
    local query = [[
        INSERT INTO `character_manager_logs` 
        (`action`, `identifier`, `citizenid`, `firstname`, `lastname`, `phone`, `admin_identifier`, `admin_name`, `tables_count`, `details`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]
    
    MySQL.query.await(query, {
        'restore',
        data.identifier,
        data.citizenid,
        data.firstname,
        data.lastname,
        data.phone,
        data.admin_identifier,
        data.admin_name,
        data.tables_count or 0,
        data.details
    })
end

-- Wipe player from all tables in database (except excluded ones)
local function wipePlayerAllTables(idType, idValue, extraExcludedTables, identifierCandidates)
    print('^3[character-manager] [DB] Wiping player from all tables: idType=' .. idType .. ', idValue=' .. idValue .. '^7')
    local safeMode = Config.SafeWipeMode ~= false
    print('^3[character-manager] [DB] SafeWipeMode=' .. tostring(safeMode) .. '^7')

    local candidateValues = {}
    if type(idType) == 'string' and idType ~= '' and idValue ~= nil and tostring(idValue) ~= '' then
        candidateValues[string.lower(idType)] = tostring(idValue)
    end

    if type(identifierCandidates) == 'table' then
        for key, value in pairs(identifierCandidates) do
            if type(key) == 'string' and key ~= '' and value ~= nil and tostring(value) ~= '' then
                candidateValues[string.lower(key)] = tostring(value)
            end
        end
    end

    local excludedLookup = {}
    for _, excludedTable in ipairs(Config.ExcludedTables or {}) do
        excludedLookup[string.lower(excludedTable)] = true
    end

    if type(extraExcludedTables) == 'table' then
        for _, excludedTable in ipairs(extraExcludedTables) do
            if type(excludedTable) == 'string' and excludedTable ~= '' then
                excludedLookup[string.lower(excludedTable)] = true
            end
        end
    end

    local processedTables = {}
    
    -- Get list of all tables
    local allTablesResult = MySQL.query.await([[
        SELECT TABLE_NAME FROM information_schema.TABLES 
        WHERE TABLE_SCHEMA = DATABASE() 
        ORDER BY TABLE_NAME
    ]])
    
    if not allTablesResult or #allTablesResult == 0 then
        print('^1[character-manager] [DB] No tables found in database^7')
        return 0
    end
    
    local tablesModified = 0
    
    for _, tableObj in ipairs(allTablesResult) do
        local tableName = tableObj.TABLE_NAME
        local lowerTableName = string.lower(tableName)

        -- Prevent duplicate processing of the same table name
        if processedTables[lowerTableName] then
            goto continue
        end
        processedTables[lowerTableName] = true

        -- Always skip backup tables
        if string.sub(lowerTableName, 1, 6) == 'wiped_' then
            goto continue
        end
        
        -- Skip excluded tables
        if excludedLookup[lowerTableName] then
            goto continue
        end
        
        -- Get columns for this table
        local columns = getTableColumns(tableName)
        if #columns == 0 then
            goto continue
        end
        
        -- Find identifier columns (license, identifier, citizenid, owner)
        local idColumns = {}
        local idColumnMap = {}
        
        for _, col in ipairs(columns) do
            local colName = string.lower(col.COLUMN_NAME)
            if colName == 'license' or colName == 'identifier' or colName == 'citizenid' or colName == 'owner' then
                table.insert(idColumns, col.COLUMN_NAME)
                idColumnMap[colName] = col.COLUMN_NAME
            end
        end
        
        if #idColumns == 0 then
            goto continue
        end
        
        -- Check if this table has a relevant identifier candidate
        local matchedColumn = nil
        local matchedValue = nil

        local preferredId = type(idType) == 'string' and string.lower(idType) or nil
        if preferredId and idColumnMap[preferredId] and candidateValues[preferredId] then
            matchedColumn = idColumnMap[preferredId]
            matchedValue = candidateValues[preferredId]
        else
            for candidateKey, candidateValue in pairs(candidateValues) do
                if idColumnMap[candidateKey] then
                    matchedColumn = idColumnMap[candidateKey]
                    matchedValue = candidateValue
                    break
                end
            end
        end
        
        if matchedColumn and matchedValue then
            print('^3[character-manager] [DB] Found ' .. matchedColumn .. ' in table ' .. tableName .. '^7')
            
            -- Get all rows for this player
            local query = string.format('SELECT * FROM `%s` WHERE `%s` = ?', tableName, matchedColumn)
            local playerRows = MySQL.query.await(query, { matchedValue })
            
            if playerRows and #playerRows > 0 then
                if safeMode then
                    -- Store in backup table (create clone if needed)
                    local wipedTableName = 'wiped_' .. tableName
                    if not tableExists(wipedTableName) then
                        local cloneQuery = string.format('CREATE TABLE IF NOT EXISTS `%s` LIKE `%s`', wipedTableName, tableName)
                        MySQL.query.await(cloneQuery)
                        print('^3[character-manager] [DB] Created backup table: ' .. wipedTableName .. '^7')
                    end
                    
                    -- Insert backup rows
                    local insertQuery = string.format('INSERT INTO `%s` SELECT * FROM `%s` WHERE `%s` = ?', wipedTableName, tableName, matchedColumn)
                    MySQL.query.await(insertQuery, { matchedValue })
                end
                
                -- Delete from original table
                local deleteQuery = string.format('DELETE FROM `%s` WHERE `%s` = ?', tableName, matchedColumn)
                MySQL.query.await(deleteQuery, { matchedValue })
                
                print('^2[character-manager] [DB] ✓ Wiped ' .. #playerRows .. ' rows from ' .. tableName .. '^7')
                tablesModified = tablesModified + 1
            end
        end
        
        ::continue::
    end
    
    print('^2[character-manager] [DB] Wipe complete: ' .. tablesModified .. ' tables modified^7')
    return tablesModified
end

-- Restore player to all backup tables (except excluded ones)
local function restorePlayerAllTables(idType, idValue, identifierCandidates)
    print('^3[character-manager] [DB] Restoring player from all backup tables: idType=' .. idType .. ', idValue=' .. idValue .. '^7')
    if Config.SafeWipeMode == false then
        print('^1[character-manager] [DB] Restore skipped: SafeWipeMode=false (no backups available)^7')
        return 0
    end

    local candidateValues = {}
    if type(idType) == 'string' and idType ~= '' and idValue ~= nil and tostring(idValue) ~= '' then
        candidateValues[string.lower(idType)] = tostring(idValue)
    end

    if type(identifierCandidates) == 'table' then
        for key, value in pairs(identifierCandidates) do
            if type(key) == 'string' and key ~= '' and value ~= nil and tostring(value) ~= '' then
                candidateValues[string.lower(key)] = tostring(value)
            end
        end
    end

    local excludedLookup = {}
    for _, excludedTable in ipairs(Config.ExcludedTables or {}) do
        excludedLookup[string.lower(excludedTable)] = true
    end

    local processedWipedTables = {}
    
    -- Get list of all wiped_ tables
    local wipedTablesResult = MySQL.query.await([[
        SELECT TABLE_NAME FROM information_schema.TABLES 
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME LIKE 'wiped_%'
        ORDER BY TABLE_NAME
    ]])
    
    if not wipedTablesResult or #wipedTablesResult == 0 then
        print('^1[character-manager] [DB] No backup tables found^7')
        return 0
    end
    
    local tablesRestored = 0
    
    for _, wipedTableObj in ipairs(wipedTablesResult) do
        local wipedTableName = wipedTableObj.TABLE_NAME
        local lowerWipedTableName = string.lower(wipedTableName)

        if processedWipedTables[lowerWipedTableName] then
            goto continue
        end
        processedWipedTables[lowerWipedTableName] = true

        local originalTableName = wipedTableName:gsub('^wiped_', '')
        local lowerOriginalTableName = string.lower(originalTableName)
        
        -- Skip if original table excluded
        if excludedLookup[lowerOriginalTableName] then
            goto continue
        end
        
        -- Get columns
        local columns = getTableColumns(wipedTableName)
        if #columns == 0 then
            goto continue
        end
        
        -- Check if table has a relevant identifier candidate
        local matchedColumn = nil
        local matchedValue = nil

        local columnMap = {}
        for _, col in ipairs(columns) do
            local colName = string.lower(col.COLUMN_NAME)
            if colName == 'license' or colName == 'identifier' or colName == 'citizenid' or colName == 'owner' then
                columnMap[colName] = col.COLUMN_NAME
            end
        end

        local preferredId = type(idType) == 'string' and string.lower(idType) or nil
        if preferredId and columnMap[preferredId] and candidateValues[preferredId] then
            matchedColumn = columnMap[preferredId]
            matchedValue = candidateValues[preferredId]
        else
            for candidateKey, candidateValue in pairs(candidateValues) do
                if columnMap[candidateKey] then
                    matchedColumn = columnMap[candidateKey]
                    matchedValue = candidateValue
                    break
                end
            end
        end
        
        if matchedColumn and matchedValue then
            -- Get rows from backup
            local query = string.format('SELECT * FROM `%s` WHERE `%s` = ?', wipedTableName, matchedColumn)
            local backupRows = MySQL.query.await(query, { matchedValue })
            
            if backupRows and #backupRows > 0 then
                -- Check if original table still exists
                if tableExists(originalTableName) then
                    -- Restore rows to original table
                    local restoreQuery = string.format('INSERT INTO `%s` SELECT * FROM `%s` WHERE `%s` = ? ON DUPLICATE KEY UPDATE id=id', 
                        originalTableName, wipedTableName, matchedColumn)
                    MySQL.query.await(restoreQuery, { matchedValue })
                    
                    print('^2[character-manager] [DB] ✓ Restored ' .. #backupRows .. ' rows to ' .. originalTableName .. '^7')
                    tablesRestored = tablesRestored + 1
                else
                    print('^1[character-manager] [DB] Original table not found: ' .. originalTableName .. '^7')
                end
            end
        end
        
        ::continue::
    end
    
    print('^2[character-manager] [DB] Restore complete: ' .. tablesRestored .. ' tables processed^7')
    return tablesRestored
end

local function getPlayerLogs(searchData)
    local limit = searchData.limit or 50
    local params = {}
    local whereClauses = {}
    
    -- Build WHERE clause dynamically based on provided search criteria
    if searchData.firstname and searchData.firstname ~= '' then
        table.insert(whereClauses, '(`firstname` LIKE ? OR `lastname` LIKE ?)')
        table.insert(params, '%' .. searchData.firstname .. '%')
        table.insert(params, '%' .. searchData.firstname .. '%')
    end
    
    if searchData.lastname and searchData.lastname ~= '' then
        table.insert(whereClauses, '`lastname` LIKE ?')
        table.insert(params, '%' .. searchData.lastname .. '%')
    end
    
    if searchData.phone and searchData.phone ~= '' then
        table.insert(whereClauses, '`phone` LIKE ?')
        table.insert(params, '%' .. searchData.phone .. '%')
    end
    
    -- If no criteria provided, return empty results
    if #whereClauses == 0 then
        return {}
    end
    
    -- Combine WHERE clauses with AND
    local whereClause = table.concat(whereClauses, ' AND ')
    
    local query = string.format([[
        SELECT * FROM `character_manager_logs` 
        WHERE %s 
        ORDER BY `timestamp` DESC 
        LIMIT ?
    ]], whereClause)
    
    table.insert(params, limit)
    
    local result = MySQL.query.await(query, params)
    
    return result or {}
end

local function analyzeTableStructure(tableName)
    if TableMetadata[tableName] then
        return TableMetadata[tableName]
    end
    
    local metadata = {
        exists = tableExists(tableName),
        identifierColumn = nil,
        columns = {}
    }
    
    if metadata.exists then
        local columns = getTableColumns(tableName)
        metadata.columns = columns
        metadata.identifierColumn = findIdentifierColumn(tableName)
    end
    
    TableMetadata[tableName] = metadata
    return metadata
end

local function compareTableStructures(originalTable, clonedTable)
    local originalColumns = getTableColumns(originalTable)
    local clonedColumns = getTableColumns(clonedTable)
    
    -- Convert cloned columns to a map for easy lookup
    local clonedMap = {}
    for _, col in ipairs(clonedColumns) do
        clonedMap[col.COLUMN_NAME] = {
            COLUMN_TYPE = col.COLUMN_TYPE,
            IS_NULLABLE = col.IS_NULLABLE,
            COLUMN_DEFAULT = col.COLUMN_DEFAULT,
            COLUMN_KEY = col.COLUMN_KEY,
            EXTRA = col.EXTRA
        }
    end
    
    local differences = {
        missingColumns = {},  -- Columns in original but not in cloned
        extraColumns = {},    -- Columns in cloned but not in original
        modifiedColumns = {}  -- Columns with different types/properties
    }
    
    -- Check for missing or modified columns
    for _, originalCol in ipairs(originalColumns) do
        local colName = originalCol.COLUMN_NAME
        local clonedCol = clonedMap[colName]
        
        if not clonedCol then
            table.insert(differences.missingColumns, originalCol)
        elseif clonedCol.COLUMN_TYPE ~= originalCol.COLUMN_TYPE then
            table.insert(differences.modifiedColumns, {
                name = colName,
                original = originalCol,
                cloned = clonedCol
            })
        end
    end
    
    -- Check for extra columns in cloned table
    local originalMap = {}
    for _, col in ipairs(originalColumns) do
        originalMap[col.COLUMN_NAME] = true
    end
    
    for _, clonedCol in ipairs(clonedColumns) do
        if not originalMap[clonedCol.COLUMN_NAME] then
            table.insert(differences.extraColumns, clonedCol)
        end
    end
    
    return differences
end

local function synchronizeTableStructure(originalTable, clonedTable)
    local diff = compareTableStructures(originalTable, clonedTable)
    local changes = {
        added = 0,
        modified = 0,
        errors = 0
    }
    
    -- Add missing columns
    for _, column in ipairs(diff.missingColumns) do
        local success, err = pcall(function()
            local nullable = column.IS_NULLABLE == 'YES' and 'NULL' or 'NOT NULL'
            local defaultValue = column.COLUMN_DEFAULT and (' DEFAULT ' .. column.COLUMN_DEFAULT) or ''
            local extra = column.EXTRA ~= '' and (' ' .. column.EXTRA) or ''
            
            local query = string.format(
                'ALTER TABLE `%s` ADD COLUMN `%s` %s %s%s%s',
                clonedTable,
                column.COLUMN_NAME,
                column.COLUMN_TYPE,
                nullable,
                defaultValue,
                extra
            )
            
            MySQL.query.await(query)
            changes.added = changes.added + 1
        end)
        
        if not success then
            print(string.format('^3[character-manager] Warning: Failed to add column %s to %s: %s^7', column.COLUMN_NAME, clonedTable, tostring(err)))
            changes.errors = changes.errors + 1
        end
    end
    
    -- Modify columns with different types
    for _, modInfo in ipairs(diff.modifiedColumns) do
        local success, err = pcall(function()
            local column = modInfo.original
            local nullable = column.IS_NULLABLE == 'YES' and 'NULL' or 'NOT NULL'
            local defaultValue = column.COLUMN_DEFAULT and (' DEFAULT ' .. column.COLUMN_DEFAULT) or ''
            local extra = column.EXTRA ~= '' and (' ' .. column.EXTRA) or ''
            
            local query = string.format(
                'ALTER TABLE `%s` MODIFY COLUMN `%s` %s %s%s%s',
                clonedTable,
                modInfo.name,
                column.COLUMN_TYPE,
                nullable,
                defaultValue,
                extra
            )
            
            MySQL.query.await(query)
            changes.modified = changes.modified + 1
        end)
        
        if not success then
            print(string.format('^3[character-manager] Warning: Failed to modify column %s in %s: %s^7', modInfo.name, clonedTable, tostring(err)))
            changes.errors = changes.errors + 1
        end
    end
    
    -- Drop extra columns (optional - commented out for safety)
    -- for _, column in ipairs(diff.extraColumns) do
    --     local query = string.format('ALTER TABLE `%s` DROP COLUMN `%s`', clonedTable, column.COLUMN_NAME)
    --     MySQL.query.await(query)
    --     changes.removed = changes.removed + 1
    -- end
    
    return changes
end

local function createWipedTable(originalTable)
    local wipedTableName = 'wiped_' .. originalTable
    
    -- Check if table already exists
    local alreadyExists = tableExists(wipedTableName)
    
    if alreadyExists then
        -- Synchronize structure if table already exists
        if not ClonedTables[wipedTableName] then
            local changes = synchronizeTableStructure(originalTable, wipedTableName)
            if changes.added > 0 or changes.modified > 0 or changes.errors > 0 then
                table.insert(InitializationLogs, {
                    type = 'sync',
                    table = wipedTableName,
                    added = changes.added,
                    modified = changes.modified,
                    errors = changes.errors
                })
            end
            ClonedTables[wipedTableName] = true
        end
        return
    end

    -- Create new backup table
    local query = string.format('CREATE TABLE IF NOT EXISTS `%s` LIKE `%s`', wipedTableName, originalTable)
    MySQL.query.await(query)
    
    -- Mark as cloned and log creation
    if not ClonedTables[wipedTableName] then
        table.insert(InitializationLogs, {
            type = 'created',
            table = wipedTableName
        })
        ClonedTables[wipedTableName] = true
    end
end

local function initializeBackupTables()
    -- Create logs table if not exists
    createLogsTable()
    
    -- Migrate logs table schema if needed (add transfer_target columns)
    local columns = getTableColumns('character_manager_logs')
    local columnNames = {}
    if columns then
        for _, col in ipairs(columns) do
            columnNames[string.lower(col.COLUMN_NAME)] = true
        end
    end
    
    if not columnNames['transfer_target_identifier'] then
        print('^2[character-manager] [DB] Migrating logs table - adding transfer_target_identifier column^7')
        MySQL.query.await('ALTER TABLE `character_manager_logs` ADD COLUMN `transfer_target_identifier` VARCHAR(100) DEFAULT NULL')
    end
    
    if not columnNames['transfer_target_name'] then
        print('^2[character-manager] [DB] Migrating logs table - adding transfer_target_name column^7')
        MySQL.query.await('ALTER TABLE `character_manager_logs` ADD COLUMN `transfer_target_name` VARCHAR(100) DEFAULT NULL')
    end
    
    -- Reset initialization logs
    InitializationLogs = {}
    
    local tables = getTablesToBackup()
    local stats = {
        total = #tables,
        identified = 0,
        warnings = 0
    }
    
    for _, tableName in ipairs(tables) do
        local metadata = analyzeTableStructure(tableName)
        
        if metadata.exists then
            createWipedTable(tableName)
            
            if metadata.identifierColumn then
                stats.identified = stats.identified + 1
                table.insert(InitializationLogs, {
                    type = 'identified',
                    table = tableName,
                    column = metadata.identifierColumn
                })
            else
                stats.warnings = stats.warnings + 1
                table.insert(InitializationLogs, {
                    type = 'warning',
                    table = tableName
                })
            end
        end
    end
    
    -- Display summary
    print('^5========================================^7')
    print('^6[character-manager] Initialization Complete^7')
    print('^5========================================^7')
    print(string.format('^2✓ Tables processed: %d^7', stats.total))
    print(string.format('^2✓ Tables identified: %d^7', stats.identified))
    
    -- Count created and synchronized tables
    local created = 0
    local synchronized = 0
    local totalColumnsAdded = 0
    local totalColumnsModified = 0
    local totalErrors = 0
    
    for _, log in ipairs(InitializationLogs) do
        if log.type == 'created' then
            created = created + 1
        elseif log.type == 'sync' then
            synchronized = synchronized + 1
            totalColumnsAdded = totalColumnsAdded + (log.added or 0)
            totalColumnsModified = totalColumnsModified + (log.modified or 0)
            totalErrors = totalErrors + (log.errors or 0)
        end
    end
    
    if created > 0 then
        print(string.format('^3✓ Backup tables created: %d^7', created))
    end
    
    if synchronized > 0 then
        print(string.format('^3✓ Tables synchronized: %d^7', synchronized))
        if totalColumnsAdded > 0 then
            print(string.format('  └─ Columns added: %d^7', totalColumnsAdded))
        end
        if totalColumnsModified > 0 then
            print(string.format('  └─ Columns modified: %d^7', totalColumnsModified))
        end
        if totalErrors > 0 then
            print(string.format('  └─ ^1Errors: %d^7', totalErrors))
        end
    end
    
    if stats.warnings > 0 then
        print(string.format('^1⚠ Warnings: %d tables without identifier column^7', stats.warnings))
    end
    
    print('^5========================================^7')
end

local function backupPlayerData(identifier, citizenId)
    if not identifier then
        return false
    end

    local tables = getTablesToBackup()
    
    for _, tableName in ipairs(tables) do
        local metadata = analyzeTableStructure(tableName)
        
        if metadata.exists and metadata.identifierColumn then
            local wipedTableName = 'wiped_' .. tableName
            
            if tableExists(wipedTableName) then
                local query = string.format(
                    'INSERT INTO `%s` SELECT * FROM `%s` WHERE `%s` = ?',
                    wipedTableName,
                    tableName,
                    metadata.identifierColumn
                )
                
                MySQL.query.await(query, { identifier })
            end
        end
    end
    
    return true
end

-- Initialize backup tables on resource start
CreateThread(function()
    while FrameworkName == nil do
        Wait(250)
    end
    
    Wait(1000)
    detectPhoneSource()
    initializeBackupTables()
end)

-- Export functions globally for use in other scripts
DatabaseModule = {
    getTablesToBackup = getTablesToBackup,
    backupPlayerData = backupPlayerData,
    tableExists = tableExists,
    analyzeTableStructure = analyzeTableStructure,
    findIdentifierColumn = findIdentifierColumn,
    shouldExcludeTable = shouldExcludeTable,
    getExcludedTables = getExcludedTables,
    compareTableStructures = compareTableStructures,
    synchronizeTableStructure = synchronizeTableStructure,
    logWipeAction = logWipeAction,
    logRestoreAction = logRestoreAction,
    getPlayerLogs = getPlayerLogs,
    getPhoneForPlayer = getPhoneForPlayer,
    wipePlayerAllTables = wipePlayerAllTables,
    restorePlayerAllTables = restorePlayerAllTables
}
