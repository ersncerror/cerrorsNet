local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8)

while task.wait(0.1) do
	myNet:FireAll(1)
end