-- Discord: invis2_0 | Roblox: MaddogJB8
-- ProfileService by MadStudioRoblox: https://github.com/MadStudioRoblox/ProfileService
-- This module keeps bike ownership, spawned models, and trade displays connected to player profiles.
-- Type annotations describe expected values; they do not validate remote arguments at runtime.

type BikeData = {Name: string, Kind: string, Speed: number, Price: number}
type FuelData = {CurrentFuel: number, MaxFuel: number}
type ChargeData = {CurrentCharge: number}
type InventoryData = {[string]: BikeData}

local ProfileService = require(game.ReplicatedStorage.ProfileService) -- require loads the external persistence module; later profile calls use its session and save handling.
local RS = game:GetService("ReplicatedStorage") -- Shared models, shop data, and remotes are reached through this service reference.
local Players = game:GetService("Players") -- Provides the player lifecycle events used to load data and clean up on leaving.
local MarketplaceService = game:GetService("MarketplaceService") -- Provides pass-ownership queries and purchase notifications.
local Profiles = {} -- Indexing by Player keeps each active profile associated with its server player instance.

local Remotes = RS:WaitForChild("Remotes") -- Waiting avoids indexing this folder before it exists.
local GiveCodeBike = Remotes:WaitForChild("GiveCodeBike") -- The .Event connection below expects this to be a BindableEvent used by another script.

local INFINITE_ENERGY_PASS_ID = 1884377642 -- Keeping the pass ID in one place lets the energy check share one entitlement.

-- Check the pass on the server so energy scripts can read its result from the spawned model.
local function PlayerHasInfiniteEnergy(plr: Player): boolean
	if INFINITE_ENERGY_PASS_ID == 0 then return false end -- Zero acts as a disabled setting and avoids an unnecessary ownership query.
	local ok, owned = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, plr.UserId, INFINITE_ENERGY_PASS_ID) -- pcall catches lookup errors; the explicit service argument supplies the method receiver.
	return ok and owned -- A failed lookup cannot be treated as an owned pass.
end

local ShopList = RS:WaitForChild("ShopList") -- These modules supply bike descriptions used by rewards and product lookup.
local BikesFolder = RS:WaitForChild("Bikes") -- Model templates are separate from the live clones spawned into Workspace.

local function GetInventoryKey(bikeName: string): (string, number)
	return string.gsub(bikeName, " ", "_") -- gsub returns the normalized name and replacement count; single-variable callers take only the name.
end

-- Energy setters update profile memory. ProfileService, not these callbacks, handles persistence.
local function GetSavedFuel(plr: Player, bikeName: string): FuelData?
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	if not profile then return nil end -- No loaded profile means no saved value can be returned.
	if not profile.Data.FuelData then return nil end -- Older profiles may not have the fuel table yet.
	local key = GetInventoryKey(bikeName) -- Use the same name format across inventory, fuel, and charge tables.
	return profile.Data.FuelData[key] -- A missing entry returns nil, allowing the caller to use the model's initial fuel.
end

local function SetSavedFuel(plr: Player, bikeName: string, currentFuel: number, maxFuel: number): ()
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	if not profile then return end -- There is no profile to mutate when loading has not completed or the session has been released.
	if not profile.Data.FuelData then
		profile.Data.FuelData = {} -- Create the new field lazily so older saved records can start storing fuel.
	end
	local key = GetInventoryKey(bikeName) -- Use the same name format across inventory, fuel, and charge tables.
	profile.Data.FuelData[key] = { -- Store a plain table; Roblox instances are not used as persisted fuel data.
		CurrentFuel = currentFuel, -- The amount is stored with its capacity rather than as a percentage.
		MaxFuel = maxFuel, -- Retaining capacity keeps the fuel record self-contained.
	}
end

local function GetSavedCharge(plr: Player, bikeName: string): ChargeData?
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	if not profile then return nil end -- No loaded profile means no saved value can be returned.
	if not profile.Data.ChargeData then return nil end -- Missing charge data is treated as a first-time value, not zero charge.
	local key = GetInventoryKey(bikeName) -- Use the same name format across inventory, fuel, and charge tables.
	return profile.Data.ChargeData[key] -- Return the record so the spawn code can distinguish nil from an existing zero value.
end

local function SetSavedCharge(plr: Player, bikeName: string, currentCharge: number): ()
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	if not profile then return end -- There is no profile to mutate when loading has not completed or the session has been released.
	if not profile.Data.ChargeData then
		profile.Data.ChargeData = {} -- Add the charge field when an older profile first needs it.
	end
	local key = GetInventoryKey(bikeName) -- Use the same name format across inventory, fuel, and charge tables.
	profile.Data.ChargeData[key] = { -- The normalized bike name separates the charge records for different bikes.
		CurrentCharge = currentCharge, -- Only the current amount is included in this charge record.
	}
end

local function FindBikeModel(bikeName: string): Model?
	local normalizedTarget = string.lower(string.gsub(bikeName, " ", "")) -- Ignoring spaces and case lets a shop name match a differently formatted model name.
	for _, child in ipairs(BikesFolder:GetDescendants()) do -- GetDescendants also searches templates inside nested folders.
		if child:IsA("Model") then -- Filter out parts, scripts, and other descendants before comparing model names.
			local normalizedChild = string.lower(string.gsub(child.Name, " ", "")) -- Both sides need the same normalization for the comparison to be meaningful.
			if normalizedChild == normalizedTarget then -- The first normalized match is the template used by the spawn request.
				return child -- Returning immediately avoids scanning the remaining descendants once a match is found.
			end
		end
	end
	return nil
end

