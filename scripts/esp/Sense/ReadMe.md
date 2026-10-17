# Sense ESP

Local backup of Sirius **Sense** ESP from [GhostDuckyy/ESP-Library](https://github.com/GhostDuckyy/ESP-Library) (also `https://sirius.menu/sense`).

Standalone load:

```lua
local Sense = loadstring(game:HttpGet("https://raw.githubusercontent.com/ziyy1337/roghoul-hub/main/scripts/esp/Sense/source.lua"))()
Sense.teamSettings.enemy.enabled = true
Sense.teamSettings.enemy.box = true
Sense.teamSettings.enemy.name = true
Sense.Load()
```

Wired into Deadcell via `scripts/DeadcellSenseHub.lua`.
