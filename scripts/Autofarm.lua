--// Ro-Ghoul Autofarm
-- Combat: Character.Remotes.KeyEvent (same path as ClientControl)
-- Movement: Humanoid:MoveTo

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local KEY_AUTH = "操你💦💔🍑👌💦操你💦💔🍑👌💦💔🍑👌💦💔🍑👌💔🍑👌💦💔🍑👌"

local Farm = {
	Enabled = false,
	AutoAttack = true,
	AutoCollect = false,
	AutoRespawn = false,
	FarmDelay = 2.0,

	-- targets
	Group = "Ghoul",
	PreferNearest = true,
	PreferLowestHP = false,
	IgnorePlayers = true,
	MaxDistance = 800,
	AttackRange = 8,

	-- loadout
	KaguneStage = "None",
	AutoEquipKagune = false,
	Quinque = "None",
	AutoEquipQuinque = false,
	RCForm = "Default",

	-- extras
	AutoKaguneToggle = false,
	AutoQuinqueSwap = false,
	AutoHeartPickup = false,
	AutoDissect = false,
	FarmMode = "NPC Grind",

	-- runtime
	CurrentTarget = nil,
	LastAttack = 0,
	LastSpecial = 0,
	LastCollect = 0,
	Stats = { kills = 0, attacks = 0, collects = 0 },
	_thread = nil,
}

local GROUP_MAP = {
	Human = "HumanSpawns",
	Ghoul = "GhoulSpawns",
	CCG = "CCGSpawns",
	Aggro = "AggroSpawns",
	Boss = "BossSpawns",
}

local function pf()
	return LocalPlayer:FindFirstChild("PlayerFolder")
end

local function character()
	local c = LocalPlayer.Character
	if not c then return nil end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) or hum.Health <= 0 then return nil end
	return c, hrp, hum
end

local function readyCD(name)
	local folder = pf()
	if not folder then return true end
	local v = folder:FindFirstChild(name)
	if not v then return true end
	return tostring(v.Value) == "Ready"
end

local function canAct()
	local folder = pf()
	if not folder then return false end
	local v = folder:FindFirstChild("CanAct")
	return not v or v.Value == true
end

local function getKeyEvent()
	local c = LocalPlayer.Character
	local rem = c and c:FindFirstChild("Remotes")
	return rem and rem:FindFirstChild("KeyEvent")
end

local function MHAt(pos)
	-- same shape ClientControl sends: CFrame at hit looking at camera
	local cam = Workspace.CurrentCamera
	local origin = cam and cam.CFrame.Position or pos
	return CFrame.lookAt(pos, origin)
end

local function fireKey(keyName, state, hitCFrame, extra)
	local remote = getKeyEvent()
	if not remote then return end
	local cam = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame or CFrame.new()
	local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local pos = hrp and hrp.Position or Vector3.zero
	local hit = hitCFrame or MHAt(pos + Vector3.new(0, 0, -3))
	pcall(function()
		remote:FireServer(KEY_AUTH, keyName, state, hit, nil, cam, pos, extra)
	end)
end

local function attackOnce()
	if not readyCD("ClickCD") or not canAct() then return false end
	local target = Farm.CurrentTarget
	local bone = target and (
		target:FindFirstChild("Head")
		or target:FindFirstChild("HumanoidRootPart")
		or target.PrimaryPart
	)
	if not bone then return false end

	-- face target
	local _, hrp = character()
	if hrp then
		local flat = Vector3.new(bone.Position.X, hrp.Position.Y, bone.Position.Z)
		if (flat - hrp.Position).Magnitude > 0.05 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, flat)
		end
	end

	local hit = MHAt(bone.Position)
	fireKey("Mouse1", "Down", hit)
	task.wait(0.05)
	fireKey("Mouse1", "Up", hit)
	Farm.LastAttack = tick()
	Farm.Stats.attacks += 1

	if Farm.AutoAttack then
		-- specials when ready
		local special = "E"
		if readyCD("Special1CD") and tick() - Farm.LastSpecial > 1.5 then
			special = "E"
		elseif readyCD("Special2CD") and tick() - Farm.LastSpecial > 3 then
			special = "R"
		elseif readyCD("Special3CD") and tick() - Farm.LastSpecial > 4 then
			special = "F"
		else
			special = nil
		end
		if special then
			fireKey(special, "Down", hit)
			task.wait(0.05)
			fireKey(special, "Up", hit)
			Farm.LastSpecial = tick()
		end
	end
	return true
