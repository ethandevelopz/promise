# Custom Promise Library

A lightweight, cancellation-aware Promise implementation designed for asynchronous workflows, resource cleanup, and structured concurrency in Luau/Roblox environments. Developed by ethandevelopz.

---

## Overview

This library provides a Promise abstraction for handling asynchronous operations with explicit fulfillment, rejection, cancellation, and chaining.

It is designed around Luau's multiple return values and Roblox's coroutine-based execution model, with consumer-aware cancellation to prevent shared asynchronous operations from being cancelled prematurely.

---

## Features

* **Promise Chaining:** Chain asynchronous operations with `andThen`, `catch`, and `finally`.
* **Cancellation:** Promises can be cancelled with cancellation hooks for cleaning up underlying resources.
* **Consumer-Aware Cancellation:** Shared Promises track active consumers, allowing one cancelled consumer to leave other consumers unaffected.
* **Multiple Return Values:** Native Luau multiple returns are preserved throughout Promise chains.
* **Thenable Assimilation:** Promises can adopt other Promise-like values and function-based thenables.
* **Promise Combinators:** Includes `all`, `race`, `any`, `allSettled`, and `some` with cancellation-aware behavior.
* **Collection Utilities:** `map`, `filter`, and `each` apply async transformations and side effects to arrays of values or Promises.
* **Roblox Utilities:** Includes `delay`, `timeout`, `retry`, `defer`, and `fromEvent` for common asynchronous workflows.
* **Interop Utilities:** `try` and `promisify` make it easy to bring synchronous code and callback-style APIs into the Promise world.
* **Coroutine Integration:** `await` allows a coroutine to yield until a Promise settles without blocking other Roblox execution.
* **Error Handling:** Rejections propagate through chains and can be handled with `catch` or converted into thrown errors with `expect`.
* **Resource Cleanup:** `onCancel` hooks allow asynchronous operations to clean up connections, timers, and other resources when cancelled.

---

## API

See `documentation.md` for the complete API reference. Summary below.

### Creating Promises

```lua
promise.new(function(resolve, reject, onCancel)
	-- asynchronous work

	resolve(value)
end)
```

Call `resolve(...)` when the operation succeeds and `reject(...)` when it fails.

```lua
promise.try(function(a, b)
	return a + b
end, 2, 3)
```

`promise.try` runs a synchronous or asynchronous callback and wraps its result (or thrown error) in a Promise.

```lua
local readFileAsync = promise.promisify(function(path, callback)
	callback(nil, readFile(path))
end)

readFileAsync('data.json'):andThen(print)
```

`promise.promisify` converts a callback-taking function `(...args, callback)` into a function that returns a Promise, using the `callback(err, ...results)` convention: a non-`nil` `err` rejects, otherwise the remaining values fulfill. That convention is a choice made by this library, not a Roblox or Luau standard, so `callback` needs to actually report errors this way for rejections to work.

```lua
promise.defer(function()
	return computeExpensiveThing()
end)
```

`promise.defer` schedules a callback with `task.defer` and resolves with its result.

### Chaining

```lua
promise.new(function(resolve)
	resolve('hello')
end)
	:andThen(function(value)
		print(value)
	end)
	:catch(function(reason)
		warn(reason)
	end)
```

```lua
fetchUser(id)
	:tap(function(user)
		print('fetched', user.name)
	end)
	:andThen(function(user)
		return user.name
	end)
```

`tap` runs a side effect on fulfillment and passes the original value(s) through unchanged.

### Awaiting

```lua
local success, value = myPromise:await()

if success then
	print(value)
end
```

### Cancellation

```lua
local request = getData()

request:onCancel(function()
	-- cleanup
end)

request:cancel()
```

### Combinators

```lua
promise.all({
	firstPromise,
	secondPromise,
	thirdPromise,
}):andThen(function(results)
	print('all completed')
end)
```

`all`, `race`, `any`, and `some` automatically cancel their remaining subscriptions when their outcome is determined.

```lua
promise.some({firstPromise, secondPromise, thirdPromise}, 2):andThen(function(results)
	print('first 2 results are in')
end)
```

`some` resolves once a given number of Promises in a list have fulfilled, rejecting only once reaching that number becomes impossible.

### Collections

```lua
promise.map({1, 2, 3}, function(value)
	return value * 2
end):andThen(print)

promise.filter({1, 2, 3, 4}, function(value)
	return value % 2 == 0
end):andThen(print)

promise.each({1, 2, 3}, function(value, index)
	print(index, value)
end)
```

`map` and `filter` resolve their list entries (which may themselves be Promises) concurrently and reject/cancel the rest as soon as one fails. `each` processes entries strictly in order, waiting for each one before moving to the next.

---

## Testing

The library includes a dedicated test suite covering Promise state transitions, cancellation, chaining, thenable assimilation, cleanup, combinators, collection utilities, timeouts, retries, cancellation races, and the interop utilities.

Current test status:

```text
62 passed, 0 failed
```

---

## Installation

Place the `Promise` ModuleScript somewhere accessible to your scripts, such as `ReplicatedStorage`.

```lua
local promise = require(game:GetService('ReplicatedStorage').Promise)
```

The library has no required external dependencies.

---

## Contact

* **Discord:** `ethanmracing`
* **Roblox:** [ethandevelopz Profile](https://www.roblox.com/users/281018055/profile)
* **GitHub:** [ethandevelopz](https://github.com/ethandevelopz)
