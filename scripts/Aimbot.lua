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

-- Silent aim: game combat reads Mouse.Hit / Mouse.Target (ClientControl MH)
local hooksInstalled = false
local oldIndex

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
		if not callerIsCheck() and Aim.Enabled and Aim.SilentAim then
			local target = Aim.Target or Aim.GetTarget()
			local isMouse = (self == getMouse()) or (typeof(self) == "Instance" and self.ClassName == "Mouse")
			if target and isMouse then
				local bone = getBone(target.Character)
				if bone then
					if key == "Hit" then
						return CFrame.lookAt(bone.Position, Camera.CFrame.Position)
					elseif key == "Target" then
						return bone
					elseif key == "UnitRay" then
						local origin = Camera.CFrame.Position
						local dir = (bone.Position - origin).Unit * 4096
						return Ray.new(origin, dir)
					elseif key == "TargetFilter" then
						return oldIndex(self, key)
					end
				end
			end
		end
		return oldIndex(self, key)
	end))
	hooksInstalled = true
end

RunService.RenderStepped:Connect(function(dt)
	if Aim.Enabled then
		Aim.GetTarget()
		if Aim.CameraAim and Aim.Target then
			updateCamera(dt)
		end
		-- optional: keep facing for silent melee
		if Aim.SilentAim and Aim.Target and not Aim.CameraAim then
			-- FaceTarget left manual to avoid fighting movement; menu can enable later
		end
	end
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
