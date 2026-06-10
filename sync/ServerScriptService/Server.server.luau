local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.Instance, CNet.uint8):Response(CNet.uint8)

local player = game:GetService("Players"):FindFirstChildOfClass("Player")
	or game:GetService("Players").PlayerAdded:Wait()

while true do
	myNet:InvokeClient(player, player, 1):Success(function(...)
		print(...)
	end)

	task.wait(1)
end
