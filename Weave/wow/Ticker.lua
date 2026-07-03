-- wow/Ticker.lua — onUpdate: throttled time signals over ONE shared ticker frame
-- (API-v0 §2). The signal's value is GetTime() as of its last tick; it is seeded at
-- creation. A signal only publishes while it has live observers.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.onUpdate then return end -- lib missing or duplicate copy

local CreateFrame, GetTime = CreateFrame, GetTime

local MIN_INTERVAL = 0.05 -- effective floor (roughly two rendered frames)

local tickerFrame        -- created on the first onUpdate; must stay SHOWN (hidden
                         -- frames receive no OnUpdate)
local entries   = {}     -- interval -> entry (same interval shares one signal)
local entryList = {}     -- array mirror for the OnUpdate loop (no pairs per frame)

local function onTick(_, elapsed)
  for i = 1, #entryList do
    local e = entryList[i]
    e.acc = e.acc + elapsed
    if e.acc >= e.interval then
      e.acc = 0
      -- no subscribers, no tick (spec): skip the set() entirely
      if next(e.signal._observers) ~= nil then
        e.signal:set(GetTime())
      end
    end
  end
end

function Weave.onUpdate(interval)
  if type(interval) ~= "number" then
    error("Weave.onUpdate: expected an interval in seconds (number), got " .. type(interval), 2)
  end
  if interval <= 0 then
    error("Weave.onUpdate: interval must be positive (seconds)", 2)
  end
  if interval < MIN_INTERVAL then interval = MIN_INTERVAL end
  local e = entries[interval]
  if not e then
    e = { signal = Weave.signal(GetTime()), interval = interval, acc = 0 }
    entries[interval] = e
    entryList[#entryList + 1] = e
    if not tickerFrame then
      tickerFrame = CreateFrame("Frame")
      tickerFrame:SetScript("OnUpdate", onTick)
    end
  end
  return e.signal
end
