--!nonstrict
-- Read-only view of the replicated round state for the HUD: GameState attributes, local-player membership and
-- a coalesced change watcher (many attributes changing in one frame -> one refresh).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameState = require(ReplicatedStorage.Shared.GameState)

local State = {}

State.player = Players.LocalPlayer
State.gs = GameState.get()

function State.get(key: string): any
	return State.gs:GetAttribute(key)
end

function State.str(key: string): string
	local v = State.gs:GetAttribute(key)
	return typeof(v) == "string" and v or ""
end

function State.num(key: string): number
	local v = State.gs:GetAttribute(key)
	return typeof(v) == "number" and v or 0
end

function State.phase(): string
	local p = State.gs:GetAttribute("Phase")
	return typeof(p) == "string" and p or "Waiting"
end

-- Player attribute flag (missing = false).
function State.flag(name: string): boolean
	return State.player:GetAttribute(name) == true
end

-- A "round member" sees round overlays: alive in the round, knocked out of it, or watching it.
function State.isMember(): boolean
	return State.flag("InRound") or State.flag("Eliminated") or State.flag("Spectating")
end

function State.now(): number
	return Workspace:GetServerTimeNow()
end

-- Seconds until PhaseEnd (0 when the phase is open-ended).
function State.timeLeft(): number
	local e = State.num("PhaseEnd")
	if e <= 0 then
		return 0
	end
	return math.max(0, e - State.now())
end

-- Calls fn() once per frame at most, after any of the listed GameState / Player attributes changed, and once
-- right away. For long-lived HUD modules (connections live as long as the session).
function State.watch(gameKeys: { string }, playerKeys: { string }, fn: () -> ())
	local queued = false
	local function schedule()
		if queued then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			fn()
		end)
	end
	for _, key in gameKeys do
		State.gs:GetAttributeChangedSignal(key):Connect(schedule)
	end
	for _, key in playerKeys do
		State.player:GetAttributeChangedSignal(key):Connect(schedule)
	end
	schedule()
end

return State
