# Weave — Claude Code

> Leer **`AGENTS.md`** — fuente de verdad única (reglas, arquitectura, stack, guardrails).
> Las instrucciones globales de `~/.claude/CLAUDE.md` (taint/secret values, vendoring) aplican
> y tienen prioridad. El estándar de proyecto vive en `Workspace/AddonTemplate` (docs 01–05).

## Estado actual (handoff — actualizar al cerrar cada sesión)

- **M0 COMPLETO** (2026-07-03): `Weave/core/Core.lua` entero — signal, computed (lazy,
  cache, corte por igualdad, diamante sin glitches), effect, batch, scope, y semántica
  taint (fallback declarado, `isSecret()`, degradación de computeds, detector inyectable
  `_setSecretDetector`). **49 tests en verde, 0 warnings.** `dev` mergeado a `main`.
- **Siguiente: M1 — capa `Weave/wow/`**: `fromEvent`/`fromUnitEvent`, `bind` + registro de
  props, `onUpdate`, chokepoint de errores en effects, e inyectar `issecretvalue` real al
  detector. Cierre del hito: la demo canónica (API-v0 §7, versión mínima) corriendo
  in-game con `/reload` — el testing headless de wow/ usa mock mínimo de frames (los tests
  de core/ JAMÁS mockean, ver abajo).
- Leer antes de empezar M1: `docs/API-v0.md` §2 (la superficie a implementar) y
  `tests/core/taint_spec.lua` (cómo se simulan secrets headless).

## Cómo se trabaja en este proyecto (acordado con el owner — NO saltárselo)

1. **Por bloques con checkpoint**: anunciar el plan del turno antes de ejecutar; al final
   de cada bloque, resumen y pausa.
2. **TDD con aprobación**: los tests de cada bloque se presentan al owner y se espera su
   OK ANTES de implementar. Los specs se escriben contra `docs/API-v0.md`.
3. **Las decisiones de identidad/alcance/gusto son del owner** (nombres, licencias, qué
   features entran): presentar opciones con recomendación (AskUserQuestion), nunca
   plasmarlas en archivos sin preguntar.
4. **El owner es dev novato y está aprendiendo del proceso**: explicar los conceptos con
   analogías (signal=celda de Excel, computed=fórmula, bind=gráfico enchufado), en
   español, sin jerga sin explicar. El valor para él está en participar, no solo en el
   resultado.
5. Cambios de decisión de fondo → ADR nuevo + AGENTS.md en el mismo commit.

## Comandos reales de esta máquina

```bash
lua tests/run.lua tests/core/signal_spec.lua tests/core/computed_spec.lua tests/core/scope_spec.lua tests/core/taint_spec.lua
# ↑ suite completa (mini-runner propio: busted NO instala aquí — falta compilador C; busted queda para CI Linux)

luacheck Weave/Weave.lua Weave/core/Core.lua --config .luacheckrc
# ↑ luacheck 1.2.0 instalado, pero NO puede escanear carpetas en esta máquina (sin lfs): pasar archivos explícitos

luac -p <archivo>   # el lua local es 5.4: sirve para sintaxis, pero el target es 5.1 (luacheck std lua51 vigila)
```

## Git — reglas para Claude Code en este repo

- **Identidad local del repo**: `Betto <betto.gamer@icloud.com>` (ya configurada, local).
- **NUNCA colocar trailers de co-autoría de IA** en los commits: nada de
  `Co-Authored-By: Claude ...` ni atribuciones de herramientas ("Generated with...").
  Mensajes limpios, como si los hubiera escrito el owner. (Regla heredada de taintlint.)
- Mensajes: **Conventional Commits en español**, descriptivos. Al publicarse el repo
  (nivel L), evaluar cambiar a inglés como taintlint.
- **`main` SIEMPRE verde**; trabajo en `dev` (o ramas cortas → dev); merge a main solo en
  hitos completos. **Releases = tags semver `v*`** sobre main.
- **MUST NOT `git push`** — lo hace el owner a mano. Commit/branch solo si el usuario lo pide.

## Convenciones (recordatorio operativo)

- **Comentarios in-code, identificadores Y mensajes de error de la API: SIEMPRE en inglés.**
  En español: docs/, ADRs, descripciones `it("...")` de los tests y la conversación.
- La frontera core/wow es sagrada: si un test de `core/` necesita un mock de WoW, el diseño
  está mal — parar y revisar, no mockear. (`.luacheckrc` refuerza: core/ solo ve LibStub.)
- Fusion es referencia de diseño, no de código: es Luau (tipos, `table.freeze`,
  `task.defer`); nada de asumir que sus técnicas compilan en Lua 5.1.
- Backlog de ideas futuras (Craft reactivo, animaciones, kit de testing): `docs/BACKLOG.md`
  — capturar allí, no diseñar en caliente.
