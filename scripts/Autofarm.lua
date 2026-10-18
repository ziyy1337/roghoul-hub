--// Ro-Ghoul Autofarm
-- Based on z4gs working patterns: tween TP, stage keys One/Two, Mouse.Hit silent aim.
-- Camera is never modified. Mask=M, Arata open=0.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local GetGc = getgc
local GetConstants = getconstants

local LocalPlayer = Players.LocalPlayer

-- fallback auth; live key is grabbed from ClientControl constants when possible
local KEY_AUTH = "操你💦💔🍑👌💦操你💦💔🍑👌💦💔🍑👌💦💔🍑👌💔🍑👌💦💔🍑👌"

local Farm = {
	Enabled = false,
	AutoCollect = true,
	CollectCorpses = true,
	Noclip = true,

	TeleportSpeed = 150,  -- studs/sec (z4gs style)
	DistanceFromNpc = 5,  -- standoff (negative in z4gs means in front)
	FarmDelay = 0.05,     -- attack tick

	Group = "Ghoul",
	PreferNearest = true,
	PreferLowestHP = false,

	-- z4gs distances (applied like working.lua)
	DistanceFromNpc = 5,   -- slider 0-8; used as lookVector * (-value)
	DistanceFromBoss = 8,  -- Y offset above boss

	-- boss farms (exact z4gs names + level gates)
	BossFarm = {
		["Gyakusatsu"] = false,
		["Eto Yoshimura"] = false,
		["Koutarou Amon"] = false,
		["Nishiki Nishio"] = false,
	},
	BossLevel = {
		["Gyakusatsu"] = 1250,
		["Eto Yoshimura"] = 1250,
		["Koutarou Amon"] = 750,
		["Nishiki Nishio"] = 250,
	},

	-- skills on bosses only (z4gs): E/R/F/C when CanAct and CD ~= DownTime
	SkillsOnBoss = true,

	Quinque = "IXA", -- unused in UI; Stage drives equip
	Stage = "One",         -- "One".."Six" (KeyEvent stage names)
	WeaponMode = "Auto",   -- Auto | Blade | Ranged (restored from old menu)

	-- Attacks (Mouse1 always active)
	AttackE = false,
	AttackR = false,
	AttackF = false,
	AttackC = false,
	RangeMode = false,       -- forces Ranged; same as WeaponMode=Ranged
	AutoArata = false,
	AutoArataRefill = false,
	AutoMask = false,

	-- Trainer / Reputation (working.lua)
	AutoTrainer = false,
	ReputationFarm = false,
	ReputationCashout = false,

	-- runtime
	CurrentTarget = nil,
	CorpseNpc = nil,
	CorpseName = nil,
	LastAttack = 0,
	LastSpecial = 0,
	LastArata = 0,
	LastMask = 0,
	LastRange = 0,
	LastEquip = 0,
	LastCashout = 0,
	LastRefill = 0,
	_baseWalkSpeed = 48,
	Stats = { attacks = 0, collects = 0, kills = 0 },
	AvailableStages = {},
	RemoteKey = nil,
	TrainersList = nil,
	_task = nil,
	_trainTask = nil,
	_noclipConn = nil,
}

