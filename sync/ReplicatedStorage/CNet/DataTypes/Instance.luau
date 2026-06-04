local types = require(script.Parent.Parent._types)
type Packet = types.Packet

local write = buffer.writeu8
local read = buffer.readu8

return {
	bytes = 1,
	write = function(packet: Packet, value: Instance)
		table.insert( packet.refs, value )
		local instId = #packet.refs
		write(packet.b, packet.offset, instId)
	end,
	read = function(packet: Packet, offset: number)
		return packet.refs[ read(packet.b, offset) ]
	end,
}