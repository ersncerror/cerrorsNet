local types = require(script.Parent.Parent._types)
type Packet = types.Packet

local write = buffer.writeu8
local read = buffer.readu8

return {
	write = function(packet: Packet, value: number)
		write(packet.b, packet.offset, math.floor(value))
		packet.offset += 1
	end,
	read = function(packet: Packet, offset: number)
		return read(packet.b, offset), 1
	end,
}
