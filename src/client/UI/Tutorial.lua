-- Party Dash onboarding: three friendly hint bubbles (DASH, SLIDE, JUMP) shown until the player has
-- performed each action once, then the server is told via remote "UI_TutorialDone" and sets the
-- Player attribute Seen_Tutorial = true. Hints fade (but keep running) under full-screen overlays.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Kit)
local Sfx = require(script.Parent.Sfx)

local C = Theme.Colors
local Phase = GameState.Phase
local localPlayer = Players.LocalPlayer

local Tutorial = {}

type Step = {
	action: string,
	cap: string,
	pc: string,
	touch: string,
	keys: { Enum.KeyCode },
	attr: string?,
	jump: boolean?,
}

local STEPS: { Step } = {
	{
		action = "Dash",
		cap = "SHIFT",
		pc = "Press SHIFT to DASH",
		touch = "Tap DASH",
		keys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
		attr = "Dashing",
	},
	{
		action = "Slide",
		cap = "C",
		pc = "Press C to SLIDE",
		touch = "Tap SLIDE",
		keys = { Enum.KeyCode.C, Enum.KeyCode.LeftControl },
		attr = "Sliding",
	},
	{
		action = "Jump",
		cap = "SPACE",
		pc = "Press SPACE to JUMP",
		touch = "Tap JUMP",
		keys = { Enum.KeyCode.Space },
		jump = true,
	},
}

-- Hints fade out while one of these full-screen moments is on screen.
local OVERLAY_PHASES = {
	[Phase.Roulette] = true,
	[Phase.ModifierRoulette] = true,
	[Phase.Intro] = true,
	[Phase.End] = true,
}

