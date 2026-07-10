-- WeaveDemo/VirtualDemo.lua — M10 field test for Weave.virtual: a VIRTUALIZED grid
-- driven by ONE signal, over THOUSANDS of entries. /weavevirtual exercises Fase 1:
--   * scroll wheel / drag the bar → fractional windowing (a fixed pool of ~N cells is
--                     re-glazed; scroll moves by pixels, not whole rows)
--   * grow 5000     → the pool NEVER grows: still the same handful of frames
--   * secret        → taint (values become secrets: cells degrade to "??", no popup)
--   * in combat     → the fixed pool only re-glazes; scrolling stays smooth, no errors
--
-- This demo owns the `scroll` signal and drives it from BOTH the wheel and a draggable
-- scrollbar, then reads v:contentHeight() to size the bar — exactly what Craft's
-- scrollbar will do (ADR-0006 boundary). The chrome (header, bar) lives OUTSIDE the
-- clipped viewport: virtual clips its container, so siblings, not children.

local W = LibStub("Weave-1.0")

-- 12.0+ client API; the shim keeps pre-12.0 clients working (nothing is secret there)
local issecretvalue = issecretvalue or function() return false end

local COLS, ROWH   = 6, 40
local VIEWW, VIEWH = COLS * 40, 400
local SBW          = 10 -- scrollbar width

-- STATE: one signal holding the whole array. `secret` fills values with UnitHealth,
-- which returns a secret in 12.0.7 addon code — the cells must degrade, not crash.
local function build(n, secret)
  local t = {}
  for i = 1, n do
    t[i] = { n = i, v = secret and UnitHealth("player") or i }
  end
  return t
end

local items  = W.signal(build(200))
local scroll = W.signal(0) -- position in px; the wheel AND the bar move it

-- RENDER: runs ONCE per pooled cell. Data flows in through item() as you scroll.
local function renderCell(item)
  return W.new("Button", {
    size = { 38, 38 },
    [W.children] = {
      W.new("Texture", {
        layer = "BACKGROUND", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
        texture = "Interface\\Buttons\\WHITE8x8",
        vertexColor = W.computed(function()
          return item() and { 0.16, 0.17, 0.22, 0.95 } or { 0, 0, 0, 0 }
        end),
      }),
      W.new("FontString", {
        layer = "OVERLAY", point = { "CENTER" }, template = "GameFontHighlightSmall",
        text = W.computed(function()
          local it = item()
          if not it then return "" end -- idle pooled cells hold nil
          local v = it.v
          if issecretvalue(v) then v = "??" end
          return tostring(v)
        end),
      }),
    },
  })
end

-- PANEL: the outer frame (NOT clipped) — holds all the chrome.
local panel = W.new("Frame", {
  name = "WeaveVirtualDemo", point = { "CENTER", 330, 0 }, size = { VIEWW + SBW + 30, VIEWH + 52 },
  [W.children] = {
    W.new("Texture", {
      layer = "BACKGROUND", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
      texture = "Interface\\Buttons\\WHITE8x8", vertexColor = { 0, 0, 0, 0.65 },
    }),
    W.new("FontString", {
      layer = "OVERLAY", point = { "TOPLEFT", 12, -10 },
      template = "GameFontNormal", text = "Weave.virtual — /weavevirtual",
    }),
  },
})

-- VIEWPORT: virtual clips this; it holds ONLY the grid (its own recessed backdrop
-- fills it exactly, so the clip does not cut it).
local viewport = W.new("Frame", {
  name = "WeaveVirtualViewport", parent = panel,
  point = { "TOPLEFT", "WeaveVirtualDemo", "TOPLEFT", 12, -32 }, size = { VIEWW, VIEWH },
  [W.children] = {
    W.new("Texture", {
      layer = "BACKGROUND", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
      texture = "Interface\\Buttons\\WHITE8x8", vertexColor = { 1, 1, 1, 0.04 },
    }),
  },
})

-- opts.parent → returns the instance so we can read :contentHeight() (Craft's scrollbar
-- binds to it). virtual only READS `scroll`; we own it, like Craft owns its scrollbar.
local v = W.virtual(items, {
  parent = viewport, viewport = { VIEWW, VIEWH }, rowHeight = ROWH, columns = COLS,
  scroll = scroll, render = renderCell,
})

local function clampScroll(s)
  local maxS = math.max(0, v:contentHeight() - VIEWH)
  if s < 0 then return 0 elseif s > maxS then return maxS end
  return s
end

