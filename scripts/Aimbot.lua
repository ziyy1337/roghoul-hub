--// Ro-Ghoul aim
-- Silent: spoof PlayerMouse.Hit (game MH() = camera ray). Ping-based prediction.
-- Dual FOV: separate cones for silent + camera; lock only inside the active FOV.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local PlayerMouse = nil

local function getMouse()
	if PlayerMouse and PlayerMouse.Parent ~= nil then
		return PlayerMouse
	end
	PlayerMouse = LocalPlayer:GetMouse()
	return PlayerMouse
end

local Aim = {
	Enabled = false, -- waits for you
	SilentAim = false,
	CameraAim = false,
	TeamCheck = false,
	WallCheck = false,

	-- separate FOV cones (degrees)
	SilentFOV = 180,  -- silent lock cone
	CameraFOV = 90,   -- camera-lock cone
	-- legacy alias kept for UI that still sets Aim.FOV
	FOV = 180,

	StickyAim = true,
	StickMulti = 1.6,
	Smoothness = 0.45,
	Bone = "Head",
	Target = nil,

	-- prediction from live ping
	PredictionMode = "Auto", -- Off | Auto | Manual
	PredictionManual = 0.05, -- extra seconds on top of ping (Manual)
	PredictionAutoScale = 1.0, -- multiply live ping (Auto)
	PingMs = 0,

	-- indicators (always on screen when their feature is active)
	ShowSilentFov = true,
	SilentFovColor = Color3.fromRGB(255, 80, 80),
	ShowCameraFov = true,
	CameraFovColor = Color3.fromRGB(80, 160, 255),
	FovThickness = 1.5,
	ShowTargetLine = true,
	LineColor = Color3.fromRGB(80, 160, 255),
	LineThickness = 1.5,
	DotColor = Color3.fromRGB(80, 160, 255),

	-- camera FieldOfView changer (not the aim cone)
	UseCameraFov = false,
	CameraFieldOfView = 70,

	AimKey = Enum.KeyCode.MouseBackButton,
	AimKeyMode = "Toggle",
	AimKeyActive = false,
	UseBuiltinAimKey = true,
}

local function isAlive(plr)
	local char = plr and plr.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
	return hum ~= nil and hrp ~= nil and hum.Health > 0
end

local function getBone(char)
	if not char then return nil end
	return char:FindFirstChild(Aim.Bone) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

local function sameTeam(plr)
	if LocalPlayer.Team and plr.Team then
		return LocalPlayer.Team == plr.Team
	end
	local mine = LocalPlayer:FindFirstChild("PlayerFolder")
	local theirs = plr:FindFirstChild("PlayerFolder")
	if mine and theirs then
		local m = mine:FindFirstChild("Customization")
		local t = theirs:FindFirstChild("Customization")
		m = m and m:FindFirstChild("Team")
		t = t and t:FindFirstChild("Team")
		if m and t then return m.Value == t.Value end
	end
	return false
end

local function canSee(fromPos, part)
	if not Aim.WallCheck then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { Workspace.Hitboxes }
	if LocalPlayer.Character then table.insert(exclude, LocalPlayer.Character) end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(fromPos, (part.Position - fromPos), params)
	if not result then return true end
	return result.Instance:IsDescendantOf(part.Parent) or result.Instance == part
end

local function angleToTarget(part)
	local look = Camera.CFrame.LookVector
	local to = part.Position - Camera.CFrame.Position
	if to.Magnitude < 1e-4 then return 0 end
	return math.deg(math.acos(math.clamp(look:Dot(to.Unit), -1, 1)))
end

local function refreshPing()
	local ok, v = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and type(v) == "number" and v == v and v >= 0 then
		Aim.PingMs = v
	end
	return Aim.PingMs
end

function Aim.GetPingSeconds()
	return refreshPing() / 1000
end

-- prediction lead time: built from live ping
function Aim.GetPredictionTime(dist)
	local pingSec = refreshPing() / 1000
	local mode = Aim.PredictionMode
	if mode == "Off" then
		return 0
	elseif mode == "Manual" then
		return math.clamp(pingSec + Aim.PredictionManual, 0, 3)
	end
	-- Auto: scale live ping; optional small distance term keeps long shots honest
	local t = pingSec * math.max(Aim.PredictionAutoScale, 0)
	return math.clamp(t, 0, 3)
end

function Aim.GetPredictedPosition(part)
	if not part then return nil end
	local vel = part.AssemblyLinearVelocity or Vector3.zero
	local dist = (part.Position - Camera.CFrame.Position).Magnitude
	local t = Aim.GetPredictionTime(dist)
	return part.Position + vel * t
