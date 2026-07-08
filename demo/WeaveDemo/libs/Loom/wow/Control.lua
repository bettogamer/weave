-- Control.lua — time-based flow control that needs real timers (C_Timer): p:timeout and
-- Loom.retry. Both reuse the core's cancellation (ADR-0006/0011) so nothing leaks: a fired
-- timeout tears down the original event; cancelling the result tears down what's in flight.

local Loom = LibStub("Loom-1.0")

--- Rejects with { code="timeout", message } if `self` doesn't settle within `seconds`. On
--- timeout it also cancels `self` (deregistering its event). Cancelling the returned promise
--- cancels both `self` and the timeout timer. (API-v0 §2.)
function Loom._Promise:timeout(seconds, err)
  local self_ = self
  local out, resolve, reject = Loom._deferred()
  local settled = false

  local timer = C_Timer.NewTimer(seconds, function()
    if settled then return end
    settled = true
    self_:cancel() -- tear down the underlying event/listener (no leak)
    reject({ code = "timeout", message = err or "timeout" })
  end)

  self_:next(
    function(v) if not settled then settled = true; timer:Cancel(); resolve(v) end end,
    function(e) if not settled then settled = true; timer:Cancel(); reject(e) end end
  )

  -- Cancelling the result cancels the source and the timer (structural, ADR-0011).
  Loom._setOnCancel(out, function()
    timer:Cancel()
    self_:cancel()
  end)
  return out
end

--- Retries `factory` up to opts.times (default 3), waiting opts.delay seconds (default 0)
--- between attempts. Resolves on the first success; on exhaustion rejects with the last error.
--- Cancelling stops retrying and cancels the in-flight attempt / delay timer. (API-v0 §2.)
function Loom.retry(factory, opts)
  opts = opts or {}
  local times = opts.times or 3
  local delay = opts.delay or 0
  local out, resolve, reject = Loom._deferred()
  local current, timer, cancelled

  local function attempt(remaining)
    if cancelled then return end
    current = factory()
    current:next(
      function(v) resolve(v) end,
      function(e)
        current = nil
        if cancelled then return end
        if remaining <= 1 then
          reject(e) -- exhausted: propagate the last attempt's error (no wrapper code)
        else
          timer = C_Timer.NewTimer(delay, function() timer = nil; attempt(remaining - 1) end)
        end
      end
    )
  end

  Loom._setOnCancel(out, function()
    cancelled = true
    if timer then timer:Cancel(); timer = nil end
    if current then current:cancel() end
  end)

  attempt(times)
  return out
end
