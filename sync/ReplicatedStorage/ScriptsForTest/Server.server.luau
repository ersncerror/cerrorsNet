local net = require(game.ReplicatedStorage.CNet)
local newNet = net.new("hello", net.DataTypes.u8)

local player = game.Players:FindFirstChildOfClass("Player") or game.Players.PlayerAdded:Wait()

task.wait(10)

while task.wait(1) do
	for i = 1, 5 do
		newNet:FireAll(i)
	end
end