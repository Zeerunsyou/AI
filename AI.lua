-- [[ Formatted with Hell ]]
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local VIM = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local mouse = LocalPlayer:GetMouse()
local player = Players.LocalPlayer
local menuGui = player:WaitForChild("PlayerGui"):WaitForChild("Menew_Main")
local playerGui = LocalPlayer.PlayerGui

local oldGui = playerGui:FindFirstChild("AIPlayNotification")
if oldGui then
	oldGui:Destroy()
end

local defaultSettings = {
	-- ===== Visual Settings =====
	visualsEnabled = true, -- Enable/disable all visual effects (dots, lines, waypoints)
	DOT_COUNT = 10, -- Number of animated dots to show on path
	visualFadeTime = 1.5, -- Time in seconds before visual parts fade/destroy
	DOT_SPEED = 10, -- How fast the dots move along the path

	-- ===== Camera Settings =====
	camLockEnabled = true, -- Whether camera auto-locks onto closest enemy
	lockAtParts = false, -- If true, the camlock will randomly choose a target body part from camlockAimParts
	camlockAimParts = { "Head", "Torso", "HumanoidRootPart" }, -- List of body parts that the camlock is allowed to aim at (enabled camlockAimParts)
	camLockTurnMode = true, -- Make AI turn when locking on instead of flicking instantly
	camlockTurnSpeed = math.rad(480), -- Change 720 to something lower if you want it to turn slower when locking on
	camLockToggle = Enum.KeyCode.H, -- Key to toggle camera lock
	CAMERA_TURN_SMOOTHNESS = 0.15, -- Smoothness factor for camera rotation (0 = instant, 1 = very smooth)

	-- ===== Hitbox Extender =====
	hitboxExtenderEnabled = true, -- Makes enemies easier to hit
	hitboxSize = Vector3.new(5, 5, 5), -- The size of the enemies body parts (Torso, Left Arm, Right Arm, Left Leg, Right Leg)
	headHitboxSize = Vector3.new(8, 8, 8), -- Size of the enemies head (Easier to hit headshots)

	-- ===== Auto-Fire Settings =====
	autoFireEnabled = true, -- Enable/disable auto-clicking on enemies
	autoFireToggle = Enum.KeyCode.J, -- Key to toggle auto-fire

	-- ===== AI / Pathfinding =====
	AIEnabled = true, -- Enable/disable AI movement
	MAX_SLOPE_Y = 0.65, -- Maximum slope Y value considered walkable (used to check hard blocks)
	REPATH_INTERVAL = 0.4, -- How often (seconds) to recompute path to target
	WAYPOINT_SKIP_DISTANCE = 6, -- Minimum distance to skip waypoints
	TARGET_REPATH_DISTANCE = 12, -- Distance threshold to recompute path if target moved
	JUMP_INTERVAL = 1.6, -- Minimum time (seconds) between AI jumps
	SPEED_THRESHOLD = 30, -- If humanoid WalkSpeed is below this, AI stops looping
	TELEPORT_OFFSET = 3, -- Offset from target position when teleporting near enemy
	GOLDEN_KNIFE_TP = true, -- Teleport to the target when you have the golden knife (BLATANT)
	autoWeaponSwitchEnabled = true, -- Enable/disable auto-switch between knife and primary
	autoWeaponSwitchCooldown = 2, -- Seconds to wait before re-equipping knife
	autoInspectKnifeEnabled = true, -- Inspect knife while walking (Doesnt affect performance)
	Inspect_Interval = 1, -- How often autoInspectKnife will occur in seconds

	-- ===== Debug / Webhook Settings =====
	webhookDebugEnabled = false, -- Enable/disable sending webhook messages
	WEBHOOK_URL = "https://discord.com/api/webhooks/your_webhook_here", -- URL for webhook messages
	DEBUG = true, -- Enable/disable internal debug logs
	DEBUG_FLUSH_INTERVAL = 10, -- Interval (seconds) to flush debug buffer to webhook
	DEBUG_MAX_LINES = 15, -- Maximum number of debug lines to keep before flushing
}

local Settings = (_G.AISettings and _G.AISettings.Settings) or defaultSettings

local GuiAPI = {}
GuiAPI.Settings = Settings
function GuiAPI:Get(key)
	return Settings[key]
end
function GuiAPI:Set(key, value)
	Settings[key] = value
end
_G.AISettings = GuiAPI

print("=== AI Play Settings ===")

for key, value in pairs(Settings) do
	print(key, "=", value)
end
print("========================")

local firing = false
local pathInProgress = false

