local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.Instance, CNet.uint8):Response(CNet.uint8)

myNet:OnInvoke(function(inst, number)
	return number + 1
end)
