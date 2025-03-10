--------------------------------
-- Variables & Configuration
--------------------------------
local ped = nil
local pedModel = GetHashKey("a_f_o_indian_01")
local pedCoords = vector3(1169.5, -291, 68)
local spawnRadius = 50.0

local alertActive = false
local jobActive = false       -- Job session active? (Player toggles via NPC)
local rideInProgress = false  -- Ride currently running

-- Payment constants
local baseRate = 1.0          -- Dollars per meter
local tipMultiplier = 10      -- Dollars per tip point
local speedThreshold = 30.0   -- m/s threshold for speeding
local speedPenalty = 2        -- Tip reduction per speeding violation
local crashPenalty = 5        -- Tip reduction per collision

--------------------------------
-- Helper Alert Functions
--------------------------------
function showAlert(message, beep)
    AddTextEntry('Crucii_Alert', message)
    BeginTextCommandDisplayHelp('Crucii_Alert')
    EndTextCommandDisplayHelp(0, false, beep, -1)
end

function clearAlert()
    ClearAllHelpMessages()
end

--------------------------------
-- Payment Calculation Function
--------------------------------
function calculatePayment(rideDistance, tipRating, rideStats)
    local basePay = rideDistance * baseRate
    local maxTip = tipRating * tipMultiplier
    local totalPenalty = (rideStats.speedViolations * speedPenalty) + (rideStats.collisions * crashPenalty)
    local finalTip = math.max(0, maxTip - totalPenalty)
    local totalPay = basePay + finalTip
    local roundedTotalPay = math.floor(totalPay + 0.5)  -- Round to nearest dollar

    print(string.format("Ride complete! Base Pay: $%.2f, Final Tip: $%.2f, Total (rounded): $%d", basePay, finalTip, roundedTotalPay))
    return roundedTotalPay
end

