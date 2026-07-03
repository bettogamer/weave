# NORTH-STAR — Weave

## ⭐ El norte innegociable

**Señales, no VDOM. Lua 5.1 puro, cero toolchain. Los frames se crean una vez; el estado
fluye hacia ellos.** Weave hace UNA cosa — **el flujo reactivo de datos**: estado (store/
signals) → derivación (computeds) → vista (ui/binds) — y la hace tan simple que un dev
nuevo la aprende en una tarde. Cada piso es un módulo opcional (ADR-0004/0005).

- Ante cualquier duda de diseño de API, la pregunta guía es: **"¿cómo se siente esto en
  Fusion/Solid, y qué exige el motor de WoW?"** — se estudia el precedente y se adapta al
  sandbox (retained-mode, combat lockdown, GC, taint), no se copia ciego ni se inventa exotismo.
- **Prohibido desviarse** salvo decisión explícita del usuario:
  - **NO VDOM / diffing / re-render**: nada de crear-destruir árboles. Actualización
    fine-grained in-place, siempre.
  - **NO compilador ni transpiler** (TSTL, JSX, macros): si no corre pegando archivos `.lua`
    en la carpeta del addon, no es Weave. (Lección: react-wow-addon murió por esto.)
  - **NO capa OOP pesada** (estilo PLoop/Scorpio): la curva de aprendizaje es el enemigo #1
    de la adopción. Primitivas sueltas y componibles, no jerarquías de clases.
  - **NO framework total**: Weave no gestiona ciclo de vida de addon, ni slash commands, ni
    comunicación/red. Eso es AddonTemplate/Ace. El estado persistente SÍ es de Weave
    (`store` = SavedVariables reactivas, ADR-0005), porque el estado ES reactividad.
  - **El core NO conoce la API de WoW**: `signal/computed/effect/batch` son Lua puro
    (100% testeables con busted, sin mock). Solo la capa `wow/` toca frames y eventos.

## Qué incluye este norte (explícito)

- La API pública v0 (`docs/API-v0.md`): superficie mínima, nombres cortos, sin variantes
  redundantes.
- La estrategia taint-aware (ADR-0003): un secret value NUNCA crashea un effect — degrada
  al fallback declarado.
- Presupuesto de rendimiento: cero allocations de tabla en el hot path de actualización;
  computeds lazy; el costo de una señal que no cambia es cero.

## Desviaciones históricas (para no repetir)

| Fecha | Desviación | Costo | Corrección |
|-------|-----------|-------|------------|
| — | (ninguna todavía) | | |
