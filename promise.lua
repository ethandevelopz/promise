local pendingStatus = 'pending'
local fulfilledStatus = 'fulfilled'
local rejectedStatus = 'rejected'
local cancelledStatus = 'cancelled'
local promise = {}
promise.__index = promise
export type Promise = {
	status: string,
	values: {[number]: any}?,
	handlers: {any},
	cancelHooks: {() -> ()},
	consumers: number,
	parent: Promise?,
	andThen: (self: Promise, onFulfill: any, onReject: any) -> Promise,
	catch: (self: Promise, onReject: any) -> Promise,
	finally: (self: Promise, onFinally: any) -> Promise,
	cancel: (self: Promise) -> (),
	onCancel: (self: Promise, hook: () -> ()) -> (),
	isPending: (self: Promise) -> boolean,
	isFulfilled: (self: Promise) -> boolean,
	isRejected: (self: Promise) -> boolean,
	isCancelled: (self: Promise) -> boolean,
	await: (self: Promise) -> (boolean, ...any),
	expect: (self: Promise) -> ...any,
}

function promise.is(value: any): boolean
	return typeof(value) == 'table' and getmetatable(value) == promise
end

local function getThenable(value: any): ((onFulfill: (...any) -> (), onReject: (...any) -> ()) -> ())?
	if promise.is(value) then
		return nil
	end

	local kind = typeof(value)
	if kind == 'function' then
		return function(onFulfill, onReject)
			value(onFulfill, onReject)
		end
	end

	if kind ~= 'table' and kind ~= 'userdata' then
		return nil
	end

	local ok, thenField = pcall(function()
		return (value :: any).andThen
	end)

	if not ok or typeof(thenField) ~= 'function' then
		return nil
	end

	return function(onFulfill, onReject)
		thenField(value, onFulfill, onReject)
	end
end

local function isThenable(value: any): boolean
	return getThenable(value) ~= nil
end

local function toPromise(value: any): Promise
	if promise.is(value) then
		return value
	end

	return promise.resolve(value)
end

function promise.new(executor: (resolve: (...any) -> (), reject: (...any) -> (), onCancel: (hook: () -> ()) -> ()) -> ()): Promise
	local self = setmetatable({}, promise) :: any
	self.status = pendingStatus
	self.values = nil
	self.handlers = {}
	self.cancelHooks = {}
	self.consumers = 0
	self.parent = nil
	local settled = false

	local function settle(status: string, ...: any)
		if settled or self.status == cancelledStatus then
			return
		end

		settled = true
		self.status = status
		self.values = table.pack(...)
		local handlers = self.handlers
		self.handlers = {}
		self.cancelHooks = {}
		if #handlers > 0 then
			task.spawn(function()
				for _, handler in handlers do
					self:dispatch(handler)
				end
			end)
		end
	end

	local function resolve(...: any)
		if settled or self.status == cancelledStatus then
			return
		end

		local count = select('#', ...)
		if count == 1 then
			local value = ...
			if value == self then
				settle(rejectedStatus, 'promise resolved with itself')
				return
			end

			if promise.is(value) then
				if value.status == pendingStatus then
					self:onCancel(function()
						value:cancel()
					end)
				end

				value:andThen(function(...)
					settle(fulfilledStatus, ...)
				end, function(...)
					settle(rejectedStatus, ...)
				end)
				return
			end

			local thenHandler = getThenable(value)
			if thenHandler then
				local resolvedOnce = false

				local function guard(status: string)
					return function(...)
						if resolvedOnce then
							return
						end
						resolvedOnce = true
						settle(status, ...)
					end
				end

				local ok, err = pcall(thenHandler, guard(fulfilledStatus), guard(rejectedStatus))
				if not ok and not resolvedOnce then
					resolvedOnce = true
					settle(rejectedStatus, err)
				end
				return
			end
		end

		settle(fulfilledStatus, ...)
	end

	local function reject(...: any)
		settle(rejectedStatus, ...)
	end

	local ok, err = pcall(executor, resolve, reject, function(hook: () -> ())
		self:onCancel(hook)
	end)

	if not ok and not settled and self.status ~= cancelledStatus then
		reject(err)
	end

	return self
end

