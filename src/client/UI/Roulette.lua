-- Party Dash card roulette (Phase Roulette) and modifier roulette (Phase ModifierRoulette).
-- A horizontal reel of cards scrolls fast, decelerates (power ease-out) and lands exactly on the target id
-- shortly before PhaseEnd, so the winner card can pop with confetti and show its rules.
-- The reel position is a pure function of server time, so late joiners and attribute updates stay in sync.
--
-- Inspection hooks (for tests): the view Frame ("Roulette" / "ModifierRoulette") carries attributes
-- Spinning (bool), CenterId (card under the selector), SelectedId / SelectedName (after landing),
-- and the landed card has attribute Selected = true.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameState = require(ReplicatedStorage.Shared.GameState)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Confetti = require(script.Parent.Confetti)
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Kit)
local Sfx = require(script.Parent.Sfx)

local C = Theme.Colors
local Phase = GameState.Phase

local Roulette = {}

local PAD = 4 -- extra cards rendered before/after the reel so the edges never look empty
local MIN_REEL = 12 -- short reels are repeated so the spin always feels like a spin
local RAY_COUNT = 8

type Style = {
	kind: "minigame" | "modifier",
	name: string,
	title: string,
	dimTop: Color3,
	dimBottom: Color3,
	ray: Color3,
	selector: Color3,
	titleColors: ColorSequence,
	badge: string?,
}

type Card = {
	frame: Frame,
	scale: UIScale,
	shade: Frame,
	info: Data.CardInfo,
}

-- Fast start, long suspenseful slow-down; exponent 2.5 keeps the final creep under ~1s.
local function easeOutReel(x: number): number
	return 1 - (1 - x) ^ 2.5
end

local function easeOutBack(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

---------------------------------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------------------------------
local function makeCard(parent: Instance, info: Data.CardInfo, style: Style, index: number): Card
	local isMod = style.kind == "modifier"
	local base = isMod and C.Ink or info.color
	local frame = Kit.new("Frame", {
		Name = "Card_" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		ZIndex = 20,
		Visible = false,
		Parent = parent,
	})
	frame:SetAttribute("Id", info.id)
	Kit.corner(UDim.new(0.14, 0)).Parent = frame
	Kit.stroke(4.5, isMod and C.Yellow or C.Ink, true).Parent = frame
	if isMod then
		Kit.gradient(Kit.lighten(C.Panel, 0.15), C.Ink).Parent = frame
	else
		Kit.gradient(Kit.lighten(base, 0.35), Kit.darken(base, 0.18)).Parent = frame
	end

	-- glossy highlight on the upper half
	local shine = Kit.new("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(0.9, 0.42),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = frame,
	})
	Kit.corner(UDim.new(0.25, 0)).Parent = shine

	local bubble = Kit.new("Frame", {
		Name = "IconBubble",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.66, 0.66),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundColor3 = isMod and info.color or C.White,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = frame,
	})
	Kit.corner(UDim.new(0.5, 0)).Parent = bubble
	Kit.stroke(3.5, C.Ink, true).Parent = bubble
	Kit.label(info.icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.7, 0.7),
		ZIndex = 3,
		Parent = bubble,
	}, { maxText = 120, stroke = 0 })

	Kit.label(info.name, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.82),
		Size = UDim2.fromScale(0.9, 0.24),
		TextColor3 = isMod and C.Yellow or C.White,
		ZIndex = 3,
		Parent = frame,
	}, { maxText = 44, stroke = 3 })

	-- darkening veil for cards away from the selector (transparency driven per frame)
	local shade = Kit.new("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = frame,
	})
	Kit.corner(UDim.new(0.14, 0)).Parent = shade

	return { frame = frame, scale = Kit.scaler(frame), shade = shade, info = info }
end

---------------------------------------------------------------------------------------------------
-- View: one full-screen roulette overlay
---------------------------------------------------------------------------------------------------
local View = {}
View.__index = View

