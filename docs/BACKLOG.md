# Backlog de ideas — Weave

> Ideas capturadas para NO diseñarlas ahora. Nada de aquí bloquea M0–M6. Cuando una madure,
> pasa por el proceso: ADR si es decisión de fondo, o directo al roadmap si es menor.
> Regla: las mejores ideas nuevas saldrán de USAR Weave (lección Craft: FR-010 nació de
> Sentry usándolo, no de imaginar).

## Planificado (ya decidido en ADR-0005)

- **v1 — `Weave.each`**: listas reactivas con frame pooling combat-safe (barras/iconos
  dinámicos — el patrón WeakAuras/MRT).
- **v2 — DevTools `/weave`**: inspector in-game del grafo de señales (hecho con Craft).
- **v2 — utilidades de tiempo**: `throttle`/`debounce`/`delay` sobre el ticker compartido.

## Solicitado desde el uso real (FR de consumidores)

- _(ninguno abierto)_

## Cerrados

- **VIRTUALIZACIÓN/windowing + modo grid + cabeceras — lista de bolsas de Coffer** — ✅ **CERRADO
  2026-07-09** (pedido 2026-07-09, ADR-0010). Resuelto con un **primitivo hermano nuevo,
  `Weave.virtual`** (NO ampliando `each`, que queda para listas chicas/DragList), en dos fases:
  - **Fase 1 (v0.6.0)** — requisitos 1/2/3/5: ventana virtual (pool FIJO al viewport, `core/
    Window.lua`), scroll fraccional, modo grid de N columnas, separación datos(`core/`)/render(`ui/`).
  - **Fase 2 (v0.7.0)** — requisito 4: cabeceras de grupo intercaladas (filas heterogéneas) vía
    `opts.typeOf` + `opts.types` con **pool por tipo** y planificador puro `core/Flow.lua`. El
    **colapso lo posee el consumidor** (el stream es un `computed` sobre una señal de grupos cerrados;
    `virtual` no conoce grupos).
  - Los 5 requisitos entregados y **verificados in-game** (`/weavevirtual`, `/weavegroups`): miles de
    filas, rueda + barra arrastrable, `secret`→"??", combate solo re-glasea, colapso. Docs: ADR-0010,
    API-v0 §4, CRAFT-INTEGRATION §4.7. **Pendiente del owner**: re-vendorear el build v0.7.0 en Coffer
    y migrar su lista manual (`List.lua` de Sorted) a `Weave.virtual`.

- **Predicados públicos de introspección de reactivos** — ✅ **CERRADO 2026-07-05**
  (pedido por Craft, ADR-0013 oleada 3). Entregado en el core: `Weave.isReactive(v)` (función
  o tabla callable → lo que `effect` observa; escalares/tablas planas → `false`) y
  `Weave.isWritable(v)` (subconjunto: solo signal con `:set`; computed y función → `false`).
  Semántica **estructural** (no por identidad de metatabla) → un consumidor no se acopla a la
  forma interna del signal. `Weave.props._isCallable` ahora **delega** en `Weave.isReactive`
  (una sola definición en todo el repo). Docs: API-v0 §1 + CRAFT-INTEGRATION §4.1/§4.3/§6
  actualizadas para usar los predicados. 12 tests nuevos (`tests/core/predicates_spec.lua`),
  suite 192 verde, sin ADR (aditivo y menor). **Pendiente del owner**: re-vendorear el build
  etiquetado en Craft y cambiar `Craft.Reactive.isCallable` / `isWritableSignal` para delegar
  (`applyOrBind` / `disposeAll` se quedan en Craft — ADR-0013).

## Ideas futuras (sin compromiso)

- **Craft reactivo por dentro (idea del owner, 2026-07-02)**: el sistema de temas de Craft
  (`Theme.register`/`_applyTheme`) es reactividad manual — con Weave serían señales + scopes
  (adiós unregister manual, double-free, re-entrancia). Y los componentes nuevos de Craft
  podrían declararse con `Weave.new` internamente. **Camino**: usar Weave en Craft_Browser
  primero (dogfooding), y con esa experiencia abrir un **RFC en `craft/docs/requests/`**
  (decisión del repo Craft, con su ADR — invierte la dirección de dependencia, no se toma a
  la ligera). Momento natural: componentes nuevos o un "Craft 2.0".
- **Animaciones reactivas** (v3+): springs/tweens estilo Fusion — "anima suave hacia el
  valor de esta señal". Requiere `ui/` maduro y presupuesto de rendimiento propio.
- **Kit de testing para consumidores**: empaquetar los mocks/harness de Weave para que un
  dev teste SU addon headless con busted. Sale casi gratis de M0; empaquetar en M6.
- **Reglas Weave para taintlint**: que taintlint conozca `fallback`/chokepoint y avise
  cuando una señal alimentada por API secretable no declara fallback (FR a taintlint).
