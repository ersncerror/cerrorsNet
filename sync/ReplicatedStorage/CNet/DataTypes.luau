local dataTypes = {
	u8number = require(script.u8number)
}

export type DataType = {
	
	bytes: number,
	write: ( b: buffer, offset: number, value: any ) -> (any),
	read: ( b: buffer, offset: number ) -> (any, number?)
	
}

return dataTypes 
