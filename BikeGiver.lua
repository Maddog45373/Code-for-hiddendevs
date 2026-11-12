local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BikeGiverUI = script.Parent
local BikeGiverFrame = BikeGiverUI:WaitForChild("BikeGiver")
local ContentFrame = BikeGiverFrame:WaitForChild("Content")
local BikeScrollingFrame = ContentFrame:WaitForChild("ScrollingFrame")
local ProfilesFrame = BikeGiverFrame:WaitForChild("Profiles")
local PlayerScrollingFrame = ProfilesFrame:WaitForChild("ScrollingFrame")

local Templates = ReplicatedStorage:WaitForChild("BikeGiver"):WaitForChild("Templates")
local BikeTemplate = Templates:WaitForChild("BikeTemplate")
local UserTemplate = Templates:WaitForChild("UserTemplate")

local RemotesFolder = ReplicatedStorage.BikeGiver:WaitForChild("Remotes")
local GetBikeListRemote = RemotesFolder:WaitForChild("GetBikeList")
local GetPlayerListRemote = RemotesFolder:WaitForChild("GetPlayerList")
local GiveBikeRemote = RemotesFolder:WaitForChild("GiveBike")
local CheckBikeOwnershipRemote = RemotesFolder:WaitForChild("CheckBikeOwnership")

local selectedBike = nil
local selectedPlayer = nil
local selectedBikeButton = nil
local selectedPlayerButton = nil

local deleteMode = false
local DELETE_MODE_COLOR = Color3.fromRGB(255, 50, 50)

local SELECTED_COLOR = Color3.fromRGB(247, 232, 16)
local DEFAULT_COLOR = Color3.fromRGB(0, 0, 0)

local function ClearScrollingFrame(scrollingFrame)
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child:IsA("ImageButton") or child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function PopulateBikes()
	ClearScrollingFrame(BikeScrollingFrame)

	local success, bikeList = pcall(function()
		return GetBikeListRemote:InvokeServer()
	end)

	if not success or not bikeList then
		warn("Failed to get bike list")
		return
	end

	table.sort(bikeList, function(a, b)
		return a.Name < b.Name
	end)

	for index, bikeData in ipairs(bikeList) do
		local bikeButton = BikeTemplate:Clone()
		bikeButton.Name = bikeData.Name
		bikeButton.Parent = BikeScrollingFrame

		local bikeNameLabel = bikeButton:FindFirstChild("BikeName")
		if bikeNameLabel then
			bikeNameLabel.Text = bikeData.Name
		end

		bikeButton.Position = UDim2.new(0, 5, 0, (index - 1) * (bikeButton.Size.Y.Offset + 5))

		bikeButton.MouseButton1Click:Connect(function()
			if selectedBike == bikeData.Name then
				selectedBike = nil
				selectedBikeButton = nil

				local stroke = bikeButton:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = DEFAULT_COLOR
				end

				print("Unselected bike")
				return
			end

			if selectedPlayer and not deleteMode then
				local hasBlock, alreadyHasBike = pcall(function()
					return CheckBikeOwnershipRemote:InvokeServer(selectedPlayer, bikeData.Name)
				end)

				if hasBlock and alreadyHasBike then
					warn(selectedPlayer .. " already has " .. bikeData.Name)

					selectedBike = nil
					selectedBikeButton = nil

					for _, btn in pairs(BikeScrollingFrame:GetChildren()) do
						if btn:IsA("ImageButton") then
							local stroke = btn:FindFirstChildOfClass("UIStroke")
							if stroke then
								stroke.Color = DEFAULT_COLOR
							end
						end
					end
					return
				end
			end

			selectedBike = bikeData.Name
			selectedBikeButton = bikeButton

			for _, btn in pairs(BikeScrollingFrame:GetChildren()) do
				if btn:IsA("ImageButton") then
					local stroke = btn:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = DEFAULT_COLOR
					end
				end
			end

			local selectedStroke = bikeButton:FindFirstChildOfClass("UIStroke")
			if selectedStroke then
				selectedStroke.Color = deleteMode and DELETE_MODE_COLOR or SELECTED_COLOR
			end

			print("Selected bike: " .. selectedBike)

			if selectedPlayer then
				GiveBike()
			end
		end)
	end

	local contentHeight = #bikeList * (BikeTemplate.Size.Y.Offset + 5)
	BikeScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, contentHeight)
end