-- Catalog lookups copy the four fields shared by inventory, rewards, and trading.
local function FindBikeDataFromName(bikeName: string): BikeData?
	for _, module in pairs(ShopList:GetChildren()) do -- Each shop category can keep its own module while this lookup searches all categories.
		if module:IsA("ModuleScript") then -- Only modules can be passed to require as catalog sources.
			local success, bikeList = pcall(require, module) -- A module error becomes a failed lookup result instead of stopping this function.
			if success and bikeList then -- Only traverse the returned catalog when loading succeeded and returned a value.
				for _, bikeData in pairs(bikeList) do -- pairs supports catalogs indexed by names as well as numeric positions.
					if bikeData.Name == bikeName then -- An exact catalog name selects the data copied into inventory.

						return {
							Name = bikeData.Name, -- Copy the display name into a new record instead of returning the catalog table itself.
							Kind = bikeData.Kind, -- Kind is used later to filter the limited-bike trading list.
							Speed = bikeData.Speed, -- Keep the speed field for the inventory and trade display values.
							Price = bikeData.Price, -- Keep the price field that the existing sell handler reads.
						}
					end
				end
			end
		end
	end
	return nil
end

local function FindBikeNameFromProductID(ID: number): BikeData?
	for _, module in pairs(ShopList:GetChildren()) do -- Each shop category can keep its own module while this lookup searches all categories.
		if module:IsA("ModuleScript") then -- Only modules can be passed to require as catalog sources.
			local success, bikeList = pcall(require, module) -- A module error becomes a failed lookup result instead of stopping this function.
			if success and bikeList then -- Only traverse the returned catalog when loading succeeded and returned a value.
				for _, bikeData in pairs(bikeList) do -- pairs supports catalogs indexed by names as well as numeric positions.
					if bikeData.Robux == true and bikeData.ProductID == ID then -- The product lookup needs both the Robux flag and a matching product identifier.
						return {
							Name = bikeData.Name, -- Copy the display name into a new record instead of returning the catalog table itself.
							Kind = bikeData.Kind, -- Kind is used later to filter the limited-bike trading list.
							Speed = bikeData.Speed, -- Keep the speed field for the inventory and trade display values.
							Price = bikeData.Price, -- Keep the price field that the existing sell handler reads.
						}
					end
				end
			end
		end
	end
	return nil
end

-- The trade GUI stores selected names as folders; this helper turns them into display records.
local function getTradedBikesData(Player: Player): {BikeData}
	local AllData = {} -- Confirmation displays need an array of selected bike records.

	for _, v in pairs(Player.BikeTradeFolder:GetChildren()) do -- The selection folder contains one child per offered bike name.
		local profile = Profiles[Player] -- Resolve the offer owner's profile rather than the recipient's profile.
		local key = GetInventoryKey(v.Name) -- Selection folders use display names, while saved inventory uses normalized keys.
		if profile and profile.Data.Inventory[key] then -- Prefer the player's saved bike fields when that entry is available.
			local completeBikeData = profile.Data.Inventory[key] -- Read the existing ownership entry before copying its fields.
			local bikeDataCopy = { -- A new table separates the copied record from the sender's table reference.
				Name = completeBikeData.Name, -- The copy retains the owned bike's display identity.
				Kind = completeBikeData.Kind, -- Keep its recorded category for the receiving display.
				Speed = completeBikeData.Speed, -- Copy the stored speed rather than a value from a trade GUI argument.
				Price = completeBikeData.Price, -- Retain the stored resale field when building the transferred record.
			}
			table.insert(AllData, bikeDataCopy)
		else
			local bikeData = FindBikeDataFromName(v.Name) -- This original fallback uses catalog data when the saved entry is absent; it is not proof of ownership.
			if not bikeData then warn("Invalid bike") continue end -- Skip just this missing catalog item so the surrounding loop can continue.
			table.insert(AllData, bikeData)
		end
	end

	return AllData -- The caller uses this list to assemble both sides of the confirmation display.
end

local refreshInterval = 30 -- The time-based key calculation uses thirty-second intervals.
local pastKey = 0 -- Keep the second generated key available to the remote handler.

-- These keys preserve the existing client protocol. Time-based seeds are predictable and do not prove authorization.
local function getNextRefreshTime(): (number, number)
	local currentTime = os.time() -- Calendar time supplies a shared input to the deterministic key calculation.
	local currentIntervalsPassed = math.floor(currentTime / refreshInterval) -- Divide seconds into interval numbers before converting back to boundary times.
	if currentIntervalsPassed < math.round(currentTime / refreshInterval) then -- The original calculation switches to the rounded interval in the second half of a window.
		currentIntervalsPassed = math.round(currentTime / refreshInterval)
	end
	local nextRefreshTime = (currentIntervalsPassed + 1) * refreshInterval -- The next calculated boundary becomes the primary random seed.
	local currentRefreshTime = currentIntervalsPassed * refreshInterval -- The current calculated boundary supplies the alternate seed.
	return nextRefreshTime, currentRefreshTime -- Both values are returned, so the annotation declares two numbers.
end

local function KEYGEN(): number
	local nextRefresh, current = getNextRefreshTime() -- Multiple assignment keeps both boundary values returned by the helper.
	local rng = Random.new(nextRefresh) -- A fixed seed gives repeatable output; this is not a secret authentication token.
	local key = rng:NextInteger(100000, 10000000) -- Generate the numeric token expected by the existing client protocol.

	local pastKeyRng = Random.new(current) -- The alternate time seed gives a second token for the existing comparison.
	pastKey = pastKeyRng:NextInteger(100000, 10000000) -- Update the outer variable read by the trade remote handler.

	return key
end

local bikes = {} -- Track live model instances separately from the saved ownership records.

