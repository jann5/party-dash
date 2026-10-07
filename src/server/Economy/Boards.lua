--!strict
-- Lobby leaderboard writes (GAME_DESIGN 7): after a successful profile save, the player's wins and level go to two
-- OrderedDataStores keyed by UserId (only when the value changed). The Social piece reads and renders them.
--   PartyDash_TopWins_v1   value = wins
--   PartyDash_TopLevel_v1  value = level * 1e6 + xp   (sorts by level, then progress)
local DataStoreService = game:GetService("DataStoreService")

local Store = require(script.Parent.Store)
local Types = require(script.Parent.Types)

type Session = Types.Session

local Boards = {}

Boards.WINS = "PartyDash_TopWins_v1"
Boards.LEVEL = "PartyDash_TopLevel_v1"

local stores: { [string]: OrderedDataStore } = {}

local function ordered(name: string): OrderedDataStore?
	local store = stores[name]
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		stores[name] = result
		return result
	end
	return nil
end

local function write(name: string, key: string, value: number): boolean
	local store = ordered(name)
	if not store then
		return false
	end
	local ok, err = pcall(function()
		store:SetAsync(key, value)
	end)
	if not ok then
		warn(("[Economy] leaderboard %s write failed: %s"):format(name, tostring(err)))
	end
	return ok
end

function Boards.levelScore(level: number, xp: number): number
	return level * 1000000 + xp
end

-- Writes whatever changed since the last write. Yields; call from a spawned thread.
function Boards.submit(s: Session)
	if not Store.isPersistent() or not s.persistent or s.lost then
		return
	end
	local key = tostring(s.player.UserId)
	local wins = s.data.wins
	local level = Boards.levelScore(s.data.level, s.data.xp)
	if wins ~= s.board.wins and write(Boards.WINS, key, wins) then
		s.board.wins = wins
	end
	if level ~= s.board.level and write(Boards.LEVEL, key, level) then
		s.board.level = level
	end
end

return Boards
