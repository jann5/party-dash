--[[
Party Dash ActionButton (client only): the mobile action pad around Roblox's jump button.

	local ActionButton = require(ReplicatedStorage.Shared.Movement.ActionButton)
	local unbind = ActionButton.bind("Swing", { icon = "action_swing", label = "Swing" }, function()
		-- the player tapped the minigame's main action
	end)
	unbind() -- removes it again (an earlier binding, if any, comes back)

Slots (touch devices only; on PC the pad exists but stays hidden):
	Dash    above the jump button        (Movement: bottom-up cooldown fill inside the button)
	Slide   left of the jump button      (Movement: 45% opacity while it cools down, pops when ready)
	Primary left of Dash                 (minigames, through ActionButton.bind; one binding shown at a time, last wins)
Buttons are big dark circles (Ink at 0.35) with a white icon and an ink outline, like the stock jump button:
>= 84 px on phones, x1.15 on tablets, laid out from the real JumpButton rect so they never overlap each other or
the jump button. A press squashes to 0.9 and clicks. `icon` is a Shared.Assets icon key or an rbxassetid string.
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Theme = require(ReplicatedStorage.Shared.Theme)

local ActionButton = {}

export type Rect = { position: Vector2, size: Vector2 }
export type SlotApi = {
	setProgress: (progress: number) -> (), -- 0..1 recharge (bottom-up fill); 1 = ready
	setCooling: (cooling: boolean) -> (), -- dims to 45% opacity while true
	pop: () -> (), -- ready pop 1.15 -> 1
	isShown: () -> boolean,
}

local GUI_NAME = "PD_ActionPad"
local PHONE_SIZE = 84 -- px on phones
local TABLET_SCALE = 1.15
local MIN_GAP = 10
local DISC_TRANSPARENCY = 0.35
local COOLING_TRANSPARENCY = 0.55 -- 45% opacity
local MOVE_ICONS = { Dash = "action_dash", Slide = "action_slide" }
local SLOT_NAMES = { "Dash", "Slide", "Primary" }

local IS_CLIENT = RunService:IsClient()
local Ink = Theme.Colors.Ink
local White = Theme.Colors.White

type Refs = {
	frame: Frame,
	press: UIScale,
	disc: CanvasGroup,
	shade: Frame,
	ring: UIStroke,
	gleam: UIStroke,
	callback: (() -> ())?,
	cooling: boolean,
	progress: number,
}
type Binding = { id: string, icon: string, label: string?, callback: () -> () }

local UIKit: any = nil -- required lazily (client only)
local gui: ScreenGui? = nil
local root: Frame? = nil
local slots: { [string]: Refs } = {}
local bindings: { Binding } = {}
local started = false
local layoutQueued = false
local touchConnections: { RBXScriptConnection } = {}

local function kit()
	if not UIKit then
		UIKit = require(ReplicatedStorage.Shared.UIKit)
	end
	return UIKit
end

local function resolveIcon(icon: string): string
	if string.find(icon, "^rbxasset") or string.find(icon, "^http") then
		return icon
	end
	return Assets.icon(icon)
end

-- Touch controls are what the player is using right now.
local function touchMode(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return true
	end
	local name = last.Name
	if
		last == Enum.UserInputType.Keyboard
		or string.sub(name, 1, 5) == "Mouse"
		or string.sub(name, 1, 7) == "Gamepad"
	then
		return false
	end
	return not UserInputService.KeyboardEnabled
end

local function playerGui(): PlayerGui?
	return Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function touchGui(): ScreenGui?
	local pg = playerGui()
	local g = pg and pg:FindFirstChild("TouchGui")
	return if g and g:IsA("ScreenGui") then g else nil
end

local function viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- AbsolutePosition of a ScreenGui that does not ignore the GUI inset starts below the top bar.
local function toScreen(screen: ScreenGui, p: Vector2): Vector2
	if screen.IgnoreGuiInset then
		return p
	end
	local inset = GuiService:GetGuiInset()
	return p + inset
end

-- Screen-space rect of Roblox's jump button (or where the stock TouchJump puts it).
local function jumpRect(): Rect
	local tg = touchGui()
	local jump = tg and tg:FindFirstChild("JumpButton", true)
	if tg and jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 4 then
		return { position = toScreen(tg, jump.AbsolutePosition), size = jump.AbsoluteSize }
	end
	local insetTopLeft, insetBottomRight = GuiService:GetGuiInset()
	local area = viewport() - insetTopLeft - insetBottomRight
	local small = math.min(area.X, area.Y) <= 500
	local size = if small then 70 else 120
	local y = if small then area.Y - size - 20 else area.Y - size * 1.75
	return { position = Vector2.new(area.X - (size * 1.5 - 10), y) + insetTopLeft, size = Vector2.new(size, size) }
end

local function rectOf(center: Vector2, size: number): Rect
	return { position = center - Vector2.new(size, size) / 2, size = Vector2.new(size, size) }
end

local function overlaps(a: Rect, b: Rect, gap: number): boolean
	return a.position.X < b.position.X + b.size.X + gap
		and b.position.X < a.position.X + a.size.X + gap
		and a.position.Y < b.position.Y + b.size.Y + gap
		and b.position.Y < a.position.Y + a.size.Y + gap
end

--[[ Pure layout (screen px): Dash right above Jump, Slide left of Jump, Primary left of Dash and lifted until its
square clears Slide. A final pass pushes any overlapping square further left/up, so no two rects ever intersect. ]]
function ActionButton.computeLayout(jump: Rect, screen: Vector2): { [string]: Rect }
	local phone = math.min(screen.X, screen.Y) <= 500
	local size = if phone then PHONE_SIZE else math.floor(PHONE_SIZE * TABLET_SCALE + 0.5)
	local gap = math.max(MIN_GAP, math.floor(size * 0.12))
	local half = size / 2
	local jumpCenter = jump.position + jump.size / 2
	local jumpHalf = jump.size / 2

	local dash = Vector2.new(jumpCenter.X, jumpCenter.Y - jumpHalf.Y - gap - half)
	-- Slide also keeps a full gap from Dash's left edge (Dash is wider than the phone jump button).
	local slideX = math.min(jumpCenter.X - jumpHalf.X - gap - half, dash.X - half - gap - half)
	local slide = Vector2.new(slideX, jumpCenter.Y)
	local primary = Vector2.new(dash.X - size - gap, math.min(dash.Y, slide.Y - size - gap))

	local rects = {
		Jump = jump,
		Dash = rectOf(dash, size),
		Slide = rectOf(slide, size),
		Primary = rectOf(primary, size),
	}
	-- Safety pass: the construction above already leaves `gap` between all squares; this only fires on odd
	-- jump-button shapes, and it moves the offending square fully clear (Slide further left, others further up).
	local order = { "Dash", "Slide", "Primary" }
	for index, name in order do
		for _ = 1, 8 do
			local hit: Rect? = nil
			if overlaps(rects[name], rects.Jump, 0) then
				hit = rects.Jump
			end
			for j = 1, index - 1 do
				if not hit and overlaps(rects[name], rects[order[j]], 0) then
					hit = rects[order[j]]
				end
			end
			if not hit then
				break
			end
			local r = rects[name]
			if name == "Slide" then
				r.position = Vector2.new(hit.position.X - gap - r.size.X, r.position.Y)
			else
				r.position = Vector2.new(r.position.X, hit.position.Y - gap - r.size.Y)
			end
		end
	end
	return rects
end

local function shouldShow(): boolean
	if not touchMode() then
		return false
	end
	local player = Players.LocalPlayer
	if player:GetAttribute("Spectating") == true then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local tg = touchGui()
	return tg == nil or tg.Enabled
end

local function ensureGui(): (ScreenGui, Frame)
	if gui and gui.Parent and root and root.Parent == gui then
		return gui, root
	end
	local newGui, newRoot = kit().screen(GUI_NAME, "Round")
	gui, root = newGui, newRoot
	return newGui, newRoot
end

local function layoutNow()
	layoutQueued = false
	local g, r = ensureGui()
	local show = shouldShow()
	g.Enabled = show
	local scale = 1
	local uiScale = r:FindFirstChildOfClass("UIScale")
	if uiScale and uiScale.Scale > 0 then
		scale = uiScale.Scale
	end
	local rects = ActionButton.computeLayout(jumpRect(), viewport())
	local origin = r.AbsolutePosition
	for _, name in SLOT_NAMES do
		local frame = r:FindFirstChild(name)
		local rect = rects[name]
		if frame and frame:IsA("GuiObject") and rect then
			local center = rect.position + rect.size / 2
			frame.Size = UDim2.fromOffset(rect.size.X / scale, rect.size.Y / scale)
			frame.Position = UDim2.fromOffset((center.X - origin.X) / scale, (center.Y - origin.Y) / scale)
		end
	end
end

local function queueLayout()
	if layoutQueued then
		return
	end
	layoutQueued = true
	task.defer(layoutNow)
end

local function hookTouchGui()
	for _, c in touchConnections do
		c:Disconnect()
	end
	table.clear(touchConnections)
	local tg = touchGui()
	if not tg then
		return
	end
	table.insert(touchConnections, tg:GetPropertyChangedSignal("Enabled"):Connect(queueLayout))
	table.insert(
		touchConnections,
		tg.DescendantAdded:Connect(function(descendant)
			if descendant.Name == "JumpButton" then
				task.defer(hookTouchGui) -- the jump button appeared after the TouchGui: follow its rect too
			end
			queueLayout()
		end)
	)
	local jump = tg:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") then
		table.insert(touchConnections, jump:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueLayout))
		table.insert(touchConnections, jump:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout))
	end
end

local function watchCharacter(character: Model?)
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(queueLayout)
	end
	queueLayout()
end

local function ensureStarted()
	assert(IS_CLIENT, "ActionButton is client-only")
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	local pg = player:WaitForChild("PlayerGui")
	ensureGui()
	pg.ChildAdded:Connect(function(child)
		if child.Name == "TouchGui" then
			task.defer(hookTouchGui)
			queueLayout()
		end
	end)
	pg.ChildRemoved:Connect(function(child)
		if child.Name == "TouchGui" then
			queueLayout()
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(queueLayout)
	player:GetAttributeChangedSignal("Spectating"):Connect(queueLayout)
	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(queueLayout)
	task.spawn(watchCharacter, player.Character)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(queueLayout)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(queueLayout)
		end
		queueLayout()
	end)
	hookTouchGui()
	queueLayout()
end

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	kit().tween(inst, t, props, style or Enum.EasingStyle.Quad)
end

local function applyCooling(refs: Refs, cooling: boolean, animate: boolean)
	refs.cooling = cooling
	local group = if cooling then COOLING_TRANSPARENCY else 0
	local ring = if cooling then COOLING_TRANSPARENCY else 0
	local gleam = if cooling then 0.85 else 0.55
	if animate then
		tween(refs.disc, 0.08, { GroupTransparency = group })
		tween(refs.ring, 0.08, { Transparency = ring })
		tween(refs.gleam, 0.08, { Transparency = gleam })
	else
		refs.disc.GroupTransparency = group
		refs.ring.Transparency = ring
		refs.gleam.Transparency = gleam
	end
end

local function buildSlot(name: string, icon: string, label: string?): Refs
	local _, r = ensureGui()
	local old = r:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local K = kit()
	local frame = K.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(PHONE_SIZE, PHONE_SIZE),
		ZIndex = 1,
		Parent = r,
	})
	local press = K.new("UIScale", { Name = "Press", Parent = frame })
	local disc = K.new("CanvasGroup", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -6, 1, -6),
		BackgroundColor3 = Ink,
		BackgroundTransparency = DISC_TRANSPARENCY,
		ZIndex = 2,
		Parent = frame,
	})
	K.corner(disc, UDim.new(0.5, 0))
	K.new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = resolveIcon(icon),
		ImageColor3 = White,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if label then 0.43 else 0.5),
		Size = UDim2.fromScale(if label then 0.56 else 0.64, if label then 0.56 else 0.64),
		ZIndex = 3,
		Parent = disc,
	})
	-- Recharge shade: covers the part that is still charging, so the icon fills back in from the bottom up.
	local shade = K.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = Ink,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		Visible = false,
		ZIndex = 4,
		Parent = disc,
	})
	if label then
		local caption = K.text(disc, {
			name = "Caption",
			text = label,
			size = 18,
			stroke = 2,
			frameSize = UDim2.fromScale(0.86, 0.24),
			position = UDim2.fromScale(0.5, 0.8),
			anchor = Vector2.new(0.5, 0.5),
			zindex = 5,
		})
		caption.TextScaled = true
	end
	local ringFrame = K.new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -6, 1, -6),
		ZIndex = 6,
		Parent = frame,
	})
	K.corner(ringFrame, UDim.new(0.5, 0))
	local ring = K.border(ringFrame, 3, Ink)
	local gleamFrame = K.new("Frame", {
		Name = "Gleam",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -16, 1, -16),
		ZIndex = 6,
		Parent = frame,
	})
	K.corner(gleamFrame, UDim.new(0.5, 0))
	local gleam = K.border(gleamFrame, 2, White, 0.55)
	local hit = K.new("TextButton", {
		Name = "Hit",
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = frame,
	})
	hit:SetAttribute("PD_NoClick", true) -- we click ourselves (quietly) on press, not on release

	local refs: Refs = {
		frame = frame,
		press = press,
		disc = disc,
		shade = shade,
		ring = ring,
		gleam = gleam,
		callback = nil,
		cooling = false,
		progress = 1,
	}
	hit.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
			return
		end
		tween(press, 0.06, { Scale = 0.9 })
		K.sound("UiClick", { volume = 0.3, pitch = 0.95 + math.random() * 0.1 })
		local callback = refs.callback
		if callback then
			task.spawn(callback)
		end
	end)
	hit.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			tween(press, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	slots[name] = refs
	frame.Destroying:Connect(function()
		if slots[name] == refs then
			slots[name] = nil
		end
	end)
	queueLayout()
	return refs
end

local function showPrimary()
	local top = bindings[#bindings]
	local existing = slots.Primary
	if not top then
		if existing then
			existing.frame:Destroy()
		end
		local _, r = ensureGui()
		local stray = r:FindFirstChild("Primary")
		if stray then
			stray:Destroy()
		end
		return
	end
	local refs = buildSlot("Primary", top.icon, top.label)
	refs.callback = top.callback
	refs.press.Scale = 0.6
	tween(refs.press, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

--[[ Shows the primary action button (touch only) with `opts.icon` (+ optional short `opts.label`) and calls
`callback` on every press. Only one primary binding is visible at a time (the latest); the returned unbind()
removes this binding and restores the previous one (or removes the button). ]]
function ActionButton.bind(id: string, opts: { icon: string, label: string? }, callback: () -> ()): () -> ()
	assert(type(id) == "string", "ActionButton.bind: id must be a string")
	assert(type(callback) == "function", "ActionButton.bind: callback must be a function")
	ensureStarted()
	local icon = if type(opts) == "table" and type(opts.icon) == "string" then opts.icon else ""
	local label = if type(opts) == "table"
			and type(opts.label) == "string"
			and opts.label ~= ""
		then opts.label
		else nil
	local binding: Binding = { id = id, icon = icon, label = label, callback = callback }
	table.insert(bindings, binding)
	showPrimary()
	local done = false
	return function()
		if done then
			return
		end
		done = true
		local index = table.find(bindings, binding)
		if index then
			table.remove(bindings, index)
			if index > #bindings then
				showPrimary() -- the visible one went away
			end
		end
	end
end

-- Movement only: creates the Dash / Slide button and returns its feedback API.
function ActionButton.move(kind: string, callback: () -> ()): SlotApi
	assert(MOVE_ICONS[kind], "ActionButton.move: kind must be Dash or Slide")
	ensureStarted()
	local refs = buildSlot(kind, MOVE_ICONS[kind], nil)
	refs.callback = callback
	local api = {}
	function api.setProgress(progress: number)
		local current = slots[kind]
		if not current then
			return
		end
		progress = math.clamp(progress, 0, 1)
		if math.abs(progress - current.progress) < 0.004 and (progress < 1) == current.shade.Visible then
			return
		end
		current.progress = progress
		current.shade.Visible = progress < 1
		current.shade.Size = UDim2.fromScale(1, 1 - progress)
	end
	function api.setCooling(cooling: boolean)
		local current = slots[kind]
		if current and current.cooling ~= cooling then
			applyCooling(current, cooling, true)
		end
	end
	function api.pop()
		local current = slots[kind]
		if current then
			current.press.Scale = 1.15
			tween(current.press, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	function api.isShown(): boolean
		return gui ~= nil and gui.Enabled and slots[kind] ~= nil
	end
	return api
end

-- True while the pad is the active control scheme (touch).
function ActionButton.isTouch(): boolean
	return touchMode()
end

-- Re-runs the layout now (normally event driven: viewport, TouchGui, input type, death, spectating).
function ActionButton.layout()
	if IS_CLIENT then
		ensureStarted()
		layoutNow()
	end
end

-- Screen-space rects (px, top-left + size) the pad buttons that exist are laid out at, plus the jump button.
-- For tests and for other HUD that has to stay clear of the pad. The buttons' AbsolutePosition matches these
-- while the pad is shown (and the press squash is not active).
function ActionButton.rects(): { [string]: Rect }
	if not IS_CLIENT then
		return {}
	end
	local jump = jumpRect()
	local layout = ActionButton.computeLayout(jump, viewport())
	local out = { Jump = jump }
	local pg = playerGui()
	local g = pg and pg:FindFirstChild(GUI_NAME)
	local r = g and g:FindFirstChild("Root")
	for _, name in SLOT_NAMES do
		if r and r:FindFirstChild(name) then
			out[name] = layout[name]
		end
	end
	return out
end

return ActionButton
