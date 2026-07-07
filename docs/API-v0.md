# Weave — Especificación de API v0

> Spec de diseño: esto es lo que se implementará y contra lo que se escriben los tests.
> Cambios a esta superficie → actualizar aquí + ADR si es decisión de fondo.
> Convención: `s()` lee (y trackea), `s:set(v)` escribe, `s:peek()` lee sin trackear.
>
> Alcance v0 por ADR-0005: **core + wow + ui + store** (la capa craft se eliminó por
> ADR-0006: Craft integra Weave nativamente, embebiendo builds etiquetados).
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

### `Weave.isReactive(v) → boolean` · `Weave.isWritable(v) → boolean`

Predicados públicos para consumidores que aceptan **"señal-o-literal"** (p. ej. Craft en
las props de sus componentes). Evitan que el consumidor hurgue en la forma interna de un
signal: es Weave quien conoce sus tipos.

```lua
Weave.isReactive(hp)             -- true: signal, computed o función (lo que effect observa)
Weave.isReactive(80)             -- false: escalar → pintar una vez, no bindear
Weave.isWritable(hp)             -- true: es un signal (tiene :set) → two-way posible
Weave.isWritable(pct)            -- false: computed es read-only
```

- `isReactive(v)` — `true` para función o cualquier tabla callable (metatabla `__call`):
  signals y computeds incluidos. `false` para escalares y tablas planas.
- `isWritable(v)` — subconjunto: `true` solo para un signal (reactivo con método `:set`).
  Computeds y funciones → `false`. `isWritable ⊆ isReactive`.

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
- El `map` corre bajo el **guard de secrets** (ADR-0003): si OPERA un secret
  (aritmética, comparación…), esa actualización se salta — el registro sigue vivo, los
  demás suscriptores del evento no se ven afectados, y avisa una vez por registro. La
  siembra degrada igual (la señal arranca `nil`). Errores no-secret se propagan intactos.

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

Señal de tiempo throttleada (un único frame ticker compartido) para countdowns/duraciones.
`interval` en segundos (mín. efectivo ~0.05). Su valor es el `GetTime()` del último tick;
nace sembrada con la hora actual. Solo tickea si tiene suscriptores vivos, y **el mismo
intervalo devuelve la misma señal** (se comparte).

### `Weave.tween(target, opts?) → Tween` (M8 — ADR-0008)

Reactivo **read-only** cuyo valor se **desliza** hacia `target()` en el tiempo, en vez de
saltar. `target` es una señal/computed (o cualquier llamable) que devuelve un **número** o
un **array de números** (`{r,g,b}`, `{x,y}` — se interpola por elemento); un literal vale y
se siembra sin animar (coherencia señal-o-literal de `bind`/`Weave.new`). Se bindea como
cualquier señal.

```lua
local pct   = Weave.computed(function() return hp() / hpMax() end)
local suave = Weave.tween(pct, { duration = 0.3, easing = Weave.easing.outQuad })

Weave.new("StatusBar", { value = suave })   -- la barra se desliza, no salta

-- arrays: color que transiciona canal a canal
local color = Weave.computed(function() return pct() < 0.3 and {1,.2,.2} or {.2,.8,.2} end)
Weave.new("StatusBar", { statusBarColor = Weave.tween(color, { duration = 0.5 }) })
```

- **Siembra:** al crearse toma el valor actual de `target()` (arranca AHÍ, sin salto). La
  primera animación ocurre en el primer cambio de `target`.
- **Re-targeting:** si `target` cambia a mitad de una animación, la nueva anima **desde el
  valor actual** (no desde el origen viejo) hacia la meta nueva, reiniciando la duración.
- `opts.duration` — segundos (default `0.3`). `opts.easing` — función `(t) → t` con `t` en
  `[0,1]` (default `Weave.easing.outQuad` — se siente natural en UI). `opts.fallback` —
  valor expuesto si `target` degrada por secret (§3).
- **Driver compartido:** un único ticker mueve TODAS las animaciones activas por frame; una
  que llega a su meta se retira (coste cero en reposo; el ticker para si no queda ninguna —
  misma disciplina que `onUpdate`). Los arrays reutilizan una tabla-resultado por tween
  (mutada in-place) → cero allocations por frame (contrato §1).
- **Taint:** si `target()` es secret, no se puede interpolar → degrada por el chokepoint
  (fallback / se congela) y reanuda al volver un valor normal.
- **Combate:** un tween solo MUTA (no crea frames) → combat-safe; el driver corre en combate
  sin tratamiento especial (a diferencia de `each`).
