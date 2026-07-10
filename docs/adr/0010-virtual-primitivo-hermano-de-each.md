# ADR-0010: `Weave.virtual` — primitivo hermano de `each` para grids virtualizados (M10)

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-07-09 |
| Alcance | roadmap (añade M10); añade `Weave.virtual` a la API pública de `ui/`; revierte la postura "grids/scroll no son de each" de API-v0 §4 |
| Decisor | owner (Alberto) |

## Contexto

`Weave.each` (M6, ADR-0007) hace **frame pooling combat-safe con un `render` homogéneo por
fila**: el `render` corre una vez por fila del pool y los cambios solo fluyen datos por las
señales `item`/`index`. Es el patrón WeakAuras/MRT — perfecto para listas dinámicas **chicas**
(auras, DragList de Craft).

Al diseñar `each` (API-v0 §4) se dejó la virtualización como **composición, no feature**: para
listas grandes, el consumidor recorta la ventana con un computed (`scrollPos` + slice) y `each`
por índice pinta esa ventana. Y se declaró explícito: *"grids/scroll no son de each"*.

El **FR del 2026-07-09** (Coffer, `docs/UI-DESIGN.md §8.1`) muestra que esa postura **no basta**
para una lista de inventario de miles de ítems. Requisitos concretos:

1. **Ventana virtual**: pool FIJO de N filas visibles reciclado sobre un array de miles (no un
   frame por ítem — hoy `each` materializa un frame por entrada del array fuera de combate).
2. **Scroll fraccional**: offset por píxel (no salto de fila entera) para scroll suave.
3. **Modo grid**: N columnas por fila (`Craft.Flex` no soporta wrap en `column` → lo resuelve
   el primitivo, no el layout de Craft).
4. **Cabeceras de grupo intercaladas**: filas heterogéneas (heading de categoría con "(n)" y
   colapso) mezcladas con ítems en el **mismo** stream virtualizado.
5. **Datos separados del render**: reconciliación/keying en `core/` (headless), pooling en
   `ui/` — ya es así en `each` (ADR-0004).

