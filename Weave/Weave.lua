-- Weave.lua — entry point. Registers the library in LibStub.
-- Every other file (core/, wow/, store/, ui/, craft/) hangs off this table.

local MAJOR, MINOR = "Weave-1.0", 4 -- MINOR bumps once per tagged release

local Weave = LibStub:NewLibrary(MAJOR, MINOR)
if not Weave then return end -- an equal or newer copy is already loaded

Weave._MAJOR   = MAJOR
Weave._MINOR   = MINOR
Weave._VERSION = "0.3.0" -- semver of the packaged release (single source of truth)
