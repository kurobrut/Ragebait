-- // Services and modules
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local router = require(ReplicatedStorage.ClientModules.Core.RouterClient.RouterClient)
local cd = require(ReplicatedStorage.ClientModules.Core.ClientData)
local furnituresdb = require(ReplicatedStorage.ClientDB.Housing.FurnitureDB)
local texturesdb = require(ReplicatedStorage.ClientDB.Housing.TexturesDB)
local housedb = require(ReplicatedStorage.ClientDB.Housing.HouseDB)

local plr = Players.LocalPlayer

--==================================================
-- JSON
--==================================================
local function lEncode(t)
	return HttpService:JSONEncode(t)
end

local function lDecode(s)
	return HttpService:JSONDecode(s)
end

--==================================================
-- MAIN UI
--==================================================

local function loadMain()
	local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

	local Window = Rayfield:CreateWindow({
		Name = "Ragebait | House Cloner",
		LoadingTitle = "Ragebait",
		LoadingSubtitle = "House Cloner",
		Theme = "Default",
	})

	local Tab = Window:CreateTab("Main", "home")
	Tab:CreateSection("File Manager")

	local fcount = Tab:CreateLabel("Furnitures count: 0")
	local fcost = Tab:CreateLabel("Furnitures cost: 0")
	local tcost = Tab:CreateLabel("Textures cost: 0")
	local progress = Tab:CreateLabel("Progress: 0%")

	local function setcosts(a, b, c)
		fcount:Set("Furnitures count: " .. a)
		fcost:Set("Furnitures cost: " .. b)
		tcost:Set("Textures cost: " .. c)
	end

	local function updateprogress(p)
		progress:Set("Progress: " .. p .. "%")
	end

	local function countfurnitures(t)
		local c = 0
		for _ in pairs(t or {}) do
			c += 1
		end
		return c
	end

	local savedhouse

	Tab:CreateLabel("Do not Touch", "info")

	local Pastetextures = Tab:CreateToggle({
		Name = "Paste textures",
		CurrentValue = true,
		Flag = "Pastetextures",
		Callback = function(_) end,
	})

	Tab:CreateSection("Main Function")

	-- // Scan house (from current interior)
	local copyhouse = Tab:CreateButton({
		Name = "Scan house",
		Callback = function()
			local house = cd.get("house_interior")
			if not house or house.player == nil then
				Rayfield:Notify({
					Title = "Error",
					Content = "You need to enter a house to copy",
					Duration = 3,
					Image = "circle-alert",
				})
				return
			end

			-- Deep copy
			local function deepCopy(tbl)
				if type(tbl) ~= "table" then
					return tbl
				end
				local t = {}
				for k, v in pairs(tbl) do
					t[k] = deepCopy(v)
				end
				return t
			end

			savedhouse = deepCopy(house)
			if savedhouse.furniture then
				for _, v in pairs(savedhouse.furniture) do
					if v.creator then
						v.creator = nil
					end
				end
			end

			local furniturecost = 0
			for _, v in pairs(savedhouse.furniture or {}) do
				if furnituresdb[v.id] then
					furniturecost += furnituresdb[v.id].cost or 0
				end
			end

			local texturecost = 0
			for _, v in pairs(savedhouse.textures or {}) do
				if texturesdb.walls[v.walls] then
					texturecost += texturesdb.walls[v.walls].cost or 0
				end
				if texturesdb.floors[v.floors] then
					texturecost += texturesdb.floors[v.floors].cost or 0
				end
			end

			task.spawn(setcosts, countfurnitures(savedhouse.furniture), furniturecost, texturecost)

			Rayfield:Notify({
				Title = "Success",
				Content = "Scanned house",
				Duration = 3,
				Image = "circle-check",
			})
		end,
	})

	-- // Clear house
	local clearhouse = Tab:CreateButton({
		Name = "Sell All Furnitures",
		Callback = function()
			local t = {}
			for i, _ in pairs(cd.get("house_interior").furniture) do
				table.insert(t, i)
			end

			local args = {
				false,
				t,
				"sell",
			}
			router.get("HousingAPI/SellFurniture"):FireServer(unpack(args))

			Rayfield:Notify({
				Title = "Success",
				Content = "House cleared successfully!",
				Duration = 3,
				Image = "circle-check",
			})
		end,
	})

	-- // Furniture and texture helpers
	local function canbuyfurniture(kind)
		if furnituresdb[kind] == nil or not furnituresdb[kind].cost or furnituresdb[kind].off_sale then
			return false, false
		end
		return furnituresdb[kind].cost < cd.get_data()[plr.Name].money, true
	end

	local function textureexists(room, texturetype, texture)
		if texture == "tile" then
			return true
		end
		for i, v in pairs(cd.get("house_interior").textures) do
			if i == room and v[texturetype] == texture then
				return true
			end
		end
		return false
	end

	local function buytexturewithretry(room, texturetype, texture)
		router.get("HousingAPI/BuyTexture"):FireServer(room, texturetype, texture)
		task.wait(0.05)
		if not textureexists(room, texturetype, texture) then
			warn("couldn't buy texture, retrying")
			buytexturewithretry(room, texturetype, texture)
		end
		print("bought texture: " .. tostring(texture))
	end

	-- // Paste house (fast)
	local function pastehousefast()
		local character = plr.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

		Rayfield:Notify({
			Title = "Loading",
			Content = "Anchoring to prevent falling during paste (glitch houses)",
			Duration = 5,
			Image = "loader",
		})

		if humanoidRootPart then
			humanoidRootPart.Anchored = true
		end

		if not savedhouse or not savedhouse.furniture then
			if humanoidRootPart then
				humanoidRootPart.Anchored = false
			end
			return Rayfield:Notify({
				Title = "Error",
				Content = "No house has been saved",
				Duration = 3,
				Image = "circle-alert",
			})
		end

		Rayfield:Notify({
			Title = "Loading",
			Content = "Pasting furnitures...",
			Duration = 3,
			Image = "loader",
		})

		local validFurniture = {}
		local totalfurnitures = 0
		for i, v in pairs(savedhouse.furniture) do
			if v.id ~= "lures_2023_cozy_home_lure" and v.cframe and typeof(v.cframe) == "CFrame" then
				validFurniture[i] = v
				totalfurnitures += 1
			else
				warn("[SKIP] Skipping invalid furniture or CFrame:", v.id)
			end
		end

		local processedCount = 0
		local furniturest = {}
		for i, v in pairs(validFurniture) do
			local canbuy, exists = canbuyfurniture(v.id)
			if not canbuy and exists == true then
				if humanoidRootPart then
					humanoidRootPart.Anchored = false
				end
				return Rayfield:Notify({
					Title = "Error",
					Content = "Insufficient funds for furniture: " .. v.id,
					Duration = 3,
					Image = "circle-alert",
				})
			elseif not canbuy and exists == false then
				processedCount += 1
				task.spawn(updateprogress, math.floor(processedCount / totalfurnitures * 100))
				continue
			end

			table.insert(furniturest, {
				kind = v.id,
				properties = { colors = v.colors, cframe = v.cframe, scale = v.scale },
			})
			processedCount += 1
			task.spawn(updateprogress, math.floor(processedCount / totalfurnitures * 100))
		end

		if #furniturest > 0 then
			router.get("HousingAPI/BuyFurnitures"):InvokeServer(furniturest)
		end

		-- Activate furniture after buying
		for i, v in pairs(cd.get("house_interior").furniture) do
			if v.text then
				router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
			elseif v.outfit_name then
				router.get("AvatarAPI/StartEditingMannequin"):InvokeServer(v.outfit)
				router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", {
					save_outfit = true,
					outfit_name = "Outfit",
				}, plr.Character)
			end
		end

		-- Apply textures
		if savedhouse.textures and Pastetextures.CurrentValue then
			for roomId, textureData in pairs(savedhouse.textures) do
				if textureData.floors and not textureexists(roomId, "floors", textureData.floors) then
					buytexturewithretry(roomId, "floors", textureData.floors)
				end
				if textureData.walls and not textureexists(roomId, "walls", textureData.walls) then
					buytexturewithretry(roomId, "walls", textureData.walls)
				end
				task.wait()
			end
		end

		-- Apply ambiance and music
		if savedhouse.ambiance then
			router.get("AmbianceAPI/UpdateAmbiance"):FireServer(savedhouse.ambiance)
		end
		if savedhouse.music then
			router.get("RadioAPI/Play"):FireServer(savedhouse.music.name, savedhouse.music.id)
			if not savedhouse.music.playing then
				router.get("RadioAPI/Pause"):InvokeServer()
			end
		end

		if humanoidRootPart then
			humanoidRootPart.Anchored = false
		end

		Rayfield:Notify({
			Title = "Success",
			Content = "House Placed successfully!",
			Duration = 3,
			Image = "circle-check",
		})
	end

	-- // Paste init
	local function pastehouseinit(slow)
		if not savedhouse then
			return Rayfield:Notify({
				Title = "Error",
				Content = "No house has been saved",
				Duration = 3,
				Image = "circle-alert",
			})
		end

		local houseInterior = cd.get("house_interior")
		if not houseInterior.player or houseInterior.player ~= plr then
			return Rayfield:Notify({
				Title = "Error",
				Content = "Please enter your house to paste the house",
				Duration = 3,
				Image = "circle-alert",
			})
		end

		Rayfield:Notify({
			Title = "Loading",
			Content = "Clearing house",
			Duration = 3,
			Image = "loader",
		})

		-- Sell all furniture safely
		for i, _ in pairs(houseInterior.furniture) do
			local args = {
				true,
				{ i },
				"sell",
			}
			-- Use pcall to prevent script from stopping if FireServer fails
			pcall(function()
				router.get("HousingAPI/SellFurniture"):FireServer(unpack(args))
			end)
		end

		task.wait(0.1) -- wait a moment for the server to process the sells

		-- Start the appropriate paste function
		if slow then
			task.spawn(pastehouseslow)
		else
			task.spawn(pastehousefast)
		end
	end

	Tab:CreateButton({
		Name = "Place House Fast",
		Callback = pastehouseinit,
	})

	local PastebinTab = Window:CreateTab("Pastebin", "clipboard")

	local userPastebinDevKey = ""

	local function serialize(value)
		local t = typeof(value)

		if t == "CFrame" then
			return {
				__type = "CFrame",
				components = { value:GetComponents() },
			}
		elseif t == "Vector3" then
			return {
				__type = "Vector3",
				x = value.X,
				y = value.Y,
				z = value.Z,
			}
		elseif t == "Color3" then
			return {
				__type = "Color3",
				r = value.R,
				g = value.G,
				b = value.B,
			}
		elseif t == "Instance" then
			return nil
		elseif t == "table" then
			local out = {}
			for k, v in pairs(value) do
				local sv = serialize(v)
				if sv ~= nil then
					out[k] = sv
				end
			end
			return out
		end

		return value
	end

	local function deserialize(value)
		if type(value) ~= "table" then
			return value
		end

		if value.__type == "CFrame" then
			return CFrame.new(unpack(value.components))
		elseif value.__type == "Vector3" then
			return Vector3.new(value.x, value.y, value.z)
		elseif value.__type == "Color3" then
			return Color3.new(value.r, value.g, value.b)
		end

		for k, v in pairs(value) do
			value[k] = deserialize(v)
		end

		return value
	end

	--==================================================
	-- PASTEBIN API (USER DEV KEY ONLY)
	--==================================================

	local function createPaste(content, name, devKey)
		if not devKey or devKey == "" then
			return nil, "NO_DEV_KEY"
		end

		local data = {
			api_dev_key = devKey,
			api_option = "paste",
			api_paste_code = content,
			api_paste_name = name or "CubixHouse",
			api_paste_private = "1",
			api_paste_format = "json",
			api_paste_expire_date = "N",
		}

		local encoded = ""
		for k, v in pairs(data) do
			encoded ..= k .. "=" .. HttpService:UrlEncode(tostring(v)) .. "&"
		end
		encoded = encoded:sub(1, -2)

		local response = request({
			Url = "https://pastebin.com/api/api_post.php",
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/x-www-form-urlencoded",
			},
			Body = encoded,
		})

		return response and response.Body
	end

	local informationLabel = PastebinTab:CreateLabel("TO GET DEV API KEY YOU NEED TO MAKE ACCOUNT ON PASTEBIN", "info")
	local infoLabel2 =
		PastebinTab:CreateLabel("AFTER THAT GO TO https://pastebin.com/doc_api AND COPY YOUR DEV API KEY", "info")

	local divider = PastebinTab:CreateDivider()

	PastebinTab:CreateInput({
		Name = "Pastebin Dev API Key (Required)",
		PlaceholderText = "Paste ONLY the API key (not a link)",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			-- sanitize common copy-paste mistakes
			value = tostring(value)
				:gsub("%s+", "")
				:gsub("YouruniquedeveloperAPIkey:", "")
				:gsub("Your%w+developer%w+API%w+key:", "")

			userPastebinDevKey = value
		end,
	})

	local pastebinInput = PastebinTab:CreateInput({
		Name = "Pastebin Link / ID",
		PlaceholderText = "https://pastebin.com/xxxxxx or xxxxxx",
		RemoveTextAfterFocusLost = false,
		Callback = function() end,
	})

	--==================================================
	-- LOAD HOUSE FROM PASTEBIN
	--==================================================

	PastebinTab:CreateButton({
		Name = "Load House from Pastebin",
		Callback = function()
			local input = pastebinInput.CurrentValue
			if not input or input == "" then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Please enter a Pastebin link or ID",
					Duration = 3,
				})
			end

			local pasteId = input:match("pastebin%.com/(.+)")
			if pasteId then
				pasteId = pasteId:gsub("raw/", "")
			else
				pasteId = input
			end

			local response
			local success = pcall(function()
				response = request({
					Url = "https://pastebin.com/raw/" .. pasteId,
					Method = "GET",
				})
			end)

			if not success or not response or not response.Body then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Failed to fetch Pastebin data",
					Duration = 3,
				})
			end

			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(response.Body)
			end)

			if not ok or type(decoded) ~= "table" then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Invalid Pastebin JSON",
					Duration = 3,
				})
			end

			savedhouse = deserialize(decoded)

			updateprogress(0)
			task.spawn(setcosts, countfurnitures(savedhouse.furniture), 0, 0)

			Rayfield:Notify({
				Title = "Success",
				Content = "House loaded from Pastebin",
				Duration = 3,
			})
		end,
	})

	--==================================================
	-- SAVE HOUSE TO PASTEBIN
	--==================================================

	PastebinTab:CreateButton({
		Name = "Save House to Pastebin",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({
					Title = "Error",
					Content = "No house has been scanned or loaded",
					Duration = 3,
				})
			end

			-- hard format validation
			if #userPastebinDevKey < 20 or not userPastebinDevKey:match("^[%w]+$") then
				return Rayfield:Notify({
					Title = "Invalid API Key",
					Content = "Paste ONLY the Pastebin Dev API key.\nDo not paste a URL.",
					Duration = 5,
				})
			end

			local clean = serialize(savedhouse)
			local ok, encoded = pcall(function()
				return HttpService:JSONEncode(clean)
			end)

			if not ok then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Failed to encode house data",
					Duration = 3,
				})
			end

			local result, err = createPaste(encoded, "CubixHouse_" .. plr.Name, userPastebinDevKey)

			if err == "NO_DEV_KEY" or not result or result:find("Bad API request") then
				return Rayfield:Notify({
					Title = "Pastebin Error",
					Content = tostring(result),
					Duration = 6,
				})
			end

			if setclipboard then
				setclipboard(result)
			end

			Rayfield:Notify({
				Title = "Success",
				Content = "House saved to Pastebin\nLink copied to clipboard",
				Duration = 8,
			})
		end,
	})

	local CreateFileTab = Window:CreateTab("Create File", "folder")

	-- Ensure folder exists
	if not isfolder("Cubixhouses") then
		makefolder("Cubixhouses")
	end

	-- UI Section
	local FileSection = CreateFileTab:CreateSection("File Manager")

	-- Dropdown for saved houses
	local fileDropdown = CreateFileTab:CreateDropdown({
		Name = "Select Saved House",
		Options = {}, -- populated dynamically
		CurrentOption = nil,
		MultipleOptions = false,
		Flag = "FileDropdown",
		Callback = function(_) end,
	})

	-- Input for new save
	local saveInput = CreateFileTab:CreateInput({
		Name = "Save As",
		PlaceholderText = "Enter File Name",
		RemoveTextAfterFocusLost = false,
		Callback = function(_) end,
	})

	-- Utility: refresh dropdown
	local function refreshFileDropdown()
		local files = listfiles("Cubixhouses")
		local validFiles = {}

		for _, filePath in ipairs(files) do
			local fileName = filePath:match("^.+/(.+)$") or filePath
			if fileName:sub(-5) == ".json" then
				table.insert(validFiles, fileName)
			end
		end

		fileDropdown:Refresh(validFiles)

		if #validFiles > 0 then
			fileDropdown:Set(validFiles[1])
		else
			fileDropdown:Set(nil)
		end
	end

	-- Initial refresh
	refreshFileDropdown()

	-- Button: Save House
	CreateFileTab:CreateButton({
		Name = "Save House to File",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({
					Title = "Error",
					Content = "No house has been scanned or loaded",
					Duration = 3,
					Image = "circle-alert",
				})
			end

			local filename = saveInput.CurrentValue
			if not filename or filename == "" then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Please enter a valid filename",
					Duration = 3,
					Image = "circle-alert",
				})
			end

			-- Serialize and encode
			local cleanData = serialize(savedhouse)
			local success, encoded = pcall(function()
				return HttpService:JSONEncode(cleanData)
			end)

			if not success then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Failed to encode house data",
					Duration = 3,
					Image = "circle-alert",
				})
			end

			writefile("Cubixhouses/" .. filename .. ".json", encoded)

			refreshFileDropdown()

			Rayfield:Notify({
				Title = "Success",
				Content = "House saved: " .. filename .. ".json",
				Duration = 3,
				Image = "circle-check",
			})
		end,
	})

	-- Button: Load House
	CreateFileTab:CreateButton({
		Name = "Load House from File",
		Callback = function()
			local selected = fileDropdown.CurrentOption

			-- Fix: if it's a table, get first value
			if type(selected) == "table" then
				selected = selected[1]
			end

			if not selected or selected == "" then
				return Rayfield:Notify({
					Title = "Error",
					Content = "No file selected to load",
					Duration = 3,
					Image = "circle-alert",
				})
			end

			local success, content = pcall(function()
				return readfile("Cubixhouses/" .. selected)
			end)
			if not success or not content then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Failed to read file: " .. selected,
					Duration = 3,
					Image = "circle-alert",
				})
			end

			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(content)
			end)
			if not ok or type(decoded) ~= "table" then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Invalid JSON in file: " .. selected,
					Duration = 3,
					Image = "circle-alert",
				})
			end

			savedhouse = deserialize(decoded)

			-- Update furniture/texture costs
			local furniturecost, texturecost = 0, 0
			for _, v in pairs(savedhouse.furniture or {}) do
				if furnituresdb[v.id] then
					furniturecost += furnituresdb[v.id].cost or 0
				end
			end
			for _, v in pairs(savedhouse.textures or {}) do
				if texturesdb.walls[v.walls] then
					texturecost += texturesdb.walls[v.walls].cost or 0
				end
				if texturesdb.floors[v.floors] then
					texturecost += texturesdb.floors[v.floors].cost or 0
				end
			end

			task.spawn(setcosts, countfurnitures(savedhouse.furniture), furniturecost, texturecost)
			updateprogress(0)

			Rayfield:Notify({
				Title = "Success",
				Content = "House loaded from file: " .. selected,
				Duration = 3,
				Image = "circle-check",
			})
		end,
	})

	-- Button: Delete House
	CreateFileTab:CreateButton({
		Name = "Delete Selected House",
		Callback = function()
			local selected = fileDropdown.CurrentOption

			-- Fix: if it's a table, get first value
			if type(selected) == "table" then
				selected = selected[1]
			end

			if not selected or selected == "" then
				return Rayfield:Notify({
					Title = "Error",
					Content = "No house selected to delete.",
					Duration = 3,
				})
			end

			local filePath = "Cubixhouses/" .. selected
			if isfile(filePath) then
				delfile(filePath)

				Rayfield:Notify({
					Title = "Deleted",
					Content = selected .. " has been deleted.",
					Duration = 3,
				})

				refreshFileDropdown()
			else
				Rayfield:Notify({
					Title = "Error",
					Content = "File not found: " .. selected,
					Duration = 3,
				})
			end
		end,
	})

	local Teleport = Window:CreateTab("Teleport", "map-pin")

	local function loadinterior(interiortype, name)
		local load = require(game:GetService("ReplicatedStorage").Fsys).load
		local interiors = load("InteriorsM")
		local enter = interiors.enter

		if interiortype == "interior" then
			enter(name, "", {})
			return
		end

		if interiortype == "house" then
			enter("housing", "MainDoor", { house_owner = name })
		end
	end

	local function getplayernames()
		local players = Players:GetPlayers()
		local names = table.create(#players)
		for i, player in ipairs(players) do
			names[i] = player.Name
		end
		return names
	end

	local selectedplayer = Teleport:CreateDropdown({
		Name = "Select Player",
		Options = getplayernames(),
		CurrentOption = { getplayernames()[1] },
		MultipleOptions = false,
		Flag = "Dropdown1",
		Callback = function(_) end,
	})

	Players.PlayerAdded:Connect(function()
		selectedplayer:Refresh(getplayernames())
	end)

	Players.PlayerRemoving:Connect(function()
		selectedplayer:Refresh(getplayernames())
	end)

	Teleport:CreateButton({
		Name = "Enter House",
		Callback = function()
			local target = Players:FindFirstChild(selectedplayer.CurrentOption[1])
			if target then
				loadinterior("house", target)
			end
		end,
	})
end
loadMain()
