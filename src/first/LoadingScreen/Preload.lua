-- Refreshes the fallback ids from Shared.Assets (when Shared replicates within 3 s) and preloads the loading
-- screen's own art first, then the main UI icons, textures and the first sounds a player hears.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Preload = {}

-- UI sounds of the first minute + the lobby music, so the first click and the first track start without a gap.
local SOUNDS = { "UiClick", "UiOpen", "UiHover", "UiError", "CoinCollect", "Purchase", "MusicLobby1", "MusicLobby2" }

local function loadAssets(): { [string]: any }?
	local shared = ReplicatedStorage:WaitForChild("Shared", 3)
	local module = shared and shared:WaitForChild("Assets", 2)
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local ok, result = pcall(require, module)
	return (ok and typeof(result) == "table") and result or nil
end

local function preloadAsync(list: { any })
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
end

-- Yields. `ids` is updated in place; onIdsChanged() runs when the live ids are known.
function Preload.run(ids: { [string]: string }, onIdsChanged: () -> ())
	local Assets = loadAssets()
	local art, icons, textures, sounds = {}, {}, {}, {}
	if Assets then
		art, icons = Assets.Art or art, Assets.Icons or icons
		textures, sounds = Assets.Textures or textures, Assets.Sounds or sounds
		ids.bg = art.loading_bg or ids.bg
		ids.logo = art.logo or ids.logo
		ids.stripes = textures.stripes_diag or ids.stripes
		ids.bomb = icons.bomb or ids.bomb
		ids.click = sounds.UiClick and sounds.UiClick.id or ids.click
		onIdsChanged()
	end
	preloadAsync({ ids.bg, ids.logo, ids.stripes, ids.bomb })
	if not Assets then
		return
	end

	local list, seen, temp = {}, {}, {}
	for _, group in { art, icons, textures } do
		for _, id in group do
			if typeof(id) == "string" and id ~= "" and not seen[id] then
				seen[id] = true
				table.insert(list, id)
			end
		end
	end
	for _, key in SOUNDS do
		local info = sounds[key]
		if typeof(info) == "table" and typeof(info.id) == "string" then
			local sound = Instance.new("Sound")
			sound.SoundId = info.id
			table.insert(list, sound)
			table.insert(temp, sound)
		end
	end
	preloadAsync(list)
	for _, sound in temp do
		sound:Destroy()
	end
end

return Preload
