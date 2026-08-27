-- WeaveDemo/VirtualGroupsDemo.lua — M10 Fase 2 field test for Weave.virtual: a
-- HETEROGENEOUS virtualized grid — full-width category headers interleaved with a grid
-- of item cells, in ONE virtualized stream. /weavegroups shows:
--   * heterogeneous rows → a pool PER TYPE (headers never recycle as items)
--   * collapse           → the CONSUMER owns it (ADR-0010): the stream is a computed
--                          over a `collapsed` signal; clicking a header toggles it and
--                          the whole grid re-windows. virtual never knows what a group is.
--   * wheel              → fractional scroll over the mixed-height stream
--   * indent             → opts.indentOf: sub-sections HANG off their header. It is per
--                          ROW, not per type, so ONE header recipe (and one pool) serves
--                          both levels — "Armor" holds "Plate"/"Mail" one step in.
--   * resize grip        → inst:Resize{...} on a LIVE list: drag the corner and the grid
--                          re-plans every frame, no rebuild and no /reload.
--
-- Collapse the categories and watch the grid reflow — virtual just paints whatever flat
-- stream the computed produces.

local W = LibStub("Weave-1.0")

local COLS         = 4
local VIEWW, VIEWH = COLS * 40, 320
local SBW          = 10 -- scrollbar width

-- STATE: categories, and a signal of which ones are collapsed.
local CATS = {
  { id = "consum",  name = "Consumables", n = 10 },
  { id = "weapons", name = "Weapons",     n = 5  },
  -- Armor is split by slot: its items live one level deeper (see `depth` in the stream).
  { id = "armor",   name = "Armor",       n = 14, subs = {
    { id = "armor/plate", name = "Plate", n = 6 },
    { id = "armor/mail",  name = "Mail",  n = 8 },
  } },
  { id = "misc",    name = "Misc",        n = 7  },
}
local collapsed = W.signal({}) -- { [catId] = true }
local scroll    = W.signal(0)  -- px; wheel AND the scrollbar move it
local geom      = W.signal(0)  -- bumped by the resize grip so OUR effects re-run too

