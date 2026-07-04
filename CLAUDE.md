# Weave — Claude Code

> Leer **`AGENTS.md`** — fuente de verdad única (reglas, arquitectura, stack, guardrails).
> Las instrucciones globales de `~/.claude/CLAUDE.md` (taint/secret values, vendoring) aplican
> y tienen prioridad. El estándar de proyecto vive en `Workspace/AddonTemplate` (docs 01–05).

## Estado actual (handoff — actualizar al cerrar cada sesión)

- **M4 COMPLETO y VERIFICADO IN-GAME** (2026-07-03): `Weave/ui/Ui.lua` entero —
  `Weave.new` declarativo (props de creación `parent`/`name`/`template`/`size`/
  `point`/`points`/`layer`; registro COMPARTIDO con bind vía `props._get`/
  `_isCallable`: literal una vez, señal/computed bindeada), regiones como
  **descriptors perezosos** (FontString/Texture no pueden nacer sin padre:
  `[Weave.children]` los materializa; con `parent` en props, en el acto),
  `[Weave.on]` scripts, combate = error DURO (no-op prod pendiente de flag),
  scopes ocultan el frame al dispose (`_attachToScope` en el core). La demo es la
  canónica §7 en forma final: UNA descripción, tres pisos, `statusBarTexture` como
  demo de `props.register`. **153 tests en verde, 0 warnings, taintlint limpio**
  (2 INFO SV010 intencionales). Detrás: M3 (store), M2 (ForceTaint), M1 (wow).
  `dev` mergeado a `main`.
- **Hallazgos clave 12.0.7** (verificados in-game, detalle en AGENTS.md §9 y CLAUDE.md
  global): (1) `UnitHealth`/`UnitHealthMax` son secret SIEMPRE en código de addon →
  patrón sink-directo + `isSecret()` → "??". (2) `C_AddOns.IsAddOnLoaded(owner)` es true
  DURANTE la carga del propio addon → con la global nil, vigilar SIEMPRE el ADDON_LOADED
  del dueño y re-adoptar (el fix auto-curativo del store).
- **Siguiente: M5 REDEFINIDO por ADR-0006** (leerlo antes de empezar): la capa `craft/`
  se ELIMINÓ — Craft integrará Weave nativamente (decisión del owner: componentes
  nacidos reactivos, no adaptadores). Weave entrega tres cosas: (1) **paquete
  embebible** — script de build que empaqueta `Weave/` para `Craft/libs/Weave/`
  (modelo Ace3; el .xml ya existe, falta bump de MINOR LibStub y empaquetado),
  (2) **guía de integración** para el autor de componentes (embed toc/xml, patrón
  señal-o-literal con `isCallable`, scopes por ciclo de vida, reglas taint, ejemplos
  Slider/Checkbox/Label), (3) **release v0.1** (tag semver sobre main — absorbe el
  viejo M6 de release). Condición dura: Craft solo embebe builds ETIQUETADOS, jamás
  dev. Cierre: el owner actualiza su primer componente Craft solo con la guía.

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
