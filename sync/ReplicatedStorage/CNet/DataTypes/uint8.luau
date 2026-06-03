local types = require("../_types")
type Packet = types.Packet

local write = buffer.writeu8
local read = buffer.readu8

return {
	bytes = 1,
	write = function(packet: Packet, value: number)
		write(packet.b, packet.offset, math.floor(value))
	end,
	read = function(packet: Packet, offset: number)
		return read(packet.b, offset) 
	end,
}