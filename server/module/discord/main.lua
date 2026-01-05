---Active forum threads per report (reportId -> threadId)
---@type table<number, string>
local reportThreads = {}

---Truncate string to max length with ellipsis
---@param str string String to truncate
---@param maxLen number Maximum length
---@return string truncated Truncated string
local function truncateString(str, maxLen)
    if not str then return "" end
    if #str <= maxLen then return str end
    return str:sub(1, maxLen - 3) .. "..."
end

---Format thread name according to config template
---@param report table Report data
---@return string threadName Formatted thread name (max 100 chars)
local function formatThreadName(report)
    local template = Config.Discord.threadNameFormat or "[#{id}] {player} - {subject}"
    
    -- Replace placeholders
    local name = template
        :gsub("{id}", tostring(report.id))
        :gsub("{player}", report.playerName or "Unknown")
        :gsub("{playerId}", report.playerId or "")
        :gsub("{subject}", report.subject or "No subject")
    
    -- Truncate to Discord's 100 character limit
    return truncateString(name, 100)
end

---Ensure a value is always a valid Discord-safe string
---@param value any
---@param fallback? string
---@return string
local function safeString(value, fallback)
    if value == nil then
        return fallback or "N/A"
    end

    local str = tostring(value)

    if str == "" then
        return fallback or "N/A"
    end

    return str
end

---Check if event type is enabled
---@param eventType string Event type
---@return boolean
local function isEventEnabled(eventType)
    if not Config.Discord.events then return true end
    return Config.Discord.events[eventType] ~= false
end

---Get the forum webhook URL
---@return string|nil webhook Webhook URL or nil
local function getForumWebhook()
    if not Config.Discord.enabled then return nil end
    return Config.Discord.forumWebhook
end

