-- Party Dash: server-side event bus between systems. FROZEN CONTRACT (v2: additive fields, PlayerRevived).
-- Lets Core announce round results without knowing about Economy/Solo (which are built later).
--   local Signals = require(ServerScriptService.Server.Signals)
--   Signals.RoundFinished:Connect(function(result) ... end)
--
-- Payloads:
--   RoundStarted(info)       info = { roundNumber, minigameId, modifierId?, participants = {Player} }
--   PlayerEliminated(p, info) info = { minigameId, placement: number, survivedSeconds: number,
--        reason: string ("fell"|"died"|"left"|"bomb"|..., [v2]), killer: Player? ([v2] KO credit, see ctx.credit),
--        participants: number ([v2]), aliveLeft: number ([v2] alive after this elimination) }
--        [v2] May fire twice for the same player in one round if they were revived in between.
--   RoundFinished(result)    result = {
--        roundNumber, minigameId, modifierId?, kind = "survival"|"score",
--        participants = {Player}, winners = {Player},
--        placements = { [Player] = 1-based place }, survived = { [Player] = seconds },
--        scores = { [Player] = number } (score kind only),
--        kos = { [Player] = number } ([v2] KO credits this round), mvp = Player? ([v2] most KOs, >= 1) }
--   PlayerRevived(p, info)   [v2] info = { minigameId, roundNumber } (after a paid/free revive put them back in)
--   SoloFinished(p, info)    info = { minigameId, seconds: number, isRecord: boolean }
local Signals = {}

local function newSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		handlers[fn] = true
		return {
			Disconnect = function()
				handlers[fn] = nil
			end,
		}
	end
	function signal:Fire(...)
		for fn in handlers do
			task.spawn(fn, ...)
		end
	end
	return signal
end

Signals.RoundStarted = newSignal()
Signals.PlayerEliminated = newSignal()
Signals.RoundFinished = newSignal()
Signals.SoloFinished = newSignal()
Signals.PlayerRevived = newSignal() -- [v2]

return Signals