local KEY_NAME_MAP = {
	["1"] = "One", ["2"] = "Two", ["3"] = "Three",
	["4"] = "Four", ["5"] = "Five", ["6"] = "Six",
	One = "One", Two = "Two", Three = "Three",
	Four = "Four", Five = "Five", Six = "Six",
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
	-- working.lua: skills fire when Value ~= "DownTime" (not == "Ready")
	local folder = pf()
	if not folder then return true end
	local v = folder:FindFirstChild(name)
	if not v then return true end
	local val = tostring(v.Value)
	if val == "DownTime" or val == "Down" then
		return false
	end
	local num = tonumber(val)
	if num and num > 0 then
		return false
	end
	return true
end

local function canAct()
	local folder = pf()
	if not folder then return true end
	local v = folder:FindFirstChild("CanAct")
	return not v or v.Value == true
end

local function getKeyEvent()
	local rem = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Remotes")
	return rem and rem:FindFirstChild("KeyEvent")
end

local function MH()
	local m = LocalPlayer:GetMouse()
	return m.Hit
end

local function getAuthKey()
	if Farm.RemoteKey and #Farm.RemoteKey >= 100 then
		return Farm.RemoteKey
	end
	-- exact working.lua key grabber
	pcall(function()
		if not getgc or not getconstants or not getconstant then return end
		for _, v in pairs(getgc(true)) do
			if type(v) == "function" then
				local info = getinfo and getinfo(v)
				local src = info and info.source or (debug and debug.getinfo and debug.getinfo(v, "s").source)
				if src and tostring(src):find(".ClientControl") then
					local constants = getconstants(v)
					for i2, v2 in pairs(constants) do
						if v2 == "KeyEvent" then
							local keyfound = getconstant(v, i2 + 1)
							if type(keyfound) == "string" and #keyfound >= 100 then
								Farm.RemoteKey = keyfound
								return
							end
						end
					end
				end
			end
		end
	end)
	if not Farm.RemoteKey then
		Farm.RemoteKey = KEY_AUTH
	end
	return Farm.RemoteKey
end

local function pressKey(keyName, hit)
	local remote = getKeyEvent()
	if not remote then return end
	local cam = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame or CFrame.new()
	local hitCFrame = hit or MH()
	pcall(function()
		remote:FireServer(getAuthKey(), keyName, "Down", hitCFrame, nil, cam)
	end)
end

-- ===================== stages =====================
function Farm.FetchStages()
	local stages = {}
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local hud = gui and gui:FindFirstChild("HUD")
	local scroll = hud and hud:FindFirstChild("StagesFrame") and hud.StagesFrame:FindFirstChild("InfoScroll")
	if scroll then
		local count = 0
		for _, child in ipairs(scroll:GetChildren()) do
			if child.ClassName == "Frame" and child.Name ~= "Example" then
				count += 1
				local stageLbl = child:FindFirstChild("StageLabel")
				local modesLbl = child:FindFirstChild("ModesLabel")
				local nickLbl = child:FindFirstChild("NicknameLabel")
				local num = stageLbl and string.match(stageLbl.Text or "", "(%d+)") or tostring(count)
				local modes = modesLbl and tonumber(string.match(modesLbl.Text or "", "MODE%(S%):%s*(%d+)")) or 1
				table.insert(stages, {
					id = num,
					word = KEY_NAME_MAP[num] or ("One"),
					label = ("Stage %s"):format(num),
					modes = modes,
					nick = nickLbl and nickLbl.Text or child.Name,
				})
			end
		end
	end
	if #stages == 0 then
		for i = 1, 3 do
			table.insert(stages, {
				id = tostring(i),
				word = KEY_NAME_MAP[tostring(i)] or "One",
				label = ("Stage %s"):format(i),
				modes = 2,
				nick = "?",
			})
		end
	end
	Farm.AvailableStages = stages
	if Farm.Stage == "" then
		Farm.Stage = stages[1].id
	end
	return stages
end

local function currentStageInfo()
	for _, s in ipairs(Farm.AvailableStages) do
		if tostring(s.id) == tostring(Farm.Stage) then
			return s
		end
	end
	return Farm.AvailableStages[1]
end

local function stageWord()
	local st = currentStageInfo()
	if st and st.word then return st.word end
	return KEY_NAME_MAP[tostring(Farm.Stage)] or "One"
end

-- ===================== character state =====================
local function hasEquip()
	local c = LocalPlayer.Character
	if not c then return false end
	-- working.lua: if not Kagune and not Quinque then equip
	return c:FindFirstChild("Kagune") ~= nil or c:FindFirstChild("Quinque") ~= nil
end

local function isWeaponOut()
	local c = LocalPlayer.Character
	if not c then return false end
	return c:FindFirstChild("Kagune") ~= nil or c:FindFirstChild("Quinque") ~= nil
end

-- ===================== noclip + anti-detect (z4gs anti-fly style) =====================
local function setNoclip(on)
	if on and not Farm._noclipConn then
		Farm._noclipConn = RunService.Stepped:Connect(function()
			local c = LocalPlayer.Character
			if not c then return end
			for _, p in ipairs(c:GetChildren()) do
				if p:IsA("BasePart") then
					p.CanCollide = false
				end
			end
		end)
	elseif not on and Farm._noclipConn then
		Farm._noclipConn:Disconnect()
		Farm._noclipConn = nil
		-- restore collision on stop
		local c = LocalPlayer.Character
		if c then
			for _, p in ipairs(c:GetChildren()) do
				if p:IsA("BasePart") then
					p.CanCollide = true
				end
			end
		end
	end
end

-- ===================== teleport — working.lua CFrame tween (no stealth; stealth froze the game) =====================
local function teleportTo(pos)
	local c, hrp, hum = character()
	if not hrp then return end
	if not pos or (typeof(pos) ~= "CFrame" and typeof(pos) ~= "Vector3") then return end
	if typeof(pos) == "Vector3" then
		pos = CFrame.new(pos)
	end

	local val = Instance.new("CFrameValue")
	val.Value = hrp.CFrame
	local dist = (hrp.Position - pos.p).Magnitude
	local tween = TweenService:Create(
		val,
		TweenInfo.new(math.max(dist / math.clamp(Farm.TeleportSpeed, 30, 250), 0.08), Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0),
		{ Value = pos }
	)
	tween:Play()
	local completed = false
	tween.Completed:Connect(function() completed = true end)
	while not completed do
		if not Farm.Enabled then tween:Cancel() break end
		local ch = LocalPlayer.Character
		if not ch or not ch:FindFirstChild("HumanoidRootPart") or ch.Humanoid.Health <= 0 then
			tween:Cancel()
			break
		end
		ch.HumanoidRootPart.CFrame = val.Value
		if Farm.Noclip then
			ch.HumanoidRootPart.CanCollide = false
		end
		task.wait()
	end
	val:Destroy()
end

-- ===================== loadout =====================
local function ensureEquip()
	-- working.lua:
	-- if not FindFirstChild("Kagune") and not FindFirstChild("Quinque") then pressKey(stage) end
	if tick() - Farm.LastEquip < 0.35 then return end
	local c = LocalPlayer.Character
	if c and (c:FindFirstChild("Kagune") or c:FindFirstChild("Quinque")) then
		Farm.LastEquip = tick()
		return
	end
	pressKey(stageWord())
	Farm.LastEquip = tick()
end

local appliedMode = nil

local function ensureWeaponMode()
	-- restored from working Weapon Mode (Auto | Blade | Ranged)
	if not hasEquip() then return end
	local st = currentStageInfo()
	local want = Farm.WeaponMode
	if Farm.RangeMode then
		want = "Ranged"
	elseif want == "Auto" then
		want = (st and (st.modes or 1) >= 2) and "Ranged" or "Blade"
	end
	if want == appliedMode then return end
	if tick() - Farm.LastRange < 1 then return end

	-- only press C when actually changing form:
	--  nil -> Ranged : press (enter range)
	--  Ranged -> Blade : press (back to blade)
	--  nil -> Blade : do nothing (already blade)
	if want == "Ranged" and appliedMode ~= "Ranged" then
		pressKey("C")
	elseif want == "Blade" and appliedMode == "Ranged" then
		pressKey("C")
	end
	appliedMode = want
	Farm.LastRange = tick()
	Farm._rangedOn = (want == "Ranged")
	print("[Autofarm] weapon mode -> " .. tostring(want))
end

local function ensureRangeAfterEquip()
	-- keep RangeMode in sync with old behavior
	if Farm.RangeMode and not Farm._rangedOn then
		ensureWeaponMode()
	elseif Farm.RangeMode then
		-- if CD blipped, re-apply every 8s
		if tick() - Farm.LastRange > 8 then
			appliedMode = nil
			ensureWeaponMode()
		end
	end
end

local function ensureMask()
	if not Farm.AutoMask then return end
	if tick() - Farm.LastMask < 2 then return end
	local folder = pf()
	local mask = folder and folder:FindFirstChild("Mask")
	if mask and mask.Value then
		Farm.LastMask = tick()
		return
	end
	pressKey("M")
	Farm.LastMask = tick()
end

local function ensureArata()
	if not Farm.AutoArata then return end
	-- long cooldown prevents spam
	if tick() - Farm.LastArata < 8 then return end
	local sc = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("ServerControl")
	local arataOn = sc and sc:FindFirstChild("ArataOn")
	if arataOn then
		if arataOn.Value then
			-- already open — never tap Zero
			Farm.LastArata = tick()
			return
		end
		-- closed: open once
		pressKey("Zero")
		Farm.LastArata = tick()
		return
	end
	-- no ArataOn flag: don't spam; try rarely
	pressKey("Zero")
	Farm.LastArata = tick()
end

-- death re-arm
local function onDeathReset()
	Farm.CurrentTarget = nil
	Farm.CorpseNpc = nil
	Farm.CorpseName = nil
	Farm._rangedOn = false
	appliedMode = nil
	Farm.LastEquip = 0
	Farm.LastMask = 0
	Farm.LastArata = 0
	Farm.LastRange = 0
	task.delay(1.5, function()
		if Farm.AutoMask then
			pressKey("M")
			Farm.LastMask = tick()
		end
		if Farm.AutoArata then
			pressKey("Zero")
			Farm.LastArata = tick()
		end
	end)
end

-- ===================== targeting =====================
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
	task.wait(0.5)
	refreshPlayerChars()
	onDeathReset()
end)

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

