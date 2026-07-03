-- core/Core.lua — the reactive engine: signal, computed, effect, batch, scope.
-- PURE Lua 5.1: this file must not call any WoW API (ADR-0004).
--
-- Model: while an effect (or a computed's formula) runs, it registers itself as an
-- observer of every signal/computed it READS (auto-tracking), re-tracking from scratch on
-- every run so deps always reflect the latest execution. Writing a signal marks dependent
-- computeds dirty and enqueues dependent effects. The flush loop recomputes dirty computeds
-- FIRST and only propagates further when their value actually changed (equality cut), then
-- runs effects — draining computeds again after each one. This keeps updates glitch-free
-- (diamond dependencies see one consistent generation) and lets unchanged computeds stop
-- the propagation chain.
--
-- Performance contract (API-v0 §1): the set()→notify path allocates no new tables;
-- queues and dep/observer sets are reused.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.signal then return end -- duplicate copy: first one wins (v0)

------------------------------------------------------------------------------
-- Internal graph state (per library copy)
------------------------------------------------------------------------------
local currentObserver = nil -- effect or computed whose fn is running (dependency collector)
local currentScope    = nil -- scope whose run() is active (ownership collector)
local batchDepth      = 0   -- >0 = inside Weave.batch
local flushing        = false
local eQueue, eQueued = {}, {} -- FIFO queue of pending effects + dedup set
local cQueue, cQueued = {}, {} -- FIFO queue of dirty computeds + dedup set

local function rawEquals(a, b) return a == b end

------------------------------------------------------------------------------
-- Secret values (WoW 12.0+) — core side of ADR-0003
-- The core is pure Lua, so it cannot call issecretvalue directly: the wow/ layer
-- injects it here. Without injection nothing is secret (safe default, old clients).
------------------------------------------------------------------------------
local secretDetector = function() return false end

function Weave._setSecretDetector(fn)
  if type(fn) ~= "function" then
    error("Weave._setSecretDetector: expected a function, got " .. type(fn), 2)
  end
  secretDetector = fn
end

-- Recognizes the client's secret-value error wording (chokepoint pattern, ADR-0003).
local function isSecretError(msg)
  msg = tostring(msg)
  return msg:find("a secret", 1, true) ~= nil
      or msg:find("ForceTaint_Strong", 1, true) ~= nil
end

-- Shared with the wow/ layer (event-map guard): ONE source of truth for what
-- counts as a secret-shaped error.
Weave._isSecretError = isSecretError

-- Shared with outer layers (store): query the injected detector directly.
function Weave._isSecret(v)
  return secretDetector(v) and true or false
end

-- Shared with outer layers (ui): attaches a disposable handle to the scope whose
-- run() is active, so non-effect resources die with the scope too. No-op outside.
function Weave._attachToScope(handle)
  if currentScope then
    local items = currentScope._items
    items[#items + 1] = handle
  end
end

-- Visible soft warning for degraded effects, injected by the wow/ layer (print).
-- Headless / not injected: degradation is silent.
local secretWarning = nil

function Weave._setSecretWarning(fn)
  if type(fn) ~= "function" then
    error("Weave._setSecretWarning: expected a function, got " .. type(fn), 2)
  end
  secretWarning = fn
end

------------------------------------------------------------------------------
-- Dependency tracking (shared by effects and computeds)
------------------------------------------------------------------------------
local function untrackDeps(node)
  local deps = node._deps
  for i = #deps, 1, -1 do
    deps[i]._observers[node] = nil
    deps[i] = nil
  end
end

-- Registers `dep` (signal or computed) as a dependency of the running observer.
local function trackRead(dep)
  local obs = currentObserver
  if obs and not dep._observers[obs] then
    dep._observers[obs] = true
    obs._deps[#obs._deps + 1] = dep
  end
end

local flush -- forward declaration

-- Enqueues the observers of `node` after its value changed. `skip` avoids re-scheduling
-- the observer that is pulling the fresh value right now.
local function scheduleObservers(node, skip)
  for obs in pairs(node._observers) do
    if obs ~= skip then
      if obs._isComputed then
        obs._dirty = true
        if not cQueued[obs] then
          cQueued[obs] = true
          cQueue[#cQueue + 1] = obs
        end
      elseif not obs._disposed and not eQueued[obs] then
        eQueued[obs] = true
        eQueue[#eQueue + 1] = obs
      end
    end
  end
  if batchDepth == 0 then flush() end
end

------------------------------------------------------------------------------
-- Computeds (lazy + cached; recomputed via the queue or pulled on read)
------------------------------------------------------------------------------
-- Recomputes `c` and returns whether its value changed. Caller decides propagation.
local function recompute(c)
  untrackDeps(c)
  c._computing = true
  local prev = currentObserver
  currentObserver = c
  local ok, result = pcall(c._fn)
  currentObserver = prev
  c._computing = false
  if not ok then
    if isSecretError(result) then
      -- degrade, never crash (API-v0 §3 row 4): declared fallback, or last good value
      c._dirty = false
      c._secret = true
      local newVal = c._value
      if c._fallback ~= nil then newVal = c._fallback end
      local okEq, same = pcall(rawEquals, c._value, newVal)
      c._value = newVal
      return not (okEq and same)
    end
    c._dirty = true -- non-secret error: stay dirty so a later read retries, and propagate
    error(result, 0)
  end
  c._dirty = false
  c._secret = secretDetector(result) and true or false
  local okEq, same = pcall(rawEquals, c._value, result)
  c._value = result
  return not (okEq and same)
end

local ComputedMT

local function readComputed(c)
  if c._computing then
    error("Weave.computed: cycle detected — the formula reads itself (directly or through another computed)", 2)
  end
  trackRead(c)
  if c._dirty then
    -- pull: the reader needs a fresh value NOW; other observers get scheduled normally
    if recompute(c) then scheduleObservers(c, currentObserver) end
  end
  return c._value
end

local ComputedMethods = {}

function ComputedMethods:peek()
  if self._dirty and not self._computing then
    if recompute(self) then scheduleObservers(self, nil) end
  end
  return self._value
end

function ComputedMethods:isSecret()
  return self._secret == true
end

ComputedMT = { __call = readComputed, __index = ComputedMethods }

function Weave.computed(fn, opts)
  if type(fn) ~= "function" then
    error("Weave.computed: expected a function, got " .. type(fn), 2)
  end
  if opts ~= nil and type(opts) ~= "table" then
    error("Weave.computed: opts must be a table, got " .. type(opts), 2)
  end
  return setmetatable({
    _isComputed = true,
    _fn         = fn,
    _value      = nil,
    _dirty      = true,  -- lazy: first read computes
    _computing  = false,
    _observers  = {},
    _deps       = {},
    _fallback   = opts and opts.fallback or nil,
    _secret     = false,
  }, ComputedMT)
end

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------
local function runEffect(eff)
  if eff._disposed then return end
  untrackDeps(eff) -- re-tracking: deps are rebuilt on every run
  local prev = currentObserver
  currentObserver = eff
  local ok, err = pcall(eff._fn)
  currentObserver = prev
  if not ok then
    if isSecretError(err) then
      -- Chokepoint (ADR-0003): degrade instead of crashing. Deps tracked before the
      -- blow-up stay registered, so the effect revives when they turn normal again
      -- (known limit: a fn that blows before reading any signal never re-runs).
      if not eff._secretWarned then
        eff._secretWarned = true
        if secretWarning then secretWarning(err) end
      end
      return
    end
    error(err, 0)
  end
end

-- Recomputes every queued dirty computed, propagating only real changes.
-- Returns the first error (if any) instead of throwing, so flush can finish.
local function drainComputeds(firstErr)
  local i = 0
  while i < #cQueue do -- propagation may enqueue more: the while picks them up
    i = i + 1
    local c = cQueue[i]
    cQueued[c] = nil
    if c._dirty then
      local ok, changed = pcall(recompute, c)
      if not ok then
        if firstErr == nil then firstErr = changed end
      elseif changed then
        scheduleObservers(c, nil)
      end
    end
  end
  for j = #cQueue, 1, -1 do cQueue[j] = nil end
  return firstErr
end

flush = function()
  if flushing then return end
  flushing = true
  local firstErr = drainComputeds(nil)
  local i = 0
  while i < #eQueue do -- effects may enqueue more (cascades): the while picks them up
    i = i + 1
    local eff = eQueue[i]
    eQueued[eff] = nil
    local ok, err = pcall(runEffect, eff)
    if not ok and firstErr == nil then firstErr = err end
    firstErr = drainComputeds(firstErr) -- keep computeds fresh between effects
  end
  for j = #eQueue, 1, -1 do eQueue[j] = nil end
  flushing = false
  if firstErr ~= nil then error(firstErr, 0) end
end

local EffectMT = {
  __index = {
    dispose = function(self)
      if self._disposed then return end
      self._disposed = true
      untrackDeps(self)
    end,
  },
}

function Weave.effect(fn)
  if type(fn) ~= "function" then
    error("Weave.effect: expected a function, got " .. type(fn), 2)
  end
  local eff = setmetatable({ _fn = fn, _deps = {}, _disposed = false }, EffectMT)
  if currentScope then
    local items = currentScope._items
    items[#items + 1] = eff
  end
  runEffect(eff)
  return eff
end

------------------------------------------------------------------------------
-- Signals
------------------------------------------------------------------------------
local SignalMT -- forward declaration (needed by the set() guard)

local function readSignal(sig)
  trackRead(sig)
  return sig._value
end

local SignalMethods = {}

function SignalMethods:set(v)
  if getmetatable(self) ~= SignalMT then
    error("Weave: use signal:set(v) with a colon, not signal.set(v)", 2)
  end
  -- secret handling (API-v0 §3): with a declared fallback readers see the fallback;
  -- without one the secret flows as-is (for sinks that accept secrets)
  local secret = secretDetector(v) and true or false
  local effective = v
  if secret and self._fallback ~= nil then effective = self._fallback end
  -- did it really change? protected compare: if comparing throws (secret values), assume it changed
  local eq = self._equals or rawEquals
  local ok, same = pcall(eq, self._value, effective)
  self._secret = secret
  if ok and same then return end
  self._value = effective
  scheduleObservers(self, nil)
end

function SignalMethods:peek()
  return self._value
end

function SignalMethods:isSecret()
  return self._secret == true
end

SignalMT = { __call = readSignal, __index = SignalMethods }

function Weave.signal(initial, opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("Weave.signal: opts must be a table, got " .. type(opts), 2)
  end
  if opts and opts.equals ~= nil and type(opts.equals) ~= "function" then
    error("Weave.signal: opts.equals must be a function", 2)
  end
  return setmetatable({
    _value     = initial,
    _observers = {},
    _equals    = opts and opts.equals or nil,
    _fallback  = opts and opts.fallback or nil,
    _secret    = false,
  }, SignalMT)
end

------------------------------------------------------------------------------
-- Batch
------------------------------------------------------------------------------
function Weave.batch(fn)
  if type(fn) ~= "function" then
    error("Weave.batch: expected a function, got " .. type(fn), 2)
  end
  batchDepth = batchDepth + 1
  local ok, err = pcall(fn)
  batchDepth = batchDepth - 1
  if batchDepth == 0 then
    local okFlush, errFlush = pcall(flush)
    if ok and not okFlush then error(errFlush, 0) end
  end
  if not ok then error(err, 0) end
end

------------------------------------------------------------------------------
-- Scopes (collective ownership of effects; WoW has no unmount, disposal is explicit)
------------------------------------------------------------------------------
local ScopeMT = {
  __index = {
    run = function(self, fn)
      if self._disposed then
        error("Weave.scope: this scope was already disposed; create a new one", 2)
      end
      if type(fn) ~= "function" then
        error("Weave.scope: run() expected a function, got " .. type(fn), 2)
      end
      local prev = currentScope
      currentScope = self
      local ok, result = pcall(fn)
      currentScope = prev
      if not ok then error(result, 0) end
      return result
    end,
    dispose = function(self)
      if self._disposed then return end
      self._disposed = true
      local items = self._items
      for i = #items, 1, -1 do
        items[i]:dispose()
        items[i] = nil
      end
    end,
  },
}

function Weave.scope()
  return setmetatable({ _items = {}, _disposed = false }, ScopeMT)
end
