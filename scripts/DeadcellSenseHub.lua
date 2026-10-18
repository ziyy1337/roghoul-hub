--// roghoul-hub // Deadcell + Sense + NPC ESP + Aim
local RAW = "https://raw.githubusercontent.com/ziyy1337/roghoul-hub/main/"
local RunService = game:GetService("RunService")

local function req(path)
	local src = game:HttpGet(RAW .. path)
	local fn = loadstring(src)
	if not fn then
		error("compile failed: " .. path)
	end
	return fn()
end

local library = req("Deadcell/source_modified.lua")
local Sense = req("scripts/esp/Sense/source.lua")
local NpcEsp = req("scripts/esp/NpcEsp.lua")
local GyakuEsp = req("scripts/GyakusatsuHeartESP.lua")
local Aim = req("scripts/Aimbot.lua")
local Farm = req("scripts/Autofarm.lua")

Aim.UseBuiltinAimKey = false
Aim.Enabled = false
Aim.SilentAim = false
Aim.CameraAim = false
GyakuEsp.Enabled = false

-- Sense off until user enables (avoids stack-overflow spam with hooks)
local enemy = Sense.teamSettings.enemy
enemy.enabled = false
enemy.box = true
enemy.boxColor = { Color3.fromRGB(255, 80, 80), 1 }
enemy.boxOutline = true
enemy.healthBar = true
enemy.name = true
enemy.distance = true
enemy.tracer = false
enemy.chams = false
enemy.offScreenArrow = true
Sense.teamSettings.friendly.enabled = false
Sense.sharedSettings.limitDistance = false
Sense.sharedSettings.maxDistance = 2500
Sense.sharedSettings.textSize = 14

local window = library:new_window({ size = Vector2.new(620, 470) })

----------------------------------------------------------------
-- VISUALS
----------------------------------------------------------------
local visuals = window:new_page({ name = "Visuals" })

local playerEsp = visuals:new_section({ name = "Players", size = "Fill" })
playerEsp:new_toggle({
	name = "Enabled",
	flag = "esp_enabled",
	state = true,
	callback = function(state)
		enemy.enabled = state
		if state then
			pcall(function() Sense.Load() end)
		end
	end,
})
playerEsp:new_toggle({ name = "Box", flag = "esp_box", state = true, callback = function(s) enemy.box = s end })
playerEsp:new_toggle({ name = "Health Bar", flag = "esp_health", state = true, callback = function(s) enemy.healthBar = s end })
playerEsp:new_toggle({ name = "Name", flag = "esp_name", state = true, callback = function(s) enemy.name = s end })
playerEsp:new_toggle({ name = "Distance", flag = "esp_distance", state = true, callback = function(s) enemy.distance = s end })
playerEsp:new_toggle({ name = "Tracers", flag = "esp_tracer", state = false, callback = function(s) enemy.tracer = s end })
playerEsp:new_toggle({ name = "Chams", flag = "esp_chams", state = false, callback = function(s) enemy.chams = s end })
playerEsp:new_toggle({ name = "Off-screen Arrows", flag = "esp_arrows", state = true, callback = function(s) enemy.offScreenArrow = s end })
playerEsp:new_slider({
	name = "Max Distance",
	flag = "esp_dist",
	min = 100,
	max = 5000,
	default = 2500,
	callback = function(v)
		Sense.sharedSettings.maxDistance = v
		Sense.sharedSettings.limitDistance = v < 5000
	end,
})
playerEsp:new_colorpicker({
	name = "Player Color",
	flag = "esp_color",
	default = enemy.boxColor[1],
	callback = function(c)
		enemy.boxColor[1] = c
		enemy.tracerColor[1] = c
		enemy.chamsOutlineColor[1] = c
	end,
})

