local ProfileService = require(game.ReplicatedStorage.ProfileService)
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local Profiles = {}

local Remotes = RS:WaitForChild("Remotes")
local GiveCodeBike = Remotes:WaitForChild("GiveCodeBike")

local INFINITE_ENERGY_PASS_ID = 1884377642

local function PlayerHasInfiniteEnergy(plr: Player): boolean
	if INFINITE_ENERGY_PASS_ID == 0 then return false end
	local ok, owned = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, plr.UserId, INFINITE_ENERGY_PASS_ID)
	return ok and owned
end

local ShopList = RS:WaitForChild("ShopList")
local BikesFolder = RS:WaitForChild("Bikes")

local function GetInventoryKey(bikeName)
	return string.gsub(bikeName, " ", "_")
end

local function GetSavedFuel(plr, bikeName)
	local profile = Profiles[plr]
	if not profile then return nil end
	if not profile.Data.FuelData then return nil end
	local key = GetInventoryKey(bikeName)
	return profile.Data.FuelData[key]
end

local function SetSavedFuel(plr, bikeName, currentFuel, maxFuel)
	local profile = Profiles[plr]
	if not profile then return end
	if not profile.Data.FuelData then
		profile.Data.FuelData = {}
	end
	local key = GetInventoryKey(bikeName)
	profile.Data.FuelData[key] = {
		CurrentFuel = currentFuel,
		MaxFuel = maxFuel,
	}
end

local function GetSavedCharge(plr, bikeName)
	local profile = Profiles[plr]
	if not profile then return nil end
	if not profile.Data.ChargeData then return nil end
	local key = GetInventoryKey(bikeName)
	return profile.Data.ChargeData[key]
end

local function SetSavedCharge(plr, bikeName, currentCharge)
	local profile = Profiles[plr]
	if not profile then return end
	if not profile.Data.ChargeData then
		profile.Data.ChargeData = {}
	end
	local key = GetInventoryKey(bikeName)
	profile.Data.ChargeData[key] = {
		CurrentCharge = currentCharge,
	}
end

local function FindBikeModel(bikeName)
	local normalizedTarget = string.lower(string.gsub(bikeName, " ", ""))
	for _, child in ipairs(BikesFolder:GetDescendants()) do
		if child:IsA("Model") then
			local normalizedChild = string.lower(string.gsub(child.Name, " ", ""))
			if normalizedChild == normalizedTarget then
				return child
			end
		end
	end
	return nil
end

local function FindBikeDataFromName(bikeName)
	for _, module in pairs(ShopList:GetChildren()) do
		if module:IsA("ModuleScript") then
			local success, bikeList = pcall(require, module)
			if success and bikeList then
				for _, bikeData in pairs(bikeList) do
					if bikeData.Name == bikeName then

						return {
							Name = bikeData.Name,
							Kind = bikeData.Kind,
							Speed = bikeData.Speed,
							Price = bikeData.Price,
						}
					end
				end
			end
		end
	end
	return nil
end

local function FindBikeNameFromProductID(ID: number)
	for _, module in pairs(ShopList:GetChildren()) do
		if module:IsA("ModuleScript") then
			local success, bikeList = pcall(require, module)
			if success and bikeList then
				for _, bikeData in pairs(bikeList) do
					if bikeData.Robux == true and bikeData.ProductID == ID then
						return {
							Name = bikeData.Name,
							Kind = bikeData.Kind,
							Speed = bikeData.Speed,
							Price = bikeData.Price,
						}
					end
				end
			end
		end
	end
	return nil
end

local function getTradedBikesData(Player)
	local AllData = {}

	for _, v in pairs(Player.BikeTradeFolder:GetChildren()) do
		local profile = Profiles[Player]
		local key = GetInventoryKey(v.Name)
		if profile and profile.Data.Inventory[key] then
			local completeBikeData = profile.Data.Inventory[key]
			local bikeDataCopy = {
				Name = completeBikeData.Name,
				Kind = completeBikeData.Kind,
				Speed = completeBikeData.Speed,
				Price = completeBikeData.Price,
			}
			table.insert(AllData, bikeDataCopy)
		else
			local bikeData = FindBikeDataFromName(v.Name)
			if not bikeData then warn("Invalid bike") continue end
			table.insert(AllData, bikeData)
		end
	end

	return AllData
