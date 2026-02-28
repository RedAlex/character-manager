Config = Config or {}

-- Server-side configuration for character-manager
ConfigServer = {
    EnableUpdateCheck = true,   -- Check GitHub releases on resource start
    WebhookURL      = '',       -- Discord webhook URL for logging (leave empty to disable)

    -- Tables to exclude from wipe/restore operations (optional manual additions)
    ExcludedTables = {
        'character_manager_logs',  -- Never wipe character-manager logs
        'ox_lib',                   -- ox_lib data
        'ox_email',                 -- Email system
        'ox_appearance',            -- Character appearance (ox_appearance)
        'metadata',                 -- Metadata storage
        'registry',                 -- Registry data
        'discord_blacklist',        -- Discord bans
        'staff_list',               -- Staff list
    }
}


for k, v in pairs(ConfigServer) do
    if Config[k] == nil then
        Config[k] = v
    end
end