-- Party Dash: one place to play every sound. FROZEN CONTRACT (lead-owned; pieces call it, never edit it).
--
-- Sound ids + default volumes live in Shared.Assets.Sounds (generated). Every sound goes through one of three
-- SoundGroups in SoundService ("Music", "SFX", "UI"), so the Settings panel can mute music / effects per player:
-- the client sets those groups' Volume locally from the Player attributes Set_Music / Set_SFX (false = muted).
--
-- Client:
--   Audio.ui("UiClick")                       -- 2D interface sound (UI group)
--   Audio.play("Dash", { volume = 0.6 })      -- 2D gameplay sound for this player only (SFX group)
--   Audio.at("Explosion", partOrPosition)     -- 3D sound heard only by this client
--   Audio.setMusic("MusicLobby1")             -- cross-fades the single music track; nil stops music
-- Server:
--   Audio.at("Explosion", partOrPosition)     -- 3D sound replicated to everyone (SFX group, each client's mute applies)
--   Audio.forPlayer(player, "LevelUp")        -- tells one client to play a 2D sound (remote Audio_Play)
-- Unknown keys are ignored (warns once), so a missing id never breaks gameplay.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Net = require(ReplicatedStorage.Shared.Net)

local IS_SERVER = RunService:IsServer()
local Audio = {}

local GROUP_VOLUME = { Music = 0.5, SFX = 0.8, UI = 0.7 }
local warned = {}

local function group(name: string): SoundGroup
	local g = SoundService:FindFirstChild(name)
	if g and g:IsA("SoundGroup") then
		return g
	end
	if IS_SERVER then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = GROUP_VOLUME[name]
		g.Parent = SoundService
		return g
	end
	-- client: the server creates them at boot; fall back to a local one if it has not replicated yet
	g = SoundService:WaitForChild(name, 5)
	if g then
		return g
	end
	g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = GROUP_VOLUME[name]
	g.Parent = SoundService
	return g
end

local function info(key: string)
	local s = Assets.Sounds[key]
	if not s then
		if not warned[key] then
			warned[key] = true
			warn("[Audio] unknown sound key " .. tostring(key))
		end
		return nil
	end
	return s
end

local function make(key: string, groupName: string, opts): Sound?
	local s = info(key)
	if not s then
		return nil
	end
	local snd = Instance.new("Sound")
	snd.Name = key
	snd.SoundId = s.id
	snd.Volume = (opts and opts.volume) or s.volume or 0.6
	snd.PlaybackSpeed = (opts and opts.pitch) or 1
	snd.SoundGroup = group(groupName)
	return snd
end

local function playOnce(snd: Sound, parent: Instance)
	snd.Parent = parent
	snd:Play()
	Debris:AddItem(snd, math.max(snd.TimeLength, 0) + 6)
	snd.Ended:Once(function()
		snd:Destroy()
	end)
end

-- 3D sound at a BasePart/Attachment or a world position (server: everyone hears it; client: only this client).
function Audio.at(
	key: string,
	where: Instance | Vector3,
	opts: { volume: number?, pitch: number?, maxDistance: number? }?
)
	local snd = make(key, "SFX", opts)
	if not snd then
		return
	end
	snd.RollOffMaxDistance = (opts and opts.maxDistance) or 160
	snd.RollOffMinDistance = 12
	if typeof(where) == "Vector3" then
		local a = Instance.new("Attachment")
		a.WorldPosition = where
		a.Parent = workspace.Terrain
		Debris:AddItem(a, 8)
		playOnce(snd, a)
	else
		playOnce(snd, where)
	end
end

if IS_SERVER then
	for name in GROUP_VOLUME do
		group(name)
	end
	local remote = Net.event("Audio_Play")

	-- Plays a 2D sound on one player's client (e.g. LevelUp, Purchase).
	function Audio.forPlayer(player: Player, key: string, opts: { volume: number?, pitch: number? }?)
		remote:FireClient(player, key, opts)
	end

	return Audio
end

-- ===== client =====
local player = Players.LocalPlayer

local function applySettings()
	local musicOn = player:GetAttribute("Set_Music") ~= false
	local sfxOn = player:GetAttribute("Set_SFX") ~= false
	group("Music").Volume = musicOn and GROUP_VOLUME.Music or 0
	group("SFX").Volume = sfxOn and GROUP_VOLUME.SFX or 0
	group("UI").Volume = sfxOn and GROUP_VOLUME.UI or 0
end
task.spawn(applySettings)
player:GetAttributeChangedSignal("Set_Music"):Connect(applySettings)
player:GetAttributeChangedSignal("Set_SFX"):Connect(applySettings)

-- 2D interface sound (button clicks, panel open).
function Audio.ui(key: string, opts: { volume: number?, pitch: number? }?)
	local snd = make(key, "UI", opts)
	if snd then
		playOnce(snd, SoundService)
	end
end

-- 2D gameplay sound for this client only.
function Audio.play(key: string, opts: { volume: number?, pitch: number? }?)
	local snd = make(key, "SFX", opts)
	if snd then
		playOnce(snd, SoundService)
	end
end

local current: Sound? = nil
local currentKey: string? = nil

-- Cross-fades to a looping music track (nil = fade out). Calling it with the playing key does nothing.
function Audio.setMusic(key: string?, fade: number?)
	if key == currentKey then
		return
	end
	currentKey = key
	local t = TweenInfo.new(fade or 1.5)
	if current then
		local old = current
		TweenService:Create(old, t, { Volume = 0 }):Play()
		task.delay(fade or 1.5, function()
			old:Destroy()
		end)
		current = nil
	end
	if not key then
		return
	end
	local snd = make(key, "Music", nil)
	if not snd then
		return
	end
	local target = snd.Volume
	snd.Looped = true
	snd.Volume = 0
	snd.Parent = SoundService
	snd:Play()
	TweenService:Create(snd, t, { Volume = target }):Play()
	current = snd
end

function Audio.currentMusic(): string?
	return currentKey
end

-- Connect lazily without erroring or warning: the remote only exists once some server script requires Audio.
local function hook(remote: Instance)
	if remote.Name == "Audio_Play" and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(function(key, opts)
			if typeof(key) == "string" then
				Audio.play(key, typeof(opts) == "table" and opts or nil)
			end
		end)
	end
end
local function watchFolder(folder: Instance)
	local existing = folder:FindFirstChild("Audio_Play")
	if existing then
		hook(existing)
	else
		local conn
		conn = folder.ChildAdded:Connect(function(c)
			if c.Name == "Audio_Play" then
				conn:Disconnect()
				hook(c)
			end
		end)
	end
end
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if remotesFolder then
	watchFolder(remotesFolder)
else
	local conn
	conn = ReplicatedStorage.ChildAdded:Connect(function(c)
		if c.Name == "Remotes" then
			conn:Disconnect()
			watchFolder(c)
		end
	end)
end

return Audio
