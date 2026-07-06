-- MiOro/MiOro.lua — the tutorial addon (docs/TUTORIAL.md): a reactive on-screen
-- gold counter. Three floors: state -> derivation -> view. Zero manual event handlers.

local W = LibStub("Weave-1.0")

-- STATE: a signal fed by the game event (buy/sell/loot -> PLAYER_MONEY fires)
local money = W.fromEvent("PLAYER_MONEY",
  function() return GetMoney() end, -- map: how much money I hold now (in copper)
  { initial = GetMoney() })         -- start value, before the first event

-- DERIVATION: formatted text; recomputes only when `money` changes
local label = W.computed(function()
  return GetCoinTextureString(money()) -- "12g 34s 56c" with coin icons
end)

-- VIEW: described once; `text` stays wired to the derivation
W.new("FontString", {
  parent   = UIParent,
  layer    = "OVERLAY",
  template = "GameFontNormalLarge",
  point    = { "CENTER", 0, 200 },
  text     = label, -- a signal/computed in a prop = automatic bind
})
