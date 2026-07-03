-- wow/Events.lua — game events as signals: fromEvent / fromUnitEvent (API-v0 §2).
-- First wow/ file to load: it also injects the client's secret detector into the
-- pure-Lua core (the ADR-0003/0004 boundary). On clients without issecretvalue
-- (pre-12.0) the core keeps its safe default: nothing is secret.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.fromEvent then return end -- lib missing or duplicate copy

local CreateFrame = CreateFrame

if issecretvalue then
  Weave._setSecretDetector(issecretvalue)
end

-- Visible side of the chokepoints (ADR-0003): one soft chat line per degraded
-- site, never the red error popup.
local function softWarn(what, err)
  print("|cffffd100Weave:|r " .. what .. " degraded on a secret value (12.0 taint): " .. tostring(err))
end

-- Effects/binds: the once-per-site accounting lives in the core.
Weave._setSecretWarning(function(err) softWarn("an effect", err) end)

-- Default map: the signal takes the event's first argument.
local function firstArg(first) return first end

------------------------------------------------------------------------------
-- Dispatchers
-- One shared frame multiplexes every plain-event registration. Unit events get
-- one small frame per (event, unit) pair instead: RegisterUnitEvent holds at
-- most two units per frame, so a single frame cannot host N different filters.
------------------------------------------------------------------------------

-- Runs ONE subscriber's map under the secret-error guard (ADR-0003): a map that
-- OPERATES on a secret degrades that update only — the registration stays alive,
-- other subscribers still run, and the warning fires once per registration.
-- Non-secret errors are real dev bugs and propagate intact.
local function applySub(sub, ...)
  local ok, result = pcall(sub.map, ...)
  if not ok then
    if Weave._isSecretError(result) then
      if not sub.warned then
        sub.warned = true
        softWarn("an event map", result)
      end
      return
    end
    error(result, 0)
  end
  sub.signal:set(result)
end

-- Fans one event out to its subscribers. NOTE (v0): each signal:set() flushes on
-- its own; several signals fed by the SAME event update sequentially, not as one
-- batch (batching the fan-out without allocating per event needs a vararg pack —
-- revisit if it ever bites).
local function dispatch(subs, ...)
  for i = 1, #subs do
    applySub(subs[i], ...)
  end
end

local sharedFrame     -- created on the first fromEvent registration
local sharedSubs = {} -- event -> array of { signal, map }

local function onSharedEvent(_, event, ...)
  local subs = sharedSubs[event]
  if subs then dispatch(subs, ...) end
end

function Weave.fromEvent(event, map, opts)
  if type(event) ~= "string" then
    error("Weave.fromEvent: expected an event name (string), got " .. type(event), 2)
  end
  if map ~= nil and type(map) ~= "function" then
    error("Weave.fromEvent: map must be a function, got " .. type(map), 2)
  end
  local signal = Weave.signal(opts and opts.initial, opts)
  local subs = sharedSubs[event]
  if not subs then
    subs = {}
    sharedSubs[event] = subs
    if not sharedFrame then
      sharedFrame = CreateFrame("Frame")
      sharedFrame:Hide()
      sharedFrame:SetScript("OnEvent", onSharedEvent)
    end
    sharedFrame:RegisterEvent(event)
  end
  subs[#subs + 1] = { signal = signal, map = map or firstArg }
  return signal
end

local unitEntries = {} -- "event\0unit" -> { frame, subs }

function Weave.fromUnitEvent(event, unit, map, opts)
  if type(event) ~= "string" then
    error("Weave.fromUnitEvent: expected an event name (string), got " .. type(event), 2)
  end
  if type(unit) ~= "string" then
    error("Weave.fromUnitEvent: expected a unit (string), got " .. type(unit), 2)
  end
  if map ~= nil and type(map) ~= "function" then
    error("Weave.fromUnitEvent: map must be a function, got " .. type(map), 2)
  end
  map = map or firstArg
  local signal = Weave.signal(nil, opts)
  local key = event .. "\0" .. unit
  local entry = unitEntries[key]
  if not entry then
    entry = { subs = {}, frame = CreateFrame("Frame") }
    entry.frame:Hide()
    local subs = entry.subs
    entry.frame:SetScript("OnEvent", function(_, _, ...)
      dispatch(subs, ...)
    end)
    entry.frame:RegisterUnitEvent(event, unit)
    unitEntries[key] = entry
  end
  local sub = { signal = signal, map = map }
  entry.subs[#entry.subs + 1] = sub
  -- Seed: expose the CURRENT value right away instead of waiting for the first
  -- event. Same guard as dispatch: a map that operates on a secret at load must
  -- not blow up addon loading — the signal just starts empty.
  applySub(sub, unit)
  return signal
end
