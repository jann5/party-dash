-- King of the Hill (client): the round HUD while you hold a bat.
--   * a status pill above the dash bar ("IN THE ZONE!", "CONTESTED!", "YOU'RE THE KING!", ...)
--   * a round BAT chip on the pill whose dark shade drains while the swing recharges
--   * "+1" pops every time your score crosses a whole point, and a "BONK!" pop when you land a hit
-- The pill sits above the dash bar and glides up out of the way while the onboarding hint bubble
-- (PlayerGui.PartyHUD.Tutorial, owned by the UI piece) is on screen, so the two never overlap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared.GameState)
local Theme = require(Shared.Theme)
local Ui = require(script.Parent.Ui)

local Hud = {}
Hud.__index = Hud

local C = Theme.Colors
local GOLD = Theme.MinigameColors.KingOfTheHill or C.Yellow
local localPlayer = Players.LocalPlayer

local BASE_LIFT = 138 -- pill bottom, in pixels above the screen bottom (clears the dash bar)
local AVOID_GAP = 12 -- extra room kept above another bottom-center widget
local POP_ABOVE_PILL = 58 -- "+1" pops start this far above the pill bottom

type Status = { text: string, top: Color3, bottom: Color3 }

local STATUS: { [string]: Status } = {
	king = { text = "YOU'RE THE KING! +1/s", top = GOLD, bottom = C.Orange },
	kingOut = { text = "KING! BACK TO THE ZONE!", top = C.Orange, bottom = C.Red },
	contested = { text = "CONTESTED! BONK THEM OFF!", top = C.Pink, bottom = C.Purple },
	inside = { text = "IN THE ZONE! +1/s", top = GOLD, bottom = C.Orange },
	outside = { text = "CLIMB TO THE GOLDEN ZONE!", top = C.Purple, bottom = C.Panel },
}

