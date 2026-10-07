--!nonstrict
-- Core_Announce router (wire format: kind, text, sub?, colorHex?):
--   big   -> Hype (huge transient word)      feed -> Feed lane      toast -> UIKit.toast with a matching icon
-- The remote is connected lazily, so the HUD works before Core boots. The last message of each kind is mirrored
-- on PD_Hype as attributes LastBig / LastFeed / LastToast (handy for tests).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Feed = require(script.Parent.Feed)
local Hype = require(script.Parent.Hype)
local Info = require(script.Parent.Info)
local Remotes = require(script.Parent.Remotes)
local Results = require(script.Parent.Results)

local Announce = {}

-- Toast icon from its wording (first match wins).
local TOAST_ICONS = {
	{ "coin", "coin" },
	{ "xp", "xp_star" },
	{ "level", "xp_star" },
	{ "revive", "revive_heart" },
	{ "streak", "fire_streak" },
	{ "spin", "spin_ticket" },
	{ "chest", "chest_daily" },
	{ "gift", "gift" },
	{ "win", "trophy" },
	{ "knocked", "hit_star" },
}

local function toastIcon(text: string): string?
	local lower = string.lower(text)
	for _, pair in TOAST_ICONS do
		if string.find(lower, pair[1], 1, true) then
			return pair[2]
		end
	end
	return nil
end

function Announce.start()
	local hud = Hype.gui()
	hud:SetAttribute("LastFeed", "")
	hud:SetAttribute("LastToast", "")
	Remotes.on("Core_Announce", function(kind, text, sub, colorHex)
		if typeof(kind) ~= "string" or typeof(text) ~= "string" then
			return
		end
		local clean = Info.clean(text)
		if clean == "" then
			return
		end
		if kind == "big" then
			-- the results card already shows the result headline: never show it twice
			if Results.claims(clean) then
				return
			end
			Hype.show(clean, { sub = typeof(sub) == "string" and sub or nil, color = Info.hex(colorHex) })
		elseif kind == "feed" then
			hud:SetAttribute("LastFeed", clean)
			Feed.push(clean)
		elseif kind == "toast" then
			hud:SetAttribute("LastToast", clean)
			UIKit.toast(clean, Info.hex(colorHex), toastIcon(clean))
		end
	end)
end

return Announce