-- If the list shrinks below the current scroll, keep our (consumer-owned) scroll signal
-- in range — virtual clamps its painting but only READS scroll (ADR-0006).
W.effect(function()
  local maxS = math.max(0, v:contentHeight() - VIEWH)
  if scroll:peek() > maxS then scroll:set(maxS) end
end)

-- The wheel scrolls the viewport (delta -1 = down = later items).
viewport:EnableMouseWheel(true)
viewport:SetScript("OnMouseWheel", function(_, delta)
  scroll:set(clampScroll(scroll:peek() - delta * ROWH))
end)

-- SCROLLBAR: sibling of the viewport (NOT clipped). The track is the rail; the thumb's
-- height and position are a reactive read of scroll()/contentHeight().
W.new("Frame", {
  name = "WeaveVirtualTrack", parent = panel,
  point = { "TOPLEFT", "WeaveVirtualViewport", "TOPRIGHT", 6, 0 }, size = { SBW, VIEWH },
  [W.children] = {
    W.new("Texture", {
      layer = "BACKGROUND", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
      texture = "Interface\\Buttons\\WHITE8x8", vertexColor = { 1, 1, 1, 0.08 },
    }),
  },
})
local track = _G.WeaveVirtualTrack
local thumb = W.new("Button", {
  parent = track, size = { SBW, 40 }, point = { "TOP", 0, 0 },
  [W.children] = {
    W.new("Texture", {
      layer = "ARTWORK", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
      texture = "Interface\\Buttons\\WHITE8x8", vertexColor = { 0.5, 0.6, 0.95, 0.9 },
    }),
  },
})

local function thumbHeight()
  local ch = v:contentHeight()
  if ch <= VIEWH then return VIEWH end
  local h = VIEWH * VIEWH / ch
  return h < 24 and 24 or h -- keep it grabbable
end

-- Reactive: the thumb tracks the signal. Reading scroll()/contentHeight() inside the
-- effect makes it re-run whenever either changes (wheel, drag, grow, reset).
W.effect(function()
  local maxS = math.max(0, v:contentHeight() - VIEWH)
  local h = thumbHeight()
  local y = maxS > 0 and -(scroll() / maxS) * (VIEWH - h) or 0
  thumb:SetHeight(h)
  thumb:ClearAllPoints()
  thumb:SetPoint("TOP", track, "TOP", 0, y)
end)

-- Draggable: maps cursor travel to scroll (the two-way bar → signal → virtual).
local dragging, startCursorY, startScroll = false, 0, 0
thumb:SetScript("OnMouseDown", function()
  dragging = true
  local _, cy = GetCursorPosition()
  startCursorY, startScroll = cy, scroll:peek()
end)
thumb:SetScript("OnMouseUp", function() dragging = false end)
thumb:SetScript("OnUpdate", function()
  if not dragging then return end
  local maxS = math.max(0, v:contentHeight() - VIEWH)
  if maxS <= 0 then return end
  local travel = VIEWH - thumbHeight()
  local _, cy = GetCursorPosition()
  local dy = (startCursorY - cy) / thumb:GetEffectiveScale() -- cursor down → dy > 0 → scroll down
  scroll:set(clampScroll(startScroll + dy * (maxS / travel)))
end)

-- STATUS: reads scroll() and v:contentHeight() reactively — proof the height is live.
W.new("FontString", {
  parent = panel, layer = "OVERLAY", point = { "BOTTOMLEFT", 12, 10 },
  template = "GameFontHighlightSmall",
  text = W.computed(function()
    return ("scroll %d / %d px · %d items"):format(
      scroll(), math.max(0, v:contentHeight() - VIEWH), #items())
  end),
})

-- /weavevirtual: the knobs
SLASH_WEAVEVIRTUAL1 = "/weavevirtual"
SlashCmdList.WEAVEVIRTUAL = function(msg)
  local cmd, arg = msg:match("^(%S*)%s*(%S*)$")
  if cmd == "grow" then
    scroll:set(0)
    items:set(build(math.max(1, math.min(tonumber(arg) or 5000, 50000))))
  elseif cmd == "secret" then
    -- 12.0.7: UnitHealth returns a secret in addon code — every cell must show "??".
    items:set(build(#items:peek(), true))
  elseif cmd == "reset" then
    scroll:set(0)
    items:set(build(200))
  else
    print("|cffffd100WeaveVirtualDemo:|r /weavevirtual grow [n] · secret · reset"
      .. " — items: " .. #items:peek() .. ", cells shown: " .. #_G.WeaveVirtualViewport._virtualRows)
    print("  spin the wheel or drag the bar to scroll (fractional). `grow 5000`: the pool"
      .. " stays the same size. In combat the pool only re-glazes — try scrolling.")
  end
end
