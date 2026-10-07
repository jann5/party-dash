--!strict
-- Live player profiles: session-locked loading, saving and releasing. Mutations live in Grants; attribute
-- mirroring in Mirror.
--
-- Session lock (inside the stored record): lock = { jobId, time }. A server may load a profile only if there is
-- no lock, the lock is its own, or the lock is older than LOCK_STALE (5 min; a crashed server). Autosave refreshes
-- the timestamp every AUTOSAVE seconds; PlayerRemoving / BindToClose release it.
local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Boards = require(script.Parent.Boards)
local Feedback = require(script.Parent.Feedback)
local Mirror = require(script.Parent.Mirror)
local Profile = require(script.Parent.Profile)
local Store = require(script.Parent.Store)
local Types = require(script.Parent.Types)

type Session = Types.Session

local Sessions = {}

Sessions.LOCK_STALE = 300
Sessions.AUTOSAVE = 60
Sessions.QUICK_SAVE_DELAY = 6 -- debounce for "save soon" (DataStore allows ~1 write per key every 6 s)

-- Game.JobId is "" in Studio; give each Studio server its own id so locks still work.
local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
Sessions.JOB_ID = JOB_ID

local sessions: { [Player]: Session } = {}
local unloading: { [number]: boolean } = {} -- userId -> final save in flight (same-server rejoin waits)
local quickSaveQueued: { [Player]: boolean } = {}
local winsRestored: { [Player]: boolean } = {} -- saved Wins already merged into leaderstats

local function now(): number
	return workspace:GetServerTimeNow()
end

function Sessions.get(player: Player): Session?
	local s = sessions[player]
	if s and s.loaded then
		return s
	end
	return nil
end

-- Snapshot of the players with a session (safe to iterate while yielding).
function Sessions.players(): { Player }
	local list = {}
	for player in sessions do
		table.insert(list, player)
	end
	return list
end

function Sessions.hasPass(player: Player, name: string): boolean
	local s = sessions[player]
	return s ~= nil and s.passes[name] == true
end

-- Raw session (also while loading), for pass checks that may finish before the profile.
function Sessions.raw(player: Player): Session?
	return sessions[player]
end

-- Day rollover --------------------------------------------------------------------------------------

-- Applies UTC-day rules: a missed day resets the calendar, VIP owners get today's bonus spin, and the
-- Ready flags are re-mirrored. Called on load, when a pass is granted and when the UTC day changes.
function Sessions.refreshDay(s: Session)
	local d = s.data
	local today = Rules.utcDay()
	if d.lastDaily > 0 and d.lastDaily < today - 1 then
		d.calendarDay = 1
		d.loginStreak = 0
	end
	if s.passes.VIP and d.vipSpinDay ~= today then
		d.vipSpinDay = today
		d.spins += Rules.VIP_DAILY_SPINS
		Feedback.toast(s.player, "VIP bonus: +1 spin!", Theme.Colors.Gold)
	end
	Mirror.spins(s)
	Mirror.daily(s)
	Mirror.group(s)
end

-- Store I/O -----------------------------------------------------------------------------------------

type LoadOutcome = "ok" | "locked" | "error"

local function tryAcquire(key: string): (LoadOutcome, Profile.Data?)
	local outcome: LoadOutcome = "error"
	local loaded: Profile.Data? = nil
	local ok = Store.update(key, function(old)
		local lock = type(old) == "table" and old.lock or nil
		local t = os.time()
		if
			type(lock) == "table"
			and lock.jobId ~= JOB_ID
			and type(lock.time) == "number"
			and t - lock.time < Sessions.LOCK_STALE
		then
			outcome = "locked"
			return nil -- cancel: someone else owns this profile right now
		end
		local data = Profile.reconcile(old)
		local record = Profile.serialize(data)
		record.lock = { jobId = JOB_ID, time = t }
		outcome, loaded = "ok", data
		return record
	end)
	if not ok then
		return "error", nil
	end
	return outcome, loaded
end

