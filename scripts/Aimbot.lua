--// Ro-Ghoul aim: silent (Mouse.Hit) + camera look
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
	FOV = 180,
	Smoothness = 0.35,
	Bone = "Head", -- Head | HumanoidRootPart
	Target = nil,

	-- FOV circle (aim indicator)
	ShowFov = true,
	FovColor = Color3.fromRGB(255, 80, 80),
	FovThickness = 1.5,

	-- Camera FOV changer (separate from aim FOV)
	UseCameraFov = false,
	CameraFov = 70,

	-- Aim keybind (mouse side buttons: MouseBackButton / M4 names)
	AimKey = Enum.KeyCode.MouseBackButton,
	AimKeyMode = "Toggle", -- Toggle | Hold
	AimKeyActive = false,
	UseBuiltinAimKey = true, -- hub sets false when using Deadcell keybind instead
}

local function getMouse()
	return LocalPlayer:GetMouse()
end

local function isAlive(plr)
	local char = plr and plr.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
	return hum ~= nil and hrp ~= nil and hum.Health > 0
end

local function getBone(char)
	if not char then return nil end
	local part = char:FindFirstChild(Aim.Bone) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	return part
end

local function sameTeam(plr)
	if LocalPlayer.Team and plr.Team then
		return LocalPlayer.Team == plr.Team
	end
	-- Ro-Ghoul: Customization Team value when present
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

local function screenCenterDist(part)
	local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
	if not onScreen then return math.huge, false end
	local vp = Camera.ViewportSize
	local dx = pos.X - vp.X / 2
	local dy = pos.Y - vp.Y / 2
	return math.sqrt(dx * dx + dy * dy), true
end

function Aim.GetTarget()
	if not Aim.Enabled then return nil end
	local best, bestDist = nil, math.huge
	local fovScale = (Camera.ViewportSize.X / 2) * (math.clamp(Aim.FOV, 1, 360) / 180)

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and isAlive(plr) then
			if not (Aim.TeamCheck and sameTeam(plr)) then
				local bone = getBone(plr.Character)
				if bone then
					local dist, onScreen = screenCenterDist(bone)
					if onScreen and dist <= fovScale then
						if canSee(Camera.CFrame.Position, bone) then
							if dist < bestDist then
								bestDist = dist
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

-- Face local character toward target (helps melee in Ro-Ghoul)
function Aim.FaceTarget(target)
	if not target then return end
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local bone = getBone(target.Character)
	if hrp and bone then
		local look = (Vector3.new(bone.Position.X, hrp.Position.Y, bone.Position.Z) - hrp.Position)
		if look.Magnitude > 0.05 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + look.Unit)
		end
	end
end

-- Camera smooth look
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

-- Aim FOV circle (center screen)
local fovCircle
local function ensureFovCircle()
	if fovCircle then return fovCircle end
	if not Drawing or not Drawing.new then return nil end
	local ok, circle = pcall(Drawing.new, "Circle")
	if not ok or not circle then return nil end
	circle.Visible = false
	circle.Color = Aim.FovColor
	circle.Thickness = Aim.FovThickness
	circle.NumSides = 64
	circle.Filled = false
	circle.Radius = 100
	circle.Position = Vector2.new(0, 0)
	fovCircle = circle
	return circle
end

local function updateFovCircle()
	local circle = ensureFovCircle()
	if not circle then return end
	local show = Aim.ShowFov and Aim.Enabled
	circle.Visible = show and Aim.SilentAim
	if not circle.Visible then return end
	local vp = Camera.ViewportSize
	circle.Position = Vector2.new(vp.X / 2, vp.Y / 2)
	-- Aim.FOV is degrees of screen half-width (same scale GetTarget uses)
	circle.Radius = (vp.X / 2) * (math.clamp(Aim.FOV, 1, 360) / 180)
	circle.Color = Aim.FovColor
	circle.Thickness = Aim.FovThickness
end

