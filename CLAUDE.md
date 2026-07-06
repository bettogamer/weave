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
- **M5 COMPLETO + RELEASE v0.1.0** (2026-07-03, ADR-0006): la capa `craft/` se eliminó
  del alcance — Craft integrará Weave nativamente. Entregado: `scripts/build-embed.ps1`
  (empaqueta `dist/Weave-vX.Y.Z/` con gates de suite+luacheck), `docs/
  CRAFT-INTEGRATION.md` (inglés: embed, applyOrBind señal-o-literal, scope por
  instancia, two-way sin bucles, taint, upgrade) y **tag `v0.1.0`** sobre main
  (LibStub MINOR 2). El trabajo de integración en los componentes es del owner, EN el
  repo de Craft, sobre el build etiquetado — validación del ADR: que lo logre solo
  con la guía (si algo no encaja con la API real de Craft, ajustar la guía aquí).
- **M6 COMPLETO + RELEASE v0.2.0** (2026-07-05, ADR-0007): `Weave.each` adelantado de
  v1 por demanda real (Coffer en diseño + Craft: options literal-only, DragList sin
  migrar). Entregado: `core/Reconcile.lua` (reconciliador puro por keys: el frame viaja
  con la key, las filas liberadas se reciclan antes de crear) + `ui/Each.lua` (render
  UNA vez por fila, datos por señales item/index, keying `opts.key` con degradación de
  key secreta a índice, pila vertical/`layout=false`, combate solo-recicla + catch-up
  en PLAYER_REGEN_ENABLED, `opts.warm`). 180 tests, demo `/weavelist` VERIFICADA
  IN-GAME (pooling, keying con marca que viaja, secrets "??", overflow en combate).
  CRAFT-INTEGRATION §4.5 (patrón para options/DragList). Diseño validado con scouts:
  notas de Craft + patrón List.lua de Sorted + Fusion ForValues como referencia.
- **FR Craft + RELEASE v0.3.0** (2026-07-05, sin ADR — aditivo): predicados públicos
  `Weave.isReactive(v)` / `Weave.isWritable(v)` (core) para consumidores que aceptan
  "señal-o-literal", pedidos por Craft (ADR-0013 oleada 3). Semántica estructural (no por
  identidad de metatabla); `Weave.props._isCallable` delega en `Weave.isReactive` (una
  sola definición). Docs: API-v0 §1 + CRAFT-INTEGRATION §4.1/§4.3/§6. 12 tests nuevos
  (`tests/core/predicates_spec.lua`), suite 192 verde, luacheck limpio, taintlint 0/0/0.
  Tag `v0.3.0` sobre main (LibStub MINOR 4). FR cerrado en BACKLOG.
- **M7 COMPLETO — docs para devs nuevos** (2026-07-05, sin ADR — solo docs): entregados
  `docs/TUTORIAL.md` ("tu primer addon reactivo": contador de oro, tres pisos estado→
  derivación→vista con analogía de Excel, ~15 líneas, gentil — sin secret values) y
  **README** reescrito a la realidad v0.3.0 (estado IMPLEMENTADO, quickstart real, tabla de
  capas, enlaces a tutorial/API/demos, ADRs 0001–0007). El tutorial se materializó como addon
  ejecutable `demo/MiOro/` (comentarios in-code en inglés; la versión en español vive en el
  doc) y se añadió a `deploy-local.ps1`. Gates en verde: suite **192**, luacheck 0/0 (`.luacheckrc`
  ganó `GetMoney`/`GetCoinTextureString`), taintlint MiOro **0/0/0** — la db 12.0.7 NO marca
  `GetMoney` como secret (a diferencia de `UnitHealth`): evidencia de que el ejemplo es correcto.
  **PENDIENTE (owner)**: verificación in-game de `/MiOro` con deploy+/reload (debe verse el oro
  con iconos de moneda; si saliera "??", el oro sería secret y habría que replantear el ejemplo).
  Toolchain de gates instalada en macOS este día (luacheck vía brew, taintlint clonado+buildeado).
