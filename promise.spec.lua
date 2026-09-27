local promise = require(game.ReplicatedStorage.Promise)

local passed = 0
local failed = 0
local failedNames = {}

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print('PASS ' .. name)
	else
		failed += 1
		table.insert(failedNames, name)
		print('FAIL ' .. name .. ' -> ' .. tostring(err))
	end
end

test('pending to fulfilled carries all return values', function()
	local p = promise.new(function(resolve)
		resolve(1, 2, 3)
	end)
	local ok, a, b, c = p:await()
	check(ok and a == 1 and b == 2 and c == 3, 'expected fulfilled with 1,2,3')
end)

test('pending to rejected carries the reason', function()
	local p = promise.new(function(_, reject)
		reject('boom')
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'boom', 'expected rejected with boom')
end)

test('pending to cancelled reports cancelled', function()
	local p = promise.new(function() end)
	p:cancel()
	check(p:isCancelled(), 'expected cancelled status')
	local ok = p:await()
	check(not ok, 'expected await to report failure on cancel')
end)

test('double settlement only keeps the first', function()
	local p = promise.new(function(resolve, reject)
		resolve('first')
		reject('second')
		resolve('third')
	end)
	local ok, value = p:await()
	check(ok and value == 'first', 'expected only first resolve to win')
end)

test('cancelling one child does not cancel siblings or the parent', function()
	local parent = promise.new(function() end)
	local childA = parent:andThen(function() end)
	local childB = parent:andThen(function() end)
	childA:cancel()
	check(childA:isCancelled(), 'childA should be cancelled')
	check(parent:isPending(), 'parent should stay pending while childB still needs it')
	childB:cancel()
	task.wait()
	check(parent:isCancelled(), 'parent should auto cancel once every consumer is gone')
end)

test('cancellation during chaining stops downstream execution', function()
	local ran = false
	local parent = promise.new(function() end)
	local child = parent:andThen(function()
		ran = true
	end)
	child:cancel()
	parent:cancel()
	task.wait()
	check(not ran, 'downstream handler should never run after cancellation')
end)

test('cancellation during delay stops the timer', function()
	local p = promise.delay(5)
	p:cancel()
	check(p:isCancelled(), 'delay promise should be cancelled immediately')
end)

test('timeout cancels the original promise when the timer wins', function()
	local original = promise.new(function() end)
	local wrapped = original:timeout(0.05, 'too slow')
	local ok, reason = wrapped:await()
	check(not ok and reason == 'too slow', 'expected timeout rejection')
	check(original:isCancelled(), 'original should be cancelled once timeout wins')
end)

test('timeout cancels the timer when the original settles first', function()
	local original = promise.resolve('done')
	local wrapped = original:timeout(5, 'too slow')
	local ok, value = wrapped:await()
	check(ok and value == 'done', 'expected the original fulfillment to win')
end)

test('cancellation during fromEvent disconnects and never errors on double disconnect', function()
	local handlers = {}
	local fakeSignal = {
		Connect = function(_, handler)
			table.insert(handlers, handler)
			local connection = {}
			function connection.Disconnect()
			end
			return connection
		end,
	}
	local p = promise.fromEvent(fakeSignal)
	p:cancel()
	local ok = pcall(function()
		p:cancel()
	end)
	check(ok, 'cancelling twice should never error')
end)

test('thenable resolving twice only honors the first call', function()
	local calls = 0
	local thenable = {
		andThen = function(_, onFulfill, onReject)
			onFulfill('first')
			onReject('second')
			onFulfill('third')
			calls += 1
		end,
	}
	local p = promise.resolve(thenable)
	local ok, value = p:await()
	check(ok and value == 'first' and calls == 1, 'expected only the first resolution to count')
end)

test('function-based thenables are assimilated', function()
	local p = promise.resolve(function(resolve)
		resolve('assimilated')
	end)
	local ok, value = p:await()
	check(ok and value == 'assimilated', 'expected function thenable to resolve')
end)

test('finally throwing rejects the resulting promise', function()
	local p = promise.resolve('value'):finally(function()
		error('finally blew up', 0)
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'finally blew up', 'expected finally throw to reject')
end)

test('finally returning a rejecting promise replaces the outcome', function()
	local p = promise.resolve('value'):finally(function()
		return promise.reject('replaced')
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'replaced', 'expected rejection to replace fulfillment')
end)

test('finally preserves the original result when it fulfills', function()
	local p = promise.resolve(1, 2, 3):finally(function()
		return promise.resolve('ignored')
	end)
	local ok, a, b, c = p:await()
	check(ok and a == 1 and b == 2 and c == 3, 'expected original multi-return preserved')
end)

