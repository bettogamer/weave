-- Inspect.lua — Loom.inspect, the one catalog entry that isn't a thin Loom.event wrapper.
-- NotifyInspect is server-throttled (one at a time) and INSPECT_READY delivers a GUID, not a
-- unit — so inspect owns a FIFO queue: the head fires NotifyInspect, and each INSPECT_READY
-- resolves the head and pumps the next (ADR-0007, minimal serialization for v0).

local Loom = LibStub("Loom-1.0")

local frame = CreateFrame("Frame")
local queue = {}   -- pending records: { unit, guid, resolve, _cancelled }
local current      -- the in-flight record (nil when idle)

local function inspectData(unit)
  return {
    specialization = GetInspectSpecialization(unit),
    itemLevel = C_PaperDollInfo.GetInspectItemLevel(unit),
  }
end

-- Stop listening once nothing is in flight and the queue is drained (no leak).
local function idleCheck()
  if not current and #queue == 0 then frame:UnregisterEvent("INSPECT_READY") end
end

-- Start the next request if idle; skip records cancelled while queued.
local function pump()
  if current then return end
  while #queue > 0 and queue[1]._cancelled do table.remove(queue, 1) end
  if #queue == 0 then idleCheck(); return end
  current = table.remove(queue, 1)
  NotifyInspect(current.unit)
end

frame:SetScript("OnEvent", function(_, event, guid)
  if event ~= "INSPECT_READY" then return end
  if current and guid == current.guid then
    local rec = current
    current = nil
    rec.resolve(inspectData(rec.unit))
    pump()
    idleCheck()
  end
end)

--- Inspects a unit's gear/spec. Serialized: concurrent calls queue (one NotifyInspect at a
--- time). Resolves with { specialization, itemLevel }. Timeout default 5s. (API-v0 §2.)
function Loom.inspect(unit, opts)
  opts = opts or {}
  local p, resolve = Loom._deferred()
  local rec = { unit = unit, guid = UnitGUID(unit), resolve = resolve }

  Loom._setOnCancel(p, function()
    rec._cancelled = true
    if current == rec then current = nil; pump() end -- was in flight: advance the queue
    idleCheck()
  end)

  frame:RegisterEvent("INSPECT_READY")
  queue[#queue + 1] = rec
  pump()

  p = Loom._withFallback(p, opts.fallback)
  if opts.timeout == false then return p end
  return p:timeout(opts.timeout or 5)
end
