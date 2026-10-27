-- core/Flow.lua — pure heterogeneous-flow planner: the brain of Weave.virtual's
-- Fase 2 (grouped grids, M10/ADR-0010). PURE Lua 5.1: no WoW API (ADR-0004). Grid
-- items FLOW into rows of `columns`; full-width rows (headers) BREAK the flow. Split
-- by cadence: _flowLayout runs per source change; _flowVisible per scroll. The ui
-- builds the pure per-entry descriptors and turns the plan into pooled frames — core
-- never sees a frame. See tests/core/flow_spec.lua for the contract.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave._flowLayout then return end -- lib missing or duplicate copy

local floor, min = math.floor, math.min
local EPS = 1e-6 -- colWidth is often fractional ((w - 2*pad)/n): "fits at the edge" must hold

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
--
-- items[i].segment = key (FR Coffer 2026-10-26, ADR-0012): consecutive grid entries with
-- the same key are a SEGMENT — a block = a label above its cells. Segments pack IN LINE,
-- `segmentGap` px apart, measured in pixels against the band (opts.width - indent, cells
-- at opts.colWidth): one that doesn't fit what is left of the row opens a new row; one
-- wider than a whole row wraps from x=0, labelled only on its first stretch. A row where
-- some segment STARTS is labelHeight taller and its cells sit cellY = labelHeight down.
-- Such rows carry segs[s] = { first, count, x, key, label, total } (x relative to the
-- band). Going from keyless to keyed entries (or back) closes the row.
local function packSegments(items, i, opts, rows, y)
  local n       = #items
  local colW    = opts.colWidth
  local gap     = opts.segmentGap or 0
  local labelH  = opts.labelHeight or 0
  local spacing = opts.spacing or 0
  local indent  = items[i].indent or 0
  local bandW   = opts.width - indent

  local row
  local function open(first) row = { first = first, count = 0, indent = indent, segs = {}, x = 0, h = 0 } end
  local function close()
    local cellY = row.labeled and labelH or 0
    rows[#rows + 1] = { y = y, height = row.h + cellY, first = row.first, count = row.count,
      indent = indent, segs = row.segs, cellY = cellY }
    y = y + row.h + cellY + spacing
  end
  local function sameBand(j)
    return items[j].grid and items[j].segment ~= nil and (items[j].indent or 0) == indent
  end

  open(i)
  while i <= n and sameBand(i) do
    local key, s, e = items[i].segment, i, i
    while e < n and sameBand(e + 1) and items[e + 1].segment == key do e = e + 1 end
    local total = e - s + 1

    local x = row.count > 0 and (row.x + gap) or 0
    if row.count > 0 and x + total * colW > bandW + EPS then
      close(); open(s); x = 0
    end
    local placed, label = 0, true
    while placed < total do
      local fit = floor((bandW - x) / colW + EPS)
      if fit < 1 then fit = 1 end -- a band narrower than one cell still shows one
      local k = min(total - placed, fit)
      row.segs[#row.segs + 1] = { first = s + placed, count = k, x = x, key = key,
        label = label, total = total }
      if label then row.labeled = true end
      for j = s + placed, s + placed + k - 1 do
        if items[j].height > row.h then row.h = items[j].height end
      end
      row.count = row.count + k
      row.x     = x + k * colW
      placed, label = placed + k, false
      if placed < total then close(); open(s + placed); x = 0 end
    end
    i = e + 1
  end
  close()
  return i, y
end

function Weave._flowLayout(items, opts)
  local columns = opts.columns or 1
  local spacing = opts.spacing or 0
  local padTop  = opts.padTop or 0
  local padBot  = opts.padBottom or 0
  local rows, y, n, i = {}, padTop, #items, 1

  while i <= n do
    if items[i].grid and items[i].segment ~= nil then
      if type(opts.colWidth) ~= "number" or type(opts.width) ~= "number" then
        error("Weave._flowLayout: segments need opts.colWidth and opts.width", 2)
      end
      i, y = packSegments(items, i, opts, rows, y)
    elseif items[i].grid then
      local first, count, h = i, 0, 0
      local indent = items[i].indent or 0    -- the band's indent: a change of it breaks the row
      local cols   = items[i].columns or columns
      while i <= n and items[i].grid and items[i].segment == nil and count < cols
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

