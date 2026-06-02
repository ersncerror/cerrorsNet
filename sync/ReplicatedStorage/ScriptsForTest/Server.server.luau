local net = require(game.ReplicatedStorage.CNet)
local newNet = net.new("hello", net.DataTypes.u8):Response(net.DataTypes.u8)

local player = game.Players:FindFirstChildOfClass("Player") or game.Players.PlayerAdded:Wait()

newNet:OnInvoke(function(player: Player?, ...)
	print(player, ...)
	return 1
end)