local GamepassBikes = { -- Several bikes can share one pass ID, allowing a purchase to grant a bundle.
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

-- Roblox supplies plr as the sender. The remaining remote arguments still come from the client.
RS.Remotes.SpawnBike.OnServerEvent:Connect(function(plr: Player, bikeName: string): ()
	local char = plr.Character or plr.CharacterAdded:Wait() -- Use the current character or yield until a new one exists.
	local hrp = char:WaitForChild("HumanoidRootPart") -- The root supplies the player-relative transform for the spawn location.

	local bike = FindBikeModel(bikeName) -- Look up the requested template; this original handler does not check inventory ownership here.
	if not bike then return end -- Cloning requires a matching model, so an unknown name ends the handler.

	local bikeClone = bike:Clone() -- Use a separate model so runtime changes do not edit the reusable template.

	bikeClone:SetAttribute("InfiniteEnergy", PlayerHasInfiniteEnergy(plr)) -- Vehicle scripts can read the pass result from the model they belong to.

	local saved = GetSavedFuel(plr, bikeName) -- Nil means the model has no stored fuel record yet.
	if saved then
		bikeClone:SetAttribute("SavedFuel", saved.CurrentFuel) -- The vehicle's fuel script can use this attribute to restore its initial amount.
	end

	local savedCharge = GetSavedCharge(plr, bikeName) -- Charge is read separately because not every vehicle uses a gas tank.
	if savedCharge then
		bikeClone:SetAttribute("SavedCharge", savedCharge.CurrentCharge) -- Expose saved charge through the interface expected by the battery script.
	end

	bikeClone.Parent = workspace -- Parenting makes the clone part of the active world.
	bikeClone.Name = plr.Name .. "sCar" -- The live instance name identifies its owner rather than the catalog model.

	local spawnCF = hrp.CFrame * CFrame.new(0, 0, -5) -- Right-side multiplication applies the five-stud offset in character space; negative Z is forward.

	if bikeName == "Mini Mercedes Maybach" then -- This particular template needs an orientation correction after the spawn offset.
		spawnCF = spawnCF * CFrame.Angles( -- Apply the correction in the local space of the existing spawn transform.
			math.rad(90), -- CFrame.Angles expects radians, so convert the ninety-degree X rotation.
			0,
			0
		)
	end

	bikeClone:PivotTo(spawnCF) -- Move the entire model using its pivot instead of positioning each part separately.
	local drivingValue = Instance.new("BoolValue") -- Expose a driving flag that the delete handler can read later.
	drivingValue.Name = "IsBeingDriven" -- Both the seat listener and deletion check use this agreed name.
	drivingValue.Value = false -- The flag begins false until a seat occupancy change updates it.
	drivingValue.Parent = bikeClone

	local gasFolder = bikeClone:FindFirstChild("Gas") -- FindFirstChild allows vehicles without a gas system to skip fuel tracking.
	if gasFolder then
		local currentFuelVal = gasFolder:WaitForChild("CurrentFuel", 5) -- Wait briefly for fuel initialization without blocking forever on a missing value.
		local maxFuelVal = gasFolder:WaitForChild("MaxFuel", 5) -- The fuel record needs both the current amount and tank capacity.

		if currentFuelVal and maxFuelVal then -- Only attach fuel logic if both timed waits found their expected values.
			if not saved then -- Initialize the record only when the profile had no fuel record for this bike.
				task.defer(function(): ()
					SetSavedFuel(plr, bikeName, currentFuelVal.Value, maxFuelVal.Value) -- Read model defaults when the deferred callback runs and store them in profile memory.
				end)
			end

			local fuelConn -- The outer variable lets the ancestry callback disconnect this specific listener.
			fuelConn = currentFuelVal.Changed:Connect(function(newValue: number): ()
				SetSavedFuel(plr, bikeName, newValue, maxFuelVal.Value) -- ValueBase.Changed supplies the new numeric value, avoiding a polling loop.
			end)

			bikeClone.AncestryChanged:Connect(function(_: Instance, parent: Instance?): ()
				if not parent then -- A nil parent is used here as the signal that the model has been removed.
					fuelConn:Disconnect() -- Stop the fuel callback from retaining references after model removal.
				end
			end)
		end
	end

	local batteryFolder = bikeClone:FindFirstChild("Battery") -- Battery tracking is optional and independent of the gas folder.
	if batteryFolder then
		local currentChargeVal = batteryFolder:WaitForChild("CurrentCharge", 5) -- Give the battery script time to create its value before skipping tracking.

		if currentChargeVal then
			if not savedCharge then -- An existing charge record should not be initialized again from defaults.
				task.defer(function(): ()
					SetSavedCharge(plr, bikeName, currentChargeVal.Value) -- Capture the initial battery value for a bike with no saved charge record.
				end)
			end

			local chargeConn -- Keep the connection accessible to the model-removal callback.
			chargeConn = currentChargeVal.Changed:Connect(function(newValue: number): ()
				SetSavedCharge(plr, bikeName, newValue) -- Update the profile table on change; this does not call the data store every time.
			end)

			bikeClone.AncestryChanged:Connect(function(_: Instance, parent: Instance?): ()
				if not parent then -- A nil parent is used here as the signal that the model has been removed.
					chargeConn:Disconnect() -- Release the battery listener once the model has no parent.
				end
			end)
		end
	end

	for _, obj in ipairs(bikeClone:GetDescendants()) do -- Prompts may be nested inside parts or submodels, so direct children are not enough.
		if obj:IsA("ProximityPrompt") then -- Only interaction prompts should have their Enabled property changed here.
			obj.Enabled = false -- Temporarily block interactions while the vehicle finishes spawning.
		end
	end

	task.delay(1, function(): ()
		if bikeClone and bikeClone.Parent then -- The delayed callback must account for a clone removed during the delay.
			for _, obj in ipairs(bikeClone:GetDescendants()) do -- Prompts may be nested inside parts or submodels, so direct children are not enough.
				if obj:IsA("ProximityPrompt") then -- Only interaction prompts should have their Enabled property changed here.
					obj.Enabled = true -- The original behavior enables every prompt after the delay, regardless of its earlier state.
				end
			end
		end
	end)

	local bikeNameValue = Instance.new("StringValue") -- Keep the catalog name available after renaming the live model to the owner's name.
	bikeNameValue.Name = "BikeName" -- Other vehicle systems can locate the original identity through this child.
	bikeNameValue.Value = bikeName -- Save the requested display name, not the underscore inventory key.
	bikeNameValue.Parent = bikeClone

	bikes[plr] = bikes[plr] or {} -- Create this player's model list on their first spawn request.

	for _, oldBike in ipairs(bikes[plr]) do -- Walk the previously tracked models before recording the new clone.
		if oldBike ~= bikeClone then -- Avoid destroying the current clone if it is already in the tracked list.
			oldBike:Destroy() -- Remove the previous live vehicle rather than removing its saved ownership.
		end
	end
	bikes[plr] = {} -- Clear references to deleted models before future spawn or deletion operations.

	table.insert(bikes[plr], bikeClone) -- Record the live clone for the player's later delete and leave handlers.

	if _G.ApplyAllBikeModifications then -- Customization is an optional integration supplied by another server script.
		_G.ApplyAllBikeModifications(plr, bikeClone) -- Pass the owner and live model so that integration can apply their saved modifications.
	end

	for _, seat in ipairs(bikeClone:GetDescendants()) do -- A vehicle can contain seats below nested parts and models.
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then -- Both passenger seats and driving seats expose an Occupant property.
			seat:GetPropertyChangedSignal("Occupant"):Connect(function(): ()
				if seat.Occupant then -- This listener checks its own seat; the original logic does not combine occupancy across seats.
					drivingValue.Value = true -- An occupied seat sets the flag used to reject deletion.
				else
					drivingValue.Value = false -- The flag begins false until a seat occupancy change updates it.
				end
			end)
		end
	end
end)


-- Check the shared driving flag before removing the player's tracked live models.
RS.Remotes.DeleteBikeNew.OnServerEvent:Connect(function(plr: Player): ()
	if not bikes[plr] then return end -- A player without a tracked list has no model list for this handler to traverse.

	for _, bike in ipairs(bikes[plr]) do
		if bike then
			local driving = bike:FindFirstChild("IsBeingDriven") -- The deletion check reads the flag installed by the spawn handler.
			if driving and driving.Value == true then -- A true flag stops deletion before the destroy loop begins.
				game.ReplicatedStorage.CheckItout:FireClient(plr, "Driving") -- Tell only the requesting player why the delete action was rejected.
				return
			end
		end
	end

	for _, bike in ipairs(bikes[plr]) do
		if bike then
			bike:Destroy()
		end
	end

	bikes[plr] = {} -- Clear references to deleted models before future spawn or deletion operations.
	game.ReplicatedStorage.CheckItout:FireClient(plr, "Deleted") -- The GUI can update after the tracked models have been removed.
end)

local saveStructure = { -- This template defines the default fields for new profiles.
	Inventory = {}, -- Saved bike records are keyed by normalized names, not live model instances.
	ClaimedBikes = {}, -- Retain the original field for compatibility with the existing save structure.
	FuelData = {}, -- Fuel records are stored separately from ownership metadata.
	ChargeData = {}, -- Battery records can evolve without changing the bike inventory entries.
}
local PlayerProfileStore = ProfileService.GetProfileStore("PlayerSaveData", saveStructure) -- The store name and template connect this module to its existing saved records.

-- Ownership lives in the profile; the Folder and Value objects mirror it for the existing GUI.
local function AddBike(plr: Player, bikeName: string, bikeData: BikeData): ()
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	if profile then
		local key = GetInventoryKey(bikeName) -- Use the same name format across inventory, fuel, and charge tables.
		if profile.Data.Inventory[key] == nil then -- This inventory format grants only one entry for each normalized bike name.
			profile.Data.Inventory[key] = bikeData -- The profile table holds ownership; the folder below mirrors it for the GUI.

			local bikeFolder = Instance.new("Folder", plr:FindFirstChild("Inventory")) -- A folder per bike gives existing GUI code an instance-based inventory view.
			bikeFolder.Name = bikeData.Name -- The folder keeps the readable name even though the save key uses underscores.
			local bikeKind = Instance.new("StringValue", bikeFolder) -- A StringValue makes the category available through the replicated folder.
			bikeKind.Name = "Kind"
			bikeKind.Value = bikeData.Kind -- Use the same category value as the saved record.
			local bikeSpeed = Instance.new("IntValue", bikeFolder) -- Newly granted bikes expose speed through an integer value in the original implementation.
			bikeSpeed.Name = "Speed"
			bikeSpeed.Value = bikeData.Speed
			print("Player got bike")
		else
			print("Player already owns the bike!")
		end
	end
end

local function RemoveBike(plr: Player, bikeName: string): ()
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	if profile then
		local key = GetInventoryKey(bikeName) -- Use the same name format across inventory, fuel, and charge tables.
		local bd = profile.Data.Inventory[key] -- Read the saved record before removal or resale.
		if bd ~= nil then -- Only remove an inventory record that actually exists.
			profile.Data.Inventory[key] = nil -- Deleting the table entry removes the bike from saved ownership.

			local bikeFolder = plr:FindFirstChild("Inventory"):FindFirstChild(bikeName) -- Locate the corresponding GUI mirror by display name.
			if bikeFolder then
				bikeFolder:Destroy() -- Remove the display entry after removing its saved record.
			end
		end
	end
end

-- Join-time pass checks also catch passes bought while the player was outside this server.
local function CheckOfflineBikePurchases(player: Player): ()
	for bikeName, gamepassIds in pairs(GamepassBikes) do -- Iterate the bundle map so one pass can correspond to several bike names.
		for _, passId in ipairs(gamepassIds) do -- Each bike can list more than one pass that grants it.
			local success, hasPass = pcall(function(): boolean
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId) -- Query ownership by numeric user ID so username changes do not affect the check.
			end)
			if success and hasPass then -- A failed API call must not count as owning a pass.
				local profile = Profiles[player]
				if profile then
					if not profile.Data.ClaimedGamepasses then
						profile.Data.ClaimedGamepasses = {} -- Add the claim field when loading a profile created before it existed.
					end

					local key = GetInventoryKey(bikeName) -- Use the same name format across inventory, fuel, and charge tables.

					if profile.Data.Inventory[key] then
						profile.Data.ClaimedGamepasses[bikeName] = true -- Keep entitlement claims separate from current ownership so a sold reward is not granted on every join.
					end

					if profile.Data.Inventory[key] == nil and not profile.Data.ClaimedGamepasses[bikeName] then -- A missing bike is eligible only when its pass reward has not already been claimed.
						local bikeData = FindBikeDataFromName(bikeName) -- Resolve the reward name through the catalog before passing its fields to AddBike.
						if bikeData then
							AddBike(player, bikeName, bikeData)
							profile.Data.ClaimedGamepasses[bikeName] = true -- Keep entitlement claims separate from current ownership so a sold reward is not granted on every join.
							print("Added bike (11/20 update)")
						end
					end
				end
				break
			end
		end
	end
