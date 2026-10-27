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

local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
local floor, ceil, max = math.floor, math.ceil, math.max

local COMBAT_MSG = "Weave.virtual: creating a virtualized list is forbidden in combat — "
  .. "build the UI out of combat; in combat the fixed pool only re-glazes and scrolls"

------------------------------------------------------------------------------
-- Shared out-of-combat watcher: instances whose viewport GREW in combat (Resize,
-- FR Coffer 2026-08-27) can't materialize the extra pooled rows right then, so
-- they register here and settle the debt on PLAYER_REGEN_ENABLED — the same
-- degrade-don't-crash spirit as Weave.each. Created lazily: an instance that
-- never resizes in combat never pays for the frame.
------------------------------------------------------------------------------
local regenFrame = nil
local pending = {} -- instance -> true

local function ensureRegenWatcher()
  if regenFrame then return end
  regenFrame = CreateFrame("Frame")
  regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  regenFrame:SetScript("OnEvent", function()
    for inst in pairs(pending) do
      pending[inst] = nil
      if not inst._disposed then
        inst._geom:set(inst._geom:peek() + 1) -- re-drive: now the pool may grow
      end
    end
  end)
end

------------------------------------------------------------------------------
-- Virtual instances
------------------------------------------------------------------------------
local VirtualMethods = {}
local VirtualMT = { __index = VirtualMethods }

function VirtualMethods:_warnOnce(what, msg)
  if self._warned[what] then return end
  self._warned[what] = true
  print("|cffffcc00Weave.virtual|r: " .. msg)
end

local POOL_MSG = "the viewport grew in combat — showing fewer rows than it now fits; "
  .. "the pool will catch up out of combat (no frame is ever created in combat)"

-- Registers the pool debt left by a growth attempted in combat.
function VirtualMethods:_deferGrowth()
  ensureRegenWatcher()
  pending[self] = true
  self:_warnOnce("pool", POOL_MSG)
end

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
  self:_ensureCapacity()
end

-- Pool is FIXED to the VIEWPORT (core formula), never to the list — but the viewport
-- can now change (Resize), so this runs on every drive, not just at build time. It only
-- ever GROWS: shrinking keeps the frames (hidden by _window, reused if it grows back),
-- which is why shrinking is always combat-safe and growing is the only deferred half.
function VirtualMethods:_ensureCapacity()
  local want = Weave._windowPlan(0, {
    rowHeight = self._rowHeight, viewportHeight = self._viewportH,
    columns = self._columns, spacing = self._spacing,
  }).capacity
  local pool = self._pool
  if #pool < want then
    if InCombatLockdown() then
      self:_deferGrowth()
    else
      for p = #pool + 1, want do pool[p] = self:_materializeRow(self._render) end
    end
  end
  self._capacity = #pool
end

function VirtualMethods:_window()
  local list = self._listGet()
  if type(list) ~= "table" then
    error("Weave.virtual: source must provide an array, got " .. type(list), 0)
  end
  local plan = Weave._windowPlan(#list, {
    rowHeight = self._rowHeight, viewportHeight = self._viewportH,
    scroll = self._scrollGet(), columns = self._columns, spacing = self._spacing,
    padTop = self._padV, padBottom = self._padV,
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
        self._padH + col * self._colWidth, plan.offset - (r - plan.firstRow) * self._stride)
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
  for name in pairs(opts.types) do
    self._pools[name]  = {}
    self._cursor[name] = 0
  end
  -- Segments (FR Coffer 2026-10-26): labels get their OWN pool — a label frame is
  -- never a cell — sized like the grid pools, O(visible).
  self._segmentOf    = opts.segmentOf
  self._segmentGap   = opts.segmentGap or 0
  self._segmentLabel = opts.segmentLabel
  self._labelPool    = {}
  self:_ensurePools()
end

-- Bakes one pooled label: a fresh `info` signal + one render run, in the instance scope.
function VirtualMethods:_materializeLabel(render)
  local label
  self._scope:run(function()
    local infoSig = Weave.signal(nil)
    label = render(infoSig)
    if type(label) ~= "table" or not label.SetParent then
      error("Weave.virtual: segmentLabel.render must return a frame", 0)
    end
    label:SetParent(self._container)
    label._weaveInfo = infoSig
    label:Hide()
  end)
  return label
end

