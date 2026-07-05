-- ui/Each.lua — Weave.each: reactive lists with combat-safe frame pooling
-- (API-v0 §4, M6/ADR-0007). The design invariant: `render` runs ONCE per pooled
-- row (it bakes the frame and plugs the binds); list changes only flow DATA
-- through the per-row item/index signals. Frames are reused, hidden into the
-- pool or materialized — never destroyed, and NEVER created in combat: if the
-- pool runs out mid-fight, each shows what it can, warns once and settles the
-- debt on PLAYER_REGEN_ENABLED (same degrade-don't-crash spirit as secrets).

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.each then return end -- lib missing or duplicate copy

local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
-- 12.0+ client API; shim for older clients and the headless runner
local issecretvalue = issecretvalue or function() return false end

local COMBAT_MSG = "Weave.each: creating a list is forbidden in combat — build the "
  .. "UI out of combat; in combat the pool only recycles"

------------------------------------------------------------------------------
-- Shared out-of-combat watcher: each instances that overflowed their pool in
-- combat register here and finish their reconciliation on PLAYER_REGEN_ENABLED.
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
      inst:_reconcile(inst._lastList)
    end
  end)
end

------------------------------------------------------------------------------
-- Each instances
------------------------------------------------------------------------------
local EachMethods = {}
local EachMT = { __index = EachMethods }

function EachMethods:_warnOnce(what, msg)
  if self._warned[what] then return end
  self._warned[what] = true
  print("|cffffcc00Weave.each|r: " .. msg)
end

-- Bakes one row: fresh item/index signals + one render run, inside the each's
-- own scope so the row's binds (and its hide-on-dispose) die with it.
function EachMethods:_materializeRow(item, index)
  local row
  self._scope:run(function()
    local itemSig  = Weave.signal(item)
    local indexSig = Weave.signal(index)
    row = self._render(itemSig, indexSig)
    if type(row) ~= "table" or not row.SetParent then
      error("Weave.each: render must return a frame", 0)
    end
    row:SetParent(self._container)
    row._weaveItem, row._weaveIndex = itemSig, indexSig
  end)
  return row
end

-- Keys for this pass: opts.key over each item, or nil to fall back to index
-- keying (declared key missing/secret — a secret cannot be a table key).
function EachMethods:_keysFor(list)
  if not self._key then return nil end
  local keys = {}
  for i = 1, #list do
    local ok, k = pcall(self._key, list[i])
    if not ok then
      if Weave._isSecretError(k) then k = nil else error(k, 0) end
    end
    if k == nil or issecretvalue(k) then
      self:_warnOnce("key", "key is secret or nil — falling back to index keying")
      return nil
    end
    keys[i] = k
  end
  return keys
end

function EachMethods:_applyLayout()
  local prev
  for i = 1, #self._visible do
    local row = self._visible[i]
    row:ClearAllPoints()
    if prev then
      row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -self._spacing)
    else
      row:SetPoint("TOPLEFT", self._container, "TOPLEFT", 0, 0)
    end
    prev = row
  end
end

function EachMethods:_reconcile(list)
  if type(list) ~= "table" then
    error("Weave.each: source must provide an array, got " .. type(list), 0)
  end
  self._lastList = list

  local keys = self:_keysFor(list)
  if not keys then -- index keying: position i is its own identity
    keys = {}
    for i = 1, #list do keys[i] = i end
  end

  local plan = Weave._reconcileKeys(self._shownKeys, keys)
  local inCombat = InCombatLockdown()
  local visible, shownKeys = {}, {}
  local overflow = false

  for i = 1, #list do
    local j = plan.slots[i]
    local row
    if j then
      row = self._visible[j]
    else
      row = self._spare[#self._spare]
      if row then
        self._spare[#self._spare] = nil
      elseif inCombat then
        overflow = true -- never CreateFrame in combat: show what the pool allows
      else
        row = self:_materializeRow(list[i], i)
      end
    end
    if row then
      local v = #visible + 1
      visible[v] = row
      shownKeys[v] = keys[i]
      row._weaveItem:set(list[i])
      row._weaveIndex:set(i)
      row:Show()
    end
  end

  for f = 1, #plan.freed do
    local row = self._visible[plan.freed[f]]
    row:Hide()
    self._spare[#self._spare + 1] = row
  end

  self._visible = visible
  self._shownKeys = shownKeys
  self._container._eachRows = visible -- rows in list order (specs, DevTools, debugging)

  if self._layout then self:_applyLayout() end

  if overflow then
    self:_warnOnce("pool", "pool exhausted in combat — showing a partial list; "
      .. "it will catch up out of combat (pre-bake rows with opts.warm)")
    pending[self] = true
  end
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

-- Materializes an each descriptor under `container`. Called by [Weave.children]
-- in Weave.new, or directly by Weave.each when opts.parent is given.
function Weave._materializeEach(container, d)
  if InCombatLockdown() then error(COMBAT_MSG, 2) end
  ensureRegenWatcher()

  local opts = d._opts or {}
  local inst = setmetatable({
    _container = container,
    _render    = d._render,
    _key       = opts.key,
    _layout    = opts.layout ~= false,
    _spacing   = opts.spacing or 0,
    _visible   = {},
    _spare     = {},
    _shownKeys = {},
    _scope     = Weave.scope(),
    _warned    = {},
  }, EachMT)

  -- One handle owns the whole list: dying with the enclosing scope kills the
  -- source effect and every row's binds, and hides the rows (their own handles).
  Weave._attachToScope({
    dispose = function()
      pending[inst] = nil
      inst._scope:dispose()
    end,
  })

  if Weave.props._isCallable(d._source) then
    inst._scope:run(function()
      Weave.effect(function() inst:_reconcile(d._source()) end)
    end)
  else
    inst:_reconcile(d._source) -- literal list: applied once (signal-or-literal rule)
  end

  -- opts.warm: pre-bake hidden spare rows so the pool absorbs in-combat growth.
  local warm = opts.warm
  if warm ~= nil then
    if type(warm) ~= "number" then
      error("Weave.each: opts.warm must be a number, got " .. type(warm), 2)
    end
    for _ = #inst._visible + #inst._spare + 1, warm do
      local row = inst:_materializeRow(nil, nil)
      row:Hide()
      inst._spare[#inst._spare + 1] = row
    end
  end

  return inst
end

function Weave.each(source, render, opts)
  if type(source) ~= "table" and not Weave.props._isCallable(source) then
    error("Weave.each: source must be an array or a signal/computed returning one, got "
      .. type(source), 2)
  end
  if type(render) ~= "function" then
    error("Weave.each: render must be a function, got " .. type(render), 2)
  end
  if opts ~= nil and type(opts) ~= "table" then
    error("Weave.each: opts must be a table, got " .. type(opts), 2)
  end
  if opts and opts.key ~= nil and type(opts.key) ~= "function" then
    error("Weave.each: opts.key must be a function, got " .. type(opts.key), 2)
  end

  local descriptor = { _weaveEach = true, _source = source, _render = render, _opts = opts }
  if opts and opts.parent ~= nil then
    Weave._materializeEach(opts.parent, descriptor)
  end
  return descriptor
end
