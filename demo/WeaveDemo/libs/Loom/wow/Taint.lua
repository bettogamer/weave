-- Taint.lua — injects the REAL secret detector into the pure core. The core can't call
-- issecretvalue itself (it's Lua-pure, ADR-0003); the wow/ layer wires the client API here.
-- Covers both secret VALUES (issecretvalue) and secret TABLES (issecrettable, e.g. inspect /
-- aura data). Shim: on pre-12.0 clients these globals are absent → the detector reports false
-- (nothing is secret, safe default). ADR-0004 / API-v0 §3.

local Loom = LibStub("Loom-1.0")

local issecretvalue = issecretvalue -- captured at load; may be nil on old clients
local issecrettable = issecrettable

Loom._setSecretDetector(function(v)
  if issecretvalue and issecretvalue(v) then return true end
  if issecrettable and issecrettable(v) then return true end
  return false
end)
