local net = require(game.ReplicatedStorage.CNet)

local newNet = net.new("hello", net.DataTypes.u8):Response(net.DataTypes.u8)

while task.wait(1) do
	newNet:InvokeServer(1):OnSuccess(function(...)
		print("Success:", ...)
	end):OnTimeout(function()
		warn("Timeout")
	end)
end