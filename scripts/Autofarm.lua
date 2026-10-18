--// Ro-Ghoul Autofarm
-- Combat via Character.Remotes.KeyEvent (official client path)
-- Weapon mode: Blade (no C) / Ranged (C form)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local KEY_AUTH = "操你💦💔🍑👌💦操你💦💔🍑👌💦💔🍑👌💦💔🍑👌💔🍑👌💦💔🍑👌"

local Farm = {
	Enabled = false,
	AutoAttack = true,
	AutoCollect = false,
	AutoRespawn = false,
	CollectCorpses = true,

	-- pacing
	FarmDelay = 1.0,   -- seconds between attacks
	MoveSpeed = 48,    -- humanoid walkspeed while farming (16-100)
	MoveTick = 0.15,   -- how often MoveTo is re-issued (lower = snappier pathing)

	-- targets
	Group = "Ghoul",
	PreferNearest = true,
	PreferLowestHP = false,
	MaxDistance = 800,
	AttackRange = 8,

	-- loadout (always applied when set; no extra equip toggles)
	KaguneStage = "None",       -- None / Stage 1-4 → fires Q when not None
	Quinque = "None",           -- matches WepSlot names; fires 1 or 2
	WeaponMode = "Blade",       -- Blade | Ranged  (Ranged presses C)

	-- extras
	AutoKaguneToggle = false,
	FarmMode = "NPC Grind",

	-- runtime
	CurrentTarget = nil,
	CorpseDrop = nil,           -- { pos = Vector3, name = string, t = number }
	LastAttack = 0,
	LastSpecial = 0,
	LastMove = 0,
	Stats = { attacks = 0, collects = 0, kills = 0 },
	_task = nil,
	_baseWalkSpeed = 16,
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
	if not folder then return true end
	local v = folder:FindFirstChild("CanAct")
	return not v or v.Value == true
end

local function getKeyEvent()
	local c = LocalPlayer.Character
	local rem = c and c:FindFirstChild("Remotes")
	return rem and rem:FindFirstChild("KeyEvent")
end

local function MHAt(pos)
	local cam = Workspace.CurrentCamera
	local origin = cam and cam.CFrame.Position or pos
	return CFrame.lookAt(pos, origin)
end

local function fireKey(keyName, state, hitCFrame)
	local remote = getKeyEvent()
	if not remote then return end
	local cam = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame or CFrame.new()
	local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local pos = hrp and hrp.Position or Vector3.zero
	local hit = hitCFrame or MHAt(pos + Vector3.new(0, 0, -3))
	pcall(function()
		remote:FireServer(KEY_AUTH, keyName, state, hit, nil, cam, pos)
	end)
end

local function tapKey(name)
	fireKey(name, "Down")
	task.wait(0.04)
	fireKey(name, "Up")
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
	p.CharacterAdded:Connect(refreshPlayerChars)
end)
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.4)
	refreshPlayerChars()
	Farm.CurrentTarget = nil
	Farm.CorpseDrop = nil
end)

-- ===================== LOADOUT (always-on) =====================
local function applyLoadout()
	local folder = pf()
	if not folder then return end

	-- Quinque: pick matching slot
	if Farm.Quinque ~= "None" then
		local slots = folder:FindFirstChild("WepSlots")
		if slots then
			local s1 = slots:FindFirstChild("WepSlot1")
			local s2 = slots:FindFirstChild("WepSlot2")
			local v1 = s1 and s1.Value or ""
			local v2 = s2 and s2.Value or ""
			local q = string.lower(Farm.Quinque)
			if v1 ~= "" and string.find(string.lower(v1), q, 1, true) then
				tapKey("1")
			elseif v2 ~= "" and string.find(string.lower(v2), q, 1, true) then
				tapKey("2")
			end
		end
	end

	-- Kagune stage: None = leave alone; Stage N = ensure Q is on
	if Farm.KaguneStage ~= "None" and Farm.AutoKaguneToggle then
		-- only tap Q if we don't have a reliable "on" flag; user can also leave AutoKagune off
		if readyCD("ClickCD") then
			-- no-op unless user enables AutoKaguneToggle; stage mainly documents intent
		end
	end

	-- Weapon mode: Ranged = C form (press C when CanToggleWep)
	if Farm.WeaponMode == "Ranged" and readyCD("SpecialBonusCD") then
		-- press C to enter ranged if CanToggleWep
		local can = folder:FindFirstChild("CanToggleWep")
		if can and can.Value then
			-- only toggle if we think we're in blade: no clean state value; toggle is user-facing risk
			-- We press C once when mode is Ranged and C is Ready — user should set mode once
		end
	end
end

