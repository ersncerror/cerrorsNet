type enum = {
	name: string,
	value: number,
}

type enumList = {
	success: enum,
	timeout: enum,
}

local enums = {
	["success"] = {
		name = "success",
		value = 1,
	},
	["timeout"] = {
		name = "timeout",
		value = 2,
	},
} :: enumList

local class = {} :: Invoker & enumList
class.__index = class

function class.new(timeout)
	local self = setmetatable({}, class)
	self._solved = false
	self._solvers = {}

	if timeout then
		self._timeout = task.delay(timeout, self._callSolver, self, enums.timeout)
	end

	return self
end

function class:_callSolver(solver, ...)
	if self._solved then
		if self._timeout and coroutine.status(self._timeout) ~= "running" then
			coroutine.close(self._timeout)
		end

		return
	end

	if not self._solvers[solver.value] then
		return
	end

	task.spawn(self._solvers[solver.value], ...)
	self._solved = true
end

function class:Success(fn)
	assert(typeof(fn) == "function", `[Invoker]: Parameter 1 is not a function. (got {typeof(fn)})`)

	self._solvers[enums.success.value] = fn

	return self
end

function class:Timeout(fn)
	assert(typeof(fn) == "function", `[Invoker]: Parameter 1 is not a function. (got {typeof(fn)})`)

	self._solvers[enums.timeout.value] = fn

	return self
end

-- cancels the invoke, if response is received, nothing will happen.
function class:Cancel()
	if self._timeout then
		task.cancel(self._timeout)
	end

	self._solved = true
end

for name, enum in enums do
	class[name] = enum
end

export type Invoker = {
	_solved: boolean,
	_timeout: thread?,
	_solvers: { [enum]: (...any) -> () },

	new: (timeout: number?) -> Invoker,

	_callSolver: (self: Invoker, solver: enum, ...any) -> (),

	InvokeSuccess: (self: Invoker, fn: (...any) -> ()) -> Invoker,
	Timeout: (self: Invoker, fn: (...any) -> ()) -> Invoker,
	Cancel: (self: Invoker) -> (),
}

return class
