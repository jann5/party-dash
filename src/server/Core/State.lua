-- Party Dash Core: shared server-side round state (read by Places/PlayerSetup, written by RoundLoop).
local State = {
	ctx = nil :: any, -- the main round's Context while a map is loaded (Intro .. End)
	arenaActive = false, -- true from Intro until the lobby is back
	roundNumber = 0,
	lastPlayed = {} :: { [Player]: number }, -- round number each player last took part in
}

-- True if the main round's context is responsible for (re)placing this player's character.
function State.mainCtxOwns(player: Player): boolean
	local ctx = State.ctx
	return ctx ~= nil and ctx:_wantsCharacter(player)
end

return State
