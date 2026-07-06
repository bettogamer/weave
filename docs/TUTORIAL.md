# Tu primer addon reactivo con Weave

> Para dev novato. En 40 líneas vas a hacer un addon que muestra tu oro en pantalla y se
> actualiza **solo** cada vez que compras, vendes o looteas — sin escribir un solo manejador
> de eventos a mano. Ese "solo" es de lo que va Weave.

Lo único que necesitas es tener **Weave instalado** (o embebido) para que exista
`LibStub("Weave-1.0")`. No hay compiladores ni pasos de build: es Lua 5.1, el mismo que
corre dentro de WoW.

---

## La idea en una frase

Un addon reactivo tiene **tres pisos**, y siempre en el mismo orden:

| Piso | Qué es | Analogía de Excel |
|------|--------|-------------------|
| 1. **Estado** | los datos que cambian (`signal`) | una **celda** donde escribes un número |
| 2. **Derivación** | lo que se calcula a partir del estado (`computed`) | una **fórmula** `=A1*2` en otra celda |
| 3. **Vista** | lo que se ve en pantalla (`Weave.new`) | un **gráfico enchufado** a esas celdas |

En Excel, cuando cambias la celda A1, la fórmula y el gráfico se actualizan **solos**. No
vas tú a "avisarles". Weave hace exactamente eso, pero con frames de WoW. Todo el truco es:
tú describes las conexiones **una vez**, y el flujo se mantiene solo para siempre.

Vamos a construir los tres pisos, uno a uno.

---

## Paso 0 — El esqueleto del addon

Dos archivos en `Interface/AddOns/MiOro/`. Primero el `.toc`, que le dice a WoW qué cargar:

```toc
## Interface: 120000
## Title: Mi Oro
## Notes: Mi primer addon reactivo
## Dependencies: Weave

MiOro.lua
```

> `## Dependencies: Weave` asegura que la librería exista antes que tu código. (Si en tu
> proyecto Weave va **embebido** en vez de instalado como addon suelto, aquí listarías tu
> propio `libs/Weave/Weave.xml` en vez de la dependencia — ver la guía de integración.)

Y en `MiOro.lua`, la primera línea de siempre: pedir la librería.

```lua
local W = LibStub("Weave-1.0")
```

`W` es tu puerta de entrada a todo (`W.signal`, `W.computed`, `W.new`…).

---

## Piso 1 — Estado: una señal con tu oro

Una **señal** (`signal`) es la celda de Excel: guarda un valor y avisa a quien dependa de
él cuando cambia. Podríamos crear una a mano con `W.signal(0)`… pero nuestro dato vive en
el juego (`GetMoney()`) y cambia con un **evento** (`PLAYER_MONEY`). Weave tiene un atajo
para justo eso:

```lua
-- PISO 1 · ESTADO — una señal alimentada por el evento del juego
local money = W.fromEvent("PLAYER_MONEY",
  function() return GetMoney() end,   -- "map": de qué se llena la señal cuando llega el evento
  { initial = GetMoney() })           -- valor de arranque, antes del primer evento
```

Qué acabas de montar:

- `W.fromEvent(evento, map, opts)` crea una señal y la **conecta** al evento `PLAYER_MONEY`.
- Cada vez que WoW dispara ese evento (compras, vendes, lootas oro…), Weave llama a tu
  `map` y mete el resultado en la señal. Tú **nunca** escribes `frame:RegisterEvent` ni un
  `OnEvent` con un `if event == ...`: eso es lo que Weave te ahorra.
- `initial = GetMoney()` es para que la señal ya tenga tu oro actual desde el segundo cero,
  sin esperar a que compres algo.

`money` ahora es "la celda A1" que se llena sola. Puedes leerla llamándola: `money()`.

---

## Piso 2 — Derivación: el texto que se calcula solo

El oro en crudo es un número gordo en cobre (12345 = 1g 23s 45c). Queremos el texto bonito
con iconos de moneda. Eso es una **derivación**: no es un dato nuevo, es algo que se
*calcula* a partir de `money`. Para eso está `computed` — la **fórmula** de Excel:

```lua
-- PISO 2 · DERIVACIÓN — texto formateado; se recalcula solo cuando `money` cambia
local label = W.computed(function()
  return GetCoinTextureString(money())   -- "12g 34s 56c" con sus iconos
end)
```

La magia está en `money()` **dentro** de la función:

- Weave se da cuenta, solo por leerla ahí, de que `label` **depende** de `money`. No se lo
  dices con ninguna lista de dependencias: lo detecta al vuelo (a esto se le llama
  *auto-tracking*).
