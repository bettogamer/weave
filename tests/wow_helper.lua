-- tests/wow_helper.lua — loads Weave WITH the wow/ layer over a MINIMAL frame mock.
-- Only wow/ specs may use this (core/ specs never mock — see CLAUDE.md). The mock
-- implements just the surface the wow/ layer touches: CreateFrame, event
-- registration (plain and unit-filtered) and SetScript("OnEvent"); specs drive the
-- "game" by firing events by hand with fireEvent().

local core = dofile("tests/helper.lua")

local M = {}

-- Re-export the fake-secret toolkit so wow/ specs need a single helper.
M.newFakeSecret = core.newFakeSecret
M.isFakeSecret  = core.isFakeSecret

local frames -- every mock frame created since the last loadWeaveWow()

local function newFrame()
  local f = {
    -- event -> true (RegisterEvent) or { unit1, unit2 } (RegisterUnitEvent)
    _events  = {},
    _scripts = {},
  }
  function f:RegisterEvent(event) self._events[event] = true end
  function f:RegisterUnitEvent(event, unit1, unit2)
    -- same semantics as the client: re-registering REPLACES the unit filter
    self._events[event] = { unit1, unit2 }
  end
  function f:UnregisterEvent(event) self._events[event] = nil end
  function f:SetScript(handler, fn) self._scripts[handler] = fn end
  function f:GetScript(handler) return self._scripts[handler] end
  function f:Hide() end
  function f:Show() end
  return f
end

--- Fires a game event: dispatches to every mock frame registered for it, honoring
--- RegisterUnitEvent filters (for unit events the first vararg is the unit).
function M.fireEvent(event, ...)
  for _, f in ipairs(frames) do
    local reg = f._events[event]
    if reg then
      local deliver = true
      if type(reg) == "table" then -- unit-filtered registration
        local unit = (...)
        deliver = (reg[1] == unit) or (reg[2] == unit)
      end
      local onEvent = deliver and f._scripts.OnEvent
      if onEvent then onEvent(f, event, ...) end
    end
  end
end

-- wow/ layer files in load order (will mirror the .toc)
local WOW_FILES = {
  "Weave/wow/Events.lua",
}

--- Loads a FRESH Weave (core + wow) over the frame mock.
--- `opts.issecretvalue`: value to expose as the _G.issecretvalue client API before
--- loading (absent by default, like a headless/pre-12.0 client).
function M.loadWeaveWow(opts)
  frames = {}
  _G.CreateFrame = function(frameType, name, parent, template)
    local f = newFrame()
    frames[#frames + 1] = f
    return f
  end
  _G.issecretvalue = opts and opts.issecretvalue or nil
  return core.loadWeave(WOW_FILES)
end

return M