end

local refreshInterval = 30
local pastKey = 0

local function getNextRefreshTime(): number
	local currentTime = os.time()
	local currentIntervalsPassed = math.floor(currentTime / refreshInterval)
	if currentIntervalsPassed < math.round(currentTime / refreshInterval) then
		currentIntervalsPassed = math.round(currentTime / refreshInterval)
	end
	local nextRefreshTime = (currentIntervalsPassed + 1) * refreshInterval
	local currentRefreshTime = currentIntervalsPassed * refreshInterval
	return nextRefreshTime, currentRefreshTime
end

local function KEYGEN()
	local nextRefresh, current = getNextRefreshTime()
	local rng = Random.new(nextRefresh)
	local key = rng:NextInteger(100000, 10000000)

	local pastKeyRng = Random.new(current)
	pastKey = pastKeyRng:NextInteger(100000, 10000000)

	return key
end

local bikes = {}

local GamepassBikes = {
	["KuKirin G3 Pro"] = {1820327558},
	["Segway GT3 Pro SuperScooter"] = {1820327558},
	["KuKirin G2 Pro"] = {1820327558},
	["Antic Bike"] = {1820657619},
	["Surronster's Hyper Quad"] = {1822776600},
	["Surronster's Surron LBX"] = {1822776600},
	["Surronster's Porsche"] = {1822776600},
	["Mini Dodge Charger Hellcat"] = {1840992559},
	["Mini RAM TRX"] = {1840992559},
	["Mini Mercedes Maybach"] = {1842916295},
	["Ultra_Ryder Surron Ultra Bee"] = {1884287496},
	["Kane._09's Surron Light Bee X"] = {1887406376},
	["Hector Buendia's Surron LBX"] = {1887406376},
	["17.robby's Surron Light Bee X"] = {1887406376},
	["Saint West's Purple Surron LBX"] = {1890598314},
	["Saint West's Pink Surron LBX"] = {1890598314}
}

