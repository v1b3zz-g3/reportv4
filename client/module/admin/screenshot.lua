-- Add to client/module/admin/screenshot.lua
RegisterNetEvent("sws-report:receiveScreenshot", function(imageUrl, playerName)
    if imageUrl then
        DebugPrint(("[sws-report] Screenshot from %s: %s"):format(playerName, imageUrl))
    end
end)

---Show screenshot popup in NUI
RegisterNetEvent("sws-report:showScreenshotPopup", function(data)
    SendNUIMessage({
        type = "SHOW_SCREENSHOT_POPUP",
        data = data
    })
end)

---Handle captured screenshot from user (camera button)
RegisterNetEvent("sws-report:screenshotCaptured", function(data)
    SendNUIMessage({
        type = "USER_SCREENSHOT_CAPTURED",
        data = data
    })
end)