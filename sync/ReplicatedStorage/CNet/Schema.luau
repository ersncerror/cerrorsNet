local types = require(script.Parent._types)
type DataType = types.DataType
type Packet = types.Packet

local class = {} :: Schema

-- sets the bit on provided position to true.
local function set(valueToSet: number, pos: number)
    local mask = bit32.lshift(1, pos)
	return bit32.bor( valueToSet, mask )
end

local function get(value: number, pos: number)
	return bit32.extract(value, pos)
end

function class.new(struct)
    local keys = {} :: { string }

    for key, _ in struct do
        table.insert(keys, key)
    end
    table.sort(keys)

    local dataType = {}

    dataType.write = function(packet: Packet, value: { [string]: any })	
		local byte = buffer.readu8(packet.b, packet.offset)
		local totalIncreased = 1

		for i, key in keys do
			if value[key] then
				byte = set(byte, i - 1)
			end
		end
		buffer.writeu8(packet.b, packet.offset, byte)
        packet.offset += 1

		for _, key in keys do
			if not value[key] then
				continue
			end
			
			local increased = struct[key].write(packet, value[key])
            totalIncreased += increased or struct[key].bytes
		end
		
        return totalIncreased
    end

    dataType.read = function(packet: Packet, offset: number)
        local t = {}
        local availableKeys = {}
        local byte = buffer.readu8(packet.b, offset)

		local totalIncreased = 1

		for i = 0, 7 do
			if get(byte, i) == 0 then
                continue
			end

            table.insert(availableKeys, keys[i + 1])
		end
		
        for _, key in availableKeys do
            local value, increased = struct[key].read(packet, offset + totalIncreased)
            t[key] = value
            
            totalIncreased += increased or struct[key].bytes
        end

        return t, totalIncreased
    end

    return dataType
end

export type Schema = {
    new: ( struct: { [string]: DataType } ) -> (DataType)
}

return class