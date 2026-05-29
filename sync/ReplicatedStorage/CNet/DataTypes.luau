local dataTypes = {} :: List

for _, dataType in script:GetChildren() do
	dataTypes[dataType.Name] = require(dataType)
end

export type DataType = {
	bytes: number,
	write: ( b: buffer, offset: number, value: any ) -> (number),
	read: ( b: buffer, offset: number ) -> (any, number?)
	
}

export type List = {
	u8: DataType
} 

return dataTypes 
