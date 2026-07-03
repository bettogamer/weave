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

-- Default map: the signal takes the event's first argument.
local function firstArg(first) return first end

------------------------------------------------------------------------------
-- Dispatchers
-- One shared frame multiplexes every plain-event registration. Unit events get
-- one small frame per (event, unit) pair instead: RegisterUnitEvent holds at
-- most two units per frame, so a single frame cannot host N different filters.
------------------------------------------------------------------------------

-- Fans one event out to its subscribers. NOTE (v0): each signal:set() flushes on
-- its own; several signals fed by the SAME event update sequentially, not as one
-- batch (batching the fan-out without allocating per event needs a vararg pack —
-- revisit if it ever bites).
local function dispatch(subs, ...)
  for i = 1, #subs do
    local sub = subs[i]
    sub.signal:set(sub.map(...))
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
  entry.subs[#entry.subs + 1] = { signal = signal, map = map }
  -- Seed: expose the CURRENT value right away instead of waiting for the first
  -- event (signal opts apply: a secret seed with a declared fallback degrades).
  signal:set(map(unit))
  return signal
end
