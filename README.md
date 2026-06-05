# cerrorsNet
A roblox network library. ~~(with terrible codes)~~

# features
- pack all datas into one event
- remote functions are safer with timeout
- idk

# simple docs

> Basic usage
```lua
-- client
local CNet = require("path/to/the/module")

local myNet = CNet.new("myNet", CNet.uint8 )

myNet:FireAll(1)

-- server
local CNet = require("path/to/the/module")

local myNet = CNet.new("myNet", CNet.uint8 )

myNet:Connect(function(player, ...)
    print(player, ...) -- Roblox, 1
end)

```

> Remote Function (Response Net)
```lua
-- client
local CNet = require("path/to/the/module")

local myNet = CNet.new("myNet", CNet.uint8 ):Response(CNet.uint8):WithTimeoutOf(1)

myNet:InvokeServer(1):InvokeSuccess(function(number)
    print(number) -- 2
end):Timeout(function() -- nothing will be return if timeout
    print("Timeout!")
end)

-- server
local CNet = require("path/to/the/module")

local myNet = CNet.new("myNet", CNet.uint8 ):Response(CNet.uint8)

myNet:OnInvoke(function(player, number)
    return number + 1
end)

```

> Unreliable RemoteEvent (Unstable Net)
```lua
-- client
local CNet = require("path/to/the/module")

local myNet = CNet.new("myNet", CNet.uint8 ):Unstable()

myNet:FireAll(1)

-- server
local CNet = require("path/to/the/module")

local myNet = CNet.new("myNet", CNet.uint8 ):Unstable()

myNet:Connect(function(player, ...)
    print(player, ...) -- Roblox, 1
end)

```

## Adding more data types
See the DataTypes under the library, add your own custom data types under module.

**Data types may cause read/write operations of the library to fail if they have bugs.** Please confirm whether the problem lies with the data type or the library itself.

**A vaild data type should follow like this:**<br>
- A write function, takes packet, and value to write.
- A read function, takes packet, and a offset.
- An optional value called "bytes", if the number of bytes occupied by this data type does not change.
- - if not, then write and read function should always return how many bytes is occupied. (read function should return it as #2 parameter, due to first one is the value which is readed.)
- **Know that you SHOULDN'T add packet's offset in these functions**, instead, returns a number to tell how many offset is increased.

### Example
```lua
-- sync/ReplicatedStorage/CNet/DataTypes/uint8.luau
return {
	bytes = 1, -- this will be 1 byte since u8 is always occupies 1 byte.
	write = function(packet: Packet, value: number)
		write(packet.b, packet.offset, math.floor(value))
	end,
	read = function(packet: Packet, offset: number)
		return read(packet.b, offset)
	end,
}
```