local defaultCameraFov = nil
local function applyCameraFov()
	if not Camera then return end
	if defaultCameraFov == nil then
		defaultCameraFov = Camera.FieldOfView
	end
	if Aim.UseCameraFov then
		Camera.FieldOfView = math.clamp(Aim.CameraFov, 30, 120)
	elseif Camera.FieldOfView ~= defaultCameraFov then
		-- restore only if we previously changed it
		if math.abs(Camera.FieldOfView - math.clamp(Aim.CameraFov, 30, 120)) < 0.01 then
			Camera.FieldOfView = defaultCameraFov
		end
	end
end

function Aim.SetAimEnabled(on)
	Aim.Enabled = on and true or false
	Aim.AimKeyActive = Aim.Enabled
	if not Aim.Enabled then
		Aim.Target = nil
		if fovCircle then fovCircle.Visible = false end
		if Aim.UseCameraFov and Camera then
			-- leave camera fov as-is until user disables UseCameraFov
		end
	end
end

function Aim.ToggleAim()
	Aim.SetAimEnabled(not Aim.Enabled)
	return Aim.Enabled
end

-- Accepts Enum.KeyCode.* or Enum.UserInputType.* (side buttons = MouseBackButton / M4 names)
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
	-- side buttons may arrive under names the enum table doesn't list
	local ut = tostring(input.UserInputType):gsub("Enum%.UserInputType%.", "")
	local kc = tostring(input.KeyCode):gsub("Enum%.KeyCode%.", "")
	if SIDE_BUTTON_NAMES[ut] or SIDE_BUTTON_NAMES[kc] then
		-- only treat as aim key if user bound a side/mouse key (or default back button)
		local bound = tostring(k or "")
		if bound:find("Mouse") or bound:find("MouseButton") then
			return true
		end
		-- if bound key is MouseBackButton, match any side-button name too
		if bound:find("MouseBack") and (SIDE_BUTTON_NAMES[ut] or SIDE_BUTTON_NAMES[kc]) then
			return true
		end
	end
	return false
end

local UIS = UserInputService
UIS.InputBegan:Connect(function(input, gameProcessed)
	if not Aim.UseBuiltinAimKey then return end
	if gameProcessed then return end
	if not isAimKeyInput(input) then return end
	if Aim.AimKeyMode == "Hold" then
		Aim.SetAimEnabled(true)
	else
		Aim.ToggleAim()
	end
end)

UIS.InputEnded:Connect(function(input)
	if not Aim.UseBuiltinAimKey then return end
	if Aim.AimKeyMode ~= "Hold" then return end
	if isAimKeyInput(input) then
		Aim.SetAimEnabled(false)
	end
end)

-- Silent aim: game combat reads Mouse.Hit / Mouse.Target (ClientControl MH)
local hooksInstalled = false
local oldIndex
local inHook = false

local function installMouseHook()
	if hooksInstalled then return end
	if not hookmetamethod then return end

	local wrap = (type(newcclosure) == "function") and newcclosure or function(f) return f end
	local callerIsCheck = function()
		if type(checkcaller) == "function" then
			return checkcaller()
		end
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
			if not (typeof(self) == "Instance" and self.ClassName == "Mouse") then
				return nil, false
			end
			local target = Aim.Target
			local bone = target and getBone(target.Character)
			if not bone or not Camera then
				return nil, false
			end
			if key == "Hit" then
				return CFrame.lookAt(bone.Position, Camera.CFrame.Position), true
			elseif key == "Target" then
				return bone, true
			end
			local origin = Camera.CFrame.Position
			local dir = bone.Position - origin
			if dir.Magnitude < 1e-4 then
				dir = Camera.CFrame.LookVector
			end
			return Ray.new(origin, dir.Unit * 4096), true
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
		if Aim.CameraAim and Aim.Target then
			local okCam, errCam = pcall(updateCamera, dt)
			if not okCam then
				warn("[Aimbot] camera aim failed:", errCam)
			end
		end
	end
	pcall(updateFovCircle)
end)

-- Re-resolve camera after respawn/teleport
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1)
	Camera = Workspace.CurrentCamera
end)

-- Ensure hook as soon as silent aim is requested
local mt = getrawmetatable and getrawmetatable(game)
if mt and hookmetamethod then
	installMouseHook()
else
	-- still try standard executor API
	pcall(installMouseHook)
end

return Aim
