local RunService = game:GetService("RunService")

local DataTypes = require(script.DataTypes)
local Schema = require(script.Schema)

local readu8 = buffer.readu8
local writeu8 = buffer.writeu8

local readu16 = buffer.readu16
local writeu16 = buffer.writeu16

local copyb = buffer.copy

local idCounter = 1

local BYTES_PER_FRAMES = 2048 -- every frames can hold for x bytes.
local MAX_PACKETS_QUEUE = 128
local DEFAULT_TIMEOUT = 5

local globalPackets = buffer.create(BYTES_PER_FRAMES)
local globalPacketOffset = 0

local unreliablePackets = buffer.create(BYTES_PER_FRAMES)
local unreliPacketOffset = 0

local playerPackets: { [Player]: { b: buffer, offset: number, unreliB: buffer?, unreliOffset: number? } }

local remote: RemoteEvent
local unreliableRemote: UnreliableRemoteEvent

local nets = {}
local netsById = {} :: { [number]: Net }

local cachedPackets = {} :: { [number]: { b: buffer, player: Player? } } -- when net is not created and this packet is being decoding.

local class = {} :: Net
class.__index = class

class.DataTypes = DataTypes
class.Schema = Schema

local function abstractPacket(source: buffer, targetOffset: number)
	local abstractedPacket = buffer.create(targetOffset + 1)
	copyb(abstractedPacket, 0, source, 0, targetOffset)

	return abstractedPacket
end

local function unSerialize(t: { any }, offset: number, packet: buffer, dataTypes: { DataTypes.DataType })
	local unSerializedPacket = t or {}

	for _, dataType in dataTypes do
		local value, len = dataType.read(packet, offset)
		offset += len or dataType.bytes
		table.insert(unSerializedPacket, value)
	end

	return unSerializedPacket, offset
end

local function serialize(b: buffer, offset: number, datas: { any }, dataTypes: { DataTypes.DataType })
	if #datas ~= #dataTypes then
		warn(
			`[CNet]: Possibly bug detected. Expect to serialize {#dataTypes} data types, but got {#datas} datas types to serialize.`
		)
	end

	for i, dataInterperter in dataTypes do
		local offsetIncreased = dataInterperter.write(b, offset, datas[i]) or dataInterperter.bytes
		offset += offsetIncreased
	end

	return offset
end

local function writeInPacket(packet: buffer, offset: number, net: Net, datas: { any }, _response: boolean?)
	writeu8(packet, offset, net._id)
	local newOffset = serialize(packet, offset + 3, datas, _response and net._responseDataTypes or net._dataTypes)
	writeu16(packet, offset + 1, newOffset - offset - 3)

	return newOffset
end

local function queuePacketToNet(net: Net, packet: any)
	local maxPacketsInQueue = net._unreliable and 1 or MAX_PACKETS_QUEUE

	if #net._queuedPackets >= maxPacketsInQueue then
		net._packetsDropped += 1

		if not net._nextPacketDropWarn or net._packetsDropped >= net._nextPacketDropWarn then
			net._nextPacketDropWarn = (net._nextPacketDropWarn or 1) * 2
			warn(
				`[CNet]: Discarded packet for "{net.Name}" cause it's queued too much packets. Did you just forget to connect? ({net._packetsDropped} Dropped.)`
			)
			return
		end
	end

	table.insert(net._queuedPackets, packet)
end

local function setPlayersPacket(player: Player, unreliable: boolean?)
	local packet = playerPackets[player]
		or {
			b = buffer.create(BYTES_PER_FRAMES),
			offset = 0,
			unreliB = unreliable and buffer.create(BYTES_PER_FRAMES) or nil,
			unreliOffset = unreliable and 0 or nil,
		}

	playerPackets[player] = packet
	return packet
end

local function newConnection(func): Connection
	return {
		Disconnect = func
	}
end

local function processPacketsToClient()
	if globalPacketOffset > 0 then
		remote:FireAllClients(abstractPacket(globalPackets, globalPacketOffset))
		globalPackets = buffer.create(BYTES_PER_FRAMES)
		globalPacketOffset = 0
	end

	if unreliPacketOffset > 0 then
		unreliableRemote:FireAllClients(abstractPacket(unreliablePackets, unreliPacketOffset))
		unreliablePackets = buffer.create(BYTES_PER_FRAMES)
		unreliPacketOffset = 0
	end

	-- process player packets
	for player, packet in playerPackets do
		remote:FireClient(player, abstractPacket(packet.b, packet.offset))

		if packet.unreliB then
			unreliableRemote:FireClient(player, abstractPacket(packet.unreliB, packet.unreliOffset))
		end
	end

	table.clear(playerPackets)
end

local function processPacketsToServer()
	if globalPacketOffset > 0 then
		remote:FireServer(abstractPacket(globalPackets, globalPacketOffset))
		globalPackets = buffer.create(BYTES_PER_FRAMES)
		globalPacketOffset = 0
	end

	if unreliPacketOffset > 0 then
		unreliableRemote:FireServer(abstractPacket(unreliablePackets, unreliPacketOffset))
		unreliablePackets = buffer.create(BYTES_PER_FRAMES)
		unreliPacketOffset = 0
	end