function View.new(gui: ScreenGui, style: Style)
	local self = setmetatable({}, View)
	self.style = style
	self.visible = false
	self.cards = {} :: { Card }
	self.landed = true
	self.lastIdx = 0
	self.lastTick = 0

	local root = Kit.box({ Name = style.name, Visible = false, ZIndex = 10, ClipsDescendants = true, Parent = gui })
	self.root = root

	local dim = Kit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = root,
	})
	Kit.gradient(style.dimTop, style.dimBottom).Parent = dim
	self.dim = dim

	-- slowly rotating sunburst behind everything
	local rays = Kit.box({
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(1.5, 1.5),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		ZIndex = 11,
		Parent = root,
	})
	self.rays = {}
	for i = 1, RAY_COUNT do
		local ray = Kit.new("Frame", {
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.07, 1),
			BackgroundColor3 = style.ray,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			ZIndex = 11,
			Parent = rays,
		})
		Kit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
		table.insert(self.rays, ray)
	end

	local content = Kit.box({ Name = "Content", ZIndex = 12, Parent = root })
	self.contentScale = Kit.scaler(content)

	self.title = Kit.label(style.title, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromScale(0.8, 0.14),
		ZIndex = 13,
		Parent = content,
	}, { maxText = 96, stroke = 7 })
	self.titleGradient = Kit.new("UIGradient", {
		Rotation = 90,
		Color = style.titleColors,
		Parent = self.title,
	})
	self.titleScale = Kit.scaler(self.title)

	if style.badge then
		local badge = Kit.panel(C.Yellow, {
			Name = "Badge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.265),
			Size = UDim2.fromScale(0.24, 0.07),
			ZIndex = 14,
			Parent = content,
		}, UDim.new(0.5, 0), 3.5)
		Kit.aspect(4.2).Parent = badge
		Kit.gradient(C.Yellow, C.Orange).Parent = badge
		Kit.label(style.badge, {
			Name = "BadgeText",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.72),
			ZIndex = 15,
			Parent = badge,
		}, { maxText = 40, stroke = 2.5 })
		self.badge = badge
		self.badgeScale = Kit.scaler(badge)
	end

	-- the reel band
	local band = Kit.box({
		Name = "Reel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(1, 0.42),
		ZIndex = 16,
		Parent = content,
	})
	self.band = band
	local strip = Kit.new("Frame", {
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.05, 0.9),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 16,
		Parent = band,
	})
	Kit.stroke(4, style.selector, true).Parent = strip
	self.cardLayer = Kit.box({ Name = "Cards", ZIndex = 17, Parent = band })

	-- selector frame + pointers
	local selector = Kit.new("Frame", {
		Name = "Selector",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = band,
	})
	Kit.corner(UDim.new(0.16, 0)).Parent = selector
	self.selectorStroke = Kit.stroke(7, style.selector, true)
	self.selectorStroke.Parent = selector
	self.selectorScale = Kit.scaler(selector)
	self.selector = selector
	for _, top in { true, false } do
		local arrow = Kit.new("Frame", {
			Name = top and "PointerTop" or "PointerBottom",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, top and -0.035 or 1.035),
			Size = UDim2.fromScale(0.15, 0.15),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			Rotation = 45,
			BackgroundColor3 = style.selector,
			BorderSizePixel = 0,
			ZIndex = 41,
			Parent = selector,
		})
		Kit.corner(UDim.new(0.2, 0)).Parent = arrow
		Kit.stroke(3.5, C.Ink, true).Parent = arrow
	end

	-- info panel (rules / description) revealed after landing
	local info = Kit.panel(C.White, {
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.855),
		Size = UDim2.fromScale(0.64, 0.17),
		Visible = false,
		ZIndex = 45,
		Parent = content,
	}, UDim.new(0.3, 0), 4)
	Kit.aspect(5.2).Parent = info
	Kit.sizeLimit(940, 190).Parent = info
	self.info = info
	self.infoScale = Kit.scaler(info)
	self.infoHeader = Kit.label("", {
		Name = "Header",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.9, 0.36),
		TextColor3 = style.selector,
		ZIndex = 46,
		Parent = info,
	}, { maxText = 40, stroke = 2.5 })
	self.infoBody = Kit.label("", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.92, 0.46),
		TextColor3 = C.Ink,
		ZIndex = 46,
		Parent = info,
	}, { maxText = 34, stroke = 0 })

	return self
