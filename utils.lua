-- Server utils
-- Provides debugPrint(...) which only prints when Config.DebugMode == true

if not Config then
    Config = {}
end

function debugPrint(...)
    if Config and Config.DebugMode then
        print(...)
    end
end

return {}
