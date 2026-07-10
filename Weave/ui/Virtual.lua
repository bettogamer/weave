-- ui/Virtual.lua — Weave.virtual: a VIRTUALIZED grid, sibling of Weave.each for
-- lists of THOUSANDS (API-v0 §4, M10/ADR-0010). Invariant vs each: the pool is FIXED
-- to the viewport, never to the list. render runs ONCE per pooled frame; scrolling
-- only re-assigns DATA and re-positions — no frame is created by scrolling, and (like
-- each) creating the list in combat is a hard error.
--
--   * Fase 1 (homogeneous): opts.render fn + opts.rowHeight → one pool, O(1) planner
--     (core/Window.lua _windowPlan).
--   * Fase 2 (heterogeneous): opts.types map + opts.typeOf → grid items + full-width
--     headers in one stream, a pool PER TYPE, laid out by the flow planner
--     (core/Flow.lua _flowLayout/_flowVisible). Collapse is the consumer's job (it
--     re-sets the stream); virtual is just a window over whatever flat stream it gets.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.virtual then return end -- lib missing or duplicate copy

local InCombatLockdown = InCombatLockdown
local floor, ceil, max = math.floor, math.ceil, math.max

local COMBAT_MSG = "Weave.virtual: creating a virtualized list is forbidden in combat — "
  .. "build the UI out of combat; in combat the fixed pool only re-glazes and scrolls"

------------------------------------------------------------------------------
-- Virtual instances
------------------------------------------------------------------------------
local VirtualMethods = {}
local VirtualMT = { __index = VirtualMethods }

-- Bakes one pooled row with `render`: fresh item/index signals + one render run,
-- inside the instance's scope so the row's binds (and hide-on-dispose) die with it.
function VirtualMethods:_materializeRow(render)
  local row
  self._scope:run(function()
    local itemSig  = Weave.signal(nil)
    local indexSig = Weave.signal(nil)
    row = render(itemSig, indexSig)
    if type(row) ~= "table" or not row.SetParent then
      error("Weave.virtual: render must return a frame", 0)
    end
    row:SetParent(self._container)
    row._weaveItem, row._weaveIndex = itemSig, indexSig
    row:Hide()
  end)
  return row
end

-- The total pixel height of the full list — a reactive read (like tween:animating()),
-- so Craft's scrollbar can bind its thumb/range to it.
function VirtualMethods:contentHeight()
  return self._contentHeight()
end

------------------------------------------------------------------------------
-- Fase 1: homogeneous grid (single pool, uniform rows)
------------------------------------------------------------------------------
function VirtualMethods:_initHomogeneous(opts)
  self._hetero    = false
  self._render    = opts.render
  self._rowHeight = opts.rowHeight
  self._stride    = opts.rowHeight + self._spacing
  self._pool      = {}
  -- Pool is FIXED, sized to the viewport (core formula), never to the list.
  self._capacity = Weave._windowPlan(0, {
    rowHeight = opts.rowHeight, viewportHeight = self._viewportH,
    columns = self._columns, spacing = self._spacing,
  }).capacity
  for p = 1, self._capacity do
    self._pool[p] = self:_materializeRow(self._render)
  end
end

function VirtualMethods:_window()
  local list = self._listGet()
  if type(list) ~= "table" then
    error("Weave.virtual: source must provide an array, got " .. type(list), 0)
  end
  local plan = Weave._windowPlan(#list, {
    rowHeight = self._rowHeight, viewportHeight = self._viewportH,
    scroll = self._scrollGet(), columns = self._columns, spacing = self._spacing,
  })
  self._contentHeight:set(plan.contentHeight)
  self._maxScroll = plan.maxScroll

  local visible = {}
  for p = 1, self._capacity do
    local row = self._pool[p]
    if p <= plan.count then
      local idx = plan.first + p - 1
      local r   = floor((idx - 1) / self._columns)
      local col = (idx - 1) % self._columns
      row._weaveItem:set(list[idx])
      row._weaveIndex:set(idx)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self._container, "TOPLEFT",
        col * self._colWidth, plan.offset - (r - plan.firstRow) * self._stride)
      row:Show()
      visible[p] = row
    else
      row._weaveItem:set(nil)
      row:Hide()
    end
  end
  self._container._virtualRows = visible
end

