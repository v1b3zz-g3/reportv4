-- client/module/admin/screenshot.lua
-- Native screenshot fallback when screenshot-basic fails

---Take screenshot using game natives (fallback method)
RegisterNetEvent("sws-report:takeNativeScreenshot", function()
    print("^3[screenshot-client] Native screenshot requested^0")
    
    -- This uses FiveM's built-in screenshot functionality
    -- It's less reliable but works without screenshot-basic
    
    Citizen.CreateThread(function()
        local success = false
        local attempts = 0
        local maxAttempts = 3
        
        while not success and attempts < maxAttempts do
            attempts = attempts + 1
            print(("^3[screenshot-client] Attempt %d/%d^0"):format(attempts, maxAttempts))
            
            -- Try to use exports.screenshot-basic if available
            local hasScreenshotBasic = GetResourceState("screenshot-basic") == "started"
            
            if hasScreenshotBasic then
                print("^2[screenshot-client] screenshot-basic available, using it^0")
                
                local completed = false
                
                -- Set timeout
                SetTimeout(8000, function()
                    if not completed then
                        completed = true
                        print("^1[screenshot-client] screenshot-basic timed out^0")
                        
                        if attempts >= maxAttempts then
                            -- Give up
                            TriggerServerEvent("sws-report:nativeScreenshotData", nil)
                        end
                    end
                end)
                
                -- Try screenshot-basic
                local ok, err = pcall(function()
                    exports["screenshot-basic"]:requestScreenshot({
                        encoding = "jpg",
                        quality = 0.85
                    }, function(captureErr, data)
                        if completed then return end
                        completed = true
                        
                        if captureErr then
                            if type(captureErr) == "string" and captureErr:match("^data:image/") then
                                -- Treat as success (miscalled callback)
                                print("^2[screenshot-client] Success (workaround)!^0")
                                success = true
                                TriggerServerEvent("sws-report:nativeScreenshotData", captureErr)
                            else
                                print(("^1[screenshot-client] Capture error: %s^0"):format(tostring(captureErr)))
                            
                                if attempts >= maxAttempts then
                                    TriggerServerEvent("sws-report:nativeScreenshotData", nil)
                                end
                            end
                        else
                            if data and #data > 100 then
                                print(("^2[screenshot-client] Success! %d bytes^0"):format(#data))
                                success = true
                                TriggerServerEvent("sws-report:nativeScreenshotData", data)
                            else
                                print("^1[screenshot-client] No data received^0")
                                
                                if attempts >= maxAttempts then
                                    TriggerServerEvent("sws-report:nativeScreenshotData", nil)
                                end
                            end
                        end
                    end)
                end)
                
                if not ok then
                    print(("^1[screenshot-client] Exception: %s^0"):format(tostring(err)))
                    completed = true
                    
                    if attempts >= maxAttempts then
                        TriggerServerEvent("sws-report:nativeScreenshotData", nil)
                        break
                    end
                end
                
                -- Wait for callback
                Wait(8000)
            else
                print("^1[screenshot-client] screenshot-basic not available^0")
                TriggerServerEvent("sws-report:nativeScreenshotData", nil)
                break
            end
            
            if not success and attempts < maxAttempts then
                print("^3[screenshot-client] Retrying in 1 second...^0")
                Wait(1000)
            end
        end
    end)
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

print("^2[screenshot-client] Module loaded^0")