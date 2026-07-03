# Weave — Especificación de API v0

> Spec de diseño: esto es lo que se implementará y contra lo que se escriben los tests.
> Cambios a esta superficie → actualizar aquí + ADR si es decisión de fondo.
> Convención: `s()` lee (y trackea), `s:set(v)` escribe, `s:peek()` lee sin trackear.
>
> Alcance v0 por ADR-0005: **core + wow + ui + store** (+ craft opcional).
> El flujo completo: `evento del juego → store/signals → computeds → UI declarativa`.

## 1. Core (`Weave/core/` — Lua puro, cero API de WoW)

### `Weave.signal(initial, opts?) → Signal`

Estado mutable raíz.

```lua
local hp = Weave.signal(100)
hp()          -- → 100 (lectura; dentro de computed/effect registra dependencia)
hp:set(80)    -- escribe; notifica solo si el valor cambió
hp:peek()     -- lectura SIN tracking (para código no reactivo)
```

- `opts.fallback` — valor a exponer si `set()` recibe un secret value (ver §3).
- `opts.equals(a, b)` — comparador custom; default: `==` protegido (si comparar lanza —
  secrets — se asume "cambió").
- `s:isSecret()` — true si el último `set()` fue un secret (y hay fallback activo).

### `Weave.computed(fn, opts?) → Computed`

Valor derivado read-only. **Lazy** (se evalúa al leerse) y **cacheado** (memoiza hasta que
una dependencia cambie). Auto-tracking: toda señal leída dentro de `fn` es dependencia.

```lua
local pct = Weave.computed(function() return hp() / hpMax() end)
```

- `opts.fallback` — valor expuesto si `fn` degrada por secrets (§3).
- Los computeds pueden leer otros computeds (grafo). Ciclos → error claro en dev.

### `Weave.effect(fn) → EffectHandle`

Side effect reactivo: corre inmediatamente y se re-ejecuta cuando cambia cualquier
dependencia leída. **Es el único sitio donde el mundo exterior se entera de los cambios.**

```lua
local h = Weave.effect(function() bar:SetValue(pct() * 100) end)
h:dispose()   -- deja de reaccionar (idempotente)
```

### `Weave.batch(fn)`

Agrupa escrituras: los effects corren UNA vez al final, no por cada `set()`.

```lua
Weave.batch(function() hp:set(50); hpMax:set(200) end)  -- pct notifica 1 vez
```

### `Weave.scope() → Scope` · `scope:run(fn)` · `scope:dispose()`

Ownership de effects/binds (WoW no tiene unmount: el disposal es explícito). Todo effect,
bind o elemento `ui` creado dentro de `scope:run(fn)` queda adscrito al scope;
`dispose()` los libera todos. Patrón: un scope por panel/página, dispuesto al cerrar/reciclar.

### Reglas de rendimiento (contrato, no sugerencia)

- Cero allocations de tabla en el hot path de `set()`→notificación (dep-sets reutilizados).
- Una señal sin suscriptores cuesta una comparación por `set()`.
- `equals` corta la propagación: `set()` con el mismo valor no notifica nada.

## 2. Capa WoW (`Weave/wow/` — eventos y bindings)

### `Weave.fromEvent(event, map?, opts?) → Signal` · `Weave.fromUnitEvent(event, unit, map?, opts?) → Signal`

Señal alimentada por un evento del juego. Un frame interno compartido multiplexa los
eventos globales; los eventos de unidad usan un frame por par (evento, unit), porque
`RegisterUnitEvent` admite máximo 2 units por frame. `map(...)` transforma los args del
evento en el valor de la señal (default: primer arg).

- `opts` = las opts de signal (`fallback`, `equals` — taint-aware, §3) + `initial`:
  valor de arranque de `fromEvent` antes del primer evento (default `nil`).
- `fromUnitEvent` se **siembra** al crearse (llama `map(unit)` una vez) para que el
  valor exista antes del primer evento — por eso no necesita `initial`.

```lua
local hp = Weave.fromUnitEvent("UNIT_HEALTH", "player",
  function(unit) return UnitHealth(unit) end,
  { fallback = 0 })                    -- opts de signal aplican (taint-aware)
```

### `Weave.bind(frame, prop, source) → EffectHandle`

