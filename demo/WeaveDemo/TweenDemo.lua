-- WeaveDemo/TweenDemo.lua — M8 field test for Weave.tween (ADR-0008): the modal/
-- collapse pattern Craft needs. A panel that, from ONE boolean signal, fades in
-- (alpha 0→1) AND expands (height COLLAPSED→PANEL_H) when opened, then fades out and —
-- the whole point of :animating() — stays shown until the exit animation ENDS, only then
-- hiding. Inside, a bar whose value slides and whose color transitions channel-by-channel
-- (array tween). The entire open/close dance is declarative: no timers, no OnUpdate,
-- no callbacks. At rest the shared driver's frame is hidden → zero per-frame cost.
--   /weavetween        → toggle open/close (fade + expand, exit hides via :animating())
--   /weavetween <0-100> → set the bar target: value slides, color transitions
-- Combat-safe: toggling only mutates existing frames (tween never creates one).
--
-- WoW RENDER CAVEAT (not a Weave issue — verified in-game via GetAlpha/GetHeight: the
-- frame always holds the correct animated values): a frame whose rendered HEIGHT animates
-- to exactly 0 and then grows again does NOT repaint on the 2nd+ cycle. So the expand
-- collapses to a small non-zero COLLAPSED_H, never 0; full invisibility is the alpha fade
-- (children inherit the parent's alpha). Hide/Show itself is fine. Craft's collapse should
-- follow the same rule: animate height to a header height, not to 0.

local W = LibStub("Weave-1.0")

local PANEL_H     = 120
local COLLAPSED_H = 20 -- never 0 (see WoW render caveat above)

-- STATE: one boolean drives the whole panel; one number drives the bar.
local open = W.signal(false)
local pct  = W.signal(0.72) -- 0..1, the bar's target

-- TWEENS: read-only reactives that slide toward their targets instead of snapping.
local alpha  = W.tween(W.computed(function() return open() and 1 or 0 end),
  { duration = 0.5 })
local height = W.tween(W.computed(function() return open() and PANEL_H or COLLAPSED_H end),
  { duration = 0.5, easing = W.easing.outQuad })

-- The bar value slides; the color transitions as an array {r,g,b}, lerped per channel.
local barValue = W.tween(pct, { duration = 0.4 })
local barColor = W.tween(W.computed(function()
  local p = pct()
  if p < 0.35 then return { 0.85, 0.2, 0.2 } end   -- red
  if p < 0.70 then return { 0.9, 0.75, 0.2 } end   -- amber
  return { 0.2, 0.8, 0.3 }                         -- green
end), { duration = 0.4 })

-- EXIT COORDINATION: shown while opening OR while the closing fade still runs. This
-- hides the panel AFTER the animation, not before — the whole reason :animating() exists.
local shown = W.computed(function() return open() or alpha:animating() end)

-- VIEW: described once. width is fixed; height is the tween (do NOT also pass `size`,
-- or its literal height would race the bind).
W.new("Frame", {
  name   = "WeaveTweenDemo",
  point  = { "TOP", "UIParent", "TOP", 0, -200 },
  width  = 260,
  height = height,
  alpha  = alpha,
  shown  = shown,
  [W.children] = {
    W.new("Texture", {
      layer = "BACKGROUND",
      points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
      texture = "Interface\\Buttons\\WHITE8x8",
      vertexColor = { 0, 0, 0, 0.7 },
    }),
    W.new("FontString", {
      layer = "OVERLAY", point = { "TOP", 0, -10 },
      template = "GameFontNormal", text = "Weave.tween — /weavetween",
    }),
    W.new("StatusBar", {
      name             = "WeaveTweenBar",
      point            = { "TOP", 0, -38 },
      size             = { 220, 20 },
      minMax           = { 0, 1 },
      value            = barValue,
      statusBarColor   = barColor,
      statusBarTexture = "Interface\\TargetingFrame\\UI-StatusBar",
    }),
    W.new("FontString", {
      layer = "OVERLAY", point = { "TOP", 0, -66 },
      template = "GameFontHighlight",
      text = W.computed(function()
        return ("target %d%%"):format(math.floor(pct() * 100 + 0.5))
      end),
    }),
  },
})

-- /weavetween: toggle, or a 0-100 number to move the bar target.
SLASH_WEAVETWEEN1 = "/weavetween"
SlashCmdList.WEAVETWEEN = function(msg)
  local n = tonumber(msg)
  if n and n >= 0 and n <= 100 then
    pct:set(n / 100)
    print(("|cff44ff44WeaveTween:|r bar target = %d%% (value slides, color transitions)"):format(n))
  elseif msg == "" or msg == "toggle" then
    open:set(not open:peek())
    print("|cff44ff44WeaveTween:|r " .. (open:peek() and "opening (fade + expand)"
      or "closing (fade out, then hides when the animation ends)"))
  else
    print("|cffffd100WeaveTween:|r /weavetween (toggle) · /weavetween <0-100> (bar target)")
  end
end