--------------------------------
-- Job Offer Stage: Customer Info & Accept/Decline Prompt
--------------------------------
function showJobOffer(vehicle)
    -- Choose random pickup and dropoff locations from Config.
    local pickup = Config.Pickups[math.random(#Config.Pickups)]
    local dropoff = Config.Dropoffs[math.random(#Config.Dropoffs)]
    
    local rideDistance = Vdist(pickup.x, pickup.y, pickup.z, dropoff.x, dropoff.y, dropoff.z)
    local customerNames = {"John", "Sarah", "Mike", "Emily", "Alex", "Jessy", "Ivan", "Candace", "Connor", "Joseph", "Alexis"}
    local customerName = customerNames[math.random(#customerNames)]
    local tipRating = math.random(1, 3)
    local distanceFromCustomer = Vdist(GetEntityCoords(PlayerPedId()), pickup.x, pickup.y, pickup.z)
    
    local offerMessage = string.format(
        "Customer: %s\nDistance: %.1f m\nRide: %.1f m\nTip Rating: %d/3\nPress ~g~Y~w~ to Accept or ~r~G~w~ to Decline", 
        customerName, distanceFromCustomer, rideDistance, tipRating
    )
    
    showAlert(offerMessage, true)
    
    local accepted = nil
    while accepted == nil do
        if IsControlJustReleased(0, 246) then  -- Y key for Accept
            accepted = true
        elseif IsControlJustReleased(0, 47) then  -- G key for Decline
            accepted = false
        end
        Citizen.Wait(0)
    end
    
    clearAlert()
    
    if accepted then
        startRideWithOffer(vehicle, pickup, dropoff, rideDistance, tipRating)
    else
        showAlert("Job declined", true)
        Citizen.Wait(1500)
        clearAlert()
        rideInProgress = false  -- Allow future ride offers
    end
end

--------------------------------
-- Ride Logic: Pickup, Payment, and Speed Alerts
--------------------------------
function startRideWithOffer(vehicle, pickup, dropoff, rideDistance, tipRating)
    -- Create a pickup blip.
    local pickupBlip = AddBlipForCoord(pickup.x, pickup.y, pickup.z)
    SetBlipSprite(pickupBlip, 280)
    SetBlipColour(pickupBlip, 2)
    SetBlipRoute(pickupBlip, true)

    Citizen.CreateThread(function()
        -- Wait until the player is near the pickup location.
        while true do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distancePickup = Vdist(playerCoords.x, playerCoords.y, playerCoords.z, pickup.x, pickup.y, pickup.z)
            if distancePickup < 5.0 then break end
            Citizen.Wait(100)
        end

        RemoveBlip(pickupBlip)

        -- Spawn the NPC for pickup.
        local npcModel = GetHashKey("a_m_y_business_01")
        RequestModel(npcModel)
        while not HasModelLoaded(npcModel) do
            Citizen.Wait(100)
        end
        local npcPed = CreatePed(4, npcModel, pickup.x, pickup.y, pickup.z, 0.0, true, false)
        SetEntityInvincible(npcPed, true)
        TaskStandStill(npcPed, -1)
        Citizen.Wait(500)

        -- Command NPC to enter the vehicle's backseat (seat index 1).
        TaskEnterVehicle(npcPed, vehicle, -1, 1, 1.0, 1, 0)

        local timeout = 10000
        local timer = 0
        while not IsPedInVehicle(npcPed, vehicle, false) and timer < timeout do
            Citizen.Wait(100)
            timer = timer + 100
        end
        if not IsPedInVehicle(npcPed, vehicle, false) then
            showAlert("Pickup failed! NPC did not get in.", true)
            Citizen.Wait(2000)
            clearAlert()
            DeleteEntity(npcPed)
            rideInProgress = false
            return
        end

        -- Start tracking driving behavior.
        local rideStats = { speedViolations = 0, collisions = 0 }
        local prevHealth = GetEntityHealth(vehicle)
        local speedAlertActive = false
        Citizen.CreateThread(function()
            while rideInProgress do
                Citizen.Wait(1000)
                local speed = GetEntitySpeed(vehicle)
                if speed > speedThreshold then
                    rideStats.speedViolations = rideStats.speedViolations + 1
                    if not speedAlertActive then
                        speedAlertActive = true
                        showAlert("Slow down! You are speeding!", true)
                        Citizen.Wait(1000)
                        clearAlert()
                        speedAlertActive = false
                    end
                end
                local curHealth = GetEntityHealth(vehicle)
                if (prevHealth - curHealth) > 10 then -- Collision threshold; adjust as needed
                    rideStats.collisions = rideStats.collisions + 1
                    prevHealth = curHealth
                end
            end
        end)

        -- Create a dropoff blip.
        local dropoffBlip = AddBlipForCoord(dropoff.x, dropoff.y, dropoff.z)
        SetBlipSprite(dropoffBlip, 280)
        SetBlipColour(dropoffBlip, 1)
        SetBlipRoute(dropoffBlip, true)

        while true do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distanceDropoff = Vdist(playerCoords.x, playerCoords.y, playerCoords.z, dropoff.x, dropoff.y, dropoff.z)
            if distanceDropoff < 5.0 then break end
            Citizen.Wait(100)
        end

        RemoveBlip(dropoffBlip)
        ClearPedTasks(npcPed)
        TaskLeaveVehicle(npcPed, vehicle, 0)
        Citizen.Wait(1000)
        
        -- Calculate and display payment.
        local totalPay = calculatePayment(rideDistance, tipRating, rideStats)
        showAlert("Job completed!\nEarnings: $" .. totalPay, true)
        Citizen.Wait(3000)
        clearAlert()
        DeleteEntity(npcPed)
        rideInProgress = false
    end)
end

--------------------------------
-- Ped (NPC) & Input Management (Toggling Job Session)
--------------------------------
-- Load the ped model before starting the toggling thread.
RequestModel(pedModel)
while not HasModelLoaded(pedModel) do
    Citizen.Wait(100)
end

Citizen.CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local distance = Vdist(playerCoords.x, playerCoords.y, playerCoords.z, pedCoords.x, pedCoords.y, pedCoords.z)
        
        if distance < spawnRadius and not DoesEntityExist(ped) then
            ped = CreatePed(4, pedModel, pedCoords.x, pedCoords.y, pedCoords.z, 348, true, false)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)
            SetPedCanRagdoll(ped, false)
            SetPedDiesWhenInjured(ped, false)
            SetPedFleeAttributes(ped, 0, 0)
            SetPedCombatAttributes(ped, 46, true)
            SetPedCombatAttributes(ped, 17, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedCanBeTargetted(ped, false)
            TaskStartScenarioInPlace(ped, "WORLD_HUMAN_GUARD_STAND", 0, true)
        elseif distance >= spawnRadius and DoesEntityExist(ped) then
            DeleteEntity(ped)
            ped = nil
        end

        Citizen.Wait(500)
    end
end)

-- Toggle the job session on/off when near the ped.
Citizen.CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local distance = Vdist(playerCoords.x, playerCoords.y, playerCoords.z, pedCoords.x, pedCoords.y, pedCoords.z)

        if distance <= 3 and DoesEntityExist(ped) then
            if not alertActive then
                if not jobActive then
                    showAlert("Press E to start Uber Job", true)
                else
                    showAlert("Press E to end Uber Job", true)
                end
                alertActive = true
            end

            if IsControlJustPressed(0, 38) then  -- E key
                jobActive = not jobActive
                clearAlert()
                alertActive = false
            end

            Citizen.Wait(0)
        else
            if alertActive then
                clearAlert()
                alertActive = false
            end
            Citizen.Wait(500)
        end
    end
end)

--------------------------------
-- Random Job Offer Thread (While Job Session Active)
--------------------------------
Citizen.CreateThread(function()
    local timeInVehicle = 0
    while true do
        Citizen.Wait(1000) -- Check every second
        if IsPedInAnyVehicle(PlayerPedId(), false) and jobActive and not rideInProgress then
            timeInVehicle = timeInVehicle + 1
            if timeInVehicle >= 10 then  -- After 10 seconds in vehicle
                local chance = math.random(1, 100)
                if chance <= 10 then  -- 10% chance per second after 10 seconds
                    rideInProgress = true
                    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
                    showJobOffer(vehicle)
                    timeInVehicle = 0
                end
            end
        else
            timeInVehicle = 0
        end
    end
end)