end

-- Rebuild replicated inventory from saved records, then check pass rewards separately.
local function PlayerDataLoaded(player: Player): ()
	local profile = Profiles[player]

	if not profile.Data.ClaimedGamepasses then
		profile.Data.ClaimedGamepasses = {} -- Add the claim field when loading a profile created before it existed.
	end

	if not profile.Data.FuelData then
		profile.Data.FuelData = {} -- Create the new field lazily so older saved records can start storing fuel.
	end

	if not profile.Data.ChargeData then
		profile.Data.ChargeData = {} -- Add the charge field when an older profile first needs it.
	end

	local inv = profile.Data.Inventory -- The saved table is the source used to rebuild the player's visible inventory.
	local InvFolder = Instance.new("Folder", player) -- Putting the mirror under Player makes it available to the existing client UI.
	InvFolder.Name = "Inventory"

	for _, bikeData in inv do -- Luau generalized iteration visits the records in the saved dictionary.
		local bikeFolder = Instance.new("Folder", InvFolder)
		bikeFolder.Name = bikeData.Name -- The folder keeps the readable name even though the save key uses underscores.
		local bikeKind = Instance.new("StringValue", bikeFolder) -- A StringValue makes the category available through the replicated folder.
		bikeKind.Name = "Kind"
		bikeKind.Value = bikeData.Kind -- Use the same category value as the saved record.
		local bikeSpeed = Instance.new("StringValue", bikeFolder) -- The original load path uses a StringValue here; its difference from AddBike is preserved.
		bikeSpeed.Name = "Speed"
		bikeSpeed.Value = bikeData.Speed
	end
	print("Bikes Added to ", player)
	spawn(function(): ()
		CheckOfflineBikePurchases(player) -- Check entitlements bought outside this server after inventory initialization.
	end)
