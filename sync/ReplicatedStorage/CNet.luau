local RunService = game:GetService("RunService")

-- modules
local DataTypes = require(script.DataTypes)
local Schema = require(script.Schema)
local Invoker = require(script.Invoker)
local Packet = require(script.Packet)
local types = require(script._types)

-- types
type Packet = types.Packet
type Invoker = Invoker.Invoker
type DataType = types.DataType
type playerPacket = { stable: Packet, unstable: Packet? }

-- luau functions
local writeu8 = buffer.writeu8
local writeu16 = buffer.writeu16
local readu8 = buffer.readu8
local readu16 = buffer.readu16

local copyb = buffer.copy
local lenb = buffer.len

-- instances
local remoteEvent: RemoteEvent
local unreliRemoteEvent: UnreliableRemoteEvent

-- variables
local DEFAULT_TIMEOUT = 5 -- when net is changed to response, before :WithTimeoutOf call.
local BYTES_PER_FRAME = 2048
local MAX_QUEUED_PACKETS = 128 -- this is for nets if they don't have listeners.
local MAX_CACHE_PACKETS = 64 -- this is for nets if they aren't registered.

local isClient = RunService:IsClient()

local idCounter = 1

-- packets
local estimatePacket = Packet.new(BYTES_PER_FRAME)
local globalPackets = Packet.new(BYTES_PER_FRAME)
local unstablePacket = Packet.new(BYTES_PER_FRAME)

local playerPackets = {} :: { [Player]: playerPacket }

-- > tables
local nets = {} :: { [string]: Net }
local netById = {} :: { [number]: Net }

local cachedPackets = {} :: { [number]: { { packet: Packet, player: Player? } } }
local packetDropCounters = {} :: { [number]: number }

local class = {} :: Net
class.__index = class

-- Net work related --
local function disconnect(self: Connection)
	self._previous._next = self._next
	self._next._previous = self._previous
	task.defer(table.clear, self)
end

local function queuePacket(self: Net, packet: { any })
	if #self._queuedPackets > MAX_QUEUED_PACKETS then
		if #self._queuedPackets % 4294967296 == 0 then
			warn(
				`[CNet]: Net "{self.Name}"'s queued packets overflowed, did you just forget to connect? ({#self._queuedPackets} packets dropped.)`
			)
		end

		return
	end

	table.insert(self._queuedPackets, packet)
end

local function sendToListeners(self: Net, packet: { any })
	if self._eventListeners._next == self._eventListeners then
		queuePacket(self, packet)
		return
	end

	local connection = self._eventListeners._next :: Connection

	while connection ~= self._eventListeners do
		if connection.func then
			task.spawn(connection.func, unpack(packet))
		elseif connection.thread then
			task.spawn(connection.thread, unpack(packet))
			connection:Disconnect()
		end

		connection = connection._next
	end
end

-- write packet related --
local function abstractPacket(packet: Packet): (buffer, { Instance })
	local abstractedBuffer = buffer.create(packet.offset + 1)
	copyb(abstractedBuffer, 0, packet.b, 0, packet.offset)

	return abstractedBuffer, packet.refs
end

local function setPlayerPacket(player: Player, unreli: boolean?): playerPacket
	playerPackets[player] = playerPackets[player]
		or {
			stable = Packet.new(BYTES_PER_FRAME),
			unstable = unreli and Packet.new(BYTES_PER_FRAME) or nil,
		}

	return playerPackets[player]
end

local function estimateDataSize(datas: { any }, dataTypes: { DataType })
	local size = 0

	for index, dataType in dataTypes do
		size += dataType.write(estimatePacket, datas[index]) or dataType.bytes
	end

	estimatePacket.offset = 0
	return size
end

