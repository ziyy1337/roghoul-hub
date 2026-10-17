# roghoul-hub

Ro-Ghoul scripts + UI hub.

## Layout

| Folder | What goes here |
|---|---|
| `Deadcell/` | Deadcell UI library backup (Aimware-style cheat hub menu) |
| `scripts/` | Hub scripts — start with `scripts/DeadcellSenseHub.lua` |
| `scripts/esp/Sense/` | Sense ESP backup + docs |

## Deadcell UI (backup)

Local backup of the **Deadcell** Roblox UI library from [GhostDuckyy/UI-Libraries](https://github.com/GhostDuckyy/UI-Libraries).

## Contents

| Path | What it is |
|---|---|
| `Deadcell/source.lua` | Main library (REMAKE) |
| `Deadcell/deps/` | External Lua deps + assets (extension, tween, bxor, etc.) — see `Deadcell/deps/README.md` |
| `Deadcell/source_modified.lua` | Modified fallback variant |
| `Deadcell/backup/` | Timestamped copies of both sources |
| `Deadcell/Example` | Example menu from Eazvy/UILibs |
| `Deadcell/preview.png` | Screenshot |
| `Deadcell/UILibs_README.md` | Original catalog blurb |

## Load

All external URLs now point at **this repo** (`ziyy1337/roghoul-hub`), not GhostDuckyy / vozoid.

```lua
-- preferred (modified: uses bxor for assets)
local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/ziyy1337/roghoul-hub/main/Deadcell/source_modified.lua"))()

-- or the main remake
-- local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/ziyy1337/roghoul-hub/main/Deadcell/source.lua"))()
```

Originals with the old GhostDuckyy/vozoid URLs are kept under `Deadcell/backup/*ORIGINAL*`.

## Hub + ESP + Aim

Deadcell menu with Sense ESP (Visuals) and silent/camera aim (Combat):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ziyy1337/roghoul-hub/main/scripts/DeadcellSenseHub.lua"))()
```

- **Visuals:** box, name, health, distance, tracers, chams, arrows
- **Combat:** silent aim (hooks `Mouse.Hit` — Ro-Ghoul attacks read that), camera aim, aim FOV circle, camera FOV changer, FOV/smoothness/bone, team/wall check
- **Keybinds:** aim toggle (default **Mouse Back / side button**, rebind in menu), menu open/close (**Insert** or “Toggle Menu Now”)

## Minimal menu

```lua
local window = library:new_window({ size = Vector2.new(600, 450) })
local page = window:new_page({ name = "Main" })

local section = page:new_section({ name = "Farming", size = "Half" })
section:new_toggle({
    name = "Auto Farm",
    flag = "auto_farm",
    callback = function(state) print(state) end,
})

local settings = page:new_section({ name = "Settings", size = "Half" })
settings:new_keybind({ name = "Menu Keybind", flag = "menu_bind" })
settings:new_toggle({
    name = "Show Keybinds List",
    flag = "keybind_list",
    callback = function(state)
        window:set_keybind_list_visibility(state)
    end,
})
```

## Upstream

- Source: https://github.com/GhostDuckyy/UI-Libraries (DEADCELL REMAKE)
- Catalog: https://github.com/Eazvy/UILibs
