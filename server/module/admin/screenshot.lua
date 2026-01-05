-- server/module/admin/screenshot.lua
---@type boolean Whether screenshot-basic is available
local screenshotAvailable = GetResourceState("screenshot-basic") == "started"

---@type table<integer, number> Screenshot cooldowns per target source
local screenshotCooldowns = {}

---@type integer Screenshot cooldown in milliseconds
local SCREENSHOT_COOLDOWN = 5000

---Check if target is on screenshot cooldown
---@param targetSource integer Target player source
---@return boolean isOnCooldown
local function isOnScreenshotCooldown(targetSource)
    local now = GetGameTimer()
    if screenshotCooldowns[targetSource] and now < screenshotCooldowns[targetSource] then
        return true
    end
    return false
end

---Set screenshot cooldown for target
---@param targetSource integer Target player source
local function setScreenshotCooldown(targetSource)
    screenshotCooldowns[targetSource] = GetGameTimer() + SCREENSHOT_COOLDOWN
end

---Upload screenshot to Discord and send to admin
---@param imageData string Base64 screenshot data
---@param reportId integer Report ID
---@param playerName string Player name
---@param adminSource integer Admin who requested it
local function uploadAndShowScreenshot(imageData, reportId, playerName, adminSource)
    if not Config.Discord.enabled or not Config.Discord.forumWebhook or Config.Discord.forumWebhook == "" then
        -- No Discord, just show to admin
        TriggerClientEvent("sws-report:showScreenshotPopup", adminSource, {
            imageData = imageData,
            playerName = playerName,
            reportId = reportId
        })
        NotifyPlayer(adminSource, L("screenshot_received", playerName), "success")
        return
    end

    -- Get existing thread ID for this report
    local threadId = exports["sws-report"]:GetReportThreadId(reportId)
    if not threadId then
        PrintError(("No thread found for report #%d - cannot upload screenshot"):format(reportId))
        -- Still show to admin but without Discord upload
        TriggerClientEvent("sws-report:showScreenshotPopup", adminSource, {
            imageData = imageData,
            playerName = playerName,
            reportId = reportId
        })
        NotifyPlayer(adminSource, L("screenshot_received", playerName) .. " (Discord upload failed - no thread)", "info")
        return
    end

    -- Upload to Discord and show to admin
    exports["sws-report"]:uploadScreenshotToDiscord({
        webhookUrl = Config.Discord.forumWebhook,
        threadId = threadId,
        base64Image = imageData,
        playerName = playerName,
        reportId = reportId,
        botName = Config.Discord.botName,
        botAvatar = Config.Discord.botAvatar ~= "" and Config.Discord.botAvatar or nil
    }, function(success, url, errorMsg)
        -- Always show to admin regardless of Discord upload status
        TriggerClientEvent("sws-report:showScreenshotPopup", adminSource, {
            imageData = imageData,
            playerName = playerName,
            reportId = reportId,
            discordUrl = url
        })

        if success and url then
            DebugPrint(("Screenshot uploaded to Discord: %s"):format(url))
            NotifyPlayer(adminSource, L("screenshot_received", playerName), "success")
            
            -- Trigger Discord event to post to thread
            local admin = Players[adminSource]
            if admin then
                TriggerEvent("sws-report:discord:screenshot", reportId, playerName, url, admin.name)
            end
        else
            PrintError(("Screenshot Discord upload failed: %s"):format(errorMsg or "Unknown error"))
            NotifyPlayer(adminSource, L("screenshot_received", playerName) .. " (Discord upload failed)", "info")
        end
    end)
end

---Execute screenshot request and send directly to admin
---@param targetSource integer Target player source
---@param notifySource integer Source to notify on success/error
---@param reportId integer Report ID
---@param playerName string Player name
local function executeScreenshotRequest(targetSource, notifySource, reportId, playerName)
    Citizen.CreateThread(function()
        local success, err = pcall(function()
            exports["screenshot-basic"]:requestClientScreenshot(targetSource, {
                encoding = "jpg",
                quality = 0.85
            }, function(captureErr, data)
                if captureErr then
                    DebugPrint(("Screenshot capture failed: %s"):format(tostring(captureErr)))
                    NotifyPlayer(notifySource, L("screenshot_failed"), "error")
                    return
                end

                DebugPrint(("Screenshot captured for report #%d"):format(reportId))
                uploadAndShowScreenshot(data, reportId, playerName, notifySource)
            end)
        end)

        if not success then
            PrintError(("Screenshot request failed: %s"):format(tostring(err)))
            NotifyPlayer(notifySource, L("screenshot_failed"), "error")
        end
    end)
