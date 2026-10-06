-- The small Blue "Skip" button (bottom-right) in the UIKit button style: dark lip, gradient face, inner light rim,
-- gloss and an outlined FredokaOne label; hover grow, press-down, pop-in. Plays its own click (PD_NoClick), because
-- the global click hook in the Audio client piece may not be running yet this early.
local SoundService = game:GetService("SoundService")

local Kit = require(script.Parent.Kit)

local SkipButton = {}

local W, H, LIP = 172, 60, 6
local RADIUS = UDim.new(0.3, 0)

local function playClick(soundId: string)
	local sound = Instance.new("Sound")
	sound.Name = "PD_LoadingClick"
	sound.SoundId = soundId
	sound.Volume = 0.6
	local group = SoundService:FindFirstChild("UI")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end
	sound.Parent = SoundService -- not under the screen: it must outlive the fade
	sound:Play()
	task.delay(3, function()
		sound:Destroy()
	end)
end

-- getClickId is read on press (the id may be refreshed from Shared.Assets meanwhile).
function SkipButton.new(parent: Instance, getClickId: () -> string, onSkip: () -> ()): ImageButton
	local new = Kit.new
	local button = new("ImageButton", {
		Name = "Skip",
		Image = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -44, 1, -50),
		Size = UDim2.fromOffset(W, H + LIP),
		ZIndex = 20,
		Parent = parent,
	})
	button:SetAttribute("PD_NoClick", true)
	local pop = new("UIScale", { Scale = 0.5, Parent = button })

	local lip = new("Frame", {
		Name = "Lip",
		BackgroundColor3 = Kit.BLUE_DARK,
		Position = UDim2.fromOffset(0, LIP),
		Size = UDim2.fromOffset(W, H),
		ZIndex = 20,
		Parent = button,
	})
	Kit.corner(lip, RADIUS)
	Kit.border(lip, 3.5)
	local face = new("Frame", {
		Name = "Face",
		BackgroundColor3 = Kit.WHITE,
		Size = UDim2.fromOffset(W, H),
		ZIndex = 21,
		Parent = button,
	})
	Kit.corner(face, RADIUS)
	Kit.border(face, 3.5)
	Kit.gradient(
		face,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Kit.shade(Kit.BLUE, 0.15)),
			ColorSequenceKeypoint.new(0.5, Kit.BLUE),
			ColorSequenceKeypoint.new(1, Kit.shade(Kit.BLUE, -0.12)),
		}),
		90
	)
	local rim = new("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		ZIndex = 21,
		Parent = face,
	})
	Kit.corner(rim, RADIUS)
	new("UIStroke", {
		Thickness = 2,
		Color = Kit.shade(Kit.BLUE, 0.45),
		Transparency = 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = rim,
	})
	Kit.corner(Kit.gloss(face, 22, 0.55), RADIUS)
	local label = new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		FontFace = Kit.FONT_DISPLAY,
		Text = "Skip",
		TextSize = 32,
		TextColor3 = Kit.WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 23,
		Parent = face,
	})
	Kit.outline(label, 3)

	local function press(down: boolean)
		if down then
			Kit.tween(face, 0.06, { Position = UDim2.fromOffset(0, LIP) })
		else
			Kit.tween(face, 0.14, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
		end
	end
	button.MouseEnter:Connect(function()
		Kit.tween(pop, 0.1, { Scale = 1.05 })
	end)
	button.MouseLeave:Connect(function()
		press(false)
		Kit.tween(pop, 0.1, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		press(true)
	end)
	button.MouseButton1Up:Connect(function()
		press(false)
	end)
	local used = false
	button.Activated:Connect(function()
		if used then
			return
		end
		used = true
		playClick(getClickId())
		onSkip()
	end)

	Kit.tween(pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	return button
end

return SkipButton
