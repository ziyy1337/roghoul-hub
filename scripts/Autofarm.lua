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
	-- working.lua stores these already negated: slider * -1
	DistanceFromNpc = -5,  -- lookVector * DistanceFromNpc
	DistanceFromBoss = -8, -- Vector3(0, DistanceFromBoss, 0)
	FarmDelay = 0.05,     -- attack tick

	-- Boss level gates (working.lua array.boss)
	Boss = {
		["Gyakusatsu"] = 1250,
		["Eto Yoshimura"] = 1250,
		["Koutarou Amon"] = 750,
		["Nishiki Nishio"] = 250,
	},
	BossEnabled = {
		["Gyakusatsu"] = false,
		["Eto Yoshimura"] = false,
		["Koutarou Amon"] = false,
		["Nishiki Nishio"] = false,
	},
	-- Boss skills (only fire on boss targets)
	Skills = { E = false, R = false, F = false, C = false },

	Group = "Ghoul",
	PreferNearest = true,
	PreferLowestHP = false,

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

	-- Gya Farm: camp behind the building at BR/BL, kill statue on spawn
	GyaFarm = false,
	GyaCamp = "Back of BR",
	GyaCampPos = nil, -- set by SaveGyaCampHere
	GyaCamLock = true, -- lock camera on BR/BL axis so one shot threads both hearts
	_gyaCampT = 0,

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
	LastQuestTry = 0,
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

