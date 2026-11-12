local EnterBox = script.Parent.Frame.canvasGroup.textField.TextBox
local Redeem = script.Parent.Frame.canvasGroup.bottomBar.Claim
local Close = script.Parent.Frame.Close
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local PlayerGUI = Player:WaitForChild("PlayerGui")
local OnScreenButtons = PlayerGUI:WaitForChild("OnScreenButtons")
local CodesButton = OnScreenButtons:WaitForChild("Folder"):WaitForChild("Codes")


local ClickDB = false
local code_event = game:GetService("ReplicatedStorage").codeEvent

CodesButton.Activated:Connect(function()
	script.Parent.Frame.Visible = true
end)


code_event.OnClientEvent:Connect(function(code_table)

	local function button_animation(Button, bool)
		local isHovering = false
		local normalX = Button.Size.X.Scale
		local noramlY = Button.Size.Y.Scale
		local pressX = normalX - 0.025
		local pressY = noramlY - 0.005
		if bool == true then
			Button.MouseButton1Down:Connect(function()
				Button:TweenSize(UDim2.new(pressX,0,pressY,0), Enum.EasingDirection.InOut, Enum.EasingStyle.Quint, 0.2, true)
			end)
			Button.MouseButton1Up:Connect(function()
				Button:TweenSize(UDim2.new(normalX,0,noramlY,0), Enum.EasingDirection.InOut, Enum.EasingStyle.Quint, 0.2, true)
			end)
		end
	end

	local function button_clicked()
		local code_valid = false
		for _, code_index in pairs(code_table) do
			if EnterBox.Text == code_index[1] then
				code_valid = true
				break
			end
		end

		if code_valid then
			local plr_codes = Player:WaitForChild("CodesFolder", 5)

			if not plr_codes then
				EnterBox.TextColor3 = Color3.fromRGB(255, 8, 61)
				EnterBox.TextEditable = false
				EnterBox.Text = 'Error, try again!'
				delay(1.25, function()
					EnterBox.TextEditable = true
					EnterBox.Text = 'Enter Code'
					EnterBox.TextColor3 = Color3.fromRGB(171, 171, 171)
				end)
				return
			end

			if plr_codes:FindFirstChild(EnterBox.Text) then
				if plr_codes[EnterBox.Text].Value == false then
					code_event:FireServer(EnterBox.Text)
					EnterBox.TextColor3 = Color3.fromRGB(0, 170, 127)
					EnterBox.TextEditable = false
					EnterBox.Text = 'Code Redeemed!'
					delay(1, function()
						EnterBox.TextEditable = true
						EnterBox.Text = 'Enter Code'
						EnterBox.TextColor3 = Color3.fromRGB(171, 171, 171)
					end)
				else
					EnterBox.TextColor3 = Color3.fromRGB(255, 8, 61)
					EnterBox.TextEditable = false
					EnterBox.Text = 'Already Redeemed!'
					delay(1.25, function()
						EnterBox.TextEditable = true
						EnterBox.Text = 'Enter Code'
						EnterBox.TextColor3 = Color3.fromRGB(171, 171, 171)
					end)
				end
			end
		else
			EnterBox.TextColor3 = Color3.fromRGB(255, 8, 61)
			EnterBox.TextEditable = false
			EnterBox.Text = 'Invalid Code!'
			delay(1.25, function()
				EnterBox.TextEditable = true
				EnterBox.Text = 'Enter Code'
				EnterBox.TextColor3 = Color3.fromRGB(171, 171, 171)
			end)
		end
	end

	Redeem.MouseButton1Click:Connect(function()
		if ClickDB == false then
			ClickDB = true
			button_clicked()
			wait(0.15)
			ClickDB = false
		end
	end)

	Close.MouseButton1Click:Connect(function()
		if ClickDB == false then
			ClickDB = true
			script.Parent.Frame.Visible = false
			wait(0.15)
			ClickDB = false
		end
	end)

	button_animation(Redeem, true)
end)