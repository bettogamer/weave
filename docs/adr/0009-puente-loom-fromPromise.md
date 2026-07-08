# ADR-0009: `Weave.fromPromise` — el puente con Loom lo posee Weave (M9)

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-07-07 |
| Alcance | roadmap (añade M9); nueva dependencia unidireccional Weave→Loom; añade `Weave.fromPromise`, `Weave.pending`, `Weave.rejected` a la API pública |
| Decisor | owner (Alberto) |

## Contexto

**Loom** (`Workspace/loom`) es la lib hermana del stack: cubre **datos que llegan tarde** —el
patrón "dispara petición → espera el evento → resuelve una vez" que impregna la API de WoW
(`Loom.item`/`spell`/`inspect`)— como **promesas componibles** one-shot. Está en **v0.1.0,
verificada in-game en 12.0.7**. Comparte nuestro ADN: core puro + capa `wow/` adoptable,
taint-aware con detector inyectado, chokepoint de degradación, Lua 5.1 puro, LibStub.

La frontera Loom↔Weave está definida en ambos lados y es limpia: **one-shot vs stream**. Un
dato que llega una vez y se estabiliza (item info) es de Loom; algo que cambia sin parar (health)
es de `Weave.fromEvent`. Ver Loom API-v0 §4.

Loom **ya decidió, en su ADR-0010, que el puente promesa→señal lo posee Weave, no Loom**: Loom no
conoce a Weave en ninguna capa y no expone `Loom.signal` ni módulo `weave/`. La razón es el
precedente directo de **nuestro ADR-0006** (Craft integra Weave, no al revés): *el consumidor de
la reactividad posee la integración*. La misma fuerza aplica un nivel más adentro — Weave es el
consumidor de la promesa de Loom, así que Weave construye la señal.

Clave habilitante: **Loom no necesita código especial.** Una promesa de Loom ya expone por su API
**pública** todo lo necesario — `p:next(onOk, onErr)`, `p:status()`, `p:isSecret()` — y Weave
construye la señal consumiendo esa superficie, sin tocar internos `_` de Loom.

## Decisión

> **Añadimos `Weave.fromPromise(promise, opts?)`: gemelo one-shot de `Weave.fromEvent`. Convierte
> una promesa de Loom en una señal read-only. Weave depende de la API PÚBLICA de la promesa;
> Loom permanece 100% ignorante de Weave (dependencia unidireccional Weave→Loom, como Weave→WoW).**

Semántica, con las tres decisiones del owner (2026-07-07):

- **(a) Centinela `pending`.** La señal arranca en `Weave.pending` —una tabla centinela pública y
  estable, comparable por identidad— mientras la promesa no ha asentado. Distinguible de un `nil`
  o de cualquier dato real. Al cumplirse, la señal se actualiza al valor de la promesa.
- **(b) Rechazo vía centinela `rejected` + `onError`.** Si la promesa se rechaza, la señal pasa a
  `Weave.rejected` (otra tabla centinela) y —si el llamante pasó `opts.onError`— se invoca
  `opts.onError(reason)` con el motivo estructurado de Loom (`{ code, message }`). Loom deja
  explícitamente a Weave cómo exponer el rechazo (su ADR-0010); elegimos un centinela simétrico a
  `pending` para que la vista pueda ramificar declarativamente (skeleton / valor / error) sin
  callbacks obligatorios, y un `onError` opcional para efectos imperativos (log, toast).
- **(c) Cancelación por scope.** `Weave.fromPromise` se ata al scope activo (`_attachToScope`,
  como todo binding/effect). Al `scope:dispose()`, la señal se limpia **y se llama `p:cancel()`**
  en la promesa: por la cancelación estructural de Loom (su ADR-0011) eso desregistra el evento
  subyacente → **cero leak de listeners**. Coherente con cómo Weave ya limpia binds/effects.

Degradación taint (ADR-0003, mismo criterio que `fromEvent`): si el valor resuelto es secret, se
consulta `p:isSecret()` y la señal degrada con el patrón de siempre (el valor secreto fluye a los
sinks que lo aceptan; la lectura numérica se marca). Un `onOk`/map que opere un secret degrada esa
actualización sin romper, warning una vez.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|---|---|---|
| A. `opts.initial` sin centinela (como fromEvent) | mínimo; reusa el patrón | no distingue "cargando" de "resolvió a ese valor"; la vista no puede mostrar skeleton fiable |
| B. Estado envuelto `{status,value,error}` siempre | un solo objeto cubre pending+valor+rechazo | el consumidor desempaqueta SIEMPRE, incluso el 90% que solo quiere el valor; más verboso que el resto de Weave |
| **C. Centinelas `pending`/`rejected` + `onError` (elegida)** | la vista ramifica por identidad (`== W.pending`); el caso feliz es el valor pelado; rechazo cubierto sin obligar handler | dos centinelas nuevos en la superficie pública |
| Puente en Loom (`Loom.signal`) | Loom controlaría el puente | rechazada por Loom ADR-0010 (Loom conocería a Weave); contradice el norte de ambos |

## Consecuencias

- (+) La reactividad a partir de una promesa es de primera clase en Weave (`fromPromise` junto a
  `fromEvent`), una sola historia de reactividad para el consumidor del stack.
- (+) Loom queda intacto: cero código de integración, adoptable sin Weave. La dependencia es
  unidireccional y se apoya solo en superficie pública versionada con LibStub.
- (+) Nuevo primitivo pequeño y aislado en `wow/` — no toca el core ni `ui/`.
- (−) Weave acopla este feature al ciclo de release de Loom → mitigación: Weave vendorea un build
  **etiquetado** de Loom (regla global de vendoring) y, si falta un gancho en la API pública de la
  promesa, es un **FR a Loom**, no se hackean internos `_`.
- (−) Dos centinelas nuevos (`Weave.pending`, `Weave.rejected`) en la API pública → se documentan
  en API-v0 §2 y se versionan.
- Añade **M9** al roadmap (§9). Requiere Loom cargado en runtime; sin Loom, `fromPromise` no aplica
  (Weave sigue siendo adoptable sin Loom — el feature simplemente no se usa).

## Validación / reversión

Acertada si un boundary "skeleton hasta resolver" funciona in-game consumiendo SOLO la API pública
de una promesa de Loom (`Loom.item(id)` → `Weave.fromPromise` → bind con ramas
pending/valor/rechazo), sin tocar internos de Loom, y `scope:dispose()` desregistra el evento
subyacente (cero leak verificado). Señal de error: si Weave necesita repetidamente ganchos que la
API pública de la promesa no da → FR a Loom (reversible: la forma del puente no cambia, solo se
amplía el contrato de Loom).
