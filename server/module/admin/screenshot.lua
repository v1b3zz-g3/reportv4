-- server/module/admin/screenshot.lua - Enhanced version with better error handling

---@type table<integer, number> Screenshot cooldowns per source
local screenshotCooldowns = {}
---@type table<integer, boolean> Active screenshot requests (prevents duplicates)
local activeScreenshots = {}
local SCREENSHOT_COOLDOWN = 10000 -- Increased to 10 seconds

---Check if on cooldown
local function isOnScreenshotCooldown(source)
    local now = GetGameTimer()
    if screenshotCooldowns[source] and now < screenshotCooldowns[source] then
        local remaining = math.ceil((screenshotCooldowns[source] - now) / 1000)
        return true, remaining
    end
    return false, 0
end

---Set cooldown
local function setScreenshotCooldown(source)
    screenshotCooldowns[source] = GetGameTimer() + SCREENSHOT_COOLDOWN
end

---Check if screenshot already in progress
local function isScreenshotInProgress(source)
    return activeScreenshots[source] == true
end

---Mark screenshot as in progress
local function setScreenshotInProgress(source, inProgress)
    activeScreenshots[source] = inProgress or nil
end

---Try screenshot-basic with enhanced error handling
local function tryScreenshotBasic(targetSource, callback)
    local resourceState = GetResourceState("screenshot-basic")
    
    print(("^3[screenshot] Attempting screenshot-basic for source %d^0"):format(targetSource))
    print(("^3[screenshot] screenshot-basic state: %s^0"):format(resourceState))
    
    if resourceState ~= "started" then
        print("^1[screenshot] screenshot-basic is not started!^0")
        return false, "screenshot-basic not running"
    end
    
    -- Verify player exists
    local playerName = GetPlayerName(targetSource)
    if not playerName then
        print("^1[screenshot] Player not found!^0")
        return false, "Player not found"
    end
    
    print(("^2[screenshot] Player found: %s^0"):format(playerName))
    
    -- Verify export exists
    local hasExport = pcall(function()
        local test = exports["screenshot-basic"]
        return test ~= nil
    end)
    
    if not hasExport then
        print("^1[screenshot] screenshot-basic export not accessible!^0")
        return false, "Export not accessible"
    end
    
    print("^2[screenshot] Export accessible, requesting screenshot...^0")
    
    -- Create timeout tracker
    local completed = false
    local timeoutTimer = SetTimeout(10000, function()
        if not completed then
            completed = true
            print(("^1[screenshot] Request TIMED OUT after 10 seconds for source %d^0"):format(targetSource))
            callback(false, nil, "Screenshot timeout - try again or contact an admin if issue persists")
        end
    end)
    
    -- Wrap in pcall
    local success, err = pcall(function()
        print(("^3[screenshot] Calling requestClientScreenshot for source %d...^0"):format(targetSource))
        
        exports["screenshot-basic"]:requestClientScreenshot(targetSource, {
            encoding = "jpg",
            quality = 0.85
        }, function(captureErr, data)
            print(("^3[screenshot] Callback received for source %d^0"):format(targetSource))
            
            if completed then
                print("^3[screenshot] Already timed out, ignoring callback^0")
                return
            end
            
            completed = true
            ClearTimeout(timeoutTimer)
            
            if captureErr then
                print(("^1[screenshot] Capture error for source %d: %s^0"):format(targetSource, tostring(captureErr)))
                callback(false, nil, "Screenshot capture failed: " .. tostring(captureErr))
                return
            end
            
            if not data or #data < 100 then
                print(("^1[screenshot] Invalid data received for source %d^0"):format(targetSource))
                callback(false, nil, "Invalid screenshot data received")
                return
            end
            
            print(("^2[screenshot] SUCCESS for source %d! Captured %d bytes^0"):format(targetSource, #data))
            callback(true, data, nil)
        end)
        
        print("^3[screenshot] requestClientScreenshot call completed (waiting for callback)^0")
    end)
    
    if not success then
        if not completed then
            completed = true
            ClearTimeout(timeoutTimer)
        end
        print(("^1[screenshot] Exception during request for source %d: %s^0"):format(targetSource, tostring(err)))
        return false, tostring(err)
    end
    
    return true, nil
end

---Try native screenshot method
local function tryNativeScreenshot(targetSource, callback)
    print(("^3[screenshot] Trying native screenshot method for source %d^0"):format(targetSource))
    
    -- Request client to take screenshot using game natives
    TriggerClientEvent("sws-report:takeNativeScreenshot", targetSource)
    
    -- Wait for response
    local completed = false
    local timeoutTimer = SetTimeout(12000, function()
        if not completed then
            completed = true
            print(("^1[screenshot] Native screenshot timeout for source %d^0"):format(targetSource))
            callback(false, nil, "Native screenshot timeout")
        end
    end)
    
    -- Listen for response
    local eventHandler = nil
    eventHandler = RegisterNetEvent("sws-report:nativeScreenshotData", function(data)
        local source = source
        
        if source == targetSource and not completed then
            completed = true
            ClearTimeout(timeoutTimer)
            RemoveEventHandler(eventHandler)
            
            if data and #data > 100 then
                print(("^2[screenshot] Native screenshot success for source %d: %d bytes^0"):format(targetSource, #data))
                callback(true, data, nil)
            else
                print(("^1[screenshot] Native screenshot failed for source %d - no data^0"):format(targetSource))
                callback(false, nil, "Screenshot failed - please try again")
            end
        end
    end)
end

---Upload screenshot to Discord
local function uploadToDiscord(imageData, reportId, playerName, callback)
    if not Config.Discord.enabled or not Config.Discord.forumWebhook then
        callback(false, nil, "Discord not configured")
        return
    end

    local threadId = exports["sws-report"]:GetReportThreadId(reportId)
    if not threadId then
        callback(false, nil, "No Discord thread found for this report")
        return
    end

    print(("^3[screenshot] Uploading to Discord thread %s for report #%d^0"):format(threadId, reportId))

    exports["sws-report"]:uploadScreenshotToDiscord({
        webhookUrl = Config.Discord.forumWebhook,
        threadId = threadId,
        base64Image = imageData,
        playerName = playerName,
        reportId = reportId,
        botName = Config.Discord.botName or "Report System",
        botAvatar = Config.Discord.botAvatar or ""
    }, function(success, url, errorMsg)
        if success and url then
            print(("^2[screenshot] Discord upload SUCCESS: %s^0"):format(url))
            callback(true, url, nil)
        else
            print(("^1[screenshot] Discord upload FAILED: %s^0"):format(errorMsg or "Unknown"))
            callback(false, nil, errorMsg or "Discord upload failed")
        end
    end)
end

---Main screenshot handler - tries multiple methods with user feedback
local function captureScreenshot(targetSource, reportId, playerName, onComplete)
    print(("^3========== Starting screenshot for source %d (Report #%d) ==========^0"):format(targetSource, reportId))
    
    -- Notify user that screenshot is starting
    NotifyPlayer(targetSource, "Taking screenshot... Please wait.", "info")
    
    -- Try screenshot-basic first
    local basicSuccess, basicError = tryScreenshotBasic(targetSource, function(success, data, err)
        if success and data then
            print(("^2[screenshot] screenshot-basic method succeeded for source %d^0"):format(targetSource))
            
            -- Upload to Discord
            uploadToDiscord(data, reportId, playerName, function(uploadSuccess, url, uploadErr)
                if uploadSuccess then
                    onComplete(true, data, url)
                else
                    -- Screenshot captured but upload failed
                    onComplete(true, data, nil)
                    NotifyPlayer(targetSource, "Screenshot captured but Discord upload failed", "info")
                end
            end)
        else
            print(("^1[screenshot] screenshot-basic failed for source %d: %s^0"):format(targetSource, err or "Unknown"))
            print("^3[screenshot] Trying native screenshot method...^0")
            
            -- Notify user we're trying another method
            NotifyPlayer(targetSource, "First method failed, trying alternative...", "info")
            
            -- Try native method as fallback
            tryNativeScreenshot(targetSource, function(nativeSuccess, nativeData, nativeErr)
                if nativeSuccess and nativeData then
                    print(("^2[screenshot] Native method succeeded for source %d^0"):format(targetSource))
                    
                    uploadToDiscord(nativeData, reportId, playerName, function(uploadSuccess, url, uploadErr)
                        if uploadSuccess then
                            onComplete(true, nativeData, url)
                        else
                            onComplete(true, nativeData, nil)
                            NotifyPlayer(targetSource, "Screenshot captured but Discord upload failed", "info")
                        end
                    end)
                else
                    print(("^1[screenshot] All methods failed for source %d^0"):format(targetSource))
                    onComplete(false, nil, nil, err or "Screenshot failed - please try again or contact an admin")
                end
            end)
        end
    end)
    
    if not basicSuccess then
        print(("^1[screenshot] Could not start screenshot-basic for source %d: %s^0"):format(targetSource, basicError))
        print("^3[screenshot] Falling back to native method immediately^0")
        
        NotifyPlayer(targetSource, "Trying alternative screenshot method...", "info")
        
        tryNativeScreenshot(targetSource, function(nativeSuccess, nativeData, nativeErr)
            if nativeSuccess and nativeData then
                uploadToDiscord(nativeData, reportId, playerName, function(uploadSuccess, url, uploadErr)
                    if uploadSuccess then
                        onComplete(true, nativeData, url)
                    else
                        onComplete(true, nativeData, nil)
                    end
                end)
            else
                onComplete(false, nil, nil, nativeErr or "All screenshot methods failed")
            end
        end)
    end
end

---User screenshot request (from chat button)
RegisterNetEvent("sws-report:requestUserScreenshot", function(reportId)
    local source = source

    print(("^3[screenshot] User screenshot request from source %d for report #%d^0"):format(source, reportId))

    if not IsValidReportId(reportId) then
        print("^1[screenshot] Invalid report ID^0")
        NotifyPlayer(source, "Invalid report ID", "error")
        return
    end

    -- CRITICAL: Check if screenshot already in progress
    if isScreenshotInProgress(source) then
        print(("^1[screenshot] BLOCKED - Screenshot already in progress for source %d^0"):format(source))
        NotifyPlayer(source, "Screenshot already in progress, please wait...", "error")
        return
    end

    -- CRITICAL: Check cooldown with remaining time
    local onCooldown, remaining = isOnScreenshotCooldown(source)
    if onCooldown then
        print(("^1[screenshot] BLOCKED - Cooldown active for source %d (%d seconds remaining)^0"):format(source, remaining))
        NotifyPlayer(source, string.format("Please wait %d seconds before taking another screenshot.", remaining), "error")
        return
    end

    local player = GetPlayerData(source)
    if not player then
        print("^1[screenshot] Player data not found^0")
        NotifyPlayer(source, "Player data error", "error")
        return
    end

    local report = Reports[reportId]
    if not report then
        NotifyPlayer(source, L("error_not_found"), "error")
        return
    end

    local isAdmin = IsPlayerAdmin(source)
    local isOwner = report:getPlayerId() == player.identifier

    if not isAdmin and not isOwner then
        NotifyPlayer(source, L("error_no_permission"), "error")
        return
    end

    -- Mark as in progress BEFORE starting
    setScreenshotInProgress(source, true)
    setScreenshotCooldown(source)
    
    print(("^2[screenshot] STARTING screenshot for source %d - marked as in progress^0"):format(source))
    NotifyPlayer(source, "Starting screenshot capture...", "info")

    captureScreenshot(source, reportId, player.name, function(success, imageData, discordUrl, errorMsg)
        -- CRITICAL: Clear in-progress flag when done
        setScreenshotInProgress(source, false)
        print(("^2[screenshot] COMPLETED for source %d - cleared in-progress flag^0"):format(source))
        
        if success and imageData then
            -- Send to client
            TriggerClientEvent("sws-report:screenshotCaptured", source, {
                reportId = reportId,
                imageData = imageData,
                discordUrl = discordUrl
            })
            
            -- Save to chat if Discord worked
            if discordUrl then
                SendMessageWithImage(reportId, player, discordUrl)
                TriggerEvent("sws-report:discord:screenshot", reportId, player.name, discordUrl, player.name)
                NotifyPlayer(source, "Screenshot uploaded successfully!", "success")
            else
                NotifyPlayer(source, "Screenshot captured (Discord upload failed)", "info")
            end
        else
            local errorMessage = errorMsg or "Screenshot failed - please try again"
            NotifyPlayer(source, errorMessage, "error")
            print(("^1[screenshot] Final error for source %d: %s^0"):format(source, errorMessage))
        end
    end)
end)

-- Admin screenshot
function ScreenshotPlayer(adminSource, reportId)
    local report = Reports[reportId]
    if not report then
        NotifyPlayer(adminSource, L("error_not_found"), "error")
        return
    end

    local playerData = GetPlayerByIdentifier(report:getPlayerId())
    if not playerData then
        NotifyPlayer(adminSource, L("player_offline"), "error")
        return
    end

    -- Check if screenshot already in progress for target player
    if isScreenshotInProgress(playerData.source) then
        NotifyPlayer(adminSource, "Screenshot already in progress for this player - please wait.", "error")
        return
    end

    -- Check cooldown
    local onCooldown, remaining = isOnScreenshotCooldown(playerData.source)
    if onCooldown then
        NotifyPlayer(adminSource, string.format("Screenshot cooldown active - wait %d seconds.", remaining), "error")
        return
    end

    setScreenshotInProgress(playerData.source, true)
    setScreenshotCooldown(playerData.source)
    
    NotifyPlayer(adminSource, "Screenshot requested...", "info")
    NotifyPlayer(playerData.source, "An admin is taking a screenshot of your screen...", "info")

    captureScreenshot(playerData.source, reportId, playerData.name, function(success, imageData, discordUrl, errorMsg)
        -- Clear in-progress flag
        setScreenshotInProgress(playerData.source, false)
        
        if success then
            TriggerClientEvent("sws-report:showScreenshotPopup", adminSource, {
                imageData = imageData,
                playerName = playerData.name,
                reportId = reportId,
                discordUrl = discordUrl
            })
            NotifyPlayer(adminSource, L("screenshot_received", playerData.name), "success")
        else
            local errorMessage = errorMsg or "Screenshot failed"
            NotifyPlayer(adminSource, errorMessage, "error")
            NotifyPlayer(playerData.source, "Screenshot failed - contact admin if this persists", "info")
        end
    end)
end

-- Cleanup on player disconnect
AddEventHandler("playerDropped", function()
    local source = source
    screenshotCooldowns[source] = nil
    activeScreenshots[source] = nil
end)

-- Debug command
RegisterCommand("screenshotdebug", function(source)
    if source == 0 then
        print("^3========== Screenshot System Debug ==========^0")
        print("screenshot-basic state: " .. GetResourceState("screenshot-basic"))
        
        local hasExport = pcall(function()
            return exports["screenshot-basic"] ~= nil
        end)
        print("Export accessible: " .. tostring(hasExport))
        
        print("Discord enabled: " .. tostring(Config.Discord.enabled))
        print("Webhook set: " .. tostring(Config.Discord.forumWebhook ~= nil and Config.Discord.forumWebhook ~= ""))
        print("^3============================================^0")
        return
    end
    
    if not IsPlayerAdmin(source) then return end
    
    local debugInfo = string.format(
        "Screenshot Debug:\nscreenshot-basic: %s\nDiscord: %s\nYour source ID: %d",
        GetResourceState("screenshot-basic"),
        tostring(Config.Discord.enabled and Config.Discord.forumWebhook ~= ""),
        source
    )
    
    NotifyPlayer(source, debugInfo, "info")
    
    -- Log to server console for this specific player
    print(("^3[screenshot] Debug for source %d (%s):^0"):format(source, GetPlayerName(source)))
    print(("^3[screenshot] - screenshot-basic: %s^0"):format(GetResourceState("screenshot-basic")))
    print(("^3[screenshot] - Discord configured: %s^0"):format(tostring(Config.Discord.enabled and Config.Discord.forumWebhook ~= "")))
end, false)

CreateThread(function()
    Wait(3000)
    print("^3[screenshot] Enhanced module loaded with detailed error handling^0")
    print("^3[screenshot] screenshot-basic state: " .. GetResourceState("screenshot-basic") .. "^0")
    print("^3[screenshot] Use /screenshotdebug command for diagnostics^0")
end)