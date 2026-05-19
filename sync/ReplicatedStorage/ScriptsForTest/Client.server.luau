local net = require(game.ReplicatedStorage.CNet)

local newNet = net.new("hello", net.DataTypes.u8)

newNet:Wait()