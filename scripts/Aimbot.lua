--// Ro-Ghoul aim: silent (Mouse.Hit) + camera look + target line
-- Standalone-safe; DeadcellSenseHub loads this as well.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Aim = {
	Enabled = false,
	SilentAim = false,
	CameraAim = false,
	TeamCheck = false,
	WallCheck = false,
	-- FOV = full cone in degrees (360 = lock anything on screen)
	FOV = 180,
	Smoothness = 0.45,
	Bone = "Head",
	Target = nil,

	-- visuals
	ShowFov = true,
	FovColor = Color3.fromRGB(255, 80, 80),
	FovThickness = 1.5,
	ShowTargetLine = true,
	LineColor = Color3.fromRGB(80, 160, 255), -- blue
	LineThickness = 1.5,
	DotColor = Color3.fromRGB(80, 160, 255),

	-- Camera FOV changer
	UseCameraFov = false,
	CameraFov = 70,

	-- keybind
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
	local inst = result.Instance
	return inst:IsDescendantOf(part.Parent) or inst == part
end

-- true angular FOV: Aim.FOV is full cone degrees (180 = in front half, 360 = everything)
local function angleToTarget(part)
	local origin = Camera.CFrame.Position
	local look = Camera.CFrame.LookVector
	local to = part.Position - origin
	if to.Magnitude < 1e-4 then return 0 end
	local dot = look:Dot(to.Unit)
	return math.deg(math.acos(math.clamp(dot, -1, 1)))
end

function Aim.GetTarget()
	if not Aim.Enabled then return nil end
	local best, bestScore = nil, math.huge
	local halfCone = math.clamp(Aim.FOV, 1, 360) / 2

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and isAlive(plr) then
			if not (Aim.TeamCheck and sameTeam(plr)) then
				local bone = getBone(plr.Character)
				if bone then
					local pos, onScreen = Camera:WorldToViewportPoint(bone.Position)
					if onScreen then
						local angle = angleToTarget(bone)
						if angle <= halfCone and canSee(Camera.CFrame.Position, bone) then
							-- prefer smallest angle (crosshair lock), break ties by distance
							local score = angle * 1000 + pos.Z
							if score < bestScore then
								bestScore = score
								best = plr
							end
						end
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
	local smooth = math.clamp(Aim.Smoothness, 0.05, 1)
	local goal = CFrame.lookAt(Camera.CFrame.Position, bone.Position)
	Camera.CFrame = Camera.CFrame:Lerp(goal, 1 - math.pow(1 - smooth, dt * 60))
end

-- Drawing: FOV circle + blue line + dot
local fovCircle, targetLine, targetDot

local function newDrawing(class)
	if not Drawing or not Drawing.new then return nil end
	local ok, obj = pcall(Drawing.new, class)
	if ok then return obj end
	return nil
end

local function ensureDrawings()
	if not fovCircle then
		fovCircle = newDrawing("Circle")
		if fovCircle then
			fovCircle.Visible = false
			fovCircle.NumSides = 72
			fovCircle.Filled = false
			fovCircle.Color = Aim.FovColor
			fovCircle.Thickness = Aim.FovThickness
		end
	end
	if not targetLine then
		targetLine = newDrawing("Line")
		if targetLine then
			targetLine.Visible = false
			targetLine.Color = Aim.LineColor
			targetLine.Thickness = Aim.LineThickness
			targetLine.From = Vector2.new(0, 0)
			targetLine.To = Vector2.new(0, 0)
		end
	end
	if not targetDot then
		-- Drawing has no "Dot" here — filled tiny circle instead
		targetDot = newDrawing("Circle")
		if targetDot then
			targetDot.Visible = false
			targetDot.Color = Aim.DotColor
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

	-- FOV circle = real cone projected roughly to screen radius
	if fovCircle then
		local show = Aim.ShowFov and Aim.Enabled and Aim.SilentAim
		fovCircle.Visible = show
		if show then
			fovCircle.Position = center
			-- map cone half-angle to pixel radius via FOV of camera
			local camFov = math.rad(math.max(Camera.FieldOfView, 1))
			local half = math.rad(math.clamp(Aim.FOV, 1, 360) / 2)
			-- radius in px along horizontal axis
			fovCircle.Radius = math.clamp((math.tan(half) / math.tan(camFov / 2)) * (vp.X / 2), 10, vp.X)
			fovCircle.Color = Aim.FovColor
			fovCircle.Thickness = Aim.FovThickness
		end
	end

	-- blue line crosshair -> target + dot on target
	local bone = Aim.Target and getBone(Aim.Target.Character)
	local showLine = Aim.ShowTargetLine and Aim.Enabled and bone ~= nil
	if targetLine then
		targetLine.Visible = showLine and true or false
		if targetLine.Visible then
			local sp, onScreen = Camera:WorldToViewportPoint(bone.Position)
			targetLine.From = center
			targetLine.To = Vector2.new(sp.X, sp.Y)
			targetLine.Color = Aim.LineColor
			targetLine.Thickness = Aim.LineThickness
			targetLine.Visible = onScreen
		end
	end
	if targetDot then
		targetDot.Visible = showLine
		if targetDot.Visible then
			local sp, onScreen = Camera:WorldToViewportPoint(bone.Position)
			targetDot.Position = Vector2.new(sp.X, sp.Y)
			targetDot.Color = Aim.DotColor
			targetDot.Visible = onScreen
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

local SIDE_BUTTON_NAMES = {
	MouseButton4 = true,
	MouseButton5 = true,
	MouseBackButton = true,
	MouseForwardButton = true,
	MouseX1 = true,
	MouseX2 = true,
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
		local bound = tostring(k or "")
		if bound:find("Mouse") then
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

-- Silent aim: Ro-Ghoul ClientControl MH() reads Mouse.Hit / Mouse.Target
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
			-- refresh target so we always lock the current best
			local target = Aim.Target
			local bone = target and getBone(target.Character)
			if not bone or not Camera then
				return nil, false
			end

			-- identify mouse loosely (Instance or Mouse userdata)
			local isMouse = false
			local okMouse, cn = pcall(function()
				return typeof(self) == "Instance" and self.ClassName
			end)
			if okMouse and cn == "Mouse" then
				isMouse = true
			elseif not okMouse then
				-- userdata Mouse: name contains Mouse
				local okName = pcall(function() return tostring(self) end)
				if okName and tostring(self):lower():find("mouse") then
					isMouse = true
				end
			end
			if not isMouse then
				return nil, false
			end

			if key == "Hit" then
				-- position ON the bone, looking at camera (matches what MH expects as a CFrame)
				return CFrame.lookAt(bone.Position, Camera.CFrame.Position), true
			elseif key == "Target" then
				return bone, true
			else
				local origin = Camera.CFrame.Position
				local dir = bone.Position - origin
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
		if Aim.SilentAim and Aim.Target then
			pcall(Aim.FaceTarget, Aim.Target)
		end
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
end)

local mt = getrawmetatable and getrawmetatable(game)
if mt and hookmetamethod then
	installMouseHook()
else
	pcall(installMouseHook)
end

return Aim