end

function View:show()
	if self.visible then
		return
	end
	self.visible = true
	self.root.Visible = true
	self.dim.BackgroundTransparency = 1
	Kit.tween(self.dim, 0.3, { BackgroundTransparency = 0.12 })
	Kit.popIn(self.contentScale, 0.45)
	Kit.popIn(self.titleScale, 0.55, 0.1)
	if self.badgeScale then
		Kit.popIn(self.badgeScale, 0.5, 0.3)
	end
	Sfx.play("whoosh")
	if not self.conn then
		local t0 = os.clock()
		self.conn = RunService.RenderStepped:Connect(function()
			self:step(os.clock() - t0)
		end)
	end
end

function View:hide()
	if not self.visible then
		return
	end
	self.visible = false
	Kit.tween(self.dim, 0.25, { BackgroundTransparency = 1 })
	local tw = Kit.popOut(self.contentScale, 0.25)
	tw.Completed:Connect(function()
		if self.visible then
			return
		end
		self.root.Visible = false
		if self.conn then
			self.conn:Disconnect()
			self.conn = nil
		end
	end)
end

-- Build cards for a reel (ids already include the target as the last entry) and start spinning.
function View:spin(items: { Data.CardInfo }, startT: number, endT: number)
	for _, card in self.cards do
		card.frame:Destroy()
	end
	self.cards = {}
	local n = #items
	for k = 1, n + PAD * 2 do
		local itemIndex = ((k - PAD - 1) % n) + 1
		self.cards[k] = makeCard(self.cardLayer, items[itemIndex], self.style, k)
	end
	self.startPos = PAD + 1
	self.endPos = PAD + n
	self.startT = startT
	self:retime(endT)
	self.landed = false
	self.lastIdx = 0
	self.landT = nil
	self.info.Visible = false
	self.title.Text = self.style.title
	self.titleGradient.Color = self.style.titleColors
	self.root:SetAttribute("Spinning", true)
	self.root:SetAttribute("SelectedId", "")
	self.root:SetAttribute("SelectedName", "")
	self.root:SetAttribute("CenterId", "")
end

-- Land a bit before PhaseEnd so the winner pop is actually seen before the next phase.
function View:retime(endT: number)
	self.endT = endT
	local total = math.max(endT - self.startT, 0.2)
	local hold = math.clamp(total * 0.22, 0.35, 1.2)
	self.spinEnd = self.startT + math.max(total - hold, 0.15)
end

function View:land()
	self.landed = true
	self.landT = os.clock()
	local card = self.cards[self.endPos]
	local info = card.info
	card.frame:SetAttribute("Selected", true)
	self.root:SetAttribute("Spinning", false)
	self.root:SetAttribute("SelectedId", info.id)
	self.root:SetAttribute("SelectedName", info.name)
	self.root:SetAttribute("CenterId", info.id)

	if self.style.kind == "minigame" then
		self.title.Text = info.name .. "!"
		self.titleGradient.Color = ColorSequence.new(C.White, Kit.lighten(info.color, 0.2))
		self.infoHeader.Text = "HOW TO PLAY"
	else
		self.infoHeader.Text = info.name
	end
	Kit.punch(self.titleScale, 0.35, 0.5)
	self.infoBody.Text = info.text
	self.info.Visible = true
	Kit.popIn(self.infoScale, 0.45, 0.12)
	self.selectorStroke.Color = C.White
	Kit.tween(self.selectorStroke, 0.5, { Color = self.style.selector })
	Kit.punch(self.selectorScale, 0.2, 0.4)
	Sfx.play("land")
	Sfx.play("pop", 1.2)
	Confetti.burst(Vector2.new(0.5, 0.5), 70)
