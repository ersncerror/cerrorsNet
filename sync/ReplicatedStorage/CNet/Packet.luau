local types = require(script.Parent._types)
type Packet = types.Packet

local newBuffer = buffer.create

local class = {} :: types.Packet

local function write(self: Packet, datas: { any }, dataTypes: { types.DataType })
	for i, dataType in dataTypes do
		self.offset += dataType.write(self, datas[i]) or dataType.bytes
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
