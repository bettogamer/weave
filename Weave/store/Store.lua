-- store/Store.lua — reactive SavedVariables (API-v0 §5): every field is a signal,
-- and writes go straight through to the SV table WoW serializes at logout.
-- Defaults are NEVER materialized into the SV (only explicit writes persist), so
-- shipping a new default in v2 reaches every user who never touched the setting.
-- M3 block 1 scope: flat stores, SV global present (or claimed) at creation;
-- early-call hydration timing is block 2, nested sub-stores and migrations block 3.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.store then return end -- lib missing or duplicate copy

local function isSerializable(v)
  local t = type(v)
  return t == "nil" or t == "boolean" or t == "number" or t == "string" or t == "table"
end

-- One store field: a signal whose set() also persists into the raw SV table.
local function makeField(svName, raw, key, default)
  local initial = raw[key]
  if initial == nil then initial = default end -- explicit nil check: saved false is a value
  local sig = Weave.signal(initial)
  local coreSet = sig.set -- the metatable method, captured before shadowing
  sig.set = function(self, v)
    if Weave._isSecret(v) then
      -- taint philosophy extended to disk: a secret must never be serialized
      print("|cffffd100Weave:|r store '" .. svName .. "." .. key
        .. "' skipped a write: secret values cannot be persisted")
      return
    end
    if not isSerializable(v) then
      error("Weave.store: field '" .. key .. "' rejected a non-serializable value ("
        .. type(v) .. "); SavedVariables only hold boolean/number/string/table", 2)
    end
    coreSet(self, v)
    raw[key] = v -- what readers see is what persists
  end
  return sig
end

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
  -- Adopt the loaded SV table as-is (unknown keys are user data: preserved, never
  -- copied or pruned); claim the global when it does not exist yet (first run).
  local raw = _G[svName]
  if raw == nil then
    raw = {}
    _G[svName] = raw
  end
  local db = { _raw = raw }
  for key, default in pairs(defaults) do
    if type(key) ~= "string" or key:sub(1, 1) == "_" then
      error("Weave.store: default keys must be strings not starting with '_' (got '"
        .. tostring(key) .. "')", 2)
    end
    if type(default) == "table" then
      error("Weave.store: nested defaults ('" .. key .. "') are not supported yet (M3 block 3)", 2)
    end
    db[key] = makeField(svName, raw, key, default)
  end
  return db
end