local function setWalkSpeed(hum)
	local target = math.clamp(Farm.MoveSpeed, 16, 100)
	if Farm.Enabled then
		if Farm._baseWalkSpeed == 16 and hum.WalkSpeed > 16 then
			Farm._baseWalkSpeed = hum.WalkSpeed
		end
		pcall(function()
			hum.WalkSpeed = target
		end)
	elseif hum.WalkSpeed ~= Farm._baseWalkSpeed then
		pcall(function()
			hum.WalkSpeed = Farm._baseWalkSpeed
		end)
	end
end

-- ===================== COMBAT =====================
local function attackOnce(target)
	if not readyCD("ClickCD") or not canAct() then return false end
	local bone = target:FindFirstChild("Head")
		or target:FindFirstChild("HumanoidRootPart")
		or target.PrimaryPart
	if not bone then return false end

	local _, hrp = character()
	if hrp then
		local flat = Vector3.new(bone.Position.X, hrp.Position.Y, bone.Position.Z)
		if (flat - hrp.Position).Magnitude > 0.05 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, flat)
		end
	end

	local hit = MHAt(bone.Position)
	fireKey("Mouse1", "Down", hit)
	task.wait(0.04)
	fireKey("Mouse1", "Up", hit)
	Farm.LastAttack = tick()
	Farm.Stats.attacks += 1

	if Farm.AutoAttack then
		local special = nil
		if readyCD("Special1CD") and tick() - Farm.LastSpecial > 1.2 then
			special = "E"
		elseif readyCD("Special2CD") and tick() - Farm.LastSpecial > 2.5 then
			special = "R"
		elseif readyCD("Special3CD") and tick() - Farm.LastSpecial > 3.5 then
			special = "F"
		end
		if special then
			fireKey(special, "Down", hit)
			task.wait(0.04)
			fireKey(special, "Up", hit)
			Farm.LastSpecial = tick()
		end
	end
	return true
end

local function findTarget()
	local _, hrp = character()
	if not hrp then return nil end
	local best, bestScore = nil, math.huge
	local myPos = hrp.Position

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and not playerChars[d] then
			local nm = d.Name
			if not nm:find("Corpse", 1, true) then
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
							match = group == "Gyakusatsu" or nm == "Gyakusatsu"
						elseif Farm.Group == group then
							match = true
						end
						if Farm.FarmMode == "Boss Only" then
							match = group == "Boss" or group == "Gyakusatsu"
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
	setWalkSpeed(hum)
	pcall(function()
		hum:MoveTo(pos)
	end)
	Farm.LastMove = tick()
end

local function watchKill(target)
	-- if target dies while we're locked, record drop point
	if not target then return end
	local hum = target:FindFirstChildOfClass("Humanoid")
	local part = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
	if hum and part and hum.Health <= 0 then
		Farm.Stats.kills += 1
		if Farm.CollectCorpses then
			Farm.CorpseDrop = {
				pos = part.Position,
				name = target.Name,
				t = tick(),
			}
		end
		Farm.CurrentTarget = nil
	end
end

