-- Party Dash movement (server). The client owns its character's physics and performs the dash / slide itself;
-- the server is the authority for the replicated state that minigames trust (ARCHITECTURE "character attributes"):
--   Dashing                     true for Config.DASH_DURATION after every ACCEPTED dash; DashCount +1 per dash
--   Sliding                     true while an accepted slide lasts; SlideCount +1 per slide
--   SlideStartAt / SlideEndAt   the client-reported slide window (server time, clamped to [now - 0.25, now]);
--                               SlideEndAt is written when the slide ends (equals SlideStartAt while sliding)
-- Validation: finite clamped timestamps, server-side cooldowns with a small tolerance, rate limits, nothing while
-- Stunned / anchored / dead, a slide must start from the ground and ends if it stays airborne.
-- It also owns the movement defaults (walk speed, a Jump Boost jump power that survives every reset, no auto-jump,
-- no Shift Lock since LeftShift dashes, camera zoom 6..45), the Forgive sampler and the jump-trick relay.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Stats = require(Shared.Movement.Stats)
require(Shared.Audio) -- creates the SoundGroups that the clients' dash / slide sounds play through

local Forgive = require(script.Forgive)
local Limiter = require(script.Limiter)

local JUMP_TRICK_COUNT = 3 -- must match TRICKS in the client JumpFx module
local FX_MIN_INTERVAL = 0.12 -- per kind ("Jump" / "Land")
local REJECT_REPLY_GAP = 0.2 -- at most one dash "Reject" reply per this many seconds
local SLIDE_GROUND_LOOKBACK = 0.6 -- a slide must have touched the ground this recently (covers a buffered landing)
local SLIDE_MAX_AIR = 0.35 -- an accepted slide that stays airborne this long is ended
local SLIDE_TIMEOUT_SLACK = 0.25 -- the server ends a slide on its own this long after it should be over
local ROBLOX_DEFAULT_WALK = 16
local ROBLOX_DEFAULT_JUMP = 50

type MoveState = {
	character: Model?,
	connections: { RBXScriptConnection },
	lastDashAt: number, -- client-reported server time of the last accepted dash
	dashToken: number,
	sliding: boolean,
	slideStartAt: number,
	slideReceivedAt: number,
	slideEndAt: number, -- server time the last slide ended (the slide cooldown counts from here)
	slideToken: number,
	lastRejectAt: number,
	lastFx: { [string]: number },
	jumpWrote: number?, -- the JumpPower we last applied
}

local states: { [Player]: MoveState } = {}

local dashLimiter = Limiter.new(6, 4)
local slideLimiter = Limiter.new(8, 6) -- start + end per slide
local fxLimiter = Limiter.new(10, 6)

local dashRemote = Net.event(Stats.Remote.Dash)
local slideRemote = Net.event(Stats.Remote.Slide)
local jumpFxRemote = Net.unreliable(Stats.Remote.JumpFx)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stateOf(player: Player): MoveState
	local s = states[player]
	if not s then
		s = {
			character = nil,
			connections = {},
			lastDashAt = -math.huge,
			dashToken = 0,
			sliding = false,
			slideStartAt = 0,
			slideReceivedAt = 0,
			slideEndAt = -math.huge,
			slideToken = 0,
			lastRejectAt = -math.huge,
			lastFx = {},
			jumpWrote = nil,
		}
		states[player] = s
	end
	return s
end

---------------------------------------------------------------------------------------------------
-- Defaults (set through StarterPlayer so every character is born with them)

StarterPlayer.CharacterWalkSpeed = Config.WALK_SPEED
StarterPlayer.CharacterUseJumpPower = true
StarterPlayer.CharacterJumpPower = Config.JUMP_POWER
StarterPlayer.AutoJumpEnabled = false
StarterPlayer.EnableMouseLockOption = false -- LeftShift is the dash key, not Shift Lock
StarterPlayer.CameraMaxZoomDistance = Stats.CAMERA_MAX_ZOOM
StarterPlayer.CameraMinZoomDistance = Stats.CAMERA_MIN_ZOOM

local function applyPlayerDefaults(player: Player)
	-- Players who joined before this script ran keep the values copied at join time: set them directly too.
	pcall(function()
		player.DevEnableMouseLock = false
		player.CameraMaxZoomDistance = Stats.CAMERA_MAX_ZOOM
		player.CameraMinZoomDistance = Stats.CAMERA_MIN_ZOOM
	end)
end

---------------------------------------------------------------------------------------------------
-- Jump Boost: JumpPower = Stats.jumpPower(player), re-applied whenever something resets it

