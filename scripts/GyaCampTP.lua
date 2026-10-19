--// Gya Camp TP — standalone, not part of the hub
-- Teleports to the user-picked camp spots behind the mall buildings.
local BL = Vector3.new(-396.5, 64, 352.4)  -- behind PartsStore (ShopsR), statue LOS blocked
local BR = Vector3.new(-500, 64, 165)      -- behind RickAstley (ShopsL), statue LOS blocked

local TARGET = BL -- flip to BR if needed

local lp = game:GetService("Players").LocalPlayer
local ch = lp.Character or lp.CharacterAdded:Wait()
local hrp = ch:WaitForChild("HumanoidRootPart")
hrp.CFrame = CFrame.new(TARGET)
print("[GyaCampTP] teleported to", TARGET)