end

local function classifyNPC(model)
	local p = model.Parent
	for _ = 1, 4 do
		if not p then break end
		local n = p.Name
		if n:find("HumanSpawns", 1, true) then return "Human" end
		if n:find("AggroSpawns", 1, true) then return "Aggro" end
		if n:find("CCGSpawns", 1, true) then return "CCG" end
		if n:find("GhoulSpawns", 1, true) then return "Ghoul" end
		if n:find("BossSpawns", 1, true) then return "Boss" end
		p = p.Parent
	end
	if model.Name == "Gyakusatsu" then return "Gyakusatsu" end
	return "Named"
end

local playerChars = {}
local function refreshPlayerChars()
	playerChars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then playerChars[p.Character] = true end
	end
end
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function() refreshPlayerChars() end)
end)
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	refreshPlayerChars()
	Farm.CurrentTarget = nil
end)

local function findTarget()
	local _, hrp = character()
	if not hrp then return nil end
	local best, bestScore = nil, math.huge
	local myPos = hrp.Position

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and not playerChars[d] then
			local nm = d.Name
			if not nm:find("Corpse", 1, true) and not nm:find("Dead", 1, true) then
				local hum = d:FindFirstChildOfClass("Humanoid")
				local part = d:FindFirstChild("HumanoidRootPart") or d:FindFirstChild("Head")
				if hum and part and hum.Health > 0 and hum.MaxHealth < 1e6 then
					local dist = (part.Position - myPos).Magnitude
					if dist <= Farm.MaxDistance then
						local group = classifyNPC(d)
						local match = false
						if Farm.Group == "Any" then
							match = true
						elseif Farm.Group == "Gyakusatsu" then
							match = (group == "Gyakusatsu" or nm == "Gyakusatsu")
						elseif Farm.Group == group then
							match = true
						end
						if Farm.FarmMode == "Boss Only" then
							match = (group == "Boss" or group == "Gyakusatsu")
						end
						if match then
							local score = dist
							if Farm.PreferLowestHP then
								score = hum.Health * 0.01 + dist
							end
							if Farm.PreferNearest then
								score = dist
							end
							if score < bestScore then
								bestScore = score
								best = d
							end
						end
					end
				end
			end
		end
	end
	return best
end

local function moveTo(pos)
	local _, _, hum = character()
	if not hum then return end
	pcall(function()
		hum:MoveTo(pos)
	end)
end

local function collectNearby()
	local _, hrp = character()
	if not hrp then return end
	local myPos = hrp.Position

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			local parent = d.Parent
			local part = parent and (parent:IsA("BasePart") and parent or parent:FindFirstChildWhichIsA("BasePart", true))
			if part and (part.Position - myPos).Magnitude < 25 then
				moveTo(part.Position)
				pcall(function()
					if d:IsA("ProximityPrompt") then
						d:InputHoldBegin()
						task.wait(0.2)
						d:InputHoldEnd()
					else
						d:MouseClick()
					end
				end)
				Farm.Stats.collects += 1
				return true
			end
		end
	end

	-- ClickPart interact (ClientControl walks to ClickPart)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "ClickPart" then
			if (d.Position - myPos).Magnitude < 40 then
				moveTo(d.Position)
				if (d.Position - myPos).Magnitude < 8 then
					fireKey("Mouse1", "Down", MHAt(d.Position))
					task.wait(0.05)
					fireKey("Mouse1", "Up", MHAt(d.Position))
					Farm.Stats.collects += 1
					return true
				end
				return true
			end
		end
	end
	return false
end

local function tryDissect()
	local remotes = game:GetService("ReplicatedStorage").Remotes
	local gya = remotes:FindFirstChild("GyaSac")
	local dissect = gya and gya:FindFirstChild("Dissect")
	local heart = remotes:FindFirstChild("HeartExchange")
	local station = Workspace:FindFirstChild("GyaSacTable")
	local ind = station and station:FindFirstChild("GyaSacIndicator")
	local pos = ind and ind:IsA("BasePart") and ind.Position
	local _, hrp = character()
	if pos and hrp and (pos - hrp.Position).Magnitude > 15 then
		moveTo(pos)
		return true
	end
	if dissect then
		pcall(function()
			dissect:InvokeServer()
		end)
	end
	if heart then
		pcall(function()
			heart:InvokeServer()
		end)
	end
	return false