local function playerLevel()
	local folder = pf()
	local st = folder and folder:FindFirstChild("Stats")
	local lv = st and st:FindFirstChild("Level")
	return tonumber(lv and lv.Value) or 0
end

local function isBossName(name)
	return name == "Gyakusatsu" or name == "Eto Yoshimura"
		or name == "Koutarou Amon" or name == "Nishiki Nishio"
end

-- exact z4gs getNPC + boss toggles
local function getNPC()
	local _, hrp = character()
	if not hrp then return nil end
	local myPos = hrp.Position
	local level = playerLevel()

	-- Gyakusatsu special path (z4gs)
	if Farm.BossFarm["Gyakusatsu"] and level > (Farm.BossLevel["Gyakusatsu"] or 1250) then
		local spawn = Workspace.NPCSpawns and Workspace.NPCSpawns:FindFirstChild("GyakusatsuSpawn")
		if spawn then
			local lowestHp, lowestModel = math.huge, nil
			for _, v in ipairs(spawn:GetChildren()) do
				if v.Name ~= "Mob" and v:FindFirstChildOfClass("Humanoid") then
					local h = v.Humanoid.Health
					if h < lowestHp then
						lowestHp = h
						lowestModel = v
					end
				end
			end
			if lowestModel then return lowestModel end
			local g = spawn:FindFirstChild("Gyakusatsu")
			if g then return g end
		end
	end

	local nearest, nearestDist = nil, math.huge
	local spawns = Workspace:FindFirstChild("NPCSpawns")
	if not spawns then return nil end

	-- group folder name from Farm.Group (z4gs uses GhoulSpawns etc.)
	local groupName
	if Farm.Group == "Human" then groupName = "HumanSpawns"
	elseif Farm.Group == "Ghoul" then groupName = "GhoulSpawns"
	elseif Farm.Group == "CCG" then groupName = "CCGSpawns"
	elseif Farm.Group == "Aggro" then groupName = "AggroSpawns"
	elseif Farm.Group == "Boss" then groupName = "BossSpawns"
	end

	for _, folder in ipairs(spawns:GetChildren()) do
		if folder:IsA("Model") or folder:IsA("Folder") or folder:IsA("BasePart") then
			local npc = folder:FindFirstChildOfClass("Model")
			-- also check folder itself if it's the spawn mesh with model children
			if not npc then
				for _, child in ipairs(folder:GetChildren()) do
					if child:IsA("Model") and child:FindFirstChild("Head") then
						npc = child
						break
					end
				end
			end
			if npc and npc:FindFirstChild("Head") and not npc:FindFirstChild("AC") then
				local hum = npc:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and hum.MaxHealth < 1e6 then
					local inGroup = groupName and (npc.Parent and npc.Parent.Name == groupName)
						or (folder.Name == groupName)
					local bossHit = Farm.BossFarm[npc.Name]
						and level >= (Farm.BossLevel[npc.Name] or 0)
					if bossHit then
						return npc -- z4gs returns boss immediately
					end
					if inGroup or (Farm.Group == "Any") then
						if not playerChars[npc] then
							local d = (npc.HumanoidRootPart.Position - myPos).Magnitude
							if d < nearestDist then
								nearest, nearestDist = npc, d
							end
						end
					end
				end
			end
		end
	end
	return nearest