- **Disposal:** adscrito al scope activo; `dispose()` lo desengancha del target y del driver.
- **`t:animating()` — booleano reactivo**: true mientras hay una animación en curso, false
  al llegar a la meta (o al sembrarse). Es una señal más (trackea): sirve para coordinar
  entrada/salida sin callbacks — un frame que se oculta al terminar su fundido de salida
  hace `shown = W.computed(function() return abierto() or t:animating() end)`.
- Read-only: `t()`, `t:peek()`, `t:isSecret()`; `Weave.isReactive(t)` → true,
  `Weave.isWritable(t)` → false. El motor de interpolación es Lua puro (`core/Tween.lua`,
  testeable headless); el reloj/driver es wow (`wow/Anim.lua`).

**Easings v0** — `Weave.easing`: `linear`, `inQuad`, `outQuad`, `inOutQuad`. Cualquier
función propia `(t) → t` vale. `Weave.spring` queda reservado como hermano futuro (ADR-0008).

### Chokepoint de errores (automático, ADR-0003)

Todo effect (y por tanto todo bind) corre bajo un handler **en el core**: si el error
contiene `"a secret"` o `"ForceTaint_Strong"`, el effect degrada — se traga el error,
conserva sus dependencias (revive solo cuando vuelven valores normales) y avisa **una vez
por sitio**. Cualquier otro error se propaga intacto. La parte visible del aviso la inyecta
la capa wow con `Weave._setSecretWarning(fn)` (mismo patrón que el detector, §3); headless
la degradación es silenciosa. Limitación conocida: un fn que explota antes de leer ninguna
señal queda sin dependencias y no revive.

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
secret (default seguro). El core también expone **`Weave._isSecretError(msg)`** (el
reconocedor de mensajes de error) para que la capa wow aplique el MISMO criterio en sus
guards (maps de eventos). La degradación de computeds reconoce los errores del cliente por
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
- **Restricción de combate (dura):** `Weave.new` con `InCombatLockdown()` → error claro
  (v0: siempre; el modo no-op con warning para producción queda pendiente de un flag de
  build). La creación declarativa es para construcción de UI fuera de combate; EN combate
  solo mutan los binds. (Listas dinámicas en combate → `each` con pooling, M6/ADR-0007.)
- Elementos creados dentro de un `scope:run()` quedan adscritos al scope (sus binds se
  liberan con él; el frame se oculta y queda reutilizable).

### `Weave.each(source, render, opts?) → EachDescriptor` (M6 — ADR-0007)

Lista reactiva con frame pooling combat-safe. `source` es una señal/computed (o cualquier
llamable) que devuelve un **array denso** (`{v1, v2, ...}`); una tabla literal vale y se
aplica una vez (coherencia señal-o-literal de `bind`/`Weave.new`). Devuelve un
**descriptor perezoso** (como las regiones de M4): dentro de `[Weave.children]` lo
materializa el padre; con `opts.parent`, en el acto.

```lua
W.new("Frame", {
  size = { 300, 400 },
  [W.children] = {
    W.each(items, function(item, index)
      -- corre UNA sola vez por fila del pool; item/index son SEÑALES read-only
      return W.new("Button", { size = { 280, 24 },
        [W.children] = {
          W.new("FontString", { layer = "OVERLAY", point = { "LEFT" },
            text = W.computed(function() return item().name end) }),
        },
      })
    end),
  },
})
```

- **`render(item, index) → frame`** corre **una vez por fila del pool** (al materializarla,
  nunca por cambio de datos): crea el frame de la fila y deja los binds enchufados a las
  señales `item`/`index`. Cuando la lista cambia, `each` NO toca frames: **re-asigna
  datos** (set en las señales de cada fila; `equals` corta lo que no cambió), materializa
  filas nuevas solo si hacen falta y esconde las sobrantes en el pool (ocultas,
  reutilizables, con sus binds vivos).
- **Identidad (keying):** default **por posición** (fila i ↔ dato i — el caso ventana de
  scroll). `opts.key = function(item) → string|number` da identidad estable: al
  reordenar/filtrar, cada dato conserva SU frame (estado visual incluido) y `each`
  re-posiciona. Claves duplicadas → error claro en dev. Si `key(item)` devuelve un
  secret o lanza por secret (un secret no puede ser key de tabla — catálogo global de
  taint), esa reconciliación degrada a índice con aviso una vez.
- **Layout:** pila vertical simple (fila i+1 anclada bajo la fila i; `opts.spacing`,
  default 0). `opts.layout = false` la desactiva (el consumidor posiciona — caso
  DragList de Craft). Nada más en v0.2: grids/scroll no son de `each`.
- **Virtualización = composición, no feature:** para listas grandes, la ventana visible
  es un computed que recorta (`scrollPos` señal + slice) y `each` por índice pinta solo
  esa ventana — el pool queda fijo en N filas visibles que se re-rellenan (patrón Sorted,
  con la seguridad que a Sorted le falta).