end

local function inSilentFov(bone)
	local half = math.clamp(Aim.SilentFOV, 1, 360) / 2
	return angleToTarget(bone) <= half
end

local function inCameraFov(bone)
	local half = math.clamp(Aim.CameraFOV, 1, 360) / 2
	return angleToTarget(bone) <= half
end

-- target must satisfy every ACTIVE feature's FOV
local function passesActiveFov(bone)
	local ok = true
	if Aim.SilentAim then ok = ok and inSilentFov(bone) end
	if Aim.CameraAim then ok = ok and inCameraFov(bone) end
	if not Aim.SilentAim and not Aim.CameraAim then
		-- still show line: use silent FOV as default lock cone
		ok = inSilentFov(bone)
	end
	return ok
end

local function stickCone()
	local half = math.clamp(Aim.SilentFOV, 1, 360) / 2
	if Aim.CameraAim and not Aim.SilentAim then
		half = math.clamp(Aim.CameraFOV, 1, 360) / 2
	end
	if Aim.SilentAim and Aim.CameraAim then
		half = math.min(
			math.clamp(Aim.SilentFOV, 1, 360),
			math.clamp(Aim.CameraFOV, 1, 360)
		) / 2
	end
	return half * math.max(Aim.StickMulti, 1)
end

function Aim.GetTarget()
	if not Aim.Enabled then return nil end

	if Aim.StickyAim and Aim.Target then
		if isAlive(Aim.Target) then
			local bone = getBone(Aim.Target.Character)
			if bone then
				local ang = angleToTarget(bone)
				local _, onScreen = Camera:WorldToViewportPoint(bone.Position)
				local dist = (Camera.CFrame.Position - bone.Position).Magnitude
				if onScreen and ang <= stickCone() and dist < 8000 and canSee(Camera.CFrame.Position, bone) then
					return Aim.Target
				end
			end
		end
		Aim.Target = nil
	end

	local best, bestScore = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and isAlive(plr) and not (Aim.TeamCheck and sameTeam(plr)) then
			local bone = getBone(plr.Character)
			if bone then
				local pos, onScreen = Camera:WorldToViewportPoint(bone.Position)
				if onScreen and passesActiveFov(bone) and canSee(Camera.CFrame.Position, bone) then
					local score = angleToTarget(bone) * 1000 + pos.Z
					if score < bestScore then
						bestScore = score
						best = plr
					end
				end
			end
		end
	end

	Aim.Target = best
	return best
end

function Aim.FaceTarget(target)
	if not target then return end
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local bone = getBone(target.Character)
	if hrp and bone then
		local look = Vector3.new(bone.Position.X, hrp.Position.Y, bone.Position.Z) - hrp.Position
		if look.Magnitude > 0.05 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + look.Unit)
		end
	end
end

local function updateCamera(dt)
	if not (Aim.Enabled and Aim.CameraAim) then return end
	local target = Aim.Target or Aim.GetTarget()
	if not target then return end
	local bone = getBone(target.Character)
	if not bone then return end
	if not inCameraFov(bone) then return end -- only lock inside camera FOV
	local aimPos = Aim.GetPredictedPosition(bone) or bone.Position
	local smooth = math.clamp(Aim.Smoothness, 0.05, 1)
	local goal = CFrame.lookAt(Camera.CFrame.Position, aimPos)
	Camera.CFrame = Camera.CFrame:Lerp(goal, 1 - math.pow(1 - smooth, dt * 60))
end

-- drawings
local silentCircle, camCircle, targetLine, targetDot

local function newDrawing(class)
	if not Drawing or not Drawing.new then return nil end
	local ok, obj = pcall(Drawing.new, class)
	return ok and obj or nil
end

local function ensureDrawings()
	if not silentCircle then
		silentCircle = newDrawing("Circle")
		if silentCircle then
			silentCircle.Visible = false
			silentCircle.NumSides = 72
			silentCircle.Filled = false
		end
	end
	if not camCircle then
		camCircle = newDrawing("Circle")
		if camCircle then
			camCircle.Visible = false
			camCircle.NumSides = 72
			camCircle.Filled = false
		end
	end
	if not targetLine then
		targetLine = newDrawing("Line")
		if targetLine then
			targetLine.Visible = false
		end
	end
	if not targetDot then
		targetDot = newDrawing("Circle")
		if targetDot then
			targetDot.Visible = false
			targetDot.Radius = 4
			targetDot.NumSides = 16
			targetDot.Filled = true
			targetDot.Thickness = 1
		end
	end
