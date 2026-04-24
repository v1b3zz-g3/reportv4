---QB-Inventory (qb-inventory) adapter implementation
---@class QBInventoryAdapter : IInventoryAdapter

---@type IInventoryAdapter
QBInventoryAdapter = {}
local QBCore = nil

---Initialize QBCore object
local function initQBCore()
    if QBCore then return true end

    if GetResourceState("qb-core") ~= "started" then
        return false
    end

    QBCore = exports["qb-core"]:GetCoreObject()
    return QBCore ~= nil
end

---Check if QB-Inventory is available
---@return boolean
function QBInventoryAdapter.IsAvailable()
    return initQBCore() and GetResourceState("qs-inventory") == "started"
end

---Get adapter name
---@return string
function QBInventoryAdapter.GetName()
    return "qs-inventory"
end

---Check if adapter supports metadata editing
---@return boolean
function QBInventoryAdapter.SupportsMetadata()
    return true
end

---Get the image path for items
---@return string imagePath Base path for item images
local function getImagePath()
    return "nui://qs-inventory/html/images"
end

---Build image URL for an item
---@param itemName string Item name
---@return string imageUrl Full image URL
local function buildImageUrl(itemName)
    return getImagePath() .. "/" .. itemName .. ".png"
end

---Get all items in player inventory
---@param playerId integer Player server ID
---@return InventoryItem[]
function QBInventoryAdapter.GetPlayerInventory(playerId)
    if not initQBCore() then
        return {}
    end

    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then
        return {}
    end

    local items = Player.PlayerData.items
    if not items then
        return {}
    end

    local result = {}
    for slot, item in pairs(items) do
        if item and item.name and item.amount and item.amount > 0 then
            local itemInfo = QBCore.Shared.Items[item.name]
            table.insert(result, {
                name = item.name,
                label = itemInfo and itemInfo.label or item.name,
                count = item.amount,
                slot = slot,
                weight = itemInfo and itemInfo.weight or 0,
                metadata = item.info or {},
                image = buildImageUrl(item.name)
            })
        end
    end

    return result
end

---Get specific item from player inventory
---@param playerId integer Player server ID
---@param itemName string Item name to find
---@return InventoryItem|nil
function QBInventoryAdapter.GetItem(playerId, itemName)
    if not initQBCore() then
        return nil
    end

    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then
        return nil
    end

    local item = Player.Functions.GetItemByName(itemName)
    if not item then
        return nil
    end

    local itemInfo = QBCore.Shared.Items[itemName]
    return {
        name = item.name,
        label = itemInfo and itemInfo.label or item.name,
        count = item.amount or 0,
        slot = item.slot,
        weight = itemInfo and itemInfo.weight or 0,
        metadata = item.info or {},
        image = buildImageUrl(item.name)
    }
end

---Add item to player inventory
---@param playerId integer Player server ID
---@param itemName string Item name
---@param count integer Amount to add
---@param metadata? table Optional metadata
---@return InventoryActionResult
function QBInventoryAdapter.AddItem(playerId, itemName, count, metadata)
    if not initQBCore() then
        return { success = false, response = "QBCore not available" }
    end

    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then
        return { success = false, response = "Player not found" }
    end

    local success = Player.Functions.AddItem(itemName, count, nil, metadata or {})

    if success then
        return { success = true, response = "Item added" }
    else
        return { success = false, response = "Failed to add item - inventory might be full" }
    end
end

---Remove item from player inventory
---@param playerId integer Player server ID
---@param itemName string Item name
---@param count integer Amount to remove
---@param slot? integer Optional specific slot
---@param metadata? table Optional metadata filter (not used in QB)
---@return InventoryActionResult
function QBInventoryAdapter.RemoveItem(playerId, itemName, count, slot, metadata)
    if not initQBCore() then
        return { success = false, response = "QBCore not available" }
    end

    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then
        return { success = false, response = "Player not found" }
    end

    local hasItem = Player.Functions.GetItemByName(itemName)
    if not hasItem or hasItem.amount < count then
        return { success = false, response = "Insufficient items" }
    end

    local success = Player.Functions.RemoveItem(itemName, count, slot)

    if success then
        return { success = true, response = "Item removed" }
    else
        return { success = false, response = "Failed to remove item" }
    end
end

---Set exact item count in player inventory
---@param playerId integer Player server ID
---@param itemName string Item name
---@param count integer Target count
---@return InventoryActionResult
function QBInventoryAdapter.SetItemCount(playerId, itemName, count)
    if not initQBCore() then
        return { success = false, response = "QBCore not available" }
    end

    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then
        return { success = false, response = "Player not found" }
    end

    local currentItem = Player.Functions.GetItemByName(itemName)
    local currentCount = currentItem and currentItem.amount or 0

    if count > currentCount then
        local diff = count - currentCount
        return QBInventoryAdapter.AddItem(playerId, itemName, diff)
    elseif count < currentCount then
        local diff = currentCount - count
        return QBInventoryAdapter.RemoveItem(playerId, itemName, diff)
    end

    return { success = true, response = "Count unchanged" }
end

---Update item metadata in specific slot
---@param playerId integer Player server ID
---@param slot integer Slot number
---@param metadata table New metadata
---@return InventoryActionResult
function QBInventoryAdapter.SetItemMetadata(playerId, slot, metadata)
    if not initQBCore() then
        return { success = false, response = "QBCore not available" }
    end

    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then
        return { success = false, response = "Player not found" }
    end

    local item = Player.PlayerData.items[slot]
    if not item then
        return { success = false, response = "No item in that slot" }
    end

    -- Update the metadata
    item.info = metadata
    Player.PlayerData.items[slot] = item
    Player.Functions.SetPlayerData("items", Player.PlayerData.items)

    return { success = true, response = "Metadata updated" }
end

---Check if player can carry item
---@param playerId integer Player server ID
---@param itemName string Item name
---@param count integer Amount to check
---@return boolean
function QBInventoryAdapter.CanCarryItem(playerId, itemName, count)
    if not initQBCore() then
        return false
    end

    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then
        return false
    end

    -- QB-Inventory doesn't have a direct CanCarryItem check
    -- We'll check if there's available weight
    local itemInfo = QBCore.Shared.Items[itemName]
    if not itemInfo then
        return false
    end

    local totalWeight = Player.Functions.GetTotalWeight()
    local maxWeight = QBCore.Config.Player.MaxWeight or 120000
    local itemWeight = (itemInfo.weight or 0) * count

    return (totalWeight + itemWeight) <= maxWeight
end

---Get all registered items with image URLs
---@return table<string, table>
function QBInventoryAdapter.GetItemList()
    if not initQBCore() then
        return {}
    end

    local result = {}
    for itemName, itemData in pairs(QBCore.Shared.Items) do
        result[itemName] = {
            name = itemName,
            label = itemData.label or itemName,
            weight = itemData.weight or 0,
            image = buildImageUrl(itemName)
        }
    end

    return result
end

-- Global adapter registered as QBInventoryAdapter