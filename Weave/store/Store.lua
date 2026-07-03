-- store/Store.lua — reactive SavedVariables (API-v0 §5): every field is a signal,
-- and writes go straight through to the SV table WoW serializes at logout.
-- Defaults are NEVER materialized into the SV (only explicit writes persist), so
-- shipping a new default in v2 reaches every user who never touched the setting.
--
-- Hydration choreography (the part that silently breaks naive SV code): addon
-- files run first, THEN the client loads the saved file into the global, THEN
-- ADDON_LOADED fires. A store created at file scope starts on a staging table
-- and re-syncs (repointing _raw and every signal) when its owner loads:
--   * saved data wins over pre-hydration writes (disk is the source of truth)
--   * first run (nothing saved): the staging table is claimed, pre-writes survive
-- opts.addon names the owner (exact); without it, the next ADDON_LOADED is
-- assumed to be the owner's (correct for the file-scope pattern).
--
-- M3 block 3 pending: nested sub-stores and version/migrate.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.store then return end -- lib missing or duplicate copy

local function isSerializable(v)
  local t = type(v)
  return t == "nil" or t == "boolean" or t == "number" or t == "string" or t == "table"
end

------------------------------------------------------------------------------
-- Hydration
------------------------------------------------------------------------------
local pending = {} -- store states waiting for their owner's ADDON_LOADED
local watcher      -- shared frame, created on first early store

local function hydrate(state)
  local loaded = _G[state.svName]
  if loaded ~= nil then
    state.raw = loaded -- disk is the source of truth: staging writes lose
  else
    _G[state.svName] = state.raw -- first run: claim the staging table as the SV
  end
  state.db._raw = state.raw
  for i = 1, #state.fields do
    local f = state.fields[i]
    local v = state.raw[f.key]
    if v == nil then v = f.default end
    -- core set (not the persisting wrapper): readers re-sync live, and defaults
    -- are never written back to disk
    f.coreSet(f.sig, v)
  end
end

local function watchAddonLoaded(state)
  pending[#pending + 1] = state
  if watcher then return end
  watcher = CreateFrame("Frame")
  watcher:Hide()
  watcher:SetScript("OnEvent", function(_, _, addonName)
    local i = 1
    while i <= #pending do
      local st = pending[i]
      if st.owner == nil or st.owner == addonName then
        table.remove(pending, i)
        hydrate(st)
      else
        i = i + 1
      end
    end
  end)
  watcher:RegisterEvent("ADDON_LOADED")
end

------------------------------------------------------------------------------
-- Fields
------------------------------------------------------------------------------
-- One store field: a signal whose set() also persists into the current raw table.
local function makeField(state, key, default)
  local initial = state.raw[key]
  if initial == nil then initial = default end -- explicit nil check: saved false is a value
  local sig = Weave.signal(initial)
  local coreSet = sig.set -- the metatable method, captured before shadowing
  sig.set = function(self, v)
    if Weave._isSecret(v) then
      -- taint philosophy extended to disk: a secret must never be serialized
      print("|cffffd100Weave:|r store '" .. state.svName .. "." .. key
        .. "' skipped a write: secret values cannot be persisted")
      return
    end
    if not isSerializable(v) then
      error("Weave.store: field '" .. key .. "' rejected a non-serializable value ("
        .. type(v) .. "); SavedVariables only hold boolean/number/string/table", 2)
    end
    coreSet(self, v)
    state.raw[key] = v -- what readers see is what persists
  end
  state.fields[#state.fields + 1] = { sig = sig, key = key, default = default, coreSet = coreSet }
  return sig
end

------------------------------------------------------------------------------
-- Constructor
------------------------------------------------------------------------------
function Weave.store(svName, defaults, opts)
  if type(svName) ~= "string" then
    error("Weave.store: expected a SavedVariables name (string), got " .. type(svName), 2)
  end
  if type(defaults) ~= "table" then
    error("Weave.store: expected a defaults table, got " .. type(defaults), 2)
  end
  if opts ~= nil and type(opts) ~= "table" then
    error("Weave.store: opts must be a table, got " .. type(opts), 2)
  end
  local owner = opts and opts.addon
  if owner ~= nil and type(owner) ~= "string" then
    error("Weave.store: opts.addon must be a string (the owning addon's name)", 2)
  end

  local state = { svName = svName, owner = owner, fields = {} }
  local needsWatch = false
  local raw = _G[svName]
  if raw ~= nil then
    state.raw = raw -- SV already loaded: adopt it as-is (unknown keys preserved)
  elseif owner and C_AddOns and C_AddOns.IsAddOnLoaded(owner) then
    state.raw = {} -- owner finished loading and nothing was ever saved: claim now
    _G[svName] = state.raw
  else
    state.raw = {} -- staging: the real table arrives with the owner's ADDON_LOADED
    needsWatch = true
  end

  local db = { _raw = state.raw }
  state.db = db
  for key, default in pairs(defaults) do
    if type(key) ~= "string" or key:sub(1, 1) == "_" then
      error("Weave.store: default keys must be strings not starting with '_' (got '"
        .. tostring(key) .. "')", 2)
    end
    if type(default) == "table" then
      error("Weave.store: nested defaults ('" .. key .. "') are not supported yet (M3 block 3)", 2)
    end
    db[key] = makeField(state, key, default)
  end

  if needsWatch then watchAddonLoaded(state) end
  return db
end
