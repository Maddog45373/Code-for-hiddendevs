local RS = game:GetService("ReplicatedStorage")
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local PlayGui = LocalPlayer:WaitForChild("PlayerGui")
local Template = RS:WaitForChild("Templates"):WaitForChild("ShopTemplate")
local ShopsLists = RS:WaitForChild("ShopList")
local BikesFolder = RS:WaitForChild("Bikes")

local runservice = game:GetService("RunService")
local player = game.Players.LocalPlayer
local Detector = game.Workspace:WaitForChild("DealershipDetector")
local ui = script.Parent

local cd = math.max(Detector.Size.X, Detector.Size.Z)
local ad = nil
local db = false
local currentList = nil

local MainFrame = script.Parent:WaitForChild("Main")
local Container = MainFrame:WaitForChild("Container")
local CloseButton = MainFrame:WaitForChild("Close")
local ShopSectionLabel = MainFrame:WaitForChild("Name")
local ScrollingFrame = Container:WaitForChild("ScrollingFrame")
local ConfirmFrame = MainFrame:WaitForChild("Confirmation")
local SellFrame = MainFrame:WaitForChild("Sell")
local SearchBar = MainFrame:WaitForChild("SearchFrame"):WaitForChild("ImageLabel"):WaitForChild("TextBox")
local NoBikes = MainFrame:WaitForChild("NoBikes")
local Buttons = MainFrame:WaitForChild("Buttons")

local Left = Container:WaitForChild("Left")
local Right = Container:WaitForChild("Right")

local buttonCounter = 0
local connections = {}
local otherConnections = {}
local ReplicatedModules = {}
local renderConnections = {}

local TweenService = game:GetService("TweenService")
local ShopScrollingInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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

local function CleanOtherConnections()
	if #otherConnections > 0 or otherConnections ~= {} then
		for _, connection in pairs(otherConnections) do
			connection:Disconnect()
			connection = nil
		end
		otherConnections = {}
	end
end

