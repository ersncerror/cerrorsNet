local DataTypes = require(script.Parent.DataTypes)

local readu8 = buffer.readu8
local writeu8 = buffer.writeu8

local writebits = buffer.writebits
local readbits = buffer.readbits

local Schema = {} :: Schema

local function getKeysInDict(dict: {[any]: any})
	local keys = {}

	for key, _ in dict do
		table.insert( keys, key )
	end

	return keys
end


function Schema.new(tab: { [string]: DataTypes.DataType })
	local keys = {}
	local schema = {}
	
	for key, _ in tab do
		table.insert(keys, key)
	end
	if #keys > 8 then
		warn(`Schema can only have 8 keys here, you have {#keys} keys.`)
		return
	end
	
	table.sort(keys)

	schema.write = function(b: buffer, offset: number, t: {[string]: any})
		local offsetIncreased = 1

		-- 1 bytes for keys is reserved
		for index, key in keys do
			writebits(b, index + offset * 8, 1, t[key] and 1 or 0)
		end

		for key, value in t do
			offsetIncreased += tab[key].write(b, offset + offsetIncreased, value) or tab[key].bytes
		end
		
		return offsetIncreased
	end

	schema.read = function(b: buffer, offset: number)
		local offsetIncreased = 1
		local availableKeys = {}
		local result = {}

		for i = 1, 8 do
			table.insert( availableKeys, readbits(b, i + offset * 8, 1) == 1 and keys[i] or nil )
		end

		for _, key in availableKeys do
			local value, vOffset = tab[key].read(b, offset + offsetIncreased)
			offsetIncreased += vOffset or tab[key].bytes
			result[key] = value
		end

		return result, offsetIncreased
	end

	return schema
end

function Schema.dict(kInterpreter, vInterpreter)
	local schema = {}

	schema.write = function(b: buffer, offset: number, dict: { [any]: any })
		local keys = #getKeysInDict(dict)
		
		if #keys > 255 then
			warn(`Dict schema can only have 255 keys, you have {#keys} keys.`)
			return
		end
		
		local offsetIncreased = 1

		writeu8(b, offset, keys)

		for key, value in dict do
			offsetIncreased += kInterpreter.write(b, offset+offsetIncreased, key) or kInterpreter.bytes	
			offsetIncreased += vInterpreter.write(b, offset + offsetIncreased, value) or vInterpreter.bytes
		end

		return offsetIncreased
	end

	schema.read = function(b: buffer, offset: number)
		local keys = readu8(b, offset)
		local offsetIncreased = 1
		local dict = {}

		for _ = 1, keys do
			
			local key, kOffset = kInterpreter.read(b, offset+offsetIncreased)
			offsetIncreased += kOffset or kInterpreter.bytes

			local value, vOffset = vInterpreter.read(b, offset + offsetIncreased)
			offsetIncreased += vOffset or vInterpreter.bytes

			dict[key] = value
		end

		return dict, offsetIncreased
	end

	return schema
end

function Schema.array(interpreter)
	local schema = {}
	
	schema.write = function(b: buffer, offset: number, array: {any})
		if #array > 255 then
			warn(`Array schema can only have 255 values, you have {#array} values.`)
			return
		end
		
		local offsetIncreased = 1
		
		writeu8(b, offset, #array)
		
		for _, value in array do
			local offsetWritted = interpreter.write(b, offset + offsetIncreased, value) or interpreter.bytes
			offsetIncreased += offsetWritted
		end
		
		return offsetIncreased
	end
	
	schema.read = function(b: buffer, offset: number)
		local count = readu8(b, offset)
		local offsetIncreased = 1
		local t = {}
		
		for _ = 1, count do
			local value, offsetReaded = interpreter.read(b, offset+offsetIncreased)
			offsetIncreased += offsetReaded or interpreter.bytes
			table.insert(t, value)
		end
		
		return t, offsetIncreased
	end
	
	return schema
end

export type Schema = {
	new: ( tab: { [string]: DataTypes.DataType } ) -> ( DataTypes.DataType ),
	dict: ( kInterpreter: DataTypes.DataType, vInterpreter: DataTypes.DataType ) -> ( DataTypes.DataType ),
	array: ( interpreter: DataTypes.DataType ) -> ( DataTypes.DataType ),
}

return Schema
