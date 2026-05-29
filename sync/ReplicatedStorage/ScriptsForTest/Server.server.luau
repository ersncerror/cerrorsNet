local net = require(game.ReplicatedStorage.CNet)
local newNet = net.new("hello", net.DataTypes.u8)

local player = game.Players:FindFirstChildOfClass("Player") or game.Players.PlayerAdded:Wait()

while task.wait(1) do
	print("hello")
	newNet:Fire(player, 1)
end