local npcSec = visuals:new_section({ name = "NPCs", size = "Fill", side = "right" })
npcSec:new_toggle({ name = "Enabled", flag = "npc_enabled", state = true, callback = function(s) NpcEsp.Enabled = s end })
npcSec:new_toggle({ name = "Names", flag = "npc_names", state = true, callback = function(s) NpcEsp.ShowNames = s end })
npcSec:new_toggle({ name = "Health", flag = "npc_hp", state = true, callback = function(s) NpcEsp.ShowHealth = s end })
npcSec:new_toggle({ name = "Boxes", flag = "npc_box", state = true, callback = function(s) NpcEsp.ShowBox = s end })
npcSec:new_slider({
	name = "Distance",
	flag = "npc_dist",
	min = 100,
	max = 8000,
	default = 2500,
	callback = function(v) NpcEsp.MaxDistance = v end,
})
npcSec:new_seperator({ name = "Group Colors" })
for _, groupName in ipairs({ "Human", "Ghoul", "CCG", "Aggro", "Boss", "Named" }) do
	local g = NpcEsp.Groups[groupName]
	npcSec:new_toggle({
		name = groupName,
		flag = "npc_g_" .. groupName,
		state = true,
		callback = function(s) g.enabled = s end,
	})
	npcSec:new_colorpicker({
		name = groupName .. " color",
		flag = "npc_gc_" .. groupName,
		default = g.color,
		callback = function(c) g.color = c end,
	})
end
npcSec:new_button({ name = "Rescan NPCs", flag = "npc_rescan", callback = function() NpcEsp.Refresh() end })

-- Gyakusatsu map markers (off by default)
local gyakuSec = visuals:new_section({ name = "Gyakusatsu", size = 220 })
gyakuSec:new_toggle({
	name = "Show Heart Map Markers",
	flag = "gyaku_esp",
	state = false,
	callback = function(s) GyakuEsp.Enabled = s end,
})
gyakuSec:new_toggle({ name = "Hearts", flag = "gyaku_hearts", state = true, callback = function(s) GyakuEsp.ShowHearts = s end })
gyakuSec:new_toggle({ name = "Head", flag = "gyaku_head", state = true, callback = function(s) GyakuEsp.ShowHead = s end })
gyakuSec:new_toggle({ name = "Station", flag = "gyaku_station", state = true, callback = function(s) GyakuEsp.ShowStation = s end })
gyakuSec:new_toggle({ name = "Lines", flag = "gyaku_beams", state = true, callback = function(s) GyakuEsp.ShowBeams = s end })
gyakuSec:new_colorpicker({
	name = "Heart Color",
	flag = "gyaku_color",
	default = GyakuEsp.HeartColor,
	callback = function(c) GyakuEsp.SetColor("heart", c) end,
})

----------------------------------------------------------------
-- COMBAT
----------------------------------------------------------------
local combat = window:new_page({ name = "Combat" })

-- Left: switches
local main = combat:new_section({ name = "Aimbot", size = "Fill" })
main:new_toggle({
	name = "Aimbot",
	flag = "aim_enabled",
	state = false,
	callback = function(s) Aim.SetAimEnabled(s) end,
})
main:new_toggle({
	name = "Silent Aim",
	flag = "aim_silent",
	state = false,
	callback = function(s) Aim.SilentAim = s end,
})
main:new_toggle({
	name = "Camera Lock",
	flag = "aim_camera",
	state = false,
	callback = function(s) Aim.CameraAim = s end,
})
main:new_toggle({
	name = "Sticky Aim",
	flag = "aim_sticky",
	state = true,
	callback = function(s)
		Aim.StickyAim = s
		if not s then Aim.ClearSticky() end
	end,
})
main:new_keybind({
	name = "Aim Keybind",
	flag = "aim_keybind",
	default = Enum.KeyCode.MouseBackButton,
	mode = "Toggle",
	ignore = true,
	callback = function(s) Aim.SetAimEnabled(s == true) end,
})
main:new_dropdown({
	name = "Key Mode",
	flag = "aim_key_mode",
	options = { "Toggle", "Hold" },
	default = "Toggle",
	callback = function(v) Aim.AimKeyMode = v end,
})
main:new_button({
	name = "Clear Sticky Lock",
	flag = "aim_clear_sticky",
	callback = function() Aim.ClearSticky() end,
})

