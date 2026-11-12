local DataStoreService = game:GetService("DataStoreService")
local PlayerCash = DataStoreService:GetDataStore("PlayerCash")
local PlayerCodes = DataStoreService:GetDataStore("PlayerCodes")
local FollowRewards = DataStoreService:GetDataStore("FollowRewards_v2")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLLOW_REWARD = 10000

-- Create the RemoteEvent for claiming reward
local claimEvent = Instance.new("RemoteEvent")
claimEvent.Name = "ClaimFollowReward"
claimEvent.Parent = ReplicatedStorage
local checkOwned = Instance.new("RemoteFunction")
checkOwned.Name = "CheckFollowReward"
checkOwned.Parent = ReplicatedStorage


function OnPlayerAdded(player)
	local stats = Instance.new("Folder", player)
	stats.Name = 'leaderstats'
	local Cash = Instance.new("NumberValue", stats)
	Cash.Name = "$"
	Cash.Value = 2500
	local DataLoaded = Instance.new("BoolValue", player)
	DataLoaded.Name = "CashDataLoaded"
	DataLoaded.Value = false
	local otherStats = Instance.new("Folder")
	otherStats.Name = "otherStats"
	otherStats.Parent = player
	local RedeemedCodes = Instance.new("StringValue")
	RedeemedCodes.Name = "RedeemedCodes"
	RedeemedCodes.Value = "[]"
	RedeemedCodes.Parent = otherStats

	-- Load cash
	local cashData
	local attempts = 10
	repeat
		local success, err = pcall(function()
			cashData = PlayerCash:GetAsync(player.UserId)
		end)
		if success then
			print("Cash loaded successfully!")
			DataLoaded.Value = true
			break
		else
			warn("Problem loading Cash DataStore (Attempts left: " .. attempts .. ")")
		end
		wait(1)
		attempts -= 1
	until attempts <= 0
	if cashData then
		Cash.Value = cashData
	end

	-- Load codes
	local codeData
	attempts = 10
	repeat
		local success, err = pcall(function()
			codeData = PlayerCodes:GetAsync(player.UserId)
		end)
		if success then
			print("Codes loaded successfully!")
			break
		else
			warn("Problem loading Codes DataStore (Attempts left: " .. attempts .. ")")
		end
		wait(1)
		attempts -= 1
	until attempts <= 0
	if codeData then
		RedeemedCodes.Value = codeData
	end
end

function OnPlayerRemoving(player)
	if player:FindFirstChild("CashDataLoaded") and player.CashDataLoaded.Value == true then
		local attempts = 10
		repeat
			local success, err = pcall(function()
				PlayerCash:SetAsync(player.UserId, player.leaderstats["$"].Value)
			end)
			if success then
				print("Cash saved successfully!")
				break
			else
				warn("Problem saving Cash DataStore (Attempts left: " .. attempts .. ")")
			end
			wait(1)
			attempts -= 1
		until attempts <= 0
	end
	if player:FindFirstChild("otherStats") then
		local redeemed = player.otherStats:FindFirstChild("RedeemedCodes")
		if redeemed then
			local attempts = 10
			repeat
				local success, err = pcall(function()
					PlayerCodes:SetAsync(player.UserId, redeemed.Value)
				end)
				if success then
					print("Codes saved successfully!")
					break
				else
					warn("Problem saving Codes DataStore (Attempts left: " .. attempts .. ")")
				end
				wait(1)
				attempts -= 1
			until attempts <= 0
		end
	end
end

game.Players.PlayerAdded:Connect(OnPlayerAdded)
game.Players.PlayerRemoving:Connect(OnPlayerRemoving)

-- Follow reward claim handler
claimEvent.OnServerEvent:Connect(function(player)
	local ok, alreadyClaimed = pcall(function()
		return FollowRewards:GetAsync(tostring(player.UserId))
	end)

	if ok and not alreadyClaimed then
		local cash = player.leaderstats:FindFirstChild("$")
		if cash then
			cash.Value += FOLLOW_REWARD
			pcall(function()
				FollowRewards:SetAsync(tostring(player.UserId), true)
			end)
			print(player.Name .. " claimed the follow reward!")
		end
	else
		print(player.Name .. " already claimed the follow reward!")
	end
end)

checkOwned.OnServerInvoke = function(player)
	local success, result = pcall(function()
		return FollowRewards:GetAsync(tostring(player.UserId))
	end)

	return result
end

local MarketplaceService = game:GetService("MarketplaceService")
local productCashMap = { -- BuyMoneyScript already handles this idk
						 -- If this is supposed to be here
	[3585449984] = 1000,
	[3585450141] = 2500,
	[3585450319] = 7500,
	[3585450464] = 10000,
	[3585450527] = 100000,
}


MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = game.Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local dataLoaded = player:FindFirstChild("CashDataLoaded")
	if dataLoaded and not dataLoaded.Value then
		dataLoaded.Changed:Wait()
	end
	local cashAmount = productCashMap[receiptInfo.ProductId]
	if cashAmount then
		local cash = player.leaderstats:FindFirstChild("$")
		if cash then
			cash.Value = cash.Value + cashAmount
			pcall(function()
				PlayerCash:SetAsync(player.UserId, cash.Value)
			end)
			print("Gave " .. cashAmount .. " to " .. player.Name)
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end