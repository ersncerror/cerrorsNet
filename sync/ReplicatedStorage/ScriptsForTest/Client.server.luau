local net = require(game.ReplicatedStorage.CNet)

task.wait(20)

local newNet = net.new("hello", net.DataTypes.u8)

newNet:Connect(function(t)
	print(t)
end)