end

---Take screenshot of player (admin action)
---@param adminSource integer Admin server ID
---@param reportId integer Report ID
function ScreenshotPlayer(adminSource, reportId)
    if not screenshotAvailable then
        NotifyPlayer(adminSource, L("screenshot_unavailable"), "error")
        return
    end

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

    NotifyPlayer(adminSource, L("screenshot_requested"), "info")

    DebugPrint(("Admin %s requested screenshot from player %s (Report #%d)"):format(
        Players[adminSource].name,
        playerData.name,
        reportId
    ))

    executeScreenshotRequest(playerData.source, adminSource, reportId, playerData.name)

    TriggerEvent("sws-report:discord:adminAction", "screenshot_player", Players[adminSource], playerData, reportId)
end

---User requests to take their own screenshot (camera button in chat)
---@param reportId integer Report ID
RegisterNetEvent("sws-report:requestUserScreenshot", function(reportId)
    local source = source

    if not IsValidReportId(reportId) then
        return
    end

    if not screenshotAvailable then
        NotifyPlayer(source, L("screenshot_unavailable"), "error")
        return
    end

    local player = GetPlayerData(source)
    if not player then
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
        NotifyPlayer(source, L("screenshot_cooldown"), "error")
        return
    end

    setScreenshotCooldown(source)

    DebugPrint(("User %s taking screenshot for report %d"):format(player.name, reportId))

    -- Take screenshot and upload to Discord + send as message
    Citizen.CreateThread(function()
        local success, err = pcall(function()
            exports["screenshot-basic"]:requestClientScreenshot(source, {
                encoding = "jpg",
                quality = 0.85
            }, function(captureErr, data)
                if captureErr then
                    NotifyPlayer(source, L("screenshot_failed"), "error")
                    return
                end

                -- Send to Discord if enabled
                if Config.Discord.enabled and Config.Discord.forumWebhook and Config.Discord.forumWebhook ~= "" then
                    -- Get existing thread ID for this report
                    local threadId = exports["sws-report"]:GetReportThreadId(reportId)
                    if not threadId then
                        PrintError(("No thread found for report #%d - cannot upload screenshot"):format(reportId))
                        -- Fallback to base64 in chat without Discord upload
                        TriggerClientEvent("sws-report:screenshotCaptured", source, {
                            reportId = reportId,
                            imageData = data
                        })
                        NotifyPlayer(source, L("screenshot_uploaded"), "success")
                        return
                    end

                    exports["sws-report"]:uploadScreenshotToDiscord({
                        webhookUrl = Config.Discord.forumWebhook,
                        threadId = threadId,
                        base64Image = data,
                        playerName = player.name,
                        reportId = reportId,
                        botName = Config.Discord.botName,
                        botAvatar = Config.Discord.botAvatar ~= "" and Config.Discord.botAvatar or nil
                    }, function(uploadSuccess, url, errorMsg)
                        if uploadSuccess and url then
                            -- Send as message with Discord URL
                            SendMessageWithImage(reportId, player, url)
                            TriggerClientEvent("sws-report:screenshotCaptured", source, {
                                reportId = reportId,
                                imageData = data,
                                discordUrl = url
                            })
                            NotifyPlayer(source, L("screenshot_uploaded"), "success")
                            
                            -- Post to Discord thread
                            TriggerEvent("sws-report:discord:screenshot", reportId, player.name, url, player.name)
                        else
                            -- Fallback to base64 in chat
                            TriggerClientEvent("sws-report:screenshotCaptured", source, {
                                reportId = reportId,
                                imageData = data
                            })
                            NotifyPlayer(source, L("screenshot_uploaded"), "success")
                        end
                    end)
                else
                    -- No Discord, send base64 directly
                    TriggerClientEvent("sws-report:screenshotCaptured", source, {
                        reportId = reportId,
                        imageData = data
                    })
                    NotifyPlayer(source, L("screenshot_uploaded"), "success")
                end
            end)
        end)

        if not success then
            NotifyPlayer(source, L("screenshot_failed"), "error")
        end
    end)
end)