local function writePacketInfo(self: Net, packetToWrite: Packet, datas: { any }, dataTypes: { DataType })
	local size = estimateDataSize(datas, dataTypes)

	if packetToWrite.offset + 3 + size >= BYTES_PER_FRAME then
		warn(
			`[CNet]: Not enough space to write! {3 + size} bytes is required, but only have space of {BYTES_PER_FRAME - packetToWrite.offset} bytes.`
		)
		return
	end

	writeu8(packetToWrite.b, packetToWrite.offset, self._id) -- 1b
	writeu16(packetToWrite.b, packetToWrite.offset + 1, size) -- 2b
	packetToWrite.offset += 3
end

-- read packet related --
local function cachePacketToUnreadyNet(netId: number, packetToCache: buffer)
	cachedPackets[netId] = cachedPackets[netId] or {}

	if #cachedPackets[netId] > MAX_CACHE_PACKETS then
		packetDropCounters[netId] = packetDropCounters[netId] or 0
		packetDropCounters[netId] += 1

		if packetDropCounters[netId] % 4294967296 == 0 then
			warn(
				`[CNet]: Cached packets overflowed, did you just forget to create a net with id of "{netId}"? ({packetDropCounters[netId]} packets dropped.)`
			)
		end

		return
	end

	packetDropCounters[netId] = nil
	table.insert(cachedPackets[netId], packetToCache)
end

local function unserialize(packet: Packet, offset: number, dataTypes: { DataType })
	local result = {}

	for _, dataType in dataTypes do
		local value, increased = dataType.read(packet, offset)
		table.insert(result, value)
		offset += increased or dataType.bytes
	end

	return result, offset
end

local function handleResponsePacket(self: Net, datas: { any }, player: Player?)
	if self._waitingForResponse then
		-- this is the invoke caller
		local invoker = self._waitingForResponse
		self._waitingForResponse = nil
		invoker:_callSolver(Invoker.success, unpack(datas))
	else
		-- response the invoke caller

		if player then
			setPlayerPacket(player)
			table.insert(datas, 1, player)
		end

		if not self._onInvoke then
			queuePacket(self, datas)
			return
		end

		local responseDatas = { self._onInvoke(unpack(datas)) }

		writePacketInfo(
			self,
			player and playerPackets[player].stable or globalPackets,
			responseDatas,
			self._responseDataTypes
		)

		if player then
			playerPackets[player].stable:Write(responseDatas, self._responseDataTypes)
		else
			globalPackets:Write(responseDatas, self._responseDataTypes)
		end
	end
end

-- main work related --
local function processPacketsToServer()
	if globalPackets.offset > 0 then
		remoteEvent:FireServer(abstractPacket(globalPackets))
		globalPackets = Packet.new(BYTES_PER_FRAME)
	end

	if unstablePacket.offset > 0 then
		unreliRemoteEvent:FireServer(abstractPacket(unstablePacket))
		unstablePacket = Packet.new(BYTES_PER_FRAME)
	end
end

local function processPacketsToClient()
	if globalPackets.offset > 0 then
		remoteEvent:FireAllClients(abstractPacket(globalPackets))
		globalPackets = Packet.new(BYTES_PER_FRAME)
	end

	if unstablePacket.offset > 0 then
		unreliRemoteEvent:FireAllClients(abstractPacket(unstablePacket))
		unstablePacket = Packet.new(BYTES_PER_FRAME)
	end

	for player, packets in playerPackets do
		if packets.stable.offset > 0 then
			remoteEvent:FireClient(player, abstractPacket(packets.stable))
		end

		if packets.unstable and packets.unstable.offset > 0 then
			unreliRemoteEvent:FireClient(player, abstractPacket(packets.unstable))
		end
	end

	table.clear(playerPackets)
end