------------------------------------------------------------------------------
-- Fase 2: heterogeneous stream (pool per type, flow layout)
------------------------------------------------------------------------------
function VirtualMethods:_initHetero(opts)
  self._hetero = true
  self._typeOf = opts.typeOf
  self._types  = opts.types
  self._pools  = {}
  self._cursor = {}
  self._lastList = nil
  -- One pool per type, each sized to the WORST-CASE visible count of that type (bounded
  -- by the viewport). A cell baked as a header can never become an item, hence per type.
  for name, spec in pairs(opts.types) do
    local n = spec.grid and (ceil(self._viewportH / spec.height) + 1) * self._columns
                        or  (ceil(self._viewportH / spec.height) + 1)
    local pool = {}
    for p = 1, n do pool[p] = self:_materializeRow(spec.render) end
    self._pools[name]  = pool
    self._cursor[name] = 0
  end
end

-- O(total): walk the stream into the pure per-entry descriptor + the flow layout. Only
-- runs when the source array identity changes (data changed), never per scroll.
function VirtualMethods:_rebuildLayout(list)
  if type(list) ~= "table" then
    error("Weave.virtual: source must provide an array, got " .. type(list), 0)
  end
  local desc, entryType = {}, {}
  for i = 1, #list do
    local t = self._typeOf(list[i])
    local spec = self._types[t]
    if not spec then
      error("Weave.virtual: typeOf returned unknown type '" .. tostring(t) .. "'", 0)
    end
    desc[i] = { grid = spec.grid or false, height = spec.height }
    entryType[i] = t
  end
  self._layout = Weave._flowLayout(desc, { columns = self._columns, spacing = self._spacing })
  self._entryType = entryType
  self._contentHeight:set(self._layout.contentHeight)
end