-- Right: FOV (always drawn when that feature is on)
local fovSec = combat:new_section({ name = "FOV", size = "Fill", side = "right" })
fovSec:new_toggle({
	name = "Show Silent FOV",
	flag = "fov_silent_show",
	state = true,
	callback = function(s) Aim.ShowSilentFov = s end,
})
fovSec:new_slider({
	name = "Silent FOV (deg)",
	flag = "fov_silent",
	min = 10,
	max = 360,
	default = 180,
	callback = function(v) Aim.SilentFOV = v end,
})
fovSec:new_colorpicker({
	name = "Silent FOV Color",
	flag = "fov_silent_color",
	default = Aim.SilentFovColor,
	callback = function(c) Aim.SilentFovColor = c end,
})
fovSec:new_toggle({
	name = "Show Camera FOV",
	flag = "fov_cam_show",
	state = true,
	callback = function(s) Aim.ShowCameraFov = s end,
})
fovSec:new_slider({
	name = "Camera FOV (deg)",
	flag = "fov_cam",
	min = 10,
	max = 360,
	default = 90,
	callback = function(v) Aim.CameraFOV = v end,
})
fovSec:new_colorpicker({
	name = "Camera FOV Color",
	flag = "fov_cam_color",
	default = Aim.CameraFovColor,
	callback = function(c) Aim.CameraFovColor = c end,
})
fovSec:new_toggle({ name = "Target Line + Dot", flag = "aim_line", state = true, callback = function(s) Aim.ShowTargetLine = s end })
fovSec:new_colorpicker({
	name = "Line Color",
	flag = "aim_line_color",
	default = Aim.LineColor,
	callback = function(c)
		Aim.LineColor = c
		Aim.DotColor = c
	end,
})
fovSec:new_slider({
	name = "Line thickness",
	flag = "aim_line_thick",
	min = 1,
	max = 5,
	default = 2,
	text = "[value]px",
	callback = function(v) Aim.LineThickness = v end,
})

-- Left lower: prediction (ping based)
local pred = combat:new_section({ name = "Prediction (ping)", size = 300 })
pred:new_dropdown({
	name = "Mode",
	flag = "aim_pred_mode",
	options = { "Off", "Auto", "Manual" },
	default = "Auto",
	callback = function(v) Aim.PredictionMode = v end,
})
pred:new_slider({
	name = "Auto: ping x",
	flag = "aim_pred_scale",
	min = 10,
	max = 300,
	default = 100,
	text = "[value]/100",
	callback = function(v) Aim.PredictionAutoScale = v / 100 end,
})
pred:new_slider({
	name = "Manual: + sec on ping",
	flag = "aim_pred_manual",
	min = 0,
	max = 100,
	default = 5,
	text = "+[value]/100s",
	callback = function(v) Aim.PredictionManual = v / 100 end,
})
pred:new_button({
	name = "Show live ping (console)",
	flag = "aim_ping_print",
	callback = function()
		local ms = Aim.GetPingSeconds() * 1000
		print(string.format("[Aimbot] ping=%.1f ms  lead=%.3fs", ms, Aim.GetPredictionTime(0)))
	end,
})

