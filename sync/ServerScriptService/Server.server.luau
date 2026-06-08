local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8):Response(CNet.uint8)

myNet:OnInvoke(function(player: Player, number: number)
	return number
end)
