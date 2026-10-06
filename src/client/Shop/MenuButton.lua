--!strict
-- The big "SHOP" button docked into PlayerGui.PartyHUD.MenuRail (LayoutOrder 10). Rebuilt automatically
-- if the UI piece ever recreates PartyHUD. A red "!" badge bounces while an upgrade is affordable.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local C = Theme.Colors

local MenuButton = {}

local function build(rail: Instance, onClick: () -> ()): (TextButton, () -> ())
	local button, scale = Ui.button(nil, C.Orange, {
		Name = "ShopButton",
		LayoutOrder = 10,
		Size = UDim2.fromScale(1, 1),
		SizeConstraint = Enum.SizeConstraint.RelativeXX, -- square, as wide as the rail
		ZIndex = 6,
	}, UDim.new(0.28, 0))
	local fill = button:FindFirstChild("Fill") :: UIGradient
	fill.Color = ColorSequence.new(Ui.lighten(C.Yellow, 0.2), C.Orange)

	-- glossy top highlight
	local gloss = Ui.box(button, {
		Name = "Gloss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.fromScale(0.8, 0.3),
		BackgroundTransparency = 0.65,
		BackgroundColor3 = C.White,
		ZIndex = 6,
	})
	Ui.corner(gloss, UDim.new(0.5, 0))

	local coin = Ui.coin(button, {
		Name = "Coin",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.48, 0.48),
		ZIndex = 7,
	}, 2.5)
	local coinScale = Ui.scaler(coin)
	Ui.label(button, "SHOP", {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.fromScale(0.9, 0.3),
		ZIndex = 8,
	}, { max = 30, stroke = 2.5 })

	local badge = Ui.panel(button, C.Red, {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.9, 0.1),
		Size = UDim2.fromScale(0.34, 0.34),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		Visible = false,
		ZIndex = 9,
	}, UDim.new(0.5, 0), 2.5)
	Ui.label(badge, "!", { ZIndex = 10 }, { max = 28, stroke = 2 })
	local badgeScale = Ui.scaler(badge)
	local pulse = TweenService:Create(
		badgeScale,
		TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.18 }
	)
	pulse:Play()
	button.Destroying:Connect(function()
		pulse:Cancel()
	end)

	button.Activated:Connect(function()
		Sfx.play("click")
		Ui.punch(scale, 0.12, 0.3)
		onClick()
	end)
	-- a little coin spin on hover
	button.MouseEnter:Connect(function()
		coin.Rotation = -20
		Ui.tween(coin, 0.5, { Rotation = 0 }, Enum.EasingStyle.Elastic)
		Ui.punch(coinScale, 0.15, 0.3)
	end)

	local function refresh()
		local show = State.loaded() and State.canAffordUpgrade()
		if show and not badge.Visible then
			Ui.punch(coinScale, 0.3, 0.4)
		end
		badge.Visible = show
	end
	refresh()
	button.Parent = rail
	return button, refresh
end

function MenuButton.start(playerGui: PlayerGui, onClick: () -> ())
	local button: TextButton? = nil
	local refresh: (() -> ())? = nil

	local function dock()
		local hud = playerGui:FindFirstChild("PartyHUD")
		local rail = hud and hud:FindFirstChild("MenuRail")
		if not rail then
			return
		end
		if button and button.Parent == rail then
			return
		end
		if button then
			button:Destroy()
		end
		button, refresh = build(rail, onClick)
	end

	local hudConn: RBXScriptConnection? = nil
	local function watchHud(hud: Instance)
		if hud.Name ~= "PartyHUD" then
			return
		end
		if hudConn then
			hudConn:Disconnect()
		end
		hudConn = hud.ChildAdded:Connect(function(child)
			if child.Name == "MenuRail" then
				dock()
			end
		end)
		dock()
	end
	playerGui.ChildAdded:Connect(watchHud)
	local existing = playerGui:FindFirstChild("PartyHUD")
	if existing then
		watchHud(existing)
	end

	State.changed:Connect(function()
		if refresh and button and button.Parent then
			refresh()
		end
	end)
end

return MenuButton
