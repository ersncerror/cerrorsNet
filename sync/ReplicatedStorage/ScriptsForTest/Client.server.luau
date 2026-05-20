local net = require(game.ReplicatedStorage.CNet)
local Schema = require(game.ReplicatedStorage.CNet.Schema)

local newSchema = Schema.new({
	Hello = net.DataTypes.u8,
	World = net.DataTypes.u8
})

local newNet = net.new("hello", newSchema)

newNet:Connect(function(t)
	print(t)
end)