# ADR-0005: Alcance ampliado — arquitectura completa en módulos opcionales (ui + store en v0)

| | |
|---|---|
| Estado | **Aceptada** (decisión del owner, 2026-07-02) |
| Fecha | 2026-07-02 |
| Alcance | superficie pública y roadmap |

## Contexto

El diseño inicial limitaba v0 a señales + bindings ("core + wow"). Feedback del owner: las
señales solas "ayudan un poco" — la meta es que un dev nuevo tenga **la arquitectura
completa** de una app moderna, no solo el cimiento. Lo que hace sentir "arquitectura" a
React/Solid son los pisos sobre las señales: vista declarativa, estado central persistente,
listas dinámicas. Fusion (precedente en Lua) incluye exactamente esos pisos (`New`,
`ForPairs`). El riesgo a controlar es el del ADR-0004: no volvernos Scorpio (monolito).

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| A. Core mínimo (solo señales+bind) | pequeño, rápido de terminar | "ayuda un poco": el dev sigue creando frames a mano y sincronizando su DB a mano |
| B. Arquitectura completa como módulos opcionales | flujo unidireccional completo (evento→store→computed→UI declarativa); cada piso adoptable por separado | más superficie que diseñar/testear; release v0 más lejos |
| C. Framework integrado | todo resuelto | contradice ADR-0004 y el north-star |

## Decisión

> **Elegimos B. El alcance queda así:**
>
> - **v0**: core + wow + **`ui/` (W1: creación declarativa de frames, estilo Fusion `New`)**
>   + **`store/` (W3: SavedVariables reactivas con migraciones)** + craft opcional.
> - **v1**: `each` (W2: listas reactivas con frame pooling combat-safe).
> - **v2**: DevTools in-game `/weave` (W4) y utilidades de tiempo `throttle/debounce/delay` (W5).
>
> Cada piso es un módulo separado que solo depende de los de abajo; quien quiera solo
> señales usa solo señales (se preserva ADR-0004).

## Consecuencias

- (+) Weave cubre vista + estado + reactividad: soporte real de "arquitecturas nuevas"
  (flujo de datos unidireccional) para devs nuevos.
- (−) El north-star decía "Weave no gestiona DB": se ajusta — el estado persistente ES
  estado reactivo (store), lo que sigue fuera es ciclo de vida/slash/eventos no reactivos.
  (NORTH-STAR actualizado en este mismo commit.)
- (−) v0 crece: el roadmap pasa de 5 a 7 hitos (M0–M6). Asumido conscientemente.
- `ui/` crea frames → restricción de combate explícita: creación declarativa solo fuera de
  combate; los binds (mutación) siguen siendo combat-safe.

## Validación / reversión

Acertada si el tutorial "tu primer addon reactivo" (M6) usa los tres pisos y cabe en <60
líneas. Si `ui/` o `store/` retrasan indefinidamente el release, se recortan a v1 sin tocar
core/wow (los módulos son independientes — esa es la prueba del ADR-0004).
