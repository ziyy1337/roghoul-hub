--// Rejoin same server — standalone, not part of the hub
-- Teleports you right back into the server you're currently in.
-- Run it, the game reloads, you're in the same place with the same people.
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local placeId = game.PlaceId
local jobId = game.JobId
print("[Rejoin] teleporting back to", jobId)
TeleportService:TeleportToPlaceInstance(placeId, jobId, lp)
