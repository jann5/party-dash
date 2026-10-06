--!strict
-- ScreenGui "EconomyHUD": top-right cluster in the Roblox top bar row with an animated coin counter
-- (coins fly in when you earn them) and a level/XP bar (LEVEL UP! burst). Tapping it opens the shop.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local C = Theme.Colors

local Hud = {}

local DESIGN_H = 44 -- the cluster is authored 44px tall and scaled to the top bar height
local COIN_W = 176
local LEVEL_W = 176
local GAP = 14

function Hud.start(playerGui: PlayerGui, openShop: (tab: string?) -> ()): ScreenGui
	local old = playerGui:FindFirstChild("EconomyHUD")
	if old then
		old:Destroy()
	end
	local gui = Ui.new("ScreenGui", {
		Name = "EconomyHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true, -- we sit inside the top bar row
		DisplayOrder = 14, -- above the shop window dim so the balance stays readable
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- avoid notches, allow the top bar row
	end)

	local cluster = Ui.box(gui, {
		Name = "TopRight",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(LEVEL_W + GAP + COIN_W, DESIGN_H),
		ZIndex = 2,
	})
	local clusterScale = Ui.scaler(cluster)

	-- Coin counter ------------------------------------------------------------------------------
	local coinPill, coinScale = Ui.button(cluster, Ui.darken(C.Panel, 0.1), {
		Name = "CoinCounter",
		Position = UDim2.fromOffset(LEVEL_W + GAP, 0),
		Size = UDim2.fromOffset(COIN_W, DESIGN_H),
		ZIndex = 2,
	}, UDim.new(0.5, 0))
	local coinIcon = Ui.coin(coinPill, {
		Name = "CoinIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(16, DESIGN_H / 2),
		Size = UDim2.fromOffset(50, 50),
		ZIndex = 3,
	}, 3)
	local coinIconScale = Ui.scaler(coinIcon)
	local amount = Ui.label(coinPill, "0", {
		Name = "Amount",
		Position = UDim2.fromOffset(46, 5),
		Size = UDim2.fromOffset(COIN_W - 46 - 40, DESIGN_H - 10),
		TextColor3 = Color3.fromRGB(255, 226, 110),
		ZIndex = 3,
	}, { max = 30, stroke = 2.5 })
	local plus = Ui.panel(coinPill, C.Green, {
		Name = "Plus",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 3,
	}, UDim.new(0.5, 0), 2.5)
	Ui.gradient(plus, Ui.lighten(C.Green, 0.3), C.Green)
	Ui.label(plus, "+", { ZIndex = 4, Position = UDim2.fromOffset(0, -1) }, { max = 26, stroke = 2 })
	coinPill.Activated:Connect(function()
		Sfx.play("click")
		openShop("Robux")
	end)

	-- Level bar ---------------------------------------------------------------------------------
	local levelPill, _ = Ui.button(cluster, Ui.darken(C.Panel, 0.1), {
		Name = "LevelBar",
		Size = UDim2.fromOffset(LEVEL_W, DESIGN_H),
		ZIndex = 2,
	}, UDim.new(0.5, 0))
	local trough = Ui.panel(levelPill, Ui.TILE, {
		Name = "Trough",
		Position = UDim2.fromOffset(40, 11),
		Size = UDim2.fromOffset(LEVEL_W - 52, DESIGN_H - 22),
		ZIndex = 3,
		ClipsDescendants = true,
	}, UDim.new(0.5, 0), 2)
	local fill = Ui.box(trough, {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
	})
	Ui.corner(fill, UDim.new(0.5, 0))
	Ui.gradient(fill, Color3.fromRGB(255, 140, 210), C.Purple, 0)
	local xpText = Ui.label(levelPill, "0 / 75 XP", {
		Name = "XPText",
		Position = UDim2.fromOffset(40, 9),
		Size = UDim2.fromOffset(LEVEL_W - 52, DESIGN_H - 18),
		ZIndex = 4,
	}, { max = 15, stroke = 1.5 })
	local badge = Ui.panel(levelPill, C.Yellow, {
		Name = "LevelBadge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(16, DESIGN_H / 2),
		Size = UDim2.fromOffset(52, 52),
		ZIndex = 4,
	}, UDim.new(0.5, 0), 3)
	Ui.gradient(badge, Ui.lighten(C.Yellow, 0.35), C.Orange)
	local badgeScale = Ui.scaler(badge)
	Ui.label(badge, "LV", {
		Name = "Caption",
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(1, 0, 0, 13),
		TextColor3 = C.Ink,
		ZIndex = 5,
	}, { max = 13, stroke = 0 })
	local levelText = Ui.label(badge, "1", {
		Name = "Level",
		Position = UDim2.fromOffset(0, 15),
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 5,
	}, { max = 28, stroke = 2.5 })
	levelPill.Activated:Connect(function()
		Sfx.play("click")
		openShop("Upgrades")
	end)

	local levelUp = Ui.label(cluster, "LEVEL UP!", {
		Name = "LevelUp",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(LEVEL_W / 2, DESIGN_H + 6),
		Size = UDim2.fromOffset(LEVEL_W + 40, 34),
		TextColor3 = C.Yellow,
		Visible = false,
		ZIndex = 6,
	}, { max = 30, stroke = 3 })
	local levelUpScale = Ui.scaler(levelUp)

	local delta = Ui.label(cluster, "", {
		Name = "Delta",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(LEVEL_W + GAP + COIN_W / 2, DESIGN_H + 4),
		Size = UDim2.fromOffset(COIN_W, 30),
		Visible = false,
		ZIndex = 6,
	}, { max = 26, stroke = 2.5 })

	-- full-screen layer for flying coins
	local layer = Ui.box(gui, { Name = "FlyLayer", ZIndex = 10 })

	-- Placement: align with Roblox's top bar buttons (44px tall, 12px from the top on desktop).
	local function place()
		local inset = GuiService:GetGuiInset()
		local top = inset.Y
		local h, y
		if top >= 30 then
			h = math.clamp(top - 14, 30, DESIGN_H)
			y = math.max(4, top - h - 2)
		else
			h, y = DESIGN_H, 10
		end
		clusterScale.Scale = h / DESIGN_H
		cluster.Position = UDim2.new(1, -16, 0, y)
	end
	place()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	-- Coins -------------------------------------------------------------------------------------
	local shown = Instance.new("NumberValue")
	shown.Changed:Connect(function(v)
		amount.Text = Rules.formatNumber(math.floor(v + 0.5))
	end)
	local target = State.coins()
	local initialized = State.loaded()
	shown.Value = target
	amount.Text = Rules.formatNumber(target)

	local deltaToken = 0
	local function showDelta(text: string, color: Color3)
		deltaToken += 1
		local token = deltaToken
		delta.Text = text
		delta.TextColor3 = color
		delta.TextTransparency = 0
		delta.Position = UDim2.fromOffset(LEVEL_W + GAP + COIN_W / 2, DESIGN_H + 2)
		delta.Visible = true
		Ui.tween(
			delta,
			0.35,
			{ Position = UDim2.fromOffset(LEVEL_W + GAP + COIN_W / 2, DESIGN_H + 12) },
			Enum.EasingStyle.Back
		)
		task.delay(1.4, function()
			if deltaToken == token then
				Ui.tween(delta, 0.3, { TextTransparency = 1 })
				local stroke = delta:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Transparency = 0
					Ui.tween(stroke, 0.3, { Transparency = 1 })
				end
			end
		end)
		local stroke = delta:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
	end

	local function rollTo(value: number, time: number, delay: number?)
		Ui.tween(shown, time, { Value = value }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, delay)
	end

	local function flyCoins(gain: number)
		local count = math.clamp(math.floor(gain / 4), 3, 12)
		local layerPos = layer.AbsolutePosition
		local size = layer.AbsoluteSize
		local iconCenter = coinIcon.AbsolutePosition + coinIcon.AbsoluteSize / 2 - layerPos
		local px = math.max(20, coinIcon.AbsoluteSize.X * 0.7)
		local origin = Vector2.new(size.X * 0.5, size.Y * 0.8)
		for i = 1, count do
			local angle = math.random() * math.pi * 2
			local spread = Vector2.new(math.cos(angle), math.sin(angle) * 0.6) * (30 + math.random() * 60)
			local c = Ui.coin(layer, {
				Name = "FlyingCoin",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(origin.X, origin.Y),
				Size = UDim2.fromOffset(px, px),
				ZIndex = 11,
			}, 2)
			local s = Ui.scaler(c, 0)
			Ui.tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			Ui.tween(c, 0.25, { Position = UDim2.fromOffset(origin.X + spread.X, origin.Y + spread.Y) })
			local fly = Ui.tween(
				c,
				0.5,
				{ Position = UDim2.fromOffset(iconCenter.X, iconCenter.Y) },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In,
				0.3 + i * 0.06
			)
			fly.Completed:Connect(function()
				c:Destroy()
				Ui.punch(coinIconScale, 0.25, 0.25)
				Ui.punch(coinScale, 0.06, 0.2)
				Sfx.play("coin", 1 + i * 0.04)
			end)
		end
		-- the counter rolls up while the coins land
		rollTo(target, 0.35 + count * 0.06, 0.75)
	end

	local function onCoins()
		local value = State.coins()
		local diff = value - target
		target = value
		if not initialized then
			shown.Value = value
			return
		end
		if diff > 0 then
			showDelta("+" .. Rules.formatNumber(diff), C.Yellow)
			flyCoins(diff)
		elseif diff < 0 then
			showDelta("-" .. Rules.formatNumber(-diff), Color3.fromRGB(255, 120, 120))
			rollTo(value, 0.45)
			Ui.punch(coinScale, -0.08, 0.3)
		end
	end

	-- Level -------------------------------------------------------------------------------------
	local lastLevel = State.level()
	local function refreshXP(animate: boolean)
		local need = math.max(1, State.xpNext())
		local ratio = math.clamp(State.xp() / need, 0, 1)
		xpText.Text = ("%s / %s XP"):format(Rules.formatNumber(State.xp()), Rules.formatNumber(need))
		levelText.Text = tostring(State.level())
		if animate then
			Ui.tween(fill, 0.5, { Size = UDim2.fromScale(ratio, 1) }, Enum.EasingStyle.Quad)
		else
			fill.Size = UDim2.fromScale(ratio, 1)
		end
	end

	local levelToken = 0
	local function celebrateLevel()
		levelToken += 1
		local token = levelToken
		Sfx.play("boom", 1.2)
		Sfx.play("ding", 0.9)
		badge.Rotation = -25
		Ui.tween(badge, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic)
		Ui.punch(badgeScale, 0.45, 0.5)
		levelUp.Visible = true
		levelUp.TextTransparency = 0
		Ui.punch(levelUpScale, 0.6, 0.45)
		task.delay(2, function()
			if levelToken == token then
				levelUp.Visible = false
			end
		end)
		-- fill to the brim, then restart from the new progress
		fill.Size = UDim2.fromScale(1, 1)
		task.delay(0.25, function()
			fill.Size = UDim2.fromScale(0, 1)
			refreshXP(true)
		end)
	end

	local function onLevel()
		local level = State.level()
		if initialized and level > lastLevel then
			lastLevel = level
			levelText.Text = tostring(level)
			celebrateLevel()
			return
		end
		lastLevel = level
		refreshXP(initialized)
	end

	refreshXP(false)
	cluster.Visible = initialized

	State.changed:Connect(function(name: string)
		if name == "Coins" then
			onCoins()
		elseif name == "Level" then
			onLevel()
		elseif name == "XP" or name == Rules.Attr.XPNext then
			refreshXP(initialized)
		elseif name == Rules.Attr.Loaded and State.loaded() and not initialized then
			-- first load: snap to the saved values, then pop the cluster in
			target = State.coins()
			shown.Value = target
			lastLevel = State.level()
			refreshXP(false)
			cluster.Visible = true
			clusterScale.Scale = 0
			place()
			local final = clusterScale.Scale
			clusterScale.Scale = 0
			Ui.tween(clusterScale, 0.45, { Scale = final }, Enum.EasingStyle.Back)
			task.delay(0.5, function()
				initialized = true
			end)
		end
	end)

	gui.Parent = playerGui
	return gui
end

return Hud