RS.Remotes.SpawnBike.OnServerEvent:Connect(function(plr: Player, bikeName: string)
	local char = plr.Character or plr.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")

	local bike = FindBikeModel(bikeName)
	if not bike then return end

	local bikeClone = bike:Clone()

	bikeClone:SetAttribute("InfiniteEnergy", PlayerHasInfiniteEnergy(plr))

	local saved = GetSavedFuel(plr, bikeName)
	if saved then
		bikeClone:SetAttribute("SavedFuel", saved.CurrentFuel)
	end

	local savedCharge = GetSavedCharge(plr, bikeName)
	if savedCharge then
		bikeClone:SetAttribute("SavedCharge", savedCharge.CurrentCharge)
	end

	bikeClone.Parent = workspace
	bikeClone.Name = plr.Name .. "sCar"

	local spawnCF = hrp.CFrame * CFrame.new(0, 0, -5)

	if bikeName == "Mini Mercedes Maybach" then
		spawnCF = spawnCF * CFrame.Angles(
			math.rad(90),
			0,
			0
		)
	end

	bikeClone:PivotTo(spawnCF)
	local drivingValue = Instance.new("BoolValue")
	drivingValue.Name = "IsBeingDriven"
	drivingValue.Value = false
	drivingValue.Parent = bikeClone

	local gasFolder = bikeClone:FindFirstChild("Gas")
	if gasFolder then
		local currentFuelVal = gasFolder:WaitForChild("CurrentFuel", 5)
		local maxFuelVal = gasFolder:WaitForChild("MaxFuel", 5)

		if currentFuelVal and maxFuelVal then
			if not saved then
				task.defer(function()
					SetSavedFuel(plr, bikeName, currentFuelVal.Value, maxFuelVal.Value)
				end)
			end

			local fuelConn
			fuelConn = currentFuelVal.Changed:Connect(function(newValue)
				SetSavedFuel(plr, bikeName, newValue, maxFuelVal.Value)
			end)

			bikeClone.AncestryChanged:Connect(function(_, parent)
				if not parent then
					fuelConn:Disconnect()
				end
			end)
		end
	end

	local batteryFolder = bikeClone:FindFirstChild("Battery")
	if batteryFolder then
		local currentChargeVal = batteryFolder:WaitForChild("CurrentCharge", 5)

		if currentChargeVal then
			if not savedCharge then
				task.defer(function()
					SetSavedCharge(plr, bikeName, currentChargeVal.Value)
				end)
			end

			local chargeConn
			chargeConn = currentChargeVal.Changed:Connect(function(newValue)
				SetSavedCharge(plr, bikeName, newValue)
			end)

			bikeClone.AncestryChanged:Connect(function(_, parent)
				if not parent then
					chargeConn:Disconnect()
				end
			end)
		end
	end

	for _, obj in ipairs(bikeClone:GetDescendants()) do
		if obj:IsA("ProximityPrompt") then
			obj.Enabled = false
		end
	end

	task.delay(1, function()
		if bikeClone and bikeClone.Parent then
			for _, obj in ipairs(bikeClone:GetDescendants()) do
				if obj:IsA("ProximityPrompt") then
					obj.Enabled = true
				end
			end
		end
	end)

	local bikeNameValue = Instance.new("StringValue")
	bikeNameValue.Name = "BikeName"
	bikeNameValue.Value = bikeName
	bikeNameValue.Parent = bikeClone

	bikes[plr] = bikes[plr] or {}

	for _, oldBike in ipairs(bikes[plr]) do
		if oldBike ~= bikeClone then
			oldBike:Destroy()
		end
	end
	bikes[plr] = {}

	table.insert(bikes[plr], bikeClone)

	if _G.ApplyAllBikeModifications then
		_G.ApplyAllBikeModifications(plr, bikeClone)
	end

	for _, seat in ipairs(bikeClone:GetDescendants()) do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				if seat.Occupant then
					drivingValue.Value = true
				else
					drivingValue.Value = false
				end
			end)
		end
	end
end)


RS.Remotes.DeleteBikeNew.OnServerEvent:Connect(function(plr: Player)
	if not bikes[plr] then return end

	for _, bike in ipairs(bikes[plr]) do
		if bike then
			local driving = bike:FindFirstChild("IsBeingDriven")
			if driving and driving.Value == true then
				game.ReplicatedStorage.CheckItout:FireClient(plr, "Driving")
				return
			end
		end
	end

	for _, bike in ipairs(bikes[plr]) do
		if bike then
			bike:Destroy()
		end
	end

	bikes[plr] = {}
	game.ReplicatedStorage.CheckItout:FireClient(plr, "Deleted")
end)

local saveStructure = {
	Inventory = {},
	ClaimedBikes = {},
	FuelData = {},
	ChargeData = {},
}
local PlayerProfileStore = ProfileService.GetProfileStore("PlayerSaveData", saveStructure)

local function AddBike(plr, bikeName, bikeData)
	local profile = Profiles[plr]
	if profile then
		local key = GetInventoryKey(bikeName)
		if profile.Data.Inventory[key] == nil then
			profile.Data.Inventory[key] = bikeData

			local bikeFolder = Instance.new("Folder", plr:FindFirstChild("Inventory"))
			bikeFolder.Name = bikeData.Name
			local bikeKind = Instance.new("StringValue", bikeFolder)
			bikeKind.Name = "Kind"
			bikeKind.Value = bikeData.Kind
			local bikeSpeed = Instance.new("IntValue", bikeFolder)
			bikeSpeed.Name = "Speed"
			bikeSpeed.Value = bikeData.Speed
			print("Player got bike")
		else
			print("Player already owns the bike!")
		end
	end
