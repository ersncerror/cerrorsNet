export type Packet = {
	b: buffer,
	offset: number,
	refs: { Instance },

	new: (size: number) -> Packet,
	Write: (self: Packet, datas: { any }, dataTypes: { DataType }) -> (),
}

export type DataType = {
	write: (packet: Packet, value: any) -> (),
	read: (packet: Packet, offset: number) -> (any, number),
}

return {}