end

-- Loading yields, so confirm that the player is still present before exposing the profile.
local function PlayerAdded(player: Player): ()
	local profile = PlayerProfileStore:LoadProfileAsync("Player_" .. player.UserId, "ForceLoad") -- The stable user ID keeps the same save key when the player changes their username.

	if profile ~= nil then
		profile:ListenToRelease(function(): ()
			Profiles[player] = nil -- Remove the active lookup when ProfileService releases this session.
			player:Kick("Your profile has been loaded remotely. Please rejoin.") -- The player should not keep interacting after their data session is released.
		end)

		if player:IsDescendantOf(Players) then -- Loading can yield, so check whether the player is still in the server.
			Profiles[player] = profile -- Make the loaded profile available to the helpers before rebuilding inventory.
			PlayerDataLoaded(player) -- Initialize the replicated inventory and optional saved fields after a successful load.
		else
			profile:Release() -- Release the session when it is no longer needed so another server can load it.
		end
	else
		player:Kick("Unable to load saved data. Please rejoin.") -- Stop play rather than continuing with a missing saved profile.
	end
end

for _, player in ipairs(Players:GetPlayers()) do -- Also load players who were already present when this module started.
	spawn(function(): ()
		PlayerAdded(player)
	end)
end

Players.PlayerAdded:Connect(PlayerAdded) -- Use the same load routine for future joins.

Players.PlayerRemoving:Connect(function(player: Player): ()
	local profile = Profiles[player]
	if profile ~= nil then
		if bikes[player] then
			for _, bike in bikes[player] do
				bike:Destroy()
			end
			bikes[player] = {}
		end
		profile:Release() -- Release the session when it is no longer needed so another server can load it.
		bikes[player] = nil -- Drop the per-player model-table reference after leaving.
	end
end)

-- Original purchase behavior is retained: the client-supplied bikeData is not validated by this handler.
RS.Remotes.PurchaseBike.OnServerEvent:Connect(function(plr: Player, bikeName: string, bikeData: BikeData): ()
	local ls = plr:FindFirstChild("leaderstats") -- Cash is managed by the existing leaderstats system rather than this profile template.
	local m = ls["$"] -- Bracket notation is needed because the currency child name is not a normal identifier.
	if m.Value > bikeData.Price then -- This original check uses the client-supplied price and requires more than the exact cost.
		ls["$"].Value = ls["$"].Value - bikeData.Price -- Subtract the supplied price before the existing AddBike call; no purchase validation is added here.
		AddBike(plr, bikeName, bikeData) -- Route the grant through the shared inventory helper so its folder mirror is also updated.
	end
end)

RS.Remotes.SellBike.OnServerEvent:Connect(function(plr: Player, bikeName: string): ()
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	local key = GetInventoryKey(bikeName) -- Use the same name format across inventory, fuel, and charge tables.
	local bd = profile.Data.Inventory[key] -- Read the saved record before removal or resale.
	local ls = plr:FindFirstChild("leaderstats") -- Cash is managed by the existing leaderstats system rather than this profile template.
	local m = ls["$"] -- Bracket notation is needed because the currency child name is not a normal identifier.
	m.Value = m.Value + bd.Price -- The original resale logic credits the price stored on the owned record.
	RemoveBike(plr, bikeName) -- Use the shared removal helper to update both the save table and inventory folder.
end)

-- BindableEvent rewards are script-to-script calls; they are not RemoteEvent client requests.
GiveCodeBike.Event:Connect(function(plr: Player, bikeName: string?): ()
	if not bikeName then return end -- The code-reward event may be called without a bike name.
	local bikeData = FindBikeDataFromName(bikeName) -- Resolve the reward name through the catalog before passing its fields to AddBike.
	if bikeData then
		AddBike(plr, bikeName, bikeData) -- Route the grant through the shared inventory helper so its folder mirror is also updated.
	end
end)

-- These bindable hooks share inventory helpers with purchases; the separate admin caller must authorize commands.
local AdminAddBikeEvent = RS:WaitForChild("BikeGiver"):WaitForChild("Remotes"):WaitForChild("AdminAddBike")
AdminAddBikeEvent.Event:Connect(function(targetPlayer: Player, bikeName: string, bikeData: BikeData): ()
	AddBike(targetPlayer, bikeName, bikeData)
end)

