-- Weave.lua — entry point. Registra la librería en LibStub.
-- El resto de archivos (core/, wow/, store/, ui/, craft/) se cuelgan de esta tabla.

local MAJOR, MINOR = "Weave-1.0", 1

local Weave = LibStub:NewLibrary(MAJOR, MINOR)
if not Weave then return end -- ya hay una copia igual o más nueva cargada

Weave._MAJOR = MAJOR
Weave._MINOR = MINOR
