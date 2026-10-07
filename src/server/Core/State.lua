--[[
Party Dash Core: shared server-side round state (written by RoundLoop/Death, read by every Core module and Solo).

	local State = require(ServerScriptService.Server.Core.State)
	State.mainContext()   -- the running main-round Context (Intro .. End), or nil. This is the documented way for
	                      -- tests and other systems to reach the live `ctx` (ctx.knockback, ctx.intensity(), ...).

Studio note: the command bar / execute_luau may run in another Luau VM with its own copy of every ModuleScript
(and therefore an empty State). The live server registers a BindableFunction "CoreApi" next to this module
(State.host), and copies in other VMs forward to it: State.mainContext() then returns a thin proxy whose functions
run on the live Context (ctx.knockback(...), ctx.intensity(), ctx:_aliveCount(), ...).
]]
local State = {
	ctx = nil :: any, -- the main round's Context while a map is loaded (Intro .. End)
	arenaActive = false, -- true from Intro until the players are back in the lobby
	roundNumber = 0,
	lastPlayed = {} :: { [Player]: number }, -- round number each player last took part in
	deathBeat = {} :: { [Player]: any }, -- players between their knock-out and the teleport to the lobby
}

local BRIDGE_NAME = "CoreApi"
local hosting = false

-- True if the main round's context is responsible for (re)placing this player's character.
function State.mainCtxOwns(player: Player): boolean
	local ctx = State.ctx
	return ctx ~= nil and ctx:_wantsCharacter(player)
end

-- Called once by Main in the game's own VM: publishes `api` ({ [method] = fn }) through the bridge.
function State.host(api: { [string]: (...any) -> ...any })
	hosting = true
	local old = script.Parent:FindFirstChild(BRIDGE_NAME)
	if old then
		old:Destroy()
	end
	local bridge = Instance.new("BindableFunction")
	bridge.Name = BRIDGE_NAME
	bridge.OnInvoke = function(method: string, ...)
		local fn = api[method]
		if type(fn) ~= "function" then
			return nil
		end
		return fn(...)
	end
	bridge.Parent = script.Parent
end

-- True in the VM that runs the game (false in a command-bar copy of this module).
function State.isHost(): boolean
	return hosting
end

-- Calls a host API method from another VM (nil when the game is not running).
function State.forward(method: string, ...: any): ...any
	local bridge = script.Parent:FindFirstChild(BRIDGE_NAME)
	if not (bridge and bridge:IsA("BindableFunction")) then
		return nil
	end
	return bridge:Invoke(method, ...)
end

local function contextProxy()
	return setmetatable({}, {
		__index = function(_, key)
			if type(key) ~= "string" then
				return nil
			end
			if State.forward("ctxMemberType", key) ~= "function" then
				return State.forward("ctxCall", key)
			end
			if string.sub(key, 1, 1) == "_" then
				-- underscore members are methods: ctx:_aliveCount()
				return function(_self, ...)
					return State.forward("ctxCall", key, ...)
				end
			end
			return function(...)
				return State.forward("ctxCall", key, ...)
			end
		end,
	})
end

function State.mainContext(): any
	if hosting then
		return State.ctx
	end
	if State.forward("hasContext") == true then
		return contextProxy()
	end
	return nil
end

-- Host side of the proxy (registered by Main).
function State.hostContextApi(): { [string]: (...any) -> ...any }
	return {
		hasContext = function()
			return State.ctx ~= nil
		end,
		ctxMemberType = function(key: string)
			local ctx = State.ctx
			return ctx and type(ctx[key]) or nil
		end,
		ctxCall = function(key: string, ...)
			local ctx = State.ctx
			if not ctx then
				return nil
			end
			local member = ctx[key]
			if type(member) ~= "function" then
				return member
			end
			if string.sub(key, 1, 1) == "_" then
				return member(ctx, ...)
			end
			return member(...)
		end,
	}
end

return State