function promise.dispatch(self: Promise, handler: any)
	local target = self :: any
	if target.status == fulfilledStatus then
		if handler.onFulfill then
			local packed = table.pack(pcall(handler.onFulfill, table.unpack(target.values, 1, target.values.n)))
			if packed[1] then
				handler.resolve(table.unpack(packed, 2, packed.n))
			else
				handler.reject(packed[2])
			end
		else
			handler.resolve(table.unpack(target.values, 1, target.values.n))
		end
	elseif target.status == rejectedStatus then
		if handler.onReject then
			local packed = table.pack(pcall(handler.onReject, table.unpack(target.values, 1, target.values.n)))
			if packed[1] then
				handler.resolve(table.unpack(packed, 2, packed.n))
			else
				handler.reject(packed[2])
			end
		else
			handler.reject(table.unpack(target.values, 1, target.values.n))
		end
	end
end

function promise.andThen(self: Promise, onFulfill: any, onReject: any): Promise
	local parent = self :: any
	local handler
	local child = promise.new(function(resolve, reject, onCancel)
		if parent.status == pendingStatus then
			handler = {onFulfill = onFulfill, onReject = onReject, resolve = resolve, reject = reject}
			table.insert(parent.handlers, handler)
			parent.consumers += 1
			onCancel(function()
				if parent.status == pendingStatus then
					local index = table.find(parent.handlers, handler)
					if index then
						table.remove(parent.handlers, index)
					end

					parent:releaseConsumer()
				end
			end)
		else
			task.spawn(function()
				parent:dispatch({onFulfill = onFulfill, onReject = onReject, resolve = resolve, reject = reject})
			end)
		end
	end)

	if handler then
		handler.child = child;
		(child :: any).parent = parent
	end

	return child
end

function promise.releaseConsumer(self: Promise)
	local target = self :: any
	target.consumers -= 1
	if target.consumers <= 0 and target.status == pendingStatus then
		target:cancel()
	end
end

function promise.cancel(self: Promise)
	local target = self :: any
	if target.status ~= pendingStatus then
		return
	end

	target.status = cancelledStatus
	target.values = table.pack('promise cancelled')
	local hooks = target.cancelHooks
	target.cancelHooks = {}
	for _, hook in hooks do
		pcall(hook)
	end

	local handlers = target.handlers
	target.handlers = {}
	target.consumers = 0
	for _, handler in handlers do
		if handler.child then
			handler.child:cancel()
		end
	end
end

function promise.onCancel(self: Promise, hook: () -> ())
	local target = self :: any
	if target.status == cancelledStatus then
		task.spawn(hook)
	elseif target.status == pendingStatus then
		table.insert(target.cancelHooks, hook)
	end
end

function promise.catch(self: Promise, onReject: any): Promise
	return self:andThen(nil, onReject)
end

function promise.finally(self: Promise, onFinally: (() -> ...any)?): Promise
	local child = self:andThen(function(...)
		local passthrough = table.pack(...)
		local result = onFinally and onFinally()
		if promise.is(result) or isThenable(result) then
			return toPromise(result):andThen(function()
				return table.unpack(passthrough, 1, passthrough.n)
			end)
		end

		return table.unpack(passthrough, 1, passthrough.n)
	end, function(...)
		local passthrough = table.pack(...)
		local result = onFinally and onFinally()
		if promise.is(result) or isThenable(result) then
			return toPromise(result):andThen(function()
				return promise.reject(table.unpack(passthrough, 1, passthrough.n))
			end)
		end

		return promise.reject(table.unpack(passthrough, 1, passthrough.n))
	end)

	child:onCancel(function()
		if onFinally then
			pcall(onFinally)
		end
	end)

	return child
end

function promise.isPending(self: Promise): boolean
	return (self :: any).status == pendingStatus
end

function promise.isFulfilled(self: Promise): boolean
	return (self :: any).status == fulfilledStatus
end

function promise.isRejected(self: Promise): boolean
	return (self :: any).status == rejectedStatus
end

function promise.isCancelled(self: Promise): boolean
	return (self :: any).status == cancelledStatus
end

function promise.await(self: Promise): (boolean, ...any)
	local target = self :: any
	if target.status == fulfilledStatus then
		return true, table.unpack(target.values, 1, target.values.n)
	elseif target.status == rejectedStatus or target.status == cancelledStatus then
		return false, table.unpack(target.values, 1, target.values.n)
	end

	local co = coroutine.running()
	local resumed = false

	local function finish(ok: boolean, ...: any)
		if resumed then
			return
		end
		resumed = true
		task.spawn(co, ok, ...)
	end

	local waiter = self:andThen(function(...)
		finish(true, ...)
	end, function(...)
		finish(false, ...)
	end)

	waiter:onCancel(function()
		finish(false, 'promise cancelled')
	end)

	return coroutine.yield()
