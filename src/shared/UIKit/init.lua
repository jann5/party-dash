--!nonstrict
--[[
Party Dash UIKit v2 — THE UI kit (client-only). FROZEN CONTRACT, lead-owned. Encodes docs/v2/ART_BIBLE.md §8.
Design in 1080p pixels; every UIKit.screen() root carries a UIScale so phones (800x360) and 1080p both work.

	local UIKit = require(ReplicatedStorage.Shared.UIKit)
	local gui, root = UIKit.screen("MyHud", "HUD")                 -- ScreenGui + design-px root Frame
	UIKit.text(root, { text = "Hello", size = 40, drop = true })   -- outlined FredokaOne label
	local b = UIKit.button(root, { text = "Claim", color = "Green", size = Vector2.new(240, 80), onClick = fn })
	UIKit.tile(parent, { icon = "shop", label = "Shop", color = "Green", onClick = fn }) -- ref1 icon tile
	UIKit.pill(parent, { icon = "coin", text = "1,250" })          -- counters / timers
	UIKit.priceTag(parent, { price = 19, was = 199 })              -- Robux price, struck-through old price
	local p = UIKit.panel({ name = "Shop", title = "Shop", icon = "shop", color = "Green", size = Vector2.new(1100, 680) })
	p.body ... p.open() / p.close()                                -- one modal at a time, Esc / X / dim closes
	UIKit.Panel.sideTabs(p.body, tabs) / UIKit.Panel.scroll(parent) / UIKit.Panel.card(parent, props)
	UIKit.Dock.add("Left", { id = "Shop", order = 10, icon = "shop", label = "Shop", color = "Green", onClick = fn })
	UIKit.Lanes.get("Action")                                      -- bottom-center lane for contextual UI
	UIKit.toast("+25 coins", Color3?, "coin")                     -- toast (above panels)
	UIKit.pop(gui) / UIKit.punch(gui) / UIKit.shake(gui) / UIKit.pulse(gui) / UIKit.bob(gui) / UIKit.shine(gui)
	UIKit.countUp(label, from, to, t?, fmt?)
	UIKit.fmt.number(12450) -> "12,450"; fmt.short; fmt.clock(74) -> "1:14"; fmt.long(s) -> "1d 02h 03m 04s"
	UIKit.Style (tokens: Colors, Text sizes, Variants, Layers, Corner, robux(n))
	UIKit.sound("UiClick")  -- UI group sound via Shared.Audio
Buttons made with UIKit play the click sound themselves and carry attribute PD_NoClick (the global click hook
skips them). Give a raw GuiButton attribute PD_NoClick = true if it must stay silent.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Core = require(script.Core)
local Style = require(script.Style)
local Format = require(script.Format)
local Panel = require(script.Panel)
local DockLanes = require(script.Dock)

local UIKit = {}

UIKit.Style = Style
UIKit.fmt = Format
UIKit.Panel = Panel
UIKit.Dock = DockLanes.Dock
UIKit.Lanes = DockLanes.Lanes

UIKit.new = Core.new
UIKit.corner = Core.corner
UIKit.border = Core.border
UIKit.gradient = Core.gradient
UIKit.padding = Core.padding
UIKit.list = Core.list
UIKit.screen = Core.screen
UIKit.scale = Core.scale
UIKit.isTouch = Core.isTouch
UIKit.text = Core.text
UIKit.icon = Core.icon
UIKit.badge = Core.badge
UIKit.button = Core.button
UIKit.tile = Core.tile
UIKit.pill = Core.pill
UIKit.priceTag = Core.priceTag
UIKit.tween = Core.tween
UIKit.pop = Core.pop
UIKit.punch = Core.punch
UIKit.shake = Core.shake
UIKit.pulse = Core.pulse
UIKit.bob = Core.bob
UIKit.shine = Core.shine
UIKit.countUp = Core.countUp
UIKit.sound = Core.sound
UIKit.panel = Panel.new

function UIKit.iconId(key: string): string
	return Assets.icon(key)
end

-- ===== toasts (own ScreenGui above panels) =====
local toastRoot = nil
local function toastLane()
	if toastRoot and toastRoot.Parent and toastRoot.Parent.Parent then
		return toastRoot
	end
	local _, root = Core.screen("PD_Toasts", "Toast")
	toastRoot = Core.new("Frame", {
		Name = "Stack",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(900, 300),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -240),
		Parent = root,
	})
	Core.list(
		toastRoot,
		Enum.FillDirection.Vertical,
		10,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Bottom
	)
	return toastRoot
end

local toastCount = 0
-- Small transient notice (coins earned, purchase done, "Coming soon!"). color = text color, icon = Assets key.
function UIKit.toast(text: string, color: Color3?, icon: string?, duration: number?)
	local lane = toastLane()
	toastCount += 1
	-- keep at most 4 on screen
	local kids = {}
	for _, c in lane:GetChildren() do
		if c:IsA("Frame") then
			table.insert(kids, c)
		end
	end
	table.sort(kids, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #kids >= 4 do
		table.remove(kids, 1):Destroy()
	end
	local width = math.clamp(#text * 17 + (icon and 110 or 60), 260, 860)
	local pill = Core.pill(lane, {
		name = "Toast",
		icon = icon,
		text = text,
		textColor = color,
		size = Vector2.new(width, 58),
		layoutOrder = toastCount,
		zindex = 5,
	})
	Core.pop(pill.frame, 0.5, 0.3)
	task.delay(duration or 2.6, function()
		if pill.frame.Parent then
			Core.tween(pill.frame, 0.25, { BackgroundTransparency = 1 })
			Core.tween(pill.label, 0.25, { TextTransparency = 1 })
			task.wait(0.26)
			pill.frame:Destroy()
		end
	end)
	return pill
end

return UIKit