local Character, Humanoid, Root
local lastJumpTime = 0
local forceNewTarget = false
local dotPool = {}
local visualParts = {}
local linePool = {}
local currentHighlight
local looping = false
local connection
local DEBUG = true
local webhookDebugEnabled = false
local DEBUG_FLUSH_INTERVAL = 10
local DEBUG_MAX_LINES = 15
local PATH_REPATH_TIMER = 0
local DOT_UPDATE_TIMER = 0
local lastEquipTime = 0
local PATH_REPATH_INTERVAL = Settings.REPATH_INTERVAL
local DOT_UPDATE_INTERVAL = 0.05
local lockedCamTarget = nil
currentWeapon = currentWeapon or nil
local lastFPress = 0
_G.MGLFiring = false

local _debugBuffer = {}
local _lastFlush = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist
rayParams.IgnoreWater = true

local function setupCharacter(char)
	Character = char
	Humanoid = char:WaitForChild("Humanoid")
	Root = char:WaitForChild("HumanoidRootPart")
	rayParams.FilterDescendantsInstances = { Character }
end

if LocalPlayer.Character then
	setupCharacter(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(setupCharacter)

local LocalPlayer = Players.LocalPlayer
local mouse = LocalPlayer:GetMouse()

RunService.RenderStepped:Connect(function()
	if not Settings.autoFireEnabled then
		return
	end
	local target = mouse.Target
	if target and target.Parent then
		local humanoid = target.Parent:FindFirstChildOfClass("Humanoid")
		local targetPlayer = Players:GetPlayerFromCharacter(target.Parent)
		if humanoid and humanoid.Health > 0 and targetPlayer and targetPlayer.Team ~= LocalPlayer.Team then
			mouse1press()
			repeat
				RunService.RenderStepped:Wait()
			until not target.Parent:FindFirstChildOfClass("Humanoid") or mouse.Target ~= target
			mouse1release()
		end
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "AIPlayNotification"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999999
gui.Parent = playerGui

local frame = Instance.new("ImageLabel")
frame.Size = UDim2.fromOffset(250, 80)
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.fromOffset(Camera.ViewportSize.X / 2, -120)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
frame.Image = "rbxassetid://101480625157317"
frame.BackgroundTransparency = 1
frame.ImageTransparency = 0.2
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = frame

local shadow = Instance.new("UIStroke")
shadow.Color = Color3.fromRGB(0, 0, 0)
shadow.Transparency = 0.7
shadow.Thickness = 3
shadow.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.fromScale(1, 0.5)
title.Position = UDim2.fromScale(0, 0.1)
title.BackgroundTransparency = 1
title.Text = "Autoplay.lua"
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextStrokeTransparency = 0.5
title.Parent = frame

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.fromScale(1, 0.3)
subtitle.Position = UDim2.fromScale(0, 0.6)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Beta Testing"
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 16
subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
subtitle.TextStrokeTransparency = 0.7
subtitle.Parent = frame

local bell = Instance.new("ImageLabel")
bell.Name = "BellIcon"
bell.Size = UDim2.fromOffset(24, 24)
bell.Position = UDim2.new(1, 0, 0, 0)
bell.AnchorPoint = Vector2.new(1, 0)
bell.Image = "rbxassetid://104254514583221"
bell.BackgroundTransparency = 1
bell.Parent = frame
bell.Rotation = 0
bell.ZIndex = 10

local function createTween(obj, info, props)
	return TweenService:Create(obj, info, props)
end

local slideDownTween, slideUpTween, bobDownTween, bobUpTween
local swingTime = 0

local function updatePositions()
	local hiddenPos = UDim2.fromOffset(Camera.ViewportSize.X / 2, -120)
	local mainPos = UDim2.fromOffset(Camera.ViewportSize.X / 2, 30)
	local bobPos = UDim2.fromOffset(Camera.ViewportSize.X / 2, 38)

	slideDownTween =
		createTween(frame, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = mainPos })
	slideUpTween = createTween(
		frame,
		TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = hiddenPos }
	)
	bobDownTween =
		createTween(frame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = bobPos })
	bobUpTween =
		createTween(frame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = mainPos })
end

updatePositions()

Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	updatePositions()
	local hiddenPos = UDim2.fromOffset(Camera.ViewportSize.X / 2, -120)
	local mainPos = UDim2.fromOffset(Camera.ViewportSize.X / 2, 30)
	if frame.Position.Y.Offset > -120 then
		frame.Position = mainPos
	else
		frame.Position = hiddenPos
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if frame.Position.Y.Offset > -120 then
		swingTime = swingTime + dt * 2
		bell.Rotation = math.sin(swingTime * math.pi) * 25
	else
		bell.Rotation = 0
		swingTime = 0
	end
end)

local function getPlayersServiceName()
	for i, v in pairs(game:GetChildren()) do
		if v.ClassName == "Players" then
			return v.Name
		end
	end
