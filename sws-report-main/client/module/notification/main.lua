---@type table<string, string> Sound file mapping
local SOUNDS = {
    notification = Config.Sounds.newReport or "notification.ogg",
    message = Config.Sounds.newMessage or "message.ogg"
}

---Play a sound effect
---@param soundType string Sound type ("notification" | "message")
local function playSound(soundType)
    if not Config.Sounds.enabled then 
        DebugPrint("Sounds disabled in config")
        return 
    end

    local soundFile = SOUNDS[soundType]
    if not soundFile then 
        DebugPrint(("Unknown sound type: %s"):format(soundType))
        return 
    end

    DebugPrint(("Playing sound: %s"):format(soundFile))

    SendNUIMessage({
        type = "PLAY_SOUND",
        data = {
            sound = soundFile,
            volume = Config.Sounds.volume or 0.5
        }
    })
end

-- Event handler for playing sounds
RegisterNetEvent("sws-report:playSound", function(soundType)
    DebugPrint(("Received sound event: %s"):format(soundType))
    playSound(soundType)
end)

-- Export for other resources
exports("PlaySound", function(soundType)
    playSound(soundType)
end)

-- Test sound command for debugging
RegisterCommand("testsound", function(source, args)
    local soundType = args[1] or "notification"
    DebugPrint(("Testing sound: %s"):format(soundType))
    playSound(soundType)
end, false)