local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8):Unstable()

local player = game:GetService("Players"):FindFirstChildOfClass("Player") or game:GetService("Players").PlayerAdded:Wait()

myNet:Connect(function(plr: Player, ...)
	print(player, ...)
end)