end

local function fireBossSkills()
	if not Farm.SkillsOnBoss then return end
	local folder = pf()
	if not folder then return end
	if not (folder:FindFirstChild("CanAct") and folder.CanAct.Value) then return end
	-- z4gs: for each skill, if value ~= "DownTime" then pressKey
	local map = {
		{ key = "E", cd = "Special1CD" },
		{ key = "R", cd = "Special2CD" },
		{ key = "F", cd = "Special3CD" },
		{ key = "C", cd = "SpecialBonusCD" },
	}
	for _, s in ipairs(map) do
		local cd = folder:FindFirstChild(s.cd)
		if cd and tostring(cd.Value) ~= "DownTime" and readyCD(s.cd) then
			pressKey(s.key, MH())
		end
	end
end

local function findTarget()
	-- getNPC first (bosses + group), fallback to old distance scan
	local npc = getNPC()
	if npc and npc.Parent then
		return npc
	end
	return nil
end

local function isRangedNow()
	if Farm.RangeMode or Farm.WeaponMode == "Ranged" then
		return true
	end
	if Farm.WeaponMode == "Blade" then
		return false
	end
	-- Auto
	return Farm._rangedOn == true
end

local function collectCorpse(npc)
	-- Corpse is a CHILD of the NPC:  NPC / "NPCName Corpse" / ClickPart
	-- ClickPart has an empty-name ClickDetector child (working.lua clickpart[""])
	if not npc then return false end
	local npcName = type(npc) == "table" and tostring(npc.Name) or npc.Name

	local model = nil
	-- 1) child of live/dead npc
	if type(npc) == "table" and npc.WaitForChild == nil then
		model = workspace:FindFirstChild(npcName .. " Corpse")
	else
		model = npc:FindFirstChild(npcName .. " Corpse")
		if (not model) and npc.Parent then
			model = npc.Parent:FindFirstChild(npcName .. " Corpse")
		end
		-- 2) corpse nested under spawn mesh
		if not model and npc.Parent and npc.Parent.Parent then
			model = npc.Parent.Parent:FindFirstChild(npcName .. " Corpse")
		end
		-- 3) npc itself may BE corpse holder after death
		if not model and npc:FindFirstChild("ClickPart") then
			model = npc
		end
	end

	-- 4) slow poll (corpse can appear ~0.3s after death)
	local t0 = tick()
	while not model and tick() - t0 < 1.2 and Farm.Enabled do
		task.wait(0.08)
		model = workspace:FindFirstChild(npcName .. " Corpse")
		if not model and type(npc) ~= "table" and npc.Parent then
			model = npc.Parent:FindFirstChild(npcName .. " Corpse")
		end
	end
	if not model then return false end

	local clickpart = model:FindFirstChild("ClickPart")
	if not clickpart then
		-- ClickPart might be nested
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "ClickPart" then
				clickpart = d
				break
			end
		end
	end
	if not clickpart then return false end

	local c, hrp, hum = character()
	if not hrp or not hum then return false end

	hrp.CFrame = clickpart.CFrame * CFrame.new(0, 1.7, 0)
	pcall(function() hum.WalkSpeed = Farm._baseWalkSpeed or 48 end)

	local unnamed = clickpart:FindFirstChild("")
	pcall(function()
		if not unnamed then unnamed = clickpart:WaitForChild("", 0.35) end
	end)

	local endT = tick() + 3
	while tick() < endT and Farm.Enabled do
		if not model or not model.Parent then break end
		if not model:FindFirstChild("ClickPart") then break end
		local ch = LocalPlayer.Character
		if not ch or not ch:FindFirstChild("Humanoid") or ch.Humanoid.Health <= 0 then break end
		pcall(function() ch.Humanoid:MoveTo(clickpart.Position) end)
		task.wait(0.1)
		if unnamed then
			pcall(function() fireclickdetector(unnamed, 1) end)
		else
			pcall(function()
				local cd = clickpart:FindFirstChildOfClass("ClickDetector")
				if cd then cd:MouseClick() end
			end)
		end
		Farm.Stats.collects += 1
	end

	pcall(function()
		local ch = LocalPlayer.Character
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		if h and Farm.Enabled and not Farm.AutoTrainer then
			h.WalkSpeed = 0
		end
	end)
	return true
