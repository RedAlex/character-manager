local CURRENT_VERSION = GetResourceMetadata(GetCurrentResourceName(), 'version') or '0.0.0'
local GITHUB_REPO = 'RedAlex/character-manager'
local GITHUB_RELEASE_API = 'https://api.github.com/repos/' .. GITHUB_REPO .. '/releases/latest'
local GITHUB_RELEASES_URL = 'https://github.com/' .. GITHUB_REPO .. '/releases'

local function normalizeVersion(version)
    if not version then
        return '0.0.0'
    end

    local normalized = tostring(version):gsub('^v', ''):match('([%d%.]+)')
    return normalized or '0.0.0'
end

local function compareVersions(v1, v2)
    local parts1 = {}
    local parts2 = {}

    for part in normalizeVersion(v1):gmatch('[^.]+') do
        table.insert(parts1, tonumber(part) or 0)
    end

    for part in normalizeVersion(v2):gmatch('[^.]+') do
        table.insert(parts2, tonumber(part) or 0)
    end

    local maxParts = math.max(#parts1, #parts2)
    for i = 1, maxParts do
        local p1 = parts1[i] or 0
        local p2 = parts2[i] or 0

        if p1 > p2 then
            return 1
        end

        if p1 < p2 then
            return -1
        end
    end

    return 0
end

local function checkForUpdates()
    if Config.EnableUpdateCheck == false then
        return
    end

    PerformHttpRequest(GITHUB_RELEASE_API, function(errorCode, resultData)
        if errorCode == 200 then
            local success, response = pcall(json.decode, resultData)
            if not success or not response then
                print('^3[character-manager] Update check failed: invalid GitHub response^7')
                return
            end

            local latestVersion = normalizeVersion(response.tag_name or response.name)
            local currentVersion = normalizeVersion(CURRENT_VERSION)
            local releaseUrl = response.html_url or GITHUB_RELEASES_URL

            if compareVersions(latestVersion, currentVersion) > 0 then
                print('^2========================================^7')
                print('^3[character-manager] Update available!^7')
                print('^1Current version: ^7' .. currentVersion)
                print('^2Latest version: ^7' .. latestVersion)
                print('^4Download: ^7' .. releaseUrl)
                print('^2========================================^7')
            else
                print('^2[character-manager] Up to date (v' .. currentVersion .. ')^7')
            end
        elseif errorCode == 404 then
            print('^3[character-manager] Update check skipped: no GitHub release found yet^7')
        else
            print('^3[character-manager] Update check failed (HTTP ' .. tostring(errorCode) .. ')^7')
        end
    end, 'GET', '', {
        ['User-Agent'] = 'character-manager-update-checker',
        ['Accept'] = 'application/vnd.github+json'
    })
end

CreateThread(function()
    Wait(2000)
    checkForUpdates()
end)
