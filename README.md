# cerrorsNet
A roblox network library. ~~(with terrible codes)~~
This project is built with [Azul](https://devforum.roblox.com/t/azul-%E2%80%94-easy-powerful-studio-first-two-way-sync/4159808).

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

myNet:InvokeServer(1):Success(function(number)
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
- write function is required to increase the packet offset, otherwise, it will possibly cause a error in library.
- read function is different, return increased offset as #2 parameter.

### Example
```lua
-- sync/ReplicatedStorage/CNet/DataTypes/uint8.luau
return {
	write = function(packet: Packet, value: number)
		buffer.writeu8(packet.b, packet.offset, math.floor(value))
		packet.offset += 1
	end,
	read = function(packet: Packet, offset: number)
		return buffer.readu8(packet.b, offset), 1
	end,
}
```