end

function View:layout(pos: number, popT: number?)
	local size = self.band.AbsoluteSize
	if size.Y <= 0 then
		return
	end
	local cardH = size.Y * 0.78
	local cardW = cardH * 0.74
	local spacing = cardW * 1.16
	local cx, cy = size.X / 2, size.Y / 2
	local winnerPop = popT and easeOutBack(math.clamp(popT / 0.45, 0, 1)) or 0
	for k, card in self.cards do
		local d = k - pos
		local x = cx + d * spacing
		local frame = card.frame
		if math.abs(x - cx) > cx + cardW then
			frame.Visible = false
			continue
		end
		local ad = math.min(math.abs(d), 3)
		frame.Visible = true
		frame.Size = UDim2.fromOffset(cardW, cardH)
		frame.Position = UDim2.fromOffset(x, cy + ad * ad * cardH * 0.025)
		frame.Rotation = math.clamp(d * 4, -14, 14)
		frame.ZIndex = 40 - math.floor(ad * 4)
		local scale = 1.1 - ad * 0.1
		local shade = math.min(ad * 0.22, 0.6)
		if popT then
			if k == self.endPos then
				scale += 0.12 * winnerPop
				frame.ZIndex = 41
			else
				scale -= 0.08 * math.clamp(popT / 0.3, 0, 1)
				shade = math.max(shade, 0.55 * math.clamp(popT / 0.3, 0, 1))
			end
		end
		card.scale.Scale = scale
		card.shade.BackgroundTransparency = 1 - shade
	end
	local grow = popT and (1 + 0.12 * winnerPop) or 1
	self.selector.Size = UDim2.fromOffset(cardW * 1.1 * 1.08 * grow, cardH * 1.1 * 1.06 * grow)
end

function View:step(t: number)
	-- ambience
	for i, ray in self.rays do
		ray.Rotation = (i - 1) * (180 / RAY_COUNT) + t * 14
	end
	if self.badge then
		self.badge.Rotation = math.sin(t * 4) * 5
	end
	if self.style.kind == "modifier" then
		-- rainbow shimmer across the SPECIAL ROUND title
		self.titleGradient.Offset = Vector2.new(0, math.sin(t * 3) * 0.15)
	end
	if #self.cards == 0 then
		return
	end

	if self.landed then
		self:layout(self.endPos, self.landT and (os.clock() - self.landT) or nil)
		self.selectorScale.Scale = 1 + math.sin(t * 6) * 0.02
		return
	end

	local now = workspace:GetServerTimeNow()
	local u = math.clamp((now - self.startT) / math.max(self.spinEnd - self.startT, 0.05), 0, 1)
	local pos = self.startPos + (self.endPos - self.startPos) * easeOutReel(u)
	self:layout(pos, nil)

	local idx = math.floor(pos + 0.5)
	if idx ~= self.lastIdx then
		self.lastIdx = idx
		local card = self.cards[idx]
		if card then
			self.root:SetAttribute("CenterId", card.info.id)
		end
		local clock = os.clock()
		if clock - self.lastTick > 0.045 then
			self.lastTick = clock
			Sfx.play("tick", 0.9 + (1 - u) * 0.4)
			self.selectorScale.Scale = 1.06
		end
	end
	-- selector relaxes back after each tick bump
	self.selectorScale.Scale += (1 - self.selectorScale.Scale) * 0.25
	if u >= 1 then
		self:layout(self.endPos, 0)
		self:land()
	end
end

