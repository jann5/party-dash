--!strict
-- Live player profiles: session-locked loading/saving and every mutation (coins, XP, upgrades,
-- cosmetics). Every change is mirrored to Player attributes + leaderstats right away.
--
-- Session lock (inside the stored record): lock = { jobId, time }. A server may load a profile only if
-- there is no lock, the lock is its own, or the lock is older than LOCK_STALE (5 min; a crashed server).
-- Autosave refreshes the timestamp every AUTOSAVE seconds; PlayerRemoving / BindToClose release it.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Announce = require(script.Parent.Parent.Announce)
local Profile = require(script.Parent.Profile)
local Store = require(script.Parent.Store)

export type Session = {
	player: Player,
	key: string,
	data: Profile.Data,
	loaded: boolean,
	persistent: boolean, -- false: temporary profile (load failed); never written back
	lost: boolean, -- another server stole the lock; stop writing
	saving: boolean,
	closing: boolean, -- unloading: only the final (lock-releasing) save may still run
	pendingReceipts: { [string]: boolean }, -- granted but not yet confirmed by a successful save
	passes: { [string]: boolean },
	connections: { RBXScriptConnection },
}

local Sessions = {}

Sessions.LOCK_STALE = 300
Sessions.AUTOSAVE = 60
Sessions.QUICK_SAVE_DELAY = 6 -- debounce for "save soon" after purchases / tutorial

-- Game.JobId is "" in Studio; give each Studio server its own id so locks still work.
local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
Sessions.JOB_ID = JOB_ID

local sessions: { [Player]: Session } = {}
local quickSaveQueued: { [Player]: boolean } = {}
local winsRestored: { [Player]: boolean } = {} -- saved Wins already merged into leaderstats
local changed = Instance.new("BindableEvent") -- (player, field) for other server modules

Sessions.Changed = changed.Event

function Sessions.get(player: Player): Session?
	local s = sessions[player]
	if s and s.loaded then
		return s
	end
	return nil
end

function Sessions.all(): { [Player]: Session }
	return sessions
end

-- Mirroring -----------------------------------------------------------------------------------------

local function stat(player: Player, name: string): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	local v = stats and stats:FindFirstChild(name)
	if v and v:IsA("IntValue") then
		return v
	end
	return nil
end

local function ownedCsv(s: Session): string
	local ids = {}
	for id in s.data.ownedCosmetics do
		table.insert(ids, id)
	end
	if s.passes.VIP then
		for _, item in Cosmetics.all() do
			if item.vip then
				table.insert(ids, item.id)
			end
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

function Sessions.owns(s: Session, item: Cosmetics.Item): boolean
	if item.vip then
		return s.passes.VIP == true
	end
	return s.data.ownedCosmetics[item.id] == true
end

local function mirrorCoins(s: Session)
	s.player:SetAttribute("Coins", s.data.coins)
	local coins = stat(s.player, "Coins")
	if coins then
		coins.Value = s.data.coins
	end
end

local function mirrorLevel(s: Session)
	s.player:SetAttribute("Level", s.data.level)
	s.player:SetAttribute("XP", s.data.xp)
	s.player:SetAttribute(Rules.Attr.XPNext, Rules.xpForLevel(s.data.level))
end

local function mirrorCosmetics(s: Session)
	for _, slot in Cosmetics.SLOTS do
		local id = s.data.equipped[slot] or ""
		local item = Cosmetics.get(id)
		if item and not Sessions.owns(s, item) then
			id = "" -- e.g. VIP trail while the pass check failed: show the default but keep it saved
		end
		s.player:SetAttribute(Cosmetics.SLOT_INFO[slot].attr, id)
	end
	s.player:SetAttribute(Rules.Attr.Owned, ownedCsv(s))
end

