local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8):Response(CNet.uint8)

local player = game:GetService("Players"):FindFirstChildOfClass("Player") or game:GetService("Players").PlayerAdded:Wait()

local counter = 0

while true do
	counter = myNet:InvokeClient(player, counter)
	print(counter)
	task.wait(1)
end