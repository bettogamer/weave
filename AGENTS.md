# AGENTS.md — Weave

> README ejecutable para agentes de IA. Fuente de verdad única: si cambia una decisión,
> este archivo y el ADR correspondiente se actualizan en el mismo commit.
>
> **Estado del proyecto: IMPLEMENTACIÓN.** **M2 COMPLETO**: taint end-to-end verificado
> in-game bajo ForceTaint_Strong (`/weavetaint`: pipeline entero con secrets reales,
> guards degradando con aviso suave, CERO popups). Los 3 puntos de entrada de código de
> usuario protegidos (fórmulas de computed, effects/binds, maps de eventos). 97 tests
> headless en verde, 0 warnings, taintlint limpio. Siguiente entregable: **M3 —
> `store/`** (SavedVariables reactivas, API-v0 §5).
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
3. `docs/adr/` — 0001–0005, decisiones fundacionales (0005 = alcance ui+store).
4. `docs/API-v0.md` — la superficie pública; los tests se escriben contra ella.
5. La regla global de taint de `~/.claude/CLAUDE.md` y AddonTemplate/docs/05 aplican.
6. Referencia externa de diseño: Fusion (https://github.com/dphfox/Fusion) — precedente de
   señales en Lua; se estudia, no se copia (Luau ≠ Lua 5.1).

## 3. Estructura del repositorio

```
/
├── AGENTS.md · CLAUDE.md · README.md
├── docs/            NORTH-STAR, adr/, API-v0.md
├── Weave/           ← la lib (M0+): core/ · wow/ · store/ · ui/ · craft/
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
- **MUST NOT**: `Weave/craft/` accede a internos `_privados` de Craft — si falta un setter
  público: FR a Craft y fallback (proceso estándar).
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