end

local playersServiceName = getPlayersServiceName()
local plr = game[playersServiceName].LocalPlayer

local function applyHitboxes(char)
	if not char then
		return
	end

	local bodySize = Settings.hitboxSize
	local headSize = Settings.headHitboxSize

	local hitParts = {
		{ "RightUpperLeg", bodySize },
		{ "LeftUpperLeg", bodySize },
		{ "HumanoidRootPart", bodySize },
	}

	for _, partData in ipairs(hitParts) do
		local partName, size = partData[1], partData[2]
		local part = char:FindFirstChild(partName)
		if part then
			part.CanCollide = false
			part.Transparency = 1
			part.Size = size
		end
	end

	local head = char:FindFirstChild("HeadHB") or char:FindFirstChild("Head")
	if head then
		head.CanCollide = false
		head.Transparency = 1
		head.Size = headSize
	end
end

coroutine.wrap(function()
	while wait(1) do
		if GuiAPI:Get("hitboxExtenderEnabled") then
			for _, v in pairs(game[playersServiceName]:GetPlayers()) do
				if v.Name ~= plr.Name and v.Character and v.Character:FindFirstChild("Humanoid") then
					applyHitboxes(v.Character)
				end
			end
		end
	end
end)()

local function showNotification()
	slideDownTween:Play()

	bobDownTween:Play()
	bobDownTween.Completed:Wait()
	bobUpTween:Play()
	bobUpTween.Completed:Wait()

	task.wait(5)
	slideUpTween:Play()
	wait(1)
	gui:Destroy()
end

task.wait(0.2)
showNotification()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Settings.autoFireToggle then
		Settings.autoFireEnabled = not Settings.autoFireEnabled
		local hint = Instance.new("Hint", game.CoreGui)
		hint.Text = "AutoClick Toggled: " .. tostring(enabled)
		wait(1.5)
		hint:Destroy()
	end
end)

local function sendWebhookEmbed(title, description, color)
	if not Settings.webhookDebugEnabled then
		return
	end
	color = color or 16711680
	local Time = os.date("!*t", os.time())

	local Embed = {
		title = title,
		description = description,
		color = color,
		footer = { text = game.JobId },
		author = {
			name = LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")",
			url = "https://www.roblox.com/users/" .. LocalPlayer.UserId .. "/profile",
		},
		timestamp = string.format(
			"%d-%02d-%02dT%02d:%02d:%02dZ",
			Time.year,
			Time.month,
			Time.day,
			Time.hour,
			Time.min,
			Time.sec
		),
	}

	if type(request) == "function" then
		request({
			Url = Settings.WEBHOOK_URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({ content = "", embeds = { Embed } }),
		})
	end
end

local function sendSettingsToWebhook()
	if not Settings.webhookDebugEnabled then
		return
	end

	local descriptionLines = {}
	for key, value in pairs(Settings) do
		table.insert(descriptionLines, key .. " = " .. tostring(value))
	end
	local description = table.concat(descriptionLines, "\n")

	sendWebhookEmbed("AI Play Script - User Settings", description, 255)
end

local function bufferDebug(message, color)
	if not Settings.webhookDebugEnabled then
		return
	end
	table.insert(_debugBuffer, { message = message, color = color or 16711680 })

	if #_debugBuffer >= DEBUG_MAX_LINES then
		FlushDebugWebhook()
	end
end

function FlushDebugWebhook()
	if #_debugBuffer == 0 then
		return
	end

	local embeds = {}
	for i, entry in ipairs(_debugBuffer) do
		table.insert(embeds, {
			title = "Zeno AI Debug",
			description = entry.message,
			color = entry.color,
			timestamp = os.date("!*t"),
			author = {
				name = "ROBLOX",
				url = "https://www.roblox.com/",
				icon_url = "https://cdn.discordapp.com/embed/avatars/4.png",
			},
		})
	end

	if type(request) == "function" then
		request({
			Url = Settings.WEBHOOK_URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({ content = "", embeds = embeds }),
		})
	end

	_debugBuffer = {}
	_lastFlush = os.clock()
end

sendSettingsToWebhook()

sendWebhookEmbed("AI Play Script", "The AI Play script has been loaded successfully!", 65280)

LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
	forceNewTarget = true
end)

local function getCharacter(player)
	local char = player.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return nil
	end
	return char, hrp, humanoid
end

local function isVisible(targetChar)
	local origin = Camera.CFrame.Position
	local partsToCheck = { "Head", "Torso", "HumanoidRootPart" }

	for _, partName in ipairs(partsToCheck) do
		local part = targetChar:FindFirstChild(partName)
		if part then
			local direction = part.Position - origin

			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Blacklist
			params.FilterDescendantsInstances = { LocalPlayer.Character }
			params.IgnoreWater = true

			local result = Workspace:Raycast(origin, direction, params)

			if result then
				if result.Instance:IsDescendantOf(targetChar) then
					return true
				else
					return false
				end
			else
				return false
			end
		end
	end

	return false