-- Right lower: feel
local feel = combat:new_section({ name = "Filters & Feel", size = 300, side = "right" })
feel:new_toggle({ name = "Team Check", flag = "aim_team", state = false, callback = function(s) Aim.TeamCheck = s end })
feel:new_toggle({ name = "Wall Check", flag = "aim_wall", state = false, callback = function(s) Aim.WallCheck = s end })
feel:new_slider({
	name = "Cam Smoothness",
	flag = "aim_smooth",
	min = 5,
	max = 100,
	default = 45,
	text = "[value]%",
	callback = function(v) Aim.Smoothness = v / 100 end,
})
feel:new_dropdown({
	name = "Bone",
	flag = "aim_bone",
	options = { "Head", "HumanoidRootPart" },
	default = "Head",
	callback = function(v) Aim.Bone = v end,
})
feel:new_toggle({ name = "Change game FOV", flag = "cam_fov_on", state = false, callback = function(s) Aim.UseCameraFov = s end })
feel:new_slider({
	name = "Game FOV value",
	flag = "cam_fov",
	min = 30,
	max = 120,
	default = 70,
	callback = function(v) Aim.CameraFieldOfView = v end,
})

----------------------------------------------------------------
-- AUTOFARM (placeholders only — no logic yet)
----------------------------------------------------------------
-- AUTOFARM
----------------------------------------------------------------
Farm.FetchStages()
local stageOpts = { "None" }
for _, s in ipairs(Farm.AvailableStages) do
	table.insert(stageOpts, tostring(s.id))
end
if #stageOpts == 1 then
	-- HUD not ready yet: at least offer 1-2
	stageOpts = { "None", "1", "2" }
end

local farm = window:new_page({ name = "Autofarm" })

local farmMain = farm:new_section({ name = "General", size = 240 })
farmMain:new_button({
	name = "Start Autofarm",
	flag = "farm_start",
	callback = function() Farm.Start() end,
})
farmMain:new_button({
	name = "Stop Autofarm",
	flag = "farm_stop",
	callback = function() Farm.Stop() end,
})
farmMain:new_toggle({
	name = "Auto Attack",
	flag = "farm_attack",
	state = true,
	callback = function(s) Farm.AutoAttack = s end,
})
farmMain:new_toggle({
	name = "Auto Collect",
	flag = "farm_collect",
	state = false,
	callback = function(s) Farm.AutoCollect = s end,
})
farmMain:new_toggle({
	name = "Collect Corpses (on kill)",
	flag = "farm_corpses",
	state = true,
	callback = function(s) Farm.CollectCorpses = s end,
})
farmMain:new_toggle({
	name = "Noclip Fly",
	flag = "farm_noclip",
	state = true,
	callback = function(s) Farm.Noclip = s end,
})
farmMain:new_slider({
	name = "Attack Delay",
	flag = "farm_delay",
	min = 15,
	max = 50,
	default = 5,
	text = "[value]/10s",
	callback = function(v) Farm.FarmDelay = v / 10 end,
})
farmMain:new_slider({
	name = "Fly Speed",
	flag = "farm_speed",
	min = 30,
	max = 200,
	default = 80,
	text = "[value]",
	callback = function(v) Farm.MoveSpeed = v end,
})

-- Attacks (Mouse1 always active) — matches user request
local farmAtk = farm:new_section({ name = "Attacks (Mouse1 always active)", size = 280 })
farmAtk:new_toggle({
	name = "Attack E",
	flag = "farm_atk_e",
	state = false,
	callback = function(s) Farm.AttackE = s end,
})
farmAtk:new_toggle({
	name = "Attack R",
	flag = "farm_atk_r",
	state = false,
	callback = function(s) Farm.AttackR = s end,
})
farmAtk:new_toggle({
	name = "Attack F",
	flag = "farm_atk_f",
	state = false,
	callback = function(s) Farm.AttackF = s end,
})
farmAtk:new_toggle({
	name = "Attack C",
	flag = "farm_atk_c",
	state = false,
	callback = function(s) Farm.AttackC = s end,
})
farmAtk:new_toggle({
	name = "Range Mode",
	flag = "farm_range_mode",
	state = false,
	callback = function(s)
		Farm.RangeMode = s
		if s then
			Farm.WeaponMode = "Ranged"
		end
	end,
})
farmAtk:new_toggle({
	name = "Auto Arata",
	flag = "farm_arata",
	state = false,
	callback = function(s) Farm.AutoArata = s end,
})
farmAtk:new_toggle({
	name = "Auto Arata Refill",
	flag = "farm_arata_refill",
	state = false,
	callback = function(s) Farm.AutoArataRefill = s end,
})
farmAtk:new_toggle({
	name = "Auto Mask",
	flag = "farm_mask",
	state = false,
	callback = function(s) Farm.AutoMask = s end,
})
farmAtk:new_button({
	name = "Equip Mask (M)",
	flag = "farm_mask_now",
	callback = function() Farm.ForceMask() end,
})
farmAtk:new_button({
	name = "Open Arata (Zero)",
	flag = "farm_arata_now",
	callback = function() Farm.OpenArata() end,
})

