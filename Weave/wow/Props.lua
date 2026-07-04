-- wow/Props.lua — the props registry + bind (API-v0 §2): the single source of truth
-- for HOW a reactive value is applied onto an existing frame. bind NEVER creates
-- frames (combat-safe by design, AGENTS.md §5); the ui/ layer (M4) reuses this same
-- registry so literal and bound props apply identically.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.bind then return end -- lib missing or duplicate copy

local registry = {} -- prop name -> apply(frame, value)

Weave.props = {}

function Weave.props.register(name, apply)
  if type(name) ~= "string" then
    error("Weave.props.register: expected a prop name (string), got " .. type(name), 2)
  end
  if type(apply) ~= "function" then
    error("Weave.props.register: expected an apply function, got " .. type(apply), 2)
  end
  registry[name] = apply
end

-- Built-in props (API-v0 §2). Multi-arg props take a table value and unpack it.
Weave.props.register("text",    function(f, v) f:SetText(v) end)
Weave.props.register("value",   function(f, v) f:SetValue(v) end)
Weave.props.register("minMax",  function(f, v) f:SetMinMaxValues(v[1], v[2]) end)
Weave.props.register("shown",   function(f, v) f:SetShown(v) end)
Weave.props.register("alpha",   function(f, v) f:SetAlpha(v) end)
Weave.props.register("width",   function(f, v) f:SetWidth(v) end)
Weave.props.register("height",  function(f, v) f:SetHeight(v) end)
Weave.props.register("texture", function(f, v) f:SetTexture(v) end)
Weave.props.register("vertexColor",    function(f, v) f:SetVertexColor(v[1], v[2], v[3], v[4]) end)
Weave.props.register("statusBarColor", function(f, v) f:SetStatusBarColor(v[1], v[2], v[3], v[4]) end)

-- Signals and computeds are tables made callable via __call; plain functions are
-- accepted too (they read their signals inside, tracking works the same).
local function isCallable(v)
  if type(v) == "function" then return true end
  local mt = getmetatable(v)
  return type(mt) == "table" and mt.__call ~= nil
end

-- Internal (ui layer): registry lookup and the callable test keep ONE definition.
Weave.props._get = function(name) return registry[name] end
Weave.props._isCallable = isCallable

function Weave.bind(frame, prop, source)
  if type(frame) ~= "table" then
    error("Weave.bind: expected a frame (table), got " .. type(frame), 2)
  end
  if type(prop) ~= "string" then
    error("Weave.bind: prop must be a string, got " .. type(prop), 2)
  end
  local apply = registry[prop]
  if not apply then
    error(("Weave.bind: unknown prop '%s' — add it with Weave.props.register"):format(prop), 2)
  end
  if not isCallable(source) then
    error("Weave.bind: source must be callable (a signal, computed or function), got " .. type(source), 2)
  end
  return Weave.effect(function()
    apply(frame, source())
  end)
end
