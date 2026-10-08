--[[
World client (V3): brings the backdrop and the lobby island to life. Everything here is local and cosmetic, except
the trampoline launch (the local character is network-owned by this client).

	Sea          wave textures scroll, clouds drift
	Zone         PLAY square border states + the "3/12 READY  0:14" board
	Props        lucky wheel idle spin + bulb chase, chest ready-glow + lid pop on claim
	Trampolines  local bounce on the beach trampolines
	LiveTv       "LIVE: <game> - 4 ALIVE" / "NEXT GAME 0:14" on the lobby TV

The lobby is bound whenever a Model named "Lobby" is (or later becomes) a child of workspace, so a late or rebuilt
lobby never blocks this script; per-lobby connections are cleaned when it leaves.
]]
local Sea = require(script:WaitForChild("Sea"))
local LobbyWatch = require(script:WaitForChild("LobbyWatch"))
local Zone = require(script:WaitForChild("Zone"))
local Props = require(script:WaitForChild("Props"))
local Trampolines = require(script:WaitForChild("Trampolines"))
local LiveTv = require(script:WaitForChild("LiveTv"))

Sea.start()

LobbyWatch.onLobby(function(lobby, trove)
	Zone.bind(lobby, trove)
	Props.bind(lobby, trove)
	Trampolines.bind(lobby, trove)
	LiveTv.bind(lobby, trove)
end)
