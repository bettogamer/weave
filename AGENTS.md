# AGENTS.md — Weave

> README ejecutable para agentes de IA. Fuente de verdad única: si cambia una decisión,
> este archivo y el ADR correspondiente se actualizan en el mismo commit.
>
> **Estado del proyecto: IMPLEMENTACIÓN.** **M4 COMPLETO**: `ui/` entero (`Weave.new`
> declarativo: props de creación, registro compartido con bind, descriptors perezosos
> de regiones, `[Weave.children]`/`[Weave.on]`, restricción dura de combate, scopes) —
> la demo canónica §7 verificada in-game en su forma final (una sola descripción, tres
> pisos, /weavetaint intacto). 153 tests headless en verde, 0 warnings, taintlint
> limpio. **M5 COMPLETO (ADR-0006)**: paquete embebible (`scripts/build-embed.ps1`
> con gates), guía de integración (`docs/CRAFT-INTEGRATION.md`, inglés) y
> **release v0.1.0** (tag sobre main, LibStub MINOR 2). La integración en los
> componentes es trabajo del owner EN el repo de Craft, sobre builds etiquetados.
> **M6 COMPLETO + RELEASE v0.2.0**: `Weave.each` (ADR-0007, adelantado de v1 por
> demanda real de Coffer y Craft) — reconciliador puro por keys en `core/Reconcile.lua`
> + pooling combat-safe en `ui/Each.lua`; 180 tests; verificado in-game (lista
> dinámica, secrets, combate con overflow y catch-up). **FR Craft + RELEASE v0.3.0**
> (sin ADR, aditivo): predicados públicos `Weave.isReactive`/`Weave.isWritable` (core)
> para consumidores "señal-o-literal"; `props._isCallable` delega en ellos; 192 tests.
> Siguiente entregable: **M7 — docs para devs nuevos** (tutorial "tu primer addon
> reactivo", <60 líneas).
> **Nivel de proceso: M** (subirá a L antes del primer release público, como craft).

## 1. Identidad del producto

- **Nombre**: Weave. Carpeta de la lib (cuando exista código): `Weave/`.
- **Dominio**: librería de **reactividad por señales** (estilo Fusion/SolidJS) para UI de
  addons de WoW, en Lua 5.1 puro.
- **Resumen**: el flujo reactivo completo — estado (`signal`/`store` persistente) →
  derivación (`computed`) → vista (`bind`/`Weave.new` declarativa). Los frames se crean una
  vez y mutan in-place. Taint-aware (secrets degradan a fallback, nunca crashean). Pieza
  hermana de Craft (componentes) y taintlint (linter). Alcance v0: ADR-0005.
- **Owner**: Alberto Gomez.

## 2. Contexto que el agente MUST leer antes de actuar

1. Este archivo completo.
2. `docs/NORTH-STAR.md` — el norte innegociable (señales/no-VDOM, cero toolchain, no monolito).
3. `docs/adr/` — 0001–0007, decisiones fundacionales (0005 = alcance ui+store;
   0006 = Craft integra Weave nativamente, sin capa `craft/` en Weave;
   0007 = `each` adelantado a M6, docs a M7).
4. `docs/API-v0.md` — la superficie pública; los tests se escriben contra ella.
5. La regla global de taint de `~/.claude/CLAUDE.md` y AddonTemplate/docs/05 aplican.
6. Referencia externa de diseño: Fusion (https://github.com/dphfox/Fusion) — precedente de
   señales en Lua; se estudia, no se copia (Luau ≠ Lua 5.1).

## 3. Estructura del repositorio

```
/
├── AGENTS.md · CLAUDE.md · README.md
├── docs/            NORTH-STAR, adr/, API-v0.md
├── Weave/           ← la lib (M0+): core/ · wow/ · store/ · ui/ (craft/ eliminada, ADR-0006)
├── tests/           busted headless (core sin mock; wow con mock mínimo)
└── demo/            addon de demo in-game (M1+)
```

## 4. Stack tecnológico autoritativo

| Capa | Tecnología | Nota |
|------|------------|------|
| Lenguaje | Lua 5.1 | sandbox WoW; SIN transpilers (ADR-0002) |
| Distribución | LibStub `"Weave-1.0"` | registro versionado (patrón Craft.register) |
| Lint | luacheck (`.luacheckrc`) + taintlint | cadena estándar AddonTemplate/docs/03 |
| Tests | busted | `core/` headless puro; `wow/` con mock mínimo |
| Tipos | anotaciones LuaLS en API pública | opcionales, sin build (ADR-0002) |

> MUST NOT introducir dependencias fuera de esta tabla sin ADR.

## 5. Reglas de dominio invariantes (MUST / MUST NOT)

- **MUST**: `Weave/core/` es Lua puro — CERO llamadas a API de WoW (ni `CreateFrame`, ni
  `GetTime`, ni globals del juego). Es la frontera del ADR-0004 y lo que permite busted sin mock.
- **MUST**: cambios a la superficie pública actualizan `docs/API-v0.md` en el mismo commit.
- **MUST**: hot path de notificación sin allocations de tabla (contrato de rendimiento, API-v0 §1).
- **MUST**: la semántica taint sigue la tabla de verdad de API-v0 §3 (ADR-0003).
- **MUST NOT**: VDOM/diffing/re-render; compiladores; capa OOP tipo PLoop; features de
  framework total (NORTH-STAR — lista de desviaciones prohibidas).
- **MUST NOT**: código en Weave que conozca a Craft (ADR-0006) — la integración vive en el
  repo de Craft, que embebe SOLO builds etiquetados de Weave (tag `v*`, jamás `dev`).
- **MUST NOT**: bind/effect crean frames — solo mutan (combat-safe por diseño).
- **MUST**: `Weave.new` (ui) rechaza creación en combate (`InCombatLockdown()` → error dev /
  no-op con warning en prod). `store/` solo escribe en la SavedVariables declarada por el
  addon consumidor y nunca borra claves que no conoce (datos del usuario intocables).

## 6. Convenciones de código

- Código, identificadores y **comentarios in-code en INGLÉS**; docs (`docs/`, ADRs) y
  descripciones de tests (`it("...")`) en español. Estándar AddonTemplate aplica
  (trampas Lua 5.1 de docs/02 incluidas).
- Anotaciones LuaLS en todo símbolo público.

## 7. Verificación

1. `luac -p` por archivo; `luacheck Weave/ --config .luacheckrc` sin warnings.
2. `busted tests/` — verde SIEMPRE en main/dev; `core/` sin mock es parte del contrato.
3. In-game (M1+): demo canónica de API-v0 §5 + prueba ForceTaint de M2 (deploy + `/reload`
   + BugSack, flujo estándar).

## 8. Git / workflow

- `main` estable + `dev` trabajo (modelo craft). Conventional Commits en español.
- Identidad git local: `Betto <betto.gamer@icloud.com>`. **Sin trailers de co-autoría de IA
  ni atribuciones de herramientas** en los commits (regla taintlint; detalle en CLAUDE.md §Git).
- **MUST NOT `git push`** (lo hace el owner). Commit/branch solo si el usuario lo pide.
- Releases (M4+): tag `v*`; empaquetado por decidir en su momento (probable ruta B/packager
  al publicar — pendiente de ADR).

## 9. Lecciones / errores comunes del proyecto

- **La demo muestra "0%" fijo sin ningún error Lua** → en 12.0.7 `UnitHealth`/`UnitHealthMax`
  devuelven secret values SIEMPRE en código de addon (incluso fuera de combate, sin
  ForceTaint), así que el `fallback` numérico declarado se convierte en el valor permanente →
  patrón correcto: el fallback es para valores que se OPERAN; lo que solo se PINTA va como
  señal **sin** fallback bindeada directo al sink que acepta secrets
  (`SetValue`/`SetMinMaxValues`), y el texto/color derivado comprueba `isSecret()` y degrada
  ("??" / color neutro). _Demo M1 (2026-07-03)._
- **El ancho persistido "vuelve al default" tras /reload** → `C_AddOns.IsAddOnLoaded(owner)`
  devuelve `true` DURANTE la ejecución de los archivos del propio addon (antes de que su
  SavedVariable cargue), así que la vía rápida "dueño ya cargado → reclama la global ya"
  reclamaba una tabla vacía que WoW pisaba después al cargar la SV; el store quedaba ciego
  en su tabla huérfana → patrón correcto: con la global `nil`, reclamar si hace falta pero
  SIEMPRE seguir vigilando el `ADDON_LOADED` del dueño y re-adoptar lo que haya en la
  global al llegar (auto-curativo bajo cualquier semántica de IsAddOnLoaded). _Store M3,
  visto in-game (2026-07-03)._
- **Tests de tiempo: nunca comparar contra literales decimales** → `1000 + 0.06 + 0.06 ≠
  1000.12` en coma flotante (el runner muestra "esperado 1000.12, obtenido 1000.12") →
  comparar contra la MISMA aritmética que hace el código (`t0 + dt1 + dt2`). _ticker_spec
  (2026-07-03)._

## 10. Registro de cambios

| Versión | Fecha | Cambio |
|---------|-------|--------|
| v0.1 | 2026-07-02 | Fase de diseño: NORTH-STAR + ADR 0001–0004 + API-v0. Sin código aún. |
| v0.2 | 2026-07-02 | ADR-0005 (decisión del owner): alcance v0 amplía a `ui/` + `store/`; `each` a v1; DevTools y tiempo a v2. API-v0 y NORTH-STAR actualizados. |
| v0.3 | 2026-07-03 | **M0 completo**: core entero con 49 tests (mini-runner propio, busted queda para CI). Git creado (identidad Betto, sin trailers de IA), licencia MIT, mensajes de error de la API en inglés, enganche `_setSecretDetector` documentado en API-v0 §3. |
| v0.4 | 2026-07-03 | **M1 completo**: capa `wow/` entera (91 tests) + Weave empaquetada standalone (toc/xml, LibStub vendoreado) + WeaveDemo verificada in-game. Hallazgo 12.0.7: UnitHealth/UnitHealthMax secret SIEMPRE en código de addon → patrón sink-directo (§9). taintlint corre local (Node 24 LTS instalado). |
| v0.5 | 2026-07-03 | **M2 completo**: guard de secrets en maps de eventos (`_isSecretError` compartido core→wow; 97 tests) + `/weavetaint` verificado in-game — pipeline entero bajo ForceTaint_Strong con secrets reales, cero popups. |
| v0.6 | 2026-07-03 | **M3 completo**: `store/` entero (133 tests) + persistencia verificada in-game. Bug real cazado: IsAddOnLoaded true durante la carga del propio addon (§9). Defaults nunca a disco; `_version` única clave propia; secrets jamás se persisten. |
| v0.7 | 2026-07-03 | **M4 completo**: `ui/` entero (153 tests) + demo canónica §7 in-game en forma declarativa final. Descriptors perezosos para regiones (no pueden nacer sin padre); combate = error duro (no-op prod pendiente de flag); `_attachToScope` en el core. |
| v0.8 | 2026-07-03 | **ADR-0006 (decisión del owner)**: Craft integrará Weave nativamente; la capa `craft/` se elimina del alcance de Weave. M5 redefinido: paquete embebible + guía de integración + release v0.1 (absorbe el viejo M6 de release). |
| v0.9 | 2026-07-03 | **M5 completo + RELEASE v0.1.0**: build-embed.ps1 (gates: suite+luacheck), CRAFT-INTEGRATION.md, bump LibStub MINOR 2, tag `v0.1.0` sobre main. Weave lista para embeberse en Craft. |
| v0.10 | 2026-07-05 | **ADR-0007 (decisión del owner)**: `Weave.each` se adelanta de v1 a **M6** (demanda real: Coffer y Craft chocaron con el límite); docs para devs nuevos → M7. `each` cerrará con release v0.2.0. |
| v0.11 | 2026-07-05 | **M6 completo + RELEASE v0.2.0**: `Weave.each` (core/Reconcile.lua puro + ui/Each.lua; render 1 vez por fila, datos por señales item/index, keying opcional, layout de pila, combate solo-recicla con catch-up en PLAYER_REGEN_ENABLED, opts.warm). 180 tests; demo `/weavelist` verificada in-game. CRAFT-INTEGRATION §4.5; bump LibStub MINOR 3; tag `v0.2.0` sobre main. |
| v0.12 | 2026-07-05 | **FR Craft + RELEASE v0.3.0** (sin ADR, aditivo): predicados públicos `Weave.isReactive`/`Weave.isWritable` (core) para consumidores "señal-o-literal"; semántica estructural; `props._isCallable` delega en ellos (una sola definición). API-v0 §1 + CRAFT-INTEGRATION §4.1/§4.3/§6; 12 tests (192 total); bump LibStub MINOR 4; tag `v0.3.0` sobre main. |
