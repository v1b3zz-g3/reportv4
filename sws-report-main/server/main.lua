---@type table<integer, PlayerData> Online players cache
Players = {}

---@type table<integer, boolean> Admin cache
Admins = {}

---@type table<integer, Report> Active reports cache
Reports = {}

---@type table<string, integer> Player cooldowns (identifier -> timestamp)
Cooldowns = {}

---@type boolean Whether voice message database columns exist
VoiceMessagesAvailable = false

---@class PlayerData
---@field source integer Server ID
---@field identifier string Player identifier
---@field name string Player name
---@field isAdmin boolean Admin status

---Get player primary identifier
---@param source integer Player server ID
---@return string | nil
local QBCore = exports['qb-core']:GetCoreObject()

local function getPlayerIdentifier(source)
    local identifiers = GetPlayerIdentifiers(source)

    for _, identifier in ipairs(identifiers) do
        if string.find(identifier, "license:") then
            return identifier
        end
    end

    for _, identifier in ipairs(identifiers) do
        if string.find(identifier, "steam:") then
            return identifier
        end
    end

    return identifiers[1]
end

---Get all player identifiers
---@param source integer Player server ID
---@return string[]
local function getAllIdentifiers(source)
    return GetPlayerIdentifiers(source) or {}
end

---Parse and save player identifiers to database
---@param source integer Player server ID
---@param primaryIdentifier string Primary identifier for this player
local function savePlayerIdentifiers(source, primaryIdentifier)
    local identifiers = GetPlayerIdentifiers(source) or {}
    local parsed = {
        license = nil,
        steam = nil,
        discord = nil,
        fivem = nil
    }

    for _, id in ipairs(identifiers) do
        if string.find(id, "license:") then
            parsed.license = id
        elseif string.find(id, "steam:") then
            parsed.steam = id
        elseif string.find(id, "discord:") then
            parsed.discord = id
        elseif string.find(id, "fivem:") then
            parsed.fivem = id
        end
    end

    -- Upsert into database
    MySQL.insert([[
        INSERT INTO player_identifiers (player_id, license, steam, discord, fivem)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            license = VALUES(license),
            steam = VALUES(steam),
            discord = VALUES(discord),
            fivem = VALUES(fivem)
    ]], { primaryIdentifier, parsed.license, parsed.steam, parsed.discord, parsed.fivem })
end

---Check if player is admin from database (SQL direct query)
---@param source integer Player server ID
---@return boolean
function IsPlayerAdmin(source)
    -- First check cache
    if Admins[source] == true then
        return true
    end

    -- Get identifier for SQL query
    local identifier = getPlayerIdentifier(source)
    if not identifier then
        return false
    end

    -- Query database directly for player group
    local result = MySQL.query.await([[
        SELECT `group` FROM players WHERE license = ? LIMIT 1
    ]], { identifier })

    if result and result[1] then
        local group = result[1].group or "user"
        
        print(("^3[ADMIN CHECK] Source: %d | License: %s | Group: %s^0"):format(source, identifier, group))
        
        -- Exclude non-admin groups
        local nonAdminGroups = {
            ["user"] = true,
            ["vip"] = true,
            ["vip2"] = true,
            ["vipmax"] = true
        }
        
        -- If group is NOT in the excluded list, they're an admin
        if not nonAdminGroups[group] then
            Admins[source] = true
            print(("^2[ADMIN GRANTED] Player %s is admin (group: %s)^0"):format(GetPlayerName(source), group))
            return true
        else
            print(("^1[ADMIN DENIED] Player %s is not admin (group: %s)^0"):format(GetPlayerName(source), group))
            return false
        end
    end
    
    print(("^1[ADMIN CHECK] No database record found for %s^0"):format(identifier))
    return false
end

---Update admin status and notify client
---@param source integer Player server ID
local function updateAdminStatus(source)
    local wasAdmin = Admins[source] or false
    local isNowAdmin = IsPlayerAdmin(source)
    
    Admins[source] = isNowAdmin
    
    if Players[source] then
        Players[source].isAdmin = isNowAdmin
        
        -- Send updated data to client
        TriggerClientEvent("sws-report:setPlayerData", source, {
            identifier = Players[source].identifier,
            name = Players[source].name,
            isAdmin = isNowAdmin,
            voiceMessagesEnabled = VoiceMessagesAvailable and Config.VoiceMessages.enabled
        })
        
        -- If admin status changed
        if isNowAdmin and not wasAdmin then
            -- New admin - send all active reports
            local allActiveReports = GetActiveReports()
            TriggerClientEvent("sws-report:setAllReports", source, allActiveReports)
            NotifyPlayer(source, "Admin permissions granted", "success")
            DebugPrint(("Admin permissions granted to %s"):format(Players[source].name))
        elseif not isNowAdmin and wasAdmin then
            NotifyPlayer(source, "Admin permissions revoked", "info")
            DebugPrint(("Admin permissions revoked from %s"):format(Players[source].name))
        end
    end
