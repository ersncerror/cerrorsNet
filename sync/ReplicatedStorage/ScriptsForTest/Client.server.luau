local net = require(game.ReplicatedStorage.CNet)

local newNet = net.new("hello", net.DataTypes.u8):Response()

newNet:OnInvoke(function(n)
	return n / 2
end)

--print( newNet:InvokeServer(10) )