-- A value that means "somebody put the default back" (Core after a freeze, a respawn, an old boost level).
local function isResetValue(s: MoveState, value: number): boolean
	if math.abs(value - Config.JUMP_POWER) < 0.01 or math.abs(value - ROBLOX_DEFAULT_JUMP) < 0.01 then
		return true
	end
	return s.jumpWrote ~= nil and math.abs(value - s.jumpWrote) < 0.01
end

local function applyJumpPower(player: Player, humanoid: Humanoid)
	if not humanoid.Parent then
		return
	end
	local s = stateOf(player)
	if not humanoid.UseJumpPower then
		humanoid.UseJumpPower = true
	end
	local current = humanoid.JumpPower
	local target = Stats.jumpPower(player)
	if current <= 0 then
		return -- 0 = frozen on purpose by another system: leave it, we re-apply when it comes back
	end
	if math.abs(current - target) < 0.01 then
		s.jumpWrote = current
		return
	end
	if isResetValue(s, current) then
		s.jumpWrote = target
		humanoid.JumpPower = target
	end
end

---------------------------------------------------------------------------------------------------
-- Dash / slide state

-- The live character if it may start a dash / slide right now.
local function actingCharacter(player: Player): Model?
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	if humanoid.Health <= 0 or root.Anchored or character:GetAttribute("Stunned") == true then
		return nil
	end
	return character
end

local function endSlide(player: Player, s: MoveState, endAt: number)
	if not s.sliding then
		return
	end
	s.sliding = false
	s.slideToken += 1
	local finish = math.clamp(endAt, s.slideStartAt, s.slideStartAt + Config.SLIDE_DURATION)
	s.slideEndAt = finish
	local character = s.character
	if character and character.Parent then
		character:SetAttribute("Sliding", false)
		character:SetAttribute("SlideEndAt", finish)
	end
	Forgive.noteSlide(player, s.slideStartAt, finish)
end

local function endDash(s: MoveState)
	s.dashToken += 1
	local character = s.character
	if character and character.Parent then
		character:SetAttribute("Dashing", false)
	end
end

local function startSlide(player: Player, s: MoveState, character: Model, at: number, received: number)
	s.sliding = true
	s.slideStartAt = at
	s.slideReceivedAt = received
	s.slideToken += 1
	local token = s.slideToken
	local predictedEnd = at + Config.SLIDE_DURATION
	-- SlideEndAt is the real end, written when the slide ends; while Sliding is true it equals SlideStartAt.
	-- (Forgive keeps the predicted window [at, at + SLIDE_DURATION] internally.)
	character:SetAttribute("SlideStartAt", at)
	character:SetAttribute("SlideEndAt", at)
	character:SetAttribute("SlideCount", (tonumber(character:GetAttribute("SlideCount")) or 0) + 1)
	character:SetAttribute("Sliding", true)
	Forgive.noteSlide(player, at, predictedEnd)
	-- The client reports the end itself; this only covers a lost / missing end message.
	task.delay(math.max(0.05, predictedEnd + SLIDE_TIMEOUT_SLACK - received), function()
		if s.slideToken == token then
			endSlide(player, s, predictedEnd)
		end
	end)
end

local function reject(player: Player, s: MoveState, remaining: number)
	local t = os.clock()
	if t - s.lastRejectAt < REJECT_REPLY_GAP then
		return
	end
	s.lastRejectAt = t
	dashRemote:FireClient(player, "Reject", remaining)
end

---------------------------------------------------------------------------------------------------
-- Characters

local function onCharacter(player: Player, character: Model)
	local s = stateOf(player)
	for _, c in s.connections do
		c:Disconnect()
	end
	table.clear(s.connections)
	s.character = character
	s.sliding = false
	s.slideToken += 1
	s.dashToken += 1
	-- A fresh life starts ready (the client resets its cooldowns on respawn too).
	s.lastDashAt = -math.huge
	s.slideEndAt = -math.huge
	s.jumpWrote = nil

	character:SetAttribute("Dashing", false)
	character:SetAttribute("DashCount", 0)
	character:SetAttribute("Sliding", false)
	character:SetAttribute("SlideCount", 0)
	character:SetAttribute("SlideStartAt", 0)
	character:SetAttribute("SlideEndAt", 0)

	local function track(connection: RBXScriptConnection)
		table.insert(s.connections, connection)
	end

	-- A knockback stun cancels any dash / slide right away.
	track(character:GetAttributeChangedSignal("Stunned"):Connect(function()
		if character:GetAttribute("Stunned") == true then
			endDash(s)
			endSlide(player, s, now())
		end
	end))

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or player.Character ~= character then
		return
	end
	if humanoid.WalkSpeed == ROBLOX_DEFAULT_WALK then
		humanoid.WalkSpeed = Config.WALK_SPEED
	end
	humanoid.AutoJumpEnabled = false
	applyJumpPower(player, humanoid)

	track(humanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
		applyJumpPower(player, humanoid)
	end))
	track(humanoid:GetPropertyChangedSignal("UseJumpPower"):Connect(function()
		applyJumpPower(player, humanoid)
	end))
	track(humanoid.Died:Connect(function()
		endDash(s)
		endSlide(player, s, now())
	end))

	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") and player.Character == character then
		-- Core freezes players by anchoring the root; whatever it restores afterwards, Jump Boost comes back.
		track(root:GetPropertyChangedSignal("Anchored"):Connect(function()
			if root.Anchored then
				endSlide(player, s, now())
				return
			end
			applyJumpPower(player, humanoid)
			task.delay(0.1, applyJumpPower, player, humanoid)
		end))
	end
