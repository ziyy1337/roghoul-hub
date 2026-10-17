--// Ro-Ghoul NPC ESP — group colors, optimized
-- Throttled rescan, early distance cull, Heartbeat (not every render cost path).

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
		Human = { enabled = true, color = Color3.fromRGB(255, 170, 60) },
		Ghoul = { enabled = true, color = Color3.fromRGB(90, 255, 120) },
		CCG = { enabled = true, color = Color3.fromRGB(80, 140, 255) },
		Aggro = { enabled = true, color = Color3.fromRGB(255, 70, 70) },
		Boss = { enabled = true, color = Color3.fromRGB(200, 90, 255) },
		Named = { enabled = true, color = Color3.fromRGB(80, 230, 230) },
	},
	RescanInterval = 4, -- seconds
	_entries = {},
	_dirty = true,
	_lastScan = 0,
	_lastRescanRequest = 0,
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
	p.CharacterAdded:Connect(function()
		playerChars[p.Character] = true
		NpcEsp._dirty = true
	end)
	p.CharacterRemoving:Connect(function()
		playerChars[p.Character] = nil
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	if p.Character then playerChars[p.Character] = nil end
end)

local function classify(model)
	local p = model.Parent
	for _ = 1, 4 do
		if not p then break end
		local n = p.Name
		if n:find("HumanSpawns", 1, true) then return "Human" end
		if n:find("AggroSpawns", 1, true) then return "Aggro" end
		if n:find("CCGSpawns", 1, true) then return "CCG" end
		if n:find("GhoulSpawns", 1, true) then return "Ghoul" end
		if n:find("BossSpawns", 1, true) then return "Boss" end
		p = p.Parent
	end
	return "Named"
end

local function makeDraw(class)
	if not Drawing or not Drawing.new then return nil end
	local ok, d = pcall(Drawing.new, class)
	return ok and d or nil
end

local function clearEntries()
	for _, e in ipairs(NpcEsp._entries) do
		if e.box then e.box:Remove() end
		if e.name then e.name:Remove() end
		if e.hp then e.hp:Remove() end
	end
	table.clear(NpcEsp._entries)
end

local function rebuild()
	clearEntries()
	refreshPlayers()
	local now = os.clock()
	local maxDist = NpcEsp.MaxDistance
	local camPos = Camera and Camera.CFrame.Position or Vector3.zero

	for _, d in ipairs(Workspace:GetDescendants()) do
		-- cheap filters first
		if d:IsA("Model") and not playerChars[d] then
			local nm = d.Name
			if not nm:find("Corpse", 1, true) and not nm:find("Dead", 1, true) then
				local hum = d:FindFirstChildOfClass("Humanoid")
				if hum and hum.MaxHealth < 1e6 and hum.MaxHealth > 0 then
					local hrp = d:FindFirstChild("HumanoidRootPart") or d:FindFirstChild("Head")
					if hrp and (camPos - hrp.Position).Magnitude <= maxDist * 1.25 then
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
								e.name.Text = nm
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
		end
	end
	NpcEsp._dirty = false
	NpcEsp._lastScan = now
end

local function hideAll()
	for _, e in ipairs(NpcEsp._entries) do
		if e.box and e.box.Visible then e.box.Visible = false end
		if e.name and e.name.Visible then e.name.Visible = false end
		if e.hp and e.hp.Visible then e.hp.Visible = false end
	end
end

local frame = 0
local function update()
	if not NpcEsp.Enabled then
		hideAll()
		return
	end

	Camera = Workspace.CurrentCamera
	local now = os.clock()

	-- throttled full rescan
	if NpcEsp._dirty and (now - NpcEsp._lastScan) >= 0.75 then
		rebuild()
	end
	if (now - NpcEsp._lastScan) >= NpcEsp.RescanInterval then
		NpcEsp._dirty = true
	end

	-- draw at half rate when possible (every other Heartbeat is still smooth enough)
	frame += 1
	if frame % 2 == 1 and #NpcEsp._entries > 0 then
		return
	end

	local camPos = Camera.CFrame.Position
	local maxDist = NpcEsp.MaxDistance
	local showBox, showNames, showHp = NpcEsp.ShowBox, NpcEsp.ShowNames, NpcEsp.ShowHealth

	for i = 1, #NpcEsp._entries do
		local e = NpcEsp._entries[i]
		local g = NpcEsp.Groups[e.group]
		local show = g and g.enabled
		local part = e.hrp

		if not show or not part or not part.Parent or part.Position == Vector3.zero then
			if e.box and e.box.Visible then e.box.Visible = false end
			if e.name and e.name.Visible then e.name.Visible = false end
			if e.hp and e.hp.Visible then e.hp.Visible = false end
		else
			local delta = part.Position - camPos
			local dist = delta.Magnitude
			if dist > maxDist or dist < 1 then
				if e.box and e.box.Visible then e.box.Visible = false end
				if e.name and e.name.Visible then e.name.Visible = false end
				if e.hp and e.hp.Visible then e.hp.Visible = false end
			else
				local rootPos, onRoot = Camera:WorldToViewportPoint(part.Position)
				local topPos = Camera:WorldToViewportPoint(part.Position + Vector3.new(0, 3, 0))
				local botPos = Camera:WorldToViewportPoint(part.Position - Vector3.new(0, 3, 0))
				local onScreen = onRoot and topPos.Z > 0
				local color = g.color

				if e.box then
					if onScreen and showBox then
						local h = math.clamp(math.abs(topPos.Y - botPos.Y), 12, 500)
						local w = h * 0.55
						e.box.Size = Vector2.new(w, h)
						e.box.Position = Vector2.new(topPos.X - w * 0.5, topPos.Y)
						e.box.Color = color
						if not e.box.Visible then e.box.Visible = true end
					elseif e.box.Visible then
						e.box.Visible = false
					end
				end

				if e.name then
					if onScreen and showNames then
						e.name.Position = Vector2.new(topPos.X, topPos.Y - 16)
						e.name.Color = color
						if not e.name.Visible then
							e.name.Text = e.model.Name
							e.name.Visible = true
						end
					elseif e.name.Visible then
						e.name.Visible = false
					end
				end

				if e.hp then
					local alive = e.hum.Health > 0
					if onScreen and showHp and alive then
						e.hp.Text = string.format("%d", math.floor(e.hum.Health))
						e.hp.Position = Vector2.new(botPos.X, botPos.Y + 4)
						e.hp.Color = color
						if not e.hp.Visible then e.hp.Visible = true end
					elseif e.hp.Visible then
						e.hp.Visible = false
					end
				end
			end
		end
	end
end

-- debounce dirty flag from tree changes
local function requestRescan()
	local now = os.clock()
	NpcEsp._dirty = true
	NpcEsp._lastRescanRequest = now
end

Workspace.DescendantAdded:Connect(requestRescan)
Workspace.DescendantRemoving:Connect(requestRescan)

RunService.Heartbeat:Connect(update)

function NpcEsp.Refresh()
	NpcEsp._dirty = true
	NpcEsp._lastScan = 0 -- force immediate
end

function NpcEsp.Destroy()
	clearEntries()
	NpcEsp.Enabled = false
end

task.defer(function()
	rebuild()
end)

return NpcEsp
