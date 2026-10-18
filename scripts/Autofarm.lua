--// Ro-Ghoul Autofarm
-- Noclip-flight to targets, official KeyEvent combat, stages from HUD.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local KEY_AUTH = "操你💦💔🍑👌💦操你💦💔🍑👌💦💔🍑👌💦💔🍑👌💔🍑👌💦💔🍑👌"

local Farm = {
	Enabled = false,
	AutoAttack = true,
	AutoCollect = false,
	CollectCorpses = true,

	-- movement
	FarmDelay = 0.5,     -- attack gap seconds
	MoveSpeed = 80,      -- fly speed studs/sec toward target
	Noclip = true,

	-- targets
	Group = "Ghoul",
	PreferNearest = true,
	PreferLowestHP = false,
	-- no max distance: always full-map search
	MaxDistance = 1e9,

	-- loadout (always applied)
	Quinque = "IXA",     -- "" = none
	Stage = "1",         -- fetched from HUD; "1".."N"
	WeaponMode = "Auto", -- Auto | Blade | Ranged

	-- runtime
	CurrentTarget = nil,
	CorpseDrop = nil,
	LastAttack = 0,
	LastSpecial = 0,
	Stats = { attacks = 0, collects = 0, kills = 0 },
	AvailableStages = {}, -- { {id="1", label="Stage 1", modes=2, nick="IXA"}, ... }
	_task = nil,
	_noclipConn = nil,
}

-- ===================== helpers =====================
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
	local rem = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Remotes")
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

-- ===================== stages (from HUD) =====================
function Farm.FetchStages()
	local stages = {}
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local hud = gui and gui:FindFirstChild("HUD")
	local frame = hud and hud:FindFirstChild("StagesFrame")
	local scroll = frame and frame:FindFirstChild("InfoScroll")
	if scroll then
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") or child:IsA("Frame") then
				local stageLbl = child:FindFirstChild("StageLabel")
				local modesLbl = child:FindFirstChild("ModesLabel")
				local nickLbl = child:FindFirstChild("NicknameLabel")
				if stageLbl and stageLbl:IsA("TextLabel") then
					local stageNum = string.match(stageLbl.Text, "(%d+)")
					local modeNum = modesLbl and string.match(modesLbl.Text, "MODE%(S%):%s*(%d+)") or "1"
					local nick = nickLbl and nickLbl.Text or child.Name
					-- skip template Example
					if child.Name ~= "Example" and stageNum then
						table.insert(stages, {
							id = stageNum,
							label = ("Stage %s"):format(stageNum),
							modes = tonumber(modeNum) or 1,
							nick = nick,
							node = child.Name,
						})
					end
				end
			end
		end
	end

	-- fallback: SpecialStat.CurStage
	if #stages == 0 then
		local folder = pf()
		local special = folder and folder:FindFirstChild("SpecialStat")
		local cur = special and special:FindFirstChild("CurStage")
		if cur then
			table.insert(stages, {
				id = tostring(cur.Value),
				label = ("Stage %s"):format(tostring(cur.Value)),
				modes = 2,
				nick = "?",
				node = "SpecialStat",
			})
		end
	end

	Farm.AvailableStages = stages
	if Farm.Stage == "" and stages[1] then
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

