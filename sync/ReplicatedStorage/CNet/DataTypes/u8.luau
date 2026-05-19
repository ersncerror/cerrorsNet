local writeu8 = buffer.writeu8
local readu8 = buffer.readu8

return {
	
	bytes = 1,	
	write = function(b: buffer, offset: number, value: number)
		writeu8(b, offset, value)
		return 1
	end,
	
	read = function(b: buffer, offset: number)
		return readu8(b, offset)
	end,
	
}