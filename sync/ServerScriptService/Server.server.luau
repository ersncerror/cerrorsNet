local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8):Response(CNet.uint8)

local player = game:GetService("Players"):FindFirstChildOfClass("Player") or game:GetService("Players").PlayerAdded:Wait()

while true do
	for i = 1, 5 do
		myNet
			:InvokeClient(player, i)
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
