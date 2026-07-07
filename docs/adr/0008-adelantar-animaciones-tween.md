# ADR-0008: Adelantar animaciones — `Weave.tween` (M8 / v0.4.0), tween-first

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-07-05 |
| Alcance | roadmap (añade M8); adelanta "animaciones reactivas (v3+)" del backlog a v0.4.0 |
| Decisor | owner (Alberto) |

## Contexto

El backlog ("Ideas futuras") lista **animaciones reactivas (v3+)**: springs/tweens estilo
Fusion — "anima suave hacia el valor de esta señal" — con la nota de que requiere `ui/`
maduro y **presupuesto de rendimiento propio**. Con M4–M6 cerrados, `ui/` está maduro.

**El consumidor es Craft.** La razón de querer animaciones ahora es concreta: los
componentes de Craft deben animarse — **selects** que despliegan, **modals** que aparecen
y desaparecen, **collapses** que expanden y contraen. Igual que con `each` (ADR-0007), hay
un consumidor real con **casos de uso concretos contra los que diseñar** en vez de en
abstracto — la señal que el backlog dice esperar ("las mejores ideas salen de USAR Weave").
La dirección de dependencia es la del ADR-0006: Craft embebe un build etiquetado de Weave y
construye SUS animaciones encima; Weave no conoce a Craft.

Esos casos ya aportan input de diseño real: modal (`alpha` 0↔1), collapse/select
(`height` 0↔N) son animaciones de **número**. Y todos comparten un requisito que un
`tween(target)` pelado no cubre — la **animación de salida**: al cerrar/colapsar hay que
ocultar el frame *después* de que la animación termine (no en el acto, o no se ve el
fundido; ni dejarlo presente-pero-invisible robando clics). Se resuelve exponiendo si el
tween **está animando** como booleano reactivo (`t:animating()`), de modo que el consumidor
haga `shown = abierto OR animando` — declarativo, sin callbacks (ver spec §2).

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| A. Dejarlo en el backlog hasta v3 | fiel al orden original | Craft no puede animar sus componentes; sigue con animación manual (el churn de callbacks que Weave evita) |
| B. Adelantar completo (tween + spring a la vez) | cubre todo el vocabulario | máxima superficie sin que los casos de Craft pidan spring aún; spring es menos determinista para tests; sobre-diseño |
| C. Adelantar **tween-first**, alcance mínimo + lo que los casos de Craft piden (`:animating()`), base lista para spring | diseña contra casos reales de Craft; riesgo acotado; spring encaja después sin rehacer la base | superficie nueva; se asume que la forma le encajará a Craft (se valida migrando un componente real) |

## Decisión

> **Elegimos C. Se adelanta `Weave.tween`, tween-first, como M8 y release v0.4.0**,
> diseñado contra los casos reales de Craft (select/modal/collapse):
>
> - **`Weave.tween(target, opts)` → reactivo read-only** cuyo valor se desliza hacia
>   `target()` en `opts.duration` con `opts.easing`. Se bindea como cualquier señal.
>   Coherencia señal-o-literal: un literal se siembra y no anima.
> - **Tipos: número O array de números** (lerp por elemento) — value/width/**alpha**/
>   **height** y color/posición. Los casos de Craft son sobre todo `alpha`/`height`.
> - **`t:animating()` — booleano reactivo** (¿hay animación en curso?) para coordinar
>   entrada/salida: `shown = W.computed(function() return abierto() or t:animating() end)`.
>   Es la única adición que los casos de Craft motivan sobre el tween mínimo.
> - **Nombre: `Weave.tween`**, con `Weave.spring` reservado como hermano futuro. La base
>   (driver + reactivo animado) se diseña para que spring sea otro "motor" encima.
> - **Reparto por capas (ADR-0004):** motor de interpolación (from/to/elapsed/duración/
>   easing → valor) en **`core/Tween.lua`** (Lua puro, testeable headless); driver
>   (`GetTime`, ticker compartido, suscripción al target, `:animating()`) en
>   **`wow/Anim.lua`**. El core sigue sin reloj (frontera intacta).
> - **Presupuesto de rendimiento:** UN driver compartido avanza todas las animaciones
>   activas por frame; una que llega a su meta se retira (coste cero en reposo; el ticker
>   para si no queda ninguna — como `onUpdate`). Los arrays reutilizan una tabla-resultado
>   por tween (mutación in-place) → cero allocations por frame (contrato API-v0 §1).
> - **Taint:** si `target()` es secret, no se interpola → degrada por el chokepoint
>   (fallback / se congela) y reanuda al volver un valor normal.
> - **Combate:** un tween solo MUTA (no crea frames) → combat-safe; el driver corre en
>   combate sin tratamiento especial (a diferencia de `each`).
> - **Disposal:** adscrito al scope activo; `dispose()` lo desengancha del target y del driver.
>
> La spec entra en `docs/API-v0.md` antes de los tests (TDD-con-aprobación de siempre).

## Consecuencias

- (+) Craft puede animar select/modal/collapse sobre un build etiquetado de Weave, tirando
  la animación manual — mismo patrón de adopción que `each`.
- (+) Se diseña contra casos reales; `:animating()` sale de una necesidad concreta (salida),
  no de imaginar. La arquitectura reusa el patrón `each` (motor puro + capa wow) y la
  infraestructura de ticker/taint/scope existente.
- (−) Superficie pública nueva cuya forma se valida al migrar un componente real de Craft;
  si no encaja, se corrige en una MINOR (aún v0, API no congelada).
- Roadmap: **M8 = `Weave.tween` + release v0.4.0** (superficie nueva → bump MINOR de semver
  y de LibStub, MINOR 5). API-v0 §8/§9 y AGENTS.md se actualizan en este mismo commit.

## Validación / reversión

Acertada si **Craft anima al menos un componente real** (un modal o un collapse) con
`Weave.tween` — fundido/expansión fluidos, salida que oculta al terminar vía `:animating()`,
bajo ForceTaint sin errores Lua y con coste cero en reposo — tirando su animación manual.
La demo in-game de Weave hace de primer validador antes de que Craft migre. Reversible a
bajo coste: `tween` es aditivo (no toca core/wow/store/ui existentes); si el diseño no
convence antes de la release, se retira sin afectar a v0.3.0.
