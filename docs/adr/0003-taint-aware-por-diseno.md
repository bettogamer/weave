# ADR-0003: Taint-aware por diseño — los secret values degradan, nunca crashean

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-07-02 |
| Alcance | core (señales) + capa wow |

## Contexto

En WoW 12.0+ las APIs de combate devuelven **secret values** en código tainted: operarlos
(aritmética, comparación, concat, key de tabla) lanza error. El flujo natural de Weave —
evento → señal → computed → bind — transporta exactamente esos valores hacia código que los
opera. Sin diseño explícito, cada computed sería una bomba. Ninguna librería reactiva
existente (Fusion, Solid) tiene este problema: es exclusivo de WoW, y por tanto una
oportunidad de diferenciación real. Ya existen patrones probados (chokepoint de Beacon,
fallback-a-default de MRT, guards quirúrgicos) y un linter propio (taintlint).

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| A. Ignorar (que el usuario se defienda) | core simple | todo addon Weave crashea en combate en 12.0+; inaceptable |
| B. Guard en cada primitiva (todo secret se filtra al entrar) | nada secreto circula | descarta datos útiles: APIs como `ColorCurve`/`Duration` SÍ aceptan secrets; guard amplio = features rotas (lección Beacon: "Announce funciona pero Timer no") |
| C. Fallback declarado + chokepoint | el dato secreto circula si puede usarse; degrada con valor declarado donde no; un solo punto de manejo de errores | algo más de superficie de API (`fallback`, `isSecret`) |

## Decisión

> **Elegimos C, en tres piezas:**
> 1. **Shim estándar** al cargar: `issecretvalue`/`issecrettable` con fallback a
>    `function() return false end` (clientes viejos).
> 2. **Fallback declarado por señal**: `Weave.signal(v, { fallback = x })` — si `set()`
>    recibe un secret, la señal expone `fallback` a los lectores y marca `s:isSecret()`.
>    Sin fallback declarado, el secret circula tal cual (para sinks que lo aceptan).
> 3. **Chokepoint en effects/binds**: todo effect corre bajo un handler que detecta errores
>    de secret (`"a secret"` / `"ForceTaint_Strong"`) → degrada ese effect (aviso soft una
>    vez, no popup) en vez de propagar. Patrón Beacon `waErrorHandler`, probado en producción.

## Consecuencias

- (+) Un addon Weave no puede crashear por secrets: o usa el fallback o degrada el effect.
- (+) taintlint puede aprender reglas específicas de Weave (futuro FR a taintlint).
- (−) Semántica sutil: documentar con ejemplos QUÉ ve un computed cuando la fuente es
  secreta (el fallback, no el secret) — tabla de verdad en API-v0.
- (−) El chokepoint intercepta errores: cuidar que los errores NO-secret se propaguen intactos.

## Validación / reversión

Demo obligatoria: barra de vida con `UnitHealth` bajo ForceTaint (macro `/run` con
loadstring) — debe mostrar el fallback sin un solo error Lua. Si el manejo resulta
insuficiente en la práctica, escalar a wrappers per-API (estilo `Compat12.lua`) sin
cambiar la API pública.