end

local function RemoveBike(plr, bikeName)
	local profile = Profiles[plr]
	if profile then
		local key = GetInventoryKey(bikeName)
		local bd = profile.Data.Inventory[key]
		if bd ~= nil then
			profile.Data.Inventory[key] = nil

			local bikeFolder = plr:FindFirstChild("Inventory"):FindFirstChild(bikeName)
			if bikeFolder then
				bikeFolder:Destroy()
			end
		end
	end
end

local function CheckOfflineBikePurchases(player)
	for bikeName, gamepassIds in pairs(GamepassBikes) do
		for _, passId in ipairs(gamepassIds) do
			local success, hasPass = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			if success and hasPass then
				local profile = Profiles[player]
				if profile then
					if not profile.Data.ClaimedGamepasses then
						profile.Data.ClaimedGamepasses = {}
					end

					local key = GetInventoryKey(bikeName)

					if profile.Data.Inventory[key] then
						profile.Data.ClaimedGamepasses[bikeName] = true
					end

					if profile.Data.Inventory[key] == nil and not profile.Data.ClaimedGamepasses[bikeName] then
						local bikeData = FindBikeDataFromName(bikeName)
						if bikeData then
							AddBike(player, bikeName, bikeData)
							profile.Data.ClaimedGamepasses[bikeName] = true
							print("Added bike (11/20 update)")
						end
					end
				end
				break
			end
		end
	end
end

local function PlayerDataLoaded(player)
	local profile = Profiles[player]

	if not profile.Data.ClaimedGamepasses then
		profile.Data.ClaimedGamepasses = {}
	end

	if not profile.Data.FuelData then
		profile.Data.FuelData = {}
	end

	if not profile.Data.ChargeData then
		profile.Data.ChargeData = {}
	end

	local inv = profile.Data.Inventory
	local InvFolder = Instance.new("Folder", player)
	InvFolder.Name = "Inventory"

	for _, bikeData in inv do
		local bikeFolder = Instance.new("Folder", InvFolder)
		bikeFolder.Name = bikeData.Name
		local bikeKind = Instance.new("StringValue", bikeFolder)
		bikeKind.Name = "Kind"
		bikeKind.Value = bikeData.Kind
		local bikeSpeed = Instance.new("StringValue", bikeFolder)
		bikeSpeed.Name = "Speed"
		bikeSpeed.Value = bikeData.Speed
	end
	print("Bikes Added to ", player)
	spawn(function()
		CheckOfflineBikePurchases(player)
	end)
end

local function PlayerAdded(player)
	local profile = PlayerProfileStore:LoadProfileAsync("Player_" .. player.UserId, "ForceLoad")

	if profile ~= nil then
		profile:ListenToRelease(function()
			Profiles[player] = nil
			player:Kick("Your profile has been loaded remotely. Please rejoin.")
		end)

		if player:IsDescendantOf(Players) then
			Profiles[player] = profile
			PlayerDataLoaded(player)
		else
			profile:Release()
		end
	else
		player:Kick("Unable to load saved data. Please rejoin.")
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	spawn(function()
		PlayerAdded(player)
	end)
end

Players.PlayerAdded:Connect(PlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	local profile = Profiles[player]
	if profile ~= nil then
		if bikes[player] then
			for _, bike in bikes[player] do
				bike:Destroy()
			end
			bikes[player] = {}
		end
		profile:Release()
		bikes[player] = nil
	end
end)

RS.Remotes.PurchaseBike.OnServerEvent:Connect(function(plr: Player, bikeName: string, bikeData)
	local ls = plr:FindFirstChild("leaderstats")
	local m = ls["$"]
	if m.Value > bikeData.Price then
		ls["$"].Value = ls["$"].Value - bikeData.Price
		AddBike(plr, bikeName, bikeData)
	end
end)