end

-- ===================== attack =====================
local function attackHitCFrame(targetPos)
	-- Mouse.Hit style: surface point under the cursor, oriented like the camera
	local cam = Workspace.CurrentCamera
	if not cam then
		return CFrame.lookAt(targetPos, targetPos + Vector3.new(0, 0, -1))
	end
	local camCF = cam.CFrame
	return CFrame.new(targetPos) * (camCF - camCF.Position)
end

local function attackOnce(target)
	if not canAct() then return false end
	local hrpPart = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
	if not hrpPart then return false end
	local c, myHrp, hum = character()
	if not myHrp then return false end

	-- glue ALWAYS like working.lua (ranged too) so the camera/mouse sit on the NPC
	local dest
	if isRangedNow() then
		dest = hrpPart.CFrame + hrpPart.CFrame.LookVector * (-math.abs(Farm.DistanceFromNpc))
	else
		dest = hrpPart.CFrame + hrpPart.CFrame.LookVector * (-math.abs(Farm.DistanceFromNpc))
	end
	myHrp.CFrame = dest
	-- facing the target helps camera ray + Mouse.Hit
	pcall(function()
		myHrp.CFrame = CFrame.lookAt(dest.Position, hrpPart.Position)
	end)

	-- working.lua: send real Mouse.Hit after we are glued on target
	local hit = MH()
	if not hit or hit.Position.Magnitude < 1 then
		hit = attackHitCFrame(hrpPart.Position)
	end

	pressKey("Mouse1", hit)
	Farm.LastAttack = tick()
	Farm.Stats.attacks += 1

	local function trySpecial(key, cdName, minGap)
		if readyCD(cdName) and tick() - Farm.LastSpecial > minGap then
			pressKey(key, hit)
			Farm.LastSpecial = tick()
			return true
		end
		return false
	end

	if Farm.AttackE then trySpecial("E", "Special1CD", 1.0) end
	if Farm.AttackR then trySpecial("R", "Special2CD", 2.0) end
	if Farm.AttackF then trySpecial("F", "Special3CD", 3.0) end
	if Farm.AttackC then trySpecial("C", "SpecialBonusCD", 2.5) end
	return true
end

-- ===================== main =====================
local function stop()
	Farm.Enabled = false
	Farm.CurrentTarget = nil
	Farm.CorpseNpc = nil
	setNoclip(false)
	pcall(Farm.StopTrain)
	if Farm._task then
		task.cancel(Farm._task)
		Farm._task = nil
	end
	-- restore movement + collision
	local c, hrp, hum = character()
	if hum then
		pcall(function()
			hum.WalkSpeed = Farm._baseWalkSpeed or 48
			hum.AutoRotate = true
		end)
	end
	if c then
		for _, p in ipairs(c:GetChildren()) do
			if p:IsA("BasePart") then
				p.CanCollide = true
			end
		end
	end
	print("[Autofarm] stopped", Farm.Status())
end

