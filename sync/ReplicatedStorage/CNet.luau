local RunService = game:GetService("RunService")

local DataTypes = require(script.DataTypes)

local idCounter = 1

local BYTES_PER_FRAMES = 256 -- every frames can hold for 256 bytes.
local MAX_PACKETS_QUEUE = 128

local globalPackets = buffer.create(BYTES_PER_FRAMES)
local globalPacketOffset = 0

local playerPackets : { [Player]: { b: buffer, offset: number } }
local invokingPackets = {}

local remote: RemoteEvent

local nets = {}
local netsById = {} :: { [number]: Net }

local class = {} :: Net
class.__index = class

class.DataTypes = DataTypes

local function unSerialize(t: {any}, offset: number, packet: buffer, dataTypes: {DataTypes.DataType})	
	local unSerializedPacket = t or {}

	for _, dataType in dataTypes do
		local value, len = dataType.read(packet, offset)
		offset += len or dataType.bytes
		table.insert(unSerializedPacket, value)
	end

	return unSerializedPacket, offset
end

local function serialize(b: buffer, offset: number, datas: {any}, dataTypes: {DataTypes.DataType})	
	if #datas ~= #dataTypes then
		error(`Serialize failed, Expect to serialize {#dataTypes} data types, but got {#datas} datas types.`)
	end
	
	for i, dataInterperter in dataTypes do
		local offsetIncreased = dataInterperter.write(b, offset, datas[i])
		offset += offsetIncreased
	end

	return offset
end

local function queuePacketToNet(net: Net, packet: any)
	if #net._queuedPackets >= MAX_PACKETS_QUEUE then
		net._packetsDropped += 1

		if MAX_PACKETS_QUEUE % net._packetsDropped == 0 or net._packetsDropped % MAX_PACKETS_QUEUE == 0 then
			warn(
				`Net "{net.Name}" has queued packets and met the limit of {MAX_PACKETS_QUEUE}. Did you just forget to connect? ({net._packetsDropped} Dropped.)`
			)
			return
		end
	end

	table.insert(net._queuedPackets, packet)
end

local function processServerPackets()
	remote:FireAllClients(globalPackets)
	globalPackets = buffer.create(BYTES_PER_FRAMES)
	globalPacketOffset = 0

	-- process player packets
	for player, packet in playerPackets do
		remote:FireClient(player, packet.b)
	end

	table.clear(playerPackets)
end

local function processClientPackets()
	remote:FireServer(globalPackets)
	globalPackets = buffer.create(BYTES_PER_FRAMES)
	globalPacketOffset = 0
end

local function onPacketReceived(packets: buffer, player: Player?)
	debug.profilebegin("CNet_ProcessPackets")

	local offset = 0

	local packetId = buffer.readu8(packets, offset)
	while packetId ~= 0 do
		local net = netsById[packetId]
		offset += 1

		local unSerializedPacket, newOffset = unSerialize({player}, offset, packets, net._dataTypes)
		offset = newOffset

		if net._response then
			if not invokingPackets[net._id] then
				if not net.OnInvoke then
					queuePacketToNet(net, unSerializedPacket)
					continue
				end

				if player then
					playerPackets[player] = playerPackets[player] or { b = buffer.create(BYTES_PER_FRAMES), offset = 0 }
				end

				local targetBuffer = player and playerPackets[player].b or globalPackets
				local bOffset = player and playerPackets[player].offset or globalPacketOffset
				local oldOffset = bOffset
				
				buffer.writeu8(targetBuffer, bOffset, net._id)
				bOffset = serialize( targetBuffer, bOffset + 1, {net._onInvoke( unpack(unSerializedPacket) )}, net._reponseDataTypes ) + 1

				if player then
					playerPackets[player].offset = bOffset
				else
					globalPacketOffset = bOffset
					offset += bOffset - oldOffset 
				end

			else
				invokingPackets[net._id] = nil
				task.spawn(net._waitingForResponse, unpack(unSerializedPacket))
			end
		else
			if net._eventListenerCount > 0 then
				local listener = net._eventListeners.next

				while listener ~= net._eventListeners do
					if listener.thread then
						task.spawn(listener.thread, unpack(unSerializedPacket))
						listener.previous.next = listener.next
						listener.next.previous = listener.previous
						listener._eventListenerCount -= 1
					elseif listener.func then
						task.spawn(listener.func, unpack(unSerializedPacket))
					end

					listener = listener.next
				end
			else
				queuePacketToNet(net, unSerializedPacket)
			end
		end

		packetId = buffer.readu8(packets, offset)
	end

	debug.profileend()
end

function class.new(netName, ...): Net
	if nets[netName] then
		return nets[netName]
	end

	local self = setmetatable({}, class)
	self.Name = netName

	self._dataTypes = { ... }

	self._eventListeners = {}
	self._eventListenerCount = 0

	self._queuedPackets = {}
	self._packetsDropped = 0

	self._id = script:GetAttribute(netName) or idCounter
	idCounter += script:GetAttribute(netName) and 0 or 1

	nets[netName] = self
	netsById[self._id] = self

	script:SetAttribute(netName, self._id)

	self._eventListeners.next = self._eventListeners
	self._eventListeners.previous = self._eventListeners

	return self
end

function class:InvokeServer(...)
	local datas = { ... }

	buffer.writeu8(globalPackets, globalPacketOffset, self._id)
	globalPacketOffset = serialize(globalPackets, globalPacketOffset + 1, datas, self._dataTypes) + 1 

	self._waitingForResponse = coroutine.running()
	invokingPackets[self._id] = self
	return coroutine.yield()