local AdminRemoveBikeEvent = RS:WaitForChild("BikeGiver"):WaitForChild("Remotes"):WaitForChild("AdminRemoveBike")
AdminRemoveBikeEvent.Event:Connect(function(targetPlayer: Player, bikeName: string): ()
	RemoveBike(targetPlayer, bikeName)
end)

local GetDataEvent = RS.Remotes.GetData -- RemoteFunctions return a value directly to the requesting GUI.
local GetAllBikes = RS.Remotes.GetAllBikes -- This endpoint returns the saved ownership dictionary.
local GetTradingBikes = RS.Remotes.GetTradingBikes -- This endpoint provides the limited-bike subset for the trade UI.

GetDataEvent.OnServerInvoke = function(plr: Player, stat: string): BikeData?
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	if profile then
		local key = GetInventoryKey(stat) -- Convert the requested display name to the save format before lookup.
		return profile.Data.Inventory[key] -- Return the matching saved bike record, or nil if it is absent.
	end
	return nil
end

GetAllBikes.OnServerInvoke = function(plr: Player): InventoryData?
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	if profile then
		return profile.Data.Inventory -- The RemoteFunction response is serialized to the client, rather than sharing table memory.
	end
end

GetTradingBikes.OnServerInvoke = function(plr: Player): InventoryData?
	local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
	if profile then
		local limitedBikes = {} -- Build a subset without removing entries from the actual inventory.
		for bikeKey, bikeData in pairs(profile.Data.Inventory) do
			if bikeData.Kind and bikeData.Kind == "LIMITED" then -- The trade list includes only records whose category matches the expected label.
				limitedBikes[bikeKey] = bikeData -- Keep the original key so GUI selections can still refer to the inventory entry.
			end
		end
		return limitedBikes
	end
end

local CheckBikeOwnership = RS.Remotes:FindFirstChild("CheckBikeOwnership")

CheckBikeOwnership.OnServerInvoke = function(plr: Player, targetPlayerName: string, bikeName: string): boolean
	local targetPlayer = Players:FindFirstChild(targetPlayerName) -- This ownership query targets a named player currently present in the server.
	if targetPlayer and targetPlayer:FindFirstChild("Inventory") then
		return targetPlayer.Inventory:FindFirstChild(bikeName) ~= nil -- The original endpoint reports the replicated inventory folder's membership.
	end
	return false
end

local TradeRemote = game:GetService("ReplicatedStorage").Remotes.TradeEvent -- One event carries different trade actions through its action-name arguments.

