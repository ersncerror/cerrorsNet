local types = require(script.Parent.Parent._types)
type DataType = types.DataType
type Packet = types.Packet

local class = {} :: Schema

local function getKeys(t: { [any]: any })
	local keys = {}

	for k, _ in t do
		table.insert(keys, k)
	end

	return keys
end

-- sets the bit on provided position to true.
local function set(valueToSet: number, pos: number)
	local mask = bit32.lshift(1, pos)
	return bit32.bor(valueToSet, mask)
end

local function get(value: number, pos: number)
	return bit32.extract(value, pos)
end

function class.new(struct)
	-- why do i have this bro :sob:

	local keys = {} :: { string }

	for key, _ in struct do
		table.insert(keys, key)
	end
	table.sort(keys)

	local dataType = {}

	dataType.write = function(packet: Packet, value: { [string]: any })
		local byte = buffer.readu8(packet.b, packet.offset)

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

			struct[key].write(packet, value[key])
		end
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

function class.dict(keyType, valueType)
	local dataType = {}

	dataType.write = function(packet: Packet, value: { [any]: any })
		buffer.writeu8(packet.b, packet.offset, #getKeys(value))
		packet.offset += 1

		for k, v in value do
			keyType.write(packet, k)
			valueType.write(packet, v)
		end
	end

	dataType.read = function(packet: Packet, offset: number)
		local keys = buffer.readu8(packet.b, offset)
		local result = {}

		local increased = 1

		for _ = 1, keys do
			local k, kOffset = keyType.read(packet, offset + increased)
			increased += kOffset or keyType.bytes

			local v, vOffset = valueType.read(packet, offset + increased)
			increased += vOffset or valueType.bytes

			result[k] = v
		end

		return result, increased
	end

	return dataType
end

function class.array(valueType)
	local dataType = {}

	dataType.write = function(packet: Packet, value: { [number]: any })
		local keys = #value
		buffer.writeu8(packet.b, packet.offset, keys)
		packet.offset += 1

		for _, v in value do
			valueType.write(packet, v)
		end
	end

	dataType.read = function(packet: Packet, offset: number)
		local keys = buffer.readu8(packet.b, offset)
		local old = offset
		local t = {}

		offset += 1
		for _ = 1, keys do
			local value, increased = valueType.read(packet, offset)
			offset += increased
			table.insert(t, value)
		end

		return t, offset - old
	end

	return dataType
end

export type Schema = {
	new: (struct: { [string]: DataType }) -> DataType,
	dict: (keyType: DataType, valueType: DataType) -> DataType,
	array: (valueType: DataType) -> DataType,
}

return class