- **CI AÑADIDO** (2026-07-05): `.github/workflows/ci.yml` — dos jobs en push a main/dev y en
  PR. Job `lua`: setup Lua **5.1** (target real; las locales corren 5.4/5.5) + luacheck vía
  luarocks → suite (mini-runner, sale !=0 si falla) + luacheck de lib y demo. Job `taintlint`:
  clona+buildea github.com/bettogamer/taintlint y lo corre sobre los 3 .toc (sale !=0 solo ante
  `error`; los 2 INFO SV010 pasan). **Verde en Actions** (validado 2026-07-05 tras el primer
  push del owner): ambos jobs pasan — suite en Lua 5.1 real, luacheck y taintlint limpios.
- **Siguiente**: (1) **animaciones** (acordado 2026-07-05, decisión del owner): empezar por
  `tween` (determinista/testeable) con la base preparada para `spring` (owner quiere ambos, pero
  por el camino seguro — evitar sobre-diseño sin consumidor real; backlog §"Ideas futuras");
  probablemente ADR (adelanta v3+, como each con ADR-0007). (2) evaluar **nivel L** y **idioma de
  commits** a inglés. Avisar a Coffer/Craft: **v0.3.0 lista para vendorear** (build con
  scripts/build-embed.ps1); al re-vendorear, que `Craft.Reactive.isCallable`/`isWritableSignal`
  deleguen en los predicados públicos.

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

> Dos máquinas en juego. **macOS (este repo, `/Users/beto/Workspace/...`)**: toolchain de
> gates completo (suite + luacheck + taintlint) — instalado 2026-07-05. **Windows
> (`c:/Users/Usuario/...`)**: donde corre WoW → deploy + prueba in-game (`deploy-local.ps1`
> es PowerShell y apunta a `F:\Games\...`). Los globs los expande Bash; en PowerShell enumerar.

```bash
# --- macOS (gates locales) ---
lua tests/run.lua tests/core/*_spec.lua tests/wow/*_spec.lua tests/store/*_spec.lua tests/ui/*_spec.lua
# ↑ suite completa, 192 tests (mini-runner propio: busted NO instala aquí — falta compilador C; busted
#   queda para CI Linux). El lua local es 5.5; el target es 5.1 (luacheck std lua51 vigila).

luacheck Weave/Weave.lua Weave/core/Core.lua Weave/core/Reconcile.lua Weave/wow/Events.lua Weave/wow/Props.lua Weave/wow/Ticker.lua Weave/store/Store.lua Weave/ui/Ui.lua Weave/ui/Each.lua --config .luacheckrc
# ↑ luacheck 1.2.0 (brew install luacheck). NO escanea carpetas (sin lfs): pasar archivos explícitos.
#   Los .lua de demo/ (MiOro, WeaveDemo) se lintean aparte cuando cambian.

node /Users/beto/Workspace/taintlint/dist/cli.js Weave/Weave.toc
node /Users/beto/Workspace/taintlint/dist/cli.js demo/WeaveDemo/WeaveDemo.toc
node /Users/beto/Workspace/taintlint/dist/cli.js demo/MiOro/MiOro.toc
# ↑ taintlint 0.2.0 clonado de github.com/bettogamer/taintlint a ~/Workspace/taintlint y buildeado
#   (npm install && npm run build → dist/cli.js). Pasa por .toc, no por carpeta. En Windows la ruta
#   es c:/Users/Usuario/Documents/Workspace/taintlint/dist/cli.js.

# --- Windows (deploy + in-game) ---
powershell -File scripts/deploy-local.ps1   # copia Weave + WeaveDemo + MiOro a F:\Games\...\AddOns → /reload
```

## Subagentes del proyecto (`.claude/agents/`)

- **addon-scout** (Sonnet, read-only) — localizar código/patrones, investigar API WoW 12.0.7.
- **error-triager** (Sonnet, read-only) — diagnosticar errores Lua de BugSack (sabe que un
  popup de secret = guard que falta, y que API de WoW en core/ es bug de frontera).
- Política de modelos: lectura/diagnóstico → Sonnet; escritura sensible → agente principal
  (AddonTemplate/docs/04). Copiados del estándar 2026-07-03 (retro de M5).

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
