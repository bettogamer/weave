# ADR-0011: tres FR de Coffer — `tween:snap`, viewport vivo en `virtual`, sangría por fila

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-08-27 |
| Alcance | aditivo a la API pública de `wow/` (`tween:snap`) y `ui/` (`virtual`: `Resize`, `opts.indentOf`); amplía el contrato del planificador puro `core/Flow.lua` (el nº de columnas deja de ser global) |
| Decisor | owner (Alberto) |

## Contexto

Los tres FR abiertos en `docs/BACKLOG.md` los levantó **Coffer usándonos de verdad** (2026-08-23,
-26 y -27), que es la fuente de FR que ADR-0005 declaró la buena. Ninguno pide un primitivo nuevo:
los tres son huecos en primitivos que ya existen, y en los tres el consumidor tenía un fallback
en producción — funcionando, pero pagando de más.

1. **`Weave.tween` no sabe saltar.** Siempre interpola *desde donde está*, así que el patrón de
   aparición más común — *fade-in*: el contenido nuevo entra a media luz y sube — no se puede
   expresar. Fallback de Coffer: un **ping-pong** por la señal fuente (bajar y volver), que dura
   el doble y enseña un frame a brillo pleno antes de bajar.
2. **`Weave.virtual` nace con el viewport congelado.** `opts.viewport`/`opts.columns` se validan
   como números de constructor y el instance solo expone `contentHeight()`. Consecuencia: la
   ventana de bolsas de Coffer estaba declarada `resizable = false` y **cada cambio de geometría
   pedía `/reload`**. Fallback posterior: reconstruir el cuerpo del grid entero en `onResized`,
   que tira y recrea los pools en cada gesto.
3. **`core/Flow.lua` reparte las celdas con un `columns` global**, así que una sub-sección no
   puede colgar de su cabecera. Coffer intentó suplirlo con señales tipográficas y luego con una
   banda de color; el propio owner volvió a pedirlo apuntando al grid: **sangrar el CONTENIDO es
   lo que crea jerarquía en una lista**, lo demás solo acompaña.

Lo que ata a Coffer a `virtual` no es el tamaño de sus datos (149 ítems en bolsas, 301 en banco):
es el **planner de tipos mezclados** y el **binding reactivo por celda**. El tamaño fijo era un
efecto colateral del constructor, no una propiedad deseada.

## Alternativas consideradas

**Para `snap`** — (a) *teletransportar y desarmar* (la letra del FR): el tween se queda quieto en
el valor saltado aunque su destino sea otro, y solo el siguiente cambio del destino anima. Es más
predecible en aislamiento pero **no resuelve el caso real**: la señal de Coffer ya vale 1, así que
el fade-in seguiría exigiendo menear la señal — el ping-pong del que se huía. (b) `opts.snapFirst`
como bandera de construcción: cubre solo la primera aparición, no las siguientes.

**Para el viewport vivo** — (a) *solo el alto* (`SetViewportHeight`), que es la mitad barata
porque **el plan no depende del alto**; (b) `SetViewport` + `SetColumns`; (c) `Resize{}` completo.
Y, transversal, la arruga de combate: agrandar necesita frames nuevos, prohibido para plantillas
seguras. Salidas posibles: diferir a `PLAYER_REGEN_ENABLED`, exponer `CanResize()` y que decida el
consumidor, o exigir pre-calentado del pool al tamaño máximo.

**Para la sangría** — (a) *por tipo* (`types.<name>.indent`): más simple por dentro, pero obliga a
declarar un tipo por nivel, con `item` e `itemSangrado` compartiendo el MISMO `render`. (b) *por
fila* (`opts.indentOf(entry)`), simétrico con el `typeOf` que ya existe. Y, con menos ancho útil,
o **encogen las celdas** o **bajan las columnas** de esa tanda.

## Decisión

**1. `tw:snap(value)` teletransporta y SIGUE.** Fija el valor en el acto y vuelve a apuntar al
destino actual: si queda camino re-arranca desde ahí; si `value` ya ES el destino, se desarma. Una
sola operación cubre los dos usos (fade-in y "saltar al final") y preserva la invariante que hace
honesto al primitivo: **un tween nunca reposa en un valor distinto de su destino**. `animating()`
se enciende solo si de verdad queda camino, y baja a false al desarmar — nunca se queda colgado.

