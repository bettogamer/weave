-- core/Flow.lua — pure heterogeneous-flow planner: the brain of Weave.virtual's
-- Fase 2 (grouped grids, M10/ADR-0010). PURE Lua 5.1: no WoW API (ADR-0004). Grid
-- items FLOW into rows of `columns`; full-width rows (headers) BREAK the flow. Split
-- by cadence: _flowLayout runs per source change; _flowVisible per scroll. The ui
-- builds the pure per-entry descriptors and turns the plan into pooled frames — core
-- never sees a frame. See tests/core/flow_spec.lua for the contract.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave._flowLayout then return end -- lib missing or duplicate copy

local floor = math.floor

-- items[i] = { grid = boolean, height = number }. Consecutive grid entries pack into a
-- visual row of up to `columns` (sharing the row's max height); a full-width entry gets
-- its own row and flushes any open grid row. Returns { rows, contentHeight }.
function Weave._flowLayout(items, opts)
  local columns = opts.columns or 1
  local spacing = opts.spacing or 0
  local rows, y, n, i = {}, 0, #items, 1

  while i <= n do
    if items[i].grid then
      local first, count, h = i, 0, 0
      while i <= n and items[i].grid and count < columns do
        count = count + 1
        if items[i].height > h then h = items[i].height end
        i = i + 1
      end
      rows[#rows + 1] = { y = y, height = h, first = first, count = count }
      y = y + h + spacing
    else
      local h = items[i].height
      rows[#rows + 1] = { y = y, height = h, first = i, count = 1 }
      y = y + h + spacing
      i = i + 1
    end
  end

  local contentHeight = #rows > 0 and (y - spacing) or 0
  return { rows = rows, contentHeight = contentHeight }
end

-- Visual-row index range [first..last] whose [y, y+height) intersects the viewport
-- [scroll, scroll+viewportHeight). Binary search (rows are sorted by y ascending, by
-- construction) — never O(total). Empty range = first > last. Scroll is assumed clamped.
function Weave._flowVisible(layout, scroll, viewportHeight)
  local rows = layout.rows
  local n = #rows
  if n == 0 then return { first = 1, last = 0 } end
  local bottom = scroll + viewportHeight

  -- first: smallest r whose bottom edge (y+height) is past the viewport top.
  local lo, hi, first = 1, n, n + 1
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if rows[mid].y + rows[mid].height > scroll then
      first = mid; hi = mid - 1
    else
      lo = mid + 1
    end
  end

  -- last: largest r whose top edge (y) is above the viewport bottom.
  lo, hi = 1, n
  local last = 0
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if rows[mid].y < bottom then
      last = mid; lo = mid + 1
    else
      hi = mid - 1
    end
  end

  return { first = first, last = last }
end