end

local function sendPacketToListeners(net: Net, packet: { any })
	if net._eventListenerCount > 0 then
		local listener = net._eventListeners.next

		while listener ~= net._eventListeners do
			if listener.thread then
				task.spawn(listener.thread, unpack(packet))
				listener.previous.next = listener.next
				listener.next.previous = listener.previous
				listener._eventListenerCount -= 1
			elseif listener.func then
				task.spawn(listener.func, unpack(packet))
			end

			listener = listener.next
		end
	else
		queuePacketToNet(net, packet)
	end
end

local function onResponseTimeout(self: Net)
	warn(`{self.Name} didn't get response before timeout.`, self._waitingForResponse)
	local t, w = self._timeoutHandler, self._waitingForResponse

	self._timeoutHandler = nil
	self._waitingForResponse = nil

	task.cancel(t)
	task.spawn(w)
end

local function handleResponsePacket(net: Net, player: Player?, packet: { any })
	-- if this net is not waiting for a response
	-- then it should be the one who response the sender.

	-- else, it will be the one where waiting for response.

	if not net._waitingForResponse then
		if not net._onInvoke then
			queuePacketToNet(net, packet)
			return
		end

		if player then
			setPlayersPacket(player, false)
		end

		local targetBuffer = player and playerPackets[player].b or globalPackets
		local bOffset = player and playerPackets[player].offset or globalPacketOffset
		local datas = { net._onInvoke(unpack(packet)) }

		local offset = writeInPacket(targetBuffer, bOffset, net, datas, true)

		if player then
			playerPackets[player].offset = offset
		else
			globalPacketOffset = offset
		end
	else
		local t, w = net._timeoutHandler, net._waitingForResponse
		
		net._timeoutHandler = nil
		net._waitingForResponse = nil
		
		task.cancel(t)
		task.spawn(w, unpack(packet))
	end
end

local function onPacketReceived(packets: buffer, player: Player?)
	debug.profilebegin("CNet_ProcessPackets")

	local offset = 0

	local packetId = readu8(packets, offset)
	while packetId ~= 0 and offset < buffer.len(packets) do
		local net = netsById[packetId]
		local length = readu16(packets, offset + 1)
		offset += 3 -- theres 2 bytes of packet length behind the id

		if not net then
			cachedPackets[packetId] = cachedPackets[packetId] or {}
			local cuttedBuffer = buffer.create(length + 1)
			copyb(cuttedBuffer, 0, packets, offset, length)
			table.insert(cachedPackets[packetId], { b = cuttedBuffer, player = player })

			offset += length
			packetId = readu8(packets, offset)
			continue
		end

		local unSerializedPacket = unSerialize({}, offset, packets, net._dataTypes)
		offset += length

		if net._response then
			handleResponsePacket(net, player, unSerializedPacket)
		else
			if player then
				table.insert(unSerializedPacket, 1, player)
			end
			sendPacketToListeners(net, unSerializedPacket)
		end

		packetId = readu8(packets, offset)
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

	-- check cached packets
	if cachedPackets[self._id] then
		for _, packet in cachedPackets[self._id] do
			local unSerializedData = unSerialize({ cachedPackets[self._id].player }, 0, packet.b, self._dataTypes)
			sendPacketToListeners(self, unSerializedData)
		end

		cachedPackets[self._id] = nil
	end

	return self
end

function class:InvokeServer(...)
	local datas = { ... }

	globalPacketOffset = writeInPacket(globalPackets, globalPacketOffset, self, datas)

	self._waitingForResponse = coroutine.running()
	self._timeoutHandler = task.delay(self._timeout, onResponseTimeout, self)

	return coroutine.yield()
end

function class:InvokeClient(player, ...)
	if not player or typeof(player) ~= "Instance" or not player:IsA("Player") then
		error(
			`On invoking client, but player parameter is not a player, got {typeof(player) == "Instance" and player.ClassName or player}.`
		)
	end

	setPlayersPacket(player)
	local b = playerPackets[player].b
	local offset = playerPackets[player].offset

	local datas = { ... }

	playerPackets[player].offset = writeInPacket(b, offset, self, datas)

	self._waitingForResponse = coroutine.running()
	self._timeoutHandler = task.delay(self._timeout, onResponseTimeout, self)
	return coroutine.yield()
end

function class:OnInvoke(func: () -> ())
	self._onInvoke = func

	if #self._queuedPackets > 0 then
		print("process cached response packets.")
		for _, packet in self._queuedPackets do
			if RunService:IsClient() then
				local data = { self._onInvoke(unpack(packet)) }
				globalPacketOffset = writeInPacket(globalPackets, globalPacketOffset, self, data, true)
			else
				local player = packet[1]

				playerPackets[player] = playerPackets[player] or { b = buffer.create(BYTES_PER_FRAMES), offset = 0 }
				local targetBuffer = playerPackets[player].b
				local bOffset = playerPackets[player].offset

				local data = { self._onInvoke(unpack(packet)) }
				bOffset = writeInPacket(targetBuffer, bOffset, self, data, true)

				playerPackets[player].offset = bOffset
			end
		end
	end
