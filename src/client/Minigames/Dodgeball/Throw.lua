-- Dodgeball (client): throwing the golden ball.
-- While our character has the attribute HoldingGoldenBall = true:
--   * PC: left mouse click throws (UserInputService.MouseButton1, ignored when the click hit the UI)
--   * mobile: a big gold THROW touch button (ContextActionService action "PartyDash_Throw"),
--     placed left of the jump button so it never overlaps Dash/Slide; gamepad: R2
--   * a "CLICK TO THROW!" / "TAP THROW!" hint, a gold aim arrow on the floor and a gold outline on the
--     player the server's aim assist would lock onto
-- The throw direction is the camera's look direction; the server validates it and adds aim assist.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local Throw = {}

local ACTION = "PartyDash_Throw"
local HOLD_ATTRIBUTE = "HoldingGoldenBall"
local LOCAL_COOLDOWN = 0.3
local GOLD = Color3.fromRGB(255, 208, 64)
local Colors = Theme.Colors
local ASSIST_ANGLE = math.rad(16) -- mirrors the server's aim assist cone
local ASSIST_RANGE = 110

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function stroke(parent: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = Colors.Ink
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function label(parent: Instance, text: string, maxSize: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = Theme.FontFace
	t.Text = text
	t.TextColor3 = Colors.White
	t.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 8
	limit.Parent = t
	local outline = Instance.new("UIStroke")
	outline.Color = Colors.Ink
	outline.Thickness = 2
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Parent = t
	t.Parent = parent
	return t
end

local function isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- The hint pill (hidden until we hold the ball).
local function buildGui(player: Player): (ScreenGui, Frame, TextLabel, UIScale)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DodgeballHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Enabled = false

	local pill = Instance.new("Frame")
	pill.Name = "ThrowHint"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -132)
	pill.Size = UDim2.new(0.26, 0, 0, 44)
	pill.BackgroundColor3 = GOLD
	corner(pill, UDim.new(0.5, 0))
	stroke(pill, 3)
	local size = Instance.new("UISizeConstraint")
	size.MinSize = Vector2.new(210, 40)
	size.MaxSize = Vector2.new(360, 48)
	size.Parent = pill
	local scale = Instance.new("UIScale")
	scale.Parent = pill
	local icon = Instance.new("Frame")
	icon.Name = "Ball"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.Size = UDim2.fromScale(0.7, 0.7)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.BackgroundColor3 = Colors.White
	corner(icon, UDim.new(1, 0))
	stroke(icon, 2)
	icon.Parent = pill
	local text = label(pill, "CLICK TO THROW!", 26)
	text.AnchorPoint = Vector2.new(1, 0.5)
	text.Position = UDim2.new(1, -12, 0.5, 0)
	text.Size = UDim2.new(1, -60, 0.72, 0)
	text.TextColor3 = Colors.White
	pill.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, pill, text, scale
end

-- Gold arrow lying on the floor in front of us, pointing where the ball will go.
local function buildArrow(): Model
	local model = Instance.new("Model")
	model.Name = "PD_DodgeballAim"
	local function piece(name: string, size: Vector3, class: string): BasePart
		local p = Instance.new(class) :: BasePart
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = GOLD
		p.Transparency = 0.25
		p.Parent = model
		return p
	end
	piece("Shaft", Vector3.new(0.9, 0.15, 5), "Part")
	-- Two mirrored wedges laid flat make the triangular arrow head.
	piece("HeadL", Vector3.new(0.15, 1.3, 2.2), "WedgePart")
	piece("HeadR", Vector3.new(0.15, 1.3, 2.2), "WedgePart")
	return model
end

-- Character the server's aim assist would pick (same cone/range), for the lock-on outline.
local function assistTarget(player: Player, from: Vector3, dir: Vector3): Model?
	local best: Model? = nil
	local bestAngle = ASSIST_ANGLE
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if other ~= player and other:GetAttribute("InRound") == true and root and root:IsA("BasePart") then
			local to = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
			local dist = to.Magnitude
			if dist > 3 and dist < ASSIST_RANGE then
				local angle = math.acos(math.clamp(to.Unit:Dot(dir), -1, 1))
				if angle < bestAngle then
					bestAngle = angle
					best = character
				end
			end
		end
	end
	return best
end

local function jumpButtonRect(player: Player, viewport: Vector2): (Vector2, number)
	local touchGui = player.PlayerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then
		return jump.AbsolutePosition, jump.AbsoluteSize.X
	end
	local small = math.min(viewport.X, viewport.Y) <= 500
	local size = if small then 70 else 120
	local y = if small then viewport.Y - size - 20 else viewport.Y - size * 1.75
	return Vector2.new(viewport.X - (size * 1.5 - 10), y), size
end

-- Restyles the stock CAS touch button as a big round gold THROW button left of the jump button.
local function styleTouchButton(player: Player)
	local button = ContextActionService:GetButton(ACTION)
	if not button then
		return
	end
	if not button:FindFirstChild("PartyDashSkin") then
		local marker = Instance.new("Folder")
		marker.Name = "PartyDashSkin"
		marker.Parent = button
		button.ImageTransparency = 1
		button.BackgroundTransparency = 0
		button.BackgroundColor3 = GOLD
		button.AutoButtonColor = false
		corner(button, UDim.new(1, 0))
		stroke(button, 3)
		local gloss = Instance.new("Frame")
		gloss.Name = "Gloss"
		gloss.BackgroundColor3 = Colors.White
		gloss.BackgroundTransparency = 0.65
		gloss.AnchorPoint = Vector2.new(0.5, 0)
		gloss.Position = UDim2.fromScale(0.5, 0.08)
		gloss.Size = UDim2.fromScale(0.62, 0.26)
		gloss.ZIndex = button.ZIndex + 1
		corner(gloss, UDim.new(1, 0))
		gloss.Parent = button
		local title = label(button, "THROW", 28)
		title.Name = "Title"
		title.AnchorPoint = Vector2.new(0.5, 0.5)
		title.Position = UDim2.fromScale(0.5, 0.52)
		title.Size = UDim2.fromScale(0.84, 0.36)
		title.ZIndex = button.ZIndex + 2
		-- Hide the stock title so only ours shows.
		local stock = button:FindFirstChild("ActionTitle")
		if stock and stock:IsA("TextLabel") then
			stock.TextTransparency = 1
		end
	end
	local parent = button.Parent
	local viewport = if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(800, 360)
	local jumpPos, jumpSize = jumpButtonRect(player, viewport)
	local size = math.clamp(jumpSize * 0.86, 58, 104)
	local gap = math.max(8, size * 0.14)
	local jumpCenter = jumpPos + Vector2.new(jumpSize / 2, jumpSize / 2)
	local center = jumpCenter - Vector2.new(jumpSize / 2 + gap + size / 2, 0)
	local origin = if parent and parent:IsA("GuiBase2d") then parent.AbsolutePosition else Vector2.zero
	button.AnchorPoint = Vector2.zero
	button.Size = UDim2.fromOffset(size, size)
	button.Position =
		UDim2.fromOffset(math.floor(center.X - size / 2 - origin.X), math.floor(center.Y - size / 2 - origin.Y))
end

function Throw.start(remote: RemoteEvent, onThrow: (() -> ())?)
	local player = Players.LocalPlayer
	local gui, pill, hintText, pillScale = buildGui(player)
	local arrow = buildArrow()
	local shaft = arrow:FindFirstChild("Shaft") :: BasePart
	local headL = arrow:FindFirstChild("HeadL") :: BasePart
	local headR = arrow:FindFirstChild("HeadR") :: BasePart
	local lockOn = Instance.new("Highlight")
	lockOn.Name = "PD_DodgeballLockOn"
	lockOn.FillColor = GOLD
	lockOn.FillTransparency = 0.7
	lockOn.OutlineColor = GOLD
	lockOn.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	lockOn.Enabled = false
	local aimConn: RBXScriptConnection? = nil
	local holding = false
	local bound = false
	local lastSent = 0
	local pulse: Tween? = nil

	local function throw()
		if not holding or os.clock() - lastSent < LOCAL_COOLDOWN then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		lastSent = os.clock()
		remote:FireServer(camera.CFrame.LookVector)
		if onThrow then
			onThrow()
		end
	end

	local function onAction(_: string, state: Enum.UserInputState, _: InputObject)
		if state == Enum.UserInputState.Begin then
			throw()
		end
		return Enum.ContextActionResult.Sink
	end

	-- Floor arrow along the camera's flat look direction + lock-on outline.
	local function updateAim()
		local camera = workspace.CurrentCamera
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not camera or not root or not root:IsA("BasePart") then
			return
		end
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.1 then
			return
		end
		flat = flat.Unit
		local base = root.Position - Vector3.new(0, 2.85, 0)
		local wobble = 0.4 * math.sin(os.clock() * 8)
		local frame = CFrame.lookAt(base, base + flat)
		shaft.CFrame = frame * CFrame.new(0, 0, -(4.5 + wobble))
		local tip = frame * CFrame.new(0, 0, -(8.1 + wobble))
		headL.CFrame = tip * CFrame.Angles(0, 0, math.pi / 2) * CFrame.new(0, 0.65, 0)
		headR.CFrame = tip * CFrame.Angles(0, 0, -math.pi / 2) * CFrame.new(0, 0.65, 0)
		local target = assistTarget(player, root.Position, flat)
		lockOn.Adornee = target
		lockOn.Enabled = target ~= nil
	end

	local function setHolding(value: boolean)
		if value == holding then
			return
		end
		holding = value
		if value then
			if not bound then
				bound = true
				ContextActionService:BindAction(ACTION, onAction, true, Enum.KeyCode.ButtonR2)
				ContextActionService:SetTitle(ACTION, "THROW")
				task.defer(function()
					if bound then
						pcall(styleTouchButton, player)
					end
				end)
			end
			hintText.Text = if isTouchOnly() then "TAP THROW!" else "CLICK TO THROW!"
			gui.Enabled = true
			arrow.Parent = workspace
			lockOn.Parent = workspace
			if aimConn then
				aimConn:Disconnect()
			end
			aimConn = RunService.RenderStepped:Connect(updateAim)
			pillScale.Scale = 0.3
			TweenService:Create(pillScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
			pulse = TweenService:Create(
				pill,
				TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Rotation = 2.5 }
			)
			pill.Rotation = -2.5
			pulse:Play()
		else
			if bound then
				bound = false
				ContextActionService:UnbindAction(ACTION)
			end
			if pulse then
				pulse:Cancel()
				pulse = nil
			end
			if aimConn then
				aimConn:Disconnect()
				aimConn = nil
			end
			gui.Enabled = false
			arrow.Parent = nil
			lockOn.Enabled = false
			lockOn.Adornee = nil
			lockOn.Parent = nil
		end
	end

	local characterConn: RBXScriptConnection? = nil
	local function watch(character: Model)
		if characterConn then
			characterConn:Disconnect()
		end
		setHolding(character:GetAttribute(HOLD_ATTRIBUTE) == true)
		characterConn = character:GetAttributeChangedSignal(HOLD_ATTRIBUTE):Connect(function()
			setHolding(character:GetAttribute(HOLD_ATTRIBUTE) == true)
		end)
	end
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)
	player.CharacterRemoving:Connect(function()
		setHolding(false)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not holding then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			throw()
		end
	end)

	-- The touch button can be re-created when the screen rotates; keep it styled and placed.
	if UserInputService.TouchEnabled then
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				if bound then
					task.defer(function()
						pcall(styleTouchButton, player)
					end)
				end
			end)
		end
	end
end

return Throw
