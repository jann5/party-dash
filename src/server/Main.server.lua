-- Party Dash: server entry point. Boots Core (world, lobby, stands, players, registry) and runs the round loop.
-- Other systems boot themselves from their own init scripts; this file only owns Core.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local Core = Server:WaitForChild("Core")

-- Shared remotes/state must exist before any client asks for them.
require(ReplicatedStorage:WaitForChild("Shared").Knockback).startServer()
require(ReplicatedStorage.Shared.GameState).get()

local LightingSetup = require(Core.LightingSetup)
local World = require(Core.World)
local Places = require(Core.Places)
local PlayerSetup = require(Core.PlayerSetup)
local Registry = require(Core.Registry)
local RoundLoop = require(Core.RoundLoop)

Players.RespawnTime = 2
LightingSetup.apply() -- bright, saturated cartoon look
Places.init() -- spectator stands + lobby island first, so new characters always have somewhere to stand
PlayerSetup.init() -- leaderstats, attributes, character placement
World.init() -- backdrop (removes the gray Baseplate)
Registry.init(Server)
RoundLoop.run()
