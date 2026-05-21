local net = require(game.ReplicatedStorage.CNet)
local Schema = require(game.ReplicatedStorage.CNet.Schema)

local newNet = net.new("hello", net.DataTypes.u8)

newNet:Connect(function(t)
	print(t)
end)