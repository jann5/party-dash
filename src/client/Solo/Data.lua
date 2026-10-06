--!strict
-- Solo Record client data: solo-capable minigames (ReplicatedStorage.MinigameInfo), your bests
-- (Player attributes "SoloBest_<id>") and the global TOP lists (ReplicatedStorage.SoloTop, JSON per id).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))

local Data = {}

Data.BEST_PREFIX = "SoloBest_"

export type Game = { id: string, name: string, rules: string, accent: Color3 }
export type TopEntry = { name: string, seconds: number, userId: number }

local localPlayer = Players.LocalPlayer

function Data.accent(id: string): Color3
	return Theme.MinigameColors[id] or Theme.Colors.Purple
end

-- Solo-capable, non-hidden minigames, sorted by id (the same order the server uses for RANDOM/boards).
function Data.soloGames(): { Game }
	local list = {}
	local info = ReplicatedStorage:FindFirstChild("MinigameInfo")
	if not info then
		return list
	end
	for _, config in info:GetChildren() do
		if config:GetAttribute("SoloCapable") == true and config:GetAttribute("Hidden") ~= true then
			local name = config:GetAttribute("DisplayName")
			local rules = config:GetAttribute("Rules")
			table.insert(list, {
				id = config.Name,
				name = if type(name) == "string" then name else string.upper(config.Name),
				rules = if type(rules) == "string" then rules else "",
				accent = Data.accent(config.Name),
			})
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

function Data.gameName(id: string): string
	local info = ReplicatedStorage:FindFirstChild("MinigameInfo")
	local config = info and info:FindFirstChild(id)
	local name = config and config:GetAttribute("DisplayName")
	return if type(name) == "string" then name else string.upper(id)
end

function Data.best(id: string): number?
	local v = localPlayer:GetAttribute(Data.BEST_PREFIX .. id)
	return if type(v) == "number" and v > 0 then v else nil
end

function Data.top(id: string): { TopEntry }
	local folder = ReplicatedStorage:FindFirstChild("SoloTop")
	local raw = folder and folder:GetAttribute(id)
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local out = {}
	for _, e in list do
		if type(e) == "table" and type(e.n) == "string" and type(e.t) == "number" then
			table.insert(out, { name = e.n, seconds = e.t, userId = tonumber(e.u) or 0 })
		end
	end
	return out
end

function Data.top1(id: string): TopEntry?
	return Data.top(id)[1]
end

-- "41.2s", or "1:02.3" past a minute.
function Data.fmt(seconds: number): string
	if seconds >= 60 then
		return ("%d:%04.1f"):format(math.floor(seconds / 60), seconds % 60)
	end
	return ("%.1fs"):format(seconds)
end

return Data
