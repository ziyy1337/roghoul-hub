--// Gyakusatsu Heart ESP — always-on map markers
-- Uses fixed coords from scripts/data/gyakusatsu-hearts.json so it works
-- even when Workspace.Gyakusatsu is NOT spawned.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Camera = Workspace.CurrentCamera

local GyakuEsp = {
	Enabled = true,
	ShowHearts = true,
	ShowHead = true,
	ShowStation = true,
	ShowBeams = true,
	ShowNames = true,
	ShowDistance = true,
	MaxDistance = 5000,
	HeartColor = Color3.fromRGB(255, 60, 90),
	HeadColor = Color3.fromRGB(255, 220, 80),
	StationColor = Color3.fromRGB(80, 200, 255),
	Thickness = 2,
}

-- Fixed positions (from live capture 2026-10-17)
local HEARTS = {
	{ name = "Heart FR", pos = Vector3.new(-635.64, 68.45, 200.11), corner = "FR" },
	{ name = "Heart FL", pos = Vector3.new(-635.41, 69.89, 342.42), corner = "FL" },
	{ name = "Heart BR", pos = Vector3.new(-530.50, 67.98, 206.58), corner = "BR" },
	{ name = "Heart BL", pos = Vector3.new(-519.59, 67.38, 341.97), corner = "BL" },
}

local STATUE_HEAD = {
	name = "Gyakusatsu Head",
	pos = Vector3.new(-575.00, 67.51, 272.50),
}

local STATION_HEAD = {
	name = "Hearts Station",
	pos = Vector3.new(-1039.50, 64.25, 267.50),
}

local function makeDrawing(class)
	if not Drawing or not Drawing.new then return nil end
	local ok, d = pcall(Drawing.new, class)
	return ok and d or nil
end

local function newMarker(color)
	local m = {
		box = makeDrawing("Square"),
		label = makeDrawing("Text"),
		dist = makeDrawing("Text"),
		beamFrom = makeDrawing("Line"),
		beamTo = makeDrawing("Line"),
		color = color,
	}
	if m.box then
		m.box.Thickness = GyakuEsp.Thickness
		m.box.Filled = false
		m.box.Visible = false
	end
	if m.label then
		m.label.Size = 14
		m.label.Center = true
		m.label.Outline = true
		m.label.Visible = false
	end
	if m.dist then
		m.dist.Size = 12
		m.dist.Center = true
		m.dist.Outline = true
		m.dist.Visible = false
	end
	if m.beamFrom then
		m.beamFrom.Thickness = 1
		m.beamFrom.Visible = false
		m.beamFrom.Color = color
	end
	if m.beamTo then
		m.beamTo.Thickness = 1
		m.beamTo.Visible = false
		m.beamTo.Color = color
	end
	return m
end

local markers = {}
local function buildMarkers()
	for _, m in ipairs(markers) do
		if m.box then m.box:Remove() end
		if m.label then m.label:Remove() end
		if m.dist then m.dist:Remove() end
		if m.beamFrom then m.beamFrom:Remove() end
		if m.beamTo then m.beamTo:Remove() end
	end
	table.clear(markers)

	for _, h in ipairs(HEARTS) do
		local m = newMarker(GyakuEsp.HeartColor)
		m.pos = h.pos
		m.labelText = h.name
		m.kind = "heart"
		table.insert(markers, m)
	end

	local hm = newMarker(GyakuEsp.HeadColor)
	hm.pos = STATUE_HEAD.pos
	hm.labelText = STATUE_HEAD.name
	hm.kind = "head"
	table.insert(markers, hm)

	local sm = newMarker(GyakuEsp.StationColor)
	sm.pos = STATION_HEAD.pos
	sm.labelText = STATION_HEAD.name
	sm.kind = "station"
	table.insert(markers, sm)
end

local function colorFor(m)
	if m.kind == "heart" then return GyakuEsp.HeartColor end
	if m.kind == "head" then return GyakuEsp.HeadColor end
	return GyakuEsp.StationColor
end

local function hide(m)
	if m.box and m.box.Visible then m.box.Visible = false end
	if m.label and m.label.Visible then m.label.Visible = false end
	if m.dist and m.dist.Visible then m.dist.Visible = false end
	if m.beamFrom and m.beamFrom.Visible then m.beamFrom.Visible = false end
	if m.beamTo and m.beamTo.Visible then m.beamTo.Visible = false end
end