-- ===================== noclip =====================
local function setNoclip(on)
	if on and not Farm._noclipConn then
		Farm._noclipConn = RunService.Stepped:Connect(function()
			local c = LocalPlayer.Character
			if not c then return end
			for _, p in ipairs(c:GetDescendants()) do
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

local function flyTo(targetPos, dt)
	local _, hrp = character()
	if not hrp then return false end
	local delta = targetPos - hrp.Position
	local dist = delta.Magnitude
	if dist < 1.5 then return true end
	local speed = math.clamp(Farm.MoveSpeed, 20, 200)
	local step = math.min(speed * dt, dist)
	local dir = delta.Unit
	-- fly: keep Y so we don't sink, then level
	local goal = hrp.Position + dir * step
	pcall(function()
		hrp.CFrame = CFrame.new(goal) * (hrp.CFrame - hrp.CFrame.Position)
		hrp.AssemblyLinearVelocity = dir * step / math.max(dt, 1/60)
	end)
	return dist < 3
end

-- ===================== loadout (always) =====================
local appliedQuinque = nil
local appliedStage = nil
local appliedMode = nil

local function applyLoadout()
	local folder = pf()
	if not folder then return end
	local st = currentStageInfo()

	-- Quinque slot
	if Farm.Quinque ~= "" and Farm.Quinque ~= "None" then
		local slots = folder:FindFirstChild("WepSlots")
		if slots then
			local v1 = slots:FindFirstChild("WepSlot1") and slots.WepSlot1.Value or ""
			local v2 = slots:FindFirstChild("WepSlot2") and slots.WepSlot2.Value or ""
			local q = string.lower(Farm.Quinque)
			if v1 ~= "" and string.find(string.lower(v1), q, 1, true) and appliedQuinque ~= "1" then
				tapKey("1")
				appliedQuinque = "1"
			elseif v2 ~= "" and string.find(string.lower(v2), q, 1, true) and appliedQuinque ~= "2" then
				tapKey("2")
				appliedQuinque = "2"
			end
		end
	end

	-- Stage: only if we have a way to switch. Ro-Ghoul stages are usually
	-- selected in HUD (not KeyEvent). We store selection; ApplyLoadoutNow
	-- also tries HUD button click if present.
	if appliedStage ~= Farm.Stage then
		appliedStage = Farm.Stage
	end

	-- Weapon mode (C form): Blade vs Ranged
	local want = Farm.WeaponMode
	if want == "Auto" then
		want = (st and (st.modes or 1) >= 2) and "Ranged" or "Blade"
	end
	if want ~= appliedMode then
		local folder2 = pf()
		local can = folder2 and folder2:FindFirstChild("CanToggleWep")
		if want == "Ranged" and can and can.Value and readyCD("SpecialBonusCD") then
			tapKey("C")
		elseif want == "Blade" and can and can.Value and readyCD("SpecialBonusCD") then
			-- press C again only if we previously set Ranged
			if appliedMode == "Ranged" then
				tapKey("C")
			end
		end
		appliedMode = want
	end

	-- Kagune: Q when stage selected and ghoul-ish
	if Farm.KaguneOn and readyCD("ClickCD") then
		-- reserved: no reliable "kagune off" state; toggle only when user forces Apply
	end
end

function Farm.KaguneToggleNow()
	tapKey("Q")
end

-- try click stage button in HUD
local function clickStageInHud(stageId)
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local hud = gui and gui:FindFirstChild("HUD")
	local frame = hud and hud:FindFirstChild("StagesFrame")
	local scroll = frame and frame:FindFirstChild("InfoScroll")
	if not scroll then return false end
	for _, child in ipairs(scroll:GetChildren()) do
		local stageLbl = child:FindFirstChild("StageLabel")
		if stageLbl and stageLbl:IsA("TextLabel") then
			local n = string.match(stageLbl.Text, "(%d+)")
			if n == tostring(stageId) then
				-- find clickable
				for _, btn in ipairs(child:GetDescendants()) do
					if btn:IsA("TextButton") or btn:IsA("ImageButton") then
						pcall(function()
							btn.Activated:Fire()
						end)
						return true
					end
				end
			end
		end
	end
	return false
end

-- ===================== combat / targeting =====================
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
	appliedQuinque = nil
	appliedMode = nil
end)

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
		if readyCD("Special1CD") and tick() - Farm.LastSpecial > 1.0 then
			special = "E"
		elseif readyCD("Special2CD") and tick() - Farm.LastSpecial > 2.0 then
			special = "R"
		elseif readyCD("Special3CD") and tick() - Farm.LastSpecial > 3.0 then
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
					if dist <= Farm.MaxDistance then -- effectively infinite
						local group = classifyNPC(d)
						local match = false
						if Farm.Group == "Any" then
							match = true
						elseif Farm.Group == "Gyakusatsu" then
							match = group == "Gyakusatsu" or nm == "Gyakusatsu"
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
	end
	return best
