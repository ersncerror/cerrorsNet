local net = require(game.ReplicatedStorage.CNet)

local newNet = net.new("hello", net.DataTypes.u8):Unreliable()

local player = game.Players:FindFirstChildOfClass("Player") or game.Players.PlayerAdded:Wait()
local charatcer = player.Character or player.CharacterAppearanceLoaded:Wait()

task.wait(2)

while task.wait() do
	newNet:FireAll(100)
end