local net = require(game.ReplicatedStorage.CNet)
local Schema = require(game.ReplicatedStorage.CNet.Schema)

local newSchema = Schema.new({
	Hello = net.DataTypes.u8,
	World = net.DataTypes.u8,
})

local newNet = net.new("hello", newSchema)

local player = game.Players:FindFirstChildOfClass("Player") or game.Players.PlayerAdded:Wait()

task.wait(20)

for i = 1, 5 do
	newNet:Fire(player, {
		Hello = i,
		World = i * 2
	} )
end
