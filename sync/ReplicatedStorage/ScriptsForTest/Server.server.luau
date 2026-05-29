local net = require(game.ReplicatedStorage.CNet)
local newNet = net.new("hello", net.DataTypes.u8):Response():WithTimeout(5)

local player = game.Players:FindFirstChildOfClass("Player") or game.Players.PlayerAdded:Wait()

print( newNet:InvokeClient(player, 1) )
print("next")
print( newNet:InvokeClient(player, 1) )
print("balalal")