Azúcar sobre `effect`: conecta una señal/computed (o cualquier llamable) a una propiedad
del frame vía el registro de props. **Nunca crea frames** (combat-safe; el frame ya
existe). Las props de varios args (`minMax`, `vertexColor`, `statusBarColor`) reciben una
tabla y la desempaquetan: `W.signal({ 0, 1 })` → `SetMinMaxValues(0, 1)`.

```lua
Weave.bind(bar, "value", pct)
Weave.bind(icon, "shown", visible)
```

Props built-in v0: `text`, `value`, `minMax`, `shown`, `alpha`, `width`, `height`,
`texture`, `vertexColor`, `statusBarColor`. Extensible:

```lua
Weave.props.register("glow", function(frame, v) --[[ aplicar ]] end)
```

### `Weave.onUpdate(interval) → Signal`

Señal de tiempo throttleada (ticker compartido) para countdowns/duraciones. `interval` en
segundos (mín. efectivo ~0.05). Solo tickea si tiene suscriptores vivos.

### Chokepoint de errores (automático, ADR-0003)

Todo effect/bind corre bajo un handler: error cuyo mensaje contiene `"a secret"` o
`"ForceTaint_Strong"` → ese effect degrada (una advertencia soft por sitio, no popup, y el
computed fuente expone su `fallback` si lo tiene). Cualquier otro error se propaga intacto.

## 3. Semántica taint (tabla de verdad — ADR-0003)

| Situación | Qué ven los lectores | `isSecret()` |
|-----------|----------------------|--------------|
| `set(v)` normal | `v` | false |
| `set(secret)` con `fallback` declarado | `fallback` | true |
| `set(secret)` sin `fallback` | el secret tal cual (para sinks que aceptan secrets: `Duration`, `ColorCurve`) | true |
| computed cuya `fn` crashea por secret | su `fallback` (o el último valor bueno si no hay) | true |

Shim al cargar la lib: `issecretvalue`/`issecrettable` → `function() return false end` si no
existen (clientes pre-12.0).

Enganche interno core↔wow: **`Weave._setSecretDetector(fn)`** — el core (Lua puro) no puede
llamar `issecretvalue`; la capa `wow/` se lo inyecta al cargar. Sin inyección, nada es
secret (default seguro). La degradación de computeds reconoce los errores del cliente por
su texto (`"a secret"` / `"ForceTaint_Strong"`), patrón chokepoint de ADR-0003; cualquier
otro error se propaga intacto.

## 4. UI declarativa (`Weave/ui/` — W1, ADR-0005)

### `Weave.new(frameType, props) → frame`

Crea el frame Y aplica/bindea props en una sola descripción (estilo Fusion `New`). Valor
literal → se aplica una vez; señal/computed → queda bindeado.

```lua
local bar = Weave.new("StatusBar", {
  size   = { 200, 20 },
  point  = { "CENTER" },
  minMax = { 0, 1 },
  value  = pct,                              -- señal → bind automático
  statusBarColor = barColor,                 -- computed → bind automático
  [Weave.children] = {
    Weave.new("FontString", { layer = "OVERLAY", point = { "CENTER" }, text = hpText }),
  },
  [Weave.on] = { OnMouseDown = function(self) ... end },   -- scripts
})
```

- Usa el MISMO registro de props que `bind` (una sola verdad de cómo se aplica cada prop).
- Props especiales de creación: `parent` (default `UIParent`), `template`, `name`,
  `size`, `point`/`points`, `layer` (para regiones), `[Weave.children]`, `[Weave.on]`.
- **Restricción de combate (dura):** `Weave.new` con `InCombatLockdown()` → error claro en
  dev / no-op con warning en producción. La creación declarativa es para construcción de UI
  fuera de combate; EN combate solo mutan los binds. (Listas dinámicas en combate → `each`
  con pooling, v1.)
- Elementos creados dentro de un `scope:run()` quedan adscritos al scope (sus binds se
  liberan con él; el frame se oculta y queda reutilizable).

## 5. Estado persistente (`Weave/store/` — W3, ADR-0005)

### `Weave.store(svName, defaults, opts?) → Store`

SavedVariables reactivas: cada campo es una señal; escribir persiste (WoW guarda al logout);
la UI enchufada se actualiza en vivo.

