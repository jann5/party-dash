-- King of the Hill (client): bat input while a King of the Hill bat is held.
--   * mouse click / screen tap: the Tool's own activation (the server listens to Tool.Activated); we also
--     ping "KingOfTheHill_Swing" as a fallback. The server cooldown dedupes, so a click is one swing.
--   * touch: a big SWING button left of the jump button (never overlapping Dash / Slide)
--   * hides the default backpack hotbar so the bat cannot be put away by a number key
--   * "KingOfTheHill_Fx" ("hit", count) from the server: hit-confirm pop + sound
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)
local Ui = require(script.Parent.Ui)

local Input = {}

local ACTION = "KingOfTheHill_Swing"
local REMOTE_SWING = "KingOfTheHill_Swing"
local REMOTE_FX = "KingOfTheHill_Fx"

local localPlayer = Players.LocalPlayer
local C = Theme.Colors

type HudLike = {
	predictSwing: (any, number) -> (),
	progress: (any, number) -> number,
	hit: (any, number) -> (),
}

local hud: HudLike? = nil
local bat: Tool? = nil
local batConn: RBXScriptConnection? = nil
local hidBackpack = false
local fxBound = false
local skin: { button: ImageButton, shade: Frame, scale: UIScale }? = nil
local hitSound: Sound? = nil

local function remote(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild(name)
	return if r and r:IsA("RemoteEvent") then r else nil
end

local function setBackpackHidden(hidden: boolean)
	if hidden == hidBackpack then
		return
	end
	if hidden then
		local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
		if ok and enabled then
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
			hidBackpack = true
		end
	else
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, true)
		hidBackpack = false
	end
end

local function bindFx()
	if fxBound then
		return
	end
	local fx = remote(REMOTE_FX)
	if not fx then
		return
	end
	fxBound = true
	local s = Instance.new("Sound")
	s.Name = "KOTH_HitConfirm"
	s.SoundId = "rbxasset://sounds/action_jump.mp3"
	s.Volume = 0.45
	s.PlaybackSpeed = 2.1
	s.Parent = SoundService
	hitSound = s
	fx.OnClientEvent:Connect(function(kind: any, count: any)
		if kind ~= "hit" or not bat then
			return
		end
		local n = if type(count) == "number" and count == count then math.clamp(math.floor(count), 1, 12) else 1
		if hud then
			hud:hit(n)
		end
		if hitSound then
			pcall(SoundService.PlayLocalSound, SoundService, hitSound)
		end
	end)
end

-- Touch button --------------------------------------------------------------------------------------

local function jumpButtonRect(viewport: Vector2): (Vector2, number)
	local touchGui = localPlayer.PlayerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then
		return jump.AbsolutePosition, jump.AbsoluteSize.X
	end
	local small = math.min(viewport.X, viewport.Y) <= 500
	local size = if small then 70 else 120
	local y = if small then viewport.Y - size - 20 else viewport.Y - size * 1.75
	return Vector2.new(viewport.X - (size * 1.5 - 10), y), size
end

-- SWING sits directly left of the jump button: Dash is above jump and Slide is above-left, so the
-- three never overlap (same sizing rule as the Movement buttons).
local function layoutButton()
	local s = skin
	local camera = workspace.CurrentCamera
	if not s or not s.button.Parent or not camera then
		return
	end
	local jumpPos, jumpSize = jumpButtonRect(camera.ViewportSize)
	local size = math.clamp(jumpSize * 0.86, 58, 104)
	local gap = math.max(8, size * 0.14)
	local jumpCenter = jumpPos + Vector2.new(jumpSize / 2, jumpSize / 2)
	local center = jumpCenter - Vector2.new(jumpSize / 2 + gap + size / 2, 0)
	local parent = s.button.Parent
	local origin = if parent and parent:IsA("GuiBase2d") then parent.AbsolutePosition else Vector2.zero
	s.button.AnchorPoint = Vector2.zero
	s.button.Size = UDim2.fromOffset(size, size)
	s.button.Position =
		UDim2.fromOffset(math.floor(center.X - size / 2 - origin.X), math.floor(center.Y - size / 2 - origin.Y))
end

local function skinButton()
	local button = ContextActionService:GetButton(ACTION)
	if not button then
		return
	end
	if skin and skin.button == button then
		layoutButton()
		return
	end
	ContextActionService:SetTitle(ACTION, "")
	button.ImageTransparency = 1
	button.BackgroundTransparency = 0
	button.BackgroundColor3 = C.Orange
	button.AutoButtonColor = false
	Ui.corner(button, UDim.new(1, 0))
	Ui.stroke(button, 3)
	Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Yellow, C.Orange) }, button)
	local scale = Ui.new("UIScale", {}, button)
	local gloss = Ui.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.7,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.62, 0.26),
		ZIndex = button.ZIndex + 1,
	}, button)
	Ui.corner(gloss, UDim.new(1, 0))
	local clip = Ui.new("CanvasGroup", {
		Name = "Cooldown",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = button.ZIndex + 2,
	}, button)
	Ui.corner(clip, UDim.new(1, 0))
	local shade = Ui.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
	}, clip)
	local title = Ui.label(button, "Title", "SWING", 30)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.52)
	title.Size = UDim2.fromScale(0.84, 0.34)
	title.ZIndex = button.ZIndex + 3
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.88 }):Play()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)
	skin = { button = button, shade = shade, scale = scale }
	layoutButton()
end

local function onSwingAction(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin and bat and bat.Parent == localPlayer.Character then
		bat:Activate()
	end
	return Enum.ContextActionResult.Sink
end

-- Public --------------------------------------------------------------------------------------------

function Input.start(h: HudLike)
	hud = h
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutButton)
	end
end

function Input.bind(tool: Tool)
	Input.unbind()
	bat = tool
	bindFx()
	setBackpackHidden(true)
	batConn = tool.Activated:Connect(function()
		local now = os.clock()
		if hud then
			hud:predictSwing(now)
		end
		local swing = remote(REMOTE_SWING)
		if swing then
			swing:FireServer()
		end
	end)
	if UserInputService.TouchEnabled then
		ContextActionService:BindAction(ACTION, onSwingAction, true, Enum.KeyCode.ButtonR2)
		skinButton()
		-- The touch button can appear a frame late and the jump button moves on rotation: settle it.
		task.delay(0.3, skinButton)
		task.delay(1, skinButton)
	end
end

function Input.unbind()
	if batConn then
		batConn:Disconnect()
		batConn = nil
	end
	if bat then
		bat = nil
		ContextActionService:UnbindAction(ACTION)
		skin = nil
	end
	setBackpackHidden(false)
end

-- Called every frame while bound: keeps the touch button's cooldown shade in sync with the HUD chip.
function Input.update(now: number)
	local s = skin
	if s and hud and s.button.Parent then
		s.shade.Size = UDim2.fromScale(1, 1 - hud:progress(now))
	end
end

return Input
