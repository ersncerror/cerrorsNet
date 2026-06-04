local CNet = require(game:GetService("ReplicatedStorage").CNet)

local myNet = CNet.new("MyNet", CNet.uint8):Response(CNet.uint8):WithTimeoutOf(10)

myNet:InvokeServer(1):InvokeSuccess(function(...)
	print(...)
end):Timeout(function()
	print("timeout!")
end)