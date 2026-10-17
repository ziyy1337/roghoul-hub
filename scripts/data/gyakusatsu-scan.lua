--// Gyakusatsu / hearts locator — run in-game to refresh gyakusatsu-hearts.json data
-- Returns a table; also prints a compact report.

local Workspace = game:GetService("Workspace")

local function partInfo(p)
	if not p or not p:IsA("BasePart") then return nil end
	local info = {
		path = p:GetFullName(),
		className = p.ClassName,
		position = { p.Position.X, p.Position.Y, p.Position.Z },
		size = { p.Size.X, p.Size.Y, p.Size.Z },
		orientation = { p.Orientation.X, p.Orientation.Y, p.Orientation.Z },
		anchored = p.Anchored,
	}
	if p:IsA("Part") then info.shape = tostring(p.Shape) end
	return info
end

local out = {
	capturedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	placeId = game.PlaceId,
	jobId = game.JobId,
}

local spawn = Workspace.NPCSpawns and Workspace.NPCSpawns:FindFirstChild("GyakusatsuSpawn")
out.spawn = partInfo(spawn)

local tbl = Workspace:FindFirstChild("GyaSacTable")
if tbl then
	out.station = {
		path = tbl:GetFullName(),
		pivot = (function()
			local p = tbl:GetPivot()
			return { p.Position.X, p.Position.Y, p.Position.Z }
		end)(),
		head = partInfo(tbl:FindFirstChild("GyaSacIndicator")),
		bench = partInfo(tbl:FindFirstChild("Bench")),
		base = partInfo(tbl:FindFirstChild("Part")),
	}
end

-- live heart parts
local hearts = {}
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("BasePart") then
		local n = string.lower(d.Name)
		if n == "heart" or n == "hearts" or n:find("heart", 1, true) then
			if not n:find("heartbeat") then
				table.insert(hearts, partInfo(d))
			end
		end
	end
end
out.liveHearts = hearts
out.liveHeartCount = #hearts

print(("Gyakusatsu spawn: %s"):format(
	out.spawn and string.format("(%.2f, %.2f, %.2f)", unpack(out.spawn.position)) or "not found"
))
print(("Hearts station head: %s"):format(
	out.station and out.station.head and string.format("(%.2f, %.2f, %.2f)", unpack(out.station.head.position)) or "not found"
))
print(("Live heart parts: %d"):format(out.liveHeartCount))

return out