end

---Handle QBCore group updates (when admin does /setgroup)
RegisterNetEvent("QBCore:Server:OnGroupUpdate", function(src, newGroup)
    local source = src or source
    
    print(("^5========== GROUP UPDATE ==========^0"))
    print(("^3Source:^0 %d"):format(source))
    print(("^3New Group:^0 %s"):format(newGroup))
    
    -- Clear cache to force re-check
    Admins[source] = nil
    
    -- Re-check admin status with new group
    if newGroup ~="user" and newGroup ~="vip" and newGroup ~="vip2" and newGroup ~="vipmax" then
        Admins[source] = true
    end
    
    print(("^3Is Admin:^0 %s"):format(tostring(isNowAdmin)))
    print(("^5==================================^0"))
    
    if Players[source] then
        updateAdminStatus(source)
    end
end)

---Alternative event names for different QBCore versions
RegisterNetEvent("QBCore:Server:SetPermission", function(src, permission)
    local source = src or source
    print(("^3[PERMISSION UPDATE] Source: %d | Permission: %s^0"):format(source, permission))
    
    if Players[source] then
        Admins[source] = nil -- Clear cache
        updateAdminStatus(source)
    end
end)

---Listen for any permission changes
AddEventHandler("QBCore:Server:OnPermissionUpdate", function(src)
    local source = src or source
    print(("^3[PERMISSION REFRESH] Source: %d^0"):format(source))
    
    if Players[source] then
        Admins[source] = nil -- Clear cache
        updateAdminStatus(source)
    end
end)

---Get player data
---@param source integer Player server ID
---@return PlayerData | nil
function GetPlayerData(source)
    return Players[source]
end

---Get player by identifier
---@param identifier string Player identifier
---@return PlayerData | nil
function GetPlayerByIdentifier(identifier)
    for _, player in pairs(Players) do
        if player.identifier == identifier then
            return player
        end
    end
    return nil
end

---Check if player is online by identifier
---@param identifier string Player identifier
---@return boolean
function IsPlayerOnline(identifier)
    return GetPlayerByIdentifier(identifier) ~= nil
end

---Get all online admins
---@return PlayerData[]
function GetOnlineAdmins()
    local admins = {}
    for source, isAdmin in pairs(Admins) do
        if isAdmin and Players[source] then
            table.insert(admins, Players[source])
        end
    end
    return admins
end

---Notify player
---@param source integer Player server ID
---@param message string Notification message
---@param notifyType? string Notification type ("success" | "error" | "info")
function NotifyPlayer(source, message, notifyType)
    notifyType = notifyType or "info"

    -- Use custom notification if configured
    if Config.CustomNotify then
        local success = pcall(Config.CustomNotify, source, message, notifyType)
        if success then return end
        -- Fall through to default if custom fails
    end

    -- Default built-in notification
    TriggerClientEvent("sws-report:notify", source, message, notifyType)
end

---Notify all admins
---@param message string Notification message
---@param notifyType? string Notification type
---@param excludeSource? integer Source to exclude
function NotifyAdmins(message, notifyType, excludeSource)
    for source, isAdmin in pairs(Admins) do
        if isAdmin and source ~= excludeSource then
            NotifyPlayer(source, message, notifyType)
        end
    end
end

---Broadcast player online status to all admins
---@param identifier string Player identifier
---@param isOnline boolean Online status
local function broadcastPlayerOnlineStatus(identifier, isOnline)
    for adminSource, adminStatus in pairs(Admins) do
        if adminStatus then
            TriggerClientEvent("sws-report:playerOnlineStatus", adminSource, identifier, isOnline)
        end
    end
end

---Player connecting handler
AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
    local source = source
    DebugPrint(("Player connecting: %s (ID: %d)"):format(name, source))
end)