end

local function isVisibleIgnoreObstacles(targetChar)
	local partsToCheck =
		{ "Head", "Torso", "HumanoidRootPart", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }
	for _, partName in ipairs(partsToCheck) do
		local part = targetChar:FindFirstChild(partName)
		if part then
			return true
		end
	end
	return false
end

local function equipKnife()
	if VIM then
		VIM:SendKeyEvent(true, Enum.KeyCode.Three, false, game)
		task.wait(0.1)
		VIM:SendKeyEvent(false, Enum.KeyCode.Three, false, game)
	end
end

local winnerWasVisible = false

local function isPositionValid(pos)
	return pos.Y > -50
end

local function getClosestEnemy()
	local closest, shortest = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Team ~= LocalPlayer.Team then
			local char, hrp, humanoid = getCharacter(plr)
			if char and humanoid.Health > 0 and hrp and isVisible(char) and isPositionValid(hrp.Position) then
				local dist = (Root.Position - hrp.Position).Magnitude
				if dist < shortest then
					closest = plr
					shortest = dist
				end
			end
		end
	end
	return closest
end

local function getRandomPlayer()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if
			plr ~= LocalPlayer
			and plr.Character
			and plr.Character:FindFirstChild("HumanoidRootPart")
			and plr.Character:FindFirstChild("Humanoid")
			and plr.Character.Humanoid.Health > 0
		then
			table.insert(list, plr)
		end
	end
	return #list > 0 and list[math.random(#list)] or nil
end

local function isHardBlocked(fromPos, toPos)
	local origin = fromPos + Vector3.new(0, 2, 0)
	local direction = toPos - fromPos
	local result = Workspace:Raycast(origin, direction, rayParams)
	if result and result.Instance and result.Instance.CanCollide then
		if result.Normal.Y >= Settings.MAX_SLOPE_Y then
			return false
		end
		return true
	end
	return false
end

local lastJumpTime = 0
local function timedJump()
	if tick() - lastJumpTime >= Settings.JUMP_INTERVAL then
		Humanoid.Jump = true
		lastJumpTime = tick()
		sendWebhookEmbed("AI Jump", "Humanoid jumped at " .. tostring(Root.Position), 16776960)
	end
end

local function getLinePart()
	local p = table.remove(linePool)
	if not p then
		p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Size = Vector3.new(0.1, 0.1, 1)
		p.Material = Enum.Material.Neon
		p.Parent = Workspace
	end
	return p
end

local function drawLine(startPos, endPos, color)
	if not Settings.visualsEnabled then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(0.1, 0.1, (startPos - endPos).Magnitude)
	part.CFrame = CFrame.new((startPos + endPos) / 2, endPos)
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Parent = Workspace
	table.insert(visualParts, part)
	task.delay(1.5, function()
		if part then
			part:Destroy()
		end
	end)
end

local function drawWaypoint(pos, color)
	if not Settings.visualsEnabled then
		debugLog("VISUAL", "Visuals disabled, skipping waypoint at " .. tostring(pos))
		return
	end
	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(0.5, 0.5, 0.5)
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Position = pos
	sphere.Color = color
	sphere.Material = Enum.Material.Neon
	sphere.Parent = Workspace
	table.insert(visualParts, sphere)
	task.delay(1.5, function()
		if sphere then
			sphere:Destroy()
		end
	end)
end

for i = 1, Settings.DOT_COUNT do
	local dot = Instance.new("Part")
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(0.3, 0.3, 0.3)
	dot.Anchored = true
	dot.CanCollide = false
	dot.Material = Enum.Material.Neon
	dot.Color = Color3.fromRGB(0, 255, 0)
	dot.Parent = Workspace

	table.insert(dotPool, {
		part = dot,
		waypoints = nil,
		segment = 1,
		progress = 0,
	})
end

Settings.DOT_SPEED = Settings.DOT_SPEED or 10

