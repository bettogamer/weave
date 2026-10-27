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

_(vacío — los dos FR de Coffer se cerraron el 2026-10-26, ADR-0012)_

## Cerrados

- **`Weave.virtual`: pausar cuando su frame NO está a la vista** — ✅ **CERRADO 2026-10-26**
  (pedido por **Coffer 2026-09-02**, revisión de rendimiento; ADR-0012). Una ventana cerrada de
  Coffer seguía pagando en cada `BAG_UPDATE` el pipeline del stream, la replanificación y el
  repintado. **Resuelto en dos capas:** (1) `virtual` duerme **automáticamente** (decisión del
  owner, sin `opts.enabled`): `HookScript` a `OnShow`/`OnHide` del viewport + `IsVisible()`;
  dormido no lee fuente/scroll/geometría y al despertar reconcilia contra el valor ACTUAL.
  (2) **Hallazgo al diseñar**: eso solo no paraba el pipeline, porque la cola del core recalculaba
  todo `computed` sucio aunque nadie lo leyera. Ahora un `computed` sin observadores queda sucio
  y suelta sus deps (pereza que sube por la cadena) — cambio de core aprobado por el owner.
  **Coffer puede retirar su apaño** (la señal `visible` leída primero por los computeds del stream).
- **`Weave.virtual`: segmentos en línea dentro de una fila de grid** — ✅ **CERRADO 2026-10-26**
  (pedido por **Coffer 2026-10-26**, variante "B · Subgrupos en fila"; ADR-0012). **Resuelto** con
  `opts.segmentOf` / `segmentGap` / `segmentLabel = { height, render(info) → frame }` (rótulo en
  idioma Weave — render una vez por marco de un pool propio, `info` = señal `{ key, entry, first,
  count, width }` — decisión del owner frente al `create`/`render` imperativo del FR). Empaquetado
  en px en `core/Flow.lua`; envoltura desde x=0 con rótulo solo en el 1er tramo; filas con rótulo
  = `labelHeight + celda`. Sin separador incorporado (el hueco queda libre). Planificador público
  **`Weave.flowPlan(list, opts)`** con las mismas opts y el mismo código que la ui, para el `fitHeight`
  de Coffer. Pendiente en Coffer: `List.lua` `emitSub` deja de emitir sub-cabeceras y marca el
  segmento; `WinBody.lua` pasa `fitHeight` a `Weave.flowPlan`.
- **`Weave.tween`: saltar a un valor sin interpolar (`:snap`)** — ✅ **CERRADO 2026-08-27**
  (pedido por **Coffer 2026-08-23**, fundido del grid al cambiar de filtro; ADR-0011). El tween
  solo sabía interpolar *desde donde está*, así que el *fade-in* —el patrón de aparición más
  común— obligaba a un **ping-pong** por la señal fuente: el doble de duración y un frame a
  brillo pleno antes de bajar. **Resuelto** con `tw:snap(value)`, que **teletransporta y SIGUE**
  (decisión del owner frente a la letra del FR, que pedía teletransportar y desarmar): fija el
  valor en el acto y re-apunta al destino actual; si `value` ya ES el destino, se desarma. Con
  eso una sola operación cubre el fade-in (`snap(0.45)` con destino 1) y el "saltar al final"
  (`snap(destino)`), y se preserva la invariante de que **un tween nunca reposa en un valor
  distinto de su destino**. `animating()` se enciende solo si queda camino. Arrays, secrets y
  `dispose()` cubiertos. Tests: +10 (`tests/wow/anim_spec.lua`). Docs: API-v0 §2,
  CRAFT-INTEGRATION §4.6. Demo `/weavetween <0-100>` (fade-in) y `/weavetween now <0-100>`
  (salto seco). **Verificado in-game** por el owner (2026-08-27).

