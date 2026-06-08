local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8):Response(CNet.uint8)

while true do
	
	for i = 1, 5 do
		myNet
			:InvokeServer(i)
			:Success(function(...)
				print(...)
			end)
			:Failed(function()
				print("oh no!")
			end)
			:Timeout(function()
				print("die")
			end)
	end
	
	task.wait(1)
end