local function loop()
	local lastApply = 0
	while Farm.Enabled do
		local c, hrp, hum = character()
		if not (c and hrp and hum) or hum.Health <= 0 then
			task.wait(0.25)
			continue
		end

		-- lock movement while farming — but NOT if Auto Trainer needs MoveTo
		if Farm._baseWalkSpeed == nil then
			Farm._baseWalkSpeed = hum.WalkSpeed
		end
		local lockMove = not Farm.AutoTrainer
		if lockMove and hum.WalkSpeed > 0 then
			pcall(function()
				hum.WalkSpeed = 0
				hum.AutoRotate = false
			end)
		elseif not lockMove and hum.WalkSpeed == 0 then
			pcall(function()
				hum.WalkSpeed = Farm._baseWalkSpeed or 48
				hum.AutoRotate = true
			end)
		end

		if tick() - lastApply > 1.0 then
			lastApply = tick()
			pcall(Farm.FetchStages)
		end

		-- order matches working.lua: equip → reputation → target → kill → corpse
		pcall(ensureEquip)
		pcall(ensureMask)
		pcall(ensureArata)
		pcall(ensureWeaponMode)
		pcall(ensureRangeAfterEquip)

		if Farm.ReputationFarm or Farm.ReputationCashout then
			local did, ret = pcall(reputationTick)
			if did and ret then
				task.wait(0.2)
				continue
			end
		end

		if Farm.CorpseNpc or (Farm.CorpseName and Farm.CollectCorpses) then
			local npc = Farm.CorpseNpc
			if (not npc or not npc.Parent) and Farm.CorpseName then
				-- resolve by name into a dummy table with Name field
				npc = { Name = Farm.CorpseName, Parent = Workspace }
			end
			Farm.CorpseNpc = nil
			Farm.CorpseName = nil
			if npc then
				pcall(collectCorpse, npc)
			end
			task.wait(0.05)
			continue
		end

		local target = Farm.CurrentTarget
		if target then
			local tHum = target:FindFirstChildOfClass("Humanoid")
			if not tHum or tHum.Health <= 0 or not target.Parent then
				Farm.Stats.kills += 1
				if Farm.CollectCorpses and not target.Name:find("Gyakusatsu", 1, true) then
					Farm.CorpseNpc = target
					Farm.CorpseName = target.Name
					-- collect immediately like working.lua
					pcall(collectCorpse, target)
					Farm.CorpseNpc = nil
					Farm.CorpseName = nil
				end
				Farm.CurrentTarget = nil
				target = nil
			end
		end
		if not target then
			target = findTarget()
			Farm.CurrentTarget = target
		end

		if target then
			local part = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
			if part then
				local isBoss = isBossName(target.Name)
					or (target.Parent and target.Parent.Name == "GyakusatsuSpawn")
				local dest
				if isBoss then
					-- exact z4gs: HRP * Angles(90) + (0, DistanceFromBoss, 0)
					dest = part.CFrame * CFrame.Angles(math.rad(90), 0, 0) + Vector3.new(0, Farm.DistanceFromBoss, 0)
				else
					-- z4gs: HRP.CFrame + lookVector * DistanceFromNpc (Npc is negative)
					dest = part.CFrame + part.CFrame.LookVector * (-math.abs(Farm.DistanceFromNpc))
				end

				local dist = (part.Position - hrp.Position).Magnitude
				if dist > 20 then
					teleportTo(dest)
				else
					pcall(function()
						local _, myHrp = character()
						if myHrp then
							myHrp.CFrame = dest
						end
					end)
					-- z4gs: skills ONLY on bosses
					if isBoss then
						pcall(fireBossSkills)
					end
					if tick() - Farm.LastAttack >= Farm.FarmDelay then
						pcall(attackOnce, target)
					end
				end
			end
		end

		task.wait(0.03)
	end
end

local hitSpoofInstalled = false
local function installHitSpoof()
	if hitSpoofInstalled or not hookmetamethod then return end
	if not getrawmetatable then
		warn("[Autofarm] no getrawmetatable; skip hit spoof")
		return
	end
	hitSpoofInstalled = true

	-- capture original BEFORE hook (hookmetamethod return can be nil here)
	local mt = getrawmetatable(game)
	local orig = mt and mt.__index

	local ok = pcall(function()
		hookmetamethod(game, "__index", newcclosure(function(self, key)
			if not checkcaller() and key == "Hit" and Farm.Enabled then
				local target = Farm.CurrentTarget
				local part = target and (target:FindFirstChild("Head") or target:FindFirstChild("HumanoidRootPart"))
				if part and typeof(self) == "Instance" and self.ClassName == "PlayerMouse" then
					local cam = Workspace.CurrentCamera
					if cam then
						return CFrame.new(part.Position) * (cam.CFrame - cam.CFrame.Position)
					end
					return CFrame.new(part.Position)
				end
			end
			if type(orig) == "function" then
				return orig(self, key)
			end
			-- table __index fallback
			if type(orig) == "table" then
				local v = orig[key]
				if type(v) == "function" then
					return v(self)
				end
				return v
			end
			return nil
		end))
	end)
	if ok then print("[Autofarm] Mouse.Hit spoof installed") else warn("[Autofarm] Mouse.Hit spoof failed") end
end

function Farm.Start()
	if Farm.Enabled then return end
	Farm.Enabled = true
	refreshPlayerChars()
	Farm.FetchStages()
	getAuthKey()
	setNoclip(Farm.Noclip)
	installHitSpoof()
Farm._rangedOn = false
	appliedMode = nil
	Farm.LastEquip = 0

	-- open mask + arata immediately (no throttle wait)
	Farm.LastMask = 0
	Farm.LastArata = 0
	Farm.LastRange = 0
	if Farm.AutoMask then
		pcall(ensureMask)
	end
	if Farm.AutoArata then
		pcall(ensureArata)
	end
	pcall(ensureEquip)
	-- weapon mode / range after a short equip delay
	task.delay(0.7, function()
		if Farm.Enabled then
			pcall(ensureEquip)
			pcall(ensureWeaponMode)
		end
	end)

	Farm._task = task.spawn(function()
		local ok, err = pcall(loop)
		if not ok then
			warn("[Autofarm] crashed:", err)
			Farm.Enabled = false
			pcall(stop)
		end
	end)
	if Farm.AutoTrainer then
		pcall(Farm.TrainLoop)
	end
	print("[Autofarm] started | group=" .. tostring(Farm.Group)
		.. " | stage=" .. tostring(Farm.Stage) .. "/" .. stageWord()
		.. " | range=" .. tostring(Farm.RangeMode)
		.. " | mask=" .. tostring(Farm.AutoMask)
		.. " | arata=" .. tostring(Farm.AutoArata))
