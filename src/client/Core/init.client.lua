-- Party Dash Core (client): knockback on our own character (Shared.Knockback: tumble, hit sound, camera shake,
-- smooth recovery), hit juice on every character (HitFx) and the Core_Fx effects (splash, poof, boom, ko).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knockback = require(ReplicatedStorage:WaitForChild("Shared").Knockback)

Knockback.startClient()
require(script.HitFx).start()
require(script.Fx).start()