function Tutorial.start(gui: ScreenGui)
	local root = Kit.box({
		Name = "Tutorial",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.82),
		Size = UDim2.fromScale(0.5, 0.2),
		Visible = false,
		ZIndex = 8,
		Parent = gui,
	})
	Kit.aspect(3.6).Parent = root
	Kit.sizeLimit(560, 156).Parent = root

	-- CanvasGroup so the whole bubble can fade as one; children are inset so strokes are not clipped.
	local group = Kit.new("CanvasGroup", {
		Name = "Group",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0,
		ZIndex = 8,
		Parent = root,
	})
	local holder = Kit.box({ Name = "Holder", ZIndex = 8, Parent = group })
	local holderScale = Kit.scaler(holder, 0)

	local tail = Kit.panel(C.White, {
		Name = "Tail",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.fromScale(0.16, 0.16),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Rotation = 45,
		ZIndex = 8,
		Parent = holder,
	}, UDim.new(0.15, 0), 3.5)

	local bubble = Kit.panel(C.White, {
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		Size = UDim2.fromScale(0.94, 0.64),
		ZIndex = 9,
		Parent = holder,
	}, UDim.new(0.3, 0), 3.5)
	local bubbleScale = Kit.scaler(bubble)

	local cap = Kit.panel(C.Yellow, {
		Name = "KeyCap",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, 0.5),
		Size = UDim2.fromScale(0.27, 0.7),
		ZIndex = 10,
		Parent = bubble,
	}, UDim.new(0.3, 0), 3)
	Kit.gradient(C.Yellow, C.Orange).Parent = cap
	local capScale = Kit.scaler(cap)
	local capText = Kit.label("SHIFT", {
		Name = "KeyText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.72),
		ZIndex = 11,
		Parent = cap,
	}, { maxText = 40, stroke = 2.5 })

	local hint = Kit.label("", {
		Name = "HintText",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.35, 0.5),
		Size = UDim2.fromScale(0.61, 0.62),
		TextColor3 = C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
		Parent = bubble,
	}, { maxText = 40, stroke = 0 })

	local counter = Kit.panel(C.Purple, {
		Name = "Counter",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.14),
		Size = UDim2.fromScale(0.13, 0.2),
		ZIndex = 12,
		Parent = holder,
	}, UDim.new(0.5, 0), 2.5)
	local counterText = Kit.label("1/3", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.76),
		ZIndex = 13,
		Parent = counter,
	}, { maxText = 24, stroke = 1.5 })

	-- State ---------------------------------------------------------------------------------------
	local running = false
	local stepIndex = 0
	local accepting = false -- false while a step's "NICE!" celebration plays
	local bobConn: RBXScriptConnection? = nil

	local function setBubbleColor(color: Color3)
		bubble.BackgroundColor3 = color
		tail.BackgroundColor3 = color
	end

	local function showStep(i: number)
		local step = STEPS[i]
		stepIndex = i
		local touch = Data.isTouch()
		hint.Text = touch and step.touch or step.pc
		capText.Text = touch and step.action:upper() or step.cap
		hint.TextColor3 = C.Ink
		setBubbleColor(C.White)
		counterText.Text = ("%d/%d"):format(i, #STEPS)
		root:SetAttribute("Step", step.action)
		Kit.popIn(holderScale, 0.45)
		Sfx.play("pop", 1.3)
		accepting = true
	end

	local function finish()
		running = false
		root:SetAttribute("Step", "Done")
		hint.Text = "YOU'RE READY! 🎉"
		capText.Text = "★"
		task.delay(1.4, function()
			Kit.popOut(holderScale, 0.3).Completed:Connect(function()
				if not running then
					root.Visible = false
					if bobConn then
						bobConn:Disconnect()
						bobConn = nil
					end
				end
			end)
		end)
		task.spawn(function()
			local ok, remote = pcall(Net.event, "UI_TutorialDone")
			if ok and remote then
				remote:FireServer()
			end
		end)
	end

	local function complete(action: string)
		if not running or not accepting then
			return
		end
		local step = STEPS[stepIndex]
		if not step or step.action ~= action then
			return
		end
		accepting = false
		setBubbleColor(C.Green)
		hint.TextColor3 = C.White
		hint.Text = "NICE!"
		capText.Text = "✓"
		Kit.punch(bubbleScale, 0.18)
		Kit.punch(capScale, 0.3)
		Sfx.play("pop", 1.8)
		local nextIndex = stepIndex + 1
		task.delay(0.7, function()
			if not running then
				return
			end
			if nextIndex > #STEPS then
				finish()
				return
			end
			Kit.popOut(holderScale, 0.2).Completed:Connect(function()
				if running then
					task.wait(0.15)
					showStep(nextIndex)
				end
			end)
		end)
	end

	local function begin()
		if running or localPlayer:GetAttribute("Seen_Tutorial") == true then
			return
		end
		running = true
		root.Visible = true
		group.GroupTransparency = OVERLAY_PHASES[GameState.read("Phase")] and 1 or 0
		if not bobConn then
			local t0 = os.clock()
			bobConn = RunService.RenderStepped:Connect(function()
				local t = os.clock() - t0
				holder.Position = UDim2.fromScale(0, math.sin(t * 3) * 0.04)
				cap.Rotation = math.sin(t * 5) * 4
			end)
		end
		showStep(1)
	end

	local function abort()
		if not running then
			return
		end
		running = false
		root:SetAttribute("Step", "Done")
		Kit.popOut(holderScale, 0.25).Completed:Connect(function()
			if not running then
				root.Visible = false
				if bobConn then
					bobConn:Disconnect()
					bobConn = nil
				end
			end
		end)
	end

	-- Inputs ----------------------------------------------------------------------------------------
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if not running or UserInputService:GetFocusedTextBox() then
			return
		end
		for _, step in STEPS do
			if table.find(step.keys, input.KeyCode) then
				complete(step.action)
			end
		end
	end)

	-- Touch players press on-screen buttons: watch the replicated movement state instead.
	local function hookCharacter(character: Model)
		for _, step in STEPS do
			local attr = step.attr
			if attr then
				character:GetAttributeChangedSignal(attr):Connect(function()
					if character:GetAttribute(attr) == true then
						complete(step.action)
					end
				end)
			end
		end
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.StateChanged:Connect(function(_, new)
				if new == Enum.HumanoidStateType.Jumping then
					complete("Jump")
				end
			end)
		end
	end
	if localPlayer.Character then
		task.spawn(hookCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(hookCharacter)

	GameState.onChanged("Phase", function(phase)
		if running then
			Kit.tween(group, 0.3, { GroupTransparency = OVERLAY_PHASES[phase] and 1 or 0 })
		end
	end)

	localPlayer:GetAttributeChangedSignal("Seen_Tutorial"):Connect(function()
		if localPlayer:GetAttribute("Seen_Tutorial") == true then
			abort()
		else
			-- reset (e.g. by a tester or a data wipe): run the hints again
			task.delay(0.5, begin)
		end
	end)

	-- Give persistence a moment to load Seen_Tutorial before greeting a "new" player.
	task.delay(1.5, begin)
end

return Tutorial