-- Arg2 stays any because this original protocol alternates between a name string and a bike table without runtime narrowing.
TradeRemote.OnServerEvent:Connect(function(plr: Player, eventType: string, Arg1: string, Arg2: any, Arg3: string?, securityKey: number?): ()
	if Arg1 ~= "Ready" and Arg1 ~= "Unready" and Arg1 ~= "Confirm" and Arg1 ~= "Unconfirm" and securityKey ~= KEYGEN() and securityKey ~= pastKey then -- These four actions bypass the token comparison; this check does not establish a verified trade session.
		warn("Keys don't match, must be an exploit")
		return
	end

	if eventType == "Trade" then -- Ignore messages that are not addressed to the trade action group.
		local tradeType = Arg1 -- The first action argument selects the branch within the trade protocol.

		if tradeType == "Request" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2) -- Most actions carry the requested partner name in Arg2; the original handler trusts that selection.
			TradeRemote:FireClient(tradeParticipant, "Trade", "Request", plr.Name, KEYGEN()) -- Send the requester's name so the other GUI can display an invitation.
		elseif tradeType == "Start" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2) -- Most actions carry the requested partner name in Arg2; the original handler trusts that selection.
			TradeRemote:FireClient(tradeParticipant, "Trade", "Start", plr.Name, KEYGEN()) -- Notify the chosen partner to open the existing trade interface.

			if not plr:FindFirstChild("TradeStatus") then -- Create status objects on the player's first trade instead of expecting them at join time.
				local TradeStatus = Instance.new("BoolValue") -- The original flow reuses one boolean for both readiness and confirmation.
				TradeStatus.Name = "TradeStatus"
				TradeStatus.Value = false -- A new trade begins without recorded consent.
				TradeStatus.Parent = plr

				local BikeTradeFolder = Instance.new("Folder", plr) -- The player's offered names are represented by child folders for the GUI.
				BikeTradeFolder.Name = "BikeTradeFolder"
			else
				plr.TradeStatus.Value = false -- Clear this player's ready or confirm flag for the next interaction.
				for _, bike in plr.BikeTradeFolder:GetChildren() do -- Clear selections from the player's previous trade attempt.
					bike:Destroy()
				end
			end

			if not tradeParticipant:FindFirstChild("TradeStatus") then
				local TradeStatus = Instance.new("BoolValue") -- The original flow reuses one boolean for both readiness and confirmation.
				TradeStatus.Name = "TradeStatus"
				TradeStatus.Value = false -- A new trade begins without recorded consent.
				TradeStatus.Parent = tradeParticipant

				local BikeTradeFolder = Instance.new("Folder", tradeParticipant) -- Create the same selection structure for the other participant.
				BikeTradeFolder.Name = "BikeTradeFolder"
			else
				tradeParticipant.TradeStatus.Value = false -- Clear the other participant's stage flag as part of the original flow.
				for _, bike in tradeParticipant.BikeTradeFolder:GetChildren() do -- Clear the partner's earlier offer before reuse or traverse it during final removal.
					bike:Destroy()
				end
			end
		elseif tradeType == "Ready" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2) -- Most actions carry the requested partner name in Arg2; the original handler trusts that selection.

			plr.TradeStatus.Value = true -- Mark this player's current stage as accepted using the existing shared boolean.

			TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerReady", plr.Name) -- Update the other GUI so it can display this player's readiness.

			if plr.TradeStatus.Value == true and tradeParticipant.TradeStatus.Value == true then -- Advance only when both existing booleans are true; this original check has no separate phase record.
				plr.TradeStatus.Value = false -- Clear this player's ready or confirm flag for the next interaction.
				tradeParticipant.TradeStatus.Value = false -- Clear the other participant's stage flag as part of the original flow.

				local plrBikesData = getTradedBikesData(plr) -- Convert this player's selected folders into the records used by confirmation UI.
				local tradeParticipantBikesData = getTradedBikesData(tradeParticipant) -- Build the matching confirmation data for the partner.

				local finalTable = { -- Key the two offer lists by player name so each GUI can label the sides.
					[plr.Name] = plrBikesData,
					[tradeParticipant.Name] = tradeParticipantBikesData
				}

				TradeRemote:FireClient(plr, "Trade", "Confirm", finalTable, KEYGEN()) -- Both participants receive the same prepared confirmation payload.
				TradeRemote:FireClient(tradeParticipant, "Trade", "Confirm", finalTable, KEYGEN())
			end
		elseif tradeType == "Confirm" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2) -- Most actions carry the requested partner name in Arg2; the original handler trusts that selection.

			plr.TradeStatus.Value = true -- Mark this player's current stage as accepted using the existing shared boolean.
			TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerConfirm", plr.Name) -- Notify the partner GUI when this player confirms.

			if plr.TradeStatus.Value == true and tradeParticipant.TradeStatus.Value == true then -- Advance only when both existing booleans are true; this original check has no separate phase record.

				for _, v in pairs(plr.BikeTradeFolder:GetChildren()) do -- The first transfer loop grants this player's selected bikes to the partner.
					local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
					local key = GetInventoryKey(v.Name) -- Selection folders use display names, while saved inventory uses normalized keys.
					if profile and profile.Data.Inventory[key] then -- Prefer the player's saved bike fields when that entry is available.
						local completeBikeData = profile.Data.Inventory[key] -- Read the existing ownership entry before copying its fields.
						local bikeDataCopy = { -- A new table separates the copied record from the sender's table reference.
							Name = completeBikeData.Name, -- The copy retains the owned bike's display identity.
							Kind = completeBikeData.Kind, -- Keep its recorded category for the receiving display.
							Speed = completeBikeData.Speed, -- Copy the stored speed rather than a value from a trade GUI argument.
							Price = completeBikeData.Price, -- Retain the stored resale field when building the transferred record.
						}
						AddBike(tradeParticipant, v.Name, bikeDataCopy) -- Grant a copied record to the receiver; the original sender removal happens in a later loop.
					else
						local bikeData = FindBikeDataFromName(v.Name) -- This original fallback uses catalog data when the saved entry is absent; it is not proof of ownership.
						if not bikeData then warn("Invalid bike") continue end -- Skip just this missing catalog item so the surrounding loop can continue.
						AddBike(tradeParticipant, v.Name, bikeData)
					end
				end

				for _, v in pairs(tradeParticipant.BikeTradeFolder:GetChildren()) do -- The second transfer loop handles the reverse direction.
					local profile = Profiles[tradeParticipant]
					local key = GetInventoryKey(v.Name) -- Selection folders use display names, while saved inventory uses normalized keys.
					if profile and profile.Data.Inventory[key] then -- Prefer the player's saved bike fields when that entry is available.
						local completeBikeData = profile.Data.Inventory[key] -- Read the existing ownership entry before copying its fields.
						local bikeDataCopy = { -- A new table separates the copied record from the sender's table reference.
							Name = completeBikeData.Name, -- The copy retains the owned bike's display identity.
							Kind = completeBikeData.Kind, -- Keep its recorded category for the receiving display.
							Speed = completeBikeData.Speed, -- Copy the stored speed rather than a value from a trade GUI argument.
							Price = completeBikeData.Price, -- Retain the stored resale field when building the transferred record.
						}
						AddBike(plr, v.Name, bikeDataCopy) -- Grant the partner's copied offer into this player's inventory.
					else
						local bikeData = FindBikeDataFromName(v.Name) -- This original fallback uses catalog data when the saved entry is absent; it is not proof of ownership.
						if not bikeData then warn("Invalid bike") continue end -- Skip just this missing catalog item so the surrounding loop can continue.
						AddBike(plr, v.Name, bikeData)
					end
				end

				for _, bike in plr.BikeTradeFolder:GetChildren() do -- Clear selections from the player's previous trade attempt.
					local inv = plr:FindFirstChild("Inventory") -- Find the sender's mirrored entries before removing names listed in the offer.
					for _, bike2 in inv:GetChildren() do
						if bike.Name == bike2.Name then -- Match display names so the selected offer identifies which owned entry to remove.
							RemoveBike(plr, bike2.Name) -- Remove the sender's entry after the earlier grant loop, preserving the original operation order.
						end
					end
				end

				for _, bike in tradeParticipant.BikeTradeFolder:GetChildren() do -- Clear the partner's earlier offer before reuse or traverse it during final removal.
					local inv = tradeParticipant:FindFirstChild("Inventory")
					for _, bike2 in inv:GetChildren() do
						if bike.Name == bike2.Name then -- Match display names so the selected offer identifies which owned entry to remove.
							RemoveBike(tradeParticipant, bike2.Name) -- Apply the same post-grant removal to the partner's selected entries.
						end
					end
				end

				TradeRemote:FireClient(plr, "Trade", "End", nil, KEYGEN()) -- End messages close the GUI; this original branch does not clear a separate server session.
				TradeRemote:FireClient(tradeParticipant, "Trade", "End", nil, KEYGEN())
			end
		elseif tradeType == "Unconfirm" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2) -- Most actions carry the requested partner name in Arg2; the original handler trusts that selection.
			plr.TradeStatus.Value = false -- Clear this player's ready or confirm flag for the next interaction.

			if tradeParticipant then
				TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerUnconfirm", plr.Name) -- Notify the partner that the player withdrew confirmation.
			end
		elseif tradeType == "Unready" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2) -- Most actions carry the requested partner name in Arg2; the original handler trusts that selection.

			plr.TradeStatus.Value = false -- Clear this player's ready or confirm flag for the next interaction.

			if tradeParticipant then
				TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerUnready", plr.Name) -- Notify the partner that this player is no longer ready.
			end
		elseif tradeType == "AutoUnready" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2) -- Most actions carry the requested partner name in Arg2; the original handler trusts that selection.

			plr.TradeStatus.Value = false -- Clear this player's ready or confirm flag for the next interaction.

			if tradeParticipant then
				TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerUnready", plr.Name) -- Notify the partner that this player is no longer ready.
				TradeRemote:FireClient(plr, "Trade", "PlayerUnready", plr.Name) -- Also update the sender's own readiness display during automatic resets.
			end
		elseif tradeType == "UnreadyOtherPlayer" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2) -- Most actions carry the requested partner name in Arg2; the original handler trusts that selection.

			if tradeParticipant then
				tradeParticipant.TradeStatus.Value = false -- Clear the other participant's stage flag as part of the original flow.

				TradeRemote:FireClient(tradeParticipant, "Trade", "PlayerUnready", tradeParticipant.Name)
				TradeRemote:FireClient(plr, "Trade", "PlayerUnready", tradeParticipant.Name)
			end
		elseif tradeType == "Select" then
			local bikeData = Arg2 -- Select uses a bike table here, while most other actions use Arg2 as a player name.
			local tradeParticipant = game.Players:FindFirstChild(Arg3) -- The selection action moves the partner name into Arg3 because Arg2 holds bike data.

			if plr.BikeTradeFolder:FindFirstChild(bikeData.Name) then -- Clicking an already selected bike toggles it out of the current offer.
				plr.BikeTradeFolder:FindFirstChild(bikeData.Name):Destroy() -- Remove the offered-name mirror, leaving actual ownership untouched at selection time.
			elseif not plr.BikeTradeFolder:FindFirstChild(bikeData.Name) then
				local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
				local completeBikeData = nil -- The selection branch will replace this only after finding an owned record.
				local key = GetInventoryKey(bikeData.Name) -- Use the selected name to find its saved ownership entry.

				if profile and profile.Data.Inventory[key] then -- Prefer the player's saved bike fields when that entry is available.
					completeBikeData = profile.Data.Inventory[key] -- Populate the selection display from server-held ownership data.
				else
					warn("Exploit")
					return
				end

				local TradeBike = Instance.new("Folder", plr.BikeTradeFolder) -- The child folder represents one selected offer, not a second owned bike.
				TradeBike.Name = completeBikeData.Name

				local Kind = Instance.new("StringValue", TradeBike)
				Kind.Name = "Kind"
				Kind.Value = completeBikeData.Kind -- The offered category comes from the owned record.

				local Speed = Instance.new("IntValue", TradeBike)
				Speed.Name = "Speed"
				Speed.Value = completeBikeData.Speed -- The offered speed also comes from the owned record.
			end

			local displayData = bikeData -- Keep the original fallback display payload before trying the server inventory lookup.
			local key = GetInventoryKey(bikeData.Name) -- Use the selected name to find its saved ownership entry.
			if Profiles[plr] and Profiles[plr].Data.Inventory[key] then
				displayData = Profiles[plr].Data.Inventory[key] -- Prefer the saved record for the partner's display when it is available.
			end

			TradeRemote:FireClient(tradeParticipant, "Trade", "BikeDisplay", displayData, KEYGEN()) -- Send the selected bike fields so the other trade GUI can update its offer list.
		elseif tradeType == "Decline" then
			local tradeParticipant = game.Players:FindFirstChild(Arg2) -- Most actions carry the requested partner name in Arg2; the original handler trusts that selection.
			TradeRemote:FireClient(tradeParticipant, "Trade", "Decline", plr, KEYGEN()) -- The existing decline message supplies the requesting Player instance to the partner GUI.
		end
	end