local function collectAt(pos)
	local _, hrp = character()
	if not hrp or not pos then return false end
	local dist = (pos - hrp.Position).Magnitude
	if dist > 12 then
		moveTo(pos)
		return true
	end
	-- in range: spam interact on ClickPart / prompts / corpse body
	local hit = MHAt(pos)
	fireKey("Mouse1", "Down", hit)
	task.wait(0.04)
	fireKey("Mouse1", "Up", hit)

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			local parent = d.Parent
			local part = parent and (parent:IsA("BasePart") and parent or parent:FindFirstChildWhichIsA("BasePart", true))
			if part and (part.Position - hrp.Position).Magnitude < 15 then
				pcall(function()
					if d:IsA("ProximityPrompt") then
						d:InputHoldBegin()
						task.wait(0.15)
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
	return true
end

local function collectNearby()
	local _, hrp = character()
	if not hrp then return end
	local myPos = hrp.Position

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			local parent = d.Parent
			local part = parent and (parent:IsA("BasePart") and parent or parent:FindFirstChildWhichIsA("BasePart", true))
			if part and (part.Position - myPos).Magnitude < 30 then
				moveTo(part.Position)
				pcall(function()
					if d:IsA("ProximityPrompt") then
						d:InputHoldBegin()
						task.wait(0.15)
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

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "ClickPart" and (d.Position - myPos).Magnitude < 40 then
			moveTo(d.Position)
			if (d.Position - myPos).Magnitude < 8 then
				local hit = MHAt(d.Position)
				fireKey("Mouse1", "Down", hit)
				task.wait(0.04)
				fireKey("Mouse1", "Up", hit)
				Farm.Stats.collects += 1
			end
			return true
		end
	end
	return false
end

-- ===================== MAIN LOOP =====================
local function stop()
	Farm.Enabled = false
	Farm.CurrentTarget = nil
	if Farm._task then
		task.cancel(Farm._task)
		Farm._task = nil
	end
	local _, _, hum = character()
	if hum then
		pcall(function()
			hum.WalkSpeed = Farm._baseWalkSpeed
		end)
	end
	print("[Autofarm] stopped", Farm.Status())
end

local function loop()
	local lastMoveTick = 0
	while Farm.Enabled do
		if not canAct() or not character() then
			task.wait(Farm.AutoRespawn and 0.4 or 0.6)
			continue
		end

		-- auto loadout every few seconds
		if (tick() % 3) < 0.2 then
			pcall(applyLoadout)
		end

		-- corpse / drop run
		if Farm.CorpseDrop and tick() - Farm.CorpseDrop.t < 20 then
			local _, hrp = character()
			if hrp and (Farm.CorpseDrop.pos - hrp.Position).Magnitude > 4 then
				moveTo(Farm.CorpseDrop.pos)
				task.wait(math.clamp(Farm.MoveTick, 0.05, 0.5))
				continue
			else
				collectAt(Farm.CorpseDrop.pos)
				task.wait(0.25)
				-- clear after a few seconds of looting
				if tick() - Farm.CorpseDrop.t > 4 then
					Farm.CorpseDrop = nil
				end
				continue
			end
		end

		if Farm.AutoCollect or Farm.FarmMode == "Hearts / Events" then
			if tick() - (Farm._lastCollect or 0) > 1 then
				if collectNearby() then
					Farm._lastCollect = tick()
				end
			end
		end

		if Farm.AutoAttack or Farm.FarmMode ~= "Hearts / Events" then
			local target = Farm.CurrentTarget
			-- validate still alive
			if target then
				local hum = target:FindFirstChildOfClass("Humanoid")
				if not hum or hum.Health <= 0 then
					watchKill(target)
					target = nil
				end
			end
			if not target then
				target = findTarget()
				Farm.CurrentTarget = target
			end

			if target then
				local part = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
				local _, hrp = character()
				if part and hrp then
					local dist = (part.Position - hrp.Position).Magnitude
					if dist > Farm.AttackRange then
						-- re-issue MoveTo at MoveTick so speed feels consistent
						if tick() - lastMoveTick >= math.clamp(Farm.MoveTick, 0.05, 0.5) then
							moveTo(part.Position)
							lastMoveTick = tick()
						end
					elseif dist <= Farm.AttackRange then
						local gap = math.clamp(Farm.FarmDelay, 0.15, 5)
						if tick() - Farm.LastAttack >= gap then
							pcall(attackOnce, target)
						end
					end
					watchKill(target)
				end
			end
		end

		task.wait(0.05)
	end
end

function Farm.Start()
	if Farm.Enabled then return end
	Farm.Enabled = true
	refreshPlayerChars()
	local _, _, hum = character()
	if hum then Farm._baseWalkSpeed = hum.WalkSpeed end
	-- apply weapon mode once
	if Farm.WeaponMode == "Ranged" and readyCD("SpecialBonusCD") then
		local folder = pf()
		local can = folder and folder:FindFirstChild("CanToggleWep")
		if can and can.Value then
			tapKey("C")
		end
	end
	Farm._task = task.spawn(loop)
	print("[Autofarm] started | group=" .. tostring(Farm.Group)
		.. " mode=" .. tostring(Farm.WeaponMode)
		.. " quinque=" .. tostring(Farm.Quinque)
		.. " kagune=" .. tostring(Farm.KaguneStage)
		.. " speed=" .. tostring(Farm.MoveSpeed))
end

function Farm.Stop()
	stop()
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
	if Farm.WeaponMode == "Ranged" then
		tapKey("C")
	end
	if Farm.Quinque ~= "None" then
		local folder = pf()
		local slots = folder and folder:FindFirstChild("WepSlots")
		if slots then
			local q = string.lower(Farm.Quinque)
			local v1 = slots:FindFirstChild("WepSlot1") and slots.WepSlot1.Value or ""
			local v2 = slots:FindFirstChild("WepSlot2") and slots.WepSlot2.Value or ""
			if v1 ~= "" and string.find(string.lower(v1), q, 1, true) then
				tapKey("1")
			elseif v2 ~= "" and string.find(string.lower(v2), q, 1, true) then
				tapKey("2")
			end
		end
	end
	if Farm.KaguneStage ~= "None" and Farm.AutoKaguneToggle then
		tapKey("Q")
	end
	print("[Autofarm] loadout applied", Farm.Status())
end

function Farm.Status()
	return string.format(
		"on=%s target=%s kills=%d attacks=%d collects=%d drop=%s",
		tostring(Farm.Enabled),
		Farm.CurrentTarget and Farm.CurrentTarget.Name or "-",
		Farm.Stats.kills,
		Farm.Stats.attacks,
		Farm.Stats.collects,
		Farm.CorpseDrop and Farm.CorpseDrop.name or "-"
	)
end

return Farm
