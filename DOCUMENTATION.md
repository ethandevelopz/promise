# Promise Library — API Reference

This is the complete API reference for the Promise library, including every public function and method, existing and newly added.

A Promise has four possible states: `pending`, `fulfilled`, `rejected`, and `cancelled`. Once a Promise leaves `pending`, its state is final.

---

## Table of Contents

**Construction**
- [`promise.new`](#promisenew)
- [`promise.is`](#promiseis)
- [`promise.resolve`](#promiseresolve)
- [`promise.reject`](#promisereject)
- [`promise.try`](#promisetry)
- [`promise.promisify`](#promisepromisify)
- [`promise.defer`](#promisedefer)

**Chaining**
- [`andThen`](#promiseandthen)
- [`catch`](#promisecatch)
- [`finally`](#promisefinally)
- [`tap`](#promisetap)

**Cancellation**
- [`cancel`](#promisecancel)
- [`onCancel`](#promiseoncancel)

**State Inspection**
- [`isPending`](#promiseispending)
- [`isFulfilled`](#promiseisfulfilled)
- [`isRejected`](#promiseisrejected)
- [`isCancelled`](#promiseiscancelled)

**Consuming**
- [`await`](#promiseawait)
- [`expect`](#promiseexpect)

**Combinators**
- [`promise.all`](#promiseall)
- [`promise.race`](#promiserace)
- [`promise.allSettled`](#promiseallsettled)
- [`promise.any`](#promiseany)
- [`promise.some`](#promisesome)

**Collections**
- [`promise.map`](#promisemap)
- [`promise.filter`](#promisefilter)
- [`promise.each`](#promiseeach)

**Roblox Utilities**
- [`promise.delay`](#promisedelay)
- [`promise:timeout`](#promisetimeout)
- [`promise.retry`](#promiseretry)
- [`promise.fromEvent`](#promisefromevent)

---

## Construction

### `promise.new`

Creates a new Promise from an executor function.

**Signature:** `promise.new(executor: (resolve, reject, onCancel) -> ()) -> Promise`

**Parameters:**
- `executor` — called synchronously and immediately. Receives:
  - `resolve(...)` — fulfills the Promise with the given values. If called with a single Promise or thenable, the new Promise adopts that value's eventual outcome instead (see Promise/thenable assimilation below).
  - `reject(...)` — rejects the Promise with the given values.
  - `onCancel(hook)` — registers a cleanup hook, equivalent to calling `:onCancel(hook)` on the resulting Promise.

**Returns:** a new `Promise` in the `pending` state (unless the executor settles it synchronously).

**Behavior:** If the executor throws synchronously and the Promise has not already settled, the Promise rejects with the thrown error.

**Multiple return values:** every value passed to `resolve` or `reject` is preserved and delivered to consumers in the same order.

**Promise/thenable assimilation:** if `resolve` is called with a single value that is itself a Promise, the new Promise waits for it and mirrors its outcome; if that inner Promise is cancelled, the outer Promise is cancelled too. If `resolve` is called with a single value that exposes an `andThen` method (a table/userdata thenable) or is itself a function `(onFulfill, onReject) -> ()`, that value is treated the same way. Only the first settlement of a thenable is honored.

```lua
local p = promise.new(function(resolve, reject, onCancel)
	local connection
	connection = someSignal:Connect(function(value)
		resolve(value)
	end)

	onCancel(function()
		connection:Disconnect()
	end)
end)
```

---

### `promise.is`

Checks whether a value is a Promise created by this library.

**Signature:** `promise.is(value: any) -> boolean`

```lua
if promise.is(result) then
	result:andThen(print)
end
```

---

### `promise.resolve`

Creates a Promise that is already fulfilled with the given values (or that assimilates a single Promise/thenable argument).

**Signature:** `promise.resolve(...: any) -> Promise`

**Multiple return values:** all arguments are preserved.

**Promise/thenable assimilation:** same rules as `resolve` inside `promise.new` — passing a single Promise or thenable causes the result to adopt its outcome instead of wrapping it.

```lua
promise.resolve(1, 2, 3):andThen(function(a, b, c)
	print(a, b, c)
end)
```

---

### `promise.reject`

Creates a Promise that is already rejected with the given values.

**Signature:** `promise.reject(...: any) -> Promise`

**Multiple return values:** all arguments are preserved as the rejection reason(s).

```lua
promise.reject('not found'):catch(warn)
```

---

### `promise.try`

*(New)* Safely executes a callback and wraps its outcome in a Promise. Equivalent to `promise.new` for synchronous logic, but without needing to write the executor boilerplate by hand.

**Signature:** `promise.try(callback: (...any) -> ...any, ...: any) -> Promise`

**Parameters:**
- `callback` — run synchronously via `pcall` as soon as `promise.try` is called.
- `...` — arguments forwarded to `callback`.

**Returns:** a Promise that fulfills with `callback`'s return values, or rejects with the error if `callback` throws.

**Behavior:** the callback runs immediately (synchronously), inside a `pcall`. A thrown error becomes a rejection reason instead of propagating out of `promise.try`.

**Multiple return values:** every value returned by `callback` is preserved.

**Promise/thenable assimilation:** if `callback` returns a single Promise or thenable, the result Promise waits for and adopts its outcome, exactly as `resolve` does.

**Cancellation:** the returned Promise is a normal Promise and can be cancelled like any other. If `callback` returned a pending Promise that is being assimilated, cancelling the outer Promise also cancels that inner Promise.

```lua
promise.try(function(a, b)
	return a / b
end, 10, 2):andThen(print)

promise.try(function()
	error('bad input')
end):catch(function(reason)
	warn(reason)
end)
```

---

### `promise.promisify`

*(New)* Converts a callback-style function into a function that returns a Promise.

**Signature:** `promise.promisify(callback: (...any) -> ...any) -> (...any) -> Promise`

**Parameters:**
- `callback` — a function whose *last* parameter is a completion callback. `promisify` calls it as `callback(err, ...results)`: a non-`nil` `err` is treated as a rejection reason; a `nil` `err` fulfills with the remaining values. This is a convention chosen by this library, not a Roblox or Luau standard — Roblox callback-style APIs don't consistently follow an `(err, ...)` shape, so `callback` needs to actually report errors this way (or be adapted with a small wrapper) for rejections to work.

**Returns:** a function. Calling it forwards all given arguments to `callback` (with the completion callback appended as the final argument) and returns a Promise for the eventual result.

**Behavior:** if `callback` throws synchronously before invoking the completion callback, the Promise rejects with the thrown error. Only the first invocation of the completion callback is honored — later invocations are ignored, preventing double settlement.

**Multiple return values:** every value passed after `err` to the completion callback is preserved as the fulfillment values.

**Cancellation:** the returned Promise can be cancelled like any other. Cancellation does not stop `callback` itself from running (the library has no way to interrupt an arbitrary callback-style operation), but any late invocation of the completion callback on an already-cancelled Promise is simply a no-op.

```lua
local readFileAsync = promise.promisify(function(path, callback)
	task.spawn(function()
		local ok, contents = pcall(readFile, path)
		if ok then
			callback(nil, contents)
		else
			callback(contents)
		end
	end)
end)

readFileAsync('data.json')
	:andThen(function(contents)
		print(contents)
	end)
	:catch(warn)
```

---

### `promise.defer`

*(New)* Schedules a callback with Roblox's `task.defer` and returns a Promise for its result.

**Signature:** `promise.defer(callback: (...any) -> ...any, ...: any) -> Promise`

**Parameters:**
- `callback` — run on the next deferred scheduling point via `task.defer`, inside a `pcall`.
- `...` — arguments forwarded to `callback`.

**Returns:** a Promise that fulfills with `callback`'s return values once it runs, or rejects with the error if it throws.

**Multiple return values:** every value returned by `callback` is preserved.

**Promise/thenable assimilation:** if `callback` returns a single Promise or thenable, the result Promise adopts its outcome.

**Cancellation:** cancelling the returned Promise before `callback` has run cancels the underlying deferred thread with `task.cancel`, so `callback` never executes.

```lua
promise.defer(function()
	return computeExpensiveThing()
end):andThen(print)
```

---

## Chaining

### `promise:andThen`

Registers fulfillment and/or rejection handlers and returns a new child Promise.

**Signature:** `promise:andThen(onFulfill: ((...any) -> ...any)?, onReject: ((...any) -> ...any)?) -> Promise`

**Parameters:**
- `onFulfill` — called with the fulfillment values if the parent fulfills. Optional; if omitted, fulfillment passes through unchanged.
- `onReject` — called with the rejection values if the parent rejects. Optional; if omitted, rejection passes through unchanged.

**Returns:** a child Promise that settles based on the return value of whichever handler ran (or passes the parent's outcome through if the relevant handler was omitted).

**Behavior:** if the parent is still pending, the handlers are queued and run once the parent settles. If the parent has already settled, the handlers run on the next scheduling tick. If a handler throws, the child Promise rejects with the thrown error.

**Multiple return values:** all values returned from the handler become the child's fulfillment values; preserved end-to-end.

**Promise/thenable assimilation:** if a handler returns a single Promise or thenable, the child Promise waits for and adopts its outcome instead of fulfilling with the Promise object itself.

**Cancellation behavior:** calling `andThen` registers the child as a *consumer* of the parent. Cancelling the child releases that consumer registration; if the parent has no other consumers left, it is automatically cancelled too. Cancelling a shared parent Promise directly cancels every child derived from it.

```lua
promise.resolve(2):andThen(function(value)
	return value * 2
end):andThen(print)
```

---

### `promise:catch`

Registers a rejection handler only. Shorthand for `promise:andThen(nil, onReject)`.

**Signature:** `promise:catch(onReject: (...any) -> ...any) -> Promise`

```lua
fetchData():catch(function(reason)
	warn('failed:', reason)
end)
```

---

### `promise:finally`

Registers a handler that runs regardless of whether the Promise fulfilled or rejected, without observing or altering the eventual value (unless it throws or returns a rejecting Promise).

**Signature:** `promise:finally(onFinally: (() -> ...any)?) -> Promise`

**Behavior:** `onFinally` is called with no arguments. If it returns a Promise or thenable, the chain waits for it before continuing. If `onFinally` throws, or returns a rejecting Promise, the resulting Promise rejects with that new reason instead of the original outcome. Otherwise, the original fulfillment values or rejection reason pass through unchanged.

**Cancellation behavior:** if the resulting Promise is cancelled, `onFinally` still runs (via a cancellation hook) so cleanup logic executes.

```lua
request():finally(function()
	spinner:Hide()
end)
```

---

### `promise:tap`

*(New)* Runs a side effect on fulfillment without altering the fulfillment values.

**Signature:** `promise:tap(callback: (...any) -> ...any) -> Promise`

**Parameters:**
- `callback` — called with the fulfillment values if the parent fulfills. Only runs on fulfillment, never on rejection.

**Returns:** a child Promise that fulfills with the *same* values the parent fulfilled with, once `callback` (and anything it returns) has settled.

**Behavior:** if `callback` throws, the resulting Promise rejects with the thrown error instead of passing the original value through. If the parent rejects, `tap`'s callback never runs and the rejection passes straight through, matching `andThen(nil, ...)` semantics for the reject path.

**Multiple return values:** the original fulfillment values are preserved exactly, regardless of what `callback` returns.

**Promise/thenable assimilation:** if `callback` returns a Promise or thenable, `tap` waits for it to settle before passing the original values through (useful for asynchronous logging or side effects that must complete first).

```lua
fetchUser(id)
	:tap(function(user)
		analytics:track('user_fetched', user.id)
	end)
	:andThen(function(user)
		return user.name
	end)
```

---

## Cancellation

### `promise:cancel`

Cancels a pending Promise.

**Signature:** `promise:cancel() -> ()`

**Behavior:** if the Promise is not `pending`, this is a no-op. Otherwise, the Promise moves to the `cancelled` state, all registered cancellation hooks run (each wrapped in `pcall`, so a throwing hook cannot prevent the others from running), and any child Promises created via `andThen` are cancelled in turn.

```lua
local request = getData()
request:cancel()
```

---

### `promise:onCancel`

Registers a hook to run when the Promise is cancelled.

**Signature:** `promise:onCancel(hook: () -> ()) -> ()`

**Behavior:** if the Promise is already `cancelled`, the hook runs immediately (scheduled via `task.spawn`). If the Promise is `pending`, the hook is stored and runs when/if the Promise is later cancelled. If the Promise has already fulfilled or rejected, the hook is discarded (there is nothing left to cancel).

```lua
request:onCancel(function()
	connection:Disconnect()
end)
```

---

## State Inspection

### `promise:isPending`

**Signature:** `promise:isPending() -> boolean`

Returns `true` only while the Promise has not yet settled.

### `promise:isFulfilled`

**Signature:** `promise:isFulfilled() -> boolean`

Returns `true` only if the Promise fulfilled successfully.

### `promise:isRejected`

**Signature:** `promise:isRejected() -> boolean`

Returns `true` only if the Promise rejected.

### `promise:isCancelled`

**Signature:** `promise:isCancelled() -> boolean`

Returns `true` only if the Promise was cancelled.

---

## Consuming

### `promise:await`

Yields the current coroutine until the Promise settles.

**Signature:** `promise:await() -> (boolean, ...any)`

**Returns:** `true, ...fulfillmentValues` if the Promise fulfilled; `false, ...rejectionOrCancellationValues` if it rejected or was cancelled.

**Behavior:** if the Promise has already settled, `await` returns immediately without yielding. Otherwise it yields the calling coroutine and resumes it once the Promise settles (or is cancelled).

**Multiple return values:** all fulfillment or rejection values are preserved after the leading boolean.

```lua
local ok, value = myPromise:await()
if ok then
	print(value)
else
	warn('failed:', value)
end
```

---

### `promise:expect`

Yields like `await`, but throws instead of returning a success flag.

**Signature:** `promise:expect() -> ...any`

**Behavior:** if the Promise fulfills, returns the fulfillment values directly. If it rejects or is cancelled, raises an error using the rejection/cancellation reason.

**Multiple return values:** all fulfillment values are preserved.

```lua
local value = myPromise:expect()
print(value)
```

---

## Combinators

### `promise.all`

Waits for every Promise in a list to fulfill, or rejects as soon as any one rejects.

**Signature:** `promise.all(list: {any}) -> Promise`

**Parameters:**
- `list` — an array of Promises or plain values (plain values are treated as already-fulfilled).

**Returns:** a Promise that fulfills with an array of packed result tuples (one per input, `results[i]` holds all values that input fulfilled with, index-aligned with `list`), or rejects with the first rejection reason encountered.

**Behavior:** an empty list resolves immediately with an empty array.

**Cancellation behavior:** as soon as one input rejects, or the returned Promise is cancelled, every other still-pending input is cancelled (subject to consumer-aware cancellation — a shared input with other consumers elsewhere is only released, not force-cancelled, unless that was its last consumer).

```lua
promise.all({promise.resolve(1), promise.resolve(2)}):andThen(function(results)
	print(results[1][1], results[2][1])
end)
```

---

### `promise.race`

Settles as soon as the first input in a list settles, in either direction.

**Signature:** `promise.race(list: {any}) -> Promise`

**Returns:** a Promise that mirrors whichever input settles first (fulfilled or rejected).

**Cancellation behavior:** once the first input settles, or the returned Promise is cancelled, every other still-pending input is cancelled (consumer-aware, same as `all`).

```lua
promise.race({promise.delay(5), fetchWithTimeout()}):andThen(print)
```

---

### `promise.allSettled`

Waits for every Promise in a list to settle, regardless of outcome, without short-circuiting on rejection.

**Signature:** `promise.allSettled(list: {any}) -> Promise`

**Returns:** a Promise that fulfills with an array of `{status = 'fulfilled' | 'rejected', values = {...}}` entries, index-aligned with `list`.

**Behavior:** an empty list resolves immediately with an empty array. This combinator never rejects on its own.

```lua
promise.allSettled({promise.resolve('ok'), promise.reject('bad')}):andThen(function(results)
	for _, entry in results do
		print(entry.status)
	end
end)
```

---

### `promise.any`

Resolves as soon as any one input fulfills; rejects only if every input rejects.

**Signature:** `promise.any(list: {any}) -> Promise`

**Returns:**
- On success: fulfills directly with the winning input's raw fulfillment values — multiple return values preserved as-is, *not* wrapped in a table, as if you had `andThen`'d that one input yourself.
- On failure: rejects with a single value — an array index-aligned with the original `list` (`errors[i]` corresponds to `list[i]`), where each entry is a packed tuple of that input's rejection values (so an individual reason is `errors[i][1]`, not `errors[i]` itself). This only happens once *every* input has rejected, so by the time it's delivered the array has one entry per input, none missing.
- Rejects immediately, before subscribing to anything, if `list` is empty.

**Cancellation behavior:** once a winner is found, or the returned Promise is cancelled, remaining pending inputs are cancelled (consumer-aware, same as `all`).

```lua
promise.any({promise.reject('a'), promise.resolve('b')}):andThen(print)
```

---

### `promise.some`

*(New)* Resolves once a specified number of inputs have fulfilled; rejects only once reaching that number becomes mathematically impossible. A generalization of `any` — `any` is comparable to `some(list, 1)`, except `any` forwards its winner's raw values directly, while `some` always wraps entries in packed tuples (see the return shapes below, and `any`'s shapes above — they are not identical).

**Signature:** `promise.some(list: {any}, count: number) -> Promise`

**Parameters:**
- `list` — an array of Promises or plain values.
- `count` — how many fulfillments to wait for. Must be `>= 1`.

**Returns:**
- On success: fulfills with a single value — an array of length `count`, built in the order inputs actually fulfilled (*not* index-aligned with `list`, unlike `promise.all`). Each entry is a packed tuple of that input's fulfillment values (an individual value is `results[i][1]`, not `results[i]` itself).
- On failure: rejects with a single value — an array built in the order rejections arrived (again, not index-aligned with `list`), where each entry is a packed tuple of that input's rejection values. This array only contains the rejections collected up to the moment `count` fulfillments became unreachable; inputs still pending at that moment are cancelled instead of being waited on, so the array's length is `total - count + 1`, not necessarily `#list`.
- Rejects immediately, without subscribing to any input, if `count` is greater than `#list`.

**Cancellation behavior:** once enough inputs fulfill (or too many reject), or the returned Promise is cancelled, every other still-pending input is cancelled (consumer-aware, same as `all`).

```lua
promise.some({fetchMirrorA(), fetchMirrorB(), fetchMirrorC()}, 2):andThen(function(results)
	print('got the first 2 responses')
end)
```

---

## Collections

### `promise.map`

*(New)* Resolves a list of values/Promises concurrently and applies a mapper function to each fulfilled value.

**Signature:** `promise.map(list: {any}, mapper: (value: any, index: number) -> any) -> Promise`

**Parameters:**
- `list` — an array of Promises or plain values.
- `mapper` — called with each input's first fulfillment value and its index once that input fulfills. Run inside `pcall`.

**Returns:** a Promise that fulfills with an array of `mapper`'s return values, index-aligned with `list`. Rejects with `mapper`'s thrown error if it throws, or with the original reason if an input rejects.

**Behavior:** an empty list resolves immediately with an empty array. All inputs are awaited concurrently, not sequentially — use `promise.each` if strict ordering between iterations is required.

**Cancellation behavior:** as soon as one input rejects, `mapper` throws, or the returned Promise is cancelled, every other still-pending input is cancelled (consumer-aware, same as `all`).

```lua
promise.map({url1, url2, url3}, function(url)
	return httpGet(url)
end):andThen(function(responses)
	print(#responses)
end)
```

---

### `promise.filter`

*(New)* Resolves a list of values/Promises concurrently and keeps only the ones that pass a predicate.

**Signature:** `promise.filter(list: {any}, predicate: (value: any, index: number) -> boolean) -> Promise`

**Parameters:**
- `list` — an array of Promises or plain values.
- `predicate` — called with each input's first fulfillment value and its index once that input fulfills. Its return value is coerced to a boolean.

**Returns:** a Promise that fulfills with an array containing only the original values for which `predicate` returned a truthy value, in their original `list` order. Rejects if any input rejects or `predicate` throws.

**Behavior:** implemented on top of `promise.map`, so it shares the same concurrency and cancellation behavior.

```lua
promise.filter(files, function(file)
	return file:IsA('Script')
end):andThen(function(scripts)
	print(#scripts)
end)
```

---

### `promise.each`

*(New)* Processes a list of values/Promises strictly in order, waiting for each one before starting the next.

**Signature:** `promise.each(list: {any}, iterator: (value: any, index: number) -> any) -> Promise`

**Parameters:**
- `list` — an array of Promises or plain values.
- `iterator` — called with each input's first fulfillment value and its index, in order, only after the previous input's iterator call has completed. Run inside `pcall`.

**Returns:** a Promise that fulfills with an array of `iterator`'s return values once every input has been processed, index-aligned with `list`. Rejects immediately (without processing further items) if `iterator` throws or an input rejects.

**Behavior:** unlike `map`, inputs are awaited sequentially, so `each` is appropriate when iteration order or throttling matters (e.g. rate-limited requests, ordered side effects).

**Cancellation behavior:** cancelling the returned Promise cancels the input currently being awaited (consumer-aware); items not yet reached are never subscribed to in the first place.

```lua
promise.each(queue, function(job, index)
	print('processing job', index)
	return runJob(job)
end)
```

---

## Roblox Utilities

### `promise.delay`

Creates a Promise that fulfills after a given number of seconds.

**Signature:** `promise.delay(seconds: number) -> Promise`

**Cancellation behavior:** cancelling the Promise before it fulfills cancels the underlying `task.delay` thread, so it never fulfills.

```lua
promise.delay(2):andThen(function()
	print('2 seconds passed')
end)
```

---

### `promise:timeout`

Races a Promise against a timer, rejecting if the timer wins.

**Signature:** `promise:timeout(seconds: number, reason: any?) -> Promise`

**Parameters:**
- `seconds` — how long to wait before timing out.
- `reason` — optional rejection reason to use on timeout; defaults to `'promise timed out'`.

**Returns:** a Promise that mirrors the original Promise's outcome if it settles first, or rejects with `reason` if the timer elapses first.

**Cancellation behavior:** if the timer wins, the original Promise is cancelled. If the original Promise settles first, the timer is cancelled. If the returned Promise is cancelled directly, both the timer and the original Promise are cancelled.

```lua
fetchData():timeout(5, 'request took too long'):catch(warn)
```

---

### `promise.retry`

Repeatedly calls a function until it succeeds or a maximum number of attempts is reached.

**Signature:** `promise.retry(fn: (...any) -> ...any, attempts: number, waitSeconds: number?) -> Promise`

**Parameters:**
- `fn` — called with no arguments on each attempt, inside `pcall`.
- `attempts` — maximum number of attempts. Must be `>= 1`, or the Promise rejects immediately without calling `fn`.
- `waitSeconds` — optional delay between attempts (via `promise.delay`); defaults to `0`.

**Returns:** a Promise that fulfills with `fn`'s outcome on the first attempt that does not throw synchronously, or rejects with the last synchronous error once `attempts` is exhausted.

**Synchronous functions vs. functions that return a Promise:** `retry` only retries on a *synchronous* error thrown by `fn` — that's the only thing `pcall(fn)` can observe. `fn` is allowed to return a Promise (or thenable) instead of a plain value; when it does, `retry` assimilates it exactly the way `resolve` does anywhere else in this library. The important consequence is that this assimilation happens on the *first* attempt that doesn't throw, and it settles the whole `retry` call directly: if the Promise `fn` returned goes on to reject, that rejection becomes the final outcome of `retry` immediately, without scheduling another attempt. So `retry` is only useful for retrying failures `fn` reports by throwing (synchronously) — it does not inspect or retry based on the eventual rejection of a Promise `fn` hands back.

**Multiple return values:** all values returned by a successful (non-throwing) `fn` call are preserved.

**Cancellation behavior:** cancelling the Promise stops further attempts from being scheduled; if a delay between attempts is in progress, it is cancelled too.

```lua
promise.retry(function()
	return httpGet(url)
end, 3, 1):andThen(print)
```

---

### `promise.fromEvent`

Wraps a Roblox `RBXScriptSignal` (or any object with a compatible `Connect` method) in a Promise that fulfills the first time the signal fires.

**Signature:** `promise.fromEvent(signal: any, predicate: ((...any) -> boolean)?) -> Promise`

**Parameters:**
- `signal` — any object exposing `:Connect(callback)`.
- `predicate` — optional filter; when the signal fires, the connection is only consumed (and the Promise fulfilled) if `predicate(...)` returns a truthy value. If falsy, the connection stays alive and waits for the next fire.

**Returns:** a Promise that fulfills with the arguments passed to the signal the first time it fires (and passes `predicate`, if given). Rejects immediately if `signal:Connect` itself throws.

**If `predicate` throws:** `predicate` is called directly inside the signal's connection callback and is *not* wrapped in `pcall` by this library (the `pcall` in the implementation only guards the initial `signal:Connect(...)` call, not each firing). If `predicate` throws when the signal fires, the error is not caught here — it propagates out of the connection callback the same way any uncaught error in a signal handler would, and does **not** reject the Promise. The Promise is left pending (with the connection still alive) unless something else cancels it. Write `predicate` so it does not throw, or wrap its own logic in `pcall`, if you need rejections on bad input.

**Cancellation behavior:** cancelling the Promise disconnects the underlying connection. Disconnecting twice never errors.

```lua
promise.fromEvent(button.MouseButton1Click):andThen(function()
	print('clicked')
end)
```

---

## Verification

- The implementation was reviewed function-by-function against this reference; no behavior described above goes beyond what the code in `Promise.luau` actually does.
- `Promise_spec.luau` exercises every API above, including new success, rejection, synchronous-error, multi-return, assimilation, cancellation, double-settlement, and combinator-interaction cases for each newly added API, without modifying or weakening any pre-existing test.
- This environment does not have a Luau/Roblox runtime available to execute the test suite directly. Run `Promise_spec.luau` inside Roblox Studio (or another Luau host) against `Promise.luau` to confirm the `62 passed, 0 failed` result reported in `README.md`.