- **`Weave.virtual`: viewport y columnas MUTABLES (`Resize`)** — ✅ **CERRADO 2026-08-27**
  (pedido por **Coffer 2026-08-26**, reiterado el **2026-08-27** pidiendo solo el alto;
  ADR-0011). `opts.viewport`/`opts.columns` eran números de constructor, así que la ventana de
  ítems de Coffer estaba `resizable = false` y **cada cambio de geometría pedía `/reload`**.
  **Resuelto con el FR completo, no con el subset** (decisión del owner):
  `inst:Resize{ width?, height?, columns? }` + azúcar `SetViewport` / `SetViewportHeight` /
  `SetColumns`. Por dentro **no es imperativo**: el viewport pasa a ser una señal interna que
  lee el effect de ventaneo, así que fijarla re-planifica y repinta por el camino que ya
  existía. **Combate = salida (a)** (la preferida por el consumidor): la geometría se aplica
  siempre y en el acto; solo se difiere **crear** las filas extra, con aviso único y catch-up en
  `PLAYER_REGEN_ENABLED` (idioma de `each`). Encoger nunca crea nada → gratis y silencioso
  incluso en combate, y el pool **solo crece** (las filas sobrantes se ocultan y se reusan: sin
  churn durante el arrastre). Idempotente; valida lo mismo que el constructor. Tests: +17
  (virtual_spec 13 + virtual_hetero_spec 4). Docs: API-v0 §4, CRAFT-INTEGRATION §4.7. Demo
  `/weavegroups` con **grip de redimensionado real** en la esquina inferior derecha.
  **Verificado in-game** por el owner (2026-08-27): el grid reflowea de forma continua durante el
  arrastre, sin parpadeos ni `/reload`. **Pendiente del owner**: declarar `resizable = true` en la ventana de bolsas de Coffer y
  borrar el aviso de `/reload` de los deslizadores de Ajustes.

- **`Flow.lua`: sangría por fila — jerarquía visual dentro de un grid** — ✅ **CERRADO
  2026-08-27** (pedido por **Coffer 2026-08-26**, sub-secciones dentro de una categoría;
  ADR-0011). El planner repartía las filas `grid` con un `columns` **global**, así que una
  sub-sección no podía colgar de su cabecera: se leía como hermana de su madre. Ni la tipografía
  ni la banda de color lo suplían — **sangrar el CONTENIDO es lo que crea jerarquía en una
  lista**. **Resuelto** con `opts.indentOf(entry) → px`, **por fila** (variante 2, decisión del
  owner: simétrica con `typeOf` y un solo `render` por nivel, sin `item`/`itemSangrado`
  gemelos). Semántica elegida: **bajan las COLUMNAS, no el tamaño de celda**
  (`floor((ancho_útil − indent) / colWidth)`, mínimo 1) — si encogieran las celdas, la sangría
  se leería como "estos ítems son más pequeños". Un cambio de sangría **rompe la fila abierta**,
  igual que una cabecera; las filas de ancho completo **también se insetan y encogen** (decisión
  del owner), así que una sub-cabecera cuelga alineada con sus propios ítems. El core sigue puro:
  `_flowLayout` recibe `indent`/`columns` ya masticados por el ui. **Consecuencia asumida: el nº
  de columnas deja de ser global en el planificador.** Tests: +12 (flow_spec 6 +
  virtual_hetero_spec 6). Docs: API-v0 §4, CRAFT-INTEGRATION §4.7. Demo `/weavegroups`: "Armor"
  con dos sub-secciones sangradas. **Verificado in-game** por el owner (2026-08-27): las celdas
  sangradas miden lo mismo que las de la sección madre y caben 3 por fila en vez de 4.

- **`Weave.virtual`: padding — no afeitar la primera fila/columna con el clip** — ✅ **CERRADO
  2026-07-23** (pedido por **Coffer 2026-07-23**, grid de bolsas/banco). Síntoma: la celda de la
  **columna 0** (y la fila 0) perdía **1px** por quedar flush contra el borde del `SetClipsChildren`
  del viewport, con `effectiveScale` no-entero. **Resuelto** con `opts.padding` (escalar, 4 lados) +
  overrides `opts.paddingH` / `opts.paddingV` (decisión del owner sobre la forma de API). Inset
  **simétrico**: el horizontal encoge `colWidth` a `(viewport_w − 2·padH)/columns`; el vertical crece
  `contentHeight` en `padTop+padBottom`. La geometría vive en el core puro (`Weave._windowPlan` y
  `Weave._flowLayout` ganan `padTop`/`padBottom`); el ui aplica el offset X y encoge `colWidth`.
  Default 0 → cero cambio de comportamiento. Cubre grid homogéneo (Fase 1) y cabeceras de ancho
  completo (Fase 2, se insetan también). Tests: +13 (window/flow/virtual/virtual_hetero specs), suite
  **294** verde, luacheck 0/0, taintlint 0/0/0. Demo `/weavevirtual` con `padding = 4`. Docs: API-v0
  §4. **Verificado in-game** por el owner (2026-07-23): grid insetado, sin afeitado en col 0 / fila 0.
  **Pendiente del owner**: re-vendorear el build v0.8.0 en Coffer y migrar su grid a `opts.padding`.

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
