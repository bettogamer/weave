-- WeaveDemo/Demo.lua — M1 minimal demo: the canonical demo of API-v0 §7 WITHOUT
-- store/ (M3) and ui/ (M4). Frames are created ONCE by hand; from there on Weave
-- feeds them through binds — zero manual event handlers.

local W = LibStub("Weave-1.0")

-- STATE: game events as signals (taint-aware: a secret degrades to the fallback)
local hp = W.fromUnitEvent("UNIT_HEALTH", "player",
  function(u) return UnitHealth(u) end, { fallback = 0 })
local hpMax = W.fromUnitEvent("UNIT_MAXHEALTH", "player",
  function(u) return UnitHealthMax(u) end, { fallback = 1 })

-- DERIVATIONS
local pct   = W.computed(function() return hp() / math.max(hpMax(), 1) end, { fallback = 0 })
local color = W.computed(function()
  return pct() < 0.3 and { 1, 0.2, 0.2 } or { 0.2, 0.8, 0.2 }
end)
local text  = W.computed(function() return ("%d%%"):format(pct() * 100) end)

-- VIEW: created once, out of combat (declarative creation via W.new arrives in M4)
local bar = CreateFrame("StatusBar", "WeaveDemoBar", UIParent)
bar:SetSize(220, 22)
bar:SetPoint("CENTER", 0, -180)
bar:SetMinMaxValues(0, 1)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("CENTER")

W.bind(bar, "value", pct)
W.bind(bar, "statusBarColor", color)
W.bind(label, "text", text)
