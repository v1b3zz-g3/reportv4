---Heal player
RegisterNetEvent("sws-report:heal", function()
    local ped = PlayerPedId()
    local playerId = NetworkGetPlayerIndexFromPed(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)

    
	TriggerEvent('hospital:client:adminHeal',playerId)
	
	
end)

---Revive player
RegisterNetEvent("sws-report:revive", function()
    local ped = PlayerPedId()
    local playerId = NetworkGetPlayerIndexFromPed(ped)
    TriggerEvent('hospital:client:Revive', playerId)
end)