-- The per-entry descriptors _flowLayout eats, built from the consumer's opts. Shared by
-- Weave.virtual (ui) and Weave.flowPlan so an estimate can never drift from what is
-- painted. cfg = { who, typeOf, types, indentOf?, segmentOf?, colWidth, width } (width
-- = usable, padding already off). Returns desc, entryType. Pure: it only reads
-- spec.grid / spec.height, never a frame.
function Weave._flowDescribe(list, cfg)
  if type(list) ~= "table" then
    error(cfg.who .. ": source must provide an array, got " .. type(list), 0)
  end
  local desc, entryType = {}, {}
  local typeOf, types, indentOf, segmentOf = cfg.typeOf, cfg.types, cfg.indentOf, cfg.segmentOf
  for i = 1, #list do
    local t = typeOf(list[i])
    local spec = types[t]
    if not spec then
      error(cfg.who .. ": typeOf returned unknown type '" .. tostring(t) .. "'", 0)
    end
    local d = { grid = spec.grid or false, height = spec.height }
    -- Indent (FR Coffer 2026-08-26): the cell KEEPS its width and the band loses
    -- columns — indented cells must measure the same as their siblings above, or the
    -- indent reads as "these items are smaller".
    if indentOf then
      local indent = indentOf(list[i])
      if type(indent) ~= "number" or indent < 0 then
        error(cfg.who .. ": opts.indentOf must return a number >= 0, got "
          .. tostring(indent), 0)
      end
      if indent > 0 then
        d.indent = indent
        if d.grid then
          local cols = floor((cfg.width - indent) / cfg.colWidth)
          d.columns = cols >= 1 and cols or 1 -- always room for at least one
        end
      end
    end
    if segmentOf and d.grid then d.segment = segmentOf(list[i]) end
    desc[i] = d
    entryType[i] = t
  end
  return desc, entryType
end

-- The flow options _flowLayout needs, derived from the SAME opts table Weave.virtual
-- takes (viewport/columns/padding*/spacing/segment*). `width` overrides viewport[1].
function Weave._flowGeometry(opts, width)
  local padH    = opts.paddingH or opts.padding or 0
  local padV    = opts.paddingV or opts.padding or 0
  local columns = opts.columns or 1
  local usable  = width - 2 * padH
  return {
    columns = columns, spacing = opts.spacing or 0, padTop = padV, padBottom = padV,
    colWidth = usable / columns, width = usable,
    segmentGap = opts.segmentGap or 0,
    labelHeight = opts.segmentLabel and opts.segmentLabel.height or 0,
  }
end

-- Public: the exact plan Weave.virtual (heterogeneous) would paint for `list`, without
-- an instance — for consumers that size their window from the content ("fit"). Takes
-- the same opts as Weave.virtual; opts.width simulates another width.
-- Returns { rows, contentHeight }.
function Weave.flowPlan(list, opts)
  if type(opts) ~= "table" then
    error("Weave.flowPlan: opts must be a table (the same opts as Weave.virtual)", 2)
  end
  if type(opts.types) ~= "table" or type(opts.typeOf) ~= "function" then
    error("Weave.flowPlan: opts.types (a table) and opts.typeOf (a function) are required", 2)
  end
  local width = opts.width or (type(opts.viewport) == "table" and opts.viewport[1])
  if type(width) ~= "number" or width <= 0 then
    error("Weave.flowPlan: needs opts.width or opts.viewport = { width, height }", 2)
  end
  local geo = Weave._flowGeometry(opts, width)
  if geo.width <= 0 then
    error("Weave.flowPlan: horizontal padding leaves no room in width " .. width, 2)
  end
  local desc = Weave._flowDescribe(list, {
    who = "Weave.flowPlan", typeOf = opts.typeOf, types = opts.types,
    indentOf = opts.indentOf, segmentOf = opts.segmentOf,
    colWidth = geo.colWidth, width = geo.width,
  })
  return Weave._flowLayout(desc, geo)
end
