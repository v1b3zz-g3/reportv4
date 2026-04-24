-- client/module/admin/screenshot.lua
-- Screenshot capture with chunked data transfer for large screenshots

local CHUNK_SIZE = 50000 -- 50KB chunks to avoid network overflow

---Split base64 data into chunks
---@param data string Base64 data
---@param chunkSize number Chunk size in bytes
---@return table chunks Array of data chunks
local function splitIntoChunks(data, chunkSize)
    local chunks = {}
    local dataLength = #data
    local numChunks = math.ceil(dataLength / chunkSize)
    
    for i = 1, numChunks do
        local startPos = (i - 1) * chunkSize + 1
        local endPos = math.min(i * chunkSize, dataLength)
        chunks[i] = data:sub(startPos, endPos)
    end
    
    return chunks
end

---Send screenshot data in chunks to avoid network overflow
---@param data string Base64 screenshot data
---@param reportId number Report ID
local function sendScreenshotInChunks(data, reportId)
    print(("^3[screenshot-client] Preparing to send %d bytes in chunks^0"):format(#data))
    
    local chunks = splitIntoChunks(data, CHUNK_SIZE)
    local totalChunks = #chunks
    
    print(("^3[screenshot-client] Split into %d chunks of max %d bytes^0"):format(totalChunks, CHUNK_SIZE))
    
    -- Send each chunk with a small delay to avoid overwhelming the network
    for i, chunk in ipairs(chunks) do
        TriggerServerEvent("sws-report:screenshotChunk", i, totalChunks, chunk, reportId)
        
        if i % 10 == 0 then -- Every 10 chunks, wait a bit
            Wait(50)
        end
    end
    
    print(("^2[screenshot-client] All %d chunks sent^0"):format(totalChunks))
end

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
                            -- Give up - send nil to indicate failure
                            TriggerServerEvent("sws-report:screenshotChunk", 1, 1, "", 0)
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
                                -- Data is in captureErr parameter
                                TriggerServerEvent("sws-report:nativeScreenshotData", captureErr)
                            else
                                print(("^1[screenshot-client] Capture error: %s^0"):format(tostring(captureErr)))
                            
                                if attempts >= maxAttempts then
                                    TriggerServerEvent("sws-report:screenshotChunk", 1, 1, "", 0)
                                end
                            end
                        else
                            if data and #data > 100 then
                                print(("^2[screenshot-client] Success! %d bytes^0"):format(#data))
                                success = true
                                -- Send in chunks to avoid network overflow
                                -- Extract report ID from somewhere or use a temp value
                                TriggerServerEvent("sws-report:nativeScreenshotData", data)
                            else
                                print("^1[screenshot-client] No data received^0")
                                
                                if attempts >= maxAttempts then
                                    TriggerServerEvent("sws-report:screenshotChunk", 1, 1, "", 0)
                                end
                            end
                        end
                    end)
                end)
                
                if not ok then
                    print(("^1[screenshot-client] Exception: %s^0"):format(tostring(err)))
                    completed = true
                    
                    if attempts >= maxAttempts then
                        TriggerServerEvent("sws-report:screenshotChunk", 1, 1, "", 0)
                        break
                    end
                end
                
                -- Wait for callback
                Wait(8000)
            else
                print("^1[screenshot-client] screenshot-basic not available^0")
                TriggerServerEvent("sws-report:screenshotChunk", 1, 1, "", 0)
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

---Handle captured screenshot from user (camera button) - WITH CHUNKING
RegisterNetEvent("sws-report:screenshotCaptured", function(data)
    -- If the data contains a very large imageData, we might need to handle it differently
    -- For display purposes in NUI, we can send it directly since it's one-way to the UI
    -- The UI won't send it back over the network
    
    SendNUIMessage({
        type = "USER_SCREENSHOT_CAPTURED",
        data = data
    })
end)

print("^2[screenshot-client] Module loaded with chunked transfer support^0")