local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8)

myNet:Connect(function(...)
	print(...)
end)