--// roghoul-hub // Deadcell + Sense ESP + NPC ESP + Aim
-- Loads from this repo so nothing depends on dead hosts.

local RAW = "https://raw.githubusercontent.com/ziyy1337/roghoul-hub/main/"

-- 1) Deadcell UI
local library = loadstring(game:HttpGet(RAW .. "Deadcell/source_modified.lua"))()

-- 2) Player ESP (Sense)
local Sense = loadstring(game:HttpGet(RAW .. "scripts/esp/Sense/source.lua"))()

-- 3) NPC ESP (group colors)
local NpcEsp = loadstring(game:HttpGet(RAW .. "scripts/esp/NpcEsp.lua"))()

-- 4) Aimbot
local Aim = loadstring(game:HttpGet(RAW .. "scripts/Aimbot.lua"))()
Aim.UseBuiltinAimKey = false -- menu keybind owns aim toggle (side buttons OK)

-- Sense defaults
local enemy = Sense.teamSettings.enemy
enemy.enabled = true
enemy.box = true
enemy.boxColor = { Color3.fromRGB(255, 80, 80), 1 }
enemy.boxOutline = true
enemy.healthBar = true
enemy.healthText = false
enemy.name = true
enemy.distance = true
enemy.tracer = false
enemy.chams = false
enemy.offScreenArrow = true

local friendly = Sense.teamSettings.friendly
friendly.enabled = false

Sense.sharedSettings.limitDistance = false
Sense.sharedSettings.maxDistance = 2500
Sense.sharedSettings.textSize = 14

-- Menu
local window = library:new_window({ size = Vector2.new(580, 440) })

----------------------------------------------------------------
-- VISUALS
----------------------------------------------------------------
local visuals = window:new_page({ name = "Visuals" })

-- Player ESP
local playerEsp = visuals:new_section({ name = "Player ESP", size = "Fill" })

playerEsp:new_toggle({
	name = "Enabled",
	flag = "esp_enabled",
	state = true,
	callback = function(state)
		enemy.enabled = state
		if state then pcall(function() Sense.Load() end) end
	end,
})
playerEsp:new_toggle({
	name = "Box",
	flag = "esp_box",
	state = true,
	callback = function(state) enemy.box = state end,
})
playerEsp:new_toggle({
	name = "Health Bar",
	flag = "esp_health",
	state = true,
	callback = function(state) enemy.healthBar = state end,
})
playerEsp:new_toggle({
	name = "Name",
	flag = "esp_name",
	state = true,
	callback = function(state) enemy.name = state end,
})
playerEsp:new_toggle({
	name = "Distance",
	flag = "esp_distance",
	state = true,
	callback = function(state) enemy.distance = state end,
})
playerEsp:new_toggle({
	name = "Tracers",
	flag = "esp_tracer",
	state = false,
	callback = function(state) enemy.tracer = state end,
})
playerEsp:new_toggle({
	name = "Chams",
	flag = "esp_chams",
	state = false,
	callback = function(state) enemy.chams = state end,
})
playerEsp:new_toggle({
	name = "Off-screen Arrows",
	flag = "esp_arrows",
	state = true,
	callback = function(state) enemy.offScreenArrow = state end,
})
playerEsp:new_slider({
	name = "Max Distance",
	flag = "esp_dist",
	min = 100,
	max = 5000,
	default = 2500,
	callback = function(value)
		Sense.sharedSettings.maxDistance = value
		Sense.sharedSettings.limitDistance = value < 5000
	end,
})
playerEsp:new_colorpicker({
	name = "Player Color",
	flag = "esp_color",
	default = enemy.boxColor[1],
	callback = function(color)
		enemy.boxColor[1] = color
		enemy.tracerColor[1] = color
		enemy.chamsOutlineColor[1] = color
	end,
})

-- NPC ESP
local npcSec = visuals:new_section({ name = "NPC ESP (groups)", size = "Fill", side = "right" })

npcSec:new_toggle({
	name = "NPC ESP Enabled",
	flag = "npc_enabled",
	state = true,
	callback = function(state) NpcEsp.Enabled = state end,
})
npcSec:new_toggle({
	name = "Names",
	flag = "npc_names",
	state = true,
	callback = function(state) NpcEsp.ShowNames = state end,
})
npcSec:new_toggle({
	name = "Health",
	flag = "npc_hp",
	state = true,
	callback = function(state) NpcEsp.ShowHealth = state end,
})
npcSec:new_toggle({
	name = "Boxes",
	flag = "npc_box",
	state = true,
	callback = function(state) NpcEsp.ShowBox = state end,
})
npcSec:new_slider({
	name = "NPC Distance",
	flag = "npc_dist",
	min = 100,
	max = 8000,
	default = 2500,
	callback = function(value) NpcEsp.MaxDistance = value end,
})
npcSec:new_seperator({ name = "Group Colors" })