local function animateDots(dotPool, dt)
	if not Settings.visualsEnabled then
		return
	end

	for _, dot in ipairs(dotPool) do
		dot.progress = dot.progress or 0
		dot.segment = dot.segment or 1
		local waypoints = dot.waypoints
		if not waypoints or #waypoints < 2 then
			continue
		end

		local segIndex = dot.segment
		local nextIndex = segIndex + 1
		if nextIndex > #waypoints then
			nextIndex = 1
		end

		local startPos = waypoints[segIndex].Position
		local endPos = waypoints[nextIndex].Position
		local segmentLength = (endPos - startPos).Magnitude

		if dot.progress >= segmentLength then
			dot.progress = 0
			dot.segment = nextIndex
			segIndex = dot.segment
			nextIndex = segIndex + 1
			if nextIndex > #waypoints then
				nextIndex = 1
			end
			startPos = waypoints[segIndex].Position
			endPos = waypoints[nextIndex].Position
			segmentLength = (endPos - startPos).Magnitude
		end

		local t = segmentLength > 0 and dot.progress / segmentLength or 0
		dot.part.Position = startPos:Lerp(endPos, t)
	end
end

local function visualizePath(pathWaypoints)
	if not pathWaypoints or #pathWaypoints < 2 then
		return
	end

	for i = 1, #pathWaypoints - 1 do
		drawLine(pathWaypoints[i].Position, pathWaypoints[i + 1].Position, Color3.fromRGB(0, 255, 0))
		drawWaypoint(pathWaypoints[i].Position, Color3.fromRGB(0, 255, 0))
	end
	drawWaypoint(pathWaypoints[#pathWaypoints].Position, Color3.fromRGB(0, 255, 0))

	for _, dot in ipairs(dotPool) do
		dot.waypoints = pathWaypoints
		dot.segment = 1
		dot.progress = 0
	end
end

local function computeValidPath(startPos, targetPos)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentJumpHeight = 10,
		AgentMaxSlope = 45,
	})
	path:ComputeAsync(startPos, targetPos)
	if path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		local validWaypoints = {}
		local lastPos = startPos
		for _, wp in ipairs(waypoints) do
			if not isHardBlocked(lastPos, wp.Position) then
				table.insert(validWaypoints, wp)
				lastPos = wp.Position
			else
				break
			end
		end
		if #validWaypoints >= 2 then
			return validWaypoints
		end
	end
	return nil
end

local function getBestTarget()
	local bestTarget, shortestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Team ~= LocalPlayer.Team then
			local char, hrp, humanoid = getCharacter(player)
			if char and humanoid.Health > 0 then
				local dist = (Root.Position - hrp.Position).Magnitude
				if dist < shortestDist and (isVisible(char) or dist < 20) then
					bestTarget = player
					shortestDist = dist
				end
			end
		end
	end
	return bestTarget
end

local function computePath(startPos, targetPos)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentJumpHeight = 10,
		AgentMaxSlope = 45,
	})
	path:ComputeAsync(startPos, targetPos)

	if path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		local validWaypoints = {}
		local lastPos = startPos
		for _, wp in ipairs(waypoints) do
			if not isHardBlocked(lastPos, wp.Position) then
				table.insert(validWaypoints, wp)
				lastPos = wp.Position
			end
		end
		return #validWaypoints >= 2 and validWaypoints or nil
	else
		task.wait(0.3)
		return computePath(startPos, targetPos)
	end
end

local function isWinnerVisible()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then
		return false
	end

	local gui = pg:FindFirstChild("GUI")
	if not gui then
		return false
	end

	local winner = gui:FindFirstChild("Timer"):WaitForChild("Sub")
	if not winner then
		return false
	end

	return winner.Visible == true
end

local function stopLoop()
	looping = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

local function startLoop()
	if looping then
		return
	end
	looping = true

	connection = RunService.Heartbeat:Connect(function()
		if isWinnerVisible() then
			stopLoop()
			return
		end

		if not Humanoid or Humanoid.Health <= 0 then
			stopLoop()
			return
		end

		if Humanoid.WalkSpeed <= Settings.SPEED_THRESHOLD then
			stopLoop()
			return
		end

		local target = getClosestEnemy()
		if
			Settings.GOLDEN_KNIFE_TP
			and target
			and target.Character
			and target.Character:FindFirstChild("HumanoidRootPart")
		then
			Root.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, Settings.TELEPORT_OFFSET)
		end
	end)
end

RunService.Heartbeat:Connect(function()
	if isWinnerVisible() then
		stopLoop()
		return
	end

	if Humanoid and Humanoid.Health > 0 and Humanoid.WalkSpeed > Settings.SPEED_THRESHOLD then
		startLoop()
	end
end)

currentWeapon = currentWeapon or nil
local lastEquipTime = 0