end

local function coneRadiusPx(coneDeg, vp)
	local camFov = math.rad(math.max(Camera.FieldOfView, 1))
	local half = math.rad(math.clamp(coneDeg, 1, 360) / 2)
	return math.clamp((math.tan(half) / math.tan(camFov / 2)) * (vp.X / 2), 8, vp.X * 1.5)
end

local function drawCone(circle, coneDeg, color, show)
	if not circle then return end
	circle.Visible = show
	if not show then return end
	local vp = Camera.ViewportSize
	circle.Position = Vector2.new(vp.X / 2, vp.Y / 2)
	circle.Radius = coneRadiusPx(coneDeg, vp)
	circle.Color = color
	circle.Thickness = Aim.FovThickness
end

local function updateIndicators()
	ensureDrawings()
	local vp = Camera and Camera.ViewportSize or Vector2.new(960, 540)
	local center = Vector2.new(vp.X / 2, vp.Y / 2)

	-- FOV circles ALWAYS visible while their feature is on (and aim master on)
	local base = Aim.Enabled
	drawCone(silentCircle, Aim.SilentFOV, Aim.SilentFovColor, base and Aim.SilentAim and Aim.ShowSilentFov)
	drawCone(camCircle, Aim.CameraFOV, Aim.CameraFovColor, base and Aim.CameraAim and Aim.ShowCameraFov)

	local bone = Aim.Target and getBone(Aim.Target.Character)
	local showLine = Aim.ShowTargetLine and Aim.Enabled and bone ~= nil

	if targetLine then
		if showLine then
			local sp, onScreen = Camera:WorldToViewportPoint(bone.Position)
			targetLine.From = center
			targetLine.To = Vector2.new(sp.X, sp.Y)
			targetLine.Color = Aim.LineColor
			targetLine.Thickness = Aim.LineThickness
			targetLine.Visible = onScreen
		else
			targetLine.Visible = false
		end
	end
	if targetDot then
		if showLine then
			local sp, onScreen = Camera:WorldToViewportPoint(bone.Position)
			targetDot.Position = Vector2.new(sp.X, sp.Y)
			targetDot.Color = Aim.DotColor
			targetDot.Visible = onScreen
		else
			targetDot.Visible = false
		end
	end
end

local defaultFieldOfView = nil
local function applyFieldOfView()
	if not Camera then return end
	if defaultFieldOfView == nil then
		defaultFieldOfView = Camera.FieldOfView
	end
	if Aim.UseCameraFov then
		Camera.FieldOfView = math.clamp(Aim.CameraFieldOfView, 30, 120)
	elseif math.abs(Camera.FieldOfView - math.clamp(Aim.CameraFieldOfView, 30, 120)) < 0.01 then
		Camera.FieldOfView = defaultFieldOfView
	end
end

local installHooks -- defined later; install only when aim is enabled

function Aim.SetAimEnabled(on)
	Aim.Enabled = on and true or false
	Aim.AimKeyActive = Aim.Enabled
	if Aim.Enabled then
		pcall(installHooks)
	else
		Aim.Target = nil
	end
end

function Aim.ToggleAim()
	Aim.SetAimEnabled(not Aim.Enabled)
	return Aim.Enabled
end

function Aim.SetAimKey(key)
	Aim.AimKey = key
end

function Aim.ClearSticky()
	Aim.Target = nil
end

-- ===================== SILENT AIM HOOKS (multiple methods) =====================
-- Mouse ClassName is "PlayerMouse". Hit is read-only → must hook __index.

local function isPlayerMouse(self)
	if typeof(self) ~= "Instance" then return false end
	local cn = self.ClassName
	return cn == "PlayerMouse" or cn == "Mouse" or cn == "LocalPlayerMouse"
end

local inHook = false
local hookedGame = false
local hookedMouse = false
local oldGameIndex
local oldMouseIndex

local function buildSpoof(self, key)
	if inHook then return nil, false end
	if not Aim.Enabled or not Aim.SilentAim then return nil, false end
	if key ~= "Hit" and key ~= "Target" and key ~= "UnitRay" then return nil, false end
	if not isPlayerMouse(self) then return nil, false end

	local target = Aim.Target
	local bone = target and getBone(target.Character)
	if not bone or not Camera then return nil, false end
	if not inSilentFov(bone) then return nil, false end -- only spoof inside silent FOV

	inHook = true
	local ok, spoofed, use = pcall(function()
		local aimPos = Aim.GetPredictedPosition(bone) or bone.Position
		if key == "Hit" then
			return CFrame.lookAt(aimPos, Camera.CFrame.Position), true
		elseif key == "Target" then
			return bone, true
		end
		local origin = Camera.CFrame.Position
		local dir = aimPos - origin
		if dir.Magnitude < 1e-4 then dir = Camera.CFrame.LookVector end
		return Ray.new(origin, dir.Unit * 4096), true
	end)
	inHook = false
	if ok and use then return spoofed, true end
	return nil, false