end

local function applyLoadout()
	local folder = pf()
	if not folder then return end

	-- Quinque: prefer matching WepSlots then fire 1/2
	if Farm.Quinque ~= "None" and Farm.AutoEquipQuinque then
		local slots = folder:FindFirstChild("WepSlots")
		if slots then
			local s1 = slots:FindFirstChild("WepSlot1")
			local s2 = slots:FindFirstChild("WepSlot2")
			local v1 = s1 and s1.Value
			local v2 = s2 and s2.Value
			local q = string.lower(Farm.Quinque)
			if v1 and string.find(string.lower(v1), q, 1, true) then
				fireKey("1", "Down")
				task.wait(0.05)
				fireKey("1", "Up")
			elseif v2 and string.find(string.lower(v2), q, 1, true) then
				fireKey("2", "Down")
				task.wait(0.05)
				fireKey("2", "Up")
			end
		end
	end

	-- Kagune: toggle with Q (ghoul) / AutoKaguneToggle
	if Farm.AutoEquipKagune or Farm.AutoKaguneToggle then
		if Farm.AutoKaguneToggle or Farm.KaguneStage ~= "None" then
			fireKey("Q", "Down")
			task.wait(0.05)
			fireKey("Q", "Up")
		end
	end
end

local function stop()
	Farm.Enabled = false
	Farm.CurrentTarget = nil
	if Farm._task then
		task.cancel(Farm._task)
		Farm._task = nil
	end
end

local function loop()
	while Farm.Enabled do
		local delay = math.clamp(Farm.FarmDelay, 0.05, 10)
		if not canAct() or not character() then
			if Farm.AutoRespawn then
				-- wait for respawn; ClientControl handles rejoin
				task.wait(1)
			else
				task.wait(0.5)
			end
			task.wait(delay)
			continue
		end

		-- loadout apply (cheap)
		if Farm.AutoEquipQuinque or Farm.AutoEquipKagune then
			pcall(applyLoadout)
		end

		if Farm.AutoHeartPickup or Farm.AutoDissect or Farm.FarmMode == "Hearts / Events" then
			if Farm.AutoDissect then
				pcall(tryDissect)
			end
			if Farm.AutoHeartPickup and Farm.AutoCollect then
				pcall(collectNearby)
			end
		end

		if Farm.AutoCollect or Farm.FarmMode == "Hearts / Events" then
			if tick() - Farm.LastCollect > 1 then
				if pcall(collectNearby) then
					Farm.LastCollect = tick()
				end
			end
		end

		if Farm.AutoAttack or Farm.FarmMode ~= "Hearts / Events" then
			local target = findTarget()
			Farm.CurrentTarget = target
			if target then
				local part = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
				local _, hrp = character()
				if part and hrp then
					local dist = (part.Position - hrp.Position).Magnitude
					if dist > Farm.AttackRange then
						moveTo(part.Position)
					elseif dist <= Farm.AttackRange then
						if tick() - Farm.LastAttack >= math.clamp(Farm.FarmDelay * 0.35, 0.15, 2) then
							pcall(attackOnce)
						end
					end
				end
			end
		end

		task.wait(0.1)
	end
end

function Farm.Start()
	if Farm.Enabled then return end
	Farm.Enabled = true
	refreshPlayerChars()
	Farm._task = task.spawn(loop)
	print("[Autofarm] started mode=" .. tostring(Farm.FarmMode) .. " group=" .. tostring(Farm.Group))
end

function Farm.Stop()
	stop()
	print("[Autofarm] stopped")
end

function Farm.Toggle()
	if Farm.Enabled then
		Farm.Stop()
	else
		Farm.Start()
	end
	return Farm.Enabled
end

function Farm.ApplyLoadoutNow()
	pcall(applyLoadout)
end

function Farm.Status()
	return string.format(
		"on=%s target=%s attacks=%d collects=%d",
		tostring(Farm.Enabled),
		Farm.CurrentTarget and Farm.CurrentTarget.Name or "-",
		Farm.Stats.attacks,
		Farm.Stats.collects
	)
end

return Farm