local SKILL_CD = {
	E = "Special1CD",
	R = "Special2CD",
	F = "Special3CD",
	C = "SpecialBonusCD",
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
	local stats = folder and folder:FindFirstChild("Stats")
	local lv = stats and stats:FindFirstChild("Level")
	return tonumber(lv and lv.Value) or 0
end

local function isBossName(nm)
	return Farm.Boss[nm] ~= nil
end

local function bossPoseFor(part)
	-- working.lua: CFrame * Angles(90,0,0) + Vector3.new(0, DistanceFromBoss, 0)
	return part.CFrame * CFrame.Angles(math.rad(90), 0, 0) + Vector3.new(0, Farm.DistanceFromBoss, 0)
end

local function npcPoseFor(part)
	-- working.lua: CFrame + lookVector * DistanceFromNpc (stored negative)
	return part.CFrame + part.CFrame.LookVector * Farm.DistanceFromNpc
end

-- ===================== gya farm camp =====================
-- Verified spots behind the mall buildings (statue LOS blocked, floor y≈61):
--   Back of BR → behind ShopsL near the BR heart corner
--   Back of BL → user-picked spot behind PartsStore (ShopsR), same cover pattern
local GYA_CAMPS = {
	["Back of BR"] = Vector3.new(-500, 64, 165),
	["Back of BL"] = Vector3.new(-396.5, 64, 352.4),
}

local function gyaCampPos()
	if Farm.GyaCamp == "My Position" and Farm.GyaCampPos then
		return Farm.GyaCampPos
	end
	return GYA_CAMPS[Farm.GyaCamp] or GYA_CAMPS["Back of BR"]
end

function Farm.SaveGyaCampHere()
	local _, hrp = character()
	if not hrp then return false end
	Farm.GyaCampPos = hrp.Position
	Farm.GyaCamp = "My Position"
	print("[Autofarm] gya camp saved:", hrp.Position)
	return true
end

-- ===================== gya hearts axis camera =====================
-- BR and BL hearts are nearly collinear (axis ≈ +Z). A camera parked on
-- that axis line looking along it sends one straight shot through BOTH
-- heart centers — verified live: extended ray lands inside BL's part box.
local GYA_HEARTS = {
	BR = Vector3.new(-530.50, 67.98, 206.58),
	BL = Vector3.new(-519.59, 67.38, 341.97),
}

local function gyaBody()
	return Workspace:FindFirstChild("Gyakusatsu")
end

local function gyaHeartPositions()
	local body = gyaBody()
	local br, bl = GYA_HEARTS.BR, GYA_HEARTS.BL
	if body then
		local a = body:FindFirstChild("BR") and body.BR:FindFirstChild("Spawn")
		local b = body:FindFirstChild("BL") and body.BL:FindFirstChild("Spawn")
		if a then br = a.Position end
		if b then bl = b.Position end
	end
	return br, bl
end

-- camera CFrame on the axis, 55 studs north of BR, aimed straight down the line
local function gyaAxisCam()
	local br, bl = gyaHeartPositions()
	local axis = (bl - br).Unit
	local camPos = br - axis * 55 + Vector3.new(0, 2, 0)
	return CFrame.lookAt(camPos, camPos + axis), camPos, axis, br, bl
end

local gyaCamConn = nil
local function setGyaCamLoop(on)
	if on and not gyaCamConn then
		gyaCamConn = RunService.RenderStepped:Connect(function()
			if not (Farm.Enabled and Farm.GyaFarm and Farm.GyaCamLock and gyaBody()) then return end
			local cf = gyaAxisCam()
			local cam = Workspace.CurrentCamera
			if cam then cam.CFrame = cf end
		end)
	elseif not on and gyaCamConn then
		gyaCamConn:Disconnect()
		gyaCamConn = nil
	end
end

local function findTarget()
	-- working.lua getNPC priority: enabled Gyakusatsu (lowest HP) → any enabled boss → nearest group NPC
	local _, hrp = character()
	if not hrp then return nil end
	local spawns = Workspace:FindFirstChild("NPCSpawns")
	if not spawns then return nil end
	local level = playerLevel()

	-- Gya Farm mode: ONLY the statue matters; ignore group/boss toggles
	if Farm.GyaFarm then
		local gspawn = spawns:FindFirstChild("GyakusatsuSpawn")
		if not gspawn then return nil end
		local lowestHP, lowestModel = math.huge, nil
		for _, v in ipairs(gspawn:GetChildren()) do
			if v.Name ~= "Mob" and v:FindFirstChildOfClass("Humanoid") then
				local h = v.Humanoid.Health
				if h > 0 and h < lowestHP then
					lowestHP = h
					lowestModel = v
				end
			end
		end
		if lowestModel then return lowestModel end
		local fallback = gspawn:FindFirstChild("Gyakusatsu")
		if fallback and fallback:FindFirstChild("Humanoid") and fallback.Humanoid.Health > 0 then
			return fallback
		end
		return nil -- not spawned: caller camps
	end

	-- 1) Gyakusatsu special (lowest HP among spawn)
	if Farm.BossEnabled["Gyakusatsu"] and level > (Farm.Boss["Gyakusatsu"] or 9999) then
		local gspawn = spawns:FindFirstChild("GyakusatsuSpawn")
		if gspawn then
			local lowestHP, lowestModel = math.huge, nil
			for _, v in ipairs(gspawn:GetChildren()) do
				if v.Name ~= "Mob" and v:FindFirstChildOfClass("Humanoid") then
					local h = v.Humanoid.Health
					if h > 0 and h < lowestHP then
						lowestHP = h
						lowestModel = v
					end
				end
			end
			if lowestModel then
				return lowestModel
			end
			local fallback = gspawn:FindFirstChild("Gyakusatsu")
			if fallback and fallback:FindFirstChild("Humanoid") and fallback.Humanoid.Health > 0 then
				return fallback
			end
		end
	end

	local nearest, nearestDist = nil, math.huge
	local myPos = hrp.Position
	for _, folder in ipairs(spawns:GetChildren()) do
		-- first Model child in folder (working.lua FindFirstChildOfClass Model)
		local npc = folder:FindFirstChildOfClass("Model")
		if npc and npc:FindFirstChild("Head") and not npc:FindFirstChild("AC") then
			local hum = npc:FindFirstChildOfClass("Humanoid")
			local part = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head")
			if hum and part and hum.Health > 0 then
				local nm = npc.Name
				-- enabled boss with level gate → return immediately
				if Farm.BossEnabled[nm] and level >= (Farm.Boss[nm] or 9999) then
					return npc
				end
				-- group match (working.lua array.targ == parent folder name)
				local groupMatch = false
				if Farm.Group == "Any" then
					groupMatch = true
				elseif Farm.Group == "Gyakusatsu" then
					groupMatch = nm == "Gyakusatsu" or folder.Name:find("Gyakusatsu", 1, true) ~= nil
				else
					groupMatch = (folder.Name == Farm.Group)
						or (Farm.Group == "Ghoul" and folder.Name:find("Ghoul", 1, true) ~= nil)
						or (Farm.Group == "CCG" and folder.Name:find("CCG", 1, true) ~= nil)
						or (Farm.Group == "Human" and folder.Name:find("Human", 1, true) ~= nil)
						or (Farm.Group == "Aggro" and folder.Name:find("Aggro", 1, true) ~= nil)
						or (Farm.Group == "Boss" and isBossName(nm))
				end
				if groupMatch then
					local dist = (part.Position - myPos).Magnitude
					if dist < nearestDist then
						nearestDist = dist
						nearest = npc
					end
				end
			end
		end
	end
	return nearest
