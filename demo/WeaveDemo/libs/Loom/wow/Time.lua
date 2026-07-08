-- Time.lua — the wow/ layer's foundation. First wow/ file loaded, so the core's injected hooks
-- are live before any other wow/ file runs: it wires the real microtask scheduler and error
-- sink into the pure core, and provides the time-based promises (after / nextFrame).

local Loom = LibStub("Loom-1.0")

-- Real microtask scheduler: drain on the next frame via C_Timer.After(0) (ADR-0009).
Loom._setScheduler(function(drain) C_Timer.After(0, drain) end)

-- Error sink: surface unhandled rejections once (the core guarantees "once"). Secret-operation
-- errors degrade to a soft note instead of a scary crash line (ADR-0004 / ADR-0006).
Loom._setErrorSink(function(_, reason)
  local msg = (type(reason) == "table" and reason.message) or tostring(reason)
  if Loom._isSecretError(msg) then
    print("|cffffcc00Loom|r: a resolved value was secret (tainted); degraded.")
  else
    print("|cffff5555Loom|r unhandled rejection: " .. msg)
  end
end)

--- Resolves (with nil) after `seconds`. Cancelable: cancelling deregisters the timer (no leak).
function Loom.after(seconds)
  local p, resolve = Loom._deferred()
  local timer = C_Timer.NewTimer(seconds, function() resolve(nil) end)
  Loom._setOnCancel(p, function() timer:Cancel() end)
  return p
end

--- Resolves on the next frame. Cancelable (same no-leak guarantee as after).
function Loom.nextFrame()
  local p, resolve = Loom._deferred()
  local timer = C_Timer.NewTimer(0, function() resolve(nil) end)
  Loom._setOnCancel(p, function() timer:Cancel() end)
  return p
end
