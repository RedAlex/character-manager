Config = {
    Language        = 'en',     -- Language of the script (en, fr, de, es, it, nl, pt, pt-br, tr, cs, da, sv, pl, ro)
    Permission      = 'admin',  -- Permission to use the command
    VehTransfert    = true,     -- Transfer vehicles to another character when wiping
    SafeWipeMode    = true,     -- true = backup to wiped_* before delete, false = direct delete without backup
    EnableUpdateCheck = true,   -- Check GitHub releases on resource start
    WebhookURL      = '',       -- Discord webhook URL for logging (leave empty to disable)
    
    -- Tables to exclude from wipe/restore operations (optional manual additions)
    -- Add custom tables here if you want to exclude them from wipe/restore
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