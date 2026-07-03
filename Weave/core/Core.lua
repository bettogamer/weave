-- core/Core.lua — the reactive engine: signal, effect, batch. (computed and scope: next blocks.)
-- PURE Lua 5.1: this file must not call any WoW API (ADR-0004).
--
-- Model: while an effect runs, it registers itself as an observer of every signal it READS
-- (auto-tracking). Writing a signal enqueues its observers and runs them, re-tracking their
-- dependencies from scratch so deps always reflect the latest execution. `batch` defers the
-- runs to the end to coalesce writes.
--
-- Performance contract (API-v0 §1): the set()→notify path allocates no new tables;
-- the queue and the dep/observer sets are reused.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.signal then return end -- duplicate copy: first one wins (v0)

------------------------------------------------------------------------------
-- Internal graph state (per library copy)
------------------------------------------------------------------------------
local currentObserver = nil -- effect whose fn is running (dependency collector)
local batchDepth      = 0   -- >0 = inside Weave.batch
local flushing        = false
local queue, queued   = {}, {} -- FIFO queue of pending effects + dedup set

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------
local function untrackDeps(eff)
  local deps = eff._deps
  for i = #deps, 1, -1 do
    deps[i]._observers[eff] = nil
    deps[i] = nil
  end
end

local function runEffect(eff)
  if eff._disposed then return end
  untrackDeps(eff) -- re-tracking: deps are rebuilt on every run
  local prev = currentObserver
  currentObserver = eff
  local ok, err = pcall(eff._fn)
  currentObserver = prev
  if not ok then error(err, 0) end
end

local function flush()
  if flushing then return end
  flushing = true
  local firstErr = nil
  local i = 0
  while i < #queue do -- effects may enqueue more (cascades): the while picks them up
    i = i + 1
    local eff = queue[i]
    queued[eff] = nil
    local ok, err = pcall(runEffect, eff)
    if not ok and firstErr == nil then firstErr = err end
  end
  for j = #queue, 1, -1 do queue[j] = nil end
  flushing = false
  if firstErr ~= nil then error(firstErr, 0) end
end

local function scheduleObservers(sig)
  for eff in pairs(sig._observers) do
    if not eff._disposed and not queued[eff] then
      queued[eff] = true
      queue[#queue + 1] = eff
    end
  end
  if batchDepth == 0 then flush() end
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
    error("Weave.effect: se esperaba una function, llegó " .. type(fn), 2)
  end
  local eff = setmetatable({ _fn = fn, _deps = {}, _disposed = false }, EffectMT)
  runEffect(eff)
  return eff
end

------------------------------------------------------------------------------
-- Signals
------------------------------------------------------------------------------
local SignalMT -- forward declaration (needed by the set() guard)

local function rawEquals(a, b) return a == b end

local function readSignal(sig)
  local obs = currentObserver
  if obs and not sig._observers[obs] then
    sig._observers[obs] = true
    obs._deps[#obs._deps + 1] = sig
  end
  return sig._value
end

local SignalMethods = {}

function SignalMethods:set(v)
  if getmetatable(self) ~= SignalMT then
    error("Weave: usa señal:set(v) (con dos puntos), no señal.set(v)", 2)
  end
  -- did it really change? protected compare: if comparing throws (secret values), assume it changed
  local eq = self._equals or rawEquals
  local ok, same = pcall(eq, self._value, v)
  if ok and same then return end
  self._value = v
  scheduleObservers(self)
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
    error("Weave.signal: opts debe ser una tabla, llegó " .. type(opts), 2)
  end
  if opts and opts.equals ~= nil and type(opts.equals) ~= "function" then
    error("Weave.signal: opts.equals debe ser una function", 2)
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
    error("Weave.batch: se esperaba una function, llegó " .. type(fn), 2)
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
