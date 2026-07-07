-- wow/Anim.lua — Weave.tween: a read-only reactive that slides toward the value of
-- a signal over time (API-v0 §2, M8/ADR-0008). The math lives in the pure core engine
-- (core/Tween.lua); here we own the clock (GetTime) and ONE shared driver frame that
-- advances every active tween per frame and HIDES itself when none remain (zero cost
-- at rest — a hidden frame gets no OnUpdate). Only mutates → combat-safe.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.tween then return end -- lib missing or duplicate copy

local CreateFrame, GetTime = CreateFrame, GetTime

-- The tween's value signal must notify on EVERY set: array results reuse one buffer
-- (in-place, §1 no-alloc), so an identity compare would read "unchanged" and never
-- repaint. Animation values differ each frame anyway, so notifying always is free.
local function alwaysChanged() return false end

------------------------------------------------------------------------------
-- Shared driver: one frame, one active set of tweens.
------------------------------------------------------------------------------
local driverFrame           -- created lazily on the first armed animation
local active     = {}       -- tween -> true (guards double-registration)
local activeList = {}       -- array mirror for the OnUpdate loop (no pairs per frame)

local function removeActive(tw)
  active[tw] = nil
  for i = #activeList, 1, -1 do
    if activeList[i] == tw then
      activeList[i] = activeList[#activeList]
      activeList[#activeList] = nil
      break
    end
  end
end

local function onTick()
  local now = GetTime()
  for i = #activeList, 1, -1 do -- backward: safe to swap-remove finished tweens
    local tw = activeList[i]
    local value, done = tw._engine:at(now - tw._start)
    if done then
      -- Unregister BEFORE notifying: the _current/_animating sets below run user
      -- effects synchronously; if one re-targets this tween (e.g. a ping-pong that
      -- reverses on :animating()=false), arm() must see it as inactive so it re-adds
      -- cleanly — otherwise this removal would clobber the re-arm and freeze the tween.
      active[tw] = nil
      activeList[i] = activeList[#activeList]
      activeList[#activeList] = nil
      tw._current:set(value)
      tw._animating:set(false)
    else
      tw._current:set(value)
    end
  end
  if #activeList == 0 and driverFrame then driverFrame:Hide() end
end

-- Snapshot the current value as the animation's origin (copy arrays so the previous
-- engine's reused buffer can't alias this one). Runs per target change, not per frame.
local function snapshot(v)
  if type(v) ~= "table" then return v end
  local copy = {}
  for i = 1, #v do copy[i] = v[i] end
  return copy
end

local function arm(tw, goal)
  tw._engine = Weave._tweenEngine(snapshot(tw._current:peek()), goal, tw._duration, tw._easing)
  tw._start = GetTime()
  tw._animating:set(true)
  if not active[tw] then
    active[tw] = true
    activeList[#activeList + 1] = tw
    if not driverFrame then
      driverFrame = CreateFrame("Frame")
      driverFrame:SetScript("OnUpdate", onTick)
    end
    driverFrame:Show()
  end
end

------------------------------------------------------------------------------
-- Tween handle (read-only reactive)
------------------------------------------------------------------------------
local TweenMethods = {}
function TweenMethods:peek()      return self._current:peek() end
function TweenMethods:isSecret()  return self._current:isSecret() end
function TweenMethods:animating() return self._animating() end -- tracks like any signal

function TweenMethods:dispose()
  if self._disposed then return end
  self._disposed = true
  if self._effect then self._effect:dispose() end
  if active[self] then removeActive(self) end
  self._animating:set(false)
  if #activeList == 0 and driverFrame then driverFrame:Hide() end
end

local TweenMT = {
  __call  = function(self) return self._current() end, -- read tracks the value signal
  __index = TweenMethods,
}

--- Weave.tween(target, opts?) → read-only reactive that eases toward target()'s value.
--- target: signal/computed/callable (animated) or a number/array literal (seeded, static).
function Weave.tween(target, opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("Weave.tween: opts must be a table, got " .. type(opts), 2)
  end
  opts = opts or {}

  local tw = setmetatable({
    _duration  = opts.duration or 0.3,
    _easing    = opts.easing or Weave.easing.outQuad,
    _current   = Weave.signal(nil, { equals = alwaysChanged, fallback = opts.fallback }),
    _animating = Weave.signal(false),
    _disposed  = false,
  }, TweenMT)

  local read = Weave.isReactive(target) and target or function() return target end

  local seeded = false
  tw._effect = Weave.effect(function()
    local goal = read() -- tracks target; holding/returning a secret is fine (no op)
    if not seeded then
      seeded = true
      tw._current:set(goal) -- seed at the target's current value (secret-safe via set)
      return
    end
    if Weave._isSecret(goal) then
      -- can't interpolate toward a secret: degrade (fallback/hold), stop animating;
      -- when a normal value returns, this effect re-runs and arms again.
      tw._current:set(goal)
      tw._animating:set(false)
      if active[tw] then removeActive(tw) end
      return
    end
    arm(tw, goal)
  end)

  Weave._attachToScope(tw) -- dies with the active scope (frees the driver registration)
  return tw
end