end

function promise.expect(self: Promise): ...any
	local packed = table.pack(self:await())
	if not packed[1] then
		error(packed[2], 0)
	end

	return table.unpack(packed, 2, packed.n)
end

function promise.resolve(...: any): Promise
	local args = table.pack(...)
	return promise.new(function(resolve)
		resolve(table.unpack(args, 1, args.n))
	end)
end

function promise.reject(...: any): Promise
	local args = table.pack(...)
	return promise.new(function(_, reject)
		reject(table.unpack(args, 1, args.n))
	end)
end

function promise.all(list: {any}): Promise
	if typeof(list) ~= 'table' then
		error('promise.all expects an array of promises', 0)
	end

	return promise.new(function(resolve, reject, onCancel)
		local total = #list
		if total == 0 then
			resolve({})
			return
		end

		local results = table.create(total)
		local subscriptions = table.create(total)
		local remaining = total
		local done = false
		local registering = true
		local deferredReject: {any}?

		local function releaseAll()
			for index = 1, total do
				local subscription = subscriptions[index]
				if subscription then
					subscription:cancel()
				end
			end
		end

		onCancel(function()
			done = true
			releaseAll()
		end)

		for index, raw in list do
			local item = toPromise(raw)
			subscriptions[index] = item:andThen(function(...)
				if done then
					return
				end

				results[index] = table.pack(...)
				remaining -= 1
				if remaining == 0 then
					done = true
					if not registering then
						resolve(results)
					end
				end
			end, function(...)
				if done then
					return
				end

				done = true
				if registering then
					deferredReject = table.pack(...)
					return
				end

				releaseAll()
				reject(...)
			end)
		end

		registering = false
		if deferredReject then
			releaseAll()
			reject(table.unpack(deferredReject, 1, deferredReject.n))
		elseif done and remaining == 0 then
			resolve(results)
		end
	end)
end

function promise.race(list: {any}): Promise
	if typeof(list) ~= 'table' then
		error('promise.race expects an array of promises', 0)
	end

	return promise.new(function(resolve, reject, onCancel)
		local total = #list
		local subscriptions = table.create(total)
		local done = false
		local registering = true
		local deferredSettleFn: ((...any) -> ())?
		local deferredValues: {any}?

		local function releaseAll()
			for index = 1, total do
				local subscription = subscriptions[index]
				if subscription then
					subscription:cancel()
				end
			end
		end

		local function finish(settleFn: (...any) -> (), ...: any)
			if done then
				return
			end

			done = true
			if registering then
				deferredSettleFn = settleFn
				deferredValues = table.pack(...)
				return
			end

			releaseAll()
			settleFn(...)
		end

		onCancel(function()
			finish(function() end)
		end)

		for index, raw in list do
			local item = toPromise(raw)
			subscriptions[index] = item:andThen(function(...)
				finish(resolve, ...)
			end, function(...)
				finish(reject, ...)
			end)
		end

		registering = false
		if deferredSettleFn then
			releaseAll()
			deferredSettleFn(table.unpack(deferredValues :: {any}, 1, (deferredValues :: any).n))
		end
	end)
end

function promise.allSettled(list: {any}): Promise
	if typeof(list) ~= 'table' then
		error('promise.allSettled expects an array of promises', 0)
	end

	return promise.new(function(resolve, _, onCancel)
		local total = #list
		if total == 0 then
			resolve({})
			return
		end

		local results = table.create(total)
		local subscriptions = table.create(total)
		local remaining = total

		onCancel(function()
			for index = 1, total do
				local subscription = subscriptions[index]
				if subscription then
					subscription:cancel()
				end
			end
		end)

		for index, raw in list do
			local item = toPromise(raw)
			subscriptions[index] = item:andThen(function(...)
				results[index] = {status = fulfilledStatus, values = table.pack(...)}
				remaining -= 1
				if remaining == 0 then
					resolve(results)
				end
			end, function(...)
				results[index] = {status = rejectedStatus, values = table.pack(...)}
				remaining -= 1
				if remaining == 0 then
					resolve(results)
				end
			end)
		end
	end)
