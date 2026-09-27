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
* **Promise Combinators:** Includes `all`, `race`, `any`, and `allSettled` with cancellation-aware behavior.
* **Roblox Utilities:** Includes `delay`, `timeout`, `retry`, and `fromEvent` for common asynchronous workflows.
* **Coroutine Integration:** `await` allows a coroutine to yield until a Promise settles without blocking other Roblox execution.
* **Error Handling:** Rejections propagate through chains and can be handled with `catch` or converted into thrown errors with `expect`.
* **Resource Cleanup:** `onCancel` hooks allow asynchronous operations to clean up connections, timers, and other resources when cancelled.

---

## API

### Creating Promises

```lua
promise.new(function(resolve, reject, onCancel)
	-- asynchronous work

	resolve(value)
end)
```

Call `resolve(...)` when the operation succeeds and `reject(...)` when it fails.

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

`all`, `race`, and `any` automatically cancel their remaining subscriptions when their outcome is determined.

---

## Testing

The library includes a dedicated test suite covering Promise state transitions, cancellation, chaining, thenable assimilation, cleanup, combinators, timeouts, retries, and cancellation races.

Current test status:

```text
22 passed, 0 failed
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
