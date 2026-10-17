--// Gyakusatsu hearts / head locator — run in-game while the event is live
local Workspace = game:GetService("Workspace")

local out = {
	capturedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	placeId = game.PlaceId,
	jobId = game.JobId,
}

local function posOf(p)
	if p and p:IsA("BasePart") then
		return { p.Position.X, p.Position.Y, p.Position.Z }
	end
	return nil
end

-- 1) four heart corners on Workspace.Gyakusatsu
local boss = Workspace:FindFirstChild("Gyakusatsu")
if boss then
	out.hearts = {}
	for _, corner in ipairs({ "FR", "FL", "BR", "BL" }) do
		local m = boss:FindFirstChild(corner)
		local heart = m and m:FindFirstChild("Spawn")
		if heart then
			table.insert(out.hearts, {
				corner = corner,
				path = heart:GetFullName(),
				position = posOf(heart),
				size = { heart.Size.X, heart.Size.Y, heart.Size.Z },
			})
		end
	end
	out.bossPivot = (function()
		local p = boss:GetPivot()
		return { p.Position.X, p.Position.Y, p.Position.Z }
	end)()
end

-- 2) statue head (main part)
local spawn = Workspace.NPCSpawns and Workspace.NPCSpawns:FindFirstChild("GyakusatsuSpawn")
local statue = spawn and spawn:FindFirstChild("Gyakusatsu")
if statue then
	local head = statue:FindFirstChild("Head")
	out.statueHead = head and {
		path = head:GetFullName(),
		position = posOf(head),
		size = { head.Size.X, head.Size.Y, head.Size.Z },
	} or nil
	local hum = statue:FindFirstChildOfClass("Humanoid")
	out.statueHealth = hum and { hum.Health, hum.MaxHealth } or nil
end

-- 3) dissection table head
local tbl = Workspace:FindFirstChild("GyaSacTable")
local ind = tbl and tbl:FindFirstChild("GyaSacIndicator")
out.stationHead = ind and { path = ind:GetFullName(), position = posOf(ind) } or nil

print(("Hearts: %d"):format(out.hearts and #out.hearts or 0))
if out.hearts then
	for _, h in ipairs(out.hearts) do
		print(("  %s (%.1f, %.1f, %.1f)"):format(h.corner, h.position[1], h.position[2], h.position[3]))
	end
end
if out.statueHead then
	print(("Head: (%.1f, %.1f, %.1f)"):format(
		out.statueHead.position[1], out.statueHead.position[2], out.statueHead.position[3]))
end

return out
