--// roghoul-hub // Deadcell menu + Sense ESP
-- Loads from this repo so nothing depends on dead hosts.

local RAW = "https://raw.githubusercontent.com/ziyy1337/roghoul-hub/main/"

-- 1) Deadcell UI
local library = loadstring(game:HttpGet(RAW .. "Deadcell/source_modified.lua"))()

-- 2) Sense ESP (local backup)
local Sense = loadstring(game:HttpGet(RAW .. "scripts/esp/Sense/source.lua"))()

-- Sense defaults: enemies on with a solid legit set
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
enemy.tracerOrigin = "Bottom"
enemy.chams = false
enemy.chamsVisibleOnly = false
enemy.offScreenArrow = true

local friendly = Sense.teamSettings.friendly
friendly.enabled = false

Sense.sharedSettings.limitDistance = false
Sense.sharedSettings.maxDistance = 2500
Sense.sharedSettings.textSize = 14

-- 3) Menu
local window = library:new_window({ size = Vector2.new(560, 420) })

local visuals = window:new_page({ name = "Visuals" })
local esp = visuals:new_section({ name = "ESP", size = "Fill" })

esp:new_toggle({
	name = "ESP Enabled",
	flag = "esp_enabled",
	state = true,
	callback = function(state)
		enemy.enabled = state
		if state then
			pcall(function() Sense.Load() end)
		end
	end,
})

esp:new_toggle({
	name = "Box",
	flag = "esp_box",
	state = true,
	callback = function(state) enemy.box = state end,
})

esp:new_toggle({
	name = "Box Outline",
	flag = "esp_box_outline",
	state = true,
	callback = function(state) enemy.boxOutline = state end,
})

esp:new_toggle({
	name = "Health Bar",
	flag = "esp_health",
	state = true,
	callback = function(state) enemy.healthBar = state end,
})

esp:new_toggle({
	name = "Name",
	flag = "esp_name",
	state = true,
	callback = function(state) enemy.name = state end,
})

esp:new_toggle({
	name = "Distance",
	flag = "esp_distance",
	state = true,
	callback = function(state) enemy.distance = state end,
})

esp:new_toggle({
	name = "Tracers",
	flag = "esp_tracer",
	state = false,
	callback = function(state) enemy.tracer = state end,
})

esp:new_toggle({
	name = "Chams",
	flag = "esp_chams",
	state = false,
	callback = function(state) enemy.chams = state end,
})

esp:new_toggle({
	name = "Off-screen Arrows",
	flag = "esp_arrows",
	state = true,
	callback = function(state) enemy.offScreenArrow = state end,
})

esp:new_toggle({
	name = "Team Check (friendly ESP)",
	flag = "esp_team",
	state = false,
	callback = function(state)
		friendly.enabled = state
	end,
})

esp:new_slider({
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

esp:new_colorpicker({
	name = "Enemy Color",
	flag = "esp_color",
	default = enemy.boxColor[1],
	callback = function(color)
		enemy.boxColor[1] = color
		enemy.tracerColor[1] = color
		enemy.chamsOutlineColor[1] = color
	end,
})

local settings = window:new_page({ name = "Settings" })
local menu = settings:new_section({ name = "Menu", size = "Half" })
menu:new_keybind({ name = "Menu Keybind", flag = "menu_bind" })
menu:new_toggle({
	name = "Show Keybinds List",
	flag = "keybind_list",
	callback = function(state)
		window:set_keybind_list_visibility(state)
	end,
})

-- Start ESP
pcall(function() Sense.Load() end)

return library, Sense