```lua
-- El .toc declara: ## SavedVariables: MiAddonDB
local db = Weave.store("MiAddonDB", {
  enabled = true,
  scale   = 1.0,
  bar     = { width = 200, locked = false },   -- tablas anidadas → sub-stores
}, {
  version = 2,
  migrate = function(raw, oldVersion) ... end, -- patrón _version del estándar, automatizado
})

db.scale()                 -- lee (trackea): 1.0
db.scale:set(1.2)          -- actualiza la UI enchufada Y persiste
db.bar.width:set(240)      -- anidado igual
Weave.bind(frame, "scale", db.scale)
```

- **Timing:** el store se hidrata en `ADDON_LOADED` del addon dueño; `Weave.store` puede
  llamarse antes (devuelve defaults y re-sincroniza al hidratar). Recomendación estándar:
  crearlo en el `ADDON_LOADED` de `Core.lua`.
- **Defaults sin pisar** lo guardado; claves guardadas que ya no están en defaults se
  preservan (datos del usuario nunca se borran — regla del estándar).
- `db._raw` — acceso de escape a la tabla SavedVariables cruda (para export/debug).
- Solo tipos serializables por WoW (boolean/number/string/table). Señales con valores no
  serializables NO van en un store.

## 6. Capa Craft (`Weave/craft/` — OPCIONAL, ADR-0004)

Registra props bindables para componentes Craft (detecta `LibStub("Craft-1.0", true)`; no-op
si falta). v0 mínimo: `text` de Label/Button, `value` de Slider, `checked` de Checkbox,
`disabled` genérico. Si un componente Craft no expone setter público para algo bindable →
**FR a Craft** (proceso estándar), no hack de internos.

## 7. Ejemplo completo (la demo canónica, con los tres pisos)

```lua
local W = LibStub("Weave-1.0")

-- ESTADO (store persistente + señales de eventos)
local db  = W.store("MiAddonDB", { locked = false, width = 200 }, { version = 1 })
local hp    = W.fromUnitEvent("UNIT_HEALTH",   "player", function(u) return UnitHealth(u) end,    { fallback = 0 })
local hpMax = W.fromUnitEvent("UNIT_MAXHEALTH","player", function(u) return UnitHealthMax(u) end, { fallback = 1 })

-- DERIVACIONES
local pct   = W.computed(function() return hp() / math.max(hpMax(), 1) end, { fallback = 0 })
local color = W.computed(function() return pct() < 0.3 and {1,.2,.2} or {.2,.8,.2} end)

-- VISTA (declarativa; se crea una vez, fuera de combate)
W.new("StatusBar", {
  size = { db.width, 20 }, point = { "CENTER" }, minMax = { 0, 1 },
  value = pct, statusBarColor = color,
  [W.children] = {
    W.new("FontString", { layer = "OVERLAY", point = { "CENTER" },
      text = W.computed(function() return ("%d%%"):format(pct() * 100) end) }),
  },
})
```

Criterio de éxito: ~20 líneas, cero handlers manuales, el ancho persiste entre sesiones, y
bajo ForceTaint muestra los fallbacks sin un solo error Lua.

## 8. Fuera de alcance v0 (explícito — ADR-0005)

- **v1:** `Weave.each` — listas reactivas con frame pooling combat-safe (W2).
- **v2:** DevTools in-game `/weave` (W4) · `throttle`/`debounce`/`delay` (W5).
- **Nunca** (north-star): async/promesas, red/comm, ciclo de vida de addon, slash commands.

## 9. Roadmap de implementación

| Hito | Entregable | Verificación |
|------|-----------|--------------|
| M0 | `core/` completo | busted headless, sin mock; 0 warnings luacheck |
| M1 | `wow/` (fromEvent, bind, props, onUpdate) | demo mínima in-game |
| M2 | taint end-to-end | demo bajo ForceTaint (macro loadstring) sin errores Lua |
| M3 | `store/` (persistencia + migraciones) | busted con SV simuladas + prueba in-game de persistencia |
| M4 | `ui/` (`W.new`, children, scripts, scopes) | demo canónica §7 completa in-game |
| M5 | `craft/` + FRs a Craft si hacen falta | página demo en Craft_Browser |
| M6 | docs para devs nuevos + release v0.1 | tutorial "tu primer addon reactivo" (<60 líneas, 3 pisos) |