-- One pool per type, each sized to the WORST-CASE visible count of that type (bounded
-- by the viewport). A cell baked as a header can never become an item, hence per type.
-- Grid types are bounded by the GLOBAL `columns`, which stays the ceiling even when an
-- indented band packs fewer per row. Grows only — see _ensureCapacity.
function VirtualMethods:_ensurePools()
  local inCombat, short = InCombatLockdown(), false
  local minGridH
  for name, spec in pairs(self._types) do
    local rows = ceil(self._viewportH / spec.height) + 1
    local want = spec.grid and rows * self._columns or rows
    if spec.grid and (not minGridH or spec.height < minGridH) then minGridH = spec.height end
    local pool = self._pools[name]
    if #pool < want then
      if inCombat then
        short = true
      else
        for p = #pool + 1, want do pool[p] = self:_materializeRow(spec.render) end
      end
    end
  end
  -- Worst case: every visible grid row full of one-cell segments, each labelled.
  if self._segmentLabel and minGridH then
    local want = (ceil(self._viewportH / minGridH) + 1) * self._columns
    local pool = self._labelPool
    if #pool < want then
      if inCombat then
        short = true
      else
        for p = #pool + 1, want do pool[p] = self:_materializeLabel(self._segmentLabel.render) end
      end
    end
  end
  if short then self:_deferGrowth() end
end

-- O(total): walk the stream into the pure per-entry descriptor + the flow layout. Only
-- runs when the source array identity changes (data changed), never per scroll.
-- Descriptors and geometry come from the same core helpers Weave.flowPlan uses, so a
-- consumer's estimate can never drift from what is painted.
function VirtualMethods:_rebuildLayout(list)
  local geo = Weave._flowGeometry({
    columns = self._columns, spacing = self._spacing,
    paddingH = self._padH, paddingV = self._padV,
    segmentGap = self._segmentGap, segmentLabel = self._segmentLabel,
  }, self._viewportW)
  local desc, entryType = Weave._flowDescribe(list, {
    who = "Weave.virtual", typeOf = self._typeOf, types = self._types,
    indentOf = self._indentOf, segmentOf = self._segmentOf,
    colWidth = geo.colWidth, width = geo.width,
  })
  self._layout = Weave._flowLayout(desc, geo)
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

  local visible, labels = {}, {}
  local colW = self._colWidth
  for r = vis.first, vis.last do
    local row = layout.rows[r]
    local rowY = scroll - row.y
    local bandX = self._padH + row.indent
    if row.segs then
      -- Segmented row: cells sit at their segment's x and cellY below the labels.
      for _, seg in ipairs(row.segs) do
        for j = seg.first, seg.first + seg.count - 1 do
          self:_place(list, j, bandX + seg.x + (j - seg.first) * colW, rowY - row.cellY, visible)
        end
        if seg.label and self._segmentLabel then self:_placeLabel(list, seg, bandX + seg.x, rowY, labels) end
      end
    else
      for j = row.first, row.first + row.count - 1 do
        local grid = self._types[self._entryType[j]].grid
        self:_place(list, j, bandX + (grid and (j - row.first) * colW or 0), rowY, visible,
          row.indent)
      end
    end
  end

  for name, pool in pairs(self._pools) do
    for p = self._cursor[name] + 1, #pool do
      pool[p]._weaveItem:set(nil)
      pool[p]:Hide()
    end
  end
  for p = #labels + 1, #self._labelPool do
    self._labelPool[p]._weaveInfo:set(nil)
    self._labelPool[p]:Hide()
  end
  self._container._virtualRows   = visible
  self._container._virtualLabels = labels
end

