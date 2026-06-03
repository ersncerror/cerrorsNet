local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8)

local counter = 0

local player = game:GetService("Players"):FindFirstChildOfClass("Player") or game:GetService("Players").PlayerAdded:Wait()

while task.wait(1) do
	myNet:Fire(player, counter)
	counter += 1
end
