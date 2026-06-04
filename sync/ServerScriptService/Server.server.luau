local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8):Response(CNet.uint8)

myNet:OnInvoke(function(...)
	print(...)
	return 2
end)