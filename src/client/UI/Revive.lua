--!nonstrict
-- Revive (brief #28): the action and the pink button shared by the death panel and the spectate bar.
-- Free when the player owns ReviveTokens (or Studio's Debug_FreeRevive): fires Economy_UseRevive. Otherwise the
-- Robux product goes through Shared.Purchase (Studio dev path when no id). Core/Economy decide the outcome; a
-- purchase that comes too late becomes a token on the server, never a loss.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Purchase = require(ReplicatedStorage.Shared.Purchase)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors

local Revive = {}

local player = Players.LocalPlayer

-- payloadTokens: Core_Death's revive.tokens (the attribute may replicate a moment later).
function Revive.isFree(payloadTokens: number?): boolean
	local tokens = player:GetAttribute("ReviveTokens")
	if typeof(tokens) == "number" and tokens > 0 then
		return true
	end
	if typeof(payloadTokens) == "number" and payloadTokens > 0 then
		return true
	end
	return RunService:IsStudio() and Workspace:GetAttribute("Debug_FreeRevive") == true
end

function Revive.request(payloadTokens: number?): string
	if Revive.isFree(payloadTokens) then
		Remotes.fire("Economy_UseRevive")
		return "free"
	end
	return Purchase.prompt("Revive")
end

--[[
Pink "Revive" button with a radial countdown. props: size (Vector2), layoutOrder, zindex, tokens (payload tokens)
Returns { api (UIKit ButtonApi), setWindow(endsAt, window?), update() -> boolean (false once expired) }
]]
function Revive.button(parent: Instance?, props: { [string]: any })
	local size = props.size or Vector2.new(230, 88)
	local tokens = props.tokens
	local busy = false
	local endsAt, window = 0, Config.REVIVE_WINDOW
	local api
	api = Widgets.button(parent, {
		name = "Revive",
		size = size,
		color = "Pink",
		layoutOrder = props.layoutOrder,
		zindex = props.zindex,
		onClick = function()
			if busy then
				return
			end
			busy = true
			api.button:SetAttribute("Requested", true)
			Revive.request(tokens)
			if props.onRequest then
				props.onRequest()
			end
			task.delay(1.5, function()
				busy = false
			end)
		end,
	})
	local face = api.face
	local z = api.button.ZIndex
	local ringSize = size.Y - 14
	local ring = Widgets.radial(face, {
		name = "Timer",
		size = ringSize,
		color = C.Yellow,
		trackColor = C.PinkDark,
		position = UDim2.new(0, 8 + ringSize / 2, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		zindex = z + 4,
	})
	local inner = UIKit.new("Frame", {
		Name = "Inner",
		BackgroundColor3 = C.PinkDark,
		Size = UDim2.fromScale(0.72, 0.72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = z + 6,
		Parent = ring.frame,
	})
	UIKit.corner(inner, UDim.new(0.5, 0))
	UIKit.border(inner, 2.5)
	UIKit.icon(inner, "revive_heart", { size = UDim2.fromScale(1.15, 1.15), zindex = z + 7 })
	local textX = ringSize + 18
	UIKit.text(face, {
		name = "Title",
		text = "Revive",
		size = 30,
		xalign = "left",
		frameSize = UDim2.new(1, -(textX + 8), 0, 36),
		position = UDim2.new(0, textX, 0.32, 0),
		anchor = Vector2.new(0, 0.5),
		zindex = z + 5,
	})
	local price = UIKit.text(face, {
		name = "Price",
		text = "",
		size = 28,
		color = C.Yellow,
		xalign = "left",
		frameSize = UDim2.new(1, -(textX + 8), 0, 34),
		position = UDim2.new(0, textX, 0.7, 0),
		anchor = Vector2.new(0, 0.5),
		zindex = z + 5,
	})

	local out = { api = api }
	function out.setWindow(at: number, length: number?)
		endsAt = at
		window = math.max(1, length or Config.REVIVE_WINDOW)
	end
	-- Call every frame while visible: refreshes the ring and the price. Returns false when the offer expired.
	function out.update(): boolean
		local left = endsAt - State.now()
		ring.set(left / window)
		local label = Revive.isFree(tokens) and "FREE" or UIKit.Style.robux(Purchase.price("Revive"))
		if price.Text ~= label then
			price.Text = label
		end
		return left > 0
	end
	out.update()
	return out
end

return Revive
