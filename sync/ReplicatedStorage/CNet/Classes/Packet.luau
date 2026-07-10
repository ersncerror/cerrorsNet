local types = require(script.Parent.Parent._types)
type Packet = types.Packet

local newBuffer = buffer.create

local class = {} :: types.Packet

local function write(self: Packet, datas: { any }, dataTypes: { types.DataType }): boolean
	if #datas ~= #dataTypes then
		warn(`[Packet Write]: Expect to write {#dataTypes} datas, but only got {#datas} datas here.`)
	end

	for i, dataType in dataTypes do
		local success, message = pcall(dataType.write, self, datas[i])

		if not success then
			return false, message
		end

		dataType.write(self, datas[i])
	end

	return true
end

function class.new(size)
	local self = {}
	self.b = newBuffer(size)
	self.offset = 0
	self.refs = {}

	self.Write = write
	return self
end

return class
