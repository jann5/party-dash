-- Music director (brief #23): picks the track for the local player's context and lets Shared.Audio cross-fade.
--   round member (InRound / Spectating / Eliminated) during Intro, Countdown or Round -> MusicRound
--   everything else (lobby, roulette, results, waiting)                              -> calm lobby playlist
-- The lobby playlist alternates MusicLobby1 / MusicLobby2: the next track starts just before the current one ends,
-- and every return to the lobby moves on to the next track. Starts once the loading screen reports ClientReady.
-- Muting is not handled here: Shared.Audio zeroes the Music SoundGroup while Set_Music == false.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Music = {}

local FADE = 1.5
local TAIL = 1.75 -- start the next lobby track this many seconds before the current one ends
local READY_TIMEOUT = 15 -- start anyway if ClientReady never arrives
local LOBBY_TRACKS = { "MusicLobby1", "MusicLobby2" }
local ROUND_TRACK = "MusicRound"
local ROUND_PHASES = { Intro = true, Countdown = true, Round = true }
local MEMBER_ATTRS = { "InRound", "Spectating", "Eliminated" }

function Music.start(Audio)
	local player = Players.LocalPlayer
	local started = false
	local mode: string? = nil -- "lobby" | "round"
	local lobbyIndex = 0
	local lobbySound: Sound? = nil
	local loopConn: RBXScriptConnection? = nil

	local function wantsRound(): boolean
		local state = ReplicatedStorage:FindFirstChild("GameState")
		local phase = state and state:GetAttribute("Phase")
		if not (phase and ROUND_PHASES[phase]) then
			return false
		end
		for _, attr in MEMBER_ATTRS do
			if player:GetAttribute(attr) == true then
				return true
			end
		end
		return false
	end

	-- Plays `key` through Audio and returns the Sound it created (nil when Audio kept the current track).
	local function play(key: string): Sound?
		local before = {}
		for _, child in SoundService:GetChildren() do
			before[child] = true
		end
		Audio.setMusic(key, FADE)
		for _, child in SoundService:GetChildren() do
			if not before[child] and child:IsA("Sound") and child.Name == key then
				return child
			end
		end
		return nil
	end

	local function stopWatchingLobby()
		if loopConn then
			loopConn:Disconnect()
			loopConn = nil
		end
		lobbySound = nil
	end

	local function nextLobbyTrack()
		stopWatchingLobby()
		lobbyIndex = lobbyIndex % #LOBBY_TRACKS + 1
		local sound = play(LOBBY_TRACKS[lobbyIndex])
		if not sound then
			return
		end
		lobbySound = sound
		-- backup for the tail watcher below: the track looped before we caught its last seconds
		loopConn = sound.DidLoop:Connect(function()
			if mode == "lobby" and lobbySound == sound then
				nextLobbyTrack()
			end
		end)
	end

	local function evaluate()
		local want = wantsRound() and "round" or "lobby"
		if want == mode then
			return
		end
		mode = want
		if want == "round" then
			stopWatchingLobby()
			play(ROUND_TRACK)
		else
			nextLobbyTrack()
		end
	end

	-- attribute bursts (phase + InRound in one frame) resolve into one decision
	local queued = false
	local function schedule()
		if not started or queued then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			evaluate()
		end)
	end

	for _, attr in MEMBER_ATTRS do
		player:GetAttributeChangedSignal(attr):Connect(schedule)
	end
	task.spawn(function()
		local state = nil
		repeat
			state = ReplicatedStorage:WaitForChild("GameState", 10)
		until state
		state:GetAttributeChangedSignal("Phase"):Connect(schedule)
		schedule()
	end)

	-- cross-fade into the next lobby track just before the current one ends
	task.spawn(function()
		while true do
			task.wait(0.5)
			local sound = lobbySound
			if
				mode == "lobby"
				and sound
				and sound.Parent
				and sound.IsPlaying
				and sound.TimeLength > TAIL * 4
				and sound.TimePosition >= sound.TimeLength - TAIL
			then
				nextLobbyTrack()
			end
		end
	end)

	task.spawn(function()
		local deadline = os.clock() + READY_TIMEOUT
		while player:GetAttribute("ClientReady") ~= true and os.clock() < deadline do
			task.wait(0.2)
		end
		started = true
		evaluate()
	end)
end

return Music
