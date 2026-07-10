-- ui/Virtual.lua — Weave.virtual: a VIRTUALIZED grid, sibling of Weave.each for
-- lists of THOUSANDS (API-v0 §4, M10/ADR-0010, Fase 1). The invariant that sets
-- it apart from each: the pool is FIXED to the viewport, never to the list. render
-- runs ONCE per pooled frame (bakes it + plugs the binds); scrolling only re-assigns
-- DATA to those frames and re-positions them by a fractional pixel offset — no frame
-- is ever created by scrolling, and (like each) creating the list in combat is a hard
-- error. The window math is the pure planner Weave._windowPlan (core/Window.lua).

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.virtual then return end -- lib missing or duplicate copy

local InCombatLockdown = InCombatLockdown
local floor = math.floor

local COMBAT_MSG = "Weave.virtual: creating a virtualized list is forbidden in combat — "
  .. "build the UI out of combat; in combat the fixed pool only re-glazes and scrolls"

------------------------------------------------------------------------------
-- Virtual instances
------------------------------------------------------------------------------
local VirtualMethods = {}
local VirtualMT = { __index = VirtualMethods }

-- Bakes one pooled row: fresh item/index signals + one render run, inside the
-- instance's own scope so the row's binds (and its hide-on-dispose) die with it.
function VirtualMethods:_materializeRow()
  local row
  self._scope:run(function()
    local itemSig  = Weave.signal(nil)
    local indexSig = Weave.signal(nil)
    row = self._render(itemSig, indexSig)
    if type(row) ~= "table" or not row.SetParent then
      error("Weave.virtual: render must return a frame", 0)
    end
    row:SetParent(self._container)
    row._weaveItem, row._weaveIndex = itemSig, indexSig
    row:Hide()
  end)
  return row
end

-- Re-windows: given the current list and scroll, fill the FIXED pool with the
-- visible slice, position each cell, hide the rest. Creates NO frames. Reads the
-- reactive source/scroll, so the enclosing effect re-runs it on any change.
function VirtualMethods:_window()
  local list = self._listGet()
  if type(list) ~= "table" then
    error("Weave.virtual: source must provide an array, got " .. type(list), 0)
  end
  local total = #list

  local plan = Weave._windowPlan(total, {
    rowHeight      = self._rowHeight,
    viewportHeight = self._viewportH,
    scroll         = self._scrollGet(),
    columns        = self._columns,
    spacing        = self._spacing,
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
      row._weaveItem:set(nil) -- idle: release any reference the row held
      row:Hide()
    end
  end
  self._container._virtualRows = visible -- visible rows in order (specs, DevTools, debugging)
end

-- The total pixel height of the full list — a reactive read (like tween:animating()),
-- so Craft's scrollbar can bind its thumb/range to it.
function VirtualMethods:contentHeight()
  return self._contentHeight()
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
  local columns  = opts.columns or 1
  local spacing  = opts.spacing or 0
  local rowH     = opts.rowHeight
  local viewport = opts.viewport
  local viewW, viewH = viewport[1], viewport[2]

  local inst = setmetatable({
    _container    = container,
    _render       = opts.render,
    _rowHeight    = rowH,
    _spacing      = spacing,
    _stride       = rowH + spacing,
    _columns      = columns,
    _viewportH    = viewH,
    _colWidth     = viewW / columns,
    _pool         = {},
    _contentHeight = Weave.signal(0),
    _maxScroll    = 0,
    _scope        = Weave.scope(),
    _warned       = {},
  }, VirtualMT)

  inst._listGet = Weave.isReactive(source) and source or function() return source end

  -- Scroll: read an external signal if the caller brought one; otherwise own one
  -- and drive it with the mouse wheel (works standalone, without Craft).
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

  -- The pool is FIXED: sized to the viewport (via the core formula), never to the
  -- list. Bake every row once, out of combat, hidden.
  inst._capacity = Weave._windowPlan(0, {
    rowHeight = rowH, viewportHeight = viewH, columns = columns, spacing = spacing,
  }).capacity
  for p = 1, inst._capacity do
    inst._pool[p] = inst:_materializeRow()
  end

  -- One handle owns the whole grid: dying with the enclosing scope kills the source
  -- effect and every pooled row's binds, and hides the rows (their own handles).
  Weave._attachToScope({ dispose = function() inst._scope:dispose() end })

  -- Windowing effect: tracks the reactive source and scroll; re-glazes on change.
  -- render already ran (pool baked) — this only re-assigns data and re-positions.
  inst._scope:run(function()
    Weave.effect(function() inst:_window() end)
  end)

  if ownsScroll then
    local step = opts.wheelStep or inst._stride
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
    error("Weave.virtual: opts must be a table (viewport/rowHeight/render required), got "
      .. type(opts), 2)
  end
  if type(opts.render) ~= "function" then
    error("Weave.virtual: opts.render must be a function, got " .. type(opts.render), 2)
  end
  if type(opts.viewport) ~= "table" or type(opts.viewport[1]) ~= "number"
    or type(opts.viewport[2]) ~= "number" then
    error("Weave.virtual: opts.viewport must be { width, height }", 2)
  end
  if type(opts.rowHeight) ~= "number" or opts.rowHeight <= 0 then
    error("Weave.virtual: opts.rowHeight must be a positive number", 2)
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
