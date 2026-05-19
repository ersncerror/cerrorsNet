local net = require(game.ReplicatedStorage.CNet)

local newNet = net.new("hello", net.DataTypes.u8)

local player = game.Players:FindFirstChildOfClass("Player") or game.Players.PlayerAdded:Wait()
local charatcer = player.Character or player.CharacterAppearanceLoaded:Wait()

while task.wait(1) do
	newNet:FireAll(10)
end