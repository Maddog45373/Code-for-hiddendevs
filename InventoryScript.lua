local RS = game:GetService("ReplicatedStorage")
local Template = RS:WaitForChild("Templates"):WaitForChild("InvTemplate")
local BikesFolder = RS:WaitForChild("Bikes")
local ShopList = RS:WaitForChild("ShopList")


local MainFrame = script.Parent:WaitForChild("Main")
local Player = game.Players
local LocalPlayer = Player.LocalPlayer
local players = game:GetService("Players")
local player = players.LocalPlayer or players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local PlayGui = player:WaitForChild("PlayerGui")
local Onscreen = PlayGui:WaitForChild("OnScreenButtons")
local Folder = Onscreen:WaitForChild("Folder")
local OpenButton = Folder:WaitForChild("Spawn")
local CloseButton = MainFrame:WaitForChild("Close")

local ScrollingFrame = MainFrame:WaitForChild("Body"):WaitForChild("ScrollingFrame")
local Header = MainFrame:WaitForChild("Header")
local RightHeader = Header:WaitForChild("RightHeader")
local SearchBar = RightHeader:WaitForChild("SearchFrame")
	:WaitForChild("ImageLabel")
	:WaitForChild("TextBox")
local NoBikes = MainFrame:WaitForChild("NoBikes")

local ShopsLists = RS:WaitForChild("ShopList")

local connections = {}
local otherConnections = {}

local renderConnections = {}


local ReplicatedModules = {}

local function showCategoryBikes(Category, module)
	local bikesInCategory = {}

	-- If Category is E-Motos, manually go through creator bikes too, WILL FIX LATER
	
	--if Category.Name == "E-Motos" then
		
	--	local creatorBikes = ReplicatedModules["CreatorBikes"]

	--	if creatorBikes then
	--		for _, bikeData in pairs(creatorBikes) do
	--			bikesInCategory[bikeData.Name] = true
	--		end
	--	end
	--end

	for _, bikeData in pairs(module) do
		bikesInCategory[bikeData.Name] = true
	end

	local visibleCount = 0

	for _, frame in ipairs(ScrollingFrame:GetChildren()) do
		if frame:IsA("Frame") then
			if bikesInCategory[frame.Name] then
				frame.Visible = true
				visibleCount += 1
			else
				frame.Visible = false
			end
		end
	end

	NoBikes.Visible = visibleCount == 0
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


function LoadModulesOnStartup()
	for _, module in pairs(ShopsLists:GetChildren()) do
		if module:IsA("ModuleScript") then
			local success, result = pcall(require, module)
			if success and result then
				ReplicatedModules[module.Name] = result
			end
		end
	end
end

LoadModulesOnStartup()





MainFrame.Visible = false
script.Parent.DeleteBike.Visible = false
CleanUp()


-- Angle calculation for rotating the camera
local x
local z
local rotationSpeed = 1 -- Adjust for speed, angle per second
game:GetService("RunService").RenderStepped:Connect(function()
	local angle = tick() * rotationSpeed 
	
	x = math.cos(angle)
	z = math.sin(angle)
end)

function OpenInv()
	CleanUp()
	SearchBar.Text = ""

	local inv = RS:WaitForChild("Remotes"):WaitForChild("GetAllBikes"):InvokeServer()
	if not inv or inv == {} then
		warn("No inventory found for player: " .. game.Players.LocalPlayer.Name)
		return
	end

	local buttonCounter = 0

	for bike, bikeData in pairs(inv) do
		local TemplateClone = Template:Clone()
		TemplateClone.Visible = false
		TemplateClone.Parent = ScrollingFrame

		TemplateClone.Name = bikeData.Name
		TemplateClone.BikeName.Text = bikeData.Name
		TemplateClone.Speed.Text = bikeData.Speed .. "MPH"


		-- Get current speed from shoplist
		for _, module in pairs(ShopList:GetChildren()) do
			if module:IsA("ModuleScript") then
				local success, moduleContent = pcall(require, module)
				if success and moduleContent then
					for _, bike in pairs(moduleContent) do
						if bike.Name == bikeData.Name then
							TemplateClone.Speed.Text = bike.Speed .. "MPH"
							break
						end
					end
				end
			end
		end 

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
				local x = x * radius
				local z = z * radius

				cam.CFrame = CFrame.new(seat.Position + Vector3.new(x, 0 ,z), seat.Position)
			end)
			
			table.insert(renderConnections, connection)
		end


		--TemplateClone.Kind.Text = bikeData.Kind
		TemplateClone.Visible = true
		buttonCounter += 1

		local button = TemplateClone.Button

		if not button then
			warn("NO BUTTON")
		end


		connections[#connections + 1] = button.MouseButton1Click:Connect(function()
			local remotes = RS:WaitForChild("Remotes")
			local spawnBike = remotes:WaitForChild("SpawnBike")
			spawnBike:FireServer(bikeData.Name)
			MainFrame.Visible = false
			script.Parent.DeleteBike.Visible = true
			CleanUp()
		end)
	end

	local totalSize = (200 + 10) * buttonCounter
	--ScrollingFrame.CanvasSize = UDim2.new(0, math.max(totalSize, 750), 0, 0)

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
					count += 1
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
end

script.Parent.DeleteBike.MouseButton1Click:Connect(function()
	humanoid.Jump = true
	RS:WaitForChild("Remotes"):WaitForChild("DeleteBikeNew"):FireServer()
	script.Parent.DeleteBike.Visible = false
end)

OpenButton.MouseButton1Click:Connect(function()
	MainFrame.Visible = not MainFrame.Visible

	if MainFrame.Visible then
		OpenInv()
	else
		CleanUp()
	end
end)

CloseButton.MouseButton1Click:Connect(function()
	MainFrame.Visible = false
	CleanUp()
end)

game.ReplicatedStorage.CheckItout.OnClientEvent:Connect(function(status)
	if status == "Deleted" then
		script.Parent.DeleteBike.Visible = false
	elseif status == "Driving" then
		script.Parent.Warn.Visible = true
		task.delay(2, function()
			script.Parent.Warn.Visible = false
		end)
	end
end)

for _, button in pairs(RightHeader:GetDescendants()) do
	
	if button:IsA("TextButton") then
		button.MouseButton1Click:Connect(function()

			if button.Name == "All" then
				local count = 0

				for _, frame in ipairs(ScrollingFrame:GetChildren()) do
					if frame:IsA("Frame") then
						frame.Visible = true
						count += 1
					end
				end

				NoBikes.Visible = (count == 0)
				return
			end

			
			local categoryModule = ShopsLists:FindFirstChild(button.Name)
			
			
			
			if categoryModule then
				
				local module = ReplicatedModules[categoryModule.Name] or require(categoryModule)
				showCategoryBikes(categoryModule, module)
			end
		end)
	end
end