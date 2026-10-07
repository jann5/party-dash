--!nonstrict
-- First-time hints (Player.Seen_Tutorial): three tiny chips bottom-left, just above the currency stack, never over
-- the centre or the lanes: DASH / SLIDE / JUMP with the action icon and the PC key. A chip turns green when you do
-- the move (key press, the Movement character attributes or the Humanoid jump); after all three the server is told
-- (UI_TutorialDone -> Seen_Tutorial, which Economy persists).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Audio = require(ReplicatedStorage.Shared.Audio)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Info = require(script.Parent.Info)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors

local Tutorial = {}

local STEPS = { "Dash", "Slide", "Jump" }
local KEYS = {
	Dash = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.Q, Enum.KeyCode.ButtonX },
	Slide = { Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB },
	Jump = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA },
}
local CHIP_H = 50
local BOTTOM = 250 -- design px from the bottom: above the UIKit "Bottom" dock (currency stack) and the Action lane

local function waitForFlag(name: string, timeout: number)
	local t0 = os.clock()
	while not State.flag(name) and os.clock() - t0 < timeout do
		task.wait(0.25)
	end
end

local function chip(parent: Instance, action: string, order: number)
	local hint = Info.keyHint(action)
	local f = UIKit.new("Frame", {
		Name = "Hint_" .. action,
		BackgroundColor3 = C.PanelDeep,
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(0, CHIP_H),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		ZIndex = 3,
		Parent = parent,
	})
	UIKit.corner(f, UDim.new(0.5, 0))
	UIKit.border(f, 3)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 14), Parent = f })
	UIKit.list(f, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local icon =
		UIKit.icon(f, hint.icon, { size = UDim2.fromOffset(CHIP_H + 4, CHIP_H + 4), anchor = Vector2.zero, zindex = 5 })
	icon.LayoutOrder = 1
	local label = UIKit.text(f, {
		text = string.upper(hint.verb),
		size = 24,
		frameSize = UDim2.fromOffset(0, CHIP_H - 10),
		autoSize = Enum.AutomaticSize.X,
		zindex = 5,
	})
	label.LayoutOrder = 2
	if not Info.isTouch() then
		Widgets.keycap(f, hint.key, 30, { layoutOrder = 3, zindex = 5 })
	end
	return { frame = f, icon = icon, done = false }
end

local function run()
	-- returning players must never see the hints flash: wait for the save to load (and the loading screen)
	waitForFlag("EconomyLoaded", 12)
	waitForFlag("LoadingDone", 8)
	if State.flag("Seen_Tutorial") then
		return
	end

	local gui, root = UIKit.screen("PD_Tutorial", "HUD")
	local trove = Trove.new()
	trove:add(gui)
	local holder = UIKit.new("Frame", {
		Name = "Hints",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(660, CHIP_H + 10),
		AnchorPoint = Vector2.new(0, 1),
		Parent = root,
	})
	holder:SetAttribute("Step", 0)
	UIKit.list(holder, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

	-- short (phone) screens: the left tile grid reaches down here, so the chips move right of it
	local function place()
		local cam = Workspace.CurrentCamera
		local designH = (cam and cam.ViewportSize.Y or 1080) / UIKit.scale()
		holder.Position = UDim2.new(0, designH < 820 and 262 or 24, 1, -BOTTOM)
	end
	place()
	if Workspace.CurrentCamera then
		trove:connect(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), place)
	end

	local entries = {}
	for i, action in STEPS do
		entries[action] = chip(holder, action, i)
		task.delay(0.12 * i, function()
			if entries[action].frame.Parent then
				UIKit.pop(entries[action].frame, 0.4, 0.3)
			end
		end)
	end

	local finished = false
	local function finish(fade: number)
		if finished then
			return
		end
		finished = true
		task.delay(fade, function()
			Widgets.fadeOut(holder, 0.3)
			task.wait(0.32)
			trove:clean()
		end)
	end

	local remaining = #STEPS
	local function complete(action: string)
		local e = entries[action]
		if finished or not e or e.done then
			return
		end
		e.done = true
		remaining -= 1
		holder:SetAttribute("Step", #STEPS - remaining)
		Widgets.paint(e.frame, C.Green)
		e.icon.Image = Assets.icon("check_badge")
		UIKit.punch(e.frame, 1.25)
		Audio.ui("CoinCollect", { volume = 0.35, pitch = 1.3 })
		if remaining == 0 then
			Remotes.fire("UI_TutorialDone")
			UIKit.toast("Nice moves!", nil, "check_badge")
			finish(0.8)
		end
	end

	trove:connect(UserInputService.InputBegan, function(input)
		if UserInputService:GetFocusedTextBox() then
			return -- typing in chat
		end
		for action, codes in KEYS do
			if table.find(codes, input.KeyCode) then
				complete(action)
			end
		end
	end)

	local charTrove = Trove.new()
	trove:add(charTrove)
	local function watchCharacter(character: Model)
		charTrove:clean()
		charTrove:connect(character:GetAttributeChangedSignal("Dashing"), function()
			if character:GetAttribute("Dashing") == true then
				complete("Dash")
			end
		end)
		charTrove:connect(character:GetAttributeChangedSignal("Sliding"), function()
			if character:GetAttribute("Sliding") == true then
				complete("Slide")
			end
		end)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			charTrove:connect(humanoid.StateChanged, function(_, new)
				if new == Enum.HumanoidStateType.Jumping then
					complete("Jump")
				end
			end)
		end
	end
	local player = Players.LocalPlayer
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	trove:connect(player.CharacterAdded, watchCharacter)

	-- saved progress arriving late, or a Solo run, hides the hints
	trove:connect(player:GetAttributeChangedSignal("Seen_Tutorial"), function()
		if State.flag("Seen_Tutorial") then
			finish(0)
		end
	end)
	local function soloVisibility()
		holder.Visible = not State.flag("InSolo")
	end
	trove:connect(player:GetAttributeChangedSignal("InSolo"), soloVisibility)
	soloVisibility()
end

function Tutorial.start()
	task.spawn(run)
end

return Tutorial
