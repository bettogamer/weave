# ADR-0001: Reactividad por señales fine-grained, no VDOM

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-07-02 |
| Alcance | todo el proyecto (decisión fundacional) |

## Contexto

Queremos UI declarativa/reactiva para addons de WoW. Los dos modelos dominantes son VDOM
(React: re-render + diff) y señales fine-grained (SolidJS, Vue Vapor, Svelte 5 runes,
Roblox Fusion). El motor de WoW impone restricciones duras:

- Los frames son **retained-mode** y no se pueden destruir de verdad (solo reciclar en pools);
  crearlos es caro y está **prohibido en combate** (`InCombatLockdown`).
- El GC de Lua 5.1 penaliza el churn de tablas — un VDOM genera árboles nuevos por render.
- Los addons corren en el mismo hilo que el juego: cada ms de render cuesta FPS en raid.
- La industria web ya recorrió este camino: los frameworks post-React convergieron en
  señales precisamente para eliminar el costo del diffing.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| A. VDOM (port de React) | modelo conocido, JSX familiar | pelea contra retained-mode; churn de GC; necesita keys/reconciler; precedentes muertos (react-wow-addon, tsCoolDown) |
| B. Señales fine-grained | actualización in-place = modelo nativo de WoW; costo cero si nada cambia; core chico (~400 líneas); precedente vivo en Lua (Fusion) | menos familiar para devs que solo conocen React; dependency-tracking requiere cuidado con el GC |
| C. Data-binding simple sin grafo (observer plano) | trivial de implementar | sin computeds/derivación, el 80% del valor se pierde; los addons vuelven al spaghetti |

## Decisión

> **Elegimos B: reactividad fine-grained por señales con auto-tracking de dependencias
> (`signal` → `computed` → `effect`/`bind`).**

Es el único modelo que coincide con cómo funciona el motor (frames vivos que mutan
propiedades) en vez de simularse encima de él. Fusion demuestra que el modelo es aprendible
y ergonómico en Lua. El diffing no aporta nada cuando no hay árbol que reconstruir.

## Consecuencias

- (+) Actualizaciones O(cambio), no O(árbol); combat-safe por diseño (bind nunca crea frames).
- (+) Core 100% Lua puro y testeable headless.
- (−) Hay que diseñar disposal explícito (no hay unmount natural en WoW) → scopes (API-v0).
- (−) Auto-tracking mal usado (leer señales fuera de contexto reactivo) confunde — mitigar
  con `peek()` explícito y buena documentación.

## Validación / reversión

Acertada si: la demo (barra de vida reactiva) se escribe en <30 líneas, corre a 0 allocations
por update, y un dev externo la entiende sin leer el core. Señal de error: necesitar
"re-render" manual en casos reales → revisar el modelo.
