--// roghoul-hub // Deadcell + Sense + NPC ESP + Aim
-- Loads from this repo so nothing depends on dead hosts.

local RAW = "https://raw.githubusercontent.com/ziyy1337/roghoul-hub/main/"

local library = loadstring(game:HttpGet(RAW .. "Deadcell/source_modified.lua"))()
local Sense = loadstring(game:HttpGet(RAW .. "scripts/esp/Sense/source.lua"))()
local NpcEsp = loadstring(game:HttpGet(RAW .. "scripts/esp/NpcEsp.lua"))()
local Aim = loadstring(game:HttpGet(RAW .. "scripts/Aimbot.lua"))()

-- menu keybind only opens/closes UI — never touches aimbot
Aim.UseBuiltinAimKey = false
Aim.Enabled = false
Aim.SilentAim = false

-- Sense defaults
local enemy = Sense.teamSettings.enemy
enemy.enabled = true
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

local window = library:new_window({ size = Vector2.new(600, 460) })

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
		if state then pcall(function() Sense.Load() end) end
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

----------------------------------------------------------------
-- COMBAT (split sections, no numbered labels)
----------------------------------------------------------------
local combat = window:new_page({ name = "Combat" })

-- Left: main switches
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
	name = "Sticky Aim (stay on one target)",
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

-- Right top: prediction
local pred = combat:new_section({ name = "Prediction", size = "Fill", side = "right" })
pred:new_dropdown({
	name = "Mode",
	flag = "aim_pred_mode",
	options = { "Off", "Auto", "Manual" },
	default = "Auto",
	callback = function(v) Aim.PredictionMode = v end,
})
pred:new_slider({
	name = "Manual Lead (sec)",
	flag = "aim_pred_manual",
	min = 0,
	max = 100,
	default = 15,
	text = "[value]/100s",
	callback = function(v) Aim.PredictionManual = v / 100 end,
})
pred:new_slider({
	name = "Auto Speed (studs/s)",
	flag = "aim_pred_speed",
	min = 50,
	max = 1200,
	default = 350,
	callback = function(v) Aim.PredictionSpeed = v end,
})
pred:new_slider({
	name = "Y Offset",
	flag = "aim_pred_y",
	min = -50,
	max = 50,
	default = 0,
	callback = function(v) Aim.PredictionYBoost = v / 10 end,
})

-- Left lower: indicators
local ind = combat:new_section({ name = "Indicators", size = 280 })
ind:new_toggle({ name = "Target Line + Dot", flag = "aim_line", state = true, callback = function(s) Aim.ShowTargetLine = s end })
ind:new_colorpicker({
	name = "Line Color",
	flag = "aim_line_color",
	default = Aim.LineColor,
	callback = function(c)
		Aim.LineColor = c
		Aim.DotColor = c
	end,
})
ind:new_toggle({ name = "FOV Circle", flag = "aim_fov_circle", state = true, callback = function(s) Aim.ShowFov = s end })
ind:new_colorpicker({
	name = "FOV Color",
	flag = "aim_fov_color",
	default = Aim.FovColor,
	callback = function(c) Aim.FovColor = c end,
})
ind:new_slider({
	name = "FOV Cone (deg)",
	flag = "aim_fov",
	min = 10,
	max = 360,
	default = 180,
	callback = function(v) Aim.FOV = v end,
})

-- Right lower: filters + feel
local feel = combat:new_section({ name = "Filters & Feel", size = 280, side = "right" })
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
feel:new_toggle({ name = "Use Camera FOV", flag = "cam_fov_on", state = false, callback = function(s) Aim.UseCameraFov = s end })
feel:new_slider({
	name = "Camera FOV",
	flag = "cam_fov",
	min = 30,
	max = 120,
	default = 70,
	callback = function(v) Aim.CameraFov = v end,
})
feel:new_button({ name = "Clear Sticky Lock", flag = "aim_clear_sticky", callback = function() Aim.ClearSticky() end })

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

pcall(function() Sense.Load() end)

return library, Sense, NpcEsp, Aim