local function onPacketReceived(b: buffer, refs: { Instance }, player: Player?)
	local offset = 0
	local packet = { b = b, refs = refs } :: Packet

	local netId = readu8(b, offset)
	while netId ~= 0 do
		local length = readu16(b, offset + 1)
		offset += 3

		if offset + length > lenb(b) then
			warn(
				`[CNet]: Malformed packet with length of {length}, exceeded buffer access bound. (bufferSize: {lenb(b)}, offset:{offset})`
			)
			break
		end

		local net = netById[netId] :: Net

		if not net then
			local packetToCache = buffer.create(length)
			copyb(packetToCache, 0, b, offset, length)
			cachePacketToUnreadyNet(netId, packetToCache)

			offset += length
			netId = readu8(b, offset)
			continue
		end

		-- unserialize packet
		local datas, newOffset = unserialize(packet, offset, net._dataTypes)
		offset = newOffset

		if net._response then
			handleResponsePacket(net, datas, player)
		else
			if player then
				table.insert(datas, 1, player)
			end

			sendToListeners(net, datas)
		end

		-- continue to next packet
		netId = readu8(b, offset)
	end
end

-- Net function/methods --

function class.new(name, ...)
	if nets[name] then
		return nets[name]
	end

	local self = setmetatable({}, class)

	self.Name = name
	self._dataTypes = { ... }

	self._id = script:GetAttribute(name) or idCounter
	idCounter += script:GetAttribute(name) and 0 or 1

	-- if network lags or other possible siuation to cause this problem
	-- could make this net have a id collision from a existed net.

	if netById[self._id] then
		-- reseparate id
		local collidedNet = netById[self._id] :: Net
		collidedNet._id = script:GetAttribute(collidedNet.Name) or idCounter
		idCounter += script:GetAttribute(collidedNet.Name) and 0 or 1

		netById[collidedNet._id] = collidedNet
	end

	netById[self._id] = self
	nets[self.Name] = self
	script:SetAttribute(self.Name, self._id)

	-- setup net works
	self._eventListeners = {}
	self._queuedPackets = {}

	self._eventListeners._next = self._eventListeners
	self._eventListeners._previous = self._eventListeners

	return self
end

-- un/stable methods

function class:Unstable()
	assert(not self._response, `[CNet]: Response net "{self.Name}" cannot be change to unstable net.`)
	self._unstable = true

	return self
end

function class:Fire(player, ...)
	assert(not isClient, `Fire is not supported on client, you should use :FireAll instead.`)
	assert(
		typeof(player) == "Instance",
		`Target to fire is a non-Instance value, got value of type "{typeof(player)}".`
	)
	assert(player:IsA("Player"), `Target to fire is a non-Player instance, got instance of class "{player.ClassName}".`)

	local datas = { ... }

	local plrPackets = setPlayerPacket(player, self._unstable)
	local packetToWrite = self._unstable and plrPackets.unstable or plrPackets.stable

	writePacketInfo(self, packetToWrite, datas, self._dataTypes)
	packetToWrite:Write(datas, self._dataTypes)
end

function class:FireAll(...)
	local datas = { ... }

	local packetToWrite = self._unstable and unstablePacket or globalPackets

	writePacketInfo(self, packetToWrite, datas, self._dataTypes)
	packetToWrite:Write(datas, self._dataTypes)
end

function class:Connect(func)
	local connection = {}
	connection._next = self._eventListeners
	connection._previous = self._eventListeners._previous
	connection.func = func
	connection.Disconnect = disconnect

	self._eventListeners._previous._next = connection
	self._eventListeners._previous = connection

	if #self._queuedPackets > 0 then
		for _, packet in self._queuedPackets do
			task.spawn(func, table.unpack(packet))
		end
	end

	return connection
end

function class:Once(func)
	local connection = {}
	connection._next = self._eventListeners
	connection._previous = self._eventListeners._previous
	connection.Disconnect = disconnect
	connection.func = function(...)
		connection:Disconnect()
		func(...)
	end

	self._eventListeners._previous._next = connection
	self._eventListeners._previous = connection

	return connection
end

function class:Wait()
	local connection = {}
	connection._next = self._eventListeners
	connection._previous = self._eventListeners._previous
	connection.thread = coroutine.running()
	connection.Disconnect = disconnect

	self._eventListeners._previous._next = connection
	self._eventListeners._previous = connection

	return coroutine.yield()
end

