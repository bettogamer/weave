# Weave — Claude Code

> Leer **`AGENTS.md`** — fuente de verdad única (reglas, arquitectura, stack, guardrails).
> Las instrucciones globales de `~/.claude/CLAUDE.md` (taint/secret values, vendoring) aplican
> y tienen prioridad. El estándar de proyecto vive en `Workspace/AddonTemplate` (docs 01–05).

## Estado actual (handoff — actualizar al cerrar cada sesión)

- **M2 COMPLETO y VERIFICADO IN-GAME** (2026-07-03): taint end-to-end. Guard de secrets
  en los maps de eventos (tercer y último punto de entrada de código de usuario;
  `Weave._isSecretError` compartido core→wow) + `/weavetaint` (`demo/WeaveDemo/
  TaintTest.lua`): pipeline completo construido dentro de `loadstring` bajo
  ForceTaint_Strong con secrets REALES — barra pintando vida real, texto "?? (taint)",
  guards avisando una vez por sitio, CERO popups. **97 tests en verde, 0 warnings,
  taintlint limpio** (los 2 INFO SV010 de la demo son intencionales: propagación
  deliberada al sink). M1 detrás: capa `wow/` entera + Weave standalone + demo +
  deploy-local. `dev` mergeado a `main`.
- **Hallazgo clave 12.0.7** (verificado in-game): `UnitHealth`/`UnitHealthMax` devuelven
  secret SIEMPRE en código de addon → un fallback numérico da "0%" permanente. Patrón:
  señal SIN fallback → secret directo a los sinks (`SetValue`/`SetMinMaxValues` los
  aceptan); texto/color con `isSecret()` → "??". Ver AGENTS.md §9 y CLAUDE.md global.
- **Siguiente: M3 — `Weave/store/`** (leer API-v0 §5 antes de proponer bloques):
  SavedVariables reactivas — hidratación en `ADDON_LOADED` del addon dueño (llamable
  antes: defaults y re-sync al hidratar), defaults sin pisar lo guardado, claves
  desconocidas se preservan (datos del usuario intocables), sub-stores anidados,
  `version`/`migrate`, `_raw`. Testing headless: SV simulada como global fake +
  disparar `ADDON_LOADED` con el mock de eventos de `tests/wow_helper.lua`.

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

node c:/Users/Usuario/Documents/Workspace/taintlint/dist/cli.js Weave/Weave.toc
node c:/Users/Usuario/Documents/Workspace/taintlint/dist/cli.js demo/WeaveDemo/WeaveDemo.toc
# ↑ taintlint local (Node 24 LTS instalado 2026-07-03 vía winget; en shells abiertas antes de esa
#   fecha usar la ruta completa "C:\Program Files\nodejs\node.exe"). Pasa por .toc, no por carpeta.

powershell -File scripts/deploy-local.ps1   # copia Weave + WeaveDemo a F:\Games\...\AddOns → /reload
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