function Sessions.mirrorAll(s: Session)
	mirrorCoins(s)
	mirrorLevel(s)
	for name in Config.UPGRADES do
		s.player:SetAttribute("Upg_" .. name, s.data.upgrades[name] or 0)
	end
	mirrorCosmetics(s)
	for name in Config.GAMEPASSES do
		s.player:SetAttribute(Rules.Attr.PassPrefix .. name, s.passes[name] == true)
	end
	if s.data.seenTutorial then
		s.player:SetAttribute("Seen_Tutorial", true)
	end
end

Sessions.mirrorCosmetics = mirrorCosmetics

-- Store I/O -----------------------------------------------------------------------------------------

type LoadOutcome = "ok" | "locked" | "error"

local function tryAcquire(key: string): (LoadOutcome, Profile.Data?, any?)
	local outcome: LoadOutcome = "error"
	local loaded: Profile.Data? = nil
	local holder: any = nil
	local ok = Store.update(key, function(old)
		local lock = type(old) == "table" and old.lock or nil
		local now = os.time()
		if
			type(lock) == "table"
			and lock.jobId ~= JOB_ID
			and type(lock.time) == "number"
			and now - lock.time < Sessions.LOCK_STALE
		then
			outcome, holder = "locked", lock
			return nil -- cancel: someone else owns this profile right now
		end
		local data = Profile.reconcile(old)
		local record = Profile.serialize(data)
		record.lock = { jobId = JOB_ID, time = now }
		outcome, loaded = "ok", data
		return record
	end)
	if not ok then
		return "error", nil, nil
	end
	return outcome, loaded, holder
end

-- Writes the session to the store. release = true drops the lock (player leaving / shutdown).
local function write(s: Session, release: boolean): boolean
	if not s.persistent or s.lost then
		return false
	end
	local stolen = false
	local snapshot = Profile.serialize(s.data)
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
		table.clear(s.pendingReceipts)
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
	return ok and result == true
end

-- Debounced save after an important change (purchase, tutorial done).
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

-- Mutations -----------------------------------------------------------------------------------------

local function notify(s: Session, field: string)
	changed:Fire(s.player, field)
end

function Sessions.addCoins(player: Player, amount: number, _reason: string?): number?
	local s = Sessions.get(player)
	if not s then
		return nil
	end
	amount = math.floor(tonumber(amount) or 0)
	s.data.coins = math.max(0, s.data.coins + amount)
	if amount > 0 then
		s.data.stats.coinsEarned += amount
	end
	mirrorCoins(s)
	notify(s, "coins")
	return s.data.coins
end

-- Adds XP and handles level-ups. Returns the number of levels gained.
function Sessions.addXP(player: Player, amount: number): number
	local s = Sessions.get(player)
	if not s then
		return 0
	end
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	local d = s.data
	d.xp += amount
	local gained = 0
	while d.xp >= Rules.xpForLevel(d.level) do
		d.xp -= Rules.xpForLevel(d.level)
		d.level += 1
		gained += 1
	end
	mirrorLevel(s)
	if gained > 0 then
		Announce.toast(player, ("LEVEL UP! You're now Lv %d"):format(d.level), Theme.Colors.Purple)
		notify(s, "level")
	end
	return gained
end

function Sessions.setUpgrade(player: Player, name: string, level: number)
	local s = Sessions.get(player)
	if not s or not Config.UPGRADES[name] then
		return
	end
	s.data.upgrades[name] = math.clamp(math.floor(level), 0, Config.UPGRADE_MAX_LEVEL)
	player:SetAttribute("Upg_" .. name, s.data.upgrades[name])
	notify(s, "upgrades")
end

function Sessions.grantCosmetic(player: Player, id: string)
	local s = Sessions.get(player)
	local item = Cosmetics.get(id)
	if not s or not item or item.vip then
		return
	end
	s.data.ownedCosmetics[item.id] = true
	mirrorCosmetics(s)
end

function Sessions.equip(player: Player, slot: string, id: string)
	local s = Sessions.get(player)
	if not s or not Cosmetics.isSlot(slot) then
		return
	end
	s.data.equipped[slot] = id
	mirrorCosmetics(s)
	notify(s, "equipped")
end

