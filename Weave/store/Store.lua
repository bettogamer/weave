-- store/Store.lua — reactive SavedVariables (API-v0 §5): every field is a signal,
-- and writes go straight through to the SV table WoW serializes at logout.
-- Defaults are NEVER materialized into the SV (only explicit writes persist), so
-- shipping a new default in v2 reaches every user who never touched the setting.
-- Nested default tables become sub-stores; their SV sub-tables are created on
-- first write only. `_version` is the ONE key Weave writes on its own (metadata
-- for opts.version/opts.migrate) — hence default keys may not start with "_".
--
-- Hydration choreography (the part that silently breaks naive SV code): addon
-- files run first, THEN the client loads the saved file into the global, THEN
-- ADDON_LOADED fires. A store created at file scope starts on a staging table
-- and re-syncs (repointing _raw and every signal) when its owner loads:
--   * saved data wins over pre-hydration writes (disk is the source of truth)
--   * first run (nothing saved): the staging table is claimed, pre-writes survive
--   * migrations run BEFORE the re-sync, so readers only ever see converted data
-- opts.addon names the owner (exact); without it, the next ADDON_LOADED is
-- assumed to be the owner's (correct for the file-scope pattern).

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.store then return end -- lib missing or duplicate copy

local function isSerializable(v)
  local t = type(v)
  return t == "nil" or t == "boolean" or t == "number" or t == "string" or t == "table"
end

------------------------------------------------------------------------------
-- Raw-table resolution (nesting-aware)
------------------------------------------------------------------------------
-- Resolves the CURRENT raw table for a container. create=true materializes
-- missing sub-tables on the way (write path) and repairs corrupt non-table
-- saves; create=false returns nil if any level is missing (read path).
local function rawFor(container, create)
  if container.parent == nil then
    return container.raw
  end
  local parentRaw = rawFor(container.parent, create)
  if parentRaw == nil then return nil end
  local sub = parentRaw[container.key]
  if type(sub) ~= "table" then
    if not create then return nil end
    sub = {}
    parentRaw[container.key] = sub
  end
  return sub
end

------------------------------------------------------------------------------
-- Hydration & migrations
------------------------------------------------------------------------------
local pending = {} -- store states waiting for their owner's ADDON_LOADED
local watcher      -- shared frame, created on first early store

-- _version bookkeeping. Migrations only ever run over PRE-EXISTING data.
local function applyVersion(state, firstRun)
  if state.version == nil then return end
  local oldV = state.raw._version
  if not firstRun and oldV ~= state.version and state.migrate then
    state.migrate(state.raw, oldV)
  end
  state.raw._version = state.version
end

local function hydrate(state)
  local loaded = _G[state.svName]
  local firstRun = loaded == nil
  if firstRun then
    _G[state.svName] = state.raw -- claim the staging table as the SV
  else
    state.raw = loaded -- disk is the source of truth: staging writes lose
  end
  state.db._raw = state.raw
  applyVersion(state, firstRun) -- BEFORE the re-sync: readers see migrated data
  for i = 1, #state.fields do
    local f = state.fields[i]
    local r = rawFor(f.container, false)
    local v = r and r[f.key]
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
-- Fields & containers
------------------------------------------------------------------------------
-- One store field: a signal whose set() also persists into the current raw table.
local function makeField(state, container, key, default)
  local r = rawFor(container, false)
  local initial = r and r[key]
  if initial == nil then initial = default end -- explicit nil check: saved false is a value
  local sig = Weave.signal(initial)
  local coreSet = sig.set -- the metatable method, captured before shadowing
  sig.set = function(self, v)
    if Weave._isSecret(v) then
      -- taint philosophy extended to disk: a secret must never be serialized
      print("|cffffd100Weave:|r store '" .. state.svName .. "." .. container.path .. key
        .. "' skipped a write: secret values cannot be persisted")
      return
    end
    if not isSerializable(v) then
      error("Weave.store: field '" .. container.path .. key
        .. "' rejected a non-serializable value (" .. type(v)
        .. "); SavedVariables only hold boolean/number/string/table", 2)
    end
    coreSet(self, v)
    rawFor(container, true)[key] = v -- what readers see is what persists
  end
  state.fields[#state.fields + 1] =
    { sig = sig, key = key, default = default, coreSet = coreSet, container = container }
  return sig
end

-- Recursively builds fields (and sub-stores for table defaults) into db.
local function buildInto(state, container, defaults, db)
  for key, default in pairs(defaults) do
    if type(key) ~= "string" or key:sub(1, 1) == "_" then
      error("Weave.store: default keys must be strings not starting with '_' (got '"
        .. tostring(key) .. "')", 2)
    end
    if type(default) == "table" then
      local sub = { parent = container, key = key, path = container.path .. key .. "." }
      local subDb = {}
      buildInto(state, sub, default, subDb)
      db[key] = subDb
    else
      db[key] = makeField(state, container, key, default)
    end
  end
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
  if opts and opts.version ~= nil and type(opts.version) ~= "number" then
    error("Weave.store: opts.version must be a number", 2)
  end
  if opts and opts.migrate ~= nil and type(opts.migrate) ~= "function" then
    error("Weave.store: opts.migrate must be a function", 2)
  end

  local state = {
    svName  = svName,
    owner   = owner,
    fields  = {},
    version = opts and opts.version,
    migrate = opts and opts.migrate,
    parent  = nil, -- the root state doubles as the root container
    path    = "",
  }
  local needsWatch = false
  local raw = _G[svName]
  if raw ~= nil then
    state.raw = raw -- SV already loaded: adopt it as-is (unknown keys preserved)
    applyVersion(state, false) -- migrate BEFORE fields read their initial values
  else
    state.raw = {} -- staging: the real table arrives with the owner's ADDON_LOADED
    needsWatch = true -- ALWAYS watch while the global is nil, even if the owner
                      -- reports loaded: IsAddOnLoaded is true DURING the owner's
                      -- own file execution, before its SV loads (in-game 12.0.7).
    if owner and C_AddOns and C_AddOns.IsAddOnLoaded(owner) then
      -- Truly-late store (no event will come): claim now so writes persist.
      -- If ADDON_LOADED does fire after all (the file-scope case), hydrate()
      -- re-adopts whatever the client put in the global — self-healing.
      _G[svName] = state.raw
      applyVersion(state, true)
    end
  end

  local db = { _raw = state.raw }
  state.db = db
  buildInto(state, state, defaults, db)

  if needsWatch then watchAddonLoaded(state) end
  return db
end