- Cuando `money` cambie, `label` se marca como "hay que recalcular". Y si nadie cambia
  `money`, `label` **no** recalcula nada: es perezoso y cacheado, como una celda de Excel
  que solo se refresca cuando su fórmula lo necesita.

`label` es "la celda B1" con `=formato(A1)`.

---

## Piso 3 — Vista: el frame enchufado

Falta enseñarlo en pantalla. `Weave.new` describe un frame de WoW **y** enchufa sus
propiedades a las señales, todo en una sola descripción. Es el **gráfico** de Excel
conectado a las celdas:

```lua
-- PISO 3 · VISTA — se describe UNA vez; `text` queda enchufado a la derivación
W.new("FontString", {
  parent   = UIParent,
  layer    = "OVERLAY",
  template = "GameFontNormalLarge",
  point    = { "CENTER", 0, 200 },
  text     = label,   -- ← una señal/computed en una prop = bind automático
})
```

La línea que lo cambia todo es `text = label`:

- Si pusieras un texto fijo (`text = "hola"`), se pintaría una vez y ya.
- Al poner **la derivación** `label`, Weave crea un *bind*: cada vez que `label` cambie de
  valor, hará `fontString:SetText(...)` por ti. Enchufado, no copiado.

Y así se cierra el circuito. `PLAYER_MONEY` → `money` cambia → `label` recalcula → el texto
en pantalla se actualiza. Tú describiste las flechas una vez; el flujo corre solo.

---

## El addon completo

`MiOro.lua`, entero, 15 líneas de verdad:

```lua
local W = LibStub("Weave-1.0")

-- PISO 1 · ESTADO
local money = W.fromEvent("PLAYER_MONEY",
  function() return GetMoney() end,
  { initial = GetMoney() })

-- PISO 2 · DERIVACIÓN
local label = W.computed(function()
  return GetCoinTextureString(money())
end)

-- PISO 3 · VISTA
W.new("FontString", {
  parent   = UIParent,
  layer    = "OVERLAY",
  template = "GameFontNormalLarge",
  point    = { "CENTER", 0, 200 },
  text     = label,
})
```

Copia los dos archivos a `Interface/AddOns/MiOro/`, entra al juego (o `/reload`) y verás tu
oro flotando sobre el personaje. Vende algo: el número cambia **solo**.

---

## Lo que NO tuviste que escribir

Vale la pena parar aquí, porque esto es el punto entero de Weave. El addon "de toda la
vida" para lo mismo sería algo así:

```lua
-- El estilo manual (NO uses esto — es solo para comparar)
local f = CreateFrame("Frame")
local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
fs:SetPoint("CENTER", 0, 200)
f:RegisterEvent("PLAYER_MONEY")
f:SetScript("OnEvent", function()
  fs:SetText(GetCoinTextureString(GetMoney()))   -- tú, a mano, cada vez
end)
fs:SetText(GetCoinTextureString(GetMoney()))     -- y otra vez para el arranque
```

No es *tanto* más… hasta que el addon crece. Con Weave, el "quién avisa a quién cuando algo
cambia" no es trabajo tuyo: lo lleva la librería, y no se te olvida un caso. Añadir un
segundo dato o una segunda vista no te obliga a tocar los manejadores existentes — enchufas
otra flecha y ya.

---

## Siguiente paso

Ya tienes los tres pisos. A partir de aquí, Weave escala con las mismas piezas:

- **Que persista entre sesiones** — si quieres que el jugador arrastre el texto y su
  posición se recuerde, ese estado va en un **store** (`W.store`), que es una señal más pero
  guardada en las SavedVariables. Ver [API-v0 §5](API-v0.md).
- **Listas dinámicas** — para pintar una fila por ítem de una tabla que cambia (tu bolsa, un
  ranking…), está `W.each`, que recicla frames y es seguro en combate. Ver
  [API-v0 §4](API-v0.md).
- **La demo canónica** — el mismo patrón de tres pisos, pero con una barra de vida y estado
  persistente, y enseñando cómo Weave sobrevive a los *secret values* de 12.0: está en
  [`demo/WeaveDemo/Demo.lua`](../demo/WeaveDemo/Demo.lua).
- **La API completa** — todo lo público, con su semántica exacta: [docs/API-v0.md](API-v0.md).

La regla no cambia nunca: **estado → derivación → vista**, describes las conexiones una vez,
y el flujo se mantiene solo.
