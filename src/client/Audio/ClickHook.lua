-- Global click sound (brief #25): every GuiButton under PlayerGui plays "UiClick" when activated, unless it (or its
-- ScreenGui) carries the attribute PD_NoClick = true. UIKit buttons set PD_NoClick because they play their own click.
-- Roblox's own mobile controls (jump button, ContextActionService buttons) stay silent: they are gameplay inputs.
local Players = game:GetService("Players")

local ClickHook = {}

local SILENT_GUIS = { TouchGui = true, ContextActionGui = true }
local MIN_GAP = 0.04 -- two buttons firing in the same instant make one click

function ClickHook.start(Audio)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hooked = setmetatable({}, { __mode = "k" }) -- buttons already connected (weak: destroyed ones drop out)
	local lastClick = 0

	local function isSilent(button: GuiButton): boolean
		if button:GetAttribute("PD_NoClick") == true then
			return true
		end
		local layer = button:FindFirstAncestorWhichIsA("LayerCollector")
		return layer ~= nil and (SILENT_GUIS[layer.Name] == true or layer:GetAttribute("PD_NoClick") == true)
	end

	local function hook(inst: Instance)
		if not inst:IsA("GuiButton") or hooked[inst] then
			return
		end
		hooked[inst] = true
		local button = inst :: GuiButton
		button.Activated:Connect(function()
			-- checked on click, so attributes set after the button was parented still count
			if isSilent(button) then
				return
			end
			local now = os.clock()
			if now - lastClick < MIN_GAP then
				return
			end
			lastClick = now
			Audio.ui("UiClick", { pitch = 0.95 + math.random() * 0.1 })
		end)
	end

	playerGui.DescendantAdded:Connect(hook)
	for _, inst in playerGui:GetDescendants() do
		hook(inst)
	end
end

return ClickHook