function Sessions.setPass(player: Player, name: string, owned: boolean)
	local s = sessions[player]
	if not s then
		return
	end
	s.passes[name] = owned
	player:SetAttribute(Rules.Attr.PassPrefix .. name, owned)
	if s.loaded then
		mirrorCosmetics(s)
	end
	notify(s, "passes")
end

function Sessions.hasPass(player: Player, name: string): boolean
	local s = sessions[player]
	return s ~= nil and s.passes[name] == true
end

-- Daily reward: once per UTC day (checked on join and by the autosave loop for long sessions).
-- `delay` lets the client HUD finish loading so the coins visibly fly in with the toast.
local dailyQueued: { [Player]: boolean } = {}
function Sessions.checkDaily(player: Player, delay: number?)
	local s = Sessions.get(player)
	if not s or dailyQueued[player] or s.data.lastDaily == Rules.utcDay() then
		return
	end
	dailyQueued[player] = true
	task.delay(delay or 0, function()
		dailyQueued[player] = nil
		local live = Sessions.get(player)
		local today = Rules.utcDay()
		if not live or player.Parent ~= Players or live.data.lastDaily == today then
			return
		end
		live.data.lastDaily = today
		Sessions.addCoins(player, Config.DAILY_REWARD, "daily")
		Announce.toast(player, ("DAILY REWARD! +%d coins"):format(Config.DAILY_REWARD), Theme.Colors.Green)
		Sessions.saveSoon(player)
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
	-- Wins: Core increments leaderstats.Wins; mirror it into the profile.
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats", 30)
		local wins = stats and stats:WaitForChild("Wins", 30)
		if not (wins and wins:IsA("IntValue")) or sessions[player] ~= s then
			return
		end
		table.insert(
			s.connections,
			wins.Changed:Connect(function(value)
				s.data.wins = math.max(0, math.floor(value))
			end)
		)
	end)
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
	if wins and wins:IsA("IntValue") and sessions[player] == s then
		if winsRestored[player] then
			-- re-applied profile (reload): leaderstats already holds the live total
			s.data.wins = math.max(s.data.wins, wins.Value)
		else
			-- wins earned before the profile finished loading are kept on top of the saved total
			winsRestored[player] = true
			s.data.wins += wins.Value
		end
		wins.Value = s.data.wins
	end
end

local loadedEvent = Instance.new("BindableEvent") -- (player) after a profile is applied
Sessions.Loaded = loadedEvent.Event

local function apply(s: Session)
	s.loaded = true
	if s.player:GetAttribute("Seen_Tutorial") == true then
		s.data.seenTutorial = true -- finished the tutorial before the profile arrived
	end
	Sessions.mirrorAll(s)
	watchPlayer(s)
	task.spawn(setupLeaderstats, s)
	s.player:SetAttribute(Rules.Attr.Loaded, true)
	loadedEvent:Fire(s.player)
end

-- Loads (or re-loads) a player's profile. Yields until it is applied or the player leaves.
function Sessions.load(player: Player)
	if sessions[player] then
		return
	end
	local s: Session = {
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
	}
	sessions[player] = s

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
				if player.Parent then
					Announce.toast(player, "Couldn't load your save. Progress won't be kept!", Theme.Colors.Red)
				end
			end)
			return
		elseif outcome == "locked" and not toldLocked then
			toldLocked = true
			Announce.toast(player, "Loading your save from another server...", Theme.Colors.Blue)
		end
		task.wait(delays[math.min(attempt, #delays)])
	end
	if sessions[player] == s then
		sessions[player] = nil
	end
end

-- Saves + releases the lock, then forgets the session (player leaving).
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
	if s.loaded then
		Sessions.save(player, true)
	end
	for _, c in s.connections do
		c:Disconnect()
	end
	if sessions[player] == s then
		sessions[player] = nil
	end
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
			Sessions.mirrorAll(fresh)
			return fresh.data
		end
	end
	return nil
end

function Sessions.peekStored(userId: number): any
	return Store.peek(Store.key(userId))
end

return Sessions
