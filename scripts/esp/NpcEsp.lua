--// Ro-Ghoul NPC ESP — colored by spawn group
-- Groups: Human / Ghoul / CCG / Aggro / Boss / Named

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local NpcEsp = {
	Enabled = true,
	MaxDistance = 2500,
	ShowNames = true,
	ShowHealth = true,
	ShowBox = true,
	Groups = {
		Human = { enabled = true, color = Color3.fromRGB(255, 170, 60) },   -- orange
		Ghoul = { enabled = true, color = Color3.fromRGB(90, 255, 120) },   -- green
		CCG = { enabled = true, color = Color3.fromRGB(80, 140, 255) },     -- blue
		Aggro = { enabled = true, color = Color3.fromRGB(255, 70, 70) },    -- red
		Boss = { enabled = true, color = Color3.fromRGB(200, 90, 255) },    -- purple
		Named = { enabled = true, color = Color3.fromRGB(80, 230, 230) },   -- cyan
	},
	_entries = {},
	_dirty = true,
}

local playerChars = {}
local function refreshPlayers()
	playerChars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			playerChars[p.Character] = true
		end
	end
end
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function() NpcEsp._dirty = true end)
end)
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	NpcEsp._dirty = true
end)

local function classify(model)
	local parent = model.Parent
	local pname = parent and parent.Name or ""
	-- walk up to NPCSpawns group folder if nested under spawn mesh
	local p = parent
	for _ = 1, 3 do
		if not p then break end
		if p.Name:find("HumanSpawns") then return "Human" end
		if p.Name:find("GhoulSpawns") and not p.Name:find("Aggro") then return "Ghoul" end
		if p.Name:find("CCGSpawns") then return "CCG" end
		if p.Name:find("AggroSpawns") then return "Aggro" end
		if p.Name:find("BossSpawns") then return "Boss" end
		p = p.Parent
	end
	if pname:find("Boss") then return "Boss" end
	-- map NPCs (Yoshimura, Furuta, CEO boss already in BossSpawns)
	if model:FindFirstChildOfClass("Humanoid") and model.Name:find("Corpse") then
		return nil -- skip corpses
	end
	return "Named"
end

local function makeDraw(class)
	if not Drawing or not Drawing.new then return nil end
	local ok, d = pcall(Drawing.new, class)
	return ok and d or nil
end

local function rebuild()
	-- cleanup old
	for _, e in ipairs(NpcEsp._entries) do
		if e.box then e.box:Remove() end
		if e.name then e.name:Remove() end
		if e.hp then e.hp:Remove() end
	end
	NpcEsp._entries = {}
	refreshPlayers()

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and not playerChars[d] and not d.Name:find("Corpse") then
			local hum = d:FindFirstChildOfClass("Humanoid")
			local hrp = d:FindFirstChild("HumanoidRootPart") or d:FindFirstChild("Head")
			if hum and hrp and hum.MaxHealth < 1e6 then
				local group = classify(d)
				if group and NpcEsp.Groups[group] then
					local e = {
						model = d,
						hum = hum,
						hrp = hrp,
						group = group,
						box = makeDraw("Square"),
						name = makeDraw("Text"),
						hp = makeDraw("Text"),
					}
					if e.box then
						e.box.Thickness = 1.5
						e.box.Filled = false
						e.box.Visible = false
					end
					if e.name then
						e.name.Size = 14
						e.name.Center = true
						e.name.Outline = true
						e.name.Visible = false
						e.name.Text = d.Name
					end
					if e.hp then
						e.hp.Size = 12
						e.hp.Center = true
						e.hp.Outline = true
						e.hp.Visible = false
					end
					table.insert(NpcEsp._entries, e)
				end
			end
		end
	end
	NpcEsp._dirty = false
end

local function update()
	if not NpcEsp.Enabled then
		for _, e in ipairs(NpcEsp._entries) do
			if e.box then e.box.Visible = false end
			if e.name then e.name.Visible = false end
			if e.hp then e.hp.Visible = false end
		end
		return
	end
	if NpcEsp._dirty then rebuild() end
	Camera = Workspace.CurrentCamera

	for _, e in ipairs(NpcEsp._entries) do
		local g = NpcEsp.Groups[e.group]
		local show = g and g.enabled
		local part = e.model.PrimaryPart or e.hrp
		if show and part and part:IsDescendantOf(game) then
			local pos, onScreen = Camera:WorldToViewportPoint(part.Position + Vector3.new(0, 3, 0))
			local rootPos = Camera:WorldToViewportPoint(part.Position - Vector3.new(0, 3, 0))
			local dist = (Camera.CFrame.Position - part.Position).Magnitude
			onScreen = onScreen and dist <= NpcEsp.MaxDistance
			local color = g.color

			if e.box then
				if onScreen and NpcEsp.ShowBox then
					local h = math.clamp(math.abs(pos.Y - rootPos.Y), 10, 400)
					local w = h * 0.55
					e.box.Size = Vector2.new(w, h)
					e.box.Position = Vector2.new(pos.X - w / 2, pos.Y)
					e.box.Color = color
					e.box.Visible = true
				else
					e.box.Visible = false
				end
			end

			if e.name then
				if onScreen and NpcEsp.ShowNames then
					e.name.Text = e.model.Name
					e.name.Position = Vector2.new(pos.X, pos.Y - 16)
					e.name.Color = color
					e.name.Visible = true
				else
					e.name.Visible = false
				end
			end

			if e.hp then
				if onScreen and NpcEsp.ShowHealth and e.hum then
					e.hp.Text = string.format("%d/%d", math.floor(e.hum.Health), math.floor(e.hum.MaxHealth))
					e.hp.Position = Vector2.new(pos.X, rootPos.Y + 4)
					e.hp.Color = color
					e.hp.Visible = e.hum.Health > 0
				else
					e.hp.Visible = false
				end
			end
		else
			if e.box then e.box.Visible = false end
			if e.name then e.name.Visible = false end
			if e.hp then e.hp.Visible = false end
		end
	end
end

-- rescan when workspace children change (npc spawn/despawn)
Workspace.DescendantAdded:Connect(function()
	NpcEsp._dirty = true
end)
Workspace.DescendantRemoving:Connect(function()
	NpcEsp._dirty = true
end)

RunService.RenderStepped:Connect(update)

function NpcEsp.Refresh()
	NpcEsp._dirty = true
end

function NpcEsp.Destroy()
	for _, e in ipairs(NpcEsp._entries) do
		if e.box then e.box:Remove() end
		if e.name then e.name:Remove() end
		if e.hp then e.hp:Remove() end
	end
	NpcEsp._entries = {}
	NpcEsp.Enabled = false
end

-- initial scan
task.defer(rebuild)

return NpcEsp