test('all rejects fast and cancels the remaining siblings', function()
	local never = promise.new(function() end)
	local combined = promise.all({promise.reject('fail'), never})
	local ok, reason = combined:await()
	check(not ok and reason == 'fail', 'expected fast rejection')
	task.wait()
	check(never:isCancelled(), 'expected the still-pending sibling to be cancelled')
end)

test('race settles with the first result and cancels the rest', function()
	local never = promise.new(function() end)
	local combined = promise.race({promise.resolve('fast'), never})
	local ok, value = combined:await()
	check(ok and value == 'fast', 'expected the fast promise to win')
	task.wait()
	check(never:isCancelled(), 'expected the loser to be cancelled')
end)

test('race does not force-cancel a shared promise still held elsewhere', function()
	local shared = promise.new(function() end)
	local keepAlive = shared:andThen(function() end)
	local combined = promise.race({promise.resolve('fast'), shared})
	combined:await()
	task.wait()
	check(shared:isPending(), 'shared promise should stay alive for its other consumer')
	keepAlive:cancel()
end)

test('any resolves with the first success and cancels the rest', function()
	local never = promise.new(function() end)
	local combined = promise.any({promise.reject('nope'), promise.resolve('ok'), never})
	local ok, value = combined:await()
	check(ok and value == 'ok', 'expected the first success')
	task.wait()
	check(never:isCancelled(), 'expected the still-pending sibling to be cancelled')
end)

test('allSettled reports every outcome without short circuiting', function()
	local combined = promise.allSettled({promise.resolve('ok'), promise.reject('bad')})
	local ok, results = combined:await()
	check(ok, 'allSettled itself should fulfill')
	check(results[1].status == 'fulfilled', 'expected first entry fulfilled')
	check(results[2].status == 'rejected', 'expected second entry rejected')
end)

test('retry rejects immediately when attempts is zero', function()
	local calls = 0
	local p = promise.retry(function()
		calls += 1
		error('always fails', 0)
	end, 0)
	local ok = p:await()
	check(not ok, 'expected rejection for attempts <= 0')
	check(calls == 0, 'fn should never run when attempts <= 0')
end)

test('retry stops scheduling new attempts once cancelled between failure and delay', function()
	local calls = 0
	local p = promise.retry(function()
		calls += 1
		error('always fails', 0)
	end, 5, 0.05)
	task.wait(0.01)
	p:cancel()
	task.wait(0.2)
	local snapshot = calls
	task.wait(0.2)
	check(calls == snapshot, 'no further attempts should start after cancellation')
end)

test('try resolves with the callback result', function()
	local p = promise.try(function(a, b)
		return a + b
	end, 2, 3)
	local ok, value = p:await()
	check(ok and value == 5, 'expected try to resolve with 5')
end)

test('try converts a synchronous error into a rejection', function()
	local p = promise.try(function()
		error('boom', 0)
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'boom', 'expected try to reject with boom')
end)

test('try preserves multiple return values', function()
	local p = promise.try(function()
		return 1, 2, 3
	end)
	local ok, a, b, c = p:await()
	check(ok and a == 1 and b == 2 and c == 3, 'expected try to preserve 1,2,3')
end)

test('try assimilates a promise returned by the callback', function()
	local p = promise.try(function()
		return promise.resolve('nested')
	end)
	local ok, value = p:await()
	check(ok and value == 'nested', 'expected try to assimilate the returned promise')
end)

test('try assimilates a thenable returned by the callback', function()
	local p = promise.try(function()
		return function(resolve)
			resolve('thenable')
		end
	end)
	local ok, value = p:await()
	check(ok and value == 'thenable', 'expected try to assimilate the returned thenable')
end)

test('try can be cancelled like any other promise', function()
	local p = promise.try(function()
		return promise.new(function() end)
	end)
	p:cancel()
	check(p:isCancelled(), 'expected try promise to be cancellable')
end)

test('promisify resolves through a callback-style function', function()
	local function readAsync(value, callback)
		callback(nil, value * 2)
	end
	local promisified = promise.promisify(readAsync)
	local ok, value = promisified(21):await()
	check(ok and value == 42, 'expected promisified success')
end)

test('promisify rejects when the callback reports an error', function()
	local function readAsync(callback)
		callback('failure')
	end
	local promisified = promise.promisify(readAsync)
	local ok, reason = promisified():await()
	check(not ok and reason == 'failure', 'expected promisified rejection')
end)

test('promisify converts a synchronous throw into a rejection', function()
	local function readAsync()
		error('sync failure', 0)
	end
	local promisified = promise.promisify(readAsync)
	local ok, reason = promisified():await()
	check(not ok and reason == 'sync failure', 'expected promisified to catch synchronous errors')
end)

test('promisify preserves multiple return values', function()
	local function readAsync(callback)
		callback(nil, 1, 2, 3)
	end
	local promisified = promise.promisify(readAsync)
	local ok, a, b, c = promisified():await()
	check(ok and a == 1 and b == 2 and c == 3, 'expected promisified to preserve 1,2,3')
end)

