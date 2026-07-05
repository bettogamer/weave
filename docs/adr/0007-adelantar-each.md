# ADR-0007: Adelantar `Weave.each` — pasa a ser M6; los docs para devs nuevos se corren a M7

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-07-05 |
| Alcance | roadmap (reordena M6/M7); adelanta la pieza W2 de v1 a la v0.2.0 |
| Decisor | owner (Alberto) |

## Contexto

El ADR-0005 dejó `Weave.each` (W2: listas reactivas con frame pooling combat-safe) fuera
de v0, para después de cerrar el roadmap M0–M6. Tras la release v0.1.0, **dos consumidores
reales chocaron con ese límite la misma semana**: el addon **Coffer** (lista virtualizada
de ítems, hoy implementada a mano con el patrón `List.lua` de Sorted, con señales solo en
los bordes) y la **integración de Craft** (ADR-0006). Es exactamente la señal que el
backlog dice esperar ("las mejores ideas salen de USAR Weave, no de imaginar"): demanda
real, con casos de uso concretos contra los que diseñar en vez de hacerlo en abstracto.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| A. Seguir el plan (M6 = docs; `each` después) | roadmap intacto; Coffer no está bloqueado (tiene el patrón manual) | los dos consumidores siguen con listas a mano; `each` se diseñaría más tarde SIN sus casos frescos |
| B. Adelantar `each` como nuevo M6; docs → M7 | se diseña contra dos casos reales; Coffer/Craft migran antes; el tutorial de M7 sale mejor (puede mencionar listas) | los docs para devs nuevos se retrasan un hito |
| C. Intercalar (diseño de `each` + docs en paralelo) | avanza todo | dispersa el foco; contra el modo de trabajo por bloques del proyecto |

## Decisión

> **Elegimos B. `Weave.each` se adelanta y pasa a ser el M6 del roadmap; los docs para
> devs nuevos (tutorial + README) pasan a M7.**
>
> - La etiqueta "v1" del ADR-0005 se lee como "post-v0.1": `each` entra en la
>   **release v0.2.0** (superficie nueva = bump MINOR de semver y de LibStub).
> - El diseño se hace **contra los casos reales** de Coffer (lista virtualizada de ítems)
>   y de la integración de Craft; la spec nueva se añade a `docs/API-v0.md` antes de los
>   tests (proceso TDD-con-aprobación de siempre).
> - Reparto por capas conforme al ADR-0004: la reconciliación/keying que sea Lua puro va
>   en `core/` (testeable headless sin mock); el pooling de frames y la materialización,
>   en `ui/`.
> - Verificación del hito: suite headless + demo in-game con lista dinámica + prueba
>   ForceTaint + prueba EN combate (el pool recicla, jamás crea; si se agota, degrada con
>   aviso — mismo espíritu que los secrets).

## Consecuencias

- (+) `each` se diseña con dos consumidores reales esperándolo — validación inmediata.
- (+) Coffer y Craft migran sus listas manuales a un build etiquetado (`v0.2.0`) antes.
- (−) El tutorial "tu primer addon reactivo" y el README se retrasan un hito (M7).
- El roadmap queda: **M6 = `Weave.each` + release v0.2.0** · **M7 = docs para devs
  nuevos**. API-v0 §8/§9 y AGENTS.md se actualizan en este mismo commit.

## Validación / reversión

Acertada si Coffer migra su lista manual (`List.lua`) a `Weave.each` sin perder
funcionalidad y borrando código propio, y la prueba en combate pasa sin errores Lua.
Reversible: si el diseño se atasca, M7 (docs) no depende de `each` — se retoma el orden
del ADR-0005 sin coste.