El requisito **(4) es el que decide la forma**: el invariante de `each` ("un `render`
homogéneo; render una vez, swap de datos") no puede expresar dos tipos de fila en un mismo
stream — una fila del pool horneada como "ítem" no puede volverse "cabecera" con solo cambiar
el dato. La composición pura tampoco: un `each` tiene un único `render`.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|---|---|---|
| A. Extender `each` con opts (`window`/`columns`/`rows`-por-tipo/`offset`) | un solo nombre; es como lo piensa el FR ("each con virtualización") | `each` se vuelve un cajón de sastre; el multi-tipo enturbia el invariante "render una vez, swap de datos" que hace a `each` simple y auditable |
| **B. Primitivo hermano `Weave.virtual` (elegida)** | `each` queda honesto a su contrato (listas chicas/DragList); el caso virtualizado tiene mecánica propia (pool fijo, scroll, grid, multi-tipo) sin contaminar `each`; comparte el reconciliador puro de `core/`; encaja con ADR-0004 y hace primer-clase el "virtualización = composición" | más superficie de API pública (dos primitivos de lista) |
| C. Solo helpers de composición (`each` intacto + helper de ventana) | mínimo; nada nuevo en el core | scroll fraccional, grid y sobre todo las cabeceras heterogéneas caen enteros en el consumidor — justo lo que el FR dice que "no basta" |

## Decisión

> **Añadimos `Weave.virtual(source, opts) → VirtualDescriptor`: un primitivo hermano de `each`
> en `ui/`, purpose-built para grids virtualizados grandes. `each` NO cambia.** La matemática de
> ventana/scroll/grid vive en `core/` (Lua puro, headless); el pool de frames y la
> materialización, en `ui/` — mismo reparto que `each`/`Reconcile` (ADR-0004).

Decisiones de forma (owner, 2026-07-09):

- **(a) Primitivo aparte, no opts de `each`.** Alternativa B. Cada primitivo cuenta una historia
  clara: `each` = lista dinámica chica con estado por fila; `virtual` = ventana fija sobre miles.
- **(b) Alturas conocidas (constraint de v1).** La ventana se calcula sin materializar todo → cada
  tipo de fila declara su alto (`rowHeight`; en Fase 2, alto por tipo de cabecera). Nada de medir
  contenido dinámico en v1.
- **(c) Scroll = señal externa que el consumidor alimenta (patrón ADR-0006).** `Weave.virtual`
  **no** va dentro de un `ScrollFrame` nativo (scrollear un hijo de miles de frames es justo lo
  que se evita). El scroll es una **posición** (píxeles, `0..max`):
  - `opts.scroll` = señal de posición que trae el consumidor (la barra de Craft la mueve);
    `virtual` solo la **lee**. Regla señal-o-literal.
  - `virtual:contentHeight()` = computed que `virtual` **expone** con el alto total de la lista
    completa → la barra de Craft dimensiona su thumb y su `max`.
  - Si `opts.scroll` se omite → `virtual` crea su propia señal y engancha la rueda del ratón (la
    demo y los consumidores sin Craft funcionan solos).
  - La rueda la engancha quien posee la barra: scroll externo (Craft) → Craft cablea la rueda.
  - Weave nunca menciona a Craft: comparten una señal (posición hacia dentro, `contentHeight`
    hacia fuera) — el patrón `applyOrBind` del ADR-0006, un nivel más adentro.
- **(d) Combat-safe idéntico a `each`.** Reusar/re-asignar/re-posicionar es combat-safe;
  materializar filas nuevas NO. El pool se dimensiona al viewport (fijo), así que en régimen no
  materializa nada al scrollear; si hace falta crecer en combate (viewport que crece), degrada +
  catch-up en `PLAYER_REGEN_ENABLED`, como `each`. `opts.warm` reservado igual.
- **(e) Degradación taint (ADR-0003).** Mismo criterio que `each`: un dato secreto fluye a los
  sinks que lo aceptan; su lectura numérica se marca; nunca un popup.

Entrega **por fases** (owner):

- **Fase 1 (release propia) — ventana + scroll fraccional + grid.** `render` **homogéneo** (un
  solo tipo de fila), `opts.columns` para grid, scroll por señal externa. Desbloquea el grid
  visual de bolsas de Coffer. Motor de ventana puro en `core/` (`Weave._windowPlan`).
- **Fase 2 (release siguiente) — cabeceras heterogéneas.** `opts.typeOf(entry)` + tabla `render`
  por tipo, con pool por tipo y alturas por tipo. Es la parte que dobla el invariante y va sola.

## Consecuencias

- (+) La lista virtualizada grande es de primera clase, sin sobrecargar `each` ni obligar al
  consumidor a reimplementar la matemática de scroll/grid.
- (+) `each` queda intacto y honesto a su contrato (auras, DragList): cero riesgo de regresión.
- (+) El motor de ventana (`core/`) es Lua puro y testeable headless, como `Reconcile`.
- (+) La integración con Craft es una señal compartida — Weave sigue sin conocer a Craft
  (ADR-0006). Coffer conecta la barra de Craft en dos líneas.
- (−) Dos primitivos de lista en la superficie pública (`each` y `virtual`) → se documenta cuándo
  usar cada uno en API-v0 §4 (regla: ¿miles de entradas con scroll? → `virtual`; ¿lista chica con
  estado por fila / DragList? → `each`).
- (−) Revierte la postura documentada "virtualización = composición, grids/scroll no son de each"
  de API-v0 §4 → se reescribe esa nota apuntando a `virtual`.
- Añade **M10** al roadmap (§9). AGENTS.md se actualiza en el mismo commit que este ADR.

## Validación / reversión

Acertada si Coffer migra su grid de bolsas manual (`List.lua` de Sorted) a `Weave.virtual` sin
perder funcionalidad y borrando su matemática de ventana/scroll propia, con la barra de Craft
alimentando `opts.scroll` y la prueba en combate pasando sin errores Lua. Reversible por fases:
si Fase 2 (cabeceras) se atasca, Fase 1 (grid homogéneo) ya entrega valor y se libera sola; el
FR queda parcialmente cubierto y las cabeceras vuelven al backlog sin coste para lo entregado.
