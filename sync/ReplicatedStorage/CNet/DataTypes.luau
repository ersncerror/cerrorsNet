local types = require(script.Parent._types)
type DataType = types.DataType

local list = {} :: List

for _, dataType in script:GetChildren() do
	list[dataType.Name] = require(dataType)
end

export type List = {
	uint8: DataType,
	Instance: DataType,
}

return list
