-- Party Dash: server -> client announcements. FROZEN CONTRACT.
-- Rendered by the UI piece (P3) which listens to Net.event("Core_Announce").
-- Wire format: (kind: "big"|"feed"|"toast", text: string, sub: string?, colorHex: string?)
--   big   = huge centered text (countdown numbers, "YOU'RE OUT!", winner banner)
--   feed  = small line in the kill feed
--   toast = small transient notice (coins earned, purchase done)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local Announce = {}

local remote = Net.event("Core_Announce")

local function hex(color: Color3?): string?
	return color and color:ToHex() or nil
end

local function send(target, kind, text, sub, color)
	if target == nil then
		remote:FireAllClients(kind, text, sub, hex(color))
	elseif typeof(target) == "Instance" then
		remote:FireClient(target, kind, text, sub, hex(color))
	else
		for _, p in target do
			if p.Parent then
				remote:FireClient(p, kind, text, sub, hex(color))
			end
		end
	end
end

-- target: nil = everyone, a Player, or a list of Players
function Announce.big(target, text: string, sub: string?, color: Color3?)
	send(target, "big", text, sub, color)
end

function Announce.feed(target, text: string)
	send(target, "feed", text)
end

function Announce.toast(target, text: string, color: Color3?)
	send(target, "toast", text, nil, color)
end

return Announce
