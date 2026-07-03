-- WeaveDemo/Demo.lua — M1 minimal demo: reactive player health bar.
-- 12.0 reality check: UnitHealth/UnitHealthMax return SECRET values in addon code
-- ALWAYS (even out of combat — confirmed in-game on 12.0.7). So this demo shows
-- the two sanctioned patterns side by side:
--   * bar fill: signals WITHOUT fallback — the secret flows untouched into sinks
--     that accept it (SetValue / SetMinMaxValues), so the bar shows REAL health.
--   * text/color: arithmetic on a secret is impossible — read the raw signal (for
--     tracking), check isSecret(), and degrade to "??" / a neutral color.

local ADDON = ... -- WoW passes (addonName, addonTable) to every file

local W = LibStub("Weave-1.0")

-- PERSISTENT STATE (M3): created at file scope, BEFORE the SV loads — it starts
-- on defaults and re-syncs (bar width included) when ADDON_LOADED hydrates it.
-- The .toc declares: ## SavedVariables: WeaveDemoDB
local db = W.store("WeaveDemoDB", { width = 220 }, { addon = ADDON, version = 1 })

-- STATE: no fallback declared — the secret circulates as-is (API-v0 §3, row 3)
local hp = W.fromUnitEvent("UNIT_HEALTH", "player",
  function(u) return UnitHealth(u) end)
local hpMax = W.fromUnitEvent("UNIT_MAXHEALTH", "player",
  function(u) return UnitHealthMax(u) end)

-- DERIVATIONS: reading/holding a secret is fine; OPERATING on it is not
local range = W.computed(function() return { 0, hpMax() } end)

local text = W.computed(function()
  local v, m = hp(), hpMax() -- track both (locals hold secrets safely)
  if hp:isSecret() or hpMax:isSecret() then return "??" end
  return ("%d%%"):format(v / math.max(m, 1) * 100)
end, { fallback = "??" })

local color = W.computed(function()
  local v, m = hp(), hpMax()
  if hp:isSecret() or hpMax:isSecret() then return { 0.2, 0.8, 0.2 } end
  return (v / math.max(m, 1)) < 0.3 and { 1, 0.2, 0.2 } or { 0.2, 0.8, 0.2 }
end, { fallback = { 0.2, 0.8, 0.2 } })

-- VIEW: created once, out of combat (declarative creation via W.new arrives in M4)
local bar = CreateFrame("StatusBar", "WeaveDemoBar", UIParent)
bar:SetHeight(22)
bar:SetPoint("CENTER", 0, -180)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("CENTER")

W.bind(bar, "width", db.width) -- persistent: survives /reload and logout
W.bind(bar, "minMax", range)
W.bind(bar, "value", hp) -- the secret goes straight into the sink: real fill
W.bind(bar, "statusBarColor", color)
W.bind(label, "text", text)

-- /weavewidth <n>: the in-game knob to verify persistence (M3 success criterion)
SLASH_WEAVEWIDTH1 = "/weavewidth"
SlashCmdList.WEAVEWIDTH = function(msg)
  local n = tonumber(msg)
  if n and n >= 50 and n <= 600 then
    db.width:set(n)
    print("|cff44ff44WeaveDemo:|r width = " .. n .. " — persists across /reload and logout")
  else
    print("|cffffd100WeaveDemo:|r usage: /weavewidth <50-600> (current: "
      .. tostring(db.width:peek()) .. ")")
  end
end