end

local function onPlayer(player: Player)
	stateOf(player)
	applyPlayerDefaults(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	player:GetAttributeChangedSignal("Upg_JumpBoost"):Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			applyJumpPower(player, humanoid)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Remotes

-- DASH (t): the client already moved; validate and publish the authoritative state.
dashRemote.OnServerEvent:Connect(function(player: Player, t: any)
	if not dashLimiter:allow(player) then
		return
	end
	local at = Stats.clampTime(t, now())
	if not at then
		return
	end
	local s = stateOf(player)
	local character = actingCharacter(player)
	if not character then
		return
	end
	local cooldown = Stats.dashCooldown(player)
	local elapsed = at - s.lastDashAt
	if elapsed < cooldown - Stats.DASH_TOLERANCE then
		reject(player, s, math.max(0, cooldown - elapsed))
		return
	end
	s.lastDashAt = at
	s.dashToken += 1
	local token = s.dashToken
	character:SetAttribute("DashCount", (tonumber(character:GetAttribute("DashCount")) or 0) + 1)
	character:SetAttribute("Dashing", true)
	Forgive.noteDash(player, at, at + Config.DASH_DURATION)
	-- A dash cancels a slide (the client does the same).
	endSlide(player, s, at)
	task.delay(Config.DASH_DURATION, function()
		if s.dashToken == token and character.Parent then
			character:SetAttribute("Dashing", false)
		end
	end)
end)

-- SLIDE (active, t): true = started at t, false = ended at t. Ending can only shorten the trusted window.
slideRemote.OnServerEvent:Connect(function(player: Player, active: any, t: any)
	if type(active) ~= "boolean" or not slideLimiter:allow(player) then
		return
	end
	local received = now()
	local at = Stats.clampTime(t, received)
	if not at then
		return
	end
	local s = stateOf(player)
	if not active then
		endSlide(player, s, at)
		return
	end
	local character = actingCharacter(player)
	if not character or s.sliding or character ~= s.character then
		return
	end
	if at - s.slideEndAt < Stats.slideCooldown() - Stats.SLIDE_TOLERANCE then
		return
	end
	if not Forgive.wasGrounded(player, at - SLIDE_GROUND_LOOKBACK) then
		return
	end
	startSlide(player, s, character, at, received)
end)

-- JUMP FX relay (purely visual, unreliable): ("Jump", trickIndex) or ("Land"), forwarded to everyone else.
jumpFxRemote.OnServerEvent:Connect(function(player: Player, kind: any, trick: any)
	if kind ~= "Jump" and kind ~= "Land" then
		return
	end
	if kind == "Jump" then
		if type(trick) ~= "number" or trick % 1 ~= 0 or trick < 1 or trick > JUMP_TRICK_COUNT then
			return
		end
	else
		trick = nil
	end
	if not fxLimiter:allow(player) then
		return
	end
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local s = stateOf(player)
	local t = os.clock()
	local last = s.lastFx[kind]
	if last and t - last < FX_MIN_INTERVAL then
		return
	end
	s.lastFx[kind] = t
	for _, other in Players:GetPlayers() do
		if other ~= player then
			jumpFxRemote:FireClient(other, kind, character, trick)
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- Boot

Forgive.start()

-- A slide only lasts while grounded: end it once it has been airborne too long (an off-ledge slide, or a
-- client asserting a slide in mid-air).
RunService.Heartbeat:Connect(function()
	local t = now()
	for player, s in states do
		if s.sliding then
			local character = player.Character
			local gone = not character or character ~= s.character or not character.Parent
			if gone or math.min(t - s.slideReceivedAt, Forgive.airTime(player)) > SLIDE_MAX_AIR then
				endSlide(player, s, t)
			end
		end
	end
end)

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
Players.PlayerRemoving:Connect(function(player)
	local s = states[player]
	if s then
		for _, c in s.connections do
			c:Disconnect()
		end
	end
	states[player] = nil
	dashLimiter:forget(player)
	slideLimiter:forget(player)
	fxLimiter:forget(player)
end)