-- Writes the session to the store. release = true drops the lock (player leaving / shutdown).
local function write(s: Session, release: boolean): boolean
	if not s.persistent or s.lost then
		return false
	end
	local stolen = false
	local snapshot = Profile.serialize(s.data)
	-- only receipts already in this snapshot are confirmed by this write
	local confirming = table.clone(s.pendingReceipts)
	local ok = Store.update(s.key, function(old)
		local lock = type(old) == "table" and old.lock or nil
		if type(lock) == "table" and lock.jobId ~= JOB_ID then
			stolen = true
			return nil
		end
		local record = table.clone(snapshot)
		if not release then
			record.lock = { jobId = JOB_ID, time = os.time() }
		end
		return record
	end)
	if stolen then
		s.lost = true
		warn(
			("[Economy] %s's profile is now owned by another server; this server stops saving it."):format(
				s.player.Name
			)
		)
		return false
	end
	if ok then
		for id in confirming do
			s.pendingReceipts[id] = nil
		end
		task.spawn(Boards.submit, s)
	end
	return ok
end

-- Saves now (yields). Concurrent calls for the same player wait for the running save.
function Sessions.save(player: Player, release: boolean?): boolean
	local s = sessions[player]
	if not s or not s.loaded then
		return false
	end
	while s.saving do
		task.wait(0.1)
	end
	if s.closing and not release then
		return false -- never re-lock a profile that is being released
	end
	s.saving = true
	local ok, result = pcall(write, s, release == true)
	s.saving = false
	if not ok then
		warn("[Economy] save failed:", result)
	end
	return ok and result == true
end

-- Debounced save after an important change (claim, purchase with coins, settings).
function Sessions.saveSoon(player: Player)
	if quickSaveQueued[player] then
		return
	end
	quickSaveQueued[player] = true
	task.delay(Sessions.QUICK_SAVE_DELAY, function()
		quickSaveQueued[player] = nil
		if sessions[player] then
			Sessions.save(player)
		end
	end)
end

-- Loading -------------------------------------------------------------------------------------------

local function watchPlayer(s: Session)
	local player = s.player
	-- Seen_Tutorial: the UI piece flips it via its own remote; persist it as soon as it becomes true.
	table.insert(
		s.connections,
		player:GetAttributeChangedSignal("Seen_Tutorial"):Connect(function()
			if player:GetAttribute("Seen_Tutorial") == true and not s.data.seenTutorial then
				s.data.seenTutorial = true
				Sessions.saveSoon(player)
			end
		end)
	)
end

-- Leaderstats: Core creates the folder with Wins/Streak; add Coins and restore saved Wins.
local function setupLeaderstats(s: Session)
	local player = s.player
	local stats = player:WaitForChild("leaderstats", 30)
	if not stats or sessions[player] ~= s then
		return
	end
	local coins = stats:FindFirstChild("Coins")
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = stats
	end
	(coins :: IntValue).Value = s.data.coins
	local wins = stats:WaitForChild("Wins", 30)
	if not (wins and wins:IsA("IntValue")) or sessions[player] ~= s then
		return
	end
	if winsRestored[player] then
		-- re-applied profile (reload): leaderstats already holds the live total
		s.data.wins = math.max(s.data.wins, wins.Value)
	else
		-- wins earned before the profile finished loading are kept on top of the saved total
		winsRestored[player] = true
		s.data.wins += wins.Value
	end
	wins.Value = s.data.wins
	-- Core increments leaderstats.Wins; keep the profile in sync.
	table.insert(
		s.connections,
		wins.Changed:Connect(function(value)
			s.data.wins = math.max(0, math.floor(value))
		end)
	)
end

local function checkGroup(s: Session)
	if Config.GROUP_ID == 0 then
		return
	end
	local ok, member = pcall(s.player.IsInGroup, s.player, Config.GROUP_ID)
	if ok and sessions[s.player] == s then
		s.groupMember = member == true
		Mirror.group(s)
	end
end

local function apply(s: Session)
	s.loaded = true
	if s.player:GetAttribute("Seen_Tutorial") == true then
		s.data.seenTutorial = true -- finished the tutorial before the profile arrived
	end
	s.joinedAt = now()
	s.giftIndex = 1
	s.giftAt = s.joinedAt + Rules.giftOffset(1)
	Sessions.refreshDay(s)
	Mirror.all(s)
	watchPlayer(s)
	task.spawn(setupLeaderstats, s)
	task.spawn(checkGroup, s)
	s.player:SetAttribute(Rules.Attr.Loaded, true)
