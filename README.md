# Weave — reactividad por señales para addons de WoW

> **Estado: IMPLEMENTADO (v0.3.0).** `core` · `wow` · `store` · `ui` (`Weave.new`,
> `Weave.each`) completos y verificados in-game. 192 tests headless en verde.
> API pública estable en [`docs/API-v0.md`](docs/API-v0.md).

Weave es una librería de **reactividad fine-grained por señales** (estilo
[Fusion](https://github.com/dphfox/Fusion) de Roblox / SolidJS) en **Lua 5.1 puro**, para
addons de World of Warcraft. Cubre el flujo completo de una app moderna: **estado
persistente** (`store` = SavedVariables reactivas) → **derivaciones** (`computed`) →
**vista declarativa** (`Weave.new` / `bind`). Los frames se crean una vez, y cada cambio
actualiza solo la propiedad exacta que depende de él. Sin toolchain, sin VDOM,
taint-aware por diseño.

```lua
local W = LibStub("Weave-1.0")

-- ESTADO: una señal alimentada por un evento del juego
local money = W.fromEvent("PLAYER_MONEY",
  function() return GetMoney() end, { initial = GetMoney() })

-- DERIVACIÓN: se recalcula sola cuando `money` cambia
local label = W.computed(function() return GetCoinTextureString(money()) end)

-- VISTA: descrita una vez; `text` queda enchufado a la derivación
W.new("FontString", {
  parent = UIParent, layer = "OVERLAY", template = "GameFontNormalLarge",
  point = { "CENTER", 0, 200 },
  text = label,               -- una señal en una prop = bind automático
})
```

Ese addon muestra tu oro en pantalla y se actualiza solo — cero manejadores de eventos a
mano. Construido paso a paso en el **[tutorial](docs/TUTORIAL.md)**.

## Empieza aquí

- **[Tutorial: tu primer addon reactivo](docs/TUTORIAL.md)** — de cero a un addon funcional
  en 15 líneas, explicando los tres pisos (estado → derivación → vista). Para dev novato.
- **[docs/API-v0.md](docs/API-v0.md)** — la superficie pública completa, con su semántica
  exacta (taint incluido). Los tests se escriben contra ella.
- **[demo/WeaveDemo/](demo/WeaveDemo/)** — demos ejecutables in-game: barra de vida con
  estado persistente (`Demo.lua`) y lista dinámica con pooling (`EachDemo.lua`).

## Por qué señales y no React/VDOM

Los frames de WoW son retained-mode: caros de crear, **imposibles de crear en combate**, y
el GC de Lua castiga el churn de tablas de un VDOM. Las señales actualizan in-place, que es
exactamente lo que los addons ya hacen a mano con spaghetti de callbacks — Weave lo
automatiza. Y como los frames solo mutan (nunca se crean) al reaccionar, los binds son
seguros en combate por diseño. Detalle: [ADR-0001](docs/adr/0001-senales-fine-grained-no-vdom.md).

## Qué incluye v0

| Capa | Piezas | Estado |
|------|--------|--------|
| **core** | `signal` · `computed` · `effect` · `batch` · `scope` · `isReactive`/`isWritable` | Lua puro, cero API de WoW |
| **wow** | `fromEvent` · `fromUnitEvent` · `bind` · `onUpdate` · registro de props | taint-aware (ADR-0003) |
| **store** | `store` — SavedVariables reactivas, anidadas, con migraciones | persistencia declarativa |
| **ui** | `Weave.new` (vista declarativa) · `Weave.each` (listas con pooling combat-safe) | frames se crean una vez |

## El stack completo (visión)

| Pieza | Rol | Análogo web |
|-------|-----|-------------|
| **Craft** | componentes UI | shadcn |
| **Weave** | estado reactivo | SolidJS/signals |
| **taintlint** | análisis estático | ESLint |
| **AddonTemplate** | estándar de proyecto | create-app |

Piezas independientes y adoptables por separado (no un framework monolítico —
[ADR-0004](docs/adr/0004-core-independiente-capas-adoptables.md)). Craft embebe Weave
nativamente ([ADR-0006](docs/adr/0006-craft-integra-weave-nativamente.md)); ver
[docs/CRAFT-INTEGRATION.md](docs/CRAFT-INTEGRATION.md) para autores de componentes.

## Documentación

- [docs/TUTORIAL.md](docs/TUTORIAL.md) — tu primer addon reactivo, paso a paso.
- [docs/API-v0.md](docs/API-v0.md) — spec de la API v0 (la superficie pública).
- [docs/NORTH-STAR.md](docs/NORTH-STAR.md) — el norte innegociable (señales/no-VDOM, cero toolchain).
- [docs/adr/](docs/adr/) — decisiones fundacionales (0001–0007).
- [docs/CRAFT-INTEGRATION.md](docs/CRAFT-INTEGRATION.md) — guía de embebido para Craft.
- [docs/BACKLOG.md](docs/BACKLOG.md) — ideas futuras (v1+).

## Licencia

**MIT** (como Craft y Fusion) — libre de embeberse en cualquier addon, incluidos los GPL.
Sin código heredado de WeakAuras ni de terceros: reimplementación desde cero.

## Nombre

"Weave" (tejer): pareja temática con Craft, hilos de estado que se tejen en la UI, corto
para LibStub (`"Weave-1.0"`).