-- STREAM: header + (unless collapsed) its items. A computed over `collapsed`, so toggling
-- a category produces a NEW flat stream and virtual re-windows. This is the whole trick:
-- collapse is just "a different stream", the consumer's business — not virtual's.
local stream = W.computed(function()
  local closed = collapsed()
  local out = {}
  for _, c in ipairs(CATS) do
    out[#out + 1] = { kind = "header", cat = c }
    if not closed[c.id] then
      if c.subs then
        -- Sub-sections are the SAME type one level deeper: the indent travels with the
        -- ROW (opts.indentOf), not with the type, so no "headerIndented" recipe exists.
        for _, sc in ipairs(c.subs) do
          out[#out + 1] = { kind = "header", cat = sc, depth = 1 }
          if not closed[sc.id] then
            for k = 1, sc.n do
              out[#out + 1] = { kind = "item", cat = sc.id, k = k, depth = 1 }
            end
          end
        end
      else
        for k = 1, c.n do out[#out + 1] = { kind = "item", cat = c.id, k = k } end
      end
    end
  end
  return out
end)

local function toggle(id)
  local t = {}
  for k, v in pairs(collapsed:peek()) do t[k] = v end
  t[id] = (not t[id]) or nil
  collapsed:set(t)
end

-- RENDER: one recipe per type. Runs ONCE per pooled frame; data flows in via item().
local function renderHeader(item)
  return W.new("Button", {
    [W.children] = {
      W.new("Texture", {
        layer = "BACKGROUND", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
        texture = "Interface\\Buttons\\WHITE8x8", vertexColor = { 0.2, 0.3, 0.42, 0.95 },
      }),
      W.new("FontString", {
        layer = "OVERLAY", point = { "LEFT", 6, 0 }, template = "GameFontNormalSmall",
        text = W.computed(function()
          local e = item(); if not e then return "" end
          local arrow = collapsed()[e.cat.id] and "|cffffd100[+]|r" or "|cffffd100[-]|r"
          return arrow .. " " .. e.cat.name .. " (" .. e.cat.n .. ")"
        end),
      }),
    },
    [W.on] = {
      OnMouseDown = function()
        local e = item() -- the header's current category (changes as the frame re-glazes)
        if e then toggle(e.cat.id) end
      end,
    },
  })
end

local function renderItem(item)
  return W.new("Button", {
    size = { 36, 36 },
    [W.children] = {
      W.new("Texture", {
        layer = "BACKGROUND", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
        texture = "Interface\\Buttons\\WHITE8x8", vertexColor = { 0.16, 0.17, 0.22, 0.95 },
      }),
      W.new("FontString", {
        layer = "OVERLAY", point = { "CENTER" }, template = "GameFontHighlightSmall",
        text = W.computed(function()
          local e = item(); return e and tostring(e.k) or ""
        end),
      }),
    },
  })
end

-- PANEL + viewport (virtual clips the viewport; title/scrollbar are siblings, not children).
local panel = W.new("Frame", {
  name = "WeaveGroupsDemo", point = { "CENTER", -330, 0 }, size = { VIEWW + SBW + 30, VIEWH + 40 },
  [W.children] = {
    W.new("Texture", {
      layer = "BACKGROUND", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
      texture = "Interface\\Buttons\\WHITE8x8", vertexColor = { 0, 0, 0, 0.65 },
    }),
    W.new("FontString", {
      layer = "OVERLAY", point = { "TOPLEFT", 12, -10 },
      template = "GameFontNormal", text = "Weave.virtual grouped — /weavegroups",
    }),
  },
})
local viewport = W.new("Frame", {
  name = "WeaveGroupsViewport", parent = panel,
  point = { "TOPLEFT", "WeaveGroupsDemo", "TOPLEFT", 12, -30 }, size = { VIEWW, VIEWH },
})

-- opts.parent → returns the instance so we can read :contentHeight() for the scrollbar.
local v = W.virtual(stream, {
  parent = viewport, viewport = { VIEWW, VIEWH }, columns = COLS, spacing = 2, scroll = scroll,
  typeOf = function(e) return e.kind end,
  -- One step of indent per level: the cells KEEP their size and the band simply fits
  -- fewer columns, so a sub-section reads as hanging off the header above it.
  indentOf = function(e) return (e.depth or 0) * 16 end,
  types = {
    item   = { render = renderItem,   height = 38, grid = true }, -- flows in the 4-col grid
    header = { render = renderHeader,  height = 20 },             -- full-width, breaks the flow
  },
})

local function clampScroll(s)
  local maxS = math.max(0, v:contentHeight() - VIEWH)
  if s < 0 then return 0 elseif s > maxS then return maxS end
  return s
end

-- When the content shrinks (e.g. collapsing the last group while scrolled to the bottom),
-- our scroll signal can point past the new end. virtual clamps its PAINTING, but the
-- scroll signal is OURS — virtual only reads it (ADR-0006). So we keep it in range here.
W.effect(function()
  geom()                                              -- tracked: a resize changes maxScroll
  local maxS = math.max(0, v:contentHeight() - VIEWH) -- tracked: re-runs when content changes
  if scroll:peek() > maxS then scroll:set(maxS) end   -- peek: no loop
end)

-- Wheel scrolls the viewport (delta -1 = down).
viewport:EnableMouseWheel(true)
viewport:SetScript("OnMouseWheel", function(_, delta)
  scroll:set(clampScroll(scroll:peek() - delta * 38))
end)

-- SCROLLBAR: sibling of the viewport. Thumb height/position are a reactive read of
-- scroll()/contentHeight() — and it's draggable (bar → signal → virtual, two-way).
W.new("Frame", {
  name = "WeaveGroupsTrack", parent = panel,
  point = { "TOPLEFT", "WeaveGroupsViewport", "TOPRIGHT", 6, 0 }, size = { SBW, VIEWH },
  [W.children] = {
    W.new("Texture", {
      layer = "BACKGROUND", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
      texture = "Interface\\Buttons\\WHITE8x8", vertexColor = { 1, 1, 1, 0.08 },
    }),
  },
})
local track = _G.WeaveGroupsTrack
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
  return h < 24 and 24 or h
end

W.effect(function()
  geom() -- a taller viewport moves the thumb even when the content did not change
  local maxS = math.max(0, v:contentHeight() - VIEWH)
  local h = thumbHeight()
  local y = maxS > 0 and -(scroll() / maxS) * (VIEWH - h) or 0
  thumb:SetHeight(h)
  thumb:ClearAllPoints()
  thumb:SetPoint("TOP", track, "TOP", 0, y)
end)

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
  local dy = (startCursorY - cy) / thumb:GetEffectiveScale()
  scroll:set(clampScroll(startScroll + dy * (maxS / travel)))
end)

------------------------------------------------------------------------------
-- RESIZE GRIP — the FR's real gesture (Coffer 2026-08-27): drag the corner and the
-- LIVE list re-plans on every frame. Before Resize this meant tearing the grid down
-- and rebuilding it (or asking for a /reload); now it is one call. Columns follow the
-- width, so the grid re-packs as it widens.
------------------------------------------------------------------------------
local function applySize(vw, vh)
  if vw < 120 then vw = 120 elseif vw > 620 then vw = 620 end
  if vh < 100 then vh = 100 elseif vh > 560 then vh = 560 end
  local cols = math.floor(vw / 40)
  if cols < 1 then cols = 1 end
  VIEWW, VIEWH = vw, vh
  panel:SetSize(vw + SBW + 30, vh + 40)
  viewport:SetSize(vw, vh)
  track:SetHeight(vh)
  v:Resize({ width = vw, height = vh, columns = cols }) -- one call: re-plan + repaint
  geom:set(geom:peek() + 1)                             -- and our scrollbar follows
end

local grip = W.new("Button", {
  parent = panel, size = { 14, 14 }, point = { "BOTTOMRIGHT", -3, 3 },
  [W.children] = {
    W.new("Texture", {
      layer = "ARTWORK", points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
      texture = "Interface\\Buttons\\WHITE8x8", vertexColor = { 0.5, 0.6, 0.95, 0.8 },
    }),
  },
})

local sizing, gripX, gripY, gripW, gripH = false, 0, 0, 0, 0
grip:SetScript("OnMouseDown", function()
  sizing = true
  gripX, gripY = GetCursorPosition()
  gripW, gripH = VIEWW, VIEWH
end)
grip:SetScript("OnMouseUp", function() sizing = false end)
grip:SetScript("OnUpdate", function()
  if not sizing then return end
  local scale = grip:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  applySize(gripW + (cx - gripX) / scale, gripH - (cy - gripY) / scale)
end)

-- /weavegroups: toggle-all + help
SLASH_WEAVEGROUPS1 = "/weavegroups"
SlashCmdList.WEAVEGROUPS = function(msg)
  if msg == "collapse" then
    local t = {}; for _, c in ipairs(CATS) do t[c.id] = true end; collapsed:set(t)
  elseif msg == "expand" then
    collapsed:set({})
  elseif msg == "reset" then
    applySize(160, 320)
  else
    print("|cffffd100WeaveGroupsDemo:|r /weavegroups collapse · expand · reset — click a"
      .. " header to toggle its group (Armor holds two INDENTED sub-sections); wheel to"
      .. " scroll; DRAG THE BOTTOM-RIGHT CORNER to resize the live list. The stream is a"
      .. " computed over one signal; virtual just windows whatever flat stream it gets.")
  end
end