-- O(visible): fill each type's pool with the visible slice and position it. Creates
-- NO frames. Full-width entries span the viewport; grid entries sit at col*colWidth.
function VirtualMethods:_paintHetero()
  local layout, list = self._layout, self._lastList
  local maxS = max(0, layout.contentHeight - self._viewportH)
  self._maxScroll = maxS
  local scroll = self._scrollGet()
  if scroll < 0 then scroll = 0 elseif scroll > maxS then scroll = maxS end

  local vis = Weave._flowVisible(layout, scroll, self._viewportH)
  for name in pairs(self._pools) do self._cursor[name] = 0 end

  local visible = {}
  for r = vis.first, vis.last do
    local row = layout.rows[r]
    for j = row.first, row.first + row.count - 1 do
      local t     = self._entryType[j]
      local grid  = self._types[t].grid
      local c     = self._cursor[t] + 1
      self._cursor[t] = c
      local frame = self._pools[t][c]
      if frame then
        frame._weaveItem:set(list[j])
        frame._weaveIndex:set(j)
        frame:ClearAllPoints()
        local x = grid and (j - row.first) * self._colWidth or 0
        frame:SetPoint("TOPLEFT", self._container, "TOPLEFT", x, scroll - row.y)
        if not grid then -- full-width row: virtual owns its size (the layout's authority)
          frame:SetWidth(self._viewportW)
          frame:SetHeight(self._types[t].height)
        end
        frame:Show()
        visible[#visible + 1] = frame
      end
    end
  end

  for name, pool in pairs(self._pools) do
    for p = self._cursor[name] + 1, #pool do
      pool[p]._weaveItem:set(nil)
      pool[p]:Hide()
    end
  end
  self._container._virtualRows = visible
end

-- The windowing effect body, mode-specific. Reads the reactive source and scroll so the
-- enclosing effect re-runs on any change; the O(total) layout rebuild is cached by array
-- identity, so scrolling only repaints.
function VirtualMethods:_drive()
  if self._hetero then
    local list = self._listGet()
    if list ~= self._lastList then
      self._lastList = list
      self:_rebuildLayout(list)
    end
    self:_paintHetero()
  else
    self:_window()
  end
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

-- Materializes a virtual descriptor under `container` (the viewport). Called by
-- [Weave.children] in Weave.new, or directly by Weave.virtual when opts.parent is
-- given. Returns the instance so the caller can reach :contentHeight().
function Weave._materializeVirtual(container, d)
  if InCombatLockdown() then error(COMBAT_MSG, 3) end

  -- The pool keeps one extra row for the fractional overflow; the container is the
  -- viewport, so it must clip or that row spills below. Intrinsic to virtualizing.
  container:SetClipsChildren(true)

  local opts     = d._opts
  local source   = d._source
  local viewport = opts.viewport

  local inst = setmetatable({
    _container     = container,
    _spacing       = opts.spacing or 0,
    _columns       = opts.columns or 1,
    _viewportW     = viewport[1],
    _viewportH     = viewport[2],
    _colWidth      = viewport[1] / (opts.columns or 1),
    _contentHeight = Weave.signal(0),
    _maxScroll     = 0,
    _scope         = Weave.scope(),
    _warned        = {},
  }, VirtualMT)

  inst._listGet = Weave.isReactive(source) and source or function() return source end

  -- Scroll: read an external signal if the caller brought one; otherwise own one and
  -- drive it with the mouse wheel (works standalone, without Craft).
  local ownsScroll = opts.scroll == nil
  local scrollSig
  if ownsScroll then
    scrollSig = Weave.signal(0)
    inst._scrollGet = scrollSig
  elseif Weave.isReactive(opts.scroll) then
    inst._scrollGet = opts.scroll
  else
    local s = opts.scroll
    inst._scrollGet = function() return s end
  end

  if opts.types then inst:_initHetero(opts) else inst:_initHomogeneous(opts) end

  -- One handle owns the whole grid: dying with the enclosing scope kills the source
  -- effect and every pooled row's binds, and hides the rows (their own handles).
  Weave._attachToScope({ dispose = function() inst._scope:dispose() end })

  -- Windowing effect: tracks the reactive source and scroll; re-glazes on change.
  inst._scope:run(function()
    Weave.effect(function() inst:_drive() end)
  end)

  if ownsScroll then
    local step = opts.wheelStep or (opts.rowHeight or 40)
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(_, delta)
      local next = scrollSig:peek() - delta * step -- wheel down (delta -1) scrolls down
      if next < 0 then next = 0 elseif next > inst._maxScroll then next = inst._maxScroll end
      scrollSig:set(next)
    end)
  end

  return inst
end

function Weave.virtual(source, opts)
  if type(source) ~= "table" and not Weave.isReactive(source) then
    error("Weave.virtual: source must be an array or a signal/computed returning one, got "
      .. type(source), 2)
  end
  if type(opts) ~= "table" then
    error("Weave.virtual: opts must be a table (viewport + render/types required), got "
      .. type(opts), 2)
  end

  if opts.types ~= nil then
    -- Fase 2: heterogeneous
    if opts.render ~= nil then
      error("Weave.virtual: pass either opts.render (homogeneous) or opts.types "
        .. "(heterogeneous), not both", 2)
    end
    if type(opts.typeOf) ~= "function" then
      error("Weave.virtual: opts.typeOf is required (a function) when opts.types is given", 2)
    end
    if type(opts.types) ~= "table" then
      error("Weave.virtual: opts.types must be a table of { render, height, grid? }", 2)
    end
    for name, spec in pairs(opts.types) do
      if type(spec) ~= "table" or type(spec.render) ~= "function" then
        error("Weave.virtual: types." .. tostring(name) .. ".render must be a function", 2)
      end
      if type(spec.height) ~= "number" or spec.height <= 0 then
        error("Weave.virtual: types." .. tostring(name) .. ".height must be a positive number", 2)
      end
    end
  else
    -- Fase 1: homogeneous
    if type(opts.render) ~= "function" then
      error("Weave.virtual: opts.render must be a function, got " .. type(opts.render), 2)
    end
    if type(opts.rowHeight) ~= "number" or opts.rowHeight <= 0 then
      error("Weave.virtual: opts.rowHeight must be a positive number", 2)
    end
  end

  if type(opts.viewport) ~= "table" or type(opts.viewport[1]) ~= "number"
    or type(opts.viewport[2]) ~= "number" then
    error("Weave.virtual: opts.viewport must be { width, height }", 2)
  end
  if opts.columns ~= nil and (type(opts.columns) ~= "number" or opts.columns < 1) then
    error("Weave.virtual: opts.columns must be a number >= 1", 2)
  end

  local descriptor = { _weaveVirtual = true, _source = source, _opts = opts }
  if opts.parent ~= nil then
    return Weave._materializeVirtual(opts.parent, descriptor) -- returns the instance
  end
  return descriptor
end
