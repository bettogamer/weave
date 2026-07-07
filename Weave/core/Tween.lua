-- core/Tween.lua — pure interpolation engine: the math behind Weave.tween (M8,
-- ADR-0008). PURE Lua 5.1: this file must not call any WoW API (ADR-0004) — it has
-- no clock. The wow/ driver owns GetTime and feeds elapsed seconds in; here we only
-- turn (from, to, elapsed, duration, easing) into a value. Numbers and arrays alike.
--
-- Weave._tweenEngine(from, to, duration, easing) → anim
--   anim:at(elapsed) → value, done
--     value : interpolated number, OR the SAME reused array (mutated in-place) so a
--             per-frame tick allocates nothing (§1 zero-allocation contract).
--     done  : true once elapsed >= duration (also at duration 0, no divide-by-zero).
-- Weave.easing = { linear, inQuad, outQuad, inOutQuad } — pure curves (t in [0,1] → [0,1]).

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave._tweenEngine then return end -- lib missing or duplicate copy

local function clamp01(t)
  if t < 0 then return 0 elseif t > 1 then return 1 else return t end
end

Weave.easing = Weave.easing or {
  linear    = function(t) return t end,
  inQuad    = function(t) return t * t end,
  outQuad   = function(t) return t * (2 - t) end,
  inOutQuad = function(t)
    if t < 0.5 then return 2 * t * t end
    local u = -2 * t + 2
    return 1 - (u * u) / 2
  end,
}

-- Progress fraction eased to [0,1], plus whether the animation has finished.
local function progress(self, elapsed)
  local done = elapsed >= self.duration
  local t = self.duration > 0 and clamp01(elapsed / self.duration) or 1
  return self.easing(t), done
end

local Scalar = {}
Scalar.__index = Scalar
function Scalar:at(elapsed)
  local e, done = progress(self, elapsed)
  return self.from + (self.to - self.from) * e, done
end

local Array = {}
Array.__index = Array
function Array:at(elapsed)
  local e, done = progress(self, elapsed)
  local from, to, buf = self.from, self.to, self.buf
  for i = 1, #from do buf[i] = from[i] + (to[i] - from[i]) * e end
  return buf, done
end

--- Builds an interpolation from `from` to `to` over `duration` seconds using `easing`
--- (defaults to outQuad). `from`/`to` are a number or two same-length number arrays.
function Weave._tweenEngine(from, to, duration, easing)
  easing = easing or Weave.easing.outQuad
  if type(from) == "table" then
    return setmetatable({ from = from, to = to, duration = duration, easing = easing, buf = {} }, Array)
  end
  return setmetatable({ from = from, to = to, duration = duration, easing = easing }, Scalar)
end
