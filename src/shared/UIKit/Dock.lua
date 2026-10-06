--!nonstrict
-- UIKit docks (ART_BIBLE 8.5 HUD zones) and lanes. Every system adds its HUD buttons here instead of placing
-- them by hand, so nothing overlaps and the whole HUD hides/shows consistently.
--
-- DOCKS (ScreenGui "PD_Docks", layer HUD):
--   "Left"      left-middle 2-column grid of icon tiles (Shop 10, Wheel 20, Daily 30, Solo 40, Settings 90)
--   "LeftTop"   above the Left grid: wide pills (free-gift timer)
--   "Right"     right-middle column (Group chest 10, playtime/streak 20, boosts 30)
--   "TopOffers" top-right column of offer tiles (Starter 10, Limited trail 20, VIP 30)
--   "Bottom"    bottom-left currency stack (coins, level, wins)
-- Lobby-only docks (Left, LeftTop, Right, TopOffers) auto-hide while the local player is InRound.
--
--   local tile = UIKit.Dock.add("Left", { id = "Shop", order = 10, icon = "shop", label = "Shop", color = "Green",
--                                         onClick = function() ... end })   -- returns the tile ButtonApi
--   UIKit.Dock.get("Left")  -> Frame (for custom children: give them LayoutOrder)
--   UIKit.Dock.setForceHidden(true/false)  -- e.g. hide everything during a cutscene
--
-- LANES (ScreenGui "PD_Lanes", layer Lanes): bottom-center stacks so popups never cover each other:
--   UIKit.Lanes.get("Toast")   bottom-center, above the action lane (UIKit.toast uses it)
--   UIKit.Lanes.get("Action")  bottom-center contextual buttons (death panel, vote cards)
--   UIKit.Lanes.get("Top")     top-center status (phase pill, timers)
--   UIKit.Lanes.get("Feed")    top-right kill feed
local Players = game:GetService("Players")

local Core = require(script.Parent.Core)

local Dock = {}
local Lanes = {}

local docksGui, docksRoot = nil, nil
local lanesGui, lanesRoot = nil, nil
local docks = {}
local lanes = {}
local forceHidden = false

local LOBBY_ONLY = { Left = true, LeftTop = true, Right = true, TopOffers = true }

local TILE = 96

local function layoutDocks()
	if not docksRoot then
		return
	end
	local player = Players.LocalPlayer
	local inRound = player:GetAttribute("InRound") == true
	for name, f in docks do
		f.Visible = not forceHidden and not (LOBBY_ONLY[name] and inRound)
	end
end

local function ensureDocks()
	if docksRoot and docksRoot.Parent and docksGui.Parent then
		return
	end
	docksGui, docksRoot = Core.screen("PD_Docks", "HUD")
	docks = {}
	local function mk(name, props)
		local f = Core.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Parent = docksRoot,
		})
		for k, v in props do
			f[k] = v
		end
		docks[name] = f
		return f
	end
	local left = mk("Left", {
		Size = UDim2.fromOffset(TILE * 2 + 26, 520),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.5, 30),
	})
	Core.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(TILE, TILE + 14),
		CellPadding = UDim2.fromOffset(18, 26),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = 2,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = left,
	})
	local leftTop = mk("LeftTop", {
		Size = UDim2.fromOffset(TILE * 2 + 26, 70),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 0.5, 18),
	})
	Core.list(leftTop, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)
	local right = mk("Right", {
		Size = UDim2.fromOffset(TILE + 20, 460),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 40),
	})
	Core.list(right, Enum.FillDirection.Vertical, 30, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	local offers = mk("TopOffers", {
		Size = UDim2.fromOffset(TILE * 3 + 60, TILE + 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 96),
	})
	Core.list(offers, Enum.FillDirection.Horizontal, 24, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top)
	local bottom = mk("Bottom", {
		Size = UDim2.fromOffset(340, 200),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -20),
	})
	Core.list(bottom, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)
	layoutDocks()
end

local hooked = false
local function hook()
	if hooked then
		return
	end
	hooked = true
	Players.LocalPlayer:GetAttributeChangedSignal("InRound"):Connect(layoutDocks)
end

-- Adds an icon tile to a dock. def: { id, order, icon, label, color, onClick, badge, size } -> ButtonApi
-- Re-adding the same id replaces the previous tile.
function Dock.add(dockName: string, def: { [string]: any })
	ensureDocks()
	hook()
	local parent = docks[dockName]
	assert(parent, "UIKit.Dock.add: unknown dock " .. tostring(dockName))
	local old = parent:FindFirstChild(def.id or def.label or "Tile")
	if old then
		old:Destroy()
	end
	local api = Core.tile(parent, {
		name = def.id or def.label,
		size = def.size or TILE,
		color = def.color or "Blue",
		icon = def.icon,
		label = def.label,
		badge = def.badge,
		timer = def.timer,
		shine = def.shine,
		layoutOrder = def.order or 50,
		onClick = def.onClick,
	})
	return api
end

function Dock.get(dockName: string): Frame
	ensureDocks()
	hook()
	return docks[dockName]
end

function Dock.setForceHidden(on: boolean)
	forceHidden = on
	layoutDocks()
end

function Dock.refresh()
	layoutDocks()
end

local function ensureLanes()
	if lanesRoot and lanesRoot.Parent and lanesGui.Parent then
		return
	end
	lanesGui, lanesRoot = Core.screen("PD_Lanes", "Lanes")
	lanes = {}
	local function mk(name, props, dir, valign, halign)
		local f = Core.new("Frame", { Name = name, BackgroundTransparency = 1, Parent = lanesRoot })
		for k, v in props do
			f[k] = v
		end
		Core.list(f, dir, 10, halign or Enum.HorizontalAlignment.Center, valign)
		lanes[name] = f
		return f
	end
	mk("Toast", {
		Size = UDim2.fromOffset(900, 260),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -230),
	}, Enum.FillDirection.Vertical, Enum.VerticalAlignment.Bottom)
	mk("Action", {
		Size = UDim2.fromOffset(1100, 220),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
	}, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Bottom)
	mk("Top", {
		Size = UDim2.fromOffset(900, 200),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
	}, Enum.FillDirection.Vertical, Enum.VerticalAlignment.Top)
	mk("Feed", {
		Size = UDim2.fromOffset(520, 260),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 230),
	}, Enum.FillDirection.Vertical, Enum.VerticalAlignment.Top, Enum.HorizontalAlignment.Right)
end

function Lanes.get(name: string): Frame
	ensureLanes()
	local f = lanes[name]
	assert(f, "UIKit.Lanes.get: unknown lane " .. tostring(name))
	return f
end

return { Dock = Dock, Lanes = Lanes }
