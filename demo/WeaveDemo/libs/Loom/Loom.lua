-- Loom.lua — entry point. Registers the library in LibStub.
-- Every other file (core/, wow/) hangs off this table via LibStub("Loom-1.0").

local MAJOR, MINOR = "Loom-1.0", 1 -- MINOR bumps once per tagged release

local Loom = LibStub:NewLibrary(MAJOR, MINOR)
if not Loom then return end -- an equal or newer copy is already loaded

Loom._MAJOR   = MAJOR
Loom._MINOR   = MINOR
Loom._VERSION = "0.1.0" -- semver of the packaged release (single source of truth)
