local types = require(script.Parent.Parent._types)
type Packet = types.Packet

local newBuffer = buffer.create

local class = {} :: types.Packet

local function write(self: Packet, datas: { any }, dataTypes: { types.DataType }): number
	if #datas ~= #dataTypes then
		warn(`[Packet Write]: Expect to write {#dataTypes} datas, but only got {#datas} datas here.`)
	end
	
	for i, dataType in dataTypes do
		dataType.write(self, datas[i])
	end
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