end

function Farm.Stop()
	stop()
end

function Farm.Toggle()
	if Farm.Enabled then Farm.Stop() else Farm.Start() end
	return Farm.Enabled
end

function Farm.ApplyLoadoutNow()
	Farm.FetchStages()
	getAuthKey()
	Farm.LastEquip = 0
	Farm._rangedOn = false
	pcall(ensureEquip)
	if Farm.RangeMode then
		-- wait briefly for equip then switch
		task.delay(0.8, function()
			if hasEquip() then
				local folder = pf()
				local can = folder and folder:FindFirstChild("CanToggleWep")
				if can and can.Value and readyCD("SpecialBonusCD") then
					pressKey("C")
					Farm._rangedOn = true
					Farm.LastRange = tick()
				end
			end
		end)
	end
	if Farm.AutoMask then
		pressKey("M")
		Farm.LastMask = tick()
	end
	if Farm.AutoArata then
		pressKey("Zero")
		Farm.LastArata = tick()
	end
	print("[Autofarm] loadout", Farm.Status())
end

function Farm.ForceMask()
	pressKey("M")
	Farm.LastMask = tick()
	print("[Autofarm] mask (M)")
end

function Farm.OpenArata()
	pressKey("Zero")
	Farm.LastArata = tick()
	print("[Autofarm] arata (Zero)")
end

function Farm.KaguneToggleNow()
	pressKey("Q")
	print("[Autofarm] kagune toggle (Q)")
end

-- ===================== Trainer (working.lua loop) =====================
local function getRemotes()
	return game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
end

local function grabTrainersList()
	if Farm.TrainersList then return Farm.TrainersList end
	local folder = pf()
	local team = folder and folder.Customization and folder.Customization.Team.Value or "CCG"
	local want = team == "CCG" and "(S1) Kureo Mado" or "(S1) Ken Kaneki"
	pcall(function()
		if not getgc then return end
		for _, v in pairs(getgc(true)) do
			if type(v) == "table" and table.find(v, want) then
				Farm.TrainersList = v
				return
			end
		end
	end)
	return Farm.TrainersList
end

-- one training cycle — same as working.lua btn2 Start body
local function trainCycle()
	local remotes = getRemotes()
	if not remotes then return end
	local folder = pf()
	if not folder then return end
	local trainers = folder:FindFirstChild("Trainers")
	if not trainers then return end
	local team = folder.Customization and folder.Customization.Team.Value or "CCG"
	local trainerName = trainers[team .. "Trainer"] and trainers[team .. "Trainer"].Value

	local tkey
	local connection = Farm._tsConn
	if connection and connection.Connected then
		connection:Disconnect()
	end

	pcall(function()
		connection = LocalPlayer.Backpack.DescendantAdded:Connect(function(obj)
			if tostring(obj) == "TSCodeVal" and obj:IsA("StringValue") then
				tkey = obj.Value
			end
		end)
		Farm._tsConn = connection
	end)

	local result
	pcall(function()
		result = remotes.Trainers.RequestTraining:InvokeServer()
	end)

	if connection and connection.Connected then
		connection:Disconnect()
	end

	if result == "TRAINING" then
		local sessions = Workspace:FindFirstChild("TrainingSessions")
		if sessions then
			for _, v in ipairs(sessions:GetChildren()) do
				local pl = v:FindFirstChild("Player")
				if pl and pl.Value == LocalPlayer then
					local comm = v:FindFirstChild("Comm")
					if comm then
						pcall(function()
							comm:FireServer("Finished", tkey, false)
						end)
					end
					break
				end
			end
		end
	elseif result == "TRAINING COMPLETE" then
		local list = grabTrainersList()
		local cur = trainerName and trainers:FindFirstChild(trainerName)
		local prog = cur and cur:FindFirstChild("Progress")
		if list and prog and tonumber(prog.Value) == 100 then
			for _, v in ipairs(trainers:GetDescendants()) do
				if table.find(list, v.Name) then
					local p = v:FindFirstChild("Progress")
					if p and tonumber(p.Value) < 100 then
						pcall(function()
							remotes.Trainers.ChangeTrainer:InvokeServer(v.Name)
						end)
						task.wait(1.5)
						break
					end
				end
			end
		end
	end
	-- else: result is time until next training — just wait
	return result
end

function Farm.TrainLoop()
	if Farm._trainTask then return end
	Farm.AutoTrainer = true
	Farm._trainTask = task.spawn(function()
		-- runs even when autofarm Start is not pressed
		while Farm.AutoTrainer do
			pcall(trainCycle)
			task.wait(1)
		end
		Farm._trainTask = nil
	end)
	print("[Autofarm] trainer loop ON")