local function update()
	if not GyakuEsp.Enabled then
		for _, m in ipairs(markers) do hide(m) end
		return
	end

	Camera = Workspace.CurrentCamera
	if not Camera then return end

	local camPos = Camera.CFrame.Position
	local vp = Camera.ViewportSize
	local center = Vector2.new(vp.X / 2, vp.Y / 2)

	-- live boss present? (optional boost: snap heart markers to live parts)
	local liveBoss = Workspace:FindFirstChild("Gyakusatsu")

	for _, m in ipairs(markers) do
		local visibleFlag = true
		if m.kind == "heart" then visibleFlag = GyakuEsp.ShowHearts end
		if m.kind == "head" then visibleFlag = GyakuEsp.ShowHead end
		if m.kind == "station" then visibleFlag = GyakuEsp.ShowStation end

		if not visibleFlag then
			hide(m)
		else
			-- prefer live heart part if boss exists
			local targetPos = m.pos
			if m.kind == "heart" and liveBoss then
				-- map FR/FL/BR/BL labels by nearest corner
				local best, bestD
				for _, corner in ipairs({ "FR", "FL", "BR", "BL" }) do
					local part = liveBoss:FindFirstChild(corner)
					part = part and part:FindFirstChild("Spawn")
					if part and part:IsA("BasePart") then
						local d = (part.Position - m.pos).Magnitude
						if not bestD or d < bestD then
							bestD = d
							best = part.Position
						end
					end
				end
				if best then targetPos = best end
			end
			if m.kind == "head" then
				local sp = Workspace.NPCSpawns and Workspace.NPCSpawns:FindFirstChild("GyakusatsuSpawn")
				local statue = sp and sp:FindFirstChild("Gyakusatsu")
				local head = statue and statue:FindFirstChild("Head")
				if head and head:IsA("BasePart") then
					targetPos = head.Position
				end
			end

			local delta = targetPos - camPos
			local dist = delta.Magnitude
			local sp, onScreen = Camera:WorldToViewportPoint(targetPos)
			local inRange = dist <= GyakuEsp.MaxDistance
			local show = inRange

			if m.box then
				if show and sp.Z > 0 then
					local h = math.clamp(math.abs(dist) * 0.04, 18, 80)
					local w = h
					m.box.Size = Vector2.new(w, h)
					m.box.Position = Vector2.new(sp.X - w / 2, sp.Y - h / 2)
					m.box.Color = colorFor(m)
					m.box.Thickness = GyakuEsp.Thickness
					m.box.Visible = true
				elseif m.box.Visible then
					m.box.Visible = false
				end
			end

			if m.label then
				if show and GyakuEsp.ShowNames and sp.Z > 0 then
					m.label.Text = m.labelText
					m.label.Position = Vector2.new(sp.X, sp.Y - 20)
					m.label.Color = colorFor(m)
					m.label.Visible = true
				elseif m.label.Visible then
					m.label.Visible = false
				end
			end

			if m.dist then
				if show and GyakuEsp.ShowDistance and sp.Z > 0 then
					m.dist.Text = string.format("%dm", math.floor(dist / 3))
					m.dist.Position = Vector2.new(sp.X, sp.Y + 14)
					m.dist.Color = colorFor(m)
					m.dist.Visible = true
				elseif m.dist.Visible then
					m.dist.Visible = false
				end
			end

			-- off-screen: short edge lines from center toward target
			if m.beamFrom and m.beamTo then
				if show and GyakuEsp.ShowBeams then
					local toCenter = Vector2.new(sp.X - center.X, sp.Y - center.Y)
					local mag = toCenter.Magnitude
					local on = sp.Z > 0
					if on and mag > 0 then
						m.beamFrom.From = center
						m.beamFrom.To = Vector2.new(sp.X, sp.Y)
						m.beamFrom.Color = colorFor(m)
						m.beamFrom.Transparency = 0.65
						m.beamFrom.Visible = true
						m.beamTo.Visible = false
					else
						-- off-screen: line from center toward edge
						local dir = Vector2.new(sp.X - center.X, sp.Y - center.Y)
						if dir.Magnitude < 1 then dir = Vector2.new(0, 1) end
						local unit = dir.Unit
						local edge = Vector2.new(
							math.clamp(center.X + unit.X * (vp.X * 0.45), 20, vp.X - 20),
							math.clamp(center.Y + unit.Y * (vp.Y * 0.45), 20, vp.Y - 20)
						)
						m.beamFrom.From = center
						m.beamFrom.To = edge
						m.beamFrom.Color = colorFor(m)
						m.beamFrom.Transparency = 0.4
						m.beamFrom.Visible = true
						m.beamTo.Visible = false
					end
				else
					if m.beamFrom.Visible then m.beamFrom.Visible = false end
					if m.beamTo.Visible then m.beamTo.Visible = false end
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(function()
	local ok, err = pcall(update)
	if not ok then
		warn("[GyakuEsp]", err)
	end
end)

buildMarkers()

function GyakuEsp.Refresh()
	buildMarkers()
end

function GyakuEsp.SetColor(kind, color)
	if kind == "heart" then GyakuEsp.HeartColor = color end
	if kind == "head" then GyakuEsp.HeadColor = color end
	if kind == "station" then GyakuEsp.StationColor = color end
	buildMarkers()
end

function GyakuEsp.Destroy()
	for _, m in ipairs(markers) do
		if m.box then m.box:Remove() end
		if m.label then m.label:Remove() end
		if m.dist then m.dist:Remove() end
		if m.beamFrom then m.beamFrom:Remove() end
		if m.beamTo then m.beamTo:Remove() end
	end
	table.clear(markers)
	GyakuEsp.Enabled = false
end

return GyakuEsp