end

-- Changes the net to response net, like RemoteFunction
function class:Response(...)
	assert(not self._unreliable, `This net ({self.Name}) is a unreliable net, you can't set it to a response net.`)

	self._response = true
	self._timeout = DEFAULT_TIMEOUT

	self._eventListeners = nil
	self._eventListenerCount = nil

	self._responseDataTypes = { ... }

	return self
end

-- Set response net with a timeout, by default, it will be a 5 seconds.
function class:WithTimeout(timeout)
	assert(self._response, `This net ({self.Name}) is not a response net, you can't set it with a timeout.`)
	assert(typeof(timeout) == "number", `Expected to have number for timeout, but got {typeof(timeout)}.`)

	self._timeout = timeout

	return self
end

-- Changes the net to unreliable net, like UnreliableRemoteEvent
function class:Unreliable()
	assert(not self._response, `This net ({self.Name}) is a response net, you can't set it to a unreliable net.`)

	self._unreliable = true

	return self
end

function class:Fire(player, ...)
	if not player or typeof(player) ~= "Instance" or not player:IsA("Player") then
		error(
			`On firing client, but player parameter is not a player, got {typeof(player) == "Instance" and player.ClassName or player}.`
		)
	end

	local isNetUnreliable = self._unreliable

	local thisPlayersPacket = setPlayersPacket(player, isNetUnreliable)
	local b = isNetUnreliable and thisPlayersPacket.unreliB or thisPlayersPacket.b
	local offset = isNetUnreliable and thisPlayersPacket.unreliOffset or thisPlayersPacket.offset

	local datas = { ... }

	local newOffset = writeInPacket(b, offset, self, datas)

	if isNetUnreliable then
		thisPlayersPacket.unreliOffset = newOffset
	else
		thisPlayersPacket.offset = newOffset
	end
end

function class:FireAll(...)
	local datas = { ... }

	if self._unreliable then
		unreliPacketOffset = writeInPacket(unreliablePackets, unreliPacketOffset, self, datas)
	else
		globalPacketOffset = writeInPacket(globalPackets, globalPacketOffset, self, datas)
	end
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

	return newConnection(function()
		link.previous.next = link.next
		link.next.previous = link.previous
		table.clear(link)
		end)
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

		return newConnection(function()
			link.previous.next = link.next
			link.next.previous = link.previous
			table.clear(link)
		end)
	end

	return
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

	unreliableRemote = Instance.new("UnreliableRemoteEvent")
	unreliableRemote.Parent = script

	playerPackets = {}

	RunService.Heartbeat:Connect(processPacketsToClient)

	unreliableRemote.OnServerEvent:Connect(function(player, packet)
		onPacketReceived(packet, player)
	end)
	remote.OnServerEvent:Connect(function(player, packet)
		onPacketReceived(packet, player)
	end)
else
	remote = script:WaitForChild("RemoteEvent")
	unreliableRemote = script:WaitForChild("UnreliableRemoteEvent")

	unreliableRemote.OnClientEvent:Connect(onPacketReceived)
	remote.OnClientEvent:Connect(onPacketReceived)
	RunService.Heartbeat:Connect(processPacketsToServer)
end

export type Net = {
	DataTypes: DataTypes.List,
	Schema: Schema.Schema,

	_id: number,
	_dataTypes: { DataTypes.DataType },
	_responseDataTypes: { DataTypes.DataType },

	_eventListeners: { () -> () },
	_eventListenerCount: number,

	_queuedPackets: { any },
	_packetsDropped: number,
	_nextPacketDropWarn: number?,

	_response: boolean?,
	_unreliable: boolean?,

	_waitingForResponse: thread?,
	_timeoutHandler: thread?,
	_onInvoke: (...any) -> ...any?,
	_timeout: number?,

	-- constructors
	new: (netName: string, ...DataTypes.DataType) -> Net,
	Response: (self: Net, ...DataTypes.DataType) -> Net,
	WithTimeout: (self: Net, timeout: number) -> Net,
	Unreliable: (self: Net) -> Net,

	-- speaker methods
	Fire: (self: Net, player: Player, ...any) -> (),
	FireAll: (self: Net, ...any) -> (),

	InvokeClient: (self: Net, player: Player, ...any) -> (Player, ...any) | nil,
	InvokeServer: (self: Net, ...any) -> (...any | nil),
	OnInvoke: (self: Net, func: () -> ()) -> (),

	-- listen methods
	Connect: (self: Net, func: (...any) -> ()) -> Connection,
	Once: (self: Net, func: (...any) -> ()) -> Connection?,
	Wait: (self: Net) -> ...any,
}

export type Connection = {
	Disconnect: ( self: Connection ) -> (),
}

return class
