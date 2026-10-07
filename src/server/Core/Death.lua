--[[
Party Dash Core: what happens when a main-round player is knocked out (brief #16, #17) or revived (#28).

	t = 0              Player InRound = false, Eliminated = true; Core_Fx "splash" (fell: on the sea surface when the
	                   body reaches it), "boom" (bomb) or "poof" (+ "ko" when an attacker gets the credit) to the round
	                   audience;
	                   Announce.big(victim, "OUT!", "#5 of 9"); feed "<Killer> knocked out <Name>" / "<Name> is out!";
	                   revive offer (Core.Revive).
	t = DEATH_BEAT     the character goes to a lobby spawn and the victim gets remote Core_Death:
	                   { reason, placement, total, survived, aliveLeft, minigameId, killerName?,
	                     revive = { offered, endsAt, tokens } }  -> the HUD shows SPECTATE / LOBBY / REVIVE.
	Core_DeathChoice   ("spectate" | "lobby") sets / clears Player Spectating. Anyone who is not alive in the round
	                   may use it (lobby players use it to WATCH LIVE). Spectating is never set automatically.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Net = require(Shared.Net)
local Theme = require(Shared.Theme)

local Server = script.Parent.Parent
local Announce = require(Server.Announce)
local Signals = require(Server.Signals)

local Fx = require(script.Parent.Fx)
local Places = require(script.Parent.Places)
local Revive = require(script.Parent.Revive)
local State = require(script.Parent.State)
local Teleport = require(script.Parent.Teleport)

local Death = {}

Death.CHOICE_RATE_LIMIT = 0.3
Death.FEET_BELOW_ROOT = 3 -- studs from the HumanoidRootPart down to the feet (standing R15)
Death.EXPLOSION_REASONS = { bomb = true, exploded = true } -- ctx.eliminate reasons drawn as a "boom"

local deathRemote: RemoteEvent? = nil
local lastChoice: { [Player]: number } = {}
local pendingChoice: { [Player]: string } = {}
local choiceScheduled: { [Player]: boolean } = {}

-- Seconds until a body at `root` touches the sea surface (0 when it is already in the water).
local function timeToWater(root: BasePart): number
	local height = root.Position.Y - Death.FEET_BELOW_ROOT - Config.SEA_LEVEL
	if height <= 0.25 then
		return 0
	end
	local g = workspace.Gravity
	local down = -root.AssemblyLinearVelocity.Y -- downward speed (negative while still rising)
	return (-down + math.sqrt(down * down + 2 * g * height)) / g
end

-- The knock-out moment: the splash plays when the body actually hits the water, then the camera holds there.
local function playSplash(player: Player, audience: { Player })
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local untilSplash = math.min(timeToWater(root), Config.DEATH_BEAT * 0.75)
	task.delay(untilSplash, function()
		if not root.Parent or not State.deathBeat[player] then
			return
		end
		Fx.send("splash", Vector3.new(root.Position.X, Config.SEA_LEVEL, root.Position.Z), audience)
		root.Anchored = true -- hold the body (and the camera) at the splash until the beat ends
	end)
end

local function payload(ctx: any, player: Player, info: { [string]: any }, round: { [string]: any })
	local offered = Revive.status(player) == "ok"
	return {
		reason = info.reason,
		placement = info.placement,
		total = info.participants,
		survived = math.floor(info.survivedSeconds * 10 + 0.5) / 10,
		aliveLeft = ctx:_aliveCount(),
		minigameId = round.minigameId,
		killerName = info.killer and info.killer.DisplayName or nil,
		revive = {
			offered = offered,
			endsAt = if offered then player:GetAttribute("ReviveUntil") or 0 else 0,
			tokens = tonumber(player:GetAttribute("ReviveTokens")) or 0,
		},
	}
end

-- Context onEliminated for the main round. round = { minigameId, roundNumber }.
function Death.onEliminated(ctx: any, player: Player, info: { [string]: any }, round: { [string]: any })
	local inServer = player.Parent == Players
	local knockedOut = inServer and info.reason ~= "left"
	-- First, while nothing has yielded: the revive offer (Debug_FreeRevive also holds the round open).
	if knockedOut then
		Revive.offer(ctx, player, info.reason)
		player:SetAttribute("Eliminated", true) -- before InRound flips, so the HUD never flashes the lobby layout
	end
	if inServer then
		player:SetAttribute("InRound", false)
	end
	GameState.write("Alive", ctx:_aliveCount())
	Signals.PlayerEliminated:Fire(player, {
		minigameId = round.minigameId,
		placement = info.placement,
		survivedSeconds = info.survivedSeconds,
		reason = info.reason,
		killer = info.killer,
		participants = info.participants,
		aliveLeft = info.aliveLeft,
	})
	local everyone = Places.audience()
	if not knockedOut then
		Announce.feed(everyone, ("%s left the round"):format(player.DisplayName))
		return
	end

	local token = {}
	State.deathBeat[player] = token
	local audience = Places.roundAudience()
	if info.reason == "fell" then
		playSplash(player, audience)
	elseif info.position then
		Fx.send(if Death.EXPLOSION_REASONS[info.reason] then "boom" else "poof", info.position, audience)
	end
	local killer: Player? = info.killer
	if killer and info.position then
		Fx.send("ko", info.position, audience)
	end

	Announce.big(player, "OUT!", ("#%d of %d"):format(info.placement, info.participants), Theme.Colors.Red)
	if killer then
		Announce.feed(everyone, ("%s knocked out %s"):format(killer.DisplayName, player.DisplayName))
		if killer.Parent == Players then
			Announce.toast(killer, ("You knocked out %s!"):format(player.DisplayName), Theme.Colors.Green)
		end
	else
		Announce.feed(everyone, ("%s is out!"):format(player.DisplayName))
	end

	task.delay(Config.DEATH_BEAT, function()
		if State.deathBeat[player] ~= token then
			return -- revived (or knocked out again) in the meantime
		end
		State.deathBeat[player] = nil
		if player.Parent ~= Players or ctx.isAlive(player) then
			return
		end
		if not Places.sendToLobby(player) then
			Teleport.setAnchored(player, false) -- dead body: the respawn lands in the lobby anyway
		end
		if deathRemote then
			deathRemote:FireClient(player, payload(ctx, player, info, round))
		end
	end)
end

-- Context onRevived for the main round (called synchronously from ctx:_revive).
function Death.onRevived(ctx: any, player: Player, round: { [string]: any })
	State.deathBeat[player] = nil
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute("InRound", true)
	player:SetAttribute("Eliminated", false)
	player:SetAttribute("Spectating", false)
	player:SetAttribute("ReviveUntil", 0)
	GameState.write("Alive", ctx:_aliveCount())
	Signals.PlayerRevived:Fire(player, { minigameId = round.minigameId, roundNumber = round.roundNumber })
	Announce.feed(Places.audience(), ("%s is back!"):format(player.DisplayName))
	Announce.big(player, "REVIVED!", nil, Theme.Colors.Green)
	local parts = Teleport.parts(player)
	if parts then
		Fx.send("poof", parts.root.Position, Places.roundAudience())
	end
end

local function applyChoice(player: Player, choice: string)
	if player.Parent ~= Players or player:GetAttribute("InSolo") == true or player:GetAttribute("InRound") == true then
		return -- gone, in a Solo run, or alive in the round: nothing to choose
	end
	local watching = choice == "spectate"
	player:SetAttribute("Spectating", watching)
	Places.setWatchFocus(player, watching)
end

-- Rate limited, but a quick change of mind is never lost: inside the cooldown the LATEST choice is kept and
-- applied when the cooldown ends.
local function onChoice(player: Player, choice: any)
	if choice ~= "spectate" and choice ~= "lobby" then
		return
	end
	pendingChoice[player] = choice
	local remaining = (lastChoice[player] or -math.huge) + Death.CHOICE_RATE_LIMIT - os.clock()
	if remaining > 0 then
		if not choiceScheduled[player] then
			choiceScheduled[player] = true
			task.delay(remaining, function()
				choiceScheduled[player] = nil
				local latest = pendingChoice[player]
				pendingChoice[player] = nil
				if latest then
					lastChoice[player] = os.clock()
					applyChoice(player, latest)
				end
			end)
		end
		return
	end
	pendingChoice[player] = nil
	lastChoice[player] = os.clock()
	applyChoice(player, choice)
end

function Death.init()
	deathRemote = Net.event("Core_Death")
	Net.event("Core_DeathChoice").OnServerEvent:Connect(onChoice)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastChoice[player] = nil
		pendingChoice[player] = nil
		State.deathBeat[player] = nil
	end)
end

return Death
