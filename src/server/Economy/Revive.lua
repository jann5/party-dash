--!strict
-- Revive tokens (brief #28). The round side (offer window, 1 per round, placing the player) belongs to Core:
--   require(ServerScriptService.Server.Core.Revive).status(player) -> "ok" | ...   .revive(player) -> boolean
-- Economy only spends tokens: Economy_UseRevive (death panel button) and the Revive product after its receipt.
-- A token is never lost: if Core can't take the player back, the token stays (ReviveTokens attribute).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Feedback = require(script.Parent.Feedback)
local Limiter = require(script.Parent.Limiter)
local Mirror = require(script.Parent.Mirror)
local Sessions = require(script.Parent.Sessions)

local Revive = {}

local STATUS_TEXT = {
	noOffer = "No revive right now",
	expired = "Too late to revive!",
	used = "Already revived this round!",
	notEligible = "Can't revive right now",
}

type CoreRevive = { status: ((Player) -> string)?, revive: (Player) -> boolean }

-- Core's Revive module, or nil when it doesn't exist (yet).
local function coreRevive(): CoreRevive?
	local core = script.Parent.Parent:FindFirstChild("Core")
	local module = core and core:FindFirstChild("Revive")
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local ok, api = pcall(require, module)
	if ok and type(api) == "table" and type(api.revive) == "function" then
		return api :: any
	end
	return nil
end

-- (canRevive, reason message)
local function check(player: Player): (boolean, string, CoreRevive?)
	local api = coreRevive()
	if not api then
		return false, "Revive isn't available here", nil
	end
	if type(api.status) == "function" then
		local ok, status = pcall(api.status, player)
		if not ok or status ~= "ok" then
			return false, STATUS_TEXT[if ok then status else "notEligible"] or STATUS_TEXT.notEligible, api
		end
	end
	return true, "", api
end

local function revive(api: CoreRevive, player: Player): boolean
	local ok, result = pcall(api.revive, player)
	if not ok then
		warn("[Economy] Core revive failed:", result)
	end
	return ok and result == true
end

local function freeRevives(): boolean
	return RunService:IsStudio() and workspace:GetAttribute("Debug_FreeRevive") == true
end

-- Economy_UseRevive: spend one token (none needed with Debug_FreeRevive in Studio) and go back in.
function Revive.use(player: Player): (boolean, string)
	local s = Sessions.get(player)
	if not s then
		return false, "Your save is still loading..."
	end
	local free = freeRevives()
	if s.data.reviveTokens <= 0 and not free then
		return false, "No revives left!"
	end
	local can, message, api = check(player)
	if not can or not api then
		return false, message
	end
	if not free then
		s.data.reviveTokens -= 1 -- spent before the (possibly yielding) revive so a double tap can't reuse it
		Mirror.revives(s)
	end
	if not revive(api, player) then
		if not free then
			s.data.reviveTokens += 1
			Mirror.revives(s)
		end
		return false, "Can't revive right now"
	end
	Sessions.saveSoon(player)
	return true, "You're back!"
end

-- After a Revive receipt is saved: the bought token (already granted) is used right away when possible.
function Revive.afterPurchase(player: Player)
	local s = Sessions.get(player)
	if not s then
		return
	end
	local can, _, api = check(player)
	if can and api and s.data.reviveTokens > 0 then
		s.data.reviveTokens -= 1
		Mirror.revives(s)
		if revive(api, player) then
			Feedback.result(player, true, "revive", "", "You're back!")
			Sessions.saveSoon(player)
			return
		end
		s.data.reviveTokens += 1
		Mirror.revives(s)
	end
	Feedback.result(player, false, "revive", "", "Revive saved for next time!")
	Feedback.toast(player, "Revive saved for next time!", Theme.Colors.Pink)
end

function Revive.start()
	Net.event(Rules.Remote.UseRevive).OnServerEvent:Connect(function(player: Player)
		if not Limiter.allow(player, "revive", 2, 1) then
			return
		end
		local ok, message = Revive.use(player)
		Feedback.result(player, ok, "revive", "", message)
	end)
end

return Revive
