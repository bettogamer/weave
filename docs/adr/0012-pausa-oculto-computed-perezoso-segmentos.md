# ADR-0012: dos FR de Coffer — `virtual` duerme oculto (+ `computed` perezoso de verdad) y segmentos en línea

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-10-26 |
| Alcance | **cambia semántica del core** (`computed` sin observadores ya no se recalcula); aditivo en `ui/` (`virtual` duerme oculto; `opts.segmentOf` / `segmentGap` / `segmentLabel`); amplía el contrato puro de `core/Flow.lua` (segmentos, px además de columnas) y añade la API pública `Weave.flowPlan` |
| Decisor | owner (Alberto) |

## Contexto

Dos FR abiertos en `docs/BACKLOG.md`, los dos de **Coffer usándonos de verdad**:

1. **`virtual` trabaja aunque nadie lo mire** (2026-09-02, el hallazgo más grande de su revisión
   de rendimiento). Las cinco ventanas de Coffer viven para siempre (cerrar = ocultar) y el
   modelo se re-publica en cada `BAG_UPDATE`: una ventana **cerrada** pagaba el pipeline entero
   del stream, la replanificación y el repintado. Coffer lo apañó en su modelo, ventana a
   ventana.
2. **Sub-grupos en línea** (2026-10-26, variante "B · Subgrupos en fila" elegida por el owner):
   cada sub-grupo es un bloque = rótulo corto encima de sus celdas, varios bloques por fila. El
   planificador solo sabía de columnas: un rótulo *encima* de un tramo de celdas no se podía
   expresar.

**Hallazgo al diseñar el FR 1:** pausar el `virtual` por sí solo **no ahorra lo caro**. La cola
de `drainComputeds` recalculaba todo `computed` sucio **tuviera o no observadores**, así que el
pipeline de Coffer (filtros, `MatchFirst`, `sort`, agrupación) seguía corriendo con la ventana
cerrada aunque el `virtual` ya no leyera el stream.

## Decisión

### 1. Core: un `computed` que nadie observa no trabaja

Cuando una dependencia cambia y el `computed` **no tiene observadores en ese instante**, se
marca sucio (O(1)) y **suelta sus propias dependencias**: ya está sucio, no necesita más avisos;
la próxima lectura (`c()` o `c:peek()`) lo recalcula contra el valor actual y vuelve a
suscribirse. Soltar las deps es lo que hace que la pereza **suba por la cadena** (A → B): en
cuanto B suelta, A tampoco tiene observadores — a lo sumo un recálculo de más por nivel.

**Por qué en el aviso y no al perder el último observador:** un effect suelta TODAS sus deps al
empezar cada pasada y las re-coge durante ella. Decidir "sin observadores → desenganchar" en ese
momento ensuciaría cada computed que lee el effect en cada re-ejecución. En el aviso, el conjunto
de observadores es el real. Hay un test guarda exactamente de eso.

Consecuencias: (a) es lo que hacen Solid/Preact — un `computed` es una fórmula, y una fórmula
que nadie mira no tiene por qué calcularse; (b) bonus: un `computed` abandonado deja de estar
colgado de sus señales (no se queda vivo por referencia de observador); (c) un error de una
fórmula sin observadores ya no aflora en el `set()` de su dependencia sino en la siguiente
lectura — antes era ruido de algo que nadie consumía. Toda la suite previa siguió verde sin tocarla.

### 2. `virtual` duerme cuando su viewport no está a la vista — automático

Sin API nueva (opción elegida por el owner frente a `opts.enabled`): el `virtual` se engancha
con `HookScript` (nunca `SetScript`: los handlers del consumidor siguen siendo suyos) a
`OnShow`/`OnHide` del viewport, que el cliente dispara también cuando cambia un **ancestro**, y
consulta `IsVisible()` (no `IsShown`). Dormido, el effect de ventaneo sale **antes de leer** la
fuente, el scroll y la geometría; como re-traquea en cada pasada, deja de estar suscrito a los
tres. Al despertar, una pasada contra los valores **actuales** (fuente, scroll, `Resize` hechos
mientras dormía). La **primera pasada se hace siempre**, para que `contentHeight()` sea válido
desde el nacimiento aunque el virtual nazca oculto. Con §1, el pipeline del consumidor también
se para: Coffer puede retirar su apaño.

Asumido: con el viewport oculto, `contentHeight()` es la última foto. Quien necesite el alto
de un contenido que no se ve usa `Weave.flowPlan` (§3).

### 3. Segmentos en línea + `Weave.flowPlan`

- `opts.segmentOf(entry) → key|nil`: entradas grid **consecutivas** con la misma clave = un
  segmento. `nil` = comportamiento de siempre. Pasar de sin clave a con clave (o al revés)
  cierra la fila — no se mezclan los dos empaquetados.
- Empaquetado en **px contra la banda** (ancho útil − sangría), celdas a `colWidth`: un segmento
  va en línea a `opts.segmentGap` px del anterior; si no cabe en lo que queda, abre fila; si es
  más ancho que la fila, envuelve desde x=0 con rótulo solo en el primer tramo. Una fila donde
  **empieza** algún segmento mide `labelHeight + celda` y todas sus celdas bajan `cellY` (las
  colas de segmentos envueltos incluidas: las celdas de una fila siempre alineadas). Cabeceras
  de ancho completo y cambios de sangría siguen cerrando fila.
- **Rótulo en idioma Weave** (elegido por el owner frente al `create`/`render` imperativo del
  FR): `opts.segmentLabel = { height, render = function(info) → frame }`; `render` corre UNA vez
  por marco de un **pool propio** (O(visible), crece diferido en combate como los demás) e
  `info` es una señal `{ key, entry, first, count, width }` (`count` = entradas del segmento
  entero; `width` = px del tramo rotulado). Solo se re-fija cuando cambia algo: scrollear no
  re-ejecuta los binds del rótulo. `virtual` fija tamaño y posición del rótulo.
- **Sin separador incorporado**: el hueco queda libre y el consumidor lo pinta desde el rótulo
  (el FR decía que bastaba).
- **`Weave.flowPlan(list, opts)` → `{ rows, contentHeight }`** (nombre elegido por el owner):
  las MISMAS opts que `virtual` heterogéneo; `opts.width` simula otro ancho. Garantía de "mismo
  algoritmo": `virtual` y `flowPlan` comparten `Weave._flowDescribe` + `Weave._flowGeometry` +
  `Weave._flowLayout` (el bucle de descriptores salió de `ui/Virtual.lua` al core puro).

## Alternativas descartadas

- **`opts.enabled` (señal) para la pausa**: explícito, pero cada consumidor tendría que
  acordarse; el FR mismo sospechaba que lo automático "es lo correcto".
- **Desenganchar el computed al perder su último observador**: trampa por el re-traqueo de los
  effects (§1).
- **Fila compuesta en el consumidor**: Coffer la descartó — reimplementar pool, combate y altura
  fuera de Weave.

## Consecuencias

- `core/Flow.lua` ya no es "tonto de píxeles": con segmentos recibe `colWidth`/`width` y empaqueta
  en px. Sin segmentos, intacto.
- 43 tests nuevos (suite **376**); mock de frames con `HookScript`/`IsVisible`/cascada de
  `OnShow`/`OnHide` como el cliente.
