-- Party Dash: server entry point. Boots Core (lighting, permanent lobby, players, world backdrop, registry, join
-- square, vote, death flow) and runs the round loop. Other systems boot themselves from their own init scripts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local Core = Server:WaitForChild("Core")

-- Shared remotes/state must exist before any client asks for them.
require(ReplicatedStorage:WaitForChild("Shared").Knockback).startServer()
require(ReplicatedStorage.Shared.GameState).get()

local Death = require(Core.Death)
local Debug = require(Core.Debug)
local Join = require(Core.Join)
local LightingSetup = require(Core.LightingSetup)
local Places = require(Core.Places)
local PlayerSetup = require(Core.PlayerSetup)
local Registry = require(Core.Registry)
local Revive = require(Core.Revive)
local RoundLoop = require(Core.RoundLoop)
local State = require(Core.State)
local Vote = require(Core.Vote)
local World = require(Core.World)

Players.RespawnTime = 2
Debug.report() -- Studio: list active Debug_* hooks; live server: say that leftovers are ignored
LightingSetup.apply()
Places.init() -- the permanent lobby first, so new characters always have somewhere to stand
PlayerSetup.init() -- leaderstats, attributes, character placement
Registry.init(Server)
Death.init() -- remotes Core_Death / Core_DeathChoice
Vote.init() -- remote Core_Vote
Join.start() -- the PLAY square

-- Studio command bar / execute_luau may run another VM: expose the live round through State's bridge.
local api = State.hostContextApi()
for name, fn in Revive.hostApi() do
	api[name] = fn
end
State.host(api)

World.init() -- sea and backdrop (may take a few frames)
RoundLoop.run()
