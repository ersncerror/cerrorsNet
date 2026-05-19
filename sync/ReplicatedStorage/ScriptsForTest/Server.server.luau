local net = require(game.ReplicatedStorage.CNet)

local newNet = net.new("hello", net.DataTypes.u8):Response(net.DataTypes.u8)

local player = game.Players:FindFirstChildOfClass("Player") or game.Players.PlayerAdded:Wait()
local charatcer = player.Character or player.CharacterAppearanceLoaded:Wait()

newNet.OnInvoke = function(player, number)
	return number / 2, true ,true
end