RunService.Heartbeat:Connect(function()
	if not Settings.autoWeaponSwitchEnabled then
		return
	end
	if not Humanoid or Humanoid.Health <= 0 then
		return
	end
	if not Root then
		return
	end

	local enemyVisible = false
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Team ~= LocalPlayer.Team then
			local char, hrp, humanoid = getCharacter(plr)
			if char and humanoid.Health > 0 and isVisible(char) then
				enemyVisible = true
				break
			end
		end
	end

	local weaponToEquip = nil
	local now = tick()

	if enemyVisible then
		weaponToEquip = Enum.KeyCode.One
		lastEquipTime = now
	elseif Root.Velocity.Magnitude > 1 then
		if now - lastEquipTime >= Settings.autoWeaponSwitchCooldown then
			weaponToEquip = Enum.KeyCode.Three
			lastEquipTime = now
		end
	end

	if weaponToEquip and weaponToEquip ~= currentWeapon then
		currentWeapon = weaponToEquip
		if VIM then
			VIM:SendKeyEvent(true, weaponToEquip, false, game)
			task.wait(0.1)
			VIM:SendKeyEvent(false, weaponToEquip, false, game)
		end
	end
end)

local function followPath(pathWaypoints)
	if not pathWaypoints then
		return
	end
	local i = 1
	while i <= #pathWaypoints do
		local wp = pathWaypoints[i]
		local targetPos = wp.Position
		if (Root.Position - targetPos).Magnitude > 1 then
			Humanoid:MoveTo(targetPos)
			if wp.Action == Enum.PathWaypointAction.Jump then
				Humanoid.Jump = true
			end
			repeat
				timedJump()
				RunService.Heartbeat:Wait()
			until (Root.Position - targetPos).Magnitude < 2.5
		end
		i += 1
	end
end

local function getRandomEnemy()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Team ~= LocalPlayer.Team then
			local char, hrp, humanoid = getCharacter(plr)
			if char and humanoid.Health > 0 then
				table.insert(list, plr)
			end
		end
	end
	return #list > 0 and list[math.random(#list)] or nil
end

