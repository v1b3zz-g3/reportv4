---Discord webhook integration for inventory actions
---This module has been simplified - all inventory actions are now routed
---through the main discord module to the report's forum thread

---Handle inventory action discord logging
---@param data table Action data containing action, admin, player, item, report
RegisterNetEvent("sws-report:discord:inventoryAction", function(data)
    -- Simply trigger the main discord event
    -- The main module will handle routing to the correct thread
    TriggerEvent("sws-report:discord:inventoryAction", data)
end)