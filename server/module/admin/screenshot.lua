-- server/module/admin/screenshot.lua - ALTERNATIVE SOLUTION
-- This version uses a different approach to avoid screenshot-basic issues

---@type table<integer, number> Screenshot cooldowns per source
local screenshotCooldowns = {}
local SCREENSHOT_COOLDOWN = 5000

---Check if on cooldown
local function isOnScreenshotCooldown(source)
    local now = GetGameTimer()
    if screenshotCooldowns[source] and now < screenshotCooldowns[source] then
        return true
    end
    return false
end

---Set cooldown
local function setScreenshotCooldown(source)
    screenshotCooldowns[source] = GetGameTimer() + SCREENSHOT_COOLDOWN
end

---Alternative 1: Try screenshot-basic with better error handling
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
    
    -- Try to get the export
    local hasExport = pcall(function()
        local test = exports["screenshot-basic"]
        return test ~= nil
    end)
    
    if not hasExport then
        print("^1[screenshot] screenshot-basic export not accessible!^0")
        return false, "Export not accessible"
    end
    
    print("^2[screenshot] Export accessible, requesting screenshot...^0")
    
    -- Create a timeout tracker
    local completed = false
    local timeoutTimer = SetTimeout(10000, function()
        if not completed then
            completed = true
            print("^1[screenshot] Request TIMED OUT after 10 seconds^0")
            callback(false, nil, "Timeout - screenshot-basic not responding")
        end
    end)
    
    -- Wrap in pcall to catch any errors
    local success, err = pcall(function()
        print("^3[screenshot] Calling requestClientScreenshot...^0")
        
        exports["screenshot-basic"]:requestClientScreenshot(targetSource, {
            encoding = "jpg",
            quality = 0.85
        }, function(captureErr, data)
            print("^3[screenshot] Callback received!^0")
            
            if completed then
                print("^3[screenshot] Already timed out, ignoring callback^0")
                return
            end
            
            completed = true
            ClearTimeout(timeoutTimer)
            
            if captureErr then
                print(("^1[screenshot] Capture error: %s^0"):format(tostring(captureErr)))
                callback(false, nil, tostring(captureErr))
                return
            end
            
            if not data or #data < 100 then
                print("^1[screenshot] Invalid data received^0")
                callback(false, nil, "Invalid screenshot data")
                return
            end
            
            print(("^2[screenshot] SUCCESS! Captured %d bytes^0"):format(#data))
            callback(true, data, nil)
        end)
        
        print("^3[screenshot] requestClientScreenshot call completed (waiting for callback)^0")
    end)
    
    if not success then
        if not completed then
            completed = true
            ClearTimeout(timeoutTimer)
        end
        print(("^1[screenshot] Exception during request: %s^0"):format(tostring(err)))
        return false, tostring(err)
    end
    
    return true, nil
end

---Alternative 2: Use game native screenshot (doesn't require screenshot-basic)
local function tryNativeScreenshot(targetSource, callback)
    print("^3[screenshot] Trying native screenshot method^0")
    
    -- Request client to take screenshot using game natives
    TriggerClientEvent("sws-report:takeNativeScreenshot", targetSource)
    
    -- Wait for response
    local completed = false
    local timeoutTimer = SetTimeout(10000, function()
        if not completed then
            completed = true
            callback(false, nil, "Native screenshot timeout")
        end
    end)
    
    -- Listen for response (we'll add the client event handler later)
    local eventHandler = nil
    eventHandler = RegisterNetEvent("sws-report:nativeScreenshotData", function(data)
        local source = source
        
        if source == targetSource and not completed then
            completed = true
            ClearTimeout(timeoutTimer)
            RemoveEventHandler(eventHandler)
            
            if data and #data > 100 then
                print(("^2[screenshot] Native screenshot success: %d bytes^0"):format(#data))
                callback(true, data, nil)
            else
                print("^1[screenshot] Native screenshot failed - no data^0")
                callback(false, nil, "No screenshot data")
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
        callback(false, nil, "No Discord thread")
        return
    end

    print(("^3[screenshot] Uploading to Discord thread %s^0"):format(threadId))

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
            callback(false, nil, errorMsg)
        end
    end)
end

---Main screenshot handler - tries multiple methods
local function captureScreenshot(targetSource, reportId, playerName, onComplete)
    print(("^3========== Starting screenshot for source %d ==========^0"):format(targetSource))
    
    -- Try screenshot-basic first
    local basicSuccess, basicError = tryScreenshotBasic(targetSource, function(success, data, err)
        if success and data then
            print("^2[screenshot] screenshot-basic method succeeded^0")
            
            -- Upload to Discord
            uploadToDiscord(data, reportId, playerName, function(uploadSuccess, url, uploadErr)
                if uploadSuccess then
                    onComplete(true, data, url)
                else
                    -- Upload failed but we have the screenshot
                    onComplete(true, data, nil)
                end
            end)
        else
            print(("^1[screenshot] screenshot-basic failed: %s^0"):format(err or "Unknown"))
            print("^3[screenshot] Trying native screenshot method...^0")
            
            -- Try native method as fallback
            tryNativeScreenshot(targetSource, function(nativeSuccess, nativeData, nativeErr)
                if nativeSuccess and nativeData then
                    print("^2[screenshot] Native method succeeded^0")
                    
                    uploadToDiscord(nativeData, reportId, playerName, function(uploadSuccess, url, uploadErr)
                        if uploadSuccess then
                            onComplete(true, nativeData, url)
                        else
                            onComplete(true, nativeData, nil)
                        end
                    end)
                else
                    print(("^1[screenshot] Native method also failed: %s^0"):format(nativeErr or "Unknown"))
                    onComplete(false, nil, nil, "All screenshot methods failed")
                end
            end)
        end
    end)
    
    if not basicSuccess then
        print(("^1[screenshot] Could not start screenshot-basic: %s^0"):format(basicError))
        print("^3[screenshot] Falling back to native method^0")
        
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
                onComplete(false, nil, nil, "All methods failed")
            end
        end)
    end
end

---User screenshot request
RegisterNetEvent("sws-report:requestUserScreenshot", function(reportId)
    local source = source

    print(("^3[screenshot] User screenshot request from source %d for report #%d^0"):format(source, reportId))

    if not IsValidReportId(reportId) then
        print("^1[screenshot] Invalid report ID^0")
        return
    end

    local player = GetPlayerData(source)
    if not player then
        print("^1[screenshot] Player data not found^0")
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

    if isOnScreenshotCooldown(source) then
        NotifyPlayer(source, "Please wait before taking another screenshot.", "error")
        return
    end

    setScreenshotCooldown(source)
    NotifyPlayer(source, "Taking screenshot...", "info")

    captureScreenshot(source, reportId, player.name, function(success, imageData, discordUrl, errorMsg)
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
                NotifyPlayer(source, "Screenshot uploaded!", "success")
            else
                NotifyPlayer(source, "Screenshot captured (Discord upload failed)", "info")
            end
        else
            NotifyPlayer(source, "Screenshot failed: " .. (errorMsg or "Unknown error"), "error")
        end
    end)
end)

-- Admin screenshot (similar implementation)
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

    if isOnScreenshotCooldown(playerData.source) then
        NotifyPlayer(adminSource, L("screenshot_cooldown"), "error")
        return
    end

    setScreenshotCooldown(playerData.source)
    NotifyPlayer(adminSource, "Screenshot requested...", "info")

    captureScreenshot(playerData.source, reportId, playerData.name, function(success, imageData, discordUrl, errorMsg)
        if success then
            TriggerClientEvent("sws-report:showScreenshotPopup", adminSource, {
                imageData = imageData,
                playerName = playerData.name,
                reportId = reportId,
                discordUrl = discordUrl
            })
            NotifyPlayer(adminSource, L("screenshot_received", playerData.name), "success")
        else
            NotifyPlayer(adminSource, "Screenshot failed: " .. (errorMsg or "Unknown"), "error")
        end
    end)
end

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
    
    NotifyPlayer(source, string.format(
        "Screenshot Debug:\nscreenshot-basic: %s\nDiscord: %s",
        GetResourceState("screenshot-basic"),
        tostring(Config.Discord.enabled and Config.Discord.forumWebhook ~= "")
    ), "info")
end, false)

CreateThread(function()
    Wait(3000)
    print("^3[screenshot] Module loaded with fallback support^0")
    print("^3[screenshot] screenshot-basic state: " .. GetResourceState("screenshot-basic") .. "^0")
end)