local function followTarget(target)
	if not Humanoid or Humanoid.Health <= 0 then
		return
	end
	if not target or not target.Character then
		return
	end

	forceNewTarget = false

	if currentHighlight then
		currentHighlight:Destroy()
	end
	currentHighlight = Instance.new("Highlight")
	currentHighlight.Adornee = target.Character
	currentHighlight.FillColor = Color3.fromRGB(255, 0, 0)
	currentHighlight.FillTransparency = 0.5
	currentHighlight.OutlineTransparency = 0
	currentHighlight.Parent = Workspace

	local targetRoot = target.Character:WaitForChild("HumanoidRootPart")
	local pathWaypoints = nil

	while
		Humanoid
		and Humanoid.Health > 0
		and target.Character
		and target.Character:FindFirstChild("Humanoid")
		and target.Character.Humanoid.Health > 0
		and not forceNewTarget
		and Settings.AIEnabled
	do
		if
			not pathWaypoints
			or (targetRoot.Position - pathWaypoints[#pathWaypoints].Position).Magnitude
				> Settings.TARGET_REPATH_DISTANCE
		then
			pathWaypoints = computeValidPath(Root.Position, targetRoot.Position)
			if pathWaypoints then
				visualizePath(pathWaypoints)
			else
				task.wait(Settings.REPATH_INTERVAL)
				continue
			end
		end

		local lastPos = Root.Position
		for _, wp in ipairs(pathWaypoints) do
			if forceNewTarget then
				break
			end
			local targetPos = wp.Position

			if (lastPos - targetPos).Magnitude >= Settings.WAYPOINT_SKIP_DISTANCE then
				if not isHardBlocked(Root.Position, targetPos) then
					Humanoid:MoveTo(targetPos)

					if wp.Action == Enum.PathWaypointAction.Jump then
						timedJump()
					end

					repeat
						timedJump()
						RunService.Heartbeat:Wait()
					until (Root.Position - targetPos).Magnitude < 2.5
						or (targetRoot.Position - targetPos).Magnitude > Settings.TARGET_REPATH_DISTANCE
					lastPos = targetPos
				end
			end
		end

		if isVisible(target.Character) then
			lockedCamTarget = target
		else
			lockedCamTarget = nil
		end

		pathWaypoints = nil
	end

	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
end

RunService.Heartbeat:Connect(function()
	if not Humanoid or Humanoid.Health <= 0 then
		return
	end
	if Root.Velocity.Magnitude < 1 and Settings.visualsEnabled then
		local randomTarget = getRandomPlayer()
		if randomTarget and randomTarget.Character then
			local path = PathfindingService:CreatePath({
				AgentRadius = 2.5,
				AgentHeight = 5,
				AgentCanJump = true,
				AgentJumpHeight = 10,
				AgentMaxSlope = 45,
			})
			path:ComputeAsync(Root.Position, randomTarget.Character.HumanoidRootPart.Position)
			if path.Status == Enum.PathStatus.Success then
				local waypoints = path:GetWaypoints()
				for i = 1, #waypoints - 1 do
					drawLine(waypoints[i].Position, waypoints[i + 1].Position, Color3.fromRGB(0, 255, 0))
					drawWaypoint(waypoints[i].Position, Color3.fromRGB(0, 255, 0))
				end
				animateDots(dotPool)
			end
		end
	end
end)

local function pickRandomAimPart(character)
	local parts = Settings.camlockAimParts
	if not parts or #parts == 0 then
		return "Head"
	end

	for _ = 1, 5 do
		local name = parts[math.random(#parts)]
		if character:FindFirstChild(name) then
			return name
		end
	end

	return character:FindFirstChild("Torso") and "Torso" or "Head"
end

Players.PlayerAdded:Connect(function(player)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		forceNewTarget = true
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player ~= LocalPlayer then
		player:GetPropertyChangedSignal("Team"):Connect(function()
			forceNewTarget = true
		end)
	end
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		Settings.visualsEnabled = not Settings.visualsEnabled
		for _, dot in ipairs(dotPool) do
			dot.part.Transparency = Settings.visualsEnabled
		end
		for _, v in ipairs(visualParts) do
			if v then
				v:Destroy()
			end
		end
		visualParts = {}
	elseif input.KeyCode == Settings.camLockToggle then
		Settings.camLockEnabled = not Settings.camLockEnabled
		Settings.autoFireEnabled = Settings.camLockEnabled
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not Settings.camLockEnabled or not Root or not Humanoid or Humanoid.Health <= 0 then
		lockedCamTarget = nil
		currentCamlockTarget = nil
		currentAimPartName = nil
		_G.MGLFiring = false
		return
	end

	local validTarget = lockedCamTarget
	if validTarget then
		local char = validTarget.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if
			not humanoid
			or humanoid.Health <= 0
			or validTarget.Team == LocalPlayer.Team
			or not hrp
			or not isVisible(char)
			or not isPositionValid(hrp.Position)
		then
			validTarget = nil
		end
	end

	if not validTarget then
		validTarget = getClosestEnemy()
		lockedCamTarget = validTarget
	end

	if validTarget then
		currentCamlockTarget = lockedCamTarget

		if Settings.lockAtParts then
			if lockedCamTarget ~= currentCamlockTarget then
				currentAimPartName = pickRandomAimPart(validTarget.Character)
			end
		else
			currentAimPartName = "Head"
		end

		local aimPart = validTarget.Character:FindFirstChild(currentAimPartName)
			or validTarget.Character:FindFirstChild("Head")
			or validTarget.Character:FindFirstChild("Torso")
			or validTarget.Character:FindFirstChild("HumanoidRootPart")

		if aimPart then
			local camPos = Camera.CFrame.Position
			local targetPos = aimPart.Position

			local equippedTool
			if LocalPlayer:FindFirstChild("NRPBS") and LocalPlayer.NRPBS:FindFirstChild("EquippedTool") then
				equippedTool = LocalPlayer.NRPBS.EquippedTool.Value
			end

			if equippedTool == "Electric Revolver" or equippedTool == "EM249" then
				targetPos = targetPos - Vector3.new(0, 3.9, 0)
			elseif equippedTool == "MGL" then
				targetPos = targetPos - Vector3.new(0, 7, 0)
			end

			local currentLook = Camera.CFrame.LookVector
			local desiredLook = (targetPos - camPos).Unit
			local dot = math.clamp(currentLook:Dot(desiredLook), -1, 1)
			local angle = math.acos(dot)
			local maxStep = Settings.camlockTurnSpeed * dt

			if angle < 0.0005 then
				Camera.CFrame = CFrame.new(camPos, targetPos)
			else
				local axis = currentLook:Cross(desiredLook)
				if axis.Magnitude > 1e-6 then
					axis = axis.Unit
					local step = CFrame.fromAxisAngle(axis, math.min(maxStep, angle))
					local newLook = step:VectorToWorldSpace(currentLook)
					Camera.CFrame = CFrame.lookAt(camPos, camPos + newLook)
				else
					Camera.CFrame = CFrame.new(camPos, targetPos)
				end
			end

			_G.MGLFiring = true
		else
			_G.MGLFiring = false
		end
	else
		lockedCamTarget = nil
		currentCamlockTarget = nil
		currentAimPartName = nil
		_G.MGLFiring = false
	end
end)

local function isValidTarget(target)
	if not target or not target.Parent then
		return false
	end
	local humanoid = target.Parent:FindFirstChildOfClass("Humanoid")
	local player = Players:GetPlayerFromCharacter(target.Parent)
	return humanoid and humanoid.Health > 0 and player and player.Team ~= LocalPlayer.Team
end

runningSequence = false

local function runSequence()
	if runningSequence then
		return
	end
	runningSequence = true

	local function tap(key)
		print("Tapping key:", key.Name)
		if VIM then
			VIM:SendKeyEvent(true, key, false, game)
			task.wait(0.25)
			VIM:SendKeyEvent(false, key, false, game)
		end
		task.wait(0.2)
	end

	task.spawn(function()
		tap(Enum.KeyCode.BackSlash)
		tap(Enum.KeyCode.Up)
		tap(Enum.KeyCode.Return)
		tap(Enum.KeyCode.BackSlash)
		tap(Enum.KeyCode.BackSlash)
		tap(Enum.KeyCode.Up)
		tap(Enum.KeyCode.Return)
		tap(Enum.KeyCode.Right)
		tap(Enum.KeyCode.Right)
		tap(Enum.KeyCode.Return)

		runningSequence = false
		print("runSequence finished")
	end)
end

menuGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if menuGui.Enabled then
		runSequence()
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not Settings.visualsEnabled then
		return
	end

	for _, dot in ipairs(dotPool) do
		local waypoints = dot.waypoints
		if waypoints and #waypoints > 1 and dot.part then
			local segIndex = dot.segment
			local nextIndex = segIndex + 1
			if nextIndex > #waypoints then
				nextIndex = 1
			end

			local startWp = waypoints[segIndex]
			local endWp = waypoints[nextIndex]
			if startWp and endWp and startWp.Position and endWp.Position then
				local startPos = startWp.Position
				local endPos = endWp.Position
				local length = (endPos - startPos).Magnitude

				if length > 0 then
					dot.progress = dot.progress + (Settings.DOT_SPEED or 0) * dt
					if dot.progress >= length then
						dot.progress = 0
						dot.segment = nextIndex
					end

					local t = length > 0 and dot.progress / length or 0
					dot.part.Position = startPos:Lerp(endPos, t)
				end
			end
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	animateDots(dotPool, dt)
end)

RunService.Heartbeat:Connect(function()
	if not webhookDebugEnabled then
		return
	end

	if os.clock() - _lastFlush >= DEBUG_FLUSH_INTERVAL then
		_lastFlush = os.clock()
		FlushDebugWebhook()
	end
end)

task.spawn(function()
	local currentTarget = nil
	while true do
		local dt = RunService.Heartbeat:Wait()

		if Settings.AIEnabled and Humanoid and Humanoid.Health > 0 then
			if
				not currentTarget
				or forceNewTarget
				or not currentTarget.Character
				or currentTarget.Character.Humanoid.Health <= 0
			then
				currentTarget = getClosestEnemy()
			end

			if currentTarget then
				followTarget(currentTarget)
			end
		else
			currentTarget = nil
		end
	end
end)

RunService.Heartbeat:Connect(function()
	if not Humanoid or Humanoid.Health <= 0 then
		return
	end
	if not Settings.autoInspectKnifeEnabled then
		return
	end
	if currentWeapon ~= Enum.KeyCode.Three then
		return
	end
	if Root.Velocity.Magnitude < 1 then
		return
	end

	if tick() - lastFPress >= Settings.Inspect_Interval then
		lastFPress = tick()
		if VIM then
			VIM:SendKeyEvent(true, Enum.KeyCode.F, false, game)
			task.wait(0.05)
			VIM:SendKeyEvent(false, Enum.KeyCode.F, false, game)
		end
	end
end)

task.spawn(function()
	while true do
		local mapFolder = Workspace:FindFirstChild("Map"):WaitForChild("Ignored")
		if mapFolder then
			for _, obj in ipairs(mapFolder:GetDescendants()) do
				if obj:IsA("BasePart") and obj.Transparency == 1 and obj.CanCollide == false then
					print("Deleting part:", obj:GetFullName())
					obj:Destroy()
				end
			end
		end
		task.wait(1)
	end
end)

RunService.Heartbeat:Connect(function()
	local winnerVisible = isWinnerVisible()
	if winnerVisible and not winnerWasVisible then
		winnerWasVisible = true
		Settings.camLockEnabled = false
		sendWebhookEmbed("Winner Frame Visible", "Winner frame is now visible.", 16711680)
	elseif not winnerVisible and winnerWasVisible then
		winnerWasVisible = false
		Settings.camLockEnabled = true
	end
end)

local GuiAPI = {}

function GuiAPI:Get(key)
	return Settings[key]
end

function GuiAPI:Set(key, value)
	Settings[key] = value
end

if not _G.AISettings then
	local GuiAPI = {}
	GuiAPI.Settings = Settings
	function GuiAPI:Get(key)
		return self.Settings[key]
	end
	function GuiAPI:Set(key, value)
		self.Settings[key] = value
	end
	_G.AISettings = GuiAPI
end
