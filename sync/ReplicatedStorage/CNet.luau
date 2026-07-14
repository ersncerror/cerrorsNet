--[[

	CNet, Version 1.1

	CNet is a roblox static network library.
	Github repository: https://github.com/ersncerror/cerrorsNet
	Written by Github/@ersncerror.

MIT License

Copyright (c) 2026 ersn_cerror

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

]]

type ResponseData = {
	invokeSucceed: boolean?,
	invokeId: number,
	generation: number,
}

-- services
local RunService = game:GetService("RunService")

-- modules
local DataTypes = require(script.DataTypes)
local Schema = require(script.Classes.Schema)
local Invoker = require(script.Classes.Invoker)
local Packet = require(script.Classes.Packet)
local Configuration = require(script.Configuration)
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
local BYTES_PER_FRAME = Configuration.BYTES_PER_FRAME
local MAX_QUEUED_PACKETS = Configuration.MAX_QUEUED_PACKETS
local MAX_CACHE_PACKETS = Configuration.MAX_CACHE_PACKETS

local DEFAULT_TIMEOUT = Configuration.DEFAULT_TIMEOUT
local MAX_PENDING_INVOKES = Configuration.MAX_PENDING_INVOKES

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

local function getIdForInvoker(array: { Invoker }): number?
	local index = 1
	while index ~= MAX_PENDING_INVOKES do
		if not array[index] or array[index]._solved then
			break
		end

		index += 1
	end

	if index == MAX_PENDING_INVOKES then
		return nil
	end

	return index
end

-- Net work related --

local function disconnect(self: Connection)
	self._previous._next = self._next
	self._next._previous = self._previous
	task.defer(table.clear, self)
end

local function queuePacket(self: Net, packet: { any }, responseData: ResponseData?)
	if #self._queuedPackets > MAX_QUEUED_PACKETS then
		if #self._queuedPackets % 4294967296 == 0 then
			warn(
				`[CNet]: Net "{self.Name}"'s queued packets overflowed, did you just forget to connect? ({#self._queuedPackets} packets dropped.)`
			)
		end

		return
	end

	table.insert(self._queuedPackets, { packet = packet, responseData = responseData })
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

local function readResponseData(packet: Packet, offset: number): ResponseData
	local datas = {}

	local byte = readu8(packet.b, offset + 1)

	datas.invokeId = readu8(packet.b, offset)

	datas.invokeSucceed = byte >= 128

	if datas.invokeSucceed then
		byte = byte - 128
	end

	datas.generation = byte

	return datas
end

local function writeResponseData(packet: Packet, datas: ResponseData)
	local succeed = datas.invokeSucceed
	local generation = datas.generation

	local byte = succeed and 128 or 0

	byte += generation

	writeu8(packet.b, packet.offset, datas.invokeId)
	writeu8(packet.b, packet.offset + 1, byte)
	packet.offset += 2
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
	estimatePacket.offset = 0

	for index, dataType in dataTypes do
		dataType.write(estimatePacket, datas[index])
	end

	return estimatePacket.offset --+ 1
end

local function writePacketInfo(
	self: Net,
	packetToWrite: Packet,
	datas: { any },
	dataTypes: { DataType },
	responseData: ResponseData?
)
	if #datas ~= #dataTypes then
		warn(`[CNet]: Possibly bug detected. Expect to write {#dataTypes} datas, but have {#datas} datas to write.`)
		return
	end

	local baseInfoSizeRequired = 3 + (self._response and 2 or 0)
	local size = estimateDataSize(datas, dataTypes)

	if packetToWrite.offset + baseInfoSizeRequired + size >= BYTES_PER_FRAME then
		warn(
			`[CNet]: Packet is too large and cannot write, {baseInfoSizeRequired + size} bytes is required, spaces left {BYTES_PER_FRAME - packetToWrite.offset} bytes.`
		)
		return
	end

	writeu8(packetToWrite.b, packetToWrite.offset, self._id) -- 1b
	writeu16(packetToWrite.b, packetToWrite.offset + 1, size) -- 2b
	packetToWrite.offset += 3

	if self._response and responseData then
		writeResponseData(packetToWrite, responseData)
	end
end

local function writeOneWayPacketWithMessageCatcher(
	self: Net,
	packetToWrite: Packet,
	datas: { DataType? },
	dataTypes: { DataType }
)
	local beforeWriteOffset = packetToWrite.offset

	writePacketInfo(self, packetToWrite, datas, self._dataTypes)
	local success, errormsg = packetToWrite:Write(datas, dataTypes)

	if not success then
		warn(`[CNet]: Failed to write datas into packet. Message catched: {errormsg}`)
		-- revert back
		packetToWrite.offset = beforeWriteOffset
	end
end

