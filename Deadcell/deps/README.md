# Deadcell external dependencies

Local backups of every external Lua (and asset) file `source.lua` / `source_modified.lua` pulls at runtime.

## Required by Deadcell source

| File | Used for | Upstream URL | Status |
|---|---|---|---|
| `extension.lua` | Drawing-style UI helpers (`utility.create`, text metrics) | `GhostDuckyy/UI-Libraries/.../misc/extension.lua` | **Alive** |
| `Tween_selfcontained.lua` | Tween animations (local, no dead hosts) | Built from GhostDuckyy `misc/tween.lua` + inlined `misc/signal.lua` | **Use this** |
| `Tween_vozoid_broken.lua` | Original GhostDuckyy tween (still HttpGets dead vozoid Signal) | `misc/tween.lua` | Broken host chain |
| `signal.lua` | Signal lib (dependency of vozoid-style tween) | GhostDuckyy `misc/signal.lua` | Alive |
| `bxor.lua` | Asset encrypt/decrypt (**source_modified only**) | `GhostDuckyy/GhostDuckyy/Tools/bxor.lua` | **Alive** |
| `base64.lua` | Fallback base64 (`base64_decode`) | `GhostDuckyy/GhostDuckyy/Tools/base64.lua` | Alive |

### Dead upstream URLs (as of 2026-10-17)

These are what the stock sources still reference — both are gone:

- `https://raw.githubusercontent.com/vozoid/utility/main/Tween.lua` → **404**
- `https://raw.githubusercontent.com/vozoid/utility/main/Signal.lua` → **404**

If you load stock `source.lua` / `source_modified.lua` as-is, replace:

```lua
local tween = loadstring(game:HttpGet("https://raw.githubusercontent.com/vozoid/utility/main/Tween.lua"))()
```

with a load of `Tween_selfcontained.lua` (host it yourself from this repo).

## Assets

| File | Source |
|---|---|
| `assets/Gradient.png`, `Gradient180.png` | GhostDuckyy `DEADCELL REMAKE/image/` (also portallol/luna) |
| `assets/Gradient_upstream.png`, `Gradient180_upstream.png` | Same, from GhostDuckyy image folder |
| `assets/arrow_down.png`, `arrow_up.png` | GhostDuckyy image folder |
| `assets/SL9cbQp.png`, `tVqy0nL.png` | imgur URLs in source (tiny 9×6 — likely dead placeholders) |

## Extra tools from GhostDuckyy (same author, not required by Deadcell)

- `FPS_booster.lua`
- `IrisBetterCompat.lua`
- `disassembler.lua`

## `upstream_misc/`

Raw copies of GhostDuckyy's `DEADCELL REMAKE/misc/` + Example/ReadMe for reference.

## `backup/`

Timestamped snapshots of the important Lua deps.