end

installHooks = function()
	local wrap = (type(newcclosure) == "function") and newcclosure or function(f) return f end
	local function safeCheckcaller()
		if type(checkcaller) == "function" then return checkcaller() end
		return false
	end

	-- Method A: game metatable __index
	if not hookedGame and type(hookmetamethod) == "function" and getrawmetatable then
		local ok = pcall(function()
			local mt = getrawmetatable(game)
			local orig = mt and mt.__index
			oldGameIndex = function(self, key)
				if type(orig) == "function" then return orig(self, key) end
				if type(orig) == "table" then
					local v = orig[key]
					if type(v) == "function" then return v(self) end
					return v
				end
				return nil
			end
			hookmetamethod(game, "__index", wrap(function(self, key)
				if not safeCheckcaller() then
					local spoof, hit = buildSpoof(self, key)
					if hit then return spoof end
				end
				return oldGameIndex(self, key)
			end))
		end)
		hookedGame = ok
	end

	-- Method B: PlayerMouse metatable
	if not hookedMouse then
		local m = getMouse()
		if m and type(hookmetamethod) == "function" and getrawmetatable then
			local ok = pcall(function()
				local mt = getrawmetatable(m)
				local orig = mt and mt.__index
				oldMouseIndex = function(self, key)
					if type(orig) == "function" then return orig(self, key) end
					if type(orig) == "table" then
						local v = orig[key]
						if type(v) == "function" then return v(self) end
						return v
					end
					return nil
				end
				hookmetamethod(m, "__index", wrap(function(self, key)
					if not safeCheckcaller() then
						local spoof, hit = buildSpoof(self, key)
						if hit then return spoof end
					end
					return oldMouseIndex(self, key)
				end))
			end)
			hookedMouse = ok
		end
	end

	return hookedGame or hookedMouse
end

local function reinstallMouseHook()
	hookedMouse = false
	installHooks()
end

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1)
	Camera = Workspace.CurrentCamera
	Aim.Target = nil
	reinstallMouseHook()
end)

-- ===================== keybinds =====================
local SIDE_BUTTON_NAMES = {
	MouseButton4 = true, MouseButton5 = true,
	MouseBackButton = true, MouseForwardButton = true,
	MouseX1 = true, MouseX2 = true,
}

local function isAimKeyInput(input)
	if not input then return false end
	local k = Aim.AimKey
	if k and (input.KeyCode == k or input.UserInputType == k) then return true end
	local ut = tostring(input.UserInputType):gsub("Enum%.UserInputType%.", "")
	local kc = tostring(input.KeyCode):gsub("Enum%.KeyCode%.", "")
	if (SIDE_BUTTON_NAMES[ut] or SIDE_BUTTON_NAMES[kc]) and tostring(k or ""):find("Mouse") then
		return true
	end
	return false
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not Aim.UseBuiltinAimKey or gameProcessed then return end
	if not isAimKeyInput(input) then return end
	if Aim.AimKeyMode == "Hold" then
		Aim.SetAimEnabled(true)
	else
		Aim.ToggleAim()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not Aim.UseBuiltinAimKey or Aim.AimKeyMode ~= "Hold" then return end
	if isAimKeyInput(input) then Aim.SetAimEnabled(false) end
end)

-- ===================== main loop =====================
local pingTick = 0
RunService.RenderStepped:Connect(function(dt)
	Camera = Workspace.CurrentCamera
	pingTick += dt
	if pingTick > 0.25 then
		pingTick = 0
		refreshPing()
	end
	pcall(applyFieldOfView)

	if Aim.Enabled then
		local ok, err = pcall(Aim.GetTarget)
		if not ok then
			Aim.Target = nil
			warn("[Aimbot] GetTarget:", err)
		end
		if Aim.CameraAim and Aim.Target then
			pcall(updateCamera, dt)
		end
	end
	pcall(updateIndicators)
end)

-- Hooks install lazily on Aim.SetAimEnabled(true) so loading the hub
-- does not break walking / menus with a half-broken __index hook.

return Aim
