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

	Quinque = "IXA", -- unused in UI; Stage drives equip
	Stage = "One",         -- "One".."Six" (KeyEvent stage names)
	WeaponMode = "Auto",   -- kept for API; UI uses RangeMode only

	-- Attacks (Mouse1 always active)
	AttackE = false,
	AttackR = false,
	AttackF = false,
	AttackC = false,
	RangeMode = false,
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
	LastAttack = 0,
	LastSpecial = 0,
	LastArata = 0,
	LastMask = 0,
	LastRange = 0,
	LastEquip = 0,
	LastCashout = 0,
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
	local folder = pf()
	if not folder then return true end
	local v = folder:FindFirstChild(name)
	if not v then return true end
	local val = tostring(v.Value)
	return val == "Ready"
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
	if Farm.RemoteKey and #Farm.RemoteKey >= 50 then
		return Farm.RemoteKey
	end
	-- try grab from ClientControl constants (z4gs method)
	local ok = pcall(function()
		if not GetGc or not GetConstants then return end
		for _, v in pairs(GetGc(true)) do
			if type(v) == "function" then
				local info = getinfo and getinfo(v)
				if info and info.source and info.source:find("ClientControl") then
					local constants = GetConstants(v)
					for i, c in ipairs(constants) do
						if c == "KeyEvent" then
							local found = constants[i + 1]
							if type(found) == "string" and #found >= 50 then
								Farm.RemoteKey = found
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
	end
end

-- Hide HRP CFrame spam from simple GetChildren scans while we teleport
local function withStealth(fn)
	if not Farm.Noclip then
		return fn()
	end
	local protected = {}
	local hidden = {}
	pcall(function()
		local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return fn() end
		-- random decoy part parented near character, name-guessed off lists
		local decoy = Instance.new("Part")
		decoy.Name = string.rep("z", math.random(6, 10))
		decoy.Size = Vector3.new(0.05, 0.05, 0.05)
		decoy.Transparency = 1
		decoy.Anchored = true
		decoy.CanCollide = false
		decoy.CFrame = hrp.CFrame
		decoy.Parent = workspace
		table.insert(protected, decoy)

		-- disable ChildAdded watchers briefly while we move (anti-detect pattern)
		for _, signal in ipairs({ workspace.ChildAdded, workspace.DescendantAdded }) do
			pcall(function()
				for _, conn in ipairs(getconnections(signal)) do
					if conn.Enabled then
						conn:Disable()
						table.insert(hidden, conn)
					end
				end
			end)
		end

		local result = fn()

		for _, conn in ipairs(hidden) do
			pcall(function() conn:Enable() end)
		end
		for _, obj in ipairs(protected) do
			pcall(function() obj:Destroy() end)
		end
		return result
	end)
	-- fallback if pcall setup failed
	return fn()
end

-- ===================== teleport — exact working.lua fly method =====================
local function teleportTo(pos)
	local c, hrp, hum = character()
	if not hrp then return end
	if not pos or (typeof(pos) ~= "CFrame" and typeof(pos) ~= "Vector3") then return end
	if typeof(pos) == "Vector3" then
		pos = CFrame.new(pos)
	end

	withStealth(function()
		local val = Instance.new("CFrameValue")
		val.Value = hrp.CFrame
		local dist = (hrp.Position - pos.p).Magnitude
		local tween = TweenService:Create(
			val,
			TweenInfo.new(dist / math.clamp(Farm.TeleportSpeed, 30, 250), Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0),
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
	end)
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

local function ensureRangeAfterEquip()
	if not Farm.RangeMode then return end
	if not hasEquip() then
		return -- wait until kagune/quinque is on character
	end
	if Farm._rangedOn then
		return -- already switched once this life
	end
	if tick() - Farm.LastRange < 2 then return end
	local folder = pf()
	local can = folder and folder:FindFirstChild("CanToggleWep")
	if can and can.Value and readyCD("SpecialBonusCD") then
		pressKey("C")
		Farm._rangedOn = true
		Farm.LastRange = tick()
	end
end

local function ensureMask()
	if not Farm.AutoMask then return end
	if tick() - Farm.LastMask < 4 then return end
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
	if tick() - Farm.LastArata < 4 then return end
	local sc = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("ServerControl")
	local arataOn = sc and sc:FindFirstChild("ArataOn")
	if arataOn and arataOn.Value then
		Farm.LastArata = tick()
		return
	end
	-- KeyCode.Zero -> KeyEvent name "Zero" (not "0")
	pressKey("Zero")
	Farm.LastArata = tick()
end

-- death re-arm
local function onDeathReset()
	Farm.CurrentTarget = nil
	Farm.CorpseNpc = nil
	Farm._rangedOn = false
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

local function findTarget()
	local _, hrp = character()
	if not hrp then return nil end
	local best, bestScore = nil, math.huge
	local myPos = hrp.Position
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and not playerChars[d] then
			local nm = d.Name
			if not nm:find("Corpse", 1, true) and not nm:find("Mob", 1, true) then
				local hum = d:FindFirstChildOfClass("Humanoid")
				local part = d:FindFirstChild("HumanoidRootPart") or d:FindFirstChild("Head")
				if hum and part and hum.Health > 0 and hum.MaxHealth < 1e6 then
					local dist = (part.Position - myPos).Magnitude
					local group = classifyNPC(d)
					local match = false
					if Farm.Group == "Any" then
						match = true
					elseif Farm.Group == "Gyakusatsu" then
						match = group == "Gyakusatsu" or nm == "Gyakusatsu" or (part.Parent and part.Parent.Name == "GyakusatsuSpawn")
					elseif Farm.Group == group then
						match = true
					end
					if match then
						local score = dist
						if Farm.PreferLowestHP and not Farm.PreferNearest then
							score = hum.Health * 0.01 + dist
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
	return best
end

local function collectCorpse(npc)
	-- exact working.lua collect pattern
	if not npc then return end
	local timer = tick()

	-- corpse is often a sibling: "NPCName Corpse"
	local model = nil
	pcall(function()
		model = npc:WaitForChild(npc.Name .. " Corpse", 1.5)
	end)
	if not model or not model.Parent then
		model = workspace:FindFirstChild(npc.Name .. " Corpse")
	end
	if not model then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Model") and d.Name == npc.Name .. " Corpse" then
				model = d
				break
			end
		end
	end
	if not model then return false end

	local clickpart = model:FindFirstChild("ClickPart")
	if not clickpart then
		pcall(function()
			clickpart = model:WaitForChild("ClickPart", 1.5)
		end)
	end
	if not clickpart then return false end

	local c, hrp, hum = character()
	if not hrp or not hum then return false end

	-- sit on the click part like working.lua
	hrp.CFrame = clickpart.CFrame * CFrame.new(0, 1.7, 0)

	-- working.lua uses unnamed child ClickDetector: clickpart[""]
	local unnamed
	pcall(function()
		unnamed = clickpart:WaitForChild("", 1)
	end)
	if not unnamed then
		unnamed = clickpart:FindFirstChild("")
	end

	repeat
		if tick() - timer > 4 then
			break
		end
		local ch = LocalPlayer.Character
		if not ch or not ch:FindFirstChild("Humanoid") or ch.Humanoid.Health <= 0 then
			break
		end
		if not model.Parent then
			break
		end
		pcall(function()
			ch.Humanoid:MoveTo(clickpart.Position)
		end)
		task.wait()
		if unnamed then
			pcall(function()
				fireclickdetector(unnamed, 1)
			end)
		else
			pcall(function()
				local cd = clickpart:FindFirstChildOfClass("ClickDetector")
				if cd then
					cd:MouseClick()
				end
			end)
		end
		Farm.Stats.collects += 1
	until not model.Parent or not model:FindFirstChild("ClickPart") or not Farm.Enabled

	return true
end

-- ===================== attack =====================
local function attackOnce(target)
	if not canAct() then return false end
	local hrpPart = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
	if not hrpPart then return false end
	local _, myHrp = character()
	if not myHrp then return false end

	-- silent: aim Mouse.Hit at target (hook spoofs Hit; camera untouched)
	local hit = CFrame.lookAt(hrpPart.Position, Workspace.CurrentCamera.CFrame.Position)

	-- working.lua kill position:
	-- HRP.CFrame = npc.HRP.CFrame + npc.HRP.CFrame.lookVector * DistanceFromNpc
	if not Farm.RangeMode then
		myHrp.CFrame = hrpPart.CFrame + hrpPart.CFrame.LookVector * (-math.abs(Farm.DistanceFromNpc))
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

	-- E/R/F/C only if each toggle is on (Mouse1 always)
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

		if tick() - lastApply > 1.5 then
			lastApply = tick()
			pcall(Farm.FetchStages)
		end

		pcall(ensureEquip)
		pcall(ensureMask)
		pcall(ensureArata)
		pcall(ensureRangeAfterEquip)

		-- corpse — working.lua collect on the dead NPC
		if Farm.CorpseNpc and Farm.CollectCorpses then
			local npc = Farm.CorpseNpc
			Farm.CorpseNpc = nil
			if npc and npc.Parent then
				pcall(collectCorpse, npc)
			end
			task.wait(0.05)
			continue
		end

		-- reputation / trainer side jobs
		if Farm.ReputationFarm or Farm.ReputationCashout then
			if pcall(Farm.TryReputationTick) then
				task.wait(0.5)
				continue
			end
		end

		local target = Farm.CurrentTarget
		if target then
			local tHum = target:FindFirstChildOfClass("Humanoid")
			if not tHum or tHum.Health <= 0 or not target.Parent then
				Farm.Stats.kills += 1
				if Farm.CollectCorpses and not target.Name:find("Gyakusatsu", 1, true) then
					Farm.CorpseNpc = target
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
				-- working.lua approach: keep re-tp to lookVector offset while killing
				local isBoss = (target.Name == "Gyakusatsu") or (target.Parent and target.Parent.Name == "GyakusatsuSpawn")
				local dest
				if isBoss then
					dest = part.CFrame * CFrame.Angles(math.rad(90), 0, 0) + Vector3.new(0, 8, 0)
				else
					dest = part.CFrame + part.CFrame.LookVector * (-math.abs(Farm.DistanceFromNpc))
				end

				local dist = (part.Position - hrp.Position).Magnitude
				if dist > 20 then
					teleportTo(dest)
				elseif dist > 5 or tick() - Farm.LastAttack >= Farm.FarmDelay then
					-- keep glued like z4gs kill loop
					pcall(function()
						local _, myHrp = character()
						if myHrp and not Farm.RangeMode then
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

function Farm.Start()
	if Farm.Enabled then return end
	Farm.Enabled = true
	refreshPlayerChars()
	Farm.FetchStages()
	getAuthKey()
	setNoclip(Farm.Noclip)
	Farm._rangedOn = false
	Farm.LastEquip = 0
	Farm._task = task.spawn(function()
		local ok, err = pcall(loop)
		if not ok then
			warn("[Autofarm] crashed:", err)
			Farm.Enabled = false
		end
	end)
	if Farm.AutoTrainer then
		pcall(Farm.TrainLoop)
	end
	print("[Autofarm] started | group=" .. tostring(Farm.Group)
		.. " | stage=" .. tostring(Farm.Stage) .. "/" .. stageWord()
		.. " | range=" .. tostring(Farm.RangeMode)
		.. " | stages=" .. #Farm.AvailableStages)
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

-- ===================== Trainer (working.lua) =====================
local function getRemotes()
	return game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
end

local function grabTrainersList()
	if Farm.TrainersList then return Farm.TrainersList end
	local team = pf() and pf().Customization and pf().Customization.Team.Value or "CCG"
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

function Farm.TrainOnce()
	local remotes = getRemotes()
	if not remotes then return end
	local folder = pf()
	if not folder then return end
	local trainers = folder:FindFirstChild("Trainers")
	if not trainers then return end
	local team = folder.Customization and folder.Customization.Team.Value or "CCG"
	local trainerName = trainers[team .. "Trainer"] and trainers[team .. "Trainer"].Value

	local tkey
	local conn
	pcall(function()
		conn = LocalPlayer.Backpack.DescendantAdded:Connect(function(obj)
			if tostring(obj) == "TSCodeVal" and obj:IsA("StringValue") then
				tkey = obj.Value
			end
		end)
	end)

	local result
	pcall(function()
		result = remotes.Trainers.RequestTraining:InvokeServer()
	end)

	if conn then
		pcall(function() conn:Disconnect() end)
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
		if list and trainerName then
			local curProg = trainers[trainerName] and trainers[trainerName]:FindFirstChild("Progress")
			local curVal = curProg and tonumber(curProg.Value) or 100
			if curVal >= 100 then
				for _, v in ipairs(trainers:GetDescendants()) do
					if list and table.find(list, v.Name) then
						local prog = v:FindFirstChild("Progress")
						if prog and tonumber(prog.Value) < 100 then
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
	end
	return result
end

function Farm.TrainLoop()
	if Farm._trainTask then return end
	Farm._trainTask = task.spawn(function()
		while Farm.Enabled and Farm.AutoTrainer do
			pcall(Farm.TrainOnce)
			task.wait(1)
		end
		Farm._trainTask = nil
	end)
end

function Farm.StopTrain()
	if Farm._trainTask then
		task.cancel(Farm._trainTask)
		Farm._trainTask = nil
	end
end

-- ===================== Reputation (working.lua) =====================
function Farm.DoReputationQuest(getQuest)
	local remotes = getRemotes()
	if not remotes then return end
	local folder = pf()
	if not folder then return end
	local team = folder.Customization and folder.Customization.Team.Value or "Ghoul"
	local npc = (team == "Ghoul") and Workspace:FindFirstChild("Anteiku") and Workspace.Anteiku:FindFirstChild("Yoshimura")
		or Workspace:FindFirstChild("CCGBuilding") and Workspace.CCGBuilding:FindFirstChild("Yoshitoki")
	if not npc or not npc:FindFirstChild("HumanoidRootPart") then return end

	teleportTo(npc.HumanoidRootPart.CFrame)
	pcall(function()
		remotes.Ally.AllyInfo:InvokeServer()
	end)
	task.wait(0.3)
	local ind = npc:FindFirstChild("TaskIndicator")
	local cd = ind and ind:FindFirstChild("ClickDetector")
	if cd then
		pcall(function() fireclickdetector(cd) end)
	end

	local _, hrp = character()
	if not hrp then return end
	if (npc.HumanoidRootPart.Position - hrp.Position).Magnitude > 20 then return end

	if getQuest then
		local remote = remotes:FindFirstChild(npc.Name)
		if remote and remote:FindFirstChild("Task") then
			pcall(function() remote.Task:InvokeServer() end)
			task.wait(0.2)
			pcall(function() remote.Task:InvokeServer() end)
		end
	else
		pcall(function() remotes.ReputationCashOut:InvokeServer() end)
		Farm.LastCashout = tick()
	end
end

function Farm.TryReputationTick()
	if Farm.ReputationCashout and tick() - Farm.LastCashout > 7200 then
		Farm.DoReputationQuest(false)
		return true
	end
	if Farm.ReputationFarm then
		local folder = pf()
		local cq = folder and folder:FindFirstChild("CurrentQuest")
		local complete = cq and cq:FindFirstChild("Complete")
		local need = complete and complete:FindFirstChild("Aogiri Member")
		if not need then
			Farm.DoReputationQuest(true)
			return true
		end
		local val = need:FindFirstChild("Value")
		local max = need:FindFirstChild("Max")
		if val and max and tonumber(val.Value) >= tonumber(max.Value) then
			Farm.DoReputationQuest(true)
			return true
		end
	end
	return false
end

function Farm.Status()
	local st = currentStageInfo()
	return string.format(
		"on=%s target=%s kills=%d attacks=%d collects=%d stage=%s ranged=%s key=%s train=%s rep=%s",
		tostring(Farm.Enabled),
		Farm.CurrentTarget and Farm.CurrentTarget.Name or "-",
		Farm.Stats.kills, Farm.Stats.attacks, Farm.Stats.collects,
		tostring(Farm.Stage) .. (st and ("/" .. tostring(st.nick)) or ""),
		tostring(Farm._rangedOn),
		Farm.RemoteKey and (#Farm.RemoteKey .. "ch") or "?",
		tostring(Farm.AutoTrainer),
		tostring(Farm.ReputationFarm or Farm.ReputationCashout)
	)
end

task.defer(function()
	Farm.FetchStages()
	getAuthKey()
end)

return Farm
