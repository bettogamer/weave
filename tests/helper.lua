-- tests/helper.lua — carga Weave como lo haría WoW (vararg por archivo) con un LibStub mínimo.
-- El core es Lua puro (ADR-0004): este helper NO mockea ninguna API de WoW — si algún día
-- un test de core/ lo necesita, el diseño está mal (ver CLAUDE.md).

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

-- Archivos de la lib en orden de carga (el mismo orden que tendrá el .toc / embeds.xml)
local FILES = {
  "Weave/Weave.lua",
  "Weave/core/Core.lua",
}

--- Carga una instancia FRESCA de Weave (cada spec parte de cero, sin estado compartido).
function M.loadWeave()
  local LibStub = newLibStub()
  _G.LibStub = LibStub -- los archivos de la lib lo resuelven como global, igual que en WoW
  for _, file in ipairs(FILES) do
    local chunk = assert(loadfile(file), "no se pudo cargar " .. file)
    chunk("WeaveTest", {}) -- vararg (addonName, addonTable), como WoW
  end
  return LibStub("Weave-1.0")
end

return M
