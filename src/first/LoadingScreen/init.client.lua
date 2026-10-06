-- Party Dash loading screen (brief #24, ART_BIBLE 8.8). Runs from ReplicatedFirst before anything else replicates:
-- key art, a bobbing logo, a striped yellow-orange progress pill with a hopping bomb, a status line and rotating tips.
-- The progress is fake (4.5-5.3 s ease-out) while ContentProvider preloads the main UI icons and sounds. A Skip button
-- appears after 1.5 s. Skip or finish -> 0.4 s fade -> destroyed, then the client-local Player attribute
-- ClientReady = true tells the other systems they may show popups. Once per session (ResetOnSpawn off).
-- Self-contained on purpose: Shared may not exist yet, so styling is local (Kit) and Shared.Assets only refreshes ids.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
if player:GetAttribute("ClientReady") == true then
	return -- already shown this session
end

-- children of a ReplicatedFirst script may arrive a moment after it starts
local Kit = require(script:WaitForChild("Kit"))
local View = require(script:WaitForChild("View"))
local SkipButton = require(script:WaitForChild("SkipButton"))
local Preload = require(script:WaitForChild("Preload"))

-- Fallback ids copied from Shared.Assets (Preload swaps in the live values once Shared replicates).
local IDS = {
	bg = "rbxassetid://103303232216166", -- Assets.Art.loading_bg
	logo = "rbxassetid://111339427078319", -- Assets.Art.logo
	stripes = "rbxassetid://74173592333501", -- Assets.Textures.stripes_diag
	bomb = "rbxassetid://133533231754084", -- Assets.Icons.bomb
	click = "rbxassetid://17208204604", -- Assets.Sounds.UiClick
}

local FAKE_MIN, FAKE_MAX = 4.5, 5.3 -- seconds of fake progress
local SKIP_AFTER = 1.5
local FADE = 0.4
local LOAD_GRACE = 0.8 -- max seconds to wait for game:IsLoaded() once the bar is full
local FAILSAFE = 15 -- never trap the player behind the screen
local TIP_EVERY = 2.6

-- Status line by progress (the last one drops the percentage).
local STATUS = {
	{ at = 0, text = "Loading assets..." },
	{ at = 0.3, text = "Loading maps..." },
	{ at = 0.5, text = "Painting lasers red..." },
	{ at = 0.66, text = "Loading sounds..." },
	{ at = 0.8, text = "Lighting the fuses..." },
	{ at = 0.95, text = "Almost ready!", final = true },
}
local TIPS = {
	"Slide under the striped laser!",
	"Pass the bomb before it blows!",
	"Step on the PLAY pad to join!",
	"Dash to dodge danger fast!",
	"Spin the wheel for free every day!",
	"Bonk rivals off the pillars with your bat!",
	"Squeeze through the hole in the wall!",
	"Play rounds in a row for bonus coins!",
}

local view: any = nil -- View.build result, set once the screen exists
local closing = false
local barFull = false
local stepConn: RBXScriptConnection? = nil

local function statusText(p: number): string
	local line = STATUS[1]
	for _, s in STATUS do
		if p >= s.at then
			line = s
		end
	end
	if line.final then
		return line.text
	end
	return ("%s %d%%"):format(line.text, math.floor(p * 100))
end

local function stopStepping()
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local function close()
	if closing then
		return
	end
	closing = true
	stopStepping()
	local v = view
	if not v then
		player:SetAttribute("ClientReady", true)
		return
	end
	Kit.fadeOut(v.gui, FADE)
	Kit.tween(v.logoScale, FADE, { Scale = 1.08 })
	task.delay(FADE + 0.05, function()
		v.gui:Destroy()
		player:SetAttribute("ClientReady", true)
	end)
end

-- Bar reached 100%: the bomb pops, the real game gets a short moment to finish loading, then the screen closes.
local function complete(v)
	if barFull or closing then
		return
	end
	barFull = true
	stopStepping()
	v.fill.Size = UDim2.fromScale(1, 1)
	v.runner.Position = UDim2.fromScale(1, 0.5)
	v.runner.Rotation = 0
	v.status.Text = statusText(1)
	Kit.tween(v.runner, 0.25, { Size = UDim2.fromOffset(104, 104) }, Enum.EasingStyle.Back)
	local deadline = os.clock() + LOAD_GRACE
	task.spawn(function()
		task.wait(0.25) -- let the pop read
		while not closing and not game:IsLoaded() and os.clock() < deadline do
			task.wait(0.05)
		end
		close()
	end)
end

local function run()
	local v = View.build(IDS, player:WaitForChild("PlayerGui"))
	view = v
	local startAt = os.clock()
	local duration = FAKE_MIN + math.random() * (FAKE_MAX - FAKE_MIN)

	-- key art fades in once streamed (or after 2 s regardless)
	local function revealBackground()
		if not closing and v.background.ImageTransparency > 0 then
			Kit.tween(v.background, 0.35, { ImageTransparency = 0 })
		end
	end
	if v.background.IsLoaded then
		v.background.ImageTransparency = 0
	else
		v.background:GetPropertyChangedSignal("IsLoaded"):Connect(function()
			if v.background.IsLoaded then
				revealBackground()
			end
		end)
		task.delay(2, revealBackground)
	end

	-- idle motion: slow zoom on the art, logo pop + bob + sway, scrolling stripes
	Kit.tween(v.backgroundZoom, 9, { Scale = 1.07 }, Enum.EasingStyle.Sine)
	Kit.tween(v.logoScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
	Kit.loop(v.logo, 0.8, { Position = UDim2.new(0.5, 0, View.LOGO_TOP, -10) }, Enum.EasingStyle.Sine, true)
	Kit.loop(v.logo, 1.3, { Rotation = 1.5 }, Enum.EasingStyle.Sine, true)
	Kit.loop(v.stripes, 0.55, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Linear, false)

	stepConn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startAt
		local t = math.clamp(elapsed / duration, 0, 1)
		local p = 1 - (1 - t) ^ 1.7 -- ease-out
		v.fill.Size = UDim2.fromScale(p, 1)
		v.runner.Position = UDim2.new(p, 0, 0.5, -math.abs(math.sin(elapsed * 9)) * 7)
		v.runner.Rotation = math.sin(elapsed * 9) * 9
		local text = statusText(p)
		if v.status.Text ~= text then
			v.status.Text = text
		end
		if t >= 1 then
			complete(v)
		end
	end)

	-- live ids from Shared.Assets (when they differ from the fallbacks) + preloading in the background
	task.spawn(Preload.run, IDS, function()
		if closing then
			return
		end
		local images = {
			[v.background] = IDS.bg,
			[v.logo] = IDS.logo,
			[v.stripes] = IDS.stripes,
			[v.groove] = IDS.stripes,
			[v.runner] = IDS.bomb,
		}
		for inst, id in images do
			if inst.Image ~= id then
				inst.Image = id
			end
		end
	end)

	task.delay(SKIP_AFTER, function()
		if not closing then
			SkipButton.new(v.ui, function()
				return IDS.click
			end, close)
		end
	end)
	task.delay(FAILSAFE, close)

	-- rotating tips with a quick cross-fade
	task.spawn(function()
		local index = math.random(#TIPS)
		local function show(i: number)
			v.tip.Text = '<font color="#FFD326">Tip:</font> ' .. TIPS[i]
		end
		show(index)
		while not closing do
			task.wait(TIP_EVERY)
			if closing then
				break
			end
			index = index % #TIPS + 1
			Kit.tween(v.tip, 0.15, { TextTransparency = 1 })
			Kit.tween(v.tipStroke, 0.15, { Transparency = 1 })
			task.wait(0.16)
			if closing then
				break
			end
			show(index)
			Kit.tween(v.tip, 0.2, { TextTransparency = 0 })
			Kit.tween(v.tipStroke, 0.2, { Transparency = 0 })
		end
	end)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
	-- the loading screen must never block the game: report it and get out of the way
	warn("[LoadingScreen] " .. tostring(err))
	closing = true
	stopStepping()
	if view then
		view.gui:Destroy()
	end
	player:SetAttribute("ClientReady", true)
end
