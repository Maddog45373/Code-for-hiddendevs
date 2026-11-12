local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("ButtonUI")
local HomeButtonFrame = gui:WaitForChild("HomeButtonFrame")


gui.Enabled = false

if UserInputService.TouchEnabled == true then
	gui.Enabled = true
end


local function updateGuiVisibility()
	if not UserInputService.TouchEnabled then
		
		gui.Enabled = false
		gui:WaitForChild("Frame").Visible = false
		gui:WaitForChild("HidemobileUI").Visible = false
		--gui:WaitForChild("HomeButtonFrame").Visible = false
		gui:WaitForChild("Tricks").Visible = false
		
		
		return
	end

	print("On mobile")
	
	local character = player.Character
	if character then
		
		local playerGui = player:WaitForChild("PlayerGui")
		local onScreenButtons = playerGui:WaitForChild("OnScreenButtons")
		local playerInfo = playerGui:WaitForChild("PlayerInfo")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.SeatPart and humanoid.SeatPart:IsA("VehicleSeat") then
			
			
			gui.Enabled = true
			gui:WaitForChild("Frame").Visible = true
			gui:WaitForChild("HidemobileUI").Visible = true
			--gui:WaitForChild("HomeButtonFrame").Visible = true
			gui:WaitForChild("Tricks").Visible = true
			onScreenButtons.Enabled = false
			playerInfo.Enabled = false
			
			GuiService.TouchControlsEnabled = false
		else
			
			gui.Enabled = false
			gui:WaitForChild("Frame").Visible = false
			gui:WaitForChild("HidemobileUI").Visible = false
			--gui:WaitForChild("HomeButtonFrame").Visible = false
			gui:WaitForChild("Tricks").Visible = false
			onScreenButtons.Enabled = true
			playerInfo.Enabled = true
			GuiService.TouchControlsEnabled = true
		end



	else
		gui.Enabled = false
		gui:WaitForChild("Frame").Visible = false
		gui:WaitForChild("HidemobileUI").Visible = false
		gui:WaitForChild("HomeButtonFrame").Visible = false
		gui:WaitForChild("Tricks").Visible = false
		
	end
end


player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid")

	humanoid.Seated:Connect(function(active, seat)
		
		updateGuiVisibility()
	end)
end)


if player.Character then
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Seated:Connect(function(active, seat)
			updateGuiVisibility()
		end)
	end
end

updateGuiVisibility()