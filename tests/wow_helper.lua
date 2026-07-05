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

local function newFrame(frameType, name, parent, template)
  local f = {
    -- creation args, recorded for the Weave.new specs
    _type = frameType, _name = name, _parent = parent, _template = template,
    -- event -> true (RegisterEvent) or { unit1, unit2 } (RegisterUnitEvent)
    _events  = {},
    _scripts = {},
    _points  = {}, -- every SetPoint call, in order
    _shown   = true,
  }
  function f:RegisterEvent(event) self._events[event] = true end
  function f:RegisterUnitEvent(event, unit1, unit2)
    -- same semantics as the client: re-registering REPLACES the unit filter
    self._events[event] = { unit1, unit2 }
  end
  function f:UnregisterEvent(event) self._events[event] = nil end
  function f:SetScript(handler, fn) self._scripts[handler] = fn end
  function f:GetScript(handler) return self._scripts[handler] end
  function f:Hide() self._shown = false end
  function f:Show() self._shown = true end
  function f:IsShown() return self._shown end
  function f:SetParent(p) self._parent = p end
  function f:GetParent() return self._parent end
  function f:SetSize(w, h) self._size = { w, h } end
  function f:SetPoint(...) self._points[#self._points + 1] = { ... } end
  function f:ClearAllPoints() self._points = {} end
  -- Regions: created THROUGH their parent, like the real client (f._regions
  -- records them in creation order; they reuse the same mock surface).
  f._regions = {}
  local function newRegion(regionType, name, layer, template)
    local r = newFrame(regionType, name, f, template)
    r._layer = layer
    f._regions[#f._regions + 1] = r
    return r
  end
  function f:CreateFontString(name, layer, template)
    return newRegion("FontString", name, layer, template)
  end
  function f:CreateTexture(name, layer, template)
    return newRegion("Texture", name, layer, template)
  end
  -- Prop setters: they only RECORD what was applied (specs read f._set.<prop>);
  -- the mock asserts nothing about rendering, just that the right call happened.
  f._set = {}
  function f:SetText(v)  self._set.text  = v end
  function f:SetValue(v) self._set.value = v end
  function f:SetMinMaxValues(min, max) self._set.minMax = { min, max } end
  function f:SetShown(v) self._set.shown = v end
  function f:SetAlpha(v) self._set.alpha = v end
  function f:SetWidth(v)  self._set.width  = v end
  function f:SetHeight(v) self._set.height = v end
  function f:SetTexture(v) self._set.texture = v end
  function f:SetVertexColor(r, g, b, a) self._set.vertexColor = { r, g, b, a } end
  function f:SetStatusBarColor(r, g, b, a) self._set.statusBarColor = { r, g, b, a } end
  return f
end

--- Creates a standalone mock frame for bind() specs (not registered for events).
function M.newMockFrame()
  return newFrame()
end

--- How many frames the library has created so far (bind must NEVER create frames).
function M.frameCount()
  return #frames
end

--- Runs fn with print muted: for specs that TRIGGER degradation warnings but do
--- not assert them (keeps the runner output clean). Errors propagate intact.
function M.silently(fn)
  local realPrint = print
  _G.print = function() end
  local ok, err = pcall(fn)
  _G.print = realPrint
  if not ok then error(err, 0) end
end

local now -- fake clock, reset by loadWeaveWow()

--- Advances the fake clock and fires every OnUpdate script once, with `dt` as the
--- elapsed seconds (one advanceTime call = one rendered frame of `dt` seconds).
function M.advanceTime(dt)
  now = now + dt
  for _, f in ipairs(frames) do
    local onUpdate = f._scripts.OnUpdate
    if onUpdate then onUpdate(f, dt) end
  end
end

local inCombat = false

--- Toggles the fake InCombatLockdown() state (reset to false by loadWeaveWow()).
function M.setInCombat(v)
  inCombat = v and true or false
end

local addonsLoaded -- set of addon names already "loaded", reset by loadWeaveWow()

--- Marks an addon as already loaded WITHOUT firing ADDON_LOADED (for specs where
--- the store is created after its owner finished loading).
function M.setAddOnLoaded(name)
  addonsLoaded[name] = true
end

--- Fires a game event: dispatches to every mock frame registered for it, honoring
--- RegisterUnitEvent filters (for unit events the first vararg is the unit).
--- ADDON_LOADED also marks that addon as loaded, like the real client.
function M.fireEvent(event, ...)
  if event == "ADDON_LOADED" then
    addonsLoaded[(...)] = true
  end
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
  "Weave/wow/Props.lua",
  "Weave/wow/Ticker.lua",
  "Weave/store/Store.lua",
  "Weave/ui/Ui.lua",
  "Weave/ui/Each.lua",
}

--- Loads a FRESH Weave (core + wow) over the frame mock.
--- `opts.issecretvalue`: value to expose as the _G.issecretvalue client API before
--- loading (absent by default, like a headless/pre-12.0 client).
function M.loadWeaveWow(opts)
  frames = {}
  _G.CreateFrame = function(frameType, name, parent, template)
    local f = newFrame(frameType, name, parent, template)
    frames[#frames + 1] = f
    return f
  end
  _G.UIParent = newFrame("Frame", "UIParent") -- not counted in frameCount()
  inCombat = false
  _G.InCombatLockdown = function() return inCombat end
  _G.issecretvalue = opts and opts.issecretvalue or nil
  now = 1000 -- arbitrary non-zero start, so specs can't rely on time starting at 0
  _G.GetTime = function() return now end
  addonsLoaded = {}
  _G.C_AddOns = {
    IsAddOnLoaded = function(name) return addonsLoaded[name] == true end,
  }
  return core.loadWeave(WOW_FILES)
end

return M
