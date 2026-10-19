--// Shows both gya camp position markers (standalone, not part of the hub)
-- Mirrored pair on the same X row, equidistant from the statue center (z≈272.5):
local SPOTS = {
	{ name = "BR Camp", pos = Vector3.new(-396.5, 64, 192.6), color = Color3.fromRGB(0, 255, 120) },
	{ name = "BL Camp", pos = Vector3.new(-396.5, 64, 352.4), color = Color3.fromRGB(0, 170, 255) },
}

for _, s in ipairs(SPOTS) do
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(4, 0.4, 4)
	part.Position = s.pos
	part.Color = s.color
	part.Material = Enum.Material.Neon
	part.Name = s.name:gsub(" ", "") .. "_Marker"
	part.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 200, 0, 40)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.Parent = part

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = string.format("%s (%.1f, %.1f, %.1f)", s.name, s.pos.X, s.pos.Y, s.pos.Z)
	lbl.TextColor3 = s.color
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = gui
end