function Hud.new()
	local self = setmetatable({}, Hud)

	local gui = Ui.new("ScreenGui", {
		Name = "KingOfTheHillHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 4,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, localPlayer:WaitForChild("PlayerGui"))

	-- Status pill, centered above the movement dash bar.
	local holder = Ui.new("Frame", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BASE_LIFT),
		Size = UDim2.new(0.34, 0, 0, 46),
		BackgroundTransparency = 1,
	}, gui)
	Ui.new("UISizeConstraint", { MinSize = Vector2.new(250, 40), MaxSize = Vector2.new(460, 56) }, holder)
	local holderScale = Ui.new("UIScale", {}, holder)

	local pill = Ui.new("Frame", {
		Name = "Pill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
	}, holder)
	Ui.corner(pill)
	Ui.stroke(pill, 3)
	local pulseScale = Ui.new("UIScale", {}, pill)
	local gradient = Ui.new("UIGradient", { Rotation = 90 }, pill)
	local text = Ui.label(pill, "Text", "", 30)
	text.AnchorPoint = Vector2.new(0, 0.5)
	text.Position = UDim2.new(0, 52, 0.5, 0)
	text.Size = UDim2.new(1, -64, 0.66, 0)

	-- Bat chip on the pill's left end.
	local chip = Ui.new("CanvasGroup", {
		Name = "BatChip",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -10, 0.5, 0),
		Size = UDim2.fromScale(1.25, 1.25),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = C.Orange,
		ZIndex = 3,
	}, holder)
	Ui.corner(chip)
	Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Yellow, C.Orange) }, chip)
	local shade = Ui.new("Frame", {
		Name = "Shade",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, chip)
	local chipText = Ui.label(chip, "Label", "BAT", 22)
	chipText.AnchorPoint = Vector2.new(0.5, 0.5)
	chipText.Position = UDim2.fromScale(0.5, 0.52)
	chipText.Size = UDim2.fromScale(0.78, 0.42)
	chipText.ZIndex = 5
	-- Outline ring drawn on top (a CanvasGroup cannot carry its own stroke nicely).
	local ring = Ui.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = chip.Position,
		Size = chip.Size,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, holder)
	Ui.corner(ring)
	Ui.stroke(ring, 3)
	local chipScale = Ui.new("UIScale", {}, chip)
	local ringScale = Ui.new("UIScale", {}, ring)

	-- Layer for "+1" / "BONK!" pops.
	local pops = Ui.new("Frame", {
		Name = "Pops",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, gui)

	self.gui = gui
	self.holder = holder
	self.holderScale = holderScale
	self.pulseScale = pulseScale
	self.gradient = gradient
	self.text = text
	self.shade = shade
	self.chipScale = chipScale
	self.ringScale = ringScale
	self.pops = pops
	self.statusKey = ""
	self.bat = nil :: Tool?
	self.map = nil :: Model?
	self.predicted = 0 -- local clock of a predicted swing (instant feedback before the server confirms)
	self.confirmedAt = 0 -- local clock when the server's LastSwing last changed
	self.lastServerSwing = 0
	self.wasReady = true
	self.lastWhole = 0
	self.lift = BASE_LIFT -- current pill lift (eased toward the target every frame)
	self.lastClock = os.clock()

	GameState.onChanged("ScoresJson", function()
		self:_onScores()
	end)
	return self
end

function Hud:show(bat: Tool, map: Model?)
	self.bat = bat
	self.map = map
	self.statusKey = ""
	self.predicted = 0
	self.confirmedAt = 0
	self.lastServerSwing = bat:GetAttribute("LastSwing") or 0
	self.lastWhole = self:_myScoreWhole()
	self.lift = self:_targetLift()
	self.lastClock = os.clock()
	self.holder.Position = UDim2.new(0.5, 0, 1, -math.floor(self.lift + 0.5))
	self.gui.Enabled = true
	self.holderScale.Scale = 0.4
	TweenService:Create(self.holderScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

function Hud:hide()
	self.bat = nil
	self.map = nil
	self.gui.Enabled = false
end

function Hud:_myScoreWhole(): number
	local score = GameState.scores()[tostring(localPlayer.UserId)]
	return if type(score) == "number" then math.floor(score + 1e-6) else 0
end

function Hud:_onScores()
	if not self.bat then
		return
	end
	local whole = self:_myScoreWhole()
	if whole > self.lastWhole then
		local y = -math.floor(self.lift + POP_ABOVE_PILL)
		self:_pop(("+%d"):format(whole - self.lastWhole), GOLD, UDim2.new(0.5, 0, 1, y), 0.9)
	end
	self.lastWhole = whole
end

-- A floating word that pops, rises and fades.
function Hud:_pop(word: string, color: Color3, position: UDim2, life: number)
	local label = Ui.label(self.pops, "Pop", word, 44)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = UDim2.new(0.16, 0, 0, 44)
	label.TextColor3 = color
	label.Rotation = math.random(-10, 10)
	local scale = Ui.new("UIScale", { Scale = 0.3 }, label)
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = position - UDim2.fromOffset(0, 46),
	}):Play()
	task.delay(life * 0.55, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(life * 0.45), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(life * 0.45), { Transparency = 1 }):Play()
			end
		end
	end)
	task.delay(life + 0.05, function()
		label:Destroy()
	end)
end

-- Called by Input when the server confirms we hit someone.
function Hud:hit(count: number)
	local word = if count > 1 then ("BONK x%d!"):format(count) else "BONK!"
	self:_pop(word, C.Yellow, UDim2.fromScale(0.5, 0.42), 0.7)
end

-- Called on a local click so the chip reacts instantly (the server stays the authority).
function Hud:predictSwing(now: number)
	if self:progress(now) >= 1 then
		self.predicted = now
	end
end