---------------------------------------------------------------------------------------------------
-- Controller: reacts to GameState
---------------------------------------------------------------------------------------------------
local KINDS = {
	minigame = {
		phase = Phase.Roulette,
		reel = "RouletteReel",
		target = "MinigameId",
		folder = "MinigameInfo",
		lookup = Data.minigame,
		duration = Config.ROULETTE_TIME,
	},
	modifier = {
		phase = Phase.ModifierRoulette,
		reel = "ModifierReel",
		target = "ModifierId",
		folder = "ModifierInfo",
		lookup = Data.modifier,
		duration = Config.MODIFIER_ROULETTE_TIME,
	},
}

local function buildItems(kind: string): ({ Data.CardInfo }, string)
	local def = KINDS[kind]
	local ids = Data.csv(GameState.read(def.reel))
	local target = GameState.read(def.target)
	if #ids == 0 then
		ids = Data.knownIds(def.folder)
	end
	if typeof(target) == "string" and target ~= "" and ids[#ids] ~= target then
		table.insert(ids, target)
	end
	if #ids == 0 then
		ids = { "Mystery" }
	end
	-- repeat short reels (keeping the target last) so there is always a proper spin
	local cycle = table.clone(ids)
	while #ids < MIN_REEL do
		for i = #cycle, 1, -1 do
			table.insert(ids, 1, cycle[i])
		end
	end
	local items = {}
	for i, id in ids do
		items[i] = def.lookup(id)
	end
	return items, table.concat(ids, ",")
end

function Roulette.start(gui: ScreenGui)
	local views = {
		minigame = View.new(gui, {
			kind = "minigame",
			name = "Roulette",
			title = "PICKING A GAME...",
			dimTop = Color3.fromRGB(40, 30, 95),
			dimBottom = Color3.fromRGB(15, 12, 35),
			ray = C.Cyan,
			selector = C.Yellow,
			titleColors = ColorSequence.new(C.White, C.Yellow),
		}),
		modifier = View.new(gui, {
			kind = "modifier",
			name = "ModifierRoulette",
			title = "SPECIAL ROUND!",
			dimTop = Color3.fromRGB(150, 30, 110),
			dimBottom = Color3.fromRGB(45, 10, 60),
			ray = C.Yellow,
			selector = C.Pink,
			badge = ("🪙 %dx COINS"):format(Config.MODIFIER_COIN_MULTIPLIER),
			titleColors = ColorSequence.new({
				ColorSequenceKeypoint.new(0, C.Yellow),
				ColorSequenceKeypoint.new(0.5, C.Pink),
				ColorSequenceKeypoint.new(1, C.Cyan),
			}),
		}),
	}

	local current: { kind: string?, sig: string?, endT: number? } = {}

	local function sync()
		local phase = GameState.read("Phase")
		local kind = nil
		for k, def in KINDS do
			if def.phase == phase then
				kind = k
			end
		end
		for k, view in views do
			if k ~= kind then
				view:hide()
			end
		end
		if not kind then
			current = {}
			return
		end
		local view = views[kind]
		local items, sig = buildItems(kind)
		local now = workspace:GetServerTimeNow()
		local phaseEnd = tonumber(GameState.read("PhaseEnd")) or 0
		local endT = if phaseEnd > now + 0.25 then phaseEnd else nil
		local wasVisible = view.visible
		view:show()
		local restart = not wasVisible
			or current.kind ~= kind
			or current.sig ~= sig
			or (endT ~= nil and current.endT ~= nil and endT > current.endT + 0.75)
		if restart then
			view:spin(items, now, endT or (now + KINDS[kind].duration))
		elseif endT and endT ~= current.endT and not view.landed then
			view:retime(endT)
		end
		current = { kind = kind, sig = sig, endT = endT or current.endT }
	end

	-- Coalesce bursts of attribute writes (Core sets several in the same frame).
	local scheduled = false
	local function schedule()
		if scheduled then
			return
		end
		scheduled = true
		task.defer(function()
			scheduled = false
			sync()
		end)
	end
	for _, key in { "Phase", "PhaseEnd", "RouletteReel", "MinigameId", "ModifierReel", "ModifierId" } do
		GameState.onChanged(key, schedule)
	end
	schedule()
end

return Roulette
