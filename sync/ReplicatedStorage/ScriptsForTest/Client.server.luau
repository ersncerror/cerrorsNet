local net = require(game.ReplicatedStorage.CNet)

local newNet = net.new("hello", net.DataTypes.u8):Unreliable()

newNet:Connect(function(number)
	print(number)
end)