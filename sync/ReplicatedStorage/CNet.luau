local RunService = game:GetService("RunService")

local DataTypes = require(script.DataTypes)

local idCounter = 1

local BYTES_PER_FRAMES = 256 -- every frames can hold for 256 bytes.
local MAX_PACKETS_QUEUE = 128

local globalPackets = buffer.create(BYTES_PER_FRAMES) 
local globalPacketOffset = 0

local playerPackets = {} :: { [Player]: { b: buffer, offset: number } }

local remote : RemoteEvent

local nets = {}
local netsById = {}-- :: { [number]: Net }

local class = {}-- :: Net
class.__index = class

class.DataTypes = DataTypes

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
	
	local packetLength = buffer.len(packets)
	local offset = 0

	local packetId = buffer.readu8(packets, offset)
	while packetId ~= 0 do
		local net = netsById[packetId]

		offset += 1

		local unSerializedPacket = {}
		table.insert(unSerializedPacket, player)
		for _, dataType in net._dataTypes do
			local value, len = dataType.read(packets, offset)
			offset += len or dataType.bytes
			table.insert( unSerializedPacket, value )
		end
		
		if net._eventListenerCount > 0 then
			local listener = net._eventListeners.next
			
			while listener ~= net._eventListeners do
				
				if listener.thread then
					task.spawn( listener.thread, unpack(unSerializedPacket) )
					listener.previous.next = listener.next
					listener.next.previous = listener.previous
					listener._eventListenerCount -= 1
				elseif listener.func then
					task.spawn(listener.func, unpack(unSerializedPacket))
				end
				
				listener = listener.next				
			end
		else
			
			if #net._queuedPackets >= MAX_PACKETS_QUEUE then
				net._packetsDropped += 1
				
				if MAX_PACKETS_QUEUE % net._packetsDropped == 0 or net._packetsDropped % MAX_PACKETS_QUEUE == 0 then
					warn(`Net "{net.Name}" has queued packets and met the limit of {MAX_PACKETS_QUEUE}. Did you just forget to connect? ({net._packetsDropped} Dropped.)`)
					continue
				end
			end
			
			table.insert( net._queuedPackets, unSerializedPacket )
		end
		
		packetId = buffer.readu8(packets, offset)
	end
	
	debug.profileend()
end

function class.new(netName, ...)
	if nets[netName] then
		return nets[netName]
	end

	local self = setmetatable( {}, class )
	self.Name = netName
	
	self._dataTypes = {...}
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

function class:Fire(player, ...)
	playerPackets[player] = playerPackets[player] or { b = buffer.create(BYTES_PER_FRAMES), offset = 0 }
	local b = playerPackets[player].b
	local offset = playerPackets[player].offset

	local datas = {...}

	buffer.writeu8(b, offset, self._id)
	offset += 1
	for i, dataInterperter in self._dataTypes do
		local offsetIncreased = dataInterperter.write(b, offset, datas[i])
		offset += i
	end

	playerPackets[player].offset = offset
end

function class:FireAll(...)
	local datas = {...}

	buffer.writeu8(globalPackets, globalPacketOffset, self._id)
	globalPacketOffset += 1
	for i, dataInterperter in self._dataTypes do
		local offsetIncreased = dataInterperter.write(globalPackets, globalPacketOffset, datas[i])
		globalPacketOffset += i
	end
end

function class:Connect(func)	

	local link = {
		previous = self._eventListeners,
		next = self._eventListeners.next,
		func = func
	}
	
	self._eventListeners.next.previous = link
	self._eventListeners.next = link
	self._eventListenerCount += 1
	
	if self._queuedPackets then

		for _, packet in self._queuedPackets do
			task.spawn( func, table.unpack( packet ) )
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
		func = once
	}
	
	if #self._queuedPackets > 0 then
		local packet = table.remove( self._queuedPackets )
		task.spawn(func, table.unpack( packet ) )
	else
		print("once")
		self._eventListeners.next.previous = link
		self._eventListeners.next = link
		self._eventListenerCount += 1
	end

end

function class:Wait()
	local link = {
		previous = self._eventListeners,
		next = self._eventListeners.next,
		thread = coroutine.running()
	}
	
	self._eventListeners.next.previous = link
	self._eventListeners.next = link
	self._eventListenerCount += 1
	
	coroutine.yield()
end

if RunService:IsServer() then
	remote = Instance.new("RemoteEvent")
	remote.Parent = script
	
	RunService.Heartbeat:Connect(processServerPackets)
	remote.OnServerEvent:Connect(function(player, packet)
		onPacketReceived(packet, player)
	end)
else
	remote = script:WaitForChild("RemoteEvent")
	remote.OnClientEvent:Connect(onPacketReceived)
	RunService.Heartbeat:Connect(processClientPackets)
end

--export type Net = {
--	DataTypes: { DataTypes },
	
--	_id: number,
--	_dataTypes: { DataTypes.DataType },
--	_eventListeners: { () -> () },
--	_eventListenerCount: number,
--	_queuedPackets: { any },

--	new: ( netName: string, ...DataTypes.DataType ) -> ( Net ),
--	Fire: ( self: Net, player: Player, ...any ) -> (...any?),
--	Connect: ( self: Net, func: (...any)->() ) -> ( { Disconnect: () -> () } ),
--	Once: ( self: Net, func: (...any)->() ) -> (),
--	Wait: ( self: Net ) -> ( any )
--}

return class