end

function Farm.StopTrain()
	Farm.AutoTrainer = false
	if Farm._tsConn and Farm._tsConn.Connected then
		pcall(function() Farm._tsConn:Disconnect() end)
	end
	if Farm._trainTask then
		task.cancel(Farm._trainTask)
		Farm._trainTask = nil
	end
	print("[Autofarm] trainer loop OFF")
end

-- ===================== Reputation (working.lua getQuest) =====================
local function getQuestNPC()
	local folder = pf()
	local team = folder and folder.Customization and folder.Customization.Team.Value or "Ghoul"
	if team == "Ghoul" then
		local anteiku = Workspace:FindFirstChild("Anteiku")
		return anteiku and anteiku:FindFirstChild("Yoshimura")
	end
	local ccg = Workspace:FindFirstChild("CCGBuilding")
	return ccg and ccg:FindFirstChild("Yoshitoki")
end

-- typ=true → get quest, typ=false → cashout
local function getQuest(typ)
	local remotes = getRemotes()
	if not remotes then return end
	local npc = getQuestNPC()
	if not npc or not npc:FindFirstChild("HumanoidRootPart") then return end

	teleportTo(npc.HumanoidRootPart.CFrame)
	pcall(function()
		remotes.Ally.AllyInfo:InvokeServer()
	end)
	task.wait()
	local ind = npc:FindFirstChild("TaskIndicator")
	local cd = ind and ind:FindFirstChild("ClickDetector")
	if cd then
		pcall(function() fireclickdetector(cd) end)
	end

	local _, hrp = character()
	if not Farm.Enabled or not hrp then return end
	if (npc.HumanoidRootPart.Position - hrp.Position).Magnitude > 20 then return end

	if typ then
		local remote = remotes:FindFirstChild(npc.Name)
		local taskRf = remote and remote:FindFirstChild("Task")
		if taskRf then
			pcall(function() taskRf:InvokeServer() end)
			task.wait(0.2)
			pcall(function() taskRf:InvokeServer() end)
		end
	else
		pcall(function() remotes.ReputationCashOut:InvokeServer() end)
		Farm.LastCashout = tick()
	end
end

-- called from main loop — same condition as working.lua farm while
local function reputationTick()
	local folder = pf()
	if not folder then return false end
	local cq = folder:FindFirstChild("CurrentQuest")
	local complete = cq and cq:FindFirstChild("Complete")
	local quest = complete and complete:FindFirstChild("Aogiri Member")

	-- working.lua: not quest OR quest.Value >= quest.Max.Value
	local missing = (quest == nil)
	local done = false
	if quest then
		local ok = pcall(function()
			done = tonumber(quest.Value) >= tonumber(quest.Max.Value)
		end)
		if not ok then
			done = false
		end
	end

	if Farm.ReputationFarm and (missing or done) then
		getQuest(true)
		return true
	elseif Farm.ReputationCashout and tick() - Farm.LastCashout > 7200 then
		getQuest(false)
		return true
	end
	return false
end

function Farm.GetQuestText()
	local folder = pf()
	local cq = folder and folder:FindFirstChild("CurrentQuest")
	local complete = cq and cq:FindFirstChild("Complete")
	if not complete then return "None" end
	for _, v in ipairs(complete:GetChildren()) do
		local val = v:IsA("ValueBase") and v.Value or (v:FindFirstChild("Value") and v.Value.Value)
		local mx = v:FindFirstChild("Max") and v.Max.Value
		if mx then
			return string.format("%s: %s/%s", v.Name, tostring(val or "?"), tostring(mx))
		end
		return v.Name
	end
	return "None"
end

function Farm.GetStatsText()
	local folder = pf()
	local st = folder and folder:FindFirstChild("Stats")
	local function sv(n)
		local x = st and st:FindFirstChild(n)
		return x and x.Value or "0"
	end
	return string.format(
		"Kills %d | Yen %s | RC %s | Quest: %s",
		Farm.Stats.kills,
		sv("Yen"),
		sv("RC"),
		Farm.GetQuestText()
	)
end

function Farm.Status()
	local st = currentStageInfo()
	return string.format(
		"on=%s target=%s kills=%d attacks=%d collects=%d stage=%s ranged=%s key=%s train=%s rep=%s\n%s",
		tostring(Farm.Enabled),
		Farm.CurrentTarget and Farm.CurrentTarget.Name or "-",
		Farm.Stats.kills, Farm.Stats.attacks, Farm.Stats.collects,
		tostring(Farm.Stage) .. (st and ("/" .. tostring(st.nick)) or ""),
		tostring(Farm._rangedOn),
		Farm.RemoteKey and (#Farm.RemoteKey .. "ch") or "?",
		tostring(Farm.AutoTrainer),
		tostring(Farm.ReputationFarm or Farm.ReputationCashout),
		Farm.GetStatsText()
	)
end

task.defer(function()
	Farm.FetchStages()
	getAuthKey()
end)


return Farm
