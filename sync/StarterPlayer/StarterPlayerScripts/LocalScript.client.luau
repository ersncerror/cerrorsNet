local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.Instance, CNet.uint8):Response(CNet.uint8)

while true do
	myNet
		:InvokeServer(game:GetService("Players").LocalPlayer, 6)
		:Success(function(...)
			print(...)
		end)
		:Failed(function()
			print("oh no!")
		end)
		:Await()
end
