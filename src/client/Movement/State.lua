-- Local (predicted) movement state shared by the client movement modules, plus a tiny event hub.
-- Controller writes it; Pose / Effects / Hud / JumpFx read it and listen to its events:
--   "Dash"(rig, dir: Vector3, grounded: boolean)   a local dash just started
--   "DashEnd"(rig)
--   "DashDenied"()                                  dash pressed while it cannot fire
--   "DashReady"()                                   the dash recharged
--   "SlideStart"(rig, dir: Vector3)
--   "SlideEnd"(rig, reason: string)                 "time" | "jump" | "air" | "blocked" | "dash" | "cancel"
--   "Jump"(rig, longJump: boolean)                  the local character left the ground by jumping
-- Times are os.clock().
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local State = {
	dashing = false,
	sliding = false,
	airDashUsed = false,
	dashCooldown = Config.DASH_COOLDOWN, -- length of the current dash cooldown
	dashReadyAt = 0, -- when the next dash is allowed
	slideReadyAt = 0, -- when the next slide is allowed (cooldown counts from the END of a slide)
}

local listeners: { [string]: { (...any) -> () } } = {}

function State.on(event: string, fn: (...any) -> ()): () -> ()
	local list = listeners[event]
	if not list then
		list = {}
		listeners[event] = list
	end
	table.insert(list, fn)
	return function()
		local index = table.find(list, fn)
		if index then
			table.remove(list, index)
		end
	end
end

-- Listeners run right away in their own thread, so the UI reacts in the same frame and one failing listener
-- never breaks the controller.
function State.fire(event: string, ...: any)
	local list = listeners[event]
	if not list then
		return
	end
	for _, fn in table.clone(list) do
		task.spawn(fn, ...)
	end
end

-- 0..1 dash recharge progress.
function State.dashProgress(now: number): number
	local cooldown = math.max(0.05, State.dashCooldown)
	return math.clamp(1 - (State.dashReadyAt - now) / cooldown, 0, 1)
end

-- A fresh life starts with everything ready.
function State.reset()
	State.dashing = false
	State.sliding = false
	State.airDashUsed = false
	State.dashCooldown = Config.DASH_COOLDOWN
	State.dashReadyAt = 0
	State.slideReadyAt = 0
end

return State