end

local function targetIsBoss(npc)
	if not npc then return false end
	if npc.Parent and npc.Parent.Name == "GyakusatsuSpawn" then return true end
	if Farm.BossEnabled[npc.Name] then return true end
	-- also treat as boss for pose if named in Boss map (even if toggle off, GyakusatsuSpawn pose still applies)
	return npc.Name == "Gyakusatsu"
end

local function fireBossSkills(target)
	if not target then return end
	if not canAct() then return end
	for key, enabled in pairs(Farm.Skills) do
		if enabled then
			local cdName = SKILL_CD[key]
			if not cdName then continue end
			-- working.lua: skill fires when Value ~= "DownTime"
			local folder = pf()
			local cd = folder and folder:FindFirstChild(cdName)
			local val = cd and tostring(cd.Value)
			if (not cd) or val ~= "DownTime" then
				local part = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
				if part then
					pressKey(key, MH())
				end
			end
		end
	end
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

	-- glue like working.lua: boss pose vs npc pose
	local boss = targetIsBoss(target)
	local dest = boss and bossPoseFor(hrpPart) or npcPoseFor(hrpPart)
	myHrp.CFrame = dest
	if not boss then
		-- facing the target helps camera ray + Mouse.Hit
		pcall(function()
			myHrp.CFrame = CFrame.lookAt(dest.Position, hrpPart.Position)
		end)
	end

	-- working.lua: send real Mouse.Hit after we are glued on target
	local hit = MH()
	if not hit or hit.Position.Magnitude < 1 then
		hit = attackHitCFrame(hrpPart.Position)
	end

	pressKey("Mouse1", hit)
	Farm.LastAttack = tick()
	Farm.Stats.attacks += 1

	-- boss skills: same as working.lua loop (only when target is boss)
	if boss then
		pcall(fireBossSkills, target)
	end

	-- optional attack toggles (still respect CD; not required on bosses)
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
local reputationTick
local function stop()
	Farm.Enabled = false
	Farm.CurrentTarget = nil
	Farm.CorpseNpc = nil
	setNoclip(false)
	setGyaCamLoop(false)
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

		-- Gya Farm: event body present → stand on the BR/BL axis and
		-- shoot straight down the line so ONE shot threads BOTH hearts
		if Farm.GyaFarm and gyaBody() then
			local cf, camPos = gyaAxisCam()
			if tick() - Farm._gyaCampT > 1.0 then
				Farm._gyaCampT = tick()
				local _, myHrp = character()
				local stand = Vector3.new(camPos.X, camPos.Y - 2, camPos.Z)
				if myHrp and (myHrp.Position - stand).Magnitude > 4 then
					pcall(teleportTo, stand)
				end
			end
			if canAct() and tick() - Farm.LastAttack >= Farm.FarmDelay then
				local br = gyaHeartPositions()
				local hit = CFrame.new(br) * (cf - cf.Position)
				pcall(pressKey, "Mouse1", hit)
				Farm.LastAttack = tick()
				Farm.Stats.attacks += 1
			end
			task.wait(0.05)
			continue
		end

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
				-- working.lua: Gyakusatsu forces suicide to respawn cycle
				if target.Name == "Gyakusatsu" then
					pcall(function()
						local _, _, myHum = character()
						if myHum then myHum.Health = 0 end
					end)
				end
				-- working.lua: skip corpse for Gyakusatsu + Eto Yoshimura
				local skipCorpse = (target.Name == "Gyakusatsu")
					or (target.Name == "Eto Yoshimura")
					or target.Name:find("Gyakusatsu", 1, true) ~= nil
				if Farm.CollectCorpses and not skipCorpse then
					Farm.CorpseNpc = target
					Farm.CorpseName = target.Name
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

		-- Gya Farm: statue not spawned → sit at the camp behind the building
		if Farm.GyaFarm and not target then
			local camp = gyaCampPos()
			if camp and tick() - Farm._gyaCampT > 2.0 then
				Farm._gyaCampT = tick()
				local _, myHrp = character()
				if myHrp and (myHrp.Position - camp).Magnitude > 5 then
					pcall(teleportTo, camp)
				end
			end
			task.wait(0.2)
			continue
		end

		if target then
			local part = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
			if part then
				local isBoss = targetIsBoss(target)
				local dest = isBoss and bossPoseFor(part) or npcPoseFor(part)

				local dist = (part.Position - hrp.Position).Magnitude
				if dist > 20 then
					teleportTo(dest)
				else
					-- glue like working.lua (boss uses Angle 90 + DistanceFromBoss)
					pcall(function()
						local _, myHrp = character()
						if myHrp then
							myHrp.CFrame = dest
						end
					end)
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
	hitSpoofInstalled = true
	local ok = pcall(function()
		local old = hookmetamethod(game, "__index", newcclosure(function(self, key)
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
			return old(self, key)
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
	setGyaCamLoop(true)
	-- installHitSpoof() -- disabled: game __index crashed
Farm._rangedOn = false
	appliedMode = nil
	Farm.LastEquip = 0
	-- LastCashout intentionally NOT reset: a Start/Stop must not re-trigger
	-- cashout/quest trips while an unfinished quest is still active

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
-- Mirrors working.lua getQuest: AllyInfo → click TaskIndicator → dist<=20 →
-- Task invoke x2 → wait for CurrentQuest.Complete["Aogiri Member"]
local function getQuest(typ)
	print("[Autofarm] rep getQuest typ=", tostring(typ))
	local remotes = getRemotes()
	if not remotes then
		print("[Autofarm] rep no remotes")
		return false
	end
	local npc = getQuestNPC()
	if not npc or not npc:FindFirstChild("HumanoidRootPart") then
		print("[Autofarm] rep npc missing")
		return false
	end
	local npcRoot = npc.HumanoidRootPart

	teleportTo(npcRoot.CFrame)

	pcall(function()
		remotes.Ally.AllyInfo:InvokeServer()
	end)
	task.wait(0.1)
	local ind = npc:FindFirstChild("TaskIndicator")
	local cd = ind and ind:FindFirstChild("ClickDetector")
	if cd then
		pcall(function() fireclickdetector(cd) end)
	else
		print("[Autofarm] rep no TaskIndicator.ClickDetector")
	end

	-- fresh dist check like working.lua (post-click); force CFrame if stuck
	local _, hrp = character()
	if not hrp or not Farm.Enabled then
		print("[Autofarm] rep abort (dead/disabled)")
		return false
	end
	local dist = (npcRoot.Position - hrp.Position).Magnitude
	if dist > 20 then
		pcall(function() hrp.CFrame = npcRoot.CFrame end)
		dist = (npcRoot.Position - hrp.Position).Magnitude
	end
	if not Farm.Enabled or not hrp or dist > 20 then
		print("[Autofarm] rep abort dist=", math.floor(dist))
		return false
	end

	if typ then
		local remote = remotes:FindFirstChild(npc.Name)
		local taskRf = remote and remote:FindFirstChild("Task")
		if not taskRf then
			print("[Autofarm] rep no Task remote under", npc.Name)
			return false
		end
		-- re-assert position immediately before Task invokes
		pcall(function() hrp.CFrame = npcRoot.CFrame end)
		local ok1 = pcall(function() taskRf:InvokeServer() end)
		local ok2 = pcall(function() taskRf:InvokeServer() end)
		if not ok1 and not ok2 then
			print("[Autofarm] rep Task invoke failed")
			return false
		end
		-- wait for a FRESH quest: entry must exist AND Value < Max.
		-- A just-finished quest already sits at Value==Max, so merely finding
		-- the child would return "granted" while the old quest is still there.
		local function freshQuest()
			local folder2 = pf()
			local cq = folder2 and folder2:FindFirstChild("CurrentQuest")
			local complete = cq and cq:FindFirstChild("Complete")
			local q = complete and complete:FindFirstChild("Aogiri Member")
			if not q then return false end
			local ok, fresh = pcall(function()
				return tonumber(q.Value) < tonumber(q.Max.Value)
			end)
			return ok and fresh == true
		end
		local deadline = tick() + 8
		local granted = freshQuest()
		while not granted and tick() < deadline and Farm.Enabled do
			task.wait(0.1)
			granted = freshQuest()
		end
		if granted then
			print("[Autofarm] rep quest granted")
			return true
		end
		print("[Autofarm] rep quest did not spawn after Task invoke")
		return false
	else
		local ok = pcall(function() remotes.ReputationCashOut:InvokeServer() end)
		if ok then
			Farm.LastCashout = tick()
			print("[Autofarm] rep cashout done")
			return true
		end
		print("[Autofarm] rep cashout invoke failed")
		return false
	end
end

-- called from main loop — same condition as working.lua farm while
-- returns true only when a quest was actually granted, so the loop retries
-- on failure instead of skipping forever
function reputationTick()
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

	-- unfinished quest (0 < Value < Max): nothing to do — never re-trip
	if quest and not missing and not done then
		return false
	end

	if Farm.ReputationFarm and (missing or done) then
		if tick() - Farm.LastQuestTry < 2.5 then
			return false -- let the previous invoke breathe before retrying
		end
		Farm.LastQuestTry = tick()
		print("[Autofarm] rep needQuest miss=", missing, " done=", done)
		return getQuest(true) == true
	elseif Farm.ReputationCashout and tick() - Farm.LastCashout > 7200 then
		if tick() - Farm.LastQuestTry < 2.5 then
			return false
		end
		Farm.LastQuestTry = tick()
		print("[Autofarm] rep needCashout")
		getQuest(false)
		return false -- working.lua keeps farming after cashout
	end
	return false
end

function Farm.Status()
	local st = currentStageInfo()
	local bossOn = {}
	for name, on in pairs(Farm.BossEnabled) do
		if on then bossOn[#bossOn + 1] = name end
	end
	return string.format(
		"on=%s target=%s kills=%d attacks=%d collects=%d stage=%s ranged=%s key=%s train=%s rep=%s distNpc=%s distBoss=%s bosses=%s",
		tostring(Farm.Enabled),
		Farm.CurrentTarget and Farm.CurrentTarget.Name or "-",
		Farm.Stats.kills, Farm.Stats.attacks, Farm.Stats.collects,
		tostring(Farm.Stage) .. (st and ("/" .. tostring(st.nick)) or ""),
		tostring(Farm._rangedOn),
		Farm.RemoteKey and (#Farm.RemoteKey .. "ch") or "?",
		tostring(Farm.AutoTrainer),
		tostring(Farm.ReputationFarm or Farm.ReputationCashout),
		tostring(Farm.DistanceFromNpc),
		tostring(Farm.DistanceFromBoss),
		#bossOn > 0 and table.concat(bossOn, ",") or "none"
	)
end

task.defer(function()
	Farm.FetchStages()
	getAuthKey()
end)


return Farm
