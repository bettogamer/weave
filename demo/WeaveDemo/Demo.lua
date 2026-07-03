-- WeaveDemo/Demo.lua — the CANONICAL demo (API-v0 §7) in its final form:
-- state (persistent store + game events as signals) → derivations (computeds) →
-- ONE declarative view description. Zero manual handlers, taint-proof.
--
-- 12.0 reality (verified in-game): UnitHealth/UnitHealthMax return SECRETS in
-- addon code, always. Holding/passing one is fine (sinks accept them); operating
-- one is not — derivations check isSecret() and degrade ("??" / neutral color).

local ADDON = ... -- WoW passes (addonName, addonTable) to every file

local W = LibStub("Weave-1.0")

-- The registry is extensible: statusBarTexture is not a v0 built-in prop.
W.props.register("statusBarTexture", function(f, v) f:SetStatusBarTexture(v) end)

-- STATE
local db    = W.store("WeaveDemoDB", { width = 220 }, { addon = ADDON, version = 1 })
local hp    = W.fromUnitEvent("UNIT_HEALTH", "player",
  function(u) return UnitHealth(u) end)
local hpMax = W.fromUnitEvent("UNIT_MAXHEALTH", "player",
  function(u) return UnitHealthMax(u) end)

-- DERIVATIONS
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

-- VIEW: one description, created once, out of combat
W.new("StatusBar", {
  name   = "WeaveDemoBar",
  point  = { "CENTER", 0, -180 },
  width  = db.width, -- persistent AND reactive: /weavewidth resizes live
  height = 22,
  minMax = range,
  value  = hp, -- the secret goes straight into the sink: real fill
  statusBarColor   = color,
  statusBarTexture = "Interface\\TargetingFrame\\UI-StatusBar",
  [W.children] = {
    W.new("FontString", {
      layer = "OVERLAY", point = { "CENTER" },
      template = "GameFontHighlightSmall",
      text = text,
    }),
  },
})

-- /weavewidth <n>: the persistence knob (M3 success criterion)
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
