--// Shows the BL camp position marker (standalone, not part of the hub)
local POS = Vector3.new(-396.5, 64, 352.4)

local part = Instance.new("Part")
part.Anchored = true
part.CanCollide = false
part.Size = Vector3.new(4, 0.4, 4)
part.Position = POS
part.Color = Color3.fromRGB(0, 170, 255)
part.Material = Enum.Material.Neon
part.Name = "BL_CampMarker"
part.Parent = workspace

local gui = Instance.new("BillboardGui")
gui.Size = UDim2.new(0, 200, 0, 40)
gui.StudsOffset = Vector3.new(0, 4, 0)
gui.AlwaysOnTop = true
gui.Parent = part

local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.new(1, 0, 1, 0)
lbl.BackgroundTransparency = 1
lbl.Text = "BL Camp (-396.5, 64, 352.4)"
lbl.TextColor3 = Color3.fromRGB(0, 200, 255)
lbl.TextScaled = true
lbl.Font = Enum.Font.GothamBold
lbl.Parent = gui