function Hud:progress(now: number): number
	local bat = self.bat
	if not bat then
		return 1
	end
	local cooldown = bat:GetAttribute("Cooldown")
	cooldown = if type(cooldown) == "number" and cooldown > 0 then cooldown else 1
	local last = math.max(self.predicted, self.confirmedAt)
	if last <= 0 then
		return 1
	end
	return math.clamp((now - last) / cooldown, 0, 1)
end

function Hud:_status(): string
	local map = self.map
	if not map then
		return "outside"
	end
	local me = tostring(localPlayer.UserId)
	local inZone = false
	local count = 0
	local csv = map:GetAttribute("InZone")
	if type(csv) == "string" and csv ~= "" then
		for id in string.gmatch(csv, "[^,]+") do
			count += 1
			if id == me then
				inZone = true
			end
		end
	end
	local isKing = map:GetAttribute("LeaderId") == localPlayer.UserId
	if inZone and count > 1 then
		return "contested"
	elseif inZone and isKing then
		return "king"
	elseif inZone then
		return "inside"
	elseif isKing then
		return "kingOut"
	end
	return "outside"
end

-- How high the pill must sit so it clears the onboarding bubble (BASE_LIFT when it is hidden).
function Hud:_targetLift(): number
	local partyHud = localPlayer.PlayerGui:FindFirstChild("PartyHUD")
	local tutorial = partyHud and partyHud:FindFirstChild("Tutorial")
	if
		not partyHud
		or not partyHud:IsA("ScreenGui")
		or not partyHud.Enabled
		or not tutorial
		or not tutorial:IsA("GuiObject")
		or not tutorial.Visible
		or tutorial.AbsoluteSize.Y <= 0
	then
		return BASE_LIFT
	end
	-- Distance from the screen bottom to the bubble's top edge. Measured from the bottom so the
	-- different GUI insets of the two ScreenGuis cancel out.
	local top = partyHud.AbsoluteSize.Y - tutorial.AbsolutePosition.Y
	return math.max(BASE_LIFT, top + AVOID_GAP)
end

function Hud:_layout(now: number)
	local dt = math.clamp(now - self.lastClock, 0, 0.1)
	self.lastClock = now
	local target = self:_targetLift()
	local alpha = 1 - math.exp(-12 * dt)
	self.lift += (target - self.lift) * alpha
	if math.abs(target - self.lift) < 0.5 then
		self.lift = target
	end
	self.holder.Position = UDim2.new(0.5, 0, 1, -math.floor(self.lift + 0.5))
end

function Hud:update(now: number)
	local bat = self.bat
	if not bat then
		return
	end
	self:_layout(now)
	-- Server-confirmed swings (LastSwing is server time; we only need "it changed").
	local serverSwing = bat:GetAttribute("LastSwing")
	if type(serverSwing) == "number" and serverSwing ~= self.lastServerSwing then
		self.lastServerSwing = serverSwing
		if now - self.predicted > 0.35 then
			self.confirmedAt = now
		else
			self.confirmedAt = self.predicted
		end
	end

	local progress = self:progress(now)
	self.shade.Size = UDim2.fromScale(1, 1 - progress)
	local ready = progress >= 1
	if ready and not self.wasReady then
		self.chipScale.Scale = 1.25
		self.ringScale.Scale = 1.25
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Back)
		TweenService:Create(self.chipScale, info, { Scale = 1 }):Play()
		TweenService:Create(self.ringScale, info, { Scale = 1 }):Play()
	end
	self.wasReady = ready

	local key = self:_status()
	if key ~= self.statusKey then
		self.statusKey = key
		local s = STATUS[key]
		self.text.Text = s.text
		self.gradient.Color = ColorSequence.new(s.top, s.bottom)
		self.holderScale.Scale = 1.12
		TweenService:Create(self.holderScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	-- Gentle heartbeat while you are scoring.
	if key == "inside" or key == "king" then
		self.pulseScale.Scale = 1 + 0.035 * math.abs(math.sin(now * 4))
	else
		self.pulseScale.Scale = 1
	end
end

return Hud
