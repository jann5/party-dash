-- Party Dash Audio (client; brief #23 / #25): background music by context, the global button click hook and the
-- reward cues (coins, level up). Every sound goes through Shared.Audio, which applies the Set_Music / Set_SFX mutes
-- to its SoundGroups (requiring it here is also what hooks those settings up on this client).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))

require(script.ClickHook).start(Audio)
require(script.Cues).start(Audio)
require(script.Music).start(Audio)
