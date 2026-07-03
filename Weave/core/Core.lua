-- core/Core.lua — el motor reactivo: signal, effect, batch. (computed y scope: bloques siguientes.)
-- Lua 5.1 PURO: este archivo no puede llamar ninguna API de WoW (ADR-0004).
--
-- Modelo: un effect en ejecución se registra como observador de cada señal que LEE
-- (auto-tracking). Al escribir una señal, sus observadores se encolan y se ejecutan
-- (re-trackeando sus dependencias desde cero, para que las deps sean siempre las de la
-- última ejecución). `batch` difiere la ejecución al final para coalescer escrituras.
--
-- Contrato de rendimiento (API-v0 §1): el camino set()→notify no crea tablas nuevas;
-- la cola y los sets de deps/observadores se reutilizan.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.signal then return end -- copia repetida: la primera gana (v0)

------------------------------------------------------------------------------
-- Estado interno del grafo (por copia de la lib)
------------------------------------------------------------------------------
local currentObserver = nil -- effect cuyo fn está corriendo (colector de dependencias)
local batchDepth      = 0   -- >0 = dentro de Weave.batch
local flushing        = false
local queue, queued   = {}, {} -- cola FIFO de effects pendientes + set de dedup

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
  untrackDeps(eff) -- re-tracking: las deps se reconstruyen en cada ejecución
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
  while i < #queue do -- los effects pueden encolar más (cascadas): el while los alcanza
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
local SignalMT -- forward (lo necesita el guard de set)

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
  -- ¿cambió de verdad? comparación protegida: si comparar lanza (secret values), se asume que cambió
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
