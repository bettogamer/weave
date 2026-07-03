-- .luacheckrc de Weave (estándar AddonTemplate)
std             = "lua51"
max_line_length = 120
color           = true

globals = {
    -- Solo la capa wow/ puede usar globals de WoW; core/ no debería necesitar NINGUNO.
    "CreateFrame", "UIParent", "GetTime", "InCombatLockdown",
    "C_Timer", "C_AddOns",
    "issecretvalue", "issecrettable",
    "print",
    "LibStub",
    -- APIs del juego usadas por la demo (demo/):
    "UnitHealth", "UnitHealthMax",
    "SLASH_WEAVETAINT1", "SLASH_WEAVEWIDTH1", "SlashCmdList",
}

ignore = {
    "212",   -- unused argument (callbacks OnEvent)
    "213",   -- unused loop variable
}

files = {
    -- Refuerzo de la frontera ADR-0004: core/ sin API de WoW (LibStub no es API del juego).
    ["Weave/core/"] = { globals = { "LibStub" } },
    -- Los specs usan el DSL del mini-runner (tests/run.lua los define como globals).
    ["tests/"] = { globals = { "describe", "it", "assert_eq", "assert_true", "assert_false", "assert_error" } },
}

exclude_files = {
    "related-addons/",
    "docs/",
    "Weave/libs/",   -- código de terceros vendoreado (LibStub): no se lintea ni se toca
}