---Player joined handler - SQL-BASED ADMIN CHECK
RegisterNetEvent("sws-report:playerJoined", function()
    local source = source
    local identifier = getPlayerIdentifier(source)

    local rawName = GetPlayerName(source)
    
    -- CRITICAL FIX: Sanitize username properly
    local name = SanitizeUsername(rawName or "Unknown", 50)
    
    -- Also create a safe version for logs
    local logName = SanitizeUsernameForLog(rawName or "Unknown")

    if not identifier then
        PrintError(("Could not get identifier for player %d"):format(source))
        return
    end

    -- WAIT A BIT for player to spawn
    Wait(2000)

    -- SQL QUERY: Get player group directly from database
    local dbResult = MySQL.query.await([[
        SELECT `group`, citizenid FROM players WHERE license = ? LIMIT 1
    ]], { identifier })

    local playerGroup = "user"
    local isAdmin = false

    if dbResult and dbResult[1] then
        playerGroup = dbResult[1].group or "user"
        
        print(("^5========== PLAYER JOIN ==========^0"))
        print(("^3Name:^0 %s"):format(logName))
        print(("^3License:^0 %s"):format(identifier))
        print(("^3Group from DB:^0 %s"):format(playerGroup))
        
        -- Check if admin
        local nonAdminGroups = {
            ["user"] = true,
            ["vip"] = true,
            ["vip2"] = true,
            ["vipmax"] = true
        }
        
        isAdmin = not nonAdminGroups[playerGroup]
        
        if isAdmin then
            Admins[source] = true
            print(("^2✓ ADMIN GRANTED^0"))
        else
            print(("^1✗ NOT ADMIN^0"))
        end
        print(("^5================================^0"))
    else
        print(("^1[ERROR] No database record found for license: %s^0"):format(identifier))
    end

    -- Store player data
    Players[source] = {
        source = source,
        identifier = identifier,
        name = name,
        rawName = rawName,
        isAdmin = isAdmin
    }

    -- Save all player identifiers to database for offline lookup
    savePlayerIdentifiers(source, identifier)

    -- Send player data to client
    TriggerClientEvent("sws-report:setPlayerData", source, {
        identifier = identifier,
        name = name,
        isAdmin = isAdmin,
        voiceMessagesEnabled = VoiceMessagesAvailable and Config.VoiceMessages.enabled
    })

    -- Send player's own reports
    local playerReports = GetPlayerReports(identifier)
    if #playerReports > 0 then
        TriggerClientEvent("sws-report:setReports", source, playerReports)
    end

    -- If admin, send all reports
    if isAdmin then
        local allActiveReports = GetActiveReports()
        TriggerClientEvent("sws-report:setAllReports", source, allActiveReports)
        print(("^2[ADMIN] Sent %d active reports to %s^0"):format(#allActiveReports, logName))
    end

    broadcastPlayerOnlineStatus(identifier, true)
end)

---Player dropped handler
AddEventHandler("playerDropped", function(reason)
    local source = source

    if Players[source] then
        DebugPrint(("Player dropped: %s - Reason: %s"):format(Players[source].name, reason))
        broadcastPlayerOnlineStatus(Players[source].identifier, false)
    end

    Players[source] = nil
    Admins[source] = nil
end)

---Manual admin refresh command (for testing/debugging)
RegisterCommand("refreshadmin", function(source)
    if not source or source == 0 then return end
    
    print(("^5========== MANUAL ADMIN REFRESH ==========^0"))
    print(("^3Source:^0 %d"):format(source))
    print(("^3Name:^0 %s"):format(GetPlayerName(source)))
    
    -- Clear cache
    Admins[source] = nil
    
    -- Force re-check from database
    local identifier = getPlayerIdentifier(source)
    if identifier then
        local dbResult = MySQL.query.await([[
            SELECT `group` FROM players WHERE license = ? LIMIT 1
        ]], { identifier })
        
        if dbResult and dbResult[1] then
            local group = dbResult[1].group or "user"
            print(("^3Database Group:^0 %s"):format(group))
            
            local nonAdminGroups = {
                ["user"] = true,
                ["vip"] = true,
                ["vip2"] = true,
                ["vipmax"] = true
            }
            
            local isAdmin = not nonAdminGroups[group]
            Admins[source] = isAdmin
            
            if Players[source] then
                Players[source].isAdmin = isAdmin
            end
            
            print(("^3Is Admin:^0 %s"):format(tostring(isAdmin)))
            
            if isAdmin then
                print(("^2✓ ADMIN ACCESS GRANTED^0"))
            else
                print(("^1✗ NOT AN ADMIN^0"))
            end
        else
            print(("^1ERROR: No database record found^0"))
        end
    end
    
    print(("^5==========================================^0"))
    
    if Players[source] then
        updateAdminStatus(source)
    end
end, false)

---Compare semantic versions
---@param current string Current version (e.g. "1.0.0")
---@param latest string Latest version (e.g. "1.0.1")
---@return boolean isOutdated True if current < latest
local function isVersionOutdated(current, latest)
    local function parseVersion(v)
        local major, minor, patch = v:match("^(%d+)%.(%d+)%.(%d+)")
        return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
    end

    local curMajor, curMinor, curPatch = parseVersion(current)
    local latMajor, latMinor, latPatch = parseVersion(latest)

    if latMajor > curMajor then return true end
    if latMajor == curMajor and latMinor > curMinor then return true end
    if latMajor == curMajor and latMinor == curMinor and latPatch > curPatch then return true end

    return false
end

---Check if voice message database columns exist
---@return boolean
local function checkVoiceMigration()
    local result = MySQL.query.await([[
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'report_messages'
        AND COLUMN_NAME = 'message_type'
    ]])
    return result and #result > 0
end

---Print voice migration warning box
local function printVoiceMigrationWarning()
    print("^3╔══════════════════════════════════════════════════════════════╗^0")
    print("^3║^0              ^1VOICE MESSAGE MIGRATION REQUIRED^0               ^3║^0")
    print("^3╠══════════════════════════════════════════════════════════════╣^0")
    print("^3║^0  Voice message feature is ^1DISABLED^0 - database not migrated  ^3║^0")
    print("^3║^0                                                              ^3║^0")
    print("^3║^0  Run this SQL to enable voice messages:                      ^3║^0")
    print("^3║^0  ^5source sql/migrate_voice_messages.sql^0                       ^3║^0")
    print("^3║^0                                                              ^3║^0")
    print("^3║^0  Text messages continue to work normally.                    ^3║^0")
    print("^3╚══════════════════════════════════════════════════════════════╝^0")
end

---Check for updates from GitHub
local function checkForUpdates()
    local currentVersion = GetResourceMetadata(RESOURCE_NAME, "version", 0) or "0.0.0"
    local repoUrl = "https://raw.githubusercontent.com/SwisserDev/sws-report/main/fxmanifest.lua"

    PerformHttpRequest(repoUrl, function(statusCode, response)
        if statusCode ~= 200 or not response then
            PrintError("Failed to check for updates")
            return
        end

        local latestVersion = response:match('\nversion%s*"([^"]+)"')
        if not latestVersion then
            PrintError("Could not parse version from GitHub")
            return
        end

        if isVersionOutdated(currentVersion, latestVersion) then
            local boxWidth = 56
            local versionText = ("  Current: v%s  →  Latest: v%s"):format(currentVersion, latestVersion)
            local versionVisualLen = 26 + #currentVersion + #latestVersion 
            local versionPadding = string.rep(" ", boxWidth - versionVisualLen)

            print("^3╔════════════════════════════════════════════════════════╗^0")
            print("^3║^0             ^1UPDATE AVAILABLE^0 - ^5sws-report^0              ^3║^0")
            print("^3╠════════════════════════════════════════════════════════╣^0")
            print("^3║^0" .. versionText .. versionPadding .. "^3║^0")
            print("^3║^0  Download: ^4github.com/SwisserDev/sws-report/releases^0   ^3║^0")
            print("^3╚════════════════════════════════════════════════════════╝^0")
        else
            PrintInfo(("Running latest version v%s"):format(currentVersion))
        end
    end, "GET")
end

---Resource start handler
AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= RESOURCE_NAME then return end

    PrintInfo("Resource started - Loading reports from database...")

    LoadReportsFromDatabase()

    PrintInfo(("Loaded %d active reports"):format(GetActiveReportCount()))

    VoiceMessagesAvailable = checkVoiceMigration()
    if VoiceMessagesAvailable then
        if not Config.Discord.enabled or not Config.Discord.forumWebhook or Config.Discord.forumWebhook == "" then
            VoiceMessagesAvailable = false
            PrintWarn("Voice messages: disabled - Discord webhook required for audio storage")
            PrintWarn("Configure Config.Discord.enabled and Config.Discord.webhook to enable voice messages")
        else
            PrintInfo("Voice messages: enabled")
        end
    else
        printVoiceMigrationWarning()
    end

    checkForUpdates()
end)

---Resource stop handler
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= RESOURCE_NAME then return end

    PrintInfo("Resource stopping...")
end)

-- Exports
exports("IsAdmin", function(source)
    return IsPlayerAdmin(source)
end)

exports("GetOnlineAdmins", function()
    return GetOnlineAdmins()
end)

exports("GetPlayerData", function(source)
    return GetPlayerData(source)
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000) -- 5 minutes
        local now = os.time()
        local cleaned = 0
        for identifier, lastReport in pairs(Cooldowns) do
            if now - lastReport > Config.Cooldown then
                Cooldowns[identifier] = nil
                cleaned = cleaned + 1
            end
        end
        if cleaned > 0 then
            DebugPrint(("Cleaned up %d expired cooldown entries"):format(cleaned))
        end
    end
end)