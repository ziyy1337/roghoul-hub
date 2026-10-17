--// Ro-Ghoul aim: silent (camera Mouse.Hit) + sticky target + prediction
-- Game attacks use MH() = Mouse.Hit (where the CAMERA looks), not character facing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Aim = {
	Enabled = false, -- starts OFF — waits for you
	SilentAim = false,
	CameraAim = false,
	TeamCheck = false,
	WallCheck = false,

	FOV = 180, -- full cone degrees
	Smoothness = 0.45,
	Bone = "Head",
	Target = nil,

	-- sticky: stay on the same target until it dies / leaves stick FOV
	StickyAim = true,
	StickFOVMultiplier = 1.6, -- lose lock when angle > FOV/2 * multiplier

	-- prediction (seconds of lead on target velocity)
	PredictionMode = "Auto", -- "Off" | "Auto" | "Manual"
	PredictionManual = 0.15, -- seconds when Manual
	PredictionSpeed = 350,   -- studs/s used by Auto (dist/speed = lead time)
	PredictionYBoost = 0,    -- extra vertical offset

	-- indicators
	ShowFov = true,
	FovColor = Color3.fromRGB(255, 80, 80),
	FovThickness = 1.5,
	ShowTargetLine = true,
	LineColor = Color3.fromRGB(80, 160, 255),
	LineThickness = 1.5,
	DotColor = Color3.fromRGB(80, 160, 255),

	-- camera FOV changer
	UseCameraFov = false,
	CameraFov = 70,

	-- keybind (menu does NOT touch aim)
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
		if m and t then
			return m.Value == t.Value
		end
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

-- lead target position by velocity
function Aim.GetPredictedPosition(part)
	if not part then return nil end
	local mode = Aim.PredictionMode
	if mode == "Off" then
		return part.Position
	end
	local vel = part.AssemblyLinearVelocity or Vector3.zero
	local t = 0
	if mode == "Manual" then
		t = math.clamp(Aim.PredictionManual, 0, 1.5)
	else -- Auto
		local dist = (part.Position - Camera.CFrame.Position).Magnitude
		local speed = math.max(Aim.PredictionSpeed, 50)
		t = math.clamp(dist / speed, 0, 1.5)
	end
	return part.Position + vel * t + Vector3.new(0, Aim.PredictionYBoost, 0)
end

local function scoreTarget(bone)
	local pos, onScreen = Camera:WorldToViewportPoint(bone.Position)
	if not onScreen then return nil end
	local angle = angleToTarget(bone)
	local halfCone = math.clamp(Aim.FOV, 1, 360) / 2
	if angle > halfCone then return nil end
	if not canSee(Camera.CFrame.Position, bone) then return nil end
	return angle * 1000 + pos.Z
end

function Aim.GetTarget()
	if not Aim.Enabled then
		return nil
	end

	local halfCone = math.clamp(Aim.FOV, 1, 360) / 2
	local stickCone = halfCone * math.max(Aim.StickFOVMultiplier, 1)

	-- sticky: keep current lock if still valid
	if Aim.StickyAim and Aim.Target then
		if isAlive(Aim.Target) then
			local bone = getBone(Aim.Target.Character)
			if bone then
				local angle = angleToTarget(bone)
				local pos, onScreen = Camera:WorldToViewportPoint(bone.Position)
				local dist = (Camera.CFrame.Position - bone.Position).Magnitude
				if onScreen and angle <= stickCone and dist < 8000 and canSee(Camera.CFrame.Position, bone) then
					return Aim.Target -- wait on this person
				end
			end
		end
		-- lost sticky — fall through to re-acquire
		Aim.Target = nil
	end

	local best, bestScore = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and isAlive(plr) then
			if not (Aim.TeamCheck and sameTeam(plr)) then
				local bone = getBone(plr.Character)
				if bone then
					local s = scoreTarget(bone)
					if s and s < bestScore then
						bestScore = s
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
	local aimPos = Aim.GetPredictedPosition(bone) or bone.Position
	local smooth = math.clamp(Aim.Smoothness, 0.05, 1)
	local goal = CFrame.lookAt(Camera.CFrame.Position, aimPos)
	Camera.CFrame = Camera.CFrame:Lerp(goal, 1 - math.pow(1 - smooth, dt * 60))
end

-- Drawing
local fovCircle, targetLine, targetDot

local function newDrawing(class)
	if not Drawing or not Drawing.new then return nil end
	local ok, obj = pcall(Drawing.new, class)
	return ok and obj or nil
end

local function ensureDrawings()
	if not fovCircle then
		fovCircle = newDrawing("Circle")
		if fovCircle then
			fovCircle.Visible = false
			fovCircle.NumSides = 72
			fovCircle.Filled = false
		end
	end
	if not targetLine then
		targetLine = newDrawing("Line")
		if targetLine then
			targetLine.Visible = false
			targetLine.Thickness = Aim.LineThickness
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

local function updateIndicators()
	ensureDrawings()
	local vp = Camera and Camera.ViewportSize or Vector2.new(960, 540)
	local center = Vector2.new(vp.X / 2, vp.Y / 2)

	if fovCircle then
		local show = Aim.ShowFov and Aim.Enabled and Aim.SilentAim
		fovCircle.Visible = show
		if show then
			fovCircle.Position = center
			local camFov = math.rad(math.max(Camera.FieldOfView, 1))
			local half = math.rad(math.clamp(Aim.FOV, 1, 360) / 2)
			fovCircle.Radius = math.clamp((math.tan(half) / math.tan(camFov / 2)) * (vp.X / 2), 10, vp.X)
			fovCircle.Color = Aim.FovColor
			fovCircle.Thickness = Aim.FovThickness
		end
	end

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

local defaultCameraFov = nil
local function applyCameraFov()
	if not Camera then return end
	if defaultCameraFov == nil then
		defaultCameraFov = Camera.FieldOfView
	end
	if Aim.UseCameraFov then
		Camera.FieldOfView = math.clamp(Aim.CameraFov, 30, 120)
	elseif math.abs(Camera.FieldOfView - math.clamp(Aim.CameraFov, 30, 120)) < 0.01 then
		Camera.FieldOfView = defaultCameraFov
	end
end

function Aim.SetAimEnabled(on)
	Aim.Enabled = on and true or false
	Aim.AimKeyActive = Aim.Enabled
	if not Aim.Enabled then
		Aim.Target = nil
		if fovCircle then fovCircle.Visible = false end
		if targetLine then targetLine.Visible = false end
		if targetDot then targetDot.Visible = false end
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

local SIDE_BUTTON_NAMES = {
	MouseButton4 = true, MouseButton5 = true,
	MouseBackButton = true, MouseForwardButton = true,
	MouseX1 = true, MouseX2 = true,
}

local function isAimKeyInput(input)
	if not input then return false end
	local k = Aim.AimKey
	if k and (input.KeyCode == k or input.UserInputType == k) then
		return true
	end
	local ut = tostring(input.UserInputType):gsub("Enum%.UserInputType%.", "")
	local kc = tostring(input.KeyCode):gsub("Enum%.KeyCode%.", "")
	if SIDE_BUTTON_NAMES[ut] or SIDE_BUTTON_NAMES[kc] then
		if tostring(k or ""):find("Mouse") then
			return true
		end
	end
	return false
end

local UIS = UserInputService
UIS.InputBegan:Connect(function(input, gameProcessed)
	if not Aim.UseBuiltinAimKey or gameProcessed then return end
	if not isAimKeyInput(input) then return end
	if Aim.AimKeyMode == "Hold" then
		Aim.SetAimEnabled(true)
	else
		Aim.ToggleAim()
	end
end)

UIS.InputEnded:Connect(function(input)
	if not Aim.UseBuiltinAimKey or Aim.AimKeyMode ~= "Hold" then return end
	if isAimKeyInput(input) then
		Aim.SetAimEnabled(false)
	end
end)

-- Silent: game MH() reads Mouse.Hit from the CAMERA ray — spoof to predicted target.
local hooksInstalled = false
local oldIndex
local inHook = false

local function installMouseHook()
	if hooksInstalled then return end
	if not hookmetamethod then return end

	local wrap = (type(newcclosure) == "function") and newcclosure or function(f) return f end
	local callerIsCheck = function()
		if type(checkcaller) == "function" then return checkcaller() end
		return false
	end

	oldIndex = hookmetamethod(game, "__index", wrap(function(self, key)
		if inHook then
			return oldIndex(self, key)
		end
		if callerIsCheck() or not Aim.Enabled or not Aim.SilentAim then
			return oldIndex(self, key)
		end
		if key ~= "Hit" and key ~= "Target" and key ~= "UnitRay" then
			return oldIndex(self, key)
		end

		inHook = true
		local ok, spoofed, useSpoof = pcall(function()
			local target = Aim.Target
			local bone = target and getBone(target.Character)
			if not bone or not Camera then
				return nil, false
			end

			local isMouse = false
			local okCn, cn = pcall(function()
				return typeof(self) == "Instance" and self.ClassName
			end)
			if okCn and cn == "Mouse" then
				isMouse = true
			elseif not okCn then
				local okStr, str = pcall(tostring, self)
				if okStr and str:lower():find("mouse") then
					isMouse = true
				end
			end
			if not isMouse then
				return nil, false
			end

			-- predicted aim point (camera-ray style hit, not character facing)
			local aimPos = Aim.GetPredictedPosition(bone) or bone.Position

			if key == "Hit" then
				-- Hit is where the camera ray lands: put it on the predicted point
				return CFrame.lookAt(aimPos, Camera.CFrame.Position), true
			elseif key == "Target" then
				return bone, true
			else
				local origin = Camera.CFrame.Position
				local dir = aimPos - origin
				if dir.Magnitude < 1e-4 then
					dir = Camera.CFrame.LookVector
				end
				return Ray.new(origin, dir.Unit * 4096), true
			end
		end)
		inHook = false

		if ok and useSpoof then
			return spoofed
		end
		return oldIndex(self, key)
	end))
	hooksInstalled = true
end

RunService.RenderStepped:Connect(function(dt)
	Camera = Workspace.CurrentCamera
	pcall(applyCameraFov)
	if Aim.Enabled then
		local ok, err = pcall(Aim.GetTarget)
		if not ok then
			Aim.Target = nil
			warn("[Aimbot] GetTarget failed:", err)
		end
		-- note: we do NOT rotate the character — this game aims with the camera
		if Aim.CameraAim and Aim.Target then
			local okCam, errCam = pcall(updateCamera, dt)
			if not okCam then
				warn("[Aimbot] camera aim failed:", errCam)
			end
		end
	end
	pcall(updateIndicators)
end)

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1)
	Camera = Workspace.CurrentCamera
	Aim.Target = nil
end)

local mt = getrawmetatable and getrawmetatable(game)
if mt and hookmetamethod then
	installMouseHook()
else
	pcall(installMouseHook)
end

return Aim