end

function class:InvokeClient(player, ...)
	playerPackets[player] = playerPackets[player] or { b = buffer.create(BYTES_PER_FRAMES), offset = 0 }
	local b = playerPackets[player].b
	local offset = playerPackets[player].offset

	local datas = { ... }

	buffer.writeu8(b, offset, self._id)
	playerPackets[player].offset = serialize(b, offset + 1, datas, self._dataTypes) + 1 

	self._waitingForResponse = coroutine.running()
	invokingPackets[self._id] = self
	return coroutine.yield()
end

function class:OnInvoke(func: () -> ())
	self._onInvoke = func
	
	if #self._queuedPackets > 0 then		
		for _, packet in self._queuedPackets do
			
			if RunService:IsClient() then
				buffer.writeu8(globalPackets, globalPacketOffset, self._id)
				globalPacketOffset = serialize( globalPackets, globalPacketOffset + 1, {self._onInvoke( unpack(packet) )}, self._reponseDataTypes ) + 1
			else
				local player = packet[1]

				playerPackets[player] = playerPackets[player] or { b = buffer.create(BYTES_PER_FRAMES), offset = 0 }
				local targetBuffer =  playerPackets[player].b
				local bOffset = playerPackets[player].offset 

				buffer.writeu8(targetBuffer, bOffset, self._id)
				bOffset = serialize( targetBuffer, bOffset + 1, {self._onInvoke( unpack(packet) )}, self._reponseDataTypes ) + 1

				playerPackets[player].offset = bOffset
			end
		end
		
	end

end

-- Changes the net to response net, like RemoteFunction
function class:Response(...)
	self._response = true

	self._eventListeners = nil
	self._eventListenerCount = nil

	self._reponseDataTypes = {...}

	return self
end

function class:Fire(player, ...)
	playerPackets[player] = playerPackets[player] or { b = buffer.create(BYTES_PER_FRAMES), offset = 0 }
	local b = playerPackets[player].b
	local offset = playerPackets[player].offset

	local datas = { ... }

	buffer.writeu8(b, offset, self._id)
	playerPackets[player].offset = serialize(playerPackets[player].b, offset + 1, datas, self._dataTypes) + 1
end

function class:FireAll(...)
	local datas = { ... }

	buffer.writeu8(globalPackets, globalPacketOffset, self._id)
	globalPacketOffset = serialize(globalPackets, globalPacketOffset + 1, datas, self._dataTypes) + 1
end

function class:Connect(func)
	local link = {
		previous = self._eventListeners,
		next = self._eventListeners.next,
		func = func,
	}

	self._eventListeners.next.previous = link
	self._eventListeners.next = link
	self._eventListenerCount += 1

	if self._queuedPackets then
		for _, packet in self._queuedPackets do
			task.spawn(func, table.unpack(packet))
		end

		table.clear(self._queuedPackets)
	end

	return {

		Disconnect = function()
			link.previous.next = link.next
			link.next.previous = link.previous
		end,
	}
end

function class:Once(func)
	local link

	local function once(...)
		func(...)
		link.previous.next = link.next
		link.next.previous = link.previous
		self._eventListenerCount -= 1
	end

	link = {
		previous = self._eventListeners,
		next = self._eventListeners.next,
		func = once,
	}

	if #self._queuedPackets > 0 then
		local packet = table.remove(self._queuedPackets)
		task.spawn(func, table.unpack(packet))
	else
		self._eventListeners.next.previous = link
		self._eventListeners.next = link
		self._eventListenerCount += 1
	end
end

function class:Wait()
	local link = {
		previous = self._eventListeners,
		next = self._eventListeners.next,
		thread = coroutine.running(),
	}

	self._eventListeners.next.previous = link
	self._eventListeners.next = link
	self._eventListenerCount += 1

	return coroutine.yield()
end

if RunService:IsServer() then
	remote = Instance.new("RemoteEvent")
	remote.Parent = script

	playerPackets = {}

	RunService.Heartbeat:Connect(processServerPackets)
	remote.OnServerEvent:Connect(function(player, packet)
		onPacketReceived(packet, player)
	end)
else
	remote = script:WaitForChild("RemoteEvent")
	remote.OnClientEvent:Connect(onPacketReceived)
	RunService.Heartbeat:Connect(processClientPackets)
end

export type Net = {
	DataTypes: DataTypes.List,

	_id: number,
	_dataTypes: { DataTypes.DataType },
	_reponseDataTypes: { DataTypes.DataType },

	_eventListeners: { () -> () },
	_eventListenerCount: number,

	_queuedPackets: { any },
	_packetsDropped: number,

	_response: boolean,
	_waitingForResponse: thread?,
	_onInvoke: (...any) -> (...any)?,

	-- constructors
	new: (netName: string, ...DataTypes.DataType) -> Net,
	Response: (self: Net, ...DataTypes.DataType) -> Net,

	-- speaker methods
	Fire: (self: Net, player: Player, ...any) -> ...any?,
	InvokeClient: (self: Net, player: Player, ...any) -> ...any,
	InvokeServer: (self: Net, ...any) -> ...any,
	OnInvoke: (self: Net, func: () -> () ) -> (),
	
	-- listen methods
	Connect: (self: Net, func: (...any) -> ()) -> { Disconnect: () -> () },
	Once: (self: Net, func: (...any) -> ()) -> (),
	Wait: (self: Net) -> any,
}

return class
