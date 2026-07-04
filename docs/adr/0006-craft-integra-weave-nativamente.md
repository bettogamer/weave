# ADR-0006: Craft integra Weave nativamente — se elimina la capa `craft/` de Weave

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-07-03 |
| Alcance | integración Weave↔Craft; redefine M5/M6 del roadmap; sustituye API-v0 §6 |
| Decisor | owner (Alberto) — decisión de dirección propuesta por él |

## Contexto

El plan original (ADR-0004, API-v0 §6) era una capa opcional `Weave/craft/` con
"adaptadores": entradas del registro de props que traducen `value`/`checked`/`text` a la
API pública de cada componente Craft. Al ir a ejecutarla (M5), el owner objetó el enfoque:
los adaptadores son **traducción perpetua** — cada componente nuevo de Craft necesita su
adaptador en Weave, cada cambio de API puede romperlos en silencio, y Weave queda
"conociendo" a Craft para siempre. Su propuesta: que **Craft integre Weave nativamente**
(los componentes nacen reactivos, aceptando señales como props), embebiendo Weave como
librería vendoreada — el modelo shadcn/React: los componentes se construyen SOBRE el
runtime reactivo, no se adaptan a él a posteriori.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| A. Capa `craft/` en Weave (adaptadores; plan ADR-0004) | Craft no cambia; Weave controla la integración | traducción perpetua; acoplamiento informativo Weave→Craft; los adaptadores persiguen la API de Craft eternamente |
| B. Craft embebe Weave y sus componentes la usan nativamente | componentes nacidos reactivos; Weave queda 100% ignorante de Craft (dependencia unidireccional Craft→Weave, como Craft→LibStub); una sola historia para el consumidor | Craft pasa a depender de Weave (acopla releases → mitigado con builds etiquetados); el trabajo de integración vive en el repo de Craft |

## Decisión

> **Elegimos B. La capa `craft/` se ELIMINA del alcance de Weave.**
>
> - Weave no sabrá nunca que Craft existe. La dependencia es unidireccional:
>   Craft vendorea un **build etiquetado** de Weave en `Craft/libs/Weave/`
>   (mismo modelo Ace3/LibStub; la regla global de vendoring aplica un nivel más adentro).
> - **Condición dura**: Craft solo embebe releases etiquetadas (tag semver `v*`, MINOR de
>   LibStub bumpeado), jamás un snapshot de `dev`. Primero Weave congela superficie y corta
>   v0.1; después Craft integra.
> - El trabajo en los componentes lo hace el owner EN el repo de Craft, con su proceso.
>   Weave entrega: (1) el paquete embebible + script de build, (2) la **guía de
>   integración** para el autor de componentes (embed, patrón señal-o-literal, scopes por
>   ciclo de vida, reglas taint), (3) la release v0.1.
> - Coexistencia: LibStub resuelve copias múltiples (Craft embebida + standalone) — gana
>   la de MINOR más alto; las demás se apagan con el guard `if not Weave then return end`.

## Consecuencias

- (+) Weave más limpia: una capa menos, cero conocimiento de Craft, el north-star
  ("piezas componibles, no monolito") reforzado.
- (+) La reactividad en Craft es de primera clase (prop = señal), no un traductor aparte.
- (−) Craft acopla su ciclo de release al de Weave → mitigación: builds etiquetados +
  semver + guía de migración cuando la superficie cambie.
- (−) Bugs de Weave se manifiestan como bugs de Craft → mitigación: la suite headless de
  Weave (153 tests) y el flujo FR/issue del repo de Weave.
- El roadmap cambia: **M5 = paquete embebible + guía + release v0.1** (absorbe el viejo
  M6); la página demo en Craft_Browser pasa a ser criterio de éxito del trabajo del owner
  en Craft, fuera de este repo. API-v0 §6 queda sustituida por referencia a este ADR.

## Validación / reversión

Acertada si el owner actualiza su primer componente Craft (señal como prop) usando SOLO la
guía, sin preguntas, y la página demo de Craft_Browser funciona con la Weave embebida.
Reversible: la capa de adaptadores (plan A) puede añadirse después sin tocar el core —
nada de esta decisión cierra esa puerta.
