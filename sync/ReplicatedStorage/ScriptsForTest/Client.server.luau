local net = require(game.ReplicatedStorage.CNet)

local newNet = net.new("hello", net.DataTypes.u8)

local a = newNet:Connect(function(...)
	print(...)
end)

task.wait(20)
print("byebye")
a:Disconnect()