local function PopulatePlayers()
	ClearScrollingFrame(PlayerScrollingFrame)

	local success, playerList = pcall(function()
		return GetPlayerListRemote:InvokeServer()
	end)

	if not success or not playerList then
		warn("Failed to get player list")
		return
	end

	table.sort(playerList, function(a, b)
		return a.Name < b.Name
	end)

	for index, playerData in ipairs(playerList) do
		local playerButton = UserTemplate:Clone()
		playerButton.Name = playerData.Name
		playerButton.Parent = PlayerScrollingFrame

		local playerNameLabel = playerButton:FindFirstChild("PlayerName")
		if playerNameLabel then
			playerNameLabel.Text = playerData.DisplayName or playerData.Name
		end

		local playerPhoto = playerButton:FindFirstChild("PlayerPhoto")
		if playerPhoto and playerPhoto:IsA("ImageLabel") then
			local success, thumbnailUrl = pcall(function()
				return Players:GetUserThumbnailAsync(
					playerData.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size150x150
				)
			end)

			if success and thumbnailUrl then
				playerPhoto.Image = thumbnailUrl
			end
		end

		playerButton.Position = UDim2.new(0, 5, 0, (index - 1) * (playerButton.Size.Y.Offset + 5))

		playerButton.MouseButton1Click:Connect(function()
			if selectedPlayer == playerData.Name then
				selectedPlayer = nil
				selectedPlayerButton = nil

				local stroke = playerButton:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = DEFAULT_COLOR
				end

				print("Unselected player")
				return
			end

			selectedPlayer = playerData.Name
			selectedPlayerButton = playerButton

			for _, btn in pairs(PlayerScrollingFrame:GetChildren()) do
				if btn:IsA("ImageButton") or btn:IsA("Frame") then
					local stroke = btn:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = DEFAULT_COLOR
					end
				end
			end

			local selectedStroke = playerButton:FindFirstChildOfClass("UIStroke")
			if selectedStroke then
				selectedStroke.Color = deleteMode and DELETE_MODE_COLOR or SELECTED_COLOR
			end

			print("Selected player: " .. selectedPlayer)

			if selectedBike then
				if deleteMode then
					GiveBike()
				else
					local hasBlock, alreadyHasBike = pcall(function()
						return CheckBikeOwnershipRemote:InvokeServer(selectedPlayer, selectedBike)
					end)

					if hasBlock and alreadyHasBike then
						warn(selectedPlayer .. " already has " .. selectedBike)

						selectedBike = nil
						selectedBikeButton = nil

						for _, btn in pairs(BikeScrollingFrame:GetChildren()) do
							if btn:IsA("ImageButton") then
								local stroke = btn:FindFirstChildOfClass("UIStroke")
								if stroke then
									stroke.Color = DEFAULT_COLOR
								end
							end
						end
					else
						GiveBike()
					end
				end
			end
		end)
	end

	local contentHeight = #playerList * (UserTemplate.Size.Y.Offset + 5)
	PlayerScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, contentHeight)
end

GiveBike = function()
	if not selectedBike then
		return
	end

	if not selectedPlayer then
		return
	end

	if deleteMode then
		local RemoveBikeRemote = RemotesFolder:FindFirstChild("RemoveBike")
		if RemoveBikeRemote then
			RemoveBikeRemote:FireServer(selectedPlayer, selectedBike)
			script.Parent.Parent.Clicked.Value = true
			task.delay(0.2,(function()
				script.Parent.Parent.Clicked.Value = false
			end))
			print("Deleted " .. selectedBike .. " from " .. selectedPlayer)
		end
	else
		local hasBlock, alreadyHasBike = pcall(function()
			return CheckBikeOwnershipRemote:InvokeServer(selectedPlayer, selectedBike)
		end)

		if hasBlock and alreadyHasBike then
			warn(selectedPlayer .. " already has " .. selectedBike .. "!")
			selectedBike = nil
			selectedBikeButton = nil

			for _, btn in pairs(BikeScrollingFrame:GetChildren()) do
				if btn:IsA("ImageButton") then
					local stroke = btn:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = DEFAULT_COLOR
					end
				end
			end
			return
		end

		GiveBikeRemote:FireServer(selectedPlayer, selectedBike)
		print("Successfully gave " .. selectedBike .. " to " .. selectedPlayer)
	end

	selectedBike = nil
	selectedPlayer = nil
	selectedBikeButton = nil
	selectedPlayerButton = nil

	for _, btn in pairs(BikeScrollingFrame:GetChildren()) do
		if btn:IsA("ImageButton") then
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = DEFAULT_COLOR
			end
		end
	end

	for _, btn in pairs(PlayerScrollingFrame:GetChildren()) do
		if btn:IsA("ImageButton") or btn:IsA("Frame") then
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = DEFAULT_COLOR
			end
		end
	end
end

BikeGiverUI:GetPropertyChangedSignal("Enabled"):Connect(function()
	if BikeGiverUI.Enabled then
		print(11)
		PopulateBikes()
		PopulatePlayers()
	end
end)

Players.PlayerAdded:Connect(function()
	if BikeGiverUI.Enabled then
		PopulatePlayers()
	end
end)

Players.PlayerRemoving:Connect(function()
	if BikeGiverUI.Enabled then
		PopulatePlayers()
	end
end)

if BikeGiverUI.Enabled then
	PopulateBikes()
	PopulatePlayers()
end

local HeaderFrame = BikeGiverFrame:FindFirstChild("Header")
if HeaderFrame then
	local DeleteButton = HeaderFrame:FindFirstChild("Delete")
	if DeleteButton then
		local DeleteTextLabel = DeleteButton:FindFirstChild("Text")

		DeleteButton.MouseButton1Click:Connect(function()
			deleteMode = not deleteMode

			local deleteStroke = DeleteButton:FindFirstChildOfClass("UIStroke")
			if deleteStroke then
				if deleteMode then
					DeleteButton.BackgroundColor3 = DELETE_MODE_COLOR
					if DeleteTextLabel then
						DeleteTextLabel.Text = "DELETE"
					end
					print("DELETE MODE ENABLED")
				else
					DeleteButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					if DeleteTextLabel then
						DeleteTextLabel.Text = "GIVE"
					end
					print("GIVE MODE ENABLED")
				end
			end

			selectedBike = nil
			selectedPlayer = nil
			selectedBikeButton = nil
			selectedPlayerButton = nil

			for _, btn in pairs(BikeScrollingFrame:GetChildren()) do
				if btn:IsA("ImageButton") then
					local stroke = btn:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = DEFAULT_COLOR
					end
				end
			end

			for _, btn in pairs(PlayerScrollingFrame:GetChildren()) do
				if btn:IsA("ImageButton") or btn:IsA("Frame") then
					local stroke = btn:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = DEFAULT_COLOR
					end
				end
			end
		end)
	end

	local CloseButton = HeaderFrame:FindFirstChild("Close")
	if CloseButton then
		CloseButton.MouseButton1Click:Connect(function()
			BikeGiverUI.Enabled = false
		end)
	end
end
