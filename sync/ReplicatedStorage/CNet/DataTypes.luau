local dataTypes = {
	u8 = require(script.u8)
}

export type DataType = {
	
	bytes: number,
	write: ( b: buffer, offset: number, value: any ) -> (any),
	read: ( b: buffer, offset: number ) -> (any, number?)
	
}

return dataTypes 
