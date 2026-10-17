# roghoul-hub

Ro-Ghoul scripts + UI hub.

## Layout

| Folder | What goes here |
|---|---|
| `Deadcell/` | Deadcell UI library backup (Aimware-style cheat hub menu) |
| `scripts/` | Game scripts (create when ready) |

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

```lua
local library = loadstring(game:HttpGet("https://github.com/GhostDuckyy/UI-Libraries/blob/main/DEADCELL%20REMAKE/Modified/source.lua?raw=true"))()
```

Or load from a local/hosted copy of `Deadcell/source_modified.lua` if the GitHub URL dies.

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