local farmTrain = farm:new_section({ name = "Training / Reputation", size = 200 })
farmTrain:new_toggle({
	name = "Auto Trainer",
	flag = "farm_trainer",
	state = false,
	callback = function(s)
		Farm.AutoTrainer = s
		-- works without Start Autofarm
		if s then
			Farm.TrainLoop()
		else
			Farm.StopTrain()
		end
	end,
})
farmTrain:new_toggle({
	name = "Reputation Farm",
	flag = "farm_rep_farm",
	state = false,
	callback = function(s) Farm.ReputationFarm = s end,
})
farmTrain:new_toggle({
	name = "Auto Reputation Cashout",
	flag = "farm_rep_cash",
	state = false,
	callback = function(s) Farm.ReputationCashout = s end,
})
farmTrain:new_button({
	name = "Print Train Status",
	flag = "farm_train_status",
	callback = function()
		print("[Autofarm]", Farm.Status())
		print("AutoTrainer=", Farm.AutoTrainer, "RepFarm=", Farm.ReputationFarm, "Cashout=", Farm.ReputationCashout)
	end,
})

local farmTarget = farm:new_section({ name = "Targets", size = "Fill", side = "right" })
farmTarget:new_dropdown({
	name = "NPC Group",
	flag = "farm_group",
	options = { "Human", "Ghoul", "CCG", "Aggro", "Boss", "Gyakusatsu", "Any" },
	default = "Ghoul",
	callback = function(v) Farm.Group = v end,
})
farmTarget:new_toggle({
	name = "Prefer Nearest",
	flag = "farm_nearest",
	state = true,
	callback = function(s) Farm.PreferNearest = s end,
})
farmTarget:new_toggle({
	name = "Prefer Lowest HP",
	flag = "farm_lowhp",
	state = false,
	callback = function(s) Farm.PreferLowestHP = s end,
})
farmTarget:new_seperator({ name = "Bosses (z4gs)" })
farmTarget:new_toggle({
	name = "Gyakusatsu (lvl 1250+)",
	flag = "boss_gya",
	state = false,
	callback = function(s) Farm.BossFarm["Gyakusatsu"] = s end,
})
farmTarget:new_toggle({
	name = "Eto Yoshimura (1250+)",
	flag = "boss_eto",
	state = false,
	callback = function(s) Farm.BossFarm["Eto Yoshimura"] = s end,
})
farmTarget:new_toggle({
	name = "Koutarou Amon (750+)",
	flag = "boss_amon",
	state = false,
	callback = function(s) Farm.BossFarm["Koutarou Amon"] = s end,
})
farmTarget:new_toggle({
	name = "Nishiki Nishio (250+)",
	flag = "boss_nishi",
	state = false,
	callback = function(s) Farm.BossFarm["Nishiki Nishio"] = s end,
})
farmTarget:new_slider({
	name = "Distance from NPC",
	flag = "farm_dist_npc",
	min = 0,
	max = 8,
	default = 5,
	text = "[value]",
	callback = function(v) Farm.DistanceFromNpc = v end,
})
farmTarget:new_slider({
	name = "Distance from Bosses",
	flag = "farm_dist_boss",
	min = 0,
	max = 15,
	default = 8,
	text = "[value]",
	callback = function(v) Farm.DistanceFromBoss = v end,
})
farmTarget:new_toggle({
	name = "Skills on Bosses (E/R/F/C)",
	flag = "farm_boss_skills",
	state = true,
	callback = function(s) Farm.SkillsOnBoss = s end,
})
farmTarget:new_seperator({ name = "Searches entire map (no range cap)" })

