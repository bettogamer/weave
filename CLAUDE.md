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
- **M8 EN CURSO — animaciones `Weave.tween`** (ADR-0008, tween-first, release v0.4.0 pendiente).
  **Consumidor real: Craft** (select/modal/collapse — el owner quiere animarlos sobre Weave).
  Hecho y VERDE headless (218 tests, luacheck 0/0, taintlint 0/0/0):
  - **Bloque 1** (`57b6c65`): `core/Tween.lua` — motor puro `Weave._tweenEngine(from,to,duration,
    easing)` con `anim:at(elapsed)→value,done`; número o array (lerp por elemento, tabla-resultado
    reutilizada = cero allocations/frame). `Weave.easing` = linear/inQuad/outQuad/inOutQuad. 13 tests.
  - **Bloque 2** (`acb8fe3`): `wow/Anim.lua` — `Weave.tween(target,opts)` reactivo read-only.
    Driver único compartido (un frame OnUpdate, se oculta al vaciarse → coste cero en reposo).
    Siembra en el valor actual, re-targeting desde el valor actual, `t:animating()` reactivo
    (coordina entrada/salida: `shown = abierto or t:animating()`), degradación por secret,
    disposal por scope. Solo muta → combat-safe. Default easing `outQuad`. 13 tests.
- **M8 bloque 3 HECHO — demo verificada in-game** (2026-07-06): `demo/WeaveDemo/TweenDemo.lua`
  (`/weavetween`) — panel modal/collapse (fade alpha + expand height, salida que se oculta vía
  `shown = abierto or alpha:animating()`) + barra que desliza value/color (array tween). Gates
  verdes (luacheck 0/0, taintlint 0/0). **Hallazgo (quirk de render de WoW, NO bug de Weave)**:
  animar la ALTURA de un frame a **0 exacto** y volver a crecer no repinta la geometría en el
  2º+ ciclo (1er ciclo va; síntoma según lo demás: con clipsChildren "no se ve", sin él "no
  anima el expand"). `Hide/Show` sí funciona; `clipsChildren` era falso culpable. Verificado 3×
  que Weave entrega valores correctos siempre (headless, repro semántica in-game, y `GetAlpha`/
  `GetHeight` in-game). **Fix del patrón**: visibilidad total por fade de alpha; geometría
  colapsa a un mínimo NO-cero (nunca 0). Detalle en AGENTS.md §9.
- **Fix real en `wow/Anim.lua` (2026-07-06)**: re-entrancy en `onTick` — desregistrar el tween
  ANTES de disparar `_current:set`/`_animating:set` (que corren effects síncronos); si uno
  re-apunta el mismo tween en el instante en que termina (ping-pong / auto-reverse), `arm` lo
  ve inactivo y lo re-engancha limpio en vez de dejarlo animando-pero-congelado. Test de
  ping-pong en `tests/wow/anim_spec.lua`; 219 tests verde. Encontrado auditando a raíz de
  "¿falta algo en anim?". (`Weave.spring` sigue reservado por diseño, ADR-0008 — no es un hueco.)
- **CRAFT-INTEGRATION §4.6 HECHA** (2026-07-06): patrón tween para Craft (modal/collapse con
  `shown = abierto or t:animating()`, array tween para color) + el caveat del `height→0`.
- **M8 CERRADO + RELEASE v0.4.0 HECHO** (2026-07-06): tag `v0.4.0` sobre main (commit
  `14197f0`), LibStub MINOR 5, changelog §10 v0.13. `main` == `dev`, árbol limpio, 219 tests verde.
- **M9 IMPLEMENTADO — `Weave.fromPromise` (puente con Loom)** (2026-07-07, ADR-0009). Loom
  (`Workspace/loom`, v0.1.0, verificada in-game) cubre "datos que llegan tarde" (item/spell/inspect:
  request→evento→resolve). Por su **ADR-0010** el puente promesa→señal lo posee **Weave** (Loom no
  conoce a Weave — paralelo exacto de nuestro ADR-0006 Craft↔Weave). Entregado (B1-B4, headless verde
  + demo montada):
  - `Weave/wow/Promise.lua` (~45 líneas): `Weave.pending`/`Weave.rejected` (centinelas tabla) +
    `Weave.fromPromise(promise, opts)` = gemelo **one-shot** de `fromEvent`. Señal interna writable +
    handle `computed` **read-only** (el valor lo posee la promesa). Usa SOLO la API pública de la
    promesa (`:next`/`:cancel`), nunca internos `_`. Decisiones del owner: (a) centinela
    `Weave.pending`; (b) rechazo → `Weave.rejected` + `opts.onError(reason)` opcional; (c)
    `scope:dispose()` → `promise:cancel()` (cero leak, cascada estructural Loom ADR-0011).
  - Degradación por secret vía el `fallback` del signal interno (mismo camino que `fromEvent`).
  - `tests/wow/promise_spec.lua`: **15 tests** con promesa falsa = contrato público (NO mock de WoW).
  - Docs: ADR-0009, API-v0 §2 (spec + §8 matiz "nunca *implementar* async" + §9 fila M9). Registrado
    en `Weave.xml` + `wow_helper.lua`.
  - **Demo `/weavepromise`** (`demo/WeaveDemo/PromiseDemo.lua`): carga item con Loom.item → fromPromise
    → panel skeleton→valor→rechazo; cada carga en su scope (dispose cancela la anterior). **Loom v0.1.0
    vendoreado READ-ONLY** en `demo/WeaveDemo/libs/Loom/` (sin su libs/; LibStub lo da Weave; nota en
    `VENDORED.md`). `.luacheckrc`: `SLASH_WEAVEPROMISE1` + exclude `demo/WeaveDemo/libs/`.
  - Gates verdes: suite **234** (+15), luacheck 0/0 (13 files), taintlint 0 err/0 warn (4 INFO benignos:
    2 SV010 pre-exist. Demo.lua + 2 SV011 del Loom vendoreado — guarda con `and`, correcto).
  - **VERIFICADO IN-GAME** por el owner (2026-07-07): `/weavepromise` OK (skeleton→item, `bad`→rejected).
    El puente Loom→Weave funciona end-to-end sobre la API pública de la promesa (validación del ADR-0009).
  - **RELEASE v0.5.0 HECHO** (2026-07-07): bump `.toc` Version + `Weave.lua` LibStub MINOR 6 + `_VERSION`,
    fila changelog §10 v0.14, commits (feat wow + feat demo + chore release), `dev` mergeado a `main`,
    tag `v0.5.0` sobre main. **`git push` lo hace el owner a mano** (regla del repo; Claude no pushea).
- **Pendientes de fondo** (post-M8): (1) ~~verificación in-game de MiOro (M7)~~ ✓ verificado
  in-game por el owner 2026-07-06 (oro con iconos + update reactivo al vender/comprar).
  (2) evaluar **nivel L** (idioma de commits ya decidido: inglés desde 2026-07-06). (3) avisar a
  Coffer/Craft: **v0.3.0 lista para vendorear** (build con scripts/build-embed.ps1); al
  re-vendorear, que `Craft.Reactive.isCallable`/`isWritableSignal` deleguen en los predicados.
- **Pendientes de fondo** (post-M8): (1) ~~verificación in-game de MiOro (M7)~~ ✓ verificado
  in-game por el owner 2026-07-06 (oro con iconos + update reactivo al vender/comprar).
  (2) evaluar **nivel L** (idioma de commits ya decidido: inglés desde 2026-07-06). (3) avisar a
  Coffer/Craft: **v0.3.0 lista para vendorear** (build con scripts/build-embed.ps1); al
  re-vendorear, que `Craft.Reactive.isCallable`/`isWritableSignal` deleguen en los predicados.

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

luacheck Weave/Weave.lua Weave/core/Core.lua Weave/core/Reconcile.lua Weave/core/Tween.lua Weave/wow/Events.lua Weave/wow/Props.lua Weave/wow/Ticker.lua Weave/wow/Anim.lua Weave/store/Store.lua Weave/ui/Ui.lua Weave/ui/Each.lua --config .luacheckrc
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
- Mensajes: **Conventional Commits en inglés**, descriptivos (decidido 2026-07-06 —
  como taintlint). Los commits previos en español se dejan como están: NO reescribir historia.
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
