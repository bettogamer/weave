-- ui/Ui.lua — Weave.new: declarative frame creation (API-v0 §4). ONE description
-- creates the frame, applies literal props once and binds reactive ones — over
-- the SAME props registry bind uses (a single truth for how props apply).
--
-- Regions (FontString/Texture) can only be created THROUGH a parent, but in the
-- declarative syntax the child is written before its parent exists: a region
-- Weave.new without `parent` returns a LAZY DESCRIPTOR that [Weave.children]
-- materializes; with `parent` in props it is created on the spot.
--
-- HARD combat restriction: creating frames in combat is the classic recipe for
-- catastrophic taint, so Weave.new errors under InCombatLockdown() (v0: always;
-- a production no-op mode awaits a build flag). In combat only binds mutate.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.new then return end -- lib missing or duplicate copy

local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
-- Lua 5.1 in the client; the 5.2+ fallback only exists for the headless runner.
local unpack = unpack or table.unpack -- luacheck: ignore 143

-- Sentinel keys (unique tables — their identity matters, their content doesn't).
Weave.children = {}
Weave.on       = {}

-- Region types and the parent method that creates each.
local REGION = { FontString = "CreateFontString", Texture = "CreateTexture" }

-- Props consumed by the creation step itself (everything else goes to the registry).
local CREATION = {
  parent = true, name = true, template = true,
  size = true, point = true, points = true,
  layer = true, -- regions only; harmless to reserve for frames too
}

local COMBAT_MSG = "Weave.new: declarative creation is forbidden in combat — build "
  .. "the UI out of combat; only binds mutate while fighting"

local function applyLayout(target, props)
  if props.size then target:SetSize(props.size[1], props.size[2]) end
  if props.point then target:SetPoint(unpack(props.point)) end
  if props.points then
    for i = 1, #props.points do target:SetPoint(unpack(props.points[i])) end
  end
end

-- Registry props: a literal applies once, a callable (signal/computed) binds.
local function applyProps(target, props)
  for key, v in pairs(props) do
    if not CREATION[key] and key ~= Weave.children and key ~= Weave.on then
      local apply = Weave.props._get(key)
      if not apply then
        error(("Weave.new: unknown prop '%s' — add it with Weave.props.register")
          :format(tostring(key)), 2)
      end
      if Weave.props._isCallable(v) then
        Weave.bind(target, key, v) -- reactive: auto-bound (and scope-attached)
      else
        apply(target, v) -- literal: applied once
      end
    end
  end
end

local function materializeRegion(parent, regionType, props)
  local region = parent[REGION[regionType]](parent, props.name, props.layer, props.template)
  applyLayout(region, props)
  applyProps(region, props)
  return region
end

function Weave.new(frameType, props)
  if type(frameType) ~= "string" then
    error("Weave.new: expected a frame type (string), got " .. type(frameType), 2)
  end
  if type(props) ~= "table" then
    error("Weave.new: expected a props table, got " .. type(props), 2)
  end

  if REGION[frameType] then
    if props.parent ~= nil then
      if InCombatLockdown() then error(COMBAT_MSG, 2) end
      return materializeRegion(props.parent, frameType, props)
    end
    -- No parent yet: a lazy descriptor for [Weave.children] to materialize.
    return { _weaveRegion = frameType, _props = props }
  end

  if InCombatLockdown() then error(COMBAT_MSG, 2) end

  local frame = CreateFrame(frameType, props.name, props.parent or UIParent, props.template)
  applyLayout(frame, props)
  applyProps(frame, props)

  local scripts = props[Weave.on]
  if scripts ~= nil then
    if type(scripts) ~= "table" then
      error("Weave.new: [Weave.on] must be a table of scripts", 2)
    end
    for name, fn in pairs(scripts) do
      if type(fn) ~= "function" then
        error(("Weave.new: [Weave.on].%s must be a function, got %s")
          :format(tostring(name), type(fn)), 2)
      end
      frame:SetScript(name, fn)
    end
  end

  local children = props[Weave.children]
  if children ~= nil then
    if type(children) ~= "table" then
      error("Weave.new: [Weave.children] must be an array", 2)
    end
    for i = 1, #children do
      local child = children[i]
      if type(child) == "table" and child._weaveRegion then
        materializeRegion(frame, child._weaveRegion, child._props)
      elseif type(child) == "table" and child._weaveEach then
        Weave._materializeEach(frame, child) -- reactive list (ui/Each.lua)
      elseif type(child) == "table" and child._weaveVirtual then
        Weave._materializeVirtual(frame, child) -- virtualized grid (ui/Virtual.lua)
      elseif type(child) == "table" and child.SetParent then
        child:SetParent(frame) -- an already-created frame joins the tree
      else
        error(("Weave.new: [Weave.children][%d] is neither a Weave region descriptor "
          .. "nor a frame"):format(i), 2)
      end
    end
  end

  -- WoW never destroys frames: on scope disposal the frame hides, ready for reuse
  Weave._attachToScope({ dispose = function() frame:Hide() end })
  return frame
end