test('promisify only honors the first callback invocation', function()
	local function readAsync(callback)
		callback(nil, 'first')
		callback(nil, 'second')
		callback('third')
	end
	local promisified = promise.promisify(readAsync)
	local ok, value = promisified():await()
	check(ok and value == 'first', 'expected only the first callback invocation to settle')
end)

test('promisify returns a cancellable pending promise when the callback never responds', function()
	local function readAsync(_callback) end
	local promisified = promise.promisify(readAsync)
	local p = promisified()
	check(p:isPending(), 'expected the promisified call to still be pending')
	p:cancel()
	check(p:isCancelled(), 'expected the promisified call to be cancellable')
end)

test('defer schedules the callback and resolves with its result', function()
	local ran = false
	local p = promise.defer(function()
		ran = true
		return 'deferred'
	end)
	check(not ran, 'callback should not run synchronously')
	local ok, value = p:await()
	check(ran and ok and value == 'deferred', 'expected defer to run later and resolve')
end)

test('defer converts a callback error into a rejection', function()
	local p = promise.defer(function()
		error('deferred failure', 0)
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'deferred failure', 'expected defer to reject')
end)

test('defer forwards arguments and preserves multiple return values', function()
	local p = promise.defer(function(a, b)
		return a, b, a + b
	end, 4, 5)
	local ok, a, b, sum = p:await()
	check(ok and a == 4 and b == 5 and sum == 9, 'expected defer to forward args and preserve returns')
end)

test('defer assimilates a promise returned by the callback', function()
	local p = promise.defer(function()
		return promise.resolve('nested defer')
	end)
	local ok, value = p:await()
	check(ok and value == 'nested defer', 'expected defer to assimilate the returned promise')
end)

test('cancelling a defer before it runs stops the callback', function()
	local ran = false
	local p = promise.defer(function()
		ran = true
	end)
	p:cancel()
	task.wait()
	check(not ran, 'expected the deferred callback to never run once cancelled')
end)

test('tap runs a side effect and passes the original value through', function()
	local seen
	local p = promise.resolve(1, 2, 3):tap(function(a, b, c)
		seen = {a, b, c}
	end)
	local ok, a, b, c = p:await()
	check(ok and a == 1 and b == 2 and c == 3, 'expected tap to preserve the original values')
	check(seen[1] == 1 and seen[2] == 2 and seen[3] == 3, 'expected tap callback to observe the values')
end)

test('tap propagates an error thrown by the side effect', function()
	local p = promise.resolve('value'):tap(function()
		error('tap failed', 0)
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'tap failed', 'expected tap error to reject')
end)

test('tap does not run when the promise rejects', function()
	local ran = false
	local p = promise.reject('nope'):tap(function()
		ran = true
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'nope' and not ran, 'expected tap to skip on rejection')
end)

test('tap waits for a promise returned by the side effect', function()
	local finished = false
	local p = promise.resolve('value'):tap(function()
		return promise.delay(0.05):andThen(function()
			finished = true
		end)
	end)
	local ok, value = p:await()
	check(ok and value == 'value' and finished, 'expected tap to wait for the returned promise')
end)

test('map transforms each value and preserves order', function()
	local p = promise.map({1, 2, 3}, function(value)
		return value * 2
	end)
	local ok, results = p:await()
	check(ok and results[1] == 2 and results[2] == 4 and results[3] == 6, 'expected mapped results in order')
end)

test('map resolves list items that are themselves promises', function()
	local slow = promise.delay(0.02):andThen(function()
		return 2
	end)
	local p = promise.map({promise.resolve(1), slow}, function(value)
		return value + 10
	end)
	local ok, results = p:await()
	check(ok and results[1] == 11 and results[2] == 12, 'expected map to await promise items before mapping')
end)

test('map rejects and cancels remaining items when the mapper throws', function()
	local never = promise.new(function() end)
	local p = promise.map({1, never}, function(value)
		if value == 1 then
			error('mapper failed', 0)
		end
		return value
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'mapper failed', 'expected map to reject on mapper error')
	task.wait()
	check(never:isCancelled(), 'expected the unresolved sibling to be cancelled')
end)

test('map rejects and cancels remaining items when a source item rejects', function()
	local never = promise.new(function() end)
	local p = promise.map({promise.reject('source failed'), never}, function(value)
		return value
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'source failed', 'expected map to reject on source rejection')
	task.wait()
	check(never:isCancelled(), 'expected the unresolved sibling to be cancelled')
end)

test('cancelling a map promise cancels its remaining subscriptions', function()
	local never = promise.new(function() end)
	local p = promise.map({never}, function(value)
		return value
	end)
	p:cancel()
	task.wait()
	check(never:isCancelled(), 'expected cancelling map to cancel its source items')
end)

