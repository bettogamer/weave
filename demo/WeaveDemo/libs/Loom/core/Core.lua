-- Core.lua — the pure-Lua promise engine (ADR-0003: ZERO WoW API).
-- Always-async resolution (no-Zalgo, ADR-0009): callbacks never run synchronously in the
-- stack of resolve()/reject(); everything settles through the microtask queue, drained by
-- the injected scheduler (wow/) or manually via Loom.flushMicrotasks() (headless tests).
-- Structural cancellation (ADR-0011): promises count consumers; cancelling the last consumer
-- of a chain tears it down to the root (which deregisters its event in M2 via _onCancel).

local Loom = LibStub("Loom-1.0")

--------------------------------------------------------------------------------
-- Microtask scheduler
--------------------------------------------------------------------------------
-- FIFO queue with head/tail indices (nested enqueues during a drain are handled by the
-- while loop growing `tail`). `scheduler` is injected by wow/ in M2; nil in headless.
local queue = {}
local head, tail = 1, 0
local scheduler
local scheduled = false

local function schedule(task)
  tail = tail + 1
  queue[tail] = task
  if scheduler and not scheduled then
    scheduled = true
    scheduler(Loom.flushMicrotasks)
  end
end

-- Drains the queue in FIFO order until empty. In WoW the injected scheduler calls this once
-- per tick; in headless tests the harness calls it explicitly.
function Loom.flushMicrotasks()
  scheduled = false
  while head <= tail do
    local task = queue[head]
    queue[head] = nil
    head = head + 1
    task()
  end
  head, tail = 1, 0
end

-- wow/ injects the real scheduler (C_Timer.After(0) / frame ticker) at load. Without it
-- (headless) microtasks wait for flushMicrotasks(); execution never falls back to sync.
function Loom._setScheduler(fn) scheduler = fn end

--------------------------------------------------------------------------------
-- Taint detection + unhandled-rejection reporting (ADR-0004 / ADR-0006)
--------------------------------------------------------------------------------
-- Detector injected by wow/ (M3): fn(v) -> true if v is a secret value OR secret table.
-- nil in headless => nothing is secret (safe default).
local secretDetector
function Loom._setSecretDetector(fn) secretDetector = fn end

-- Error sink injected by wow/ (M2): fn(promise, reason) for unhandled rejections. nil in
-- headless => silent. Distinct hook from the secret detector.
local errorSink
function Loom._setErrorSink(fn) errorSink = fn end

-- Recognizes error messages produced by operating on a secret. The wow/ layer uses the SAME
-- criterion in its own guards (event match, maps). Exposed per API-v0 §3/§9.
local function isSecretError(msg)
  msg = tostring(msg)
  return msg:find("a secret", 1, true) ~= nil or msg:find("ForceTaint_Strong", 1, true) ~= nil
end
Loom._isSecretError = isSecretError

--------------------------------------------------------------------------------
-- Promise type
--------------------------------------------------------------------------------
local Promise = {}
Promise.__index = Promise

local function isPromise(v)
  return type(v) == "table" and getmetatable(v) == Promise
end

local function newPromise()
  -- _parent / _consumers / _onCancel are added lazily (structural cancellation).
  return setmetatable({ _state = "pending", _value = nil, _handlers = nil }, Promise)
end

local settle, resolveWith, runHandler, applyFinally, cancelPromise, rejectFromCallback

-- Transition pending -> fulfilled/rejected and schedule registered handlers. One-shot:
-- a promise settles exactly once (ignored if already settled or cancelled).
settle = function(p, state, value)
  if p._state ~= "pending" then return end
  p._state = state
  p._value = value
  -- Mark taint: the detector never operates the value (getmetatable / issecretvalue only).
  p._secret = (secretDetector ~= nil and secretDetector(value)) and true or false

  local hs = p._handlers
  p._handlers = nil
  if hs then
    for i = 1, #hs do
      local h = hs[i]
      schedule(function() runHandler(p, h) end)
    end
  end

  -- Unhandled rejection: if nobody ever attached a handler, report ONCE at drain end.
  if state == "rejected" and not p._handled then
    schedule(function()
      if not p._handled and not p._reported then
        p._reported = true
        if errorSink then errorSink(p, value) end
      end
    end)
  end
