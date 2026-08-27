-- core/Flow.lua — pure heterogeneous-flow planner: the brain of Weave.virtual's
-- Fase 2 (grouped grids, M10/ADR-0010). PURE Lua 5.1: no WoW API (ADR-0004). Grid
-- items FLOW into rows of `columns`; full-width rows (headers) BREAK the flow. Split
-- by cadence: _flowLayout runs per source change; _flowVisible per scroll. The ui
-- builds the pure per-entry descriptors and turns the plan into pooled frames — core
-- never sees a frame. See tests/core/flow_spec.lua for the contract.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave._flowLayout then return end -- lib missing or duplicate copy

local floor = math.floor

-- items[i] = { grid = boolean, height = number, indent? = number, columns? = number }.
-- Consecutive grid entries pack into a visual row of up to `columns` (sharing the row's
-- max height); a full-width entry gets its own row and flushes any open grid row.
-- Returns { rows, contentHeight }.
--
-- indent/columns are the per-row INDENT (FR Coffer 2026-08-26): a band of cells that
-- hangs off the header above it. Core stays dumb about pixels — the ui hands it the
-- indent and how many columns still fit at that indent — and applies two rules: a
-- CHANGE OF INDENT closes the open row (a sub-section starts on its own line, like a
-- header does), and every row remembers its indent so the ui can offset it.
--
-- padTop/padBottom inset the stream vertically (FR Coffer 2026-07-23): every row's y is
-- shifted down by padTop and contentHeight grows by padTop+padBottom, so the first row is
-- never flush with the viewport clip. _flowVisible needs no change — it works in the same
-- (already shifted) content space the ui scrolls over.
function Weave._flowLayout(items, opts)
  local columns = opts.columns or 1
  local spacing = opts.spacing or 0
  local padTop  = opts.padTop or 0
  local padBot  = opts.padBottom or 0
  local rows, y, n, i = {}, padTop, #items, 1

  while i <= n do
    if items[i].grid then
      local first, count, h = i, 0, 0
      local indent = items[i].indent or 0    -- the band's indent: a change of it breaks the row
      local cols   = items[i].columns or columns
      while i <= n and items[i].grid and count < cols
        and (items[i].indent or 0) == indent do
        count = count + 1
        if items[i].height > h then h = items[i].height end
        i = i + 1
      end
      rows[#rows + 1] = { y = y, height = h, first = first, count = count, indent = indent }
      y = y + h + spacing
    else
      local h = items[i].height
      rows[#rows + 1] = { y = y, height = h, first = i, count = 1,
        indent = items[i].indent or 0 }
      y = y + h + spacing
      i = i + 1
    end
  end

  local contentHeight = #rows > 0 and (y - spacing + padBot) or 0
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