**2. `inst:Resize{ width?, height?, columns? }` completo**, con `SetViewport`/`SetViewportHeight`/
`SetColumns` como azúcar. Por dentro **no es imperativo**: el viewport pasa a ser una señal interna
que lee el effect de ventaneo, así que fijarla re-planifica y repinta por el camino que ya existía.
En combate, **salida (a)**: la geometría se aplica siempre y en el acto — `colWidth`,
`contentHeight` y el re-empaquetado no esperan a nadie —; lo único que se difiere es **crear** las
filas extra, con aviso único y catch-up en `PLAYER_REGEN_ENABLED`, exactamente el idioma de `each`.
Encoger nunca crea nada, así que es gratis y silencioso incluso en combate. El pool **solo crece**:
las filas sobrantes quedan ocultas y se reusan, de modo que un arrastre no genera churn.

**3. Sangría POR FILA (`opts.indentOf(entry) → px`), y bajan las COLUMNAS, no el tamaño de celda.**
Las celdas conservan su ancho — si encogieran, la sangría se leería como "estos ítems son más
pequeños" —, así que la tanda pasa a caber en `floor((ancho_útil − indent) / colWidth)` columnas,
mínimo 1. Un cambio de sangría **rompe la fila abierta**, igual que una cabecera. Las filas de
ancho completo **también se insetan y encogen**, para que una sub-cabecera cuelgue alineada con sus
propios ítems (decisión explícita del owner: `virtual` ya es dueño de la x y el width de esas filas).

El **core sigue tonto y puro**: `_flowLayout` recibe `items[i].indent` y `items[i].columns` ya
masticados por el ui y solo aplica las dos reglas nuevas. La traducción de píxeles a columnas —lo
único que necesita saber de geometría de pantalla— vive en `ui/Virtual.lua`, donde ya vivía.

## Consecuencias

- (+) Los tres FR se cierran sobre primitivos existentes: **cero superficie conceptual nueva**. No
  hay un `Weave.resizableVirtual` ni un tipo de fila "sangrada".
- (+) Coffer puede quitar sus tres fallbacks: el ping-pong de `WinBody.lua`, la reconstrucción del
  grid en `onResized`, y la banda de color que simulaba jerarquía.
- (+) `Resize` reusa el effect de ventaneo en vez de abrir un camino imperativo paralelo — misma
  disciplina reactiva que el resto de la librería, y el combate se resuelve con el idioma que
  `each` ya había fijado en M6.
- (+) Default en todo: `indent` 0 y viewport inmutable si nadie llama a `Resize` → la suite previa
  entera (294 tests) sigue verde sin tocarla.
- (−) **El nº de columnas deja de ser global** en el planificador puro: `_flowLayout` ya no puede
  asumir un ancho único por stream. Es la parte que el FR identificaba como cara y la que hay que
  tener presente al tocar `core/Flow.lua`.
- (−) `virtual` gana un vigía compartido de `PLAYER_REGEN_ENABLED` (perezoso: solo se crea si
  alguien redimensiona en combate). Segundo sitio de la librería con ese patrón, tras `each`.
- (−) Tres entradas nuevas en la superficie pública (`snap`, `Resize` + azúcar, `indentOf`) →
  documentadas en API-v0 §2/§4 y CRAFT-INTEGRATION §4.6/§4.7.

## Validación / reversión

Acertada si Coffer, sobre el build v0.9.0, (1) sustituye su ping-pong por un `snap` de una línea,
(2) declara su ventana de bolsas `resizable = true` con grip continuo y borra el aviso de
`/reload` de los deslizadores de Ajustes, y (3) sus sub-secciones se leen colgando de su cabecera
sin la banda de color de emergencia. Las tres piezas son **independientes y aditivas**: si alguna
no encajara con el uso real, se revierte sola sin tocar a las otras dos ni al comportamiento por
defecto (todas tienen default = comportamiento previo).