end

local function newSession(player: Player): Session
	return {
		player = player,
		key = Store.key(player.UserId),
		data = Profile.default(),
		loaded = false,
		persistent = true,
		lost = false,
		saving = false,
		closing = false,
		pendingReceipts = {},
		passes = {},
		connections = {},
		joinedAt = 0,
		giftIndex = 1,
		giftAt = 0,
		groupMember = nil,
		board = { wins = -1, level = -1 },
	}
end

-- Loads (or re-loads) a player's profile. Yields until it is applied or the player leaves.
function Sessions.load(player: Player)
	if sessions[player] then
		return
	end
	local s = newSession(player)
	sessions[player] = s

	-- same-server rejoin: let the previous session's final save land first
	while unloading[player.UserId] and player.Parent == Players do
		task.wait(0.1)
	end
	Store.waitReady()
	local delays = { 2, 4, 8, 15 }
	local attempt = 0
	local toldLocked = false
	while player.Parent == Players and sessions[player] == s do
		attempt += 1
		local outcome, data = tryAcquire(s.key)
		if outcome == "ok" and data then
			s.data = data
			if player.Parent ~= Players or sessions[player] ~= s then
				-- left while loading: give the lock straight back
				s.loaded = true
				write(s, true)
				return
			end
			apply(s)
			return
		elseif outcome == "error" and attempt >= 3 then
			-- the store is down: play on a temporary profile instead of risking an overwrite later
			warn(("[Economy] Could not load %s's profile; using a temporary one this session."):format(player.Name))
			s.persistent = false
			s.data = Profile.default()
			apply(s)
			task.delay(4, function()
				Feedback.toast(player, "Couldn't load your save. Progress won't be kept!", Theme.Colors.Red)
			end)
			return
		elseif outcome == "locked" and not toldLocked then
			toldLocked = true
			Feedback.toast(player, "Loading your save from another server...", Theme.Colors.Blue)
		end
		task.wait(delays[math.min(attempt, #delays)])
	end
	if sessions[player] == s then
		sessions[player] = nil
	end
end

-- Saves + releases the lock, then forgets the session (player leaving / shutdown).
function Sessions.unload(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	if s.closing then
		-- already unloading (PlayerRemoving + BindToClose): wait for that save to finish
		while sessions[player] == s do
			task.wait(0.1)
		end
		return
	end
	s.closing = true
	unloading[player.UserId] = true
	if s.loaded then
		Sessions.save(player, true)
	end
	for _, c in s.connections do
		c:Disconnect()
	end
	if sessions[player] == s then
		sessions[player] = nil
	end
	unloading[player.UserId] = nil
	quickSaveQueued[player] = nil
	winsRestored[player] = nil
end

-- Test/debug: save + release, then load the profile again from the store and re-apply it.
function Sessions.reload(player: Player): Profile.Data?
	local s = sessions[player]
	if not s then
		return nil
	end
	if s.loaded and s.persistent then
		Sessions.save(player, true)
	end
	local passes = s.passes
	for _, c in s.connections do
		c:Disconnect()
	end
	sessions[player] = nil
	Sessions.load(player)
	local fresh = sessions[player]
	if fresh then
		fresh.passes = passes
		if fresh.loaded then
			Sessions.refreshDay(fresh)
			Mirror.all(fresh)
			return fresh.data
		end
	end
	return nil
end

function Sessions.peekStored(userId: number): any
	return Store.peek(Store.key(userId))
end

-- Fresh group membership check for a claim (Player:IsInGroup is cached per server; GetGroupsAsync is not).
-- Yields. Returns the best known answer.
function Sessions.checkGroupFresh(s: Session): boolean
	if Config.GROUP_ID == 0 then
		return false
	end
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, s.player.UserId)
	if ok and type(groups) == "table" then
		local member = false
		for _, g in groups do
			if type(g) == "table" and g.Id == Config.GROUP_ID then
				member = true
				break
			end
		end
		s.groupMember = member
	elseif s.groupMember ~= true then
		local ok2, member = pcall(s.player.IsInGroup, s.player, Config.GROUP_ID)
		if ok2 then
			s.groupMember = member == true
		end
	end
	return s.groupMember == true
end

return Sessions