---Create forum thread for a report
---@param report table Report data
---@return string|nil threadId Thread ID or nil if failed
local function createReportThread(report)
    local webhook = getForumWebhook()
    if not webhook or webhook == "" then
        PrintError("Forum webhook not configured")
        return nil
    end

    local threadName = formatThreadName(report)
    
    -- Get category config for icon
    local categoryConfig = GetCategoryConfig(report.category)
    local categoryLabel = categoryConfig and categoryConfig.label or report.category

    -- FIX: Ensure description is valid and not too long
    local description = safeString(report.description, "No description provided")
    description = truncateString(description, 1000)

    -- FIX: Build initial thread post with proper content
    local threadData = {
        thread_name = threadName,
        auto_archive_duration = 10080,
        -- FIX: Remove applied_tags if causing issues, or ensure valid tag IDs
        -- applied_tags = {},
        content = string.format("**New Report #%s**\n**Player:** %s\n**Category:** %s", 
            safeString(report.id), 
            safeString(report.playerName, "Unknown"),
            safeString(categoryLabel)
        ),
        embeds = {{
            title = "📋 New Report Created",
            description = description,
            color = Config.Discord.colors.new,
            fields = {
                { name = "Report ID", value = "#" .. safeString(report.id, "0"), inline = true },
                { name = "Player", value = safeString(report.playerName, "Unknown"), inline = true },
                { name = "Category", value = safeString(categoryLabel, "Unknown"), inline = true },
                { name = "Subject", value = truncateString(safeString(report.subject, "No subject"), 256), inline = false },
                { name = "Player ID", value = "`" .. truncateString(safeString(report.playerId, "N/A"), 100) .. "`", inline = false }
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer = { text = "Report System" }
        }}
    }

    -- Add ?wait=true to get the thread ID back
    local webhookWithWait = webhook:find("?") and (webhook .. "&wait=true") or (webhook .. "?wait=true")
    
    local threadId = nil
    local success = false
    
    PerformHttpRequest(webhookWithWait, function(err, text, headers)
        if err == 200 or err == 204 then
            local parseSuccess, response = pcall(json.decode, text)
            if parseSuccess and response and response.id then
                threadId = response.id
                reportThreads[report.id] = threadId
                success = true
                DebugPrint(("Created forum thread %s for report #%d"):format(threadId, report.id))
            else
                PrintError(("Failed to parse Discord response for report #%d"):format(report.id))
                if text then PrintError(("Response: %s"):format(text)) end
            end
        else
            PrintError(("Failed to create forum thread for report #%d: HTTP %s"):format(report.id, tostring(err)))
            if text then
                PrintError(("Response: %s"):format(text))
            end
        end
    end, "POST", json.encode(threadData), { ["Content-Type"] = "application/json" })

    -- Wait for thread creation
    local timeout = 0
    while not success and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end

    return threadId
end

---Send message to report thread
---@param reportId number Report ID
---@param embed table Discord embed
---@param content? string Optional message content
local function sendToReportThread(reportId, embed, content)
    local webhook = getForumWebhook()
    if not webhook or webhook == "" then return end

    -- Get or create thread
    local threadId = reportThreads[reportId]
    if not threadId then
        PrintWarn(("No thread found for report #%d - thread may not have been created yet"):format(reportId))
        return
    end

    -- Build webhook URL with thread parameter
    local webhookUrl = webhook:find("?") 
        and (webhook .. "&thread_id=" .. threadId) 
        or (webhook .. "?thread_id=" .. threadId)

    local payload = {
        username = Config.Discord.botName,
        avatar_url = Config.Discord.botAvatar ~= "" and Config.Discord.botAvatar or nil,
        content = content,
        embeds = { embed }
    }

    PerformHttpRequest(webhookUrl, function(err, text, headers)
        if err ~= 200 and err ~= 204 then
            PrintError(("Failed to send message to thread for report #%d: HTTP %s"):format(reportId, tostring(err)))
            if text then PrintError(("Response: %s"):format(text)) end
        end
    end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
end

---Archive a forum thread
---@param threadId string Thread ID to archive
---@param lockThread? boolean Whether to lock the thread (default false)
local function archiveThread(threadId, lockThread)
    if not threadId then return end
    
    -- Note: Archiving requires bot token, not webhook
    -- This is a placeholder for servers with bot integration
    DebugPrint(("Thread %s should be archived (requires bot token)"):format(threadId))
end

local function buildScreenshotEmbed(playerName, reportId, imageUrl, capturedBy)
    return {
        title = "📸 Screenshot",
        description = string.format("Screenshot from **%s** (Report #%d)\nCaptured by: %s", 
            playerName, reportId, capturedBy),
        color = 3447003,
        image = { url = imageUrl },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end

---Build embed for report claimed
---@param report table Report data
---@param admin table Admin data
---@return table embed Discord embed
local function buildClaimedEmbed(report, admin)
    return {
        title = "✋ Report Claimed",
        description = ("**%s** has claimed this report"):format(admin.name),
        color = Config.Discord.colors.claimed,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end

---Build embed for report unclaimed
---@param report table Report data
---@param admin table Admin data
---@return table embed Discord embed
local function buildUnclaimedEmbed(report, admin)
    return {
        title = "🔓 Report Unclaimed",
        description = ("**%s** has unclaimed this report"):format(admin.name),
        color = Config.Discord.colors.claimed,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end

---Build embed for report resolved
---@param report table Report data
---@param admin table Admin data
---@return table embed Discord embed
local function buildResolvedEmbed(report, admin)
    local createdTime = os.time()
    local resolvedTime = os.time()
    local duration = resolvedTime - createdTime
    local durationStr = string.format("%dh %dm", math.floor(duration / 3600), math.floor((duration % 3600) / 60))

    return {
        title = "✅ Report Resolved",
        description = ("**%s** has resolved this report"):format(admin.name),
        color = Config.Discord.colors.resolved,
        fields = {
            {
                name = "Resolution Time",
                value = durationStr,
                inline = true
            }
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end

---Build embed for report deleted
---@param report table Report data
---@param player table Player who deleted
---@return table embed Discord embed
local function buildDeletedEmbed(report, player)
    return {
        title = "🗑️ Report Deleted",
        description = ("**%s** has deleted this report"):format(player.name),
        color = Config.Discord.colors.deleted,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end

---Build embed for chat message
---@param message table Message data
---@return table embed Discord embed
local function buildChatMessageEmbed(message)
    local isAdmin = message.senderType == "admin"
    local isSystem = message.senderType == "system"
    
    return {
        description = message.message,
        color = Config.Discord.colors.message,
        author = isSystem and {
            name = "System Message",
            icon_url = nil
        } or {
            name = message.senderName .. (isAdmin and " 🛡️" or ""),
            icon_url = nil
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end

---Build embed for voice message
---@param message table Message data
---@return table embed Discord embed
local function buildVoiceMessageEmbed(message)
    local isAdmin = message.senderType == "admin"
    
    return {
        title = "🎤 Voice Message",
        description = ("Duration: **%d seconds**"):format(message.audioDuration or 0),
        color = Config.Discord.colors.voice,
        author = {
            name = message.senderName .. (isAdmin and " 🛡️" or ""),
            icon_url = nil
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end



---Build embed for admin action
---@param action string Action type
---@param admin table Admin data
---@param target table Target player data
---@return table embed Discord embed
local function buildAdminActionEmbed(action, admin, target)
    local actionLabels = {
        teleport_to = "📍 Teleported To Player",
        bring_player = "🚀 Brought Player",
        heal_player = "❤️ Healed Player",
        revive_player = "⚡ Revived Player",
        freeze_player = "❄️ Froze/Unfroze Player",
        spectate_player = "👁️ Spectating Player",
        kick_player = "👢 Kicked Player",
        ragdoll_player = "🤸 Ragdolled Player",
        screenshot_player = "📸 Screenshot Requested"
    }

    return {
        title = actionLabels[action] or "Admin Action",
        description = ("**%s** → **%s**"):format(admin.name, target.name),
        color = Config.Discord.colors.admin,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end

---Build embed for inventory action
---@param data table Action data
---@return table embed Discord embed
local function buildInventoryEmbed(data)
    local actionLabels = {
        add = "➕ Item Added",
        remove = "➖ Item Removed",
        set = "🔢 Item Count Set",
        metadata_edit = "✏️ Metadata Edited"
    }

    local fields = {
        {
            name = "Admin",
            value = data.admin.name,
            inline = true
        },
        {
            name = "Item",
            value = data.item.label or data.item.name,
            inline = true
        }
    }

    if data.action == "add" or data.action == "remove" then
        table.insert(fields, {
            name = "Amount",
            value = tostring(data.item.count),
            inline = true
        })
        table.insert(fields, {
            name = "Count Change",
            value = ("%d → %d"):format(data.countBefore or 0, data.countAfter or 0),
            inline = true
        })
    elseif data.action == "set" then
        table.insert(fields, {
            name = "Count Change",
            value = ("%d → %d"):format(data.countBefore or 0, data.countAfter or 0),
            inline = true
        })
    end

    return {
        title = actionLabels[data.action] or "Inventory Action",
        color = Config.Discord.colors.inventory,
        fields = fields,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end

-- Event Handlers

AddEventHandler("sws-report:discord:newReport", function(report)
    if not isEventEnabled("newReport") then return end
    createReportThread(report)
end)

AddEventHandler("sws-report:discord:claimed", function(report, admin)
    if not isEventEnabled("reportClaimed") then return end
    sendToReportThread(report.id, buildClaimedEmbed(report, admin))
end)

AddEventHandler("sws-report:discord:unclaimed", function(report, admin)
    if not isEventEnabled("reportUnclaimed") then return end
    sendToReportThread(report.id, buildUnclaimedEmbed(report, admin))
end)

AddEventHandler("sws-report:discord:resolved", function(report, admin)
    if not isEventEnabled("reportResolved") then return end
    sendToReportThread(report.id, buildResolvedEmbed(report, admin))
    
    -- Auto-archive if enabled
    if Config.Discord.autoArchive and Config.Discord.autoArchive.enabled then
        local threadId = reportThreads[report.id]
        if threadId then
            -- Note: Actual archiving requires Discord bot token
            DebugPrint(("Report #%d resolved - thread %s should be archived"):format(report.id, threadId))
        end
    end
end)

AddEventHandler("sws-report:discord:deleted", function(report, player)
    if not isEventEnabled("reportDeleted") then return end
    sendToReportThread(report.id, buildDeletedEmbed(report, player))
    
    -- Auto-archive if enabled
    if Config.Discord.autoArchive and Config.Discord.autoArchive.enabled then
        local threadId = reportThreads[report.id]
        if threadId then
            DebugPrint(("Report #%d deleted - thread %s should be archived"):format(report.id, threadId))
        end
    end
end)

AddEventHandler("sws-report:discord:chatMessage", function(report, message)
    if not isEventEnabled("chatMessage") then return end
    sendToReportThread(report.id, buildChatMessageEmbed(message))
end)

AddEventHandler("sws-report:discord:voiceMessage", function(report, message)
    if not isEventEnabled("voiceMessage") then return end
    sendToReportThread(report.id, buildVoiceMessageEmbed(message))
end)

AddEventHandler("sws-report:discord:adminAction", function(action, admin, target, reportId)
    if not isEventEnabled("adminAction") then return end
    if not reportId or reportId == 0 then return end
    sendToReportThread(reportId, buildAdminActionEmbed(action, admin, target))
end)

AddEventHandler("sws-report:discord:inventoryAction", function(data)
    if not isEventEnabled("inventoryAction") then return end
    sendToReportThread(data.reportId, buildInventoryEmbed(data))
end)

-- Cleanup thread cache on resource restart
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    reportThreads = {}
end)


AddEventHandler("sws-report:discord:screenshot", function(reportId, playerName, imageUrl, capturedBy)
    if not Config.Discord.enabled or not Config.Discord.forumWebhook then return end
    sendToReportThread(reportId, buildScreenshotEmbed(playerName, reportId, imageUrl, capturedBy))
end)

-- [Other event handlers remain the same]

AddEventHandler("sws-report:discord:screenshot", function(reportId, playerName, imageUrl, capturedBy)
    if not Config.Discord.enabled or not Config.Discord.forumWebhook then return end
    sendToReportThread(reportId, buildScreenshotEmbed(playerName, reportId, imageUrl, capturedBy))
end)

---Get thread ID for a report
---@param reportId number Report ID
---@return string|nil threadId Thread ID or nil if not found
local function getReportThreadId(reportId)
    return reportThreads[reportId]
end

-- Export for other modules to get thread IDs
exports("GetReportThreadId", getReportThreadId)



DebugPrint("Discord module loaded - All reports will be logged as forum threads")