--!strict
-- ScreenGui "EconomyShop": the shop window (banner, balance, level, tabs, content pages, toast).
-- Authored at 1000x600 design pixels; a UIScale fits it to any screen (phone landscape to 1080p).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local C = Theme.Colors

local Window = {}

local W, H = 1000, 600
Window.W = W
Window.H = H
Window.CONTENT = Vector2.new(952, 404)

Window.TABS = {
	{ id = "Upgrades", title = "UPGRADES", color = C.Blue },
	{ id = "Cosmetics", title = "COSMETICS", color = C.Pink },
	{ id = "Robux", title = "ROBUX", color = C.Green },
}

export type Api = {
	gui: ScreenGui,
	pages: { [string]: Frame },
	open: (tab: string?) -> (),
	close: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	switch: (tab: string) -> (),
	toast: (text: string, ok: boolean?) -> (),
	onSwitched: (fn: (tab: string) -> ()) -> (),
}

function Window.new(playerGui: PlayerGui): Api
	local old = playerGui:FindFirstChild("EconomyShop")
	if old then
		old:Destroy()
	end
	local gui = Ui.new("ScreenGui", {
		Name = "EconomyShop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 12, -- above the HUD/overlays, below announcements (20) and the coin counter (14)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
	end)

	local dim = Ui.new("TextButton", {
		Name = "Dim",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})

	local root = Ui.box(gui, {
		Name = "ShopRoot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(W, H),
		ZIndex = 2,
	})
	local fit = Ui.scaler(root)
	fit.Name = "Fit"

	local window = Ui.panel(root, C.Panel, {
		Name = "ShopWindow",
		ZIndex = 2,
		Active = true, -- swallow clicks so they don't reach the dim (which closes)
	}, UDim.new(0, 30), 5)
	Ui.gradient(window, Ui.lighten(C.Panel, 0.12), Ui.darken(C.Panel, 0.12))
	local pop = Ui.scaler(window)
	pop.Name = "Pop"

	-- soft glossy highlight across the top band
	local band = Ui.box(window, {
		Name = "Band",
		Size = UDim2.fromOffset(W, 166),
		BackgroundTransparency = 0.9,
		BackgroundColor3 = C.White,
		ZIndex = 2,
	})
	Ui.corner(band, UDim.new(0, 30))
	Ui.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0, 1),
		Parent = band,
	})

	-- Banner --------------------------------------------------------------------------------------
	local banner = Ui.panel(window, C.Yellow, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(W / 2, 0),
		Size = UDim2.fromOffset(300, 86),
		Rotation = -2,
		ZIndex = 5,
	}, UDim.new(0, 26), 5)
	Ui.gradient(banner, Ui.lighten(C.Yellow, 0.3), C.Orange)
	Ui.label(banner, "SHOP", {
		Name = "Title",
		Position = UDim2.fromOffset(0, 4),
		ZIndex = 6,
	}, { max = 60, stroke = 4 })
	local bannerScale = Ui.scaler(banner)

	-- Close ---------------------------------------------------------------------------------------
	local closeButton = Ui.button(window, C.Red, {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(W - 14, 14),
		Size = UDim2.fromOffset(66, 66),
		ZIndex = 6,
	}, UDim.new(0.5, 0))
	Ui.label(closeButton, "X", { ZIndex = 7, Position = UDim2.fromOffset(0, 1) }, { max = 38, stroke = 3 })

	-- Balance + level chips -------------------------------------------------------------------------
	local balance = Ui.panel(window, Ui.TILE, {
		Name = "Balance",
		Position = UDim2.fromOffset(26, 26),
		Size = UDim2.fromOffset(236, 56),
		ZIndex = 3,
	}, UDim.new(0.5, 0), 3)
	Ui.coin(balance, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(28, 28),
		Size = UDim2.fromOffset(46, 46),
		ZIndex = 4,
	}, 3)
	local balanceText = Ui.label(balance, "0", {
		Name = "Amount",
		Position = UDim2.fromOffset(58, 8),
		Size = UDim2.fromOffset(166, 40),
		TextColor3 = Color3.fromRGB(255, 226, 110),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	}, { max = 32, stroke = 2.5 })
	local balanceScale = Ui.scaler(balance)

	local levelChip = Ui.panel(window, Ui.TILE, {
		Name = "LevelChip",
		Position = UDim2.fromOffset(W - 26 - 44 - 190, 26),
		Size = UDim2.fromOffset(190, 56),
		ZIndex = 3,
	}, UDim.new(0.5, 0), 3)
	local levelText = Ui.label(levelChip, "LEVEL 1", {
		Name = "Level",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(166, 40),
		TextColor3 = Color3.fromRGB(215, 185, 255),
		ZIndex = 4,
	}, { max = 30, stroke = 2.5 })

	-- Tabs ----------------------------------------------------------------------------------------
	local tabsRow = Ui.box(window, {
		Name = "Tabs",
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.fromOffset(W, 66),
		ZIndex = 3,
	})
	local content = Ui.box(window, {
		Name = "Content",
		Position = UDim2.fromOffset(24, 174),
		Size = UDim2.fromOffset(Window.CONTENT.X, Window.CONTENT.Y),
		ZIndex = 3,
	})

	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: { button: TextButton, scale: UIScale, label: TextLabel, color: Color3 } } = {}
	local current: string? = nil
	local switchedListeners: { (string) -> () } = {}

	local TAB_W, TAB_GAP = 236, 18
	local x0 = W / 2 - (3 * TAB_W + 2 * TAB_GAP) / 2
	for i, tab in Window.TABS do
		local b, s = Ui.button(tabsRow, Ui.CARD, {
			Name = tab.id .. "Tab",
			Position = UDim2.fromOffset(x0 + (i - 1) * (TAB_W + TAB_GAP), 2),
			Size = UDim2.fromOffset(TAB_W, 62),
			ZIndex = 3,
		}, UDim.new(0, 20))
		local label = Ui.label(b, tab.title, {
			Name = "Label",
			Position = UDim2.fromOffset(10, 9),
			Size = UDim2.fromOffset(TAB_W - 20, 44),
			ZIndex = 4,
		}, { max = 30, stroke = 2.5 })
		tabButtons[tab.id] = { button = b, scale = s, label = label, color = tab.color }
		pages[tab.id] = Ui.box(content, { Name = tab.id, Visible = false, ZIndex = 3 })
	end

	-- Toast -----------------------------------------------------------------------------------------
	local toastFrame = Ui.panel(window, C.Green, {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(W / 2, H),
		Size = UDim2.fromOffset(560, 56),
		Visible = false,
		ZIndex = 20,
	}, UDim.new(0.5, 0), 4)
	local toastGradient = Ui.gradient(toastFrame, C.Green, C.Green)
	local toastLabel = Ui.label(toastFrame, "", {
		Name = "Text",
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.fromOffset(524, 40),
		ZIndex = 21,
	}, { max = 26, stroke = 2.5 })
	local toastScale = Ui.scaler(toastFrame)
	local toastToken = 0

	local api = {} :: Api
	api.gui = gui
	api.pages = pages

	function api.toast(text: string, ok: boolean?)
		toastToken += 1
		local token = toastToken
		local color = if ok == false then C.Red else C.Green
		toastGradient.Color = ColorSequence.new(Ui.lighten(color, 0.25), color)
		toastLabel.Text = text
		toastFrame.Visible = true
		toastScale.Scale = 0.4
		Ui.tween(toastScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(2.2, function()
			if toastToken == token then
				Ui.tween(toastScale, 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed
					:Connect(function()
						if toastToken == token then
							toastFrame.Visible = false
						end
					end)
			end
		end)
	end

	function api.switch(tab: string)
		if not pages[tab] then
			tab = "Upgrades"
		end
		if current == tab then
			return
		end
		local first = current == nil
		current = tab
		for id, info in tabButtons do
			local active = id == tab
			Ui.tint(info.button, if active then info.color else Ui.CARD)
			info.label.TextColor3 = if active then C.White else Ui.MUTED
			info.button.ZIndex = if active then 4 else 3
			pages[id].Visible = active
		end
		local info = tabButtons[tab]
		Ui.punch(info.scale, 0.08, 0.3)
		local page = pages[tab]
		page.Position = UDim2.fromOffset(0, 18)
		Ui.tween(page, 0.3, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
		if not first then
			Sfx.play("pop", 1.3)
		end
		for _, fn in switchedListeners do
			task.spawn(fn, tab)
		end
	end

	function api.onSwitched(fn: (string) -> ())
		table.insert(switchedListeners, fn)
	end

	for id, info in tabButtons do
		info.button.Activated:Connect(function()
			api.switch(id)
		end)
	end

	-- Fit to screen -------------------------------------------------------------------------------
	local function refit()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		-- leave room for the banner/close overhang and the toast below
		fit.Scale = math.min(size.X * 0.95 / (W + 50), size.Y * 0.9 / (H + 90), 1.25)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)

	-- Balance / level -------------------------------------------------------------------------------
	local lastCoins = State.coins()
	local function refreshHeader()
		local coins = State.coins()
		balanceText.Text = Rules.formatNumber(coins)
		if coins ~= lastCoins and gui.Enabled then
			Ui.punch(balanceScale, if coins > lastCoins then 0.1 else -0.06, 0.3)
		end
		lastCoins = coins
		levelText.Text = ("LEVEL %d"):format(State.level())
	end
	refreshHeader()
	State.changed:Connect(function(name)
		if name == "Coins" or name == "Level" then
			refreshHeader()
		end
	end)

	-- Open / close ----------------------------------------------------------------------------------
	local opened = false
	local blur: BlurEffect? = nil
	local closeToken = 0

	local function setBlur(on: boolean)
		local camera = workspace.CurrentCamera
		if on and camera then
			if not blur or not blur.Parent then
				blur = Ui.new("BlurEffect", { Name = "ShopBlur", Size = 0, Parent = camera })
			end
			Ui.tween(blur :: BlurEffect, 0.3, { Size = 10 })
		elseif blur then
			Ui.tween(blur, 0.2, { Size = 0 })
		end
	end

	function api.open(tab: string?)
		closeToken += 1
		if tab or not current then
			api.switch(tab or "Upgrades")
		end
		if opened then
			return
		end
		opened = true
		gui.Enabled = true
		refit()
		refreshHeader()
		dim.BackgroundTransparency = 1
		Ui.tween(dim, 0.25, { BackgroundTransparency = 0.45 })
		pop.Scale = 0.6
		Ui.tween(pop, 0.42, { Scale = 1 }, Enum.EasingStyle.Back)
		bannerScale.Scale = 0
		Ui.tween(bannerScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.12)
		banner.Rotation = -10
		Ui.tween(banner, 0.7, { Rotation = -2 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0.12)
		setBlur(true)
		Sfx.play("whoosh", 1)
		Sfx.play("pop", 1.1)
	end

	function api.close()
		if not opened then
			return
		end
		opened = false
		closeToken += 1
		local token = closeToken
		Ui.tween(dim, 0.2, { BackgroundTransparency = 1 })
		Ui.tween(pop, 0.2, { Scale = 0.7 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		setBlur(false)
		Sfx.play("whoosh", 1.3)
		task.delay(0.21, function()
			if closeToken == token and not opened then
				gui.Enabled = false
			end
		end)
	end

	function api.toggle()
		if opened then
			api.close()
		else
			api.open()
		end
	end

	function api.isOpen(): boolean
		return opened
	end

	closeButton.Activated:Connect(api.close)
	dim.Activated:Connect(api.close)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not opened then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonB then
			api.close()
		end
	end)

	-- a round is about to start: get the shop out of the way
	GameState.onChanged("Phase", function(phase)
		if phase == GameState.Phase.Countdown or phase == GameState.Phase.Intro then
			api.close()
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		-- the camera may be new after a respawn; re-home the blur
		if opened then
			setBlur(true)
		end
	end)

	gui.Parent = playerGui
	refit()
	return api
end

return Window
