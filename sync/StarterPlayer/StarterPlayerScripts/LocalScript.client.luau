local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8):Unstable()

local counter = 0

while task.wait() do
	if counter > 255 then
		counter = 0
	end
	
	myNet:FireAll(counter)
	counter += 1
end