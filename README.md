# Weave — reactividad por señales para addons de WoW

> **Estado: DISEÑO (v0).** Nada de código todavía — primero el modelo (ver `docs/`).
>
> Weave es una librería de **reactividad fine-grained por señales** (estilo
> [Fusion](https://github.com/dphfox/Fusion) de Roblox / SolidJS) en **Lua 5.1 puro**,
> para addons de World of Warcraft. Cubre el flujo completo de una app moderna:
> **estado persistente** (`store` = SavedVariables reactivas) → **derivaciones**
> (`computed`) → **vista declarativa** (`Weave.new`/`bind`). Los frames se crean una vez,
> y cada cambio actualiza solo la propiedad exacta que depende de él. (Alcance: ADR-0005.)

```lua
local hp    = Weave.signal(100)
local color = Weave.computed(function() return hp() < 30 and RED or GREEN end)

Weave.bind(bar, "value", hp)              -- bar:SetValue(...) solo cuando hp cambia
Weave.bind(bar, "statusBarColor", color)

Weave.fromEvent("UNIT_HEALTH", "player", function(unit)
  hp:set(UnitHealth(unit))                -- evento WoW → señal (taint-aware)
end)
```

## Por qué señales y no React/VDOM

Los frames de WoW son retained-mode: caros de crear, **imposibles de crear en combate**, y
el GC de Lua castiga el churn de tablas de un VDOM. Las señales actualizan in-place, que es
exactamente lo que los addons ya hacen a mano con spaghetti de callbacks — Weave lo automatiza.
Detalle: `docs/adr/0001`.

## El stack completo (visión)

| Pieza | Rol | Análogo web |
|-------|-----|-------------|
| **Craft** | componentes UI | shadcn |
| **Weave** | estado reactivo | SolidJS/signals |
| **taintlint** | análisis estático | ESLint |
| **AddonTemplate** | estándar de proyecto | create-app |

Piezas independientes y adoptables por separado (no un framework monolítico — ADR-0004).

## Documentación

- [docs/NORTH-STAR.md](docs/NORTH-STAR.md) — el norte innegociable
- [docs/adr/](docs/adr/) — decisiones fundacionales (0001–0004)
- [docs/API-v0.md](docs/API-v0.md) — spec de la API v0 (lo que se implementará)

## Licencia

**MIT** (como Craft y Fusion) — libre de embeberse en cualquier addon, incluidos los GPL.
Sin código heredado de WeakAuras ni de terceros: reimplementación desde cero.

## Nombre

"Weave" (tejer): pareja temática con Craft, hilos de estado que se tejen en la UI, corto para
LibStub (`"Weave-1.0"`). Alternativas consideradas si hay colisión: Loom, Filament, Strand.