end

-- Fulfil p with a value, adopting it if the value is itself a promise (no nesting).
resolveWith = function(p, value)
  if p._state ~= "pending" then return end
  if isPromise(value) then
    value:next(
      function(v) settle(p, "fulfilled", v) end,
      function(e) settle(p, "rejected", e) end
    )
  else
    settle(p, "fulfilled", value)
  end
end

-- Apply a finally callback and settle its child preserving the original outcome (or
-- overriding it if the callback throws). `kind` is the parent's settled state.
applyFinally = function(fn, child, kind, value)
  local ok, err = pcall(fn)
  if not ok then
    settle(child, "rejected", err)
  elseif kind == "fulfilled" then
    resolveWith(child, value)
  elseif kind == "rejected" then
    settle(child, "rejected", value)
  else -- "cancelled": finally ran, the cancel propagates to the child
    cancelPromise(child)
  end
end

-- Reject child with an error thrown by a callback. Chokepoint (ADR-0004): if the error came
-- from operating a secret, mark the child secret so a :catch can tell it apart from a normal
-- crash (settle already ran; here we just flag it — the detector doesn't flag error strings).
rejectFromCallback = function(child, err)
  settle(child, "rejected", err)
  if isSecretError(err) then child._secret = true end
end

-- Run one registered handler against the settled parent p, settling its child promise.
runHandler = function(p, h)
  if h.onFinally then
    applyFinally(h.onFinally, h.child, p._state, p._value)
    return
  end
  local child, state, value = h.child, p._state, p._value
  if state == "fulfilled" then
    if h.onOk then
      local ok, res = pcall(h.onOk, value)
      if ok then resolveWith(child, res) else rejectFromCallback(child, res) end
    else
      resolveWith(child, value) -- pass-through
    end
  else -- rejected
    if h.onErr then
      local ok, res = pcall(h.onErr, value)
      if ok then resolveWith(child, res) else rejectFromCallback(child, res) end
    else
      settle(child, "rejected", value) -- pass-through (keeps the parent's _secret intent)
    end
  end
end

-- Cancel p (only if pending): mark cancelled, run its cleanup hook synchronously (so the
-- underlying event is deregistered at once), cascade DOWN to children, then propagate UP to
-- the parent if it loses its last consumer (ADR-0011).
cancelPromise = function(p)
  if p._state ~= "pending" then return end
  p._state = "cancelled"

  if p._onCancel then
    local fn = p._onCancel
    p._onCancel = nil
    pcall(fn) -- cleanup must not throw out of cancel
  end

  local hs = p._handlers
  p._handlers = nil
  if hs then
    for i = 1, #hs do
      local h = hs[i]
      if h.onFinally then
        local fn = h.onFinally
        schedule(function() applyFinally(fn, h.child, "cancelled") end)
      else
        cancelPromise(h.child) -- downstream cascade; onOk/onErr never run
      end
    end
  end

  local parent = p._parent
  if parent and parent._state == "pending" then
    parent._consumers = (parent._consumers or 1) - 1
    if parent._consumers <= 0 then
      cancelPromise(parent) -- upstream: nobody left waiting -> tear the source down
    end
  end
end

-- Register a handler on self, linking the child for structural cancellation.
local function registerHandler(self, h)
  local child = newPromise()
  h.child = child
  child._parent = self
  self._consumers = (self._consumers or 0) + 1
  self._handled = true -- someone is observing self; its rejection is not "unhandled"
  local state = self._state
  if state == "pending" then
    self._handlers = self._handlers or {}
    self._handlers[#self._handlers + 1] = h
  elseif state == "cancelled" then
    if h.onFinally then
      schedule(function() applyFinally(h.onFinally, child, "cancelled") end)
    else
      cancelPromise(child) -- chaining onto an already-cancelled promise cancels the child
    end
  else -- fulfilled / rejected: run soon
    schedule(function() runHandler(self, h) end)
  end
  return child
end

--------------------------------------------------------------------------------
-- Promise methods
--------------------------------------------------------------------------------
--- Current lifecycle state. Debug/testing only — don't build logic on this in production.
function Promise:status() return self._state end

--- Whether the last settled value/error is a secret (value, secret table, or a callback that
--- crashed operating one). False if no detector is injected (headless). See §3 truth table.
function Promise:isSecret() return self._secret == true end

--- Chain. Returns a NEW promise settled by what the callback does (value, promise, or throw).
function Promise:next(onOk, onErr)
  return registerHandler(self, { onOk = onOk, onErr = onErr })
end

--- Sugar for the rejection path only: p:next(nil, onErr).
function Promise:catch(onErr) return self:next(nil, onErr) end

--- Side effect that runs on fulfil, reject AND cancel, with NO arguments. Preserves the
--- original outcome downstream — unless `fn` itself throws (then the returned promise rejects).
function Promise:finally(fn)
  return registerHandler(self, { onFinally = fn })
end

--- Cancel this promise (no-op if already settled). Structural: see cancelPromise.
function Promise:cancel()
  cancelPromise(self)
  return self
end

--------------------------------------------------------------------------------
-- Constructors
--------------------------------------------------------------------------------
--- Generic constructor. The executor gets (resolve, reject) and runs asynchronously; a throw
--- inside it becomes reject(error).
function Loom.new(executor)
  local p = newPromise()
  schedule(function()
    local ok, err = pcall(executor,
      function(v) resolveWith(p, v) end,
      function(r) settle(p, "rejected", r) end)
    if not ok then settle(p, "rejected", err) end
  end)
  return p
end

--- Already-fulfilled promise (callbacks still run async). If `value` is a promise, returns
--- it unchanged (no nesting).
function Loom.resolve(value)
  if isPromise(value) then return value end
  local p = newPromise()
  schedule(function() settle(p, "fulfilled", value) end)
  return p
end

--- Already-rejected promise. `reason` is passed verbatim to :catch().
function Loom.reject(reason)
  local p = newPromise()
  schedule(function() settle(p, "rejected", reason) end)
  return p
end

--- pcall wrapper: resolves fn()'s return, or rejects if it throws. Async (microtask).
function Loom.try(fn)
  return Loom.new(function(resolve) resolve(fn()) end)
end

--------------------------------------------------------------------------------
-- Combinators (ADR-0011: settle -> cancel the still-pending inputs; cancelling the
-- combined cancels its inputs. ADR-0004: values are never operated on, only stored.)
--------------------------------------------------------------------------------
-- Cancel every input that is still pending (the winner/failed one is already settled).
local function cancelPendingInputs(inputs)
  for i = 1, #inputs do
    if inputs[i]._state == "pending" then cancelPromise(inputs[i]) end
  end
end

-- Normalize a list entry to a promise (a plain value becomes Loom.resolve(value)).
local function asPromise(item)
  return isPromise(item) and item or Loom.resolve(item)
end

--- Waits for ALL to fulfil; resolves with the values in order. Fail-fast: the first reject
--- rejects the combined and cancels the rest.
function Loom.all(list)
  local combined = newPromise()
  local inputs, results = {}, {}
  local remaining, done = #list, false
  combined._onCancel = function() cancelPendingInputs(inputs) end

  local function finish(state, value)
    if done then return end
    done = true
    cancelPendingInputs(inputs)
    settle(combined, state, value)
  end

  if remaining == 0 then
    schedule(function() settle(combined, "fulfilled", results) end)
    return combined
  end
  for i = 1, #list do
    local p = asPromise(list[i])
    inputs[i] = p
    p:next(
      function(v)
        results[i] = v
        remaining = remaining - 1
        if remaining == 0 then finish("fulfilled", results) end
      end,
      function(e) finish("rejected", e) end
    )
  end
  return combined
end

--- Waits for all to settle; resolves with { status, value|reason } per entry. Never rejects.
function Loom.allSettled(list)
  local combined = newPromise()
  local inputs, results = {}, {}
  local remaining = #list
  combined._onCancel = function() cancelPendingInputs(inputs) end

  if remaining == 0 then
    schedule(function() settle(combined, "fulfilled", results) end)
    return combined
  end
  local function record(i, entry)
    results[i] = entry
    remaining = remaining - 1
    if remaining == 0 then settle(combined, "fulfilled", results) end
  end
  for i = 1, #list do
    local p = asPromise(list[i])
    inputs[i] = p
    p:next(
      function(v) record(i, { status = "fulfilled", value = v }) end,
      function(e) record(i, { status = "rejected", reason = e }) end
    )
  end
  return combined
end

--- First to settle (fulfil OR reject) wins; the rest are cancelled.
function Loom.race(list)
  local combined = newPromise()
  local inputs, done = {}, false
  combined._onCancel = function() cancelPendingInputs(inputs) end

  local function finish(state, value)
    if done then return end
    done = true
    cancelPendingInputs(inputs)
    settle(combined, state, value)
  end
  for i = 1, #list do
    local p = asPromise(list[i])
    inputs[i] = p
    p:next(function(v) finish("fulfilled", v) end, function(e) finish("rejected", e) end)
  end
  return combined
end

--- First to FULFIL wins; the rest are cancelled. If all reject, rejects with an aggregate.
function Loom.any(list)
  local combined = newPromise()
  local inputs, errors = {}, {}
  local remaining, done = #list, false
  combined._onCancel = function() cancelPendingInputs(inputs) end

  if remaining == 0 then
    schedule(function()
      settle(combined, "rejected", { code = "aggregate", message = "any: empty list", errors = errors })
    end)
    return combined
  end
  for i = 1, #list do
    local p = asPromise(list[i])
    inputs[i] = p
    p:next(
      function(v)
        if done then return end
        done = true
        cancelPendingInputs(inputs)
        settle(combined, "fulfilled", v)
      end,
      function(e)
        errors[i] = e
        remaining = remaining - 1
        if remaining == 0 and not done then
          done = true
          settle(combined, "rejected", { code = "aggregate", message = "all promises rejected", errors = errors })
        end
      end
    )
  end
  return combined
end

--------------------------------------------------------------------------------
-- Internal hooks (used by the wow/ layer and combinators; not public API)
--------------------------------------------------------------------------------
-- Predicate so the wow/ layer recognizes core promises.
Loom._isPromise = isPromise

-- The Promise metatable, exposed so the wow/ layer can attach methods that need WoW APIs
-- (e.g. p:timeout needs C_Timer). Not public.
Loom._Promise = Promise

-- Register a cleanup callback fired when p is cancelled (wow/ deregisters its event here).
function Loom._setOnCancel(p, fn) p._onCancel = fn; return p end

-- A promise plus synchronous resolve/reject handles, for the wow/ layer to settle from event
-- and timer callbacks. Settles synchronously when called, but downstream callbacks still run
-- async (handlers are scheduled) — no-Zalgo holds.
function Loom._deferred()
  local p = newPromise()
  return p,
    function(v) resolveWith(p, v) end,
    function(r) settle(p, "rejected", r) end
end

-- Whether a value is secret per the injected detector (false if none — headless / no wow).
function Loom._isSecret(v)
  return (secretDetector ~= nil and secretDetector(v)) and true or false
end

-- Wraps p so that if it fulfils with a SECRET value, the returned promise fulfils with
-- `fallback` instead (marked isSecret — readers see the fallback but know it was tainted;
-- §3 truth table). No-op if fallback is nil. Used by the catalog for opts.fallback (ADR-0004).
function Loom._withFallback(p, fallback)
  if fallback == nil then return p end
  local out, resolve, reject = Loom._deferred()
  p:next(
    function(v)
      if secretDetector and secretDetector(v) then
        settle(out, "fulfilled", fallback)
        out._secret = true
      else
        resolve(v)
      end
    end,
    reject
  )
  Loom._setOnCancel(out, function() p:cancel() end)
  return out
end