-- read packet related --
local function cachePacketToUnreadyNet(netId: number, packetToCache: buffer)
	cachedPackets[netId] = cachedPackets[netId] or {}

	if #cachedPackets[netId] > MAX_CACHE_PACKETS then
		packetDropCounters[netId] = packetDropCounters[netId] or 0
		packetDropCounters[netId] += 1

		if 4294967296 % packetDropCounters[netId] == 0 then
			warn(
				`[CNet]: Cached packets overflowed, did you just forget to create a net with id of "{netId}"? ({packetDropCounters[netId]} packets dropped.)`
			)
		end

		return
	end

	packetDropCounters[netId] = nil
	table.insert(cachedPackets[netId], packetToCache)
end

local function unserialize(packet: Packet, offset: number, dataTypes: { DataType }): (any | string, number | string)
	local result = {}

	for _, dataType in dataTypes do
		local pcallResult = table.pack(pcall(dataType.read, packet, offset))
		local success = pcallResult[1]

		if not success then
			warn(`[CNet]: Unserialize failed, message catched: {pcallResult[2]}`)
			return "Failed", pcallResult[2]
		end

		local value, increased = pcallResult[2], pcallResult[3]
		table.insert(result, value)
		offset += increased
	end

	return result, offset
end

local function handleResponsePacket(self: Net, datas: { any }, responseData: ResponseData, player: Player?)
	local invokeSuccess = responseData.invokeSucceed
	local invokeId = responseData.invokeId
	local generation = responseData.generation

	local invoker = self._pendingInvokes[invokeId]
	if invoker and invoker._generation == generation then
		if invoker._solved then
			return
		end

		invoker:_callSolver(invokeSuccess and Invoker.success or Invoker.failed, unpack(datas))
		self._pendingInvokes[invokeId] = { _solved = true, _generation = generation }
	else
		-- response the invoke caller

		if player then
			setPlayerPacket(player)
			table.insert(datas, 1, player)
		end

		if not self._onInvoke then
			queuePacket(self, datas, responseData)
			return
		end

		local results = table.pack(pcall(self._onInvoke, unpack(datas)))
		local success = results[1]
		local responseDatas = table.clone(results)
		table.remove(responseDatas, 1)

		if not success then
			warn(`[CNet]: Failed to get response from invoke handler. message catched: {results[2]}`)
			writePacketInfo(self, player and playerPackets[player].stable or globalPackets, {}, {}, invokeId)
			return
		end

		writePacketInfo(
			self,
			player and playerPackets[player].stable or globalPackets,
			responseDatas,
			self._responseDataTypes,
			{ invokeId = invokeId, invokeSucceed = success, generation = generation }
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

	if typeof(b) ~= "buffer" then
		return
	end

	if lenb(b) > BYTES_PER_FRAME + 1 then
		return
	end

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
			if not isClient then
				-- if we are server, then we can't trust client easily
				-- due to client can pass a incorrect length and a invalid net.
				warn(
					`[CNet]: Possibly exploiter detected, {player} was attempting to send packets to a non-exists net with id of {netId}.`
				)
				return
			end

			local packetToCache = buffer.create(length)
			copyb(packetToCache, 0, b, offset, length)
			cachePacketToUnreadyNet(netId, packetToCache)

			offset += length
			netId = readu8(b, offset)
			continue
		end

		-- unserialize packet
		local readers
		local newOffset

		if net._response then
			local responseData = readResponseData(packet, offset)
			local invokeId = responseData.invokeId
			local isInvokeSuccess = responseData.invokeSucceed

			local datas

			readers = (net._response and net._pendingInvokes[invokeId]) and net._responseDataTypes or net._dataTypes
			offset += 2

			if net._pendingInvokes[invokeId] and not isInvokeSuccess then
				newOffset = offset
			else
				local unserialized = { unserialize(packet, offset, readers) }
				datas = unserialized[1]
				newOffset = unserialized[2]
			end

			if datas == "Failed" then
				offset += length
			else
				handleResponsePacket(net, datas, responseData, player)
			end
		else
			readers = net._dataTypes

			local datas, nOffset = unserialize(packet, offset, readers)

			if datas ~= "Failed" then
				newOffset = nOffset

				if player then
					table.insert(datas, 1, player)
				end

				sendToListeners(net, datas)
			else
				offset += length
			end
		end

		if newOffset then
			offset = newOffset
		end

		-- continue to next packet
		netId = readu8(b, offset)
	end
end

-- Net function/methods --

function class.new(name, ...)
	assert(
		typeof(name) == "string",
		`[CNet]: Could not construct a new net object with a non-string identifier. Got value of type {typeof(name)}.`
	)

	if nets[name] then
		return nets[name]
	end

	local self = setmetatable({}, class)

	self.Name = name
	self._dataTypes = { ... }

	for _, dataType in self._dataTypes do
		local write = dataType.write
		local read = dataType.read

		assert(
			typeof(write) == "function",
			`[CNet]: Constructing a net object, but invalid data type was found. {dataType} was provided a non-function member of "write".`
		)

		assert(
			typeof(read) == "function",
			`[CNet]: Constructing a net object, but invalid data type was found. {dataType} was provided a non-function member of "read".`
		)
	end

	if isClient then
		if script:GetAttribute(name) then
			self._id = script:GetAttribute(name)
			netById[self._id] = self
			nets[self.Name] = self
		else
			local connect
			connect = script:GetAttributeChangedSignal(name):Connect(function()
				self._id = script:GetAttribute(name)
				netById[self._id] = self
				nets[self.Name] = self

				if self._id ~= nil then
					connect:Disconnect()
					connect = nil
				end
			end)
		end
	else
		self._id = idCounter
		netById[self._id] = self
		nets[self.Name] = self

		idCounter += 1
		script:SetAttribute(self.Name, self._id)
	end

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

	writeOneWayPacketWithMessageCatcher(self, packetToWrite, datas, self._dataTypes)
end

function class:FireAll(...)
	assert(
		not (isClient and not self._id),
		`Net "{self.Name}" does not have a id, it seems like you didn't setup a net on server. This is required.`
	)

	local datas = { ... }

	local packetToWrite = self._unstable and unstablePacket or globalPackets

	writeOneWayPacketWithMessageCatcher(self, packetToWrite, datas, self._dataTypes)
end

function class:Connect(func)
	assert(not self._response, `:Connect() is not availiable for response net, use :OnInvoke instead.`)

	local connection = {}
	connection._next = self._eventListeners
	connection._previous = self._eventListeners._previous
	connection.func = func
	connection.Disconnect = disconnect

	self._eventListeners._previous._next = connection
	self._eventListeners._previous = connection

	if #self._queuedPackets > 0 then
		for _, packet in self._queuedPackets do
			task.spawn(func, table.unpack(packet.packet))
		end
		table.clear(self._queuedPackets)
	end

	return connection
end

function class:Once(func)
	assert(not self._response, `:Once is not available for response net.`)

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
	assert(not self._response, `:Wait is not available for response net..`)

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
	self._pendingInvokes = {}

	return self
end

function class:WithTimeoutOf(timeout)
	assert(self._response, `[CNet]: Could not set timeout for a non-response Net. (Net name:"{self.Name}")`)
	assert(typeof(timeout) == "number", `[CNet]: Cannot set timeout with a value of type "{typeof(timeout)}".`)

	self._timeout = timeout

	return self
end

function class:InvokeServer(...)
	local id = getIdForInvoker(self._pendingInvokes)

	if not id then
		error(`[CNet]: Pending invokes is fulled and cannot having more. ({MAX_PENDING_INVOKES} invokes pending)`)
	end

	local datas = { ... }

	self._pendingInvokes[id] = Invoker.new(self._timeout):Timeout(function()
		self._pendingInvokes[id] = { _solved = true, _generation = self._pendingInvokes[id]._generation }
	end)

	writePacketInfo(
		self,
		globalPackets,
		datas,
		self._dataTypes,
		{ generation = self._pendingInvokes[id]._generation, invokeId = id }
	)

	local success, errormsg = globalPackets:Write(datas, self._dataTypes)

	if not success then
		warn(`[CNet]: Failed to write datas into packet. Message catched: {errormsg}`)
	end

	return self._pendingInvokes[id]
end

function class:InvokeClient(player, ...)
	local id = getIdForInvoker(self._pendingInvokes)

	if not id then
		error(`[CNet]: Pending invokes is fulled and cannot having more. ({MAX_PENDING_INVOKES} invokes pending)`)
	end

	local datas = { ... }

	local plrPacket = setPlayerPacket(player)

	self._pendingInvokes[id] = Invoker.new(self._timeout):Timeout(function()
		self._pendingInvokes[id] = { _solved = true, _generation = self._pendingInvokes[id]._generation }
	end)

	writePacketInfo(
		self,
		plrPacket.stable,
		datas,
		self._dataTypes,
		{ generation = self._pendingInvokes[id]._generation, invokeId = id }
	)
	plrPacket.stable:Write(datas, self._dataTypes)

	return self._pendingInvokes[id]
end

function class:OnInvoke(func)
	assert(typeof(func) == "function", `Could not use {typeof(func)} as a invoke handler.`)

	self._onInvoke = func

	if #self._queuedPackets > 0 then
		for _, datas in self._queuedPackets do
			handleResponsePacket(self, datas.packet, datas.responseData)
		end
	end

	table.clear(self._queuedPackets)
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
	_queuedPackets: { { packet: { any }, responseData: ResponseData? } },

	-- unstable net properties
	_unstable: boolean?,

	-- response net properties
	_response: boolean?,
	_timeout: number?,
	_responseDataTypes: { DataType }?,
	_pendingInvokes: { [number]: Invoker },
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