-- response methods
function class:Response(...)
	assert(not self._unstable, `[CNet]: Unstable net "{self.Name}" cannot be change to response net.`)

	self._response = true
	self._eventListeners = nil
	self._timeout = DEFAULT_TIMEOUT

	self._responseDataTypes = { ... }

	return self
end

function class:WithTimeoutOf(timeout)
	assert(self._response, `[CNet]: Could not set timeout for a non-response Net. (Name:"{self.Name}")`)
	assert(typeof(timeout) == "number", `[CNet]: Cannot set timeout with a value of type "{typeof(timeout)}".`)

	self._timeout = timeout

	return self
end

function class:InvokeServer(...)
	local datas = { ... }

	writePacketInfo(self, globalPackets, datas, self._dataTypes)
	globalPackets:Write(datas, self._dataTypes)

	self._waitingForResponse = Invoker.new(self._timeout)
	return self._waitingForResponse
end

function class:InvokeClient(player, ...)
	local datas = { ... }

	local plrPacket = setPlayerPacket(player)
	writePacketInfo(self, plrPacket.stable, datas, self._dataTypes)
	plrPacket.stable:Write(datas, self._dataTypes)

	self._waitingForResponse = Invoker.new(self._timeout)
	return self._waitingForResponse
end

function class:OnInvoke(func)
	assert(typeof(func) == "function", `Could not use {typeof(func)} as a invoke handler.`)

	self._onInvoke = func

	if #self._queuedPackets > 0 then
		for _, datas in self._queuedPackets do
			handleResponsePacket(self, datas)
		end
	end
end

-- Initialize --
class.Schema = Schema

for name, dataType in DataTypes do
	class[name] = dataType
end

if not isClient then
	remoteEvent = Instance.new("RemoteEvent")
	unreliRemoteEvent = Instance.new("UnreliableRemoteEvent")

	remoteEvent.Parent = script
	unreliRemoteEvent.Parent = script

	RunService.Heartbeat:Connect(processPacketsToClient)

	remoteEvent.OnServerEvent:Connect(function(player, packets, refs)
		onPacketReceived(packets, refs, player)
	end)

	unreliRemoteEvent.OnServerEvent:Connect(function(player, packets, refs)
		onPacketReceived(packets, refs, player)
	end)
else
	remoteEvent = script:WaitForChild("RemoteEvent")
	unreliRemoteEvent = script:WaitForChild("UnreliableRemoteEvent")

	RunService.Heartbeat:Connect(processPacketsToServer)

	remoteEvent.OnClientEvent:Connect(onPacketReceived)
	unreliRemoteEvent.OnClientEvent:Connect(onPacketReceived)
end

export type Connection = {
	_next: Connection,
	_previous: Connection,
	func: () -> ()?,
	thread: thread?,

	Disconnect: (self: Connection) -> (),
}

export type Net = {
	Schema: Schema.Schema,

	Name: string,

	-- main properties
	_id: number,
	_dataTypes: { DataType },

	-- stable net properties
	_eventListeners: Connection,
	_queuedPackets: { { any } },

	-- unstable net properties
	_unstable: boolean?,

	-- response net properties
	_response: boolean?,
	_timeout: number?,
	_waitingForResponse: Invoker?,
	_responseDataTypes: { DataType }?,
	_onInvoke: (...any) -> ...any,

	new: (name: string, ...DataType) -> Net,
	Response: (self: Net, ...DataType) -> Net,
	Unstable: (self: Net) -> Net,

	-- speakers
	Fire: (self: Net, player: Player, ...any) -> (),
	FireAll: (self: Net, ...any) -> (),

	InvokeServer: (self: Net, ...any) -> Invoker,
	InvokeClient: (self: Net, player: Player, ...any) -> Invoker,

	-- listeners
	Connect: (self: Net, func: (...any) -> ()) -> Connection,
	Once: (self: Net, func: (...any) -> ()) -> Connection,
	Wait: (self: Net) -> ...any,

	WithTimeoutOf: (self: Net, timeout: number) -> Net,
	OnInvoke: (self: Net, func: (...any) -> ...any) -> (),
} & DataTypes.List

return class