local groupOrder = { "Human", "Ghoul", "CCG", "Aggro", "Boss", "Named" }
for _, groupName in ipairs(groupOrder) do
	local g = NpcEsp.Groups[groupName]
	npcSec:new_toggle({
		name = groupName,
		flag = "npc_g_" .. groupName,
		state = true,
		callback = function(state) g.enabled = state end,
	})
	npcSec:new_colorpicker({
		name = groupName .. " color",
		flag = "npc_gc_" .. groupName,
		default = g.color,
		callback = function(c) g.color = c end,
	})
end

npcSec:new_button({
	name = "Rescan NPCs",
	flag = "npc_rescan",
	callback = function() NpcEsp.Refresh() end,
})

----------------------------------------------------------------
-- COMBAT
----------------------------------------------------------------
local combat = window:new_page({ name = "Combat" })
local lock = combat:new_section({ name = "Aim Lock", size = "Fill" })

lock:new_toggle({
	name = "1) Aim ON (master)",
	flag = "aim_enabled",
	state = false,
	callback = function(state) Aim.SetAimEnabled(state) end,
})
lock:new_toggle({
	name = "2) Silent Aim (hits follow target)",
	flag = "aim_silent",
	state = false,
	callback = function(state) Aim.SilentAim = state end,
})
lock:new_toggle({
	name = "3) Camera Lock (look at target)",
	flag = "aim_camera",
	state = false,
	callback = function(state) Aim.CameraAim = state end,
})

lock:new_seperator({ name = "Target line / FOV" })
lock:new_toggle({
	name = "Blue line + dot on target",
	flag = "aim_line",
	state = true,
	callback = function(state) Aim.ShowTargetLine = state end,
})
lock:new_colorpicker({
	name = "Line / dot color",
	flag = "aim_line_color",
	default = Aim.LineColor,
	callback = function(c)
		Aim.LineColor = c
		Aim.DotColor = c
	end,
})
lock:new_toggle({
	name = "FOV circle",
	flag = "aim_fov_circle",
	state = true,
	callback = function(state) Aim.ShowFov = state end,
})
lock:new_colorpicker({
	name = "FOV circle color",
	flag = "aim_fov_color",
	default = Aim.FovColor,
	callback = function(c) Aim.FovColor = c end,
})
lock:new_slider({
	name = "FOV cone (degrees, 360=all)",
	flag = "aim_fov",
	min = 10,
	max = 360,
	default = 180,
	callback = function(value) Aim.FOV = value end,
})

lock:new_seperator({ name = "Filters / feel" })
lock:new_toggle({
	name = "Team Check",
	flag = "aim_team",
	state = false,
	callback = function(state) Aim.TeamCheck = state end,
})
lock:new_toggle({
	name = "Wall Check",
	flag = "aim_wall",
	state = false,
	callback = function(state) Aim.WallCheck = state end,
})
lock:new_slider({
	name = "Camera Smoothness",
	flag = "aim_smooth",
	min = 5,
	max = 100,
	default = 45,
	text = "[value]%",
	callback = function(value) Aim.Smoothness = value / 100 end,
})
lock:new_dropdown({
	name = "Bone",
	flag = "aim_bone",
	options = { "Head", "HumanoidRootPart" },
	default = "Head",
	callback = function(value) Aim.Bone = value end,
})
lock:new_toggle({
	name = "Use Camera FOV changer",
	flag = "cam_fov_on",
	state = false,
	callback = function(state) Aim.UseCameraFov = state end,
})
lock:new_slider({
	name = "Camera FOV value",
	flag = "cam_fov",
	min = 30,
	max = 120,
	default = 70,
	callback = function(value) Aim.CameraFov = value end,
})
lock:new_keybind({
	name = "Aim keybind (side buttons OK)",
	flag = "aim_keybind",
	default = Enum.KeyCode.MouseBackButton,
	mode = "Toggle",
	ignore = true,
	callback = function(state)
		Aim.SetAimEnabled(state == true)
	end,
})
lock:new_dropdown({
	name = "Aim key mode",
	flag = "aim_key_mode",
	options = { "Toggle", "Hold" },
	default = "Toggle",
	callback = function(value) Aim.AimKeyMode = value end,
})
lock:new_button({
	name = "Face target once",
	flag = "aim_face_once",
	callback = function()
		local t = Aim.GetTarget()
		if t then Aim.FaceTarget(t) end
	end,
})

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
local settings = window:new_page({ name = "Settings" })
local menu = settings:new_section({ name = "Menu", size = "Half" })
menu:new_keybind({
	name = "Open / Close Menu",
	flag = "menu_bind",
	default = Enum.KeyCode.Insert,
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
