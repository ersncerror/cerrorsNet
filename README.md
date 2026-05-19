# cerrorsNet
roblox network library (with terrible codes)<br>
**This project is built with [Azul](https://devforum.roblox.com/t/azul-%E2%80%94-easy-powerful-studio-first-two-way-sync/4159808).**

## Example Usage

### Server
```lua

local CNet = require("Path/To/The/Module")

local newNet = CNet.new("myFirstNet", CNet.DataTypes.u8)

newNet:FireAll(10)

```

### Client
```lua

local CNet = require("Path/To/The/Module")

local newNet = CNet.new("myFirstNet", CNet.DataTypes.u8)

newNet:Connect(function(...)
    print(...) -- 10
end)

```

## Data Types
See `DataTypes` under the Module, you can add your own data types. It should follow the format of:

- Having a read and write function.
- The write function can return a number for telling how much bytes is taked, and it should use for data types with unpredictable bytes, like string.
- - If it is predictable, then you should have a interger value in the table with key of "bytes".

It should like this:
```lua
-- sync/ReplicatedStorage/CNet/DataTypes/u8.luau

return {
	bytes = 1,	

	write = function(b: buffer, offset: number, value: number)
		writeu8(b, offset, value)
		return 1
	end,
	read = function(b: buffer, offset: number)
		return readu8(b, offset)
	end,	
}
```

After that, you should require it in the list.
```lua
-- sync/ReplicatedStorage/CNet/DataTypes.luau

local dataTypes = {
	u8 = require(script.u8)
}

return dataTypes 

```