end)

-- The pass event is checked against the mapping so bundles can grant every associated bike.
game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(plr: Player, gamepassID: number, ifPurchased: boolean): ()
	if not ifPurchased then -- Skip the reward branch when the notification does not report a purchase.
		return
	end

	for bikeName, gamepassIds in pairs(GamepassBikes) do -- Iterate the bundle map so one pass can correspond to several bike names.
		for _, passId in ipairs(gamepassIds) do -- Each bike can list more than one pass that grants it.
			if passId == gamepassID then -- Match the purchased pass to every bike included in that pass's mapping.
				print("found ID")
				local bikeData = FindBikeDataFromName(bikeName) -- Resolve the reward name through the catalog before passing its fields to AddBike.
				if bikeData then
					print("Got bike data")
					AddBike(plr, bikeName, bikeData) -- Route the grant through the shared inventory helper so its folder mirror is also updated.

					local profile = Profiles[plr] -- Resolve the player's in-memory profile instead of opening a new data-store request.
					if profile then
						if not profile.Data.ClaimedGamepasses then
							profile.Data.ClaimedGamepasses = {} -- Add the claim field when loading a profile created before it existed.
						end
						profile.Data.ClaimedGamepasses[bikeName] = true -- Keep entitlement claims separate from current ownership so a sold reward is not granted on every join.
					end

					print("test")
				end
				break
			end
		end
	end
end)

-- Original product handler retained. PromptProductPurchaseFinished is not receipt verification; ProcessReceipt is required for reliable grants.
game:GetService("MarketplaceService").PromptProductPurchaseFinished:Connect(function(userID: number, productID: number, ifPurchased: boolean): ()
	if not ifPurchased then -- Skip the reward branch when the notification does not report a purchase.
		return
	end

	local plr = game.Players:GetPlayerByUserId(userID) -- This product notification provides a numeric user ID rather than a Player argument.
	if plr then
		local bikeData = FindBikeNameFromProductID(productID) -- Map the notified developer product to the bike catalog entry.
		if bikeData then
			AddBike(plr, bikeData.Name, bikeData)
			RS.Remotes.PurchaseBike:FireClient(plr, productID) -- The purchase GUI receives the product ID after the original grant call.
			print("Success!")
		end
	end
end)

return Profiles -- Requiring server scripts receive the same active-profile table used by this module.