end

local function watchKill(target)
	if not target then return end
	local hum = target:FindFirstChildOfClass("Humanoid")
	local part = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
	if hum and part and hum.Health <= 0 then
		Farm.Stats.kills += 1
		if Farm.CollectCorpses then
			Farm.CorpseDrop = { pos = part.Position, name = target.Name, t = tick() }
		end
		Farm.CurrentTarget = nil
	end
end

local function collectAt(pos)
	local _, hrp = character()
	if not hrp or not pos then return false end
	if (pos - hrp.Position).Magnitude > 8 then
		flyTo(pos, 0.05)
		return true
	end
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
			if part and (part.Position - myPos).Magnitude < 40 then
				flyTo(part.Position, 0.05)
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
	return false
end

-- ===================== loop =====================
local function stop()
	Farm.Enabled = false
	Farm.CurrentTarget = nil
	setNoclip(false)
	if Farm._task then
		task.cancel(Farm._task)
		Farm._task = nil
	end
	print("[Autofarm] stopped", Farm.Status())
end

local function loop()
	local lastApply = 0
	local lastT = tick()
	while Farm.Enabled do
		local now = tick()
		local dt = math.min(now - lastT, 0.1)
		lastT = now

		if not canAct() or not character() then
			task.wait(0.3)
			continue
		end

		if now - lastApply > 2 then
			lastApply = now
			pcall(Farm.FetchStages)
			pcall(applyLoadout)
		end

		-- corpse run
		if Farm.CorpseDrop and tick() - Farm.CorpseDrop.t < 15 then
			local _, hrp = character()
			if hrp and (Farm.CorpseDrop.pos - hrp.Position).Magnitude > 6 then
				flyTo(Farm.CorpseDrop.pos, dt)
				task.wait(0.03)
				continue
			else
				collectAt(Farm.CorpseDrop.pos)
				if tick() - Farm.CorpseDrop.t > 3 then
					Farm.CorpseDrop = nil
				end
				task.wait(0.2)
				continue
			end
		end

		if Farm.AutoCollect then
			collectNearby()
		end

		local target = Farm.CurrentTarget
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
				if dist > 6 then
					flyTo(part.Position, dt)
				elseif Farm.AutoAttack and tick() - Farm.LastAttack >= math.clamp(Farm.FarmDelay, 0.15, 5) then
					pcall(attackOnce, target)
				end
				watchKill(target)
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
	setNoclip(Farm.Noclip)
	pcall(applyLoadout)
	local st = currentStageInfo()
	Farm._task = task.spawn(function()
		local ok, err = pcall(loop)
		if not ok then
			warn("[Autofarm] loop crashed:", err)
			Farm.Enabled = false
		end
	end)
	print("[Autofarm] started"
		.. " | group=" .. tostring(Farm.Group)
		.. " | quinque=" .. tostring(Farm.Quinque)
		.. " | stage=" .. tostring(Farm.Stage)
		.. " | mode=" .. tostring(Farm.WeaponMode)
		.. " | stages=" .. tostring(#Farm.AvailableStages)
		.. (st and (" | nick=" .. tostring(st.nick)) or ""))
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
	appliedQuinque = nil
	appliedMode = nil
	pcall(applyLoadout)
	pcall(clickStageInHud, Farm.Stage)
	print("[Autofarm] loadout", Farm.Status())
end

function Farm.Status()
	local st = currentStageInfo()
	return string.format(
		"on=%s target=%s kills=%d attacks=%d collects=%d stages=%d cur=%s",
		tostring(Farm.Enabled),
		Farm.CurrentTarget and Farm.CurrentTarget.Name or "-",
		Farm.Stats.kills,
		Farm.Stats.attacks,
		Farm.Stats.collects,
		#Farm.AvailableStages,
		tostring(Farm.Stage) .. (st and ("/" .. tostring(st.nick)) or "")
	)
end

-- init stage list once
task.defer(function()
	Farm.FetchStages()
end)

return Farm
