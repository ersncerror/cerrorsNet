local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.Schema.dict( CNet.uint8, CNet.uint8 ))

local player = game:GetService("Players"):FindFirstChildOfClass("Player") or game:GetService("Players").PlayerAdded:Wait()

while true do
	myNet:Fire(player, {
		[1] = 2,
		[2] = 3,
		[3] = 4,
		[4] = 5,
	})
	task.wait(1)
end
