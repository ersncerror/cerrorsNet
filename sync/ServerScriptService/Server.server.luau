local CNet = require(game:GetService("ReplicatedStorage").CNet)

local struct = CNet.Schema.new({ ["hello"] = CNet.uint8 })

local myNet = CNet.new("MyNet", struct)

myNet:Connect(function(...)
	print(...)
end)