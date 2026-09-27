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

print(string.format('%d passed, %d failed', passed, failed))
if failed > 0 then
	error('failing tests: ' .. table.concat(failedNames, ', '), 0)
end