RS.Remotes.SellBike.OnServerEvent:Connect(function(plr: Player, bikeName: string)
	local profile = Profiles[plr]
	local key = GetInventoryKey(bikeName)
	local bd = profile.Data.Inventory[key]
	local ls = plr:FindFirstChild("leaderstats")
	local m = ls["$"]
	m.Value = m.Value + bd.Price
	RemoveBike(plr, bikeName)
end)

GiveCodeBike.Event:Connect(function(plr, bikeName)
	if not bikeName then return end
	local bikeData = FindBikeDataFromName(bikeName)
	if bikeData then
		AddBike(plr, bikeName, bikeData)
	end	
end)

local AdminAddBikeEvent = RS:WaitForChild("BikeGiver"):WaitForChild("Remotes"):WaitForChild("AdminAddBike")
AdminAddBikeEvent.Event:Connect(function(targetPlayer, bikeName, bikeData)
	AddBike(targetPlayer, bikeName, bikeData)
end)

local AdminRemoveBikeEvent = RS:WaitForChild("BikeGiver"):WaitForChild("Remotes"):WaitForChild("AdminRemoveBike")
AdminRemoveBikeEvent.Event:Connect(function(targetPlayer, bikeName)
	RemoveBike(targetPlayer, bikeName)
end)

local GetDataEvent = RS.Remotes.GetData
local GetAllBikes = RS.Remotes.GetAllBikes
local GetTradingBikes = RS.Remotes.GetTradingBikes

GetDataEvent.OnServerInvoke = function(plr, stat)
	local profile = Profiles[plr]
	if profile then
		local key = GetInventoryKey(stat)
		return profile.Data.Inventory[key]
	end
	return nil
end

GetAllBikes.OnServerInvoke = function(plr)
	local profile = Profiles[plr]
	if profile then
		return profile.Data.Inventory
	end
end

GetTradingBikes.OnServerInvoke = function(plr)
	local profile = Profiles[plr]
	if profile then
		local limitedBikes = {}
		for bikeKey, bikeData in pairs(profile.Data.Inventory) do
			if bikeData.Kind and bikeData.Kind == "LIMITED" then
				limitedBikes[bikeKey] = bikeData
			end
		end
		return limitedBikes
	end
end

local CheckBikeOwnership = RS.Remotes:FindFirstChild("CheckBikeOwnership")

CheckBikeOwnership.OnServerInvoke = function(plr, targetPlayerName, bikeName)
	local targetPlayer = Players:FindFirstChild(targetPlayerName)
	if targetPlayer and targetPlayer:FindFirstChild("Inventory") then
		return targetPlayer.Inventory:FindFirstChild(bikeName) ~= nil
	end
	return false
end

local TradeRemote = game:GetService("ReplicatedStorage").Remotes.TradeEvent

