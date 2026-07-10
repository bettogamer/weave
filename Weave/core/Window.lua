-- core/Window.lua — pure window planner: the brain of Weave.virtual (M10,
-- ADR-0010, Fase 1). PURE Lua 5.1: this file must not call any WoW API
-- (ADR-0004). Given the full list size and a scroll position, it returns which
-- slice is visible and where it sits, so the ui layer can fill a FIXED pool
-- without ever materializing the whole list. See tests/core/window_spec.lua.
--
-- Weave._windowPlan(total, opts) → plan
--   total : number of entries in the FULL list.
--   opts  : { rowHeight, viewportHeight, scroll?, columns?, spacing? } (px; scroll
--           default 0, columns default 1, spacing default 0). Inputs assumed valid —
--           Weave.virtual validates opts; core is pure math (like Reconcile).
--   plan  : { first, count, offset, firstRow, capacity, contentHeight, maxScroll }.
--
-- stride = rowHeight + spacing. poolRows = ceil(viewportHeight/stride)+1 (the +1
-- covers a fractional top). Entry j sits at grid-row floor((j-1)/columns), column
-- (j-1)%columns, screen-y = (row - firstRow)*stride - offset.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave._windowPlan then return end -- lib missing or duplicate copy

local ceil, floor, max = math.ceil, math.floor, math.max

function Weave._windowPlan(total, opts)
  local rowHeight = opts.rowHeight
  local viewportH = opts.viewportHeight
  local columns   = opts.columns or 1
  local spacing   = opts.spacing or 0
  local stride    = rowHeight + spacing

  -- Full-list geometry (drives Craft's scrollbar thumb/max).
  local numRows       = ceil(total / columns)
  local contentHeight = numRows > 0 and (numRows * rowHeight + (numRows - 1) * spacing) or 0
  local maxScroll     = max(0, contentHeight - viewportH)

  -- Clamp scroll into range: past the end just pins to the bottom.
  local scroll = opts.scroll or 0
  if scroll < 0 then scroll = 0 elseif scroll > maxScroll then scroll = maxScroll end

  -- Which grid-row is at the top, and by how much is it scrolled above the viewport.
  local firstRow = floor(scroll / stride)
  local offset   = scroll - firstRow * stride

  -- The pool is FIXED: sized to the viewport, never to the list.
  local poolRows = ceil(viewportH / stride) + 1
  local capacity = poolRows * columns

  local first     = firstRow * columns + 1
  local remaining = total - first + 1
  local count     = remaining < capacity and remaining or capacity
  if count < 0 then count = 0 end

  return {
    first         = first,
    count         = count,
    offset        = offset,
    firstRow      = firstRow,
    capacity      = capacity,
    contentHeight = contentHeight,
    maxScroll     = maxScroll,
  }
end
