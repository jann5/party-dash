-- Party Dash movement (server side).
-- The client owns its character's physics and performs the dash/slide motion itself. The server is the
-- authority for the replicated state that minigames trust:
--   character "Dashing"   true for Config.DASH_DURATION after every ACCEPTED dash
--   character "DashCount" incremented on every accepted dash (rejected / spammed dashes are not counted)
--   character "Sliding"   true for Config.SLIDE_DURATION (or until the client ends the slide early)
-- It also sets the base WalkSpeed / JumpPower (+ Jump Boost upgrade) and relays the jump flip FX.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Stats = require(Shared.Movement.Stats)

local dashRemote = Net.event(Stats.Remote.Dash)
local slideRemote = Net.event(Stats.Remote.Slide)
local jumpFxRemote = Net.event(Stats.Remote.JumpFx)

local JUMP_TRICK_COUNT = 4 -- must match the TRICKS table in the client JumpFx module
local FX_MIN_INTERVAL = 0.15
local ROBLOX_DEFAULT_WALK = 16
local ROBLOX_DEFAULT_JUMP = 50

type PlayerState = {
	lastDash: number,
	dashToken: number,
	slideToken: number,
	sliding: boolean,
	slideEndedAt: number,
	lastFx: { [string]: number },
}

local states: { [Player]: PlayerState } = {}

local function stateOf(player: Player): PlayerState
	local s = states[player]
	if not s then
		s = {
			lastDash = -math.huge,
			dashToken = 0,
			slideToken = 0,
			sliding = false,
			slideEndedAt = -math.huge,
			lastFx = {},
		}
		states[player] = s
	end
	return s
end

-- Spawn defaults through StarterPlayer so every character is born with them (no race with Core,
-- which may freeze a freshly spawned character).
StarterPlayer.CharacterWalkSpeed = Config.WALK_SPEED
StarterPlayer.CharacterUseJumpPower = true
StarterPlayer.CharacterJumpPower = Config.JUMP_POWER

-- Returns the live character pieces if the character may act right now.
local function actingCharacter(player: Player): (Model?, Humanoid?)
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
	return character, humanoid
end

local function applyJumpPower(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.UseJumpPower = true
	-- JumpPower 0 means someone (Core) froze the character on purpose: leave it alone.
	if humanoid.JumpPower > 0 then
		humanoid.JumpPower = Stats.jumpPower(player)
	end
end

local function endSlide(player: Player, character: Model?)
	local s = stateOf(player)
	if s.sliding then
		s.sliding = false
		s.slideEndedAt = os.clock()
	end
	s.slideToken += 1
	if character and character.Parent then
		character:SetAttribute("Sliding", false)
	end
end

local function onCharacter(player: Player, character: Model)
	local s = stateOf(player)
	s.dashToken += 1
	s.slideToken += 1
	s.sliding = false
	character:SetAttribute("DashCount", 0)
	character:SetAttribute("Dashing", false)
	character:SetAttribute("Sliding", false)

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		-- Only replace untouched spawn defaults (ours or Roblox's); a frozen (0) value belongs to Core.
		if humanoid.WalkSpeed == ROBLOX_DEFAULT_WALK then
			humanoid.WalkSpeed = Config.WALK_SPEED
		end
		local jump = humanoid.JumpPower
		if math.abs(jump - Config.JUMP_POWER) < 0.01 or math.abs(jump - ROBLOX_DEFAULT_JUMP) < 0.01 then
			humanoid.UseJumpPower = true
			humanoid.JumpPower = Stats.jumpPower(player)
		end
	end

	-- A knockback stun cancels any dash/slide immediately.
	character:GetAttributeChangedSignal("Stunned"):Connect(function()
		if character:GetAttribute("Stunned") == true then
			s.dashToken += 1
			character:SetAttribute("Dashing", false)
			endSlide(player, character)
		end
	end)
end

local function onPlayer(player: Player)
	stateOf(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	player:GetAttributeChangedSignal("Upg_JumpBoost"):Connect(function()
		applyJumpPower(player)
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

-- DASH: the client already moved; validate the cooldown and publish the authoritative state.
dashRemote.OnServerEvent:Connect(function(player: Player)
	local s = stateOf(player)
	local character = actingCharacter(player)
	local now = os.clock()
	local cooldown = Stats.dashCooldown(player)
	local elapsed = now - s.lastDash
	if not character or elapsed < cooldown - Stats.DASH_TOLERANCE then
		-- Tell the client how long it really has to wait so its cooldown bar stays honest.
		local remaining = if character then math.max(0, cooldown - elapsed) else 0
		dashRemote:FireClient(player, "Reject", remaining)
		return
	end
	s.lastDash = now
	s.dashToken += 1
	local token = s.dashToken
	character:SetAttribute("DashCount", (tonumber(character:GetAttribute("DashCount")) or 0) + 1)
	character:SetAttribute("Dashing", true)
	-- A dash cancels a slide (the client does the same).
	if s.sliding then
		endSlide(player, character)
	end
	task.delay(Config.DASH_DURATION, function()
		if s.dashToken == token and character.Parent then
			character:SetAttribute("Dashing", false)
		end
	end)
end)

-- SLIDE: true = start, false = the client ended it early (jumped out / dashed). Ending early can only
-- shorten the trusted Sliding window, never extend it.
slideRemote.OnServerEvent:Connect(function(player: Player, active: any)
	if type(active) ~= "boolean" then
		return
	end
	local s = stateOf(player)
	if not active then
		if s.sliding then
			endSlide(player, player.Character)
		end
		return
	end
	local character = actingCharacter(player)
	local now = os.clock()
	if not character or s.sliding or now - s.slideEndedAt < Stats.slideCooldown() - Stats.SLIDE_TOLERANCE then
		return
	end
	s.sliding = true
	s.slideToken += 1
	local token = s.slideToken
	character:SetAttribute("Sliding", true)
	task.delay(Config.SLIDE_DURATION, function()
		if s.slideToken == token then
			endSlide(player, character)
		end
	end)
end)

-- JUMP FX relay (purely visual): ("Jump", trickIndex) or ("Land"), forwarded to everyone else.
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
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local s = stateOf(player)
	local now = os.clock()
	local last = s.lastFx[kind]
	if last and now - last < FX_MIN_INTERVAL then
		return
	end
	s.lastFx[kind] = now
	for _, other in Players:GetPlayers() do
		if other ~= player then
			jumpFxRemote:FireClient(other, kind, character, trick)
		end
	end
end)
