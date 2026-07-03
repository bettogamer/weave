-- WeaveDemo/TaintTest.lua — M2 field test: builds a whole Weave pipeline INSIDE a
-- loadstring chunk, i.e. under *** ForceTaint_Strong ***, where every secretable
-- API returns secrets ALWAYS. Success criteria in-game (scriptErrors 1 on):
--   * the blue test bar tracks real health, its text says "?? (taint)"
--   * exactly TWO yellow Weave warnings (one effect, one event map — deliberate)
--   * ZERO red error popups
-- Usage: /weavetaint (once per session; /reload to reset).

local ran = false
local bar, label

local function ensureFrames()
  if bar then return end
  bar = CreateFrame("StatusBar", "WeaveTaintTestBar", UIParent)
  bar:SetSize(220, 16)
  bar:SetPoint("CENTER", 0, -210)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.2, 0.6, 1) -- blue: tell it apart from the demo bar
  label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("CENTER")
end

-- Everything below runs force-tainted. Keep it self-contained: only the two test
-- frames come in from outside (as chunk arguments).
local SRC = [==[
  local bar, label = ...
  local W = LibStub("Weave-1.0")

  -- 1) The sanctioned path: secrets flow untouched into sinks; derivations check
  --    isSecret() and degrade. This must just work.
  local hp = W.fromUnitEvent("UNIT_HEALTH", "player",
    function(u) return UnitHealth(u) end)
  local hpMax = W.fromUnitEvent("UNIT_MAXHEALTH", "player",
    function(u) return UnitHealthMax(u) end)
  local range = W.computed(function() return { 0, hpMax() } end)
  local text = W.computed(function()
    local v, m = hp(), hpMax()
    if hp:isSecret() or hpMax:isSecret() then return "?? (taint)" end
    return ("%d%%"):format(v / math.max(m, 1) * 100)
  end, { fallback = "??" })
  W.bind(bar, "minMax", range)
  W.bind(bar, "value", hp)
  W.bind(label, "text", text)

  -- 2) An effect that OPERATES the secret on purpose: the core chokepoint must
  --    degrade it with ONE yellow warning, never a popup.
  W.effect(function() return hp() + 1 end)

  -- 3) An event map that OPERATES the secret on purpose: the map guard must
  --    degrade it with ONE yellow warning and keep the other subscribers alive.
  W.fromEvent("UNIT_HEALTH", function(u) return UnitHealth(u) / 100 end)
]==]

SLASH_WEAVETAINT1 = "/weavetaint"
SlashCmdList.WEAVETAINT = function()
  if ran then
    print("|cffffd100WeaveTaint:|r already ran — /reload to run it again.")
    return
  end
  if InCombatLockdown() then
    print("|cffffd100WeaveTaint:|r out of combat only (it creates frames).")
    return
  end
  ensureFrames()
  local chunk, compileErr = loadstring(SRC, "WeaveTaintTest")
  if not chunk then
    print("|cffff4444WeaveTaint:|r compile error: " .. tostring(compileErr))
    return
  end
  local ok, err = pcall(chunk, bar, label)
  ran = ok
  if ok then
    print("|cff44ff44WeaveTaint:|r pipeline built under ForceTaint_Strong."
      .. " Expect: blue bar tracking your health, text '?? (taint)',"
      .. " exactly TWO yellow Weave warnings, ZERO red popups.")
  else
    print("|cffff4444WeaveTaint:|r FAILED (this is the bug to report): " .. tostring(err))
  end
end