end

function promise.any(list: {any}): Promise
	if typeof(list) ~= 'table' then
		error('promise.any expects an array of promises', 0)
	end

	return promise.new(function(resolve, reject, onCancel)
		local total = #list
		if total == 0 then
			reject('promise.any received an empty list')
			return
		end

		local errors = table.create(total)
		local subscriptions = table.create(total)
		local remaining = total
		local done = false
		local registering = true
		local winnerIndex: number?
		local winnerValues: {any}?
		local deferredReject = false

		local function releaseAll(exceptIndex: number?)
			for index = 1, total do
				if index ~= exceptIndex then
					local subscription = subscriptions[index]
					if subscription then
						subscription:cancel()
					end
				end
			end
		end

		onCancel(function()
			done = true
			releaseAll()
		end)

		for index, raw in list do
			local item = toPromise(raw)
			subscriptions[index] = item:andThen(function(...)
				if done then
					return
				end

				done = true
				if registering then
					winnerIndex = index
					winnerValues = table.pack(...)
					return
				end

				releaseAll(index)
				resolve(...)
			end, function(...)
				if done then
					return
				end

				errors[index] = table.pack(...)
				remaining -= 1
				if remaining == 0 then
					done = true
					if registering then
						deferredReject = true
						return
					end
					reject(errors)
				end
			end)
		end

		registering = false
		if winnerIndex then
			releaseAll(winnerIndex)
			resolve(table.unpack(winnerValues :: {any}, 1, (winnerValues :: any).n))
		elseif deferredReject then
			reject(errors)
		end
	end)
end

function promise.delay(seconds: number): Promise
	return promise.new(function(resolve, _, onCancel)
		local thread = task.delay(seconds, resolve)
		onCancel(function()
			task.cancel(thread)
		end)
	end)
end

function promise.timeout(self: Promise, seconds: number, reason: any?): Promise
	return promise.new(function(resolve, reject, onCancel)
		local settled = false
		local timer = promise.delay(seconds)

		local subscription = self:andThen(function(...)
			if settled then
				return
			end

			settled = true
			timer:cancel()
			resolve(...)
		end, function(...)
			if settled then
				return
			end

			settled = true
			timer:cancel()
			reject(...)
		end)

		timer:andThen(function()
			if settled then
				return
			end

			settled = true
			subscription:cancel()
			self:cancel()
			reject(reason or 'promise timed out')
		end)

		onCancel(function()
			settled = true
			timer:cancel()
			subscription:cancel()
			self:cancel()
		end)
	end)
end

function promise.retry(fn: (...any) -> ...any, attempts: number, waitSeconds: number?): Promise
	return promise.new(function(resolve, reject, onCancel)
		if typeof(attempts) ~= 'number' or attempts <= 0 then
			reject('promise.retry requires attempts >= 1')
			return
		end

		local cancelled = false
		local activeDelay: Promise?

		onCancel(function()
			cancelled = true
			if activeDelay then
				(activeDelay :: any):cancel()
			end
		end)

		local function attempt(tries: number)
			if cancelled then
				return
			end

			local packed = table.pack(pcall(fn))
			if packed[1] then
				resolve(table.unpack(packed, 2, packed.n))
				return
			end

			if cancelled then
				return
			end

			if tries >= attempts then
				reject(packed[2])
				return
			end

			local delayPromise = promise.delay(waitSeconds or 0)
			activeDelay = delayPromise
			delayPromise:andThen(function()
				activeDelay = nil
				attempt(tries + 1)
			end)
		end

		attempt(1)
	end)
end

function promise.fromEvent(signal: any, predicate: ((...any) -> boolean)?): Promise
	return promise.new(function(resolve, reject, onCancel)
		local connection
		local disconnected = false

		local function disconnect()
			if disconnected then
				return
			end
			disconnected = true
			if connection then
				pcall(function()
					connection:Disconnect()
				end)
			end
		end

		local ok, connOrErr = pcall(function()
			return signal:Connect(function(...)
				if predicate and not predicate(...) then
					return
				end

				disconnect()
				resolve(...)
			end)
		end)

		if not ok then
			reject(connOrErr)
			return
		end

		connection = connOrErr
		onCancel(disconnect)
	end)
end

return promise
