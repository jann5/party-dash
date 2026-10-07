--[[
Party Dash Core: revive (brief #28). Puts a knocked-out player back into the RUNNING main round.

	local Revive = require(ServerScriptService.Server.Core.Revive)
	Revive.status(player) -> "ok" | "noOffer" | "expired" | "used" | "notEligible"
	Revive.revive(player) -> boolean   -- Economy calls it after a purchase / token; false = grant a token instead

Offer rules (made by Core when the player is knocked out, Revive.offer):
	- survival main round, the player did not leave, and they have not used Config.REVIVE_MAX_PER_ROUND revives;
	- the round started with >= Config.REVIVE_MIN_PARTICIPANTS players and >= Config.REVIVE_MIN_OTHERS_ALIVE others
	  are still alive (checked again when the revive is granted, so a 1v1 final can never be bought);
	- the window is Config.REVIVE_WINDOW seconds (Player attribute ReviveUntil, server time).
	Debug_FreeRevive (Studio): offered even with 1 participant, and the round waits for an open window to close.
Works from the Studio command bar too (calls are forwarded to the live server through State's bridge).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Debug = require(script.Parent.Debug)
local State = require(script.Parent.State)

local Revive = {}

local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player")
end

local function mainContext(): any
	local ctx = State.ctx
	if ctx and not ctx.isSolo then
		return ctx
	end
	return nil
end

-- Called by Death when a main-round player is knocked out. Returns (offered, endsAt).
function Revive.offer(ctx: any, player: Player, reason: string): (boolean, number)
	if ctx.isSolo or ctx.definition.kind ~= "survival" or reason == "left" or reason == "stuck" then
		return false, 0
	end
	if ctx:_revivesUsed(player) >= Config.REVIVE_MAX_PER_ROUND then
		return false, 0
	end
	local free = Debug.freeRevive()
	if not free then
		if #ctx.allPlayers() < Config.REVIVE_MIN_PARTICIPANTS or ctx:_aliveCount() < Config.REVIVE_MIN_OTHERS_ALIVE then
			return false, 0
		end
	end
	local endsAt = workspace:GetServerTimeNow() + Config.REVIVE_WINDOW
	ctx:_offerRevive(player, endsAt)
	player:SetAttribute("ReviveUntil", endsAt)
	if free then
		ctx:_holdEnd(endsAt)
	end
	return true, endsAt
end

function Revive.status(player: Player): string
	if not State.isHost() then
		return State.forward("reviveStatus", player) or "notEligible"
	end
	local ctx = mainContext()
	if not isPlayer(player) or player.Parent ~= Players or not ctx or not ctx:_isParticipant(player) then
		return "notEligible"
	end
	if ctx.isAlive(player) then
		return "notEligible"
	end
	if ctx:_revivesUsed(player) >= Config.REVIVE_MAX_PER_ROUND then
		return "used"
	end
	local over = ctx:_isOver()
	if over or not ctx:_isRunning() then
		return "notEligible"
	end
	local endsAt = ctx:_reviveOffer(player)
	if not endsAt then
		return "noOffer"
	end
	if workspace:GetServerTimeNow() > endsAt then
		return "expired"
	end
	if not Debug.freeRevive() and ctx:_aliveCount() < Config.REVIVE_MIN_OTHERS_ALIVE then
		return "noOffer"
	end
	return "ok"
end

function Revive.revive(player: Player): boolean
	if not State.isHost() then
		return State.forward("revive", player) == true
	end
	if Revive.status(player) ~= "ok" then
		return false
	end
	if not mainContext():_revive(player) then
		return false
	end
	player:SetAttribute("ReviveUntil", 0)
	return true
end

-- Host side of the command-bar bridge (registered by Main).
function Revive.hostApi(): { [string]: (...any) -> ...any }
	return {
		reviveStatus = Revive.status,
		revive = Revive.revive,
	}
end

return Revive