TradeRemote.OnServerEvent:Connect(function(plr: Player, eventType: string, Arg1, Arg2, Arg3, securityKey)
	if Arg1 ~= "Ready" and Arg1 ~= "Unready" and Arg1 ~= "Confirm" and Arg1 ~= "Unconfirm" and securityKey ~= KEYGEN() and securityKey ~= pastKey then
		warn("Keys don't match, must be an exploit")
		return
	end

	if eventType == "Trade" then
		local tradeType = Arg1

		if tradeType == "Request" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2)
			TradeRemote:FireClient(tradeParticipant, "Trade", "Request", plr.Name, KEYGEN())
		elseif tradeType == "Start" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2)
			TradeRemote:FireClient(tradeParticipant, "Trade", "Start", plr.Name, KEYGEN())

			if not plr:FindFirstChild("TradeStatus") then
				local TradeStatus = Instance.new("BoolValue")
				TradeStatus.Name = "TradeStatus"
				TradeStatus.Value = false
				TradeStatus.Parent = plr

				local BikeTradeFolder = Instance.new("Folder", plr)
				BikeTradeFolder.Name = "BikeTradeFolder"
			else
				plr.TradeStatus.Value = false
				for _, bike in plr.BikeTradeFolder:GetChildren() do
					bike:Destroy()
				end
			end

			if not tradeParticipant:FindFirstChild("TradeStatus") then
				local TradeStatus = Instance.new("BoolValue")
				TradeStatus.Name = "TradeStatus"
				TradeStatus.Value = false
				TradeStatus.Parent = tradeParticipant

				local BikeTradeFolder = Instance.new("Folder", tradeParticipant)
				BikeTradeFolder.Name = "BikeTradeFolder"
			else
				tradeParticipant.TradeStatus.Value = false
				for _, bike in tradeParticipant.BikeTradeFolder:GetChildren() do
					bike:Destroy()
				end
			end
		elseif tradeType == "Ready" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2)

			plr.TradeStatus.Value = true

			TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerReady", plr.Name)

			if plr.TradeStatus.Value == true and tradeParticipant.TradeStatus.Value == true then
				plr.TradeStatus.Value = false
				tradeParticipant.TradeStatus.Value = false

				local plrBikesData = getTradedBikesData(plr)
				local tradeParticipantBikesData = getTradedBikesData(tradeParticipant)

				local finalTable = {
					[plr.Name] = plrBikesData,
					[tradeParticipant.Name] = tradeParticipantBikesData
				}

				TradeRemote:FireClient(plr, "Trade", "Confirm", finalTable, KEYGEN())
				TradeRemote:FireClient(tradeParticipant, "Trade", "Confirm", finalTable, KEYGEN())
			end
		elseif tradeType == "Confirm" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2)

			plr.TradeStatus.Value = true
			TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerConfirm", plr.Name)

			if plr.TradeStatus.Value == true and tradeParticipant.TradeStatus.Value == true then

				for _, v in pairs(plr.BikeTradeFolder:GetChildren()) do
					local profile = Profiles[plr]
					local key = GetInventoryKey(v.Name)
					if profile and profile.Data.Inventory[key] then
						local completeBikeData = profile.Data.Inventory[key]
						local bikeDataCopy = {
							Name = completeBikeData.Name,
							Kind = completeBikeData.Kind,
							Speed = completeBikeData.Speed,
							Price = completeBikeData.Price,
						}
						AddBike(tradeParticipant, v.Name, bikeDataCopy)
					else
						local bikeData = FindBikeDataFromName(v.Name)
						if not bikeData then warn("Invalid bike") continue end
						AddBike(tradeParticipant, v.Name, bikeData)
					end
				end

				for _, v in pairs(tradeParticipant.BikeTradeFolder:GetChildren()) do
					local profile = Profiles[tradeParticipant]
					local key = GetInventoryKey(v.Name)
					if profile and profile.Data.Inventory[key] then
						local completeBikeData = profile.Data.Inventory[key]
						local bikeDataCopy = {
							Name = completeBikeData.Name,
							Kind = completeBikeData.Kind,
							Speed = completeBikeData.Speed,
							Price = completeBikeData.Price,
						}
						AddBike(plr, v.Name, bikeDataCopy)
					else
						local bikeData = FindBikeDataFromName(v.Name)
						if not bikeData then warn("Invalid bike") continue end
						AddBike(plr, v.Name, bikeData)
					end
				end

				for _, bike in plr.BikeTradeFolder:GetChildren() do
					local inv = plr:FindFirstChild("Inventory")
					for _, bike2 in inv:GetChildren() do
						if bike.Name == bike2.Name then
							RemoveBike(plr, bike2.Name)
						end
					end
				end

				for _, bike in tradeParticipant.BikeTradeFolder:GetChildren() do
					local inv = tradeParticipant:FindFirstChild("Inventory")
					for _, bike2 in inv:GetChildren() do
						if bike.Name == bike2.Name then
							RemoveBike(tradeParticipant, bike2.Name)
						end
					end
				end

				TradeRemote:FireClient(plr, "Trade", "End", nil, KEYGEN())
				TradeRemote:FireClient(tradeParticipant, "Trade", "End", nil, KEYGEN())
			end
		elseif tradeType == "Unconfirm" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2)
			plr.TradeStatus.Value = false

			if tradeParticipant then
				TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerUnconfirm", plr.Name)
			end
		elseif tradeType == "Unready" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2)

			plr.TradeStatus.Value = false

			if tradeParticipant then
				TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerUnready", plr.Name)
			end
		elseif tradeType == "AutoUnready" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2)

			plr.TradeStatus.Value = false

			if tradeParticipant then
				TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerUnready", plr.Name)
				TradeRemote:FireClient(plr, "Trade", "PlayerUnready", plr.Name)
			end
		elseif tradeType == "UnreadyOtherPlayer" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2)

			if tradeParticipant then
				tradeParticipant.TradeStatus.Value = false

				TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerUnready", tradeParticipant.Name)
				TradeRemote:FireClient(plr, "Trade", "PlayerUnready", tradeParticipant.Name)
			end
		elseif tradeType == "Select" then
			local bikeData = Arg2
			local tradeParticipant = game.Players:FindFirstChild(Arg3)

			if plr.BikeTradeFolder:FindFirstChild(bikeData.Name) then
				plr.BikeTradeFolder:FindFirstChild(bikeData.Name):Destroy()
			elseif not plr.BikeTradeFolder:FindFirstChild(bikeData.Name) then
				local profile = Profiles[plr]
				local completeBikeData = nil
				local key = GetInventoryKey(bikeData.Name)

				if profile and profile.Data.Inventory[key] then
					completeBikeData = profile.Data.Inventory[key]
				else
					warn("Exploit")
					return
				end

				local TradeBike = Instance.new("Folder", plr.BikeTradeFolder)
				TradeBike.Name = completeBikeData.Name

				local Kind = Instance.new("StringValue", TradeBike)
				Kind.Name = "Kind"
				Kind.Value = completeBikeData.Kind

				local Speed = Instance.new("IntValue", TradeBike)
				Speed.Name = "Speed"
				Speed.Value = completeBikeData.Speed
			end

			local displayData = bikeData
			local key = GetInventoryKey(bikeData.Name)
			if Profiles[plr] and Profiles[plr].Data.Inventory[key] then
				displayData = Profiles[plr].Data.Inventory[key]
			end

			TradeRemote:FireClient(tradeParticipant, "Trade", "BikeDisplay", displayData, KEYGEN())
		elseif tradeType == "Decline" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2)
			TradeRemote:FireClient(tradeParticipant, "Trade", "Decline", plr, KEYGEN())
		end
	end
end)

game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(plr: Player, gamepassID: number, ifPurchased: boolean)
	if not ifPurchased then
		return
	end

	for bikeName, gamepassIds in pairs(GamepassBikes) do
		for _, passId in ipairs(gamepassIds) do
			if passId == gamepassID then
				print("found ID")
				local bikeData = FindBikeDataFromName(bikeName)
				if bikeData then
					print("Got bike data")
					AddBike(plr, bikeName, bikeData)

					local profile = Profiles[plr]
					if profile then
						if not profile.Data.ClaimedGamepasses then
							profile.Data.ClaimedGamepasses = {}
						end
						profile.Data.ClaimedGamepasses[bikeName] = true
					end

					print("test")
				end
				break
			end
		end
	end
end)

game:GetService("MarketplaceService").PromptProductPurchaseFinished:Connect(function(userID: number, productID: number, ifPurchased: boolean)
	if not ifPurchased then
		return
	end

	local plr = game.Players:GetPlayerByUserId(userID)
	if plr then
		local bikeData = FindBikeNameFromProductID(productID)
		if bikeData then
			AddBike(plr, bikeData.Name, bikeData)
			RS.Remotes.PurchaseBike:FireClient(plr, productID)
			print("Success!")
		end
	end
end)

return Profiles
