local CNet = require(game:GetService("ReplicatedStorage").CNet)

local struct = CNet.Schema.new({ ["hello"] = CNet.uint8 })

local myNet = CNet.new("MyNet", struct)

while task.wait(1) do
	myNet:FireAll( { 
		["hello"] = math.floor( tick() ) % 5 
	} )
end