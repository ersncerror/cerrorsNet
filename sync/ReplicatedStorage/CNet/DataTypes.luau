local dataTypes = {
	u8 = require(script.u8)
} :: List

export type DataType = {
	bytes: number,
	write: ( b: buffer, offset: number, value: any ) -> (any),
	read: ( b: buffer, offset: number ) -> (any, number?)
	
}

export type List = {
	u8: DataType
} 

return dataTypes 