local function CleanUp()
	for _, child in pairs(ScrollingFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	ScrollingFrame.Visible = false
	SellFrame.Visible = false
	ConfirmFrame.Visible = false
	if ConfirmFrame:FindFirstChildOfClass("Frame") then
		ConfirmFrame:FindFirstChildOfClass("Frame"):Destroy()
	end
	if #connections > 0 or connections ~= {} then
		for _, connection in pairs(connections) do
			connection:Disconnect()
			connection = nil
		end
		connections = {}
	end
	CleanOtherConnections()
	
	if #renderConnections > 0 or renderConnections ~= {} then
		for _, connection in pairs(renderConnections) do
			connection:Disconnect()
			connection = nil
		end
		renderConnections = {}
	end
end

MainFrame.Visible = false
CleanUp()

Detector.Touched:Connect(function(hit)
	if db then
		return
	end
	local char = player.Character
	if char and hit.Parent == char then
		db = true
		MainFrame.Visible = true
		ad = Detector
		spawn(function()
			wait(1)
			db = false
		end)
	end
end)

runservice.RenderStepped:Connect(function()
	if MainFrame.Visible and ad then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local distance = (hrp.Position - ad.Position).Magnitude
			local pSize = hrp.Size.Magnitude
			if distance > cd + pSize then
				MainFrame.Visible = false
				ad = nil
				CleanUp()
			end
		end
	end
end)

CloseButton.MouseButton1Click:Connect(function()
	MainFrame.Visible = false
	CleanUp()
end)

function LoadModulesOnStartup()
	for _, module in pairs(ShopsLists:GetChildren()) do
		if module:IsA("ModuleScript") then
			local success, result = pcall(require, module)
			if success and result then
				ReplicatedModules[module.Name] = result
			else
				warn("Failed to load module: " .. module.Name .. " | " .. tostring(result))
			end
		end
	end
end

LoadModulesOnStartup()

local LoadingTask = nil
local currentlyLoadingShop = false

-- Angle calculation for rotating the camera
local x
local z
local rotationSpeed = 1 -- Adjust for speed, angle per second
game:GetService("RunService").RenderStepped:Connect(function()
	local angle = tick() * rotationSpeed 

	x = math.cos(angle)
	z = math.sin(angle)
end)


local function LoadShopContents(ShopList, module, buttonName)
	if currentlyLoadingShop and currentList ~= ShopList.Name then
		task.cancel(LoadingTask)
		currentlyLoadingShop = false
	elseif currentList == ShopList.Name then
		return
	end
	
	
	
	LoadingTask = task.spawn(function()
		CleanUp()
		SearchBar.Text = ""
		SearchBar.PlaceholderText = "SEARCH " .. string.upper(ShopList.Name)
		buttonCounter = 0
		currentlyLoadingShop = true
		currentList = ShopList.Name
		for i, bikeData in pairs(module) do
			local TemplateClone = Template:Clone()
			TemplateClone.Name = bikeData.Name
			TemplateClone.BikeName.Text = bikeData.Name
			TemplateClone.Speed.Text = bikeData.Speed .. "MPH"
			TemplateClone.Price.Text = "$" .. bikeData.Price
			--TemplateClone.Kind.Text = bikeData.Kind
			TemplateClone.Parent = ScrollingFrame
			TemplateClone.LayoutOrder = i
			TemplateClone.Visible = true
			buttonCounter += 1
			task.spawn(function()
				local bikeModel = FindBikeModel(bikeData.Name)

				-- Jeos fix
				if bikeModel then
					local bikeClone = bikeModel:Clone()
					for _, des in bikeClone:GetDescendants() do
						if des:IsA("LocalScript") or des:IsA("Script") then
							des:Destroy()
						end
					end

					local seat = bikeClone:WaitForChild("DriveSeat")
					bikeClone.Parent = TemplateClone.BikeImage
					local cam = Instance.new("Camera")
					cam.Parent = TemplateClone.BikeImage

					cam.CameraSubject = seat
					cam.CameraType = Enum.CameraType.Orbital

					TemplateClone.BikeImage.CurrentCamera = cam

					-- Rotation logic
					local radius = 8 -- Distance from the center

					---- Change the radius to compensate for big size
					if bikeClone.Name == "Mini RAM TRX" or bikeClone.Name == "Mini Merc	edes Maybach" or bikeClone.Name == "Mini Dodge Charger Hellcat" or bikeClone.Name == "Surronster's Porsche" then
						radius = 12
					end

					local connection = game:GetService("RunService").RenderStepped:Connect(function()


						if x and z then		
							local x = x * radius
							local z = z * radius

							cam.CFrame = CFrame.new(seat.Position + Vector3.new(x, 0 ,z), seat.Position)
						end

					end)

					table.insert(renderConnections, connection)

				end
				if bikeData.Robux == true then
					if not bikeData.ProductID then
						warn("No ID found in " .. bikeData.Name .. "'s BikeData located in " .. ShopList.Name)
					else
						local success, productData = pcall(function()
							return game:GetService("MarketplaceService")
								:GetProductInfoAsync(bikeData.ProductID, Enum.InfoType.Product)
						end)
						if success and productData and productData.PriceInRobux then
							TemplateClone.Robux:WaitForChild("Text").Text = productData.PriceInRobux .. "\u{E002}"
							TemplateClone.Robux.Visible = true
						else
							warn("Error getting the product's data. Make sure the product is onsale.")
						end
					end
				end
			end)


			connections[#connections + 1] = TemplateClone.Button.MouseButton1Click:Connect(function()
				if ConfirmFrame.Visible then
					return
				end
				if SellFrame.Visible then
					return
				end
				
				local ifBought = RS:WaitForChild("Remotes"):WaitForChild("GetData"):InvokeServer(bikeData.Name)
				if ifBought then
					SellFrame.ConfirmMessage.Text = "ARE YOU SURE YOU WANT TO SELL '" .. bikeData.Name .. "'?"
					SellFrame.RedPrice.Text = "$" .. tostring(math.floor(bikeData.Price * 0.8))
					SellFrame.Visible = true
					otherConnections[#otherConnections + 1] = SellFrame.NO.MouseButton1Click:Connect(function()
						SellFrame.Visible = false
						CleanOtherConnections()
					end)
					otherConnections[#otherConnections + 1] = SellFrame.YES.MouseButton1Click:Connect(function()
						RS:WaitForChild("Remotes"):WaitForChild("SellBike"):FireServer(bikeData.Name)
						SellFrame.Visible = false
						CleanOtherConnections()
					end)
				else
					local anotherClone = TemplateClone:Clone()
					anotherClone.Visible = false
					anotherClone.Size = UDim2.new(0.7, 0, 0.95, 0)
					anotherClone.Position = UDim2.new(0.025, 0, 0.025, 0)
					anotherClone.Parent = ConfirmFrame
					anotherClone.Visible = true
					ConfirmFrame.RedPrice.Text = "$" .. bikeData.Price
					ConfirmFrame.ConfirmMessage.Text = "ARE YOU SURE YOU WANT TO BUY '" .. bikeData.Name .. "'?"
					ConfirmFrame.Visible = true
					if bikeData.Robux == true then
						if not bikeData.ProductID then
							warn("No ID found in " .. bikeData.Name .. "'s BikeData located in " .. ShopList.Name)
						else
							local productData = game:GetService("MarketplaceService")
								:GetProductInfoAsync(bikeData.ProductID, Enum.InfoType.Product)
							if not productData or not productData.PriceInRobux then
								warn("Error getting the product's data. Make sure the product is onsale.")
							else
								ConfirmFrame.Robux.Text = "Buy with " .. productData.PriceInRobux .. "\u{E002}"
								ConfirmFrame.Robux.Visible = true
								local connection = nil
								otherConnections[#otherConnections + 1] = ConfirmFrame.Robux.MouseButton1Click:Connect(function()
									game:GetService("MarketplaceService"):PromptProductPurchase(LocalPlayer, bikeData.ProductID)
									if connection ~= nil then
										return
									end
									connection = RS:WaitForChild("Remotes"):WaitForChild("PurchaseBike").OnClientEvent:Connect(function(ID)
										if ID ~= bikeData.ProductID then
											return
										end
										ConfirmFrame.Visible = false
										anotherClone:Destroy()
										CleanOtherConnections()
										connection:Disconnect()
									end)
								end)
							end
						end
					end
					otherConnections[#otherConnections + 1] = ConfirmFrame.NO.MouseButton1Click:Connect(function()
						ConfirmFrame.Visible = false
						anotherClone:Destroy()
						CleanOtherConnections()
					end)
					otherConnections[#otherConnections + 1] = ConfirmFrame.YES.MouseButton1Click:Connect(function()
						RS:WaitForChild("Remotes"):WaitForChild("PurchaseBike"):FireServer(bikeData.Name, bikeData)
						ConfirmFrame.Visible = false
						anotherClone:Destroy()
						CleanOtherConnections()
					end)
				end
			end)
		end
		currentlyLoadingShop = false
		local totalSize = (200 + 10) * buttonCounter
		--ScrollingFrame.CanvasSize = UDim2.new(0, math.max(totalSize, 750), 0, 0)
		ScrollingFrame.Visible = true
		ShopSectionLabel.Text = buttonName
		if buttonCounter == 0 then
			NoBikes.Visible = true
		else
			NoBikes.Visible = false
		end
		otherConnections[#otherConnections + 1] = SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
			local text = string.lower(SearchBar.Text)
			local count = 0
			for _, item in pairs(ScrollingFrame:GetChildren()) do
				if item:IsA("Frame") then
					if string.find(string.lower(item.Name), text, 1, true) then
						item.Visible = true
						count = count + 1
					else
						item.Visible = false
					end
				end
			end
			local newSize = (200 + 10) * count
			--ScrollingFrame.CanvasSize = UDim2.new(0, math.max(newSize, 750), 0, 0)
			if count == 0 then
				NoBikes.Visible = true
			else
				NoBikes.Visible = false
			end
		end)
		
		
		otherConnections[#otherConnections + 1] = Left.Activated:Connect(function()
			
			
			local goal = Vector2.new(math.max(0, ScrollingFrame.CanvasPosition.X - 200),0)
			
			TweenService:Create(ScrollingFrame, ShopScrollingInfo, {CanvasPosition = goal}):Play()
		end)
		
		otherConnections[#otherConnections + 1] = Right.Activated:Connect(function()
			local maxX = ScrollingFrame.AbsoluteCanvasSize.X - ScrollingFrame.AbsoluteSize.X

			local goal = Vector2.new(math.min(maxX, ScrollingFrame.CanvasPosition.X + 200),0)
			
			
			TweenService:Create(ScrollingFrame, ShopScrollingInfo, {CanvasPosition = goal}):Play()
		end)
		
	end)
end

local function moveScrollingBar(dir)
	local currentX = ScrollingFrame.CanvasPosition.X
	
	
	
end


LoadShopContents(ShopsLists:FindFirstChild("E-Bikes"), require(ShopsLists:FindFirstChild("E-Bikes")), "E-Bikes")

for _, button in pairs(Buttons:GetDescendants()) do
	if button:IsA("TextButton") then
		button.MouseButton1Click:Connect(function()
			local ShopList = ShopsLists:FindFirstChild(button.Name)
			if ShopList then
				local module = ReplicatedModules[ShopList.Name] or require(ShopList)
				LoadShopContents(ShopList, module, button.Name)
			else
				warn("Shop list not found: " .. button.Name)
			end
		end)
	end
end

