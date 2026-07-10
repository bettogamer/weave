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

- **VIRTUALIZACIÓN/windowing + modo grid — para la lista de bolsas de Coffer**
  (pedido 2026-07-09). Resuelto con un **primitivo hermano nuevo, `Weave.virtual`** (ADR-0010),
  NO ampliando `each` — `each` queda para listas chicas/DragList. **Estado: Fase 1 ENTREGADA en
  v0.6.0 (2026-07-09)** — requisitos 1/2/3/5 (ventana virtual + scroll fraccional + grid +
  separación datos/render). **Fase 2 PENDIENTE**: requisito 4 (cabeceras de grupo intercaladas =
  filas heterogéneas, `opts.typeOf` + `render` por tipo con pool por tipo) → release aparte.
  El `each` v1 del ADR-0005 ("frame pooling combat-safe", un frame por
  entrada, patrón WeakAuras/MRT) **no basta** para una lista de inventario de miles de ítems.
  Requisitos concretos (fuente: Coffer `docs/UI-DESIGN.md` §8.1 y doc research 08 §2):
  1. **Ventana virtual, no frame-por-entrada**: pool FIJO de N filas visibles reciclado sobre
     un array de miles de entradas (no crear un frame por ítem). El pool recicla; jamás crea en
     caliente; si se agota, degrada con aviso (mismo espíritu que los secrets).
  2. **Scroll fraccional**: offsets por anchor (no salto de fila entera) para scroll suave.
  3. **Modo grid**: N columnas por fila (no solo lista de 1 columna) — el grid de iconos de
     bolsas. Nota: `Craft.Flex` no soporta wrap en `column`, así que el grid lo tiene que
     resolver `each`, no el layout de Craft.
  4. **Cabeceras de grupo intercaladas**: filas especiales (heading de categoría/grupo con
     "(n)" y estado colapsado) mezcladas con filas de ítem en el mismo stream virtualizado.
  5. **Datos separados del render**: la reconciliación/keying (Lua puro → `core/`, testeable
     headless) separada del pooling/materialización (`ui/`) — conforme al ADR-0004. Coffer ya
     diseña su lista manual con esta separación para migrar sin reescribir consumidores.
  - **Estado en Coffer**: hoy lista manual (patrón `List.lua` de Sorted, señales solo en los
    bordes); migra a `Weave.each` en cuanto el build etiquetado (v0.2.0 según ADR-0007) lo
    entregue. No bloquea el M5 de Coffer.
  - **Verificación esperada** (ya en ADR-0007): suite headless + demo in-game con lista dinámica
    + ForceTaint + prueba EN combate.

## Cerrados

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
