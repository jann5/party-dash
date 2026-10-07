--!strict
-- Shared type definitions for the Economy server modules (no runtime code).
local Profile = require(script.Parent.Profile)

export type Data = Profile.Data

export type Session = {
	player: Player,
	key: string,
	data: Data,
	loaded: boolean,
	persistent: boolean, -- false: temporary profile (load failed); never written back
	lost: boolean, -- another server stole the lock; stop writing
	saving: boolean,
	closing: boolean, -- unloading: only the final (lock-releasing) save may still run
	pendingReceipts: { [string]: boolean }, -- granted but not yet confirmed by a successful save
	passes: { [string]: boolean },
	connections: { RBXScriptConnection },
	-- session-only state
	joinedAt: number, -- server time the profile was applied (playtime gifts count from here)
	giftIndex: number,
	giftAt: number,
	groupMember: boolean?,
	board: { wins: number, level: number }, -- last values written to the lobby leaderboards
}

export type Granted = {
	coins: number,
	xp: number,
	spins: number,
	revives: number,
	boostSeconds: number,
	items: { string }, -- newly owned cosmetic ids
	converted: { string }, -- ids already owned, paid out as coins instead
	levels: number, -- levels gained from the bundle's XP
}

return {}
