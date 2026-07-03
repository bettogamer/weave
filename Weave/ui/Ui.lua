-- ui/Ui.lua — Weave.new: declarative frame creation (API-v0 §4). ONE description
-- creates the frame, applies literal props once and binds reactive ones — over
-- the SAME props registry bind uses (a single truth for how props apply).
-- [Weave.children] and [Weave.on] land in M4 block 2.
--
-- HARD combat restriction: creating frames in combat is the classic recipe for
-- catastrophic taint, so Weave.new errors under InCombatLockdown() (v0: always;
-- a production no-op mode awaits a build flag). In combat only binds mutate.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.new then return end -- lib missing or duplicate copy

local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
-- Lua 5.1 in the client; the 5.2+ fallback only exists for the headless runner.
local unpack = unpack or table.unpack -- luacheck: ignore 143

-- Props consumed by the creation step itself (everything else goes to the registry).
local CREATION = {
  parent = true, name = true, template = true,
  size = true, point = true, points = true,
}

function Weave.new(frameType, props)
  if type(frameType) ~= "string" then
    error("Weave.new: expected a frame type (string), got " .. type(frameType), 2)
  end
  if type(props) ~= "table" then
    error("Weave.new: expected a props table, got " .. type(props), 2)
  end
  if InCombatLockdown() then
    error("Weave.new: declarative creation is forbidden in combat — build the UI "
      .. "out of combat; only binds mutate while fighting", 2)
  end

  local frame = CreateFrame(frameType, props.name, props.parent or UIParent, props.template)
  if props.size then frame:SetSize(props.size[1], props.size[2]) end
  if props.point then frame:SetPoint(unpack(props.point)) end
  if props.points then
    for i = 1, #props.points do frame:SetPoint(unpack(props.points[i])) end
  end

  for key, v in pairs(props) do
    if not CREATION[key] then
      local apply = Weave.props._get(key)
      if not apply then
        error(("Weave.new: unknown prop '%s' — add it with Weave.props.register")
          :format(tostring(key)), 2)
      end
      if Weave.props._isCallable(v) then
        Weave.bind(frame, key, v) -- reactive: auto-bound (and scope-attached)
      else
        apply(frame, v) -- literal: applied once
      end
    end
  end

  -- WoW never destroys frames: on scope disposal the frame hides, ready for reuse
  Weave._attachToScope({ dispose = function() frame:Hide() end })
  return frame
end
