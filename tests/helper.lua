-- tests/helper.lua — loads Weave the way WoW would (per-file vararg) with a minimal LibStub.
-- The core is pure Lua (ADR-0004): this helper mocks NO WoW API — if a core/ test ever
-- needs one, the design is wrong (see CLAUDE.md).

local M = {}

local function newLibStub()
  local libs = {}
  local LibStub = { minor = 2 }
  function LibStub:NewLibrary(major, minor)
    local old = libs[major]
    if old and old.minor >= minor then return nil end
    libs[major] = libs[major] or { lib = {}, minor = minor }
    libs[major].minor = minor
    return libs[major].lib
  end
  function LibStub:GetLibrary(major, silent)
    if not libs[major] and not silent then error("LibStub: lib no registrada: " .. major, 2) end
    return libs[major] and libs[major].lib
  end
  setmetatable(LibStub, { __call = function(self, major, silent) return self:GetLibrary(major, silent) end })
  return LibStub
end

------------------------------------------------------------------------------
-- Fake secret values (WoW 12.0+ simulation, headless)
-- Real secrets throw on any operation; these mimic that, with the same error
-- wording the real client uses ("a secret ... value") so degradation paths match.
------------------------------------------------------------------------------
local function blow()
  error("attempt to perform arithmetic on a secret number value (simulated)", 2)
end

local SECRET_MT = {
  __metatable = "WeaveFakeSecret", -- tag readable via getmetatable(); real mt is protected
  __add = blow, __sub = blow, __mul = blow, __div = blow, __mod = blow,
  __pow = blow, __unm = blow, __concat = blow, __len = blow,
  __eq = blow, __lt = blow, __le = blow,
}

--- Creates a value that behaves like a WoW secret (any operation on it throws).
function M.newFakeSecret()
  return setmetatable({}, SECRET_MT)
end

--- Detector to inject via Weave._setSecretDetector (the wow/ layer will inject the
--- real issecretvalue in M1).
function M.isFakeSecret(v)
  return getmetatable(v) == "WeaveFakeSecret"
end

-- Library files in load order (same order the .toc / embeds.xml will use)
local FILES = {
  "Weave/Weave.lua",
  "Weave/core/Core.lua",
}

--- Loads a FRESH Weave instance (each spec starts from zero, no shared state).
function M.loadWeave()
  local LibStub = newLibStub()
  _G.LibStub = LibStub -- library files resolve it as a global, same as in WoW
  for _, file in ipairs(FILES) do
    local chunk = assert(loadfile(file), "no se pudo cargar " .. file)
    chunk("WeaveTest", {}) -- vararg (addonName, addonTable), as WoW passes it
  end
  return LibStub("Weave-1.0")
end

return M