test('map resolves immediately with an empty list', function()
	local ok, results = promise.map({}, function(value)
		return value
	end):await()
	check(ok and #results == 0, 'expected map of an empty list to resolve with an empty array')
end)

test('filter keeps only values that pass the predicate', function()
	local p = promise.filter({1, 2, 3, 4, 5}, function(value)
		return value % 2 == 0
	end)
	local ok, results = p:await()
	check(ok and #results == 2 and results[1] == 2 and results[2] == 4, 'expected filter to keep even values')
end)

test('filter awaits promise items before filtering', function()
	local p = promise.filter({promise.resolve(1), promise.resolve(2), promise.resolve(3)}, function(value)
		return value > 1
	end)
	local ok, results = p:await()
	check(ok and #results == 2 and results[1] == 2 and results[2] == 3, 'expected filter to await promise items')
end)

test('filter propagates rejection from a source item', function()
	local p = promise.filter({promise.reject('filter source failed')}, function()
		return true
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'filter source failed', 'expected filter to reject on source rejection')
end)

test('each runs sequentially and collects results in order', function()
	local order = {}
	local p = promise.each({1, 2, 3}, function(value)
		table.insert(order, value)
		return value * 10
	end)
	local ok, results = p:await()
	check(ok and results[1] == 10 and results[2] == 20 and results[3] == 30, 'expected each to collect results in order')
	check(order[1] == 1 and order[2] == 2 and order[3] == 3, 'expected each to run sequentially in order')
end)

test('each waits for a pending item before moving to the next', function()
	local slowDone = false
	local sawFastBeforeSlowFinished = false
	local slow = promise.delay(0.05)
	local p = promise.each({slow, promise.resolve('fast')}, function(value, index)
		if index == 1 then
			slowDone = true
		elseif index == 2 and not slowDone then
			sawFastBeforeSlowFinished = true
		end
	end)
	p:await()
	check(not sawFastBeforeSlowFinished, 'expected each to process items strictly in order')
end)

test('each rejects and stops when the iterator throws', function()
	local ran = {}
	local p = promise.each({1, 2, 3}, function(value)
		table.insert(ran, value)
		if value == 2 then
			error('each failed', 0)
		end
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'each failed', 'expected each to reject on iterator error')
	check(#ran == 2, 'expected each to stop after the failing item')
end)

test('each rejects when a source item rejects', function()
	local ran = {}
	local p = promise.each({promise.resolve(1), promise.reject('each source failed'), promise.resolve(3)}, function(value)
		table.insert(ran, value)
	end)
	local ok, reason = p:await()
	check(not ok and reason == 'each source failed', 'expected each to reject on source rejection')
	check(#ran == 1, 'expected each to stop before the rejected item runs')
end)

test('cancelling each cancels the item currently in flight', function()
	local current = promise.new(function() end)
	local p = promise.each({current}, function() end)
	task.wait()
	p:cancel()
	task.wait()
	check(current:isCancelled(), 'expected each to cancel the in-flight item')
end)

test('some resolves once enough items fulfill', function()
	local never = promise.new(function() end)
	local p = promise.some({promise.resolve(1), promise.resolve(2), never}, 2)
	local ok, results = p:await()
	check(ok and #results == 2, 'expected some to resolve with 2 results')
	task.wait()
	check(never:isCancelled(), 'expected the unneeded sibling to be cancelled')
end)

test('some rejects once enough items reject to make the target unreachable', function()
	local p = promise.some({promise.reject('a'), promise.reject('b'), promise.resolve('c')}, 2)
	local ok, errors = p:await()
	check(not ok and #errors == 2, 'expected some to reject once the target becomes unreachable')
end)

test('some rejects immediately when count exceeds the list size', function()
	local ok, reason = promise.some({promise.resolve(1)}, 2):await()
	check(not ok and reason == 'promise.some requested more results than the list contains', 'expected some to reject on an impossible count')
end)

test('cancelling some cancels its remaining subscriptions', function()
	local never = promise.new(function() end)
	local p = promise.some({never}, 1)
	p:cancel()
	task.wait()
	check(never:isCancelled(), 'expected cancelling some to cancel its source items')
end)

test('try, defer and promisify interoperate with promise.all', function()
	local combined = promise.all({
		promise.try(function()
			return 1
		end),
		promise.defer(function()
			return 2
		end),
		promise.promisify(function(callback)
			callback(nil, 3)
		end)(),
	})
	local ok, results = combined:await()
	check(ok and results[1][1] == 1 and results[2][1] == 2 and results[3][1] == 3, 'expected try/defer/promisify to interoperate with promise.all')
end)

print(string.format('%d passed, %d failed', passed, failed))
if failed > 0 then
	error('failing tests: ' .. table.concat(failedNames, ', '), 0)
end