- **Combate (la razón de ser del pooling):** reusar/re-asignar/ocultar/re-posicionar es
  combat-safe; **materializar filas nuevas NO**. Si la lista crece en combate y el pool
  no alcanza: pinta lo que el pool permita, avisa una vez (canal del chokepoint) y
  completa la reconciliación sola al salir de combate (`PLAYER_REGEN_ENABLED`).
  `opts.warm = n` pre-materializa n filas al crearse (fuera de combate) para absorber
  crecimiento en combate.
- **Disposal:** el descriptor queda adscrito al scope activo (como todo en `ui/`);
  `dispose()` libera binds de todas las filas y oculta los frames.

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
  llamarse antes (devuelve defaults y re-sincroniza al hidratar — los effects/binds
  enchufados se enteran solos). `opts.addon = "MiAddon"` nombra al dueño (exacto,
  recomendado — WoW pasa `local addonName = ...` a cada archivo); sin él, se asume que
  el SIGUIENTE `ADDON_LOADED` es el del dueño (válido para el patrón file-scope). Al
  hidratar, **lo guardado gana** a escrituras pre-hidratación; en primera ejecución las
  escrituras tempranas sobreviven. Recomendación estándar: crearlo en el `ADDON_LOADED`
  de `Core.lua`.
- **Defaults sin pisar** lo guardado; claves guardadas que ya no están en defaults se
  preservan (datos del usuario nunca se borran — regla del estándar). **Los defaults NO
  se materializan en la SV**: solo persiste lo que se escribe explícitamente (estilo
  AceDB) — cambiar un default en una versión nueva alcanza a quien nunca lo tocó.
- `db._raw` — acceso de escape a la tabla SavedVariables cruda (para export/debug); es
  LA MISMA tabla que la global, sin copias. Claves de defaults: strings que no empiecen
  por `_` (reservado: `_version` es la única clave que Weave escribe por su cuenta).
- **Anidados**: una tabla en defaults crea un sub-store; su sub-tabla en la SV se
  materializa solo al escribir. Si lo guardado bajo esa clave no es una tabla (formato
  viejo/corrupto), valen los defaults y la primera escritura la repara.
- **`version`/`migrate`**: `migrate(raw, oldVersion)` corre en la hidratación, ANTES del
  re-sync (los lectores solo ven datos ya convertidos), y solo sobre datos preexistentes
  con versión distinta (`oldVersion` es `nil` en datos pre-versionado); primera ejecución
  solo estampa `_version`.
- Solo tipos serializables por WoW (boolean/number/string/table); `set()` con otro tipo
  → error claro. **Un secret jamás se persiste**: `set(secret)` en un campo de store
  avisa suave y salta la escritura (señal y SV intactas).

## 6. Integración con Craft (ADR-0006 — SIN capa en Weave)

La capa `craft/` de adaptadores fue **eliminada** (decisión del owner, ADR-0006): Craft
integra Weave nativamente — sus componentes aceptan señales como props porque embeben un
**build etiquetado** de Weave en `Craft/libs/Weave/` (modelo Ace3/LibStub). Weave no
contiene ni contendrá código que conozca a Craft; sus entregables para esta integración
son el paquete embebible, la guía de integración para autores de componentes y las
releases etiquetadas (ver el ADR).

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

## 8. Fuera de alcance v0.1 (explícito — ADR-0005, reordenado por ADR-0007/0008)

- **M6 / v0.2.0 (adelantado por ADR-0007):** `Weave.each` — listas reactivas con frame
  pooling combat-safe (W2). Spec en §4 (diseñada contra los casos reales de Coffer y
  Craft, 2026-07-05).
- **M8 / v0.4.0 (adelantado por ADR-0008):** `Weave.tween` — animaciones tween-first
  (número/array). Spec en §2. `Weave.spring` reservado como hermano futuro.
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
| M5 | paquete embebible + guía de integración Craft + release v0.1 (ADR-0006; absorbe el viejo M6) | el owner actualiza su primer componente Craft solo con la guía; página demo en Craft_Browser (en el repo de Craft) |
| M6 | `Weave.each` (W2, adelantado por ADR-0007) + release v0.2.0 | suite headless + demo in-game con lista dinámica + ForceTaint + prueba EN combate (el pool recicla, jamás crea) |
| M7 | docs para devs nuevos | tutorial "tu primer addon reactivo" (<60 líneas, 3 pisos) |
| M8 | `Weave.tween` (animaciones tween-first, ADR-0008) + release v0.4.0 | suite headless (motor `core/Tween.lua`) + demo in-game deslizando bajo ForceTaint, coste cero en reposo |