-- Fills the next pooled frame of entry j's type and anchors it at (x, y). `indent` is
-- only read for full-width rows, whose size virtual owns (the layout's authority).
function VirtualMethods:_place(list, j, x, y, visible, indent)
  local t = self._entryType[j]
  local c = self._cursor[t] + 1
  self._cursor[t] = c
  local frame = self._pools[t][c]
  if not frame then return end -- pool short (grew in combat): paint what there is
  frame._weaveItem:set(list[j])
  frame._weaveIndex:set(j)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", self._container, "TOPLEFT", x, y)
  if not self._types[t].grid then
    frame:SetWidth(self._viewportW - 2 * self._padH - (indent or 0))
    frame:SetHeight(self._types[t].height)
  end
  frame:Show()
  visible[#visible + 1] = frame
end

-- Fills the next pooled label for a segment's first stretch. `info` only changes when
-- the label now shows another segment or width, so scrolling doesn't re-run its binds.
function VirtualMethods:_placeLabel(list, seg, x, y, labels)
  local label = self._labelPool[#labels + 1]
  if not label then return end
  local width = seg.count * self._colWidth
  local info  = label._weaveInfo:peek()
  local entry = list[seg.first]
  if not info or info.key ~= seg.key or info.first ~= seg.first or info.entry ~= entry
    or info.count ~= seg.total or info.width ~= width then
    label._weaveInfo:set({ key = seg.key, entry = entry, first = seg.first,
      count = seg.total, width = width })
  end
  label:ClearAllPoints()
  label:SetPoint("TOPLEFT", self._container, "TOPLEFT", x, y)
  label:SetWidth(width)
  label:SetHeight(self._segmentLabel.height)
  label:Show()
  labels[#labels + 1] = label
end

-- The windowing effect body, mode-specific. Reads the reactive source and scroll so the
-- enclosing effect re-runs on any change; the O(total) layout rebuild is cached by array
-- identity, so scrolling only repaints.
--
-- Asleep (viewport not visible, FR Coffer 2026-09-02) it returns BEFORE reading the
-- source, the scroll or the geometry: the effect re-tracks on every run, so it lets go
-- of all three and no change reaches it — nor, with nobody else reading it, the
-- source's own computed pipeline (ADR-0012). Waking re-runs it against the CURRENT
-- values. The very first pass always runs, so contentHeight is valid from birth.
function VirtualMethods:_drive()
  if not self._awake() and self._primed then return end
  self._primed = true
  self._geom() -- track the viewport/columns signal: Resize re-runs this effect
  if self._hetero then
    local list = self._listGet()
    if list ~= self._lastList or self._layoutDirty then
      self._lastList    = list
      self._layoutDirty = false
      self:_rebuildLayout(list)
    end
    self:_ensurePools()
    self:_paintHetero()
  else
    self:_ensureCapacity()
    self:_window()
  end
end

------------------------------------------------------------------------------
-- Resize: a LIVE viewport (FR Coffer 2026-08-27)
------------------------------------------------------------------------------
-- Geometry is applied ALWAYS and at once — colWidth, contentHeight and the re-packed
-- flow never wait for combat to end. The only half that cannot happen in combat is
-- CREATING the extra pooled rows a taller viewport wants, and that is deferred to
-- PLAYER_REGEN_ENABLED (showing fewer rows than ideal mid-fight is survivable).
-- Not a setter storm: it bumps one internal signal and the windowing effect re-plans
-- and repaints down the path it already uses.
function VirtualMethods:Resize(opts)
  if type(opts) ~= "table" then
    error("Weave.virtual: Resize expects a table { width?, height?, columns? }, got "
      .. type(opts), 2)
  end
  if self._disposed then return end

  local w = opts.width   or self._viewportW
  local h = opts.height  or self._viewportH
  local n = opts.columns or self._columns
  if type(w) ~= "number" or w <= 0 then
    error("Weave.virtual: Resize width must be a positive number", 2)
  end
  if type(h) ~= "number" or h <= 0 then
    error("Weave.virtual: Resize height must be a positive number", 2)
  end
  if type(n) ~= "number" or n < 1 then
    error("Weave.virtual: Resize columns must be a number >= 1", 2)
  end
  if 2 * self._padH >= w then
    error("Weave.virtual: horizontal padding (" .. self._padH .. ") leaves no room in "
      .. "viewport width " .. w, 2)
  end
  if w == self._viewportW and h == self._viewportH and n == self._columns then
    return -- idempotent: same geometry, not a single SetPoint
  end

  self._viewportW, self._viewportH, self._columns = w, h, n
  self._colWidth    = (w - 2 * self._padH) / n
  self._layoutDirty = true -- the flow plan depends on columns/width, never on the height
  self._geom:set(self._geom:peek() + 1)
end

function VirtualMethods:SetViewport(w, h)    self:Resize({ width = w, height = h }) end
function VirtualMethods:SetViewportHeight(h) self:Resize({ height = h }) end
function VirtualMethods:SetColumns(n)        self:Resize({ columns = n }) end

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

  -- Padding (FR Coffer 2026-07-23): opts.padding is the scalar for all four sides;
  -- opts.paddingH / opts.paddingV override per axis. Symmetric inset — horizontal
  -- shrinks colWidth so the last column is not flush with the clip either.
  local padH = opts.paddingH or opts.padding or 0
  local padV = opts.paddingV or opts.padding or 0

  local inst = setmetatable({
    _container     = container,
    _spacing       = opts.spacing or 0,
    _columns       = opts.columns or 1,
    _padH          = padH,
    _padV          = padV,
    _viewportW     = viewport[1],
    _viewportH     = viewport[2],
    _colWidth      = (viewport[1] - 2 * padH) / (opts.columns or 1),
    _contentHeight = Weave.signal(0),
    _maxScroll     = 0,
    _scope         = Weave.scope(),
    _warned        = {},
    _indentOf      = opts.indentOf,
    _geom          = Weave.signal(0), -- bumped by Resize; the drive effect tracks it
    _layoutDirty   = false,
    _disposed      = false,
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
  Weave._attachToScope({ dispose = function()
    inst._disposed = true
    pending[inst] = nil
    inst._scope:dispose()
  end })

  -- Sleep while nobody can see it: OnShow/OnHide also fire when an ANCESTOR toggles,
  -- and IsVisible() (not IsShown) is the truth. HookScript, never SetScript: the
  -- consumer's own handlers stay theirs. Hooks can't be removed — dispose mutes them.
  inst._awake = Weave.signal(container:IsVisible() and true or false)
  local function syncAwake()
    if not inst._disposed then inst._awake:set(container:IsVisible() and true or false) end
  end
  container:HookScript("OnShow", syncAwake)
  container:HookScript("OnHide", syncAwake)

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

  if opts.indentOf ~= nil then
    if opts.types == nil then
      error("Weave.virtual: opts.indentOf requires opts.types (indent is a heterogeneous-"
        .. "flow feature: it re-packs bands of grid cells)", 2)
    end
    if type(opts.indentOf) ~= "function" then
      error("Weave.virtual: opts.indentOf must be a function, got " .. type(opts.indentOf), 2)
    end
  end

  if opts.segmentOf ~= nil then
    if opts.types == nil then
      error("Weave.virtual: opts.segmentOf requires opts.types (segments are a "
        .. "heterogeneous-flow feature: they pack runs of grid cells in line)", 2)
    end
    if type(opts.segmentOf) ~= "function" then
      error("Weave.virtual: opts.segmentOf must be a function, got " .. type(opts.segmentOf), 2)
    end
  end
  if opts.segmentGap ~= nil and (type(opts.segmentGap) ~= "number" or opts.segmentGap < 0) then
    error("Weave.virtual: opts.segmentGap must be a number >= 0", 2)
  end
  if opts.segmentLabel ~= nil then
    if opts.segmentOf == nil then
      error("Weave.virtual: opts.segmentLabel requires opts.segmentOf", 2)
    end
    local l = opts.segmentLabel
    if type(l) ~= "table" or type(l.render) ~= "function"
      or type(l.height) ~= "number" or l.height <= 0 then
      error("Weave.virtual: opts.segmentLabel must be { height = number > 0, "
        .. "render = function(info) -> frame }", 2)
    end
  end

  if type(opts.viewport) ~= "table" or type(opts.viewport[1]) ~= "number"
    or type(opts.viewport[2]) ~= "number" then
    error("Weave.virtual: opts.viewport must be { width, height }", 2)
  end
  if opts.columns ~= nil and (type(opts.columns) ~= "number" or opts.columns < 1) then
    error("Weave.virtual: opts.columns must be a number >= 1", 2)
  end
  for _, k in ipairs({ "padding", "paddingH", "paddingV" }) do
    if opts[k] ~= nil and (type(opts[k]) ~= "number" or opts[k] < 0) then
      error("Weave.virtual: opts." .. k .. " must be a number >= 0", 2)
    end
  end
  local padH = opts.paddingH or opts.padding or 0
  if 2 * padH >= opts.viewport[1] then
    error("Weave.virtual: horizontal padding (" .. padH .. ") leaves no room in viewport "
      .. "width " .. opts.viewport[1], 2)
  end

  local descriptor = { _weaveVirtual = true, _source = source, _opts = opts }
  if opts.parent ~= nil then
    return Weave._materializeVirtual(opts.parent, descriptor) -- returns the instance
  end
  return descriptor
end
