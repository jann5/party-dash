-- Party Dash: server-side event bus between systems. FROZEN CONTRACT.
-- Lets Core announce round results without knowing about Economy/Solo (which are built later).
--   local Signals = require(ServerScriptService.Server.Signals)
--   Signals.RoundFinished:Connect(function(result) ... end)
--
-- Payloads:
--   RoundStarted(info)       info = { roundNumber, minigameId, modifierId?, participants = {Player} }
--   PlayerEliminated(p, info) info = { minigameId, placement: number, survivedSeconds: number }
--   RoundFinished(result)    result = {
--        roundNumber, minigameId, modifierId?, kind = "survival"|"score",
--        participants = {Player}, winners = {Player},
--        placements = { [Player] = 1-based place }, survived = { [Player] = seconds },
--        scores = { [Player] = number } (score kind only) }
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

return Signals