local farmLoadout = farm:new_section({ name = "Loadout (auto)", size = 260 })
farmLoadout:new_dropdown({
	name = "Stage",
	flag = "farm_stage",
	options = stageOpts,
	default = stageOpts[2] or "1",
	callback = function(v)
		if v == "None" then Farm.Stage = "" else Farm.Stage = v end
	end,
})
farmLoadout:new_dropdown({
	name = "Weapon Mode",
	flag = "farm_wepmode",
	options = { "Auto", "Blade", "Ranged" },
	default = "Auto",
	callback = function(v)
		Farm.WeaponMode = v
		if v == "Ranged" then
			Farm.RangeMode = true
		elseif v == "Blade" or v == "Auto" then
			Farm.RangeMode = false
		end
	end,
})
farmLoadout:new_button({
	name = "Refresh Stages",
	flag = "farm_refresh_stages",
	callback = function()
		local st = Farm.FetchStages()
		print("[Autofarm] stages=" .. #st)
		for _, s in ipairs(st) do
			print(string.format("  Stage %s | %s | modes=%s", s.id, s.nick, s.modes))
		end
		print("[Autofarm]", Farm.Status())
	end,
})
farmLoadout:new_button({
	name = "Apply Loadout Now",
	flag = "farm_apply",
	callback = function() Farm.ApplyLoadoutNow() end,
})
farmLoadout:new_button({
	name = "Toggle Kagune (Q)",
	flag = "farm_kagune_q",
	callback = function() Farm.KaguneToggleNow() end,
})

local farmMisc = farm:new_section({ name = "Status", size = 260, side = "right" })
farmMisc:new_button({
	name = "Print Farm Status",
	flag = "farm_status",
	callback = function() print("[Autofarm]", Farm.Status()) end,
})
farmMisc:new_button({
	name = "Show Quest / Stats",
	flag = "farm_stats",
	callback = function()
		print("[Autofarm]", Farm.GetStatsText())
		print("[Autofarm] Quest:", Farm.GetQuestText())
	end,
})
farmMisc:new_button({
	name = "List My Stages",
	flag = "farm_list_stages",
	callback = function()
		for _, s in ipairs(Farm.FetchStages()) do
			print(string.format("Stage %s | %s | modes=%s", s.id, s.nick, tostring(s.modes)))
		end
	end,
})

-- live stats ticker (menu-visible via console + flag)
local lastStats = 0
RunService.Heartbeat:Connect(function()
	if not Farm.Enabled then return end
	if tick() - lastStats < 8 then return end
	lastStats = tick()
	library.flags.farm_stats_text = Farm.GetStatsText()
	print("[stats]", Farm.GetStatsText())
end)

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
local settings = window:new_page({ name = "Settings" })
local menu = settings:new_section({ name = "Menu", size = "Half" })
menu:new_keybind({
	name = "Open / Close Menu",
	flag = "menu_bind",
	default = Enum.KeyCode.Delete,
	mode = "Toggle",
	ignore = true,
	callback = function()
		library:Close()
	end,
})
menu:new_button({
	name = "Toggle Menu Now",
	flag = "menu_toggle_btn",
	callback = function()
		library:Close()
	end,
})
menu:new_toggle({
	name = "Show Keybinds List",
	flag = "keybind_list",
	callback = function(state)
		window:set_keybind_list_visibility(state)
	end,
})

	-- Sense loads only when "Enabled" is toggled on (see Visuals → Players)
	return library, Sense, NpcEsp, GyakuEsp, Aim, Farm
