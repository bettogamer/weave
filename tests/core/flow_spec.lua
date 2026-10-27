-- flow_spec.lua — contract for the PURE heterogeneous-flow planner (API-v0 §4,
-- Weave.virtual Fase 2, M10/ADR-0010). Core layer: plain arithmetic, zero WoW. It
-- answers "given a flat stream of mixed rows (grid items that flow in N columns +
-- full-width headers that break the flow), which VISUAL ROWS exist and where, and
-- which are visible at a scroll position?" so the ui layer can fill per-type pools.
--
-- Two functions, split by cadence:
--   Weave._flowLayout(items, opts) → { rows, contentHeight }   (per SOURCE change)
--     items[i] = { grid = boolean, height = number }  -- a pure per-entry descriptor
--       grid=true  → flows in the N-column grid; consecutive grid entries pack into a
--                    visual row of up to `columns`, sharing the row's height (max).
--       grid=false → full-width: its own visual row; FLUSHES any open grid row and the
--                    next grid entry starts fresh (headers break the flow).
--     opts = { columns, spacing? }  (spacing = px between visual rows, default 0)
--     rows[r] = { y, height, first, count }  -- entries first..first+count-1 live here
--     contentHeight = sum(row heights) + spacing*(#rows-1)   (no trailing gap; 0 if empty)
--   Weave._flowVisible(layout, scroll, viewportHeight) → { first, last }  (per SCROLL)
--     visual-row index range [first..last] whose [y, y+height) intersects the viewport
--     [scroll, scroll+viewportHeight). Empty range = first > last (returns first=1,last=0).
--     Assumes scroll already clamped by the ui (like _windowPlan's caller).

local helper = dofile("tests/helper.lua")

local function item(h)   return { grid = true,  height = h or 40 } end
local function header(h) return { grid = false, height = h or 24 } end

describe("Weave._flowLayout: filas visuales de un stream heterogéneo", function()

  it("todo grid, una columna: una fila visual por ítem, apiladas", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ item(40), item(40), item(40) }, { columns = 1 })
    assert_eq(#L.rows, 3)
    assert_eq(L.rows[1].y, 0);  assert_eq(L.rows[1].first, 1); assert_eq(L.rows[1].count, 1)
    assert_eq(L.rows[2].y, 40); assert_eq(L.rows[2].first, 2)
    assert_eq(L.rows[3].y, 80); assert_eq(L.rows[3].first, 3)
    assert_eq(L.contentHeight, 120)
  end)

  it("grid de N columnas: empaqueta N por fila, última fila parcial", function()
    local W = helper.loadWeave()
    local items = { item(40), item(40), item(40), item(40), item(40), item(40), item(40) }
    local L = W._flowLayout(items, { columns = 3 })
    assert_eq(#L.rows, 3)
    assert_eq(L.rows[1].first, 1); assert_eq(L.rows[1].count, 3)
    assert_eq(L.rows[2].first, 4); assert_eq(L.rows[2].count, 3)
    assert_eq(L.rows[3].first, 7); assert_eq(L.rows[3].count, 1, "7 ítems en 3 columnas → última fila con 1")
    assert_eq(L.contentHeight, 120)
  end)

  it("una cabecera rompe el flujo: los ítems tras ella empiezan en fila nueva", function()
    local W = helper.loadWeave()
    -- [header, item, item] en 3 columnas: la cabecera NO comparte fila con los ítems
    local L = W._flowLayout({ header(24), item(40), item(40) }, { columns = 3 })
    assert_eq(#L.rows, 2)
    assert_eq(L.rows[1].height, 24); assert_eq(L.rows[1].first, 1); assert_eq(L.rows[1].count, 1)
    assert_eq(L.rows[2].y, 24);      assert_eq(L.rows[2].first, 2); assert_eq(L.rows[2].count, 2)
    assert_eq(L.contentHeight, 64)
  end)

  it("una fila de grid parcial se cierra al llegar una cabecera", function()
    local W = helper.loadWeave()
    -- [item, item, header, item] en 3 columnas: la fila de 2 ítems se flushea antes de la cabecera
    local L = W._flowLayout({ item(40), item(40), header(24), item(40) }, { columns = 3 })
    assert_eq(#L.rows, 3)
    assert_eq(L.rows[1].first, 1); assert_eq(L.rows[1].count, 2); assert_eq(L.rows[1].y, 0)
    assert_eq(L.rows[2].first, 3); assert_eq(L.rows[2].count, 1); assert_eq(L.rows[2].y, 40) -- header
    assert_eq(L.rows[3].first, 4); assert_eq(L.rows[3].count, 1); assert_eq(L.rows[3].y, 64)
    assert_eq(L.contentHeight, 104)
  end)

  it("alturas distintas por tipo se acumulan en la Y correcta", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ header(30), item(20), item(20) }, { columns = 1 })
    assert_eq(L.rows[1].y, 0)
    assert_eq(L.rows[2].y, 30)
    assert_eq(L.rows[3].y, 50)
    assert_eq(L.contentHeight, 70)
  end)

  it("spacing separa las filas visuales, sin gap final", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ item(40), item(40) }, { columns = 1, spacing = 5 })
    assert_eq(L.rows[1].y, 0)
    assert_eq(L.rows[2].y, 45, "40 + 5 de spacing")
    assert_eq(L.contentHeight, 85, "40*2 + 5*(2-1), sin gap tras la última")
  end)

  it("stream vacío: sin filas, contentHeight 0", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({}, { columns = 6 })
    assert_eq(#L.rows, 0)
    assert_eq(L.contentHeight, 0)
  end)

  it("padding vertical: desplaza todas las filas por padTop y crece contentHeight", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ item(40), item(40) }, { columns = 1, padTop = 6, padBottom = 6 })
    assert_eq(L.rows[1].y, 6, "la primera fila arranca en padTop, no en 0")
    assert_eq(L.rows[2].y, 46)
    assert_eq(L.contentHeight, 92, "40*2 + 6 + 6")
  end)

  it("padding en stream vacío: contentHeight sigue 0 (nada que insetar)", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({}, { columns = 6, padTop = 6, padBottom = 6 })
    assert_eq(L.contentHeight, 0)
  end)

end)

describe("Weave._flowVisible: rango de filas visuales visibles (por scroll)", function()

  -- 10 ítems de 20px en una columna → filas en y = 0,20,...,180; contentHeight 200
  local function tenRows(W)
    local items = {}
    for i = 1, 10 do items[i] = item(20) end
    return W._flowLayout(items, { columns = 1 })
  end

  it("scroll 0: las filas que llenan el viewport, sin parcial extra", function()
    local W = helper.loadWeave()
    local vis = W._flowVisible(tenRows(W), 0, 100)
    assert_eq(vis.first, 1)
    assert_eq(vis.last, 5, "5 filas de 20px llenan exactamente 100px")
  end)

  it("scroll fraccional: incluye la fila parcial de arriba y la de abajo", function()
    local W = helper.loadWeave()
    local vis = W._flowVisible(tenRows(W), 10, 100)
    assert_eq(vis.first, 1, "la fila 0 sigue parcialmente visible arriba")
    assert_eq(vis.last, 6, "asoma una fila más por abajo")
  end)

  it("scroll al fondo: las últimas filas", function()
    local W = helper.loadWeave()
    -- maxScroll = 200 - 100 = 100
    local vis = W._flowVisible(tenRows(W), 100, 100)
    assert_eq(vis.first, 6)
    assert_eq(vis.last, 10)
  end)

  it("alturas mixtas: la búsqueda encuentra el rango correcto", function()
    local W = helper.loadWeave()
    -- [header(30), item(20)*5] → filas y = 0,30,50,70,90,110
    local items = { header(30), item(20), item(20), item(20), item(20), item(20) }
    local vis = W._flowVisible(W._flowLayout(items, { columns = 1 }), 0, 60)
    assert_eq(vis.first, 1)
    assert_eq(vis.last, 3, "filas en 0-30, 30-50, 50-70 tocan el viewport [0,60)")
  end)

  it("layout vacío: rango vacío (first > last)", function()
    local W = helper.loadWeave()
    local vis = W._flowVisible(W._flowLayout({}, { columns = 6 }), 0, 100)
    assert_true(vis.first > vis.last, "sin filas, nada visible")
  end)

  it("con padding: _flowVisible trabaja en el mismo espacio ya desplazado", function()
    local W = helper.loadWeave()
    -- 3 ítems de 20 con padTop 10 → filas en y = 10, 30, 50; contentHeight 80
    local L = W._flowLayout({ item(20), item(20), item(20) }, { columns = 1, padTop = 10, padBottom = 10 })
    local vis = W._flowVisible(L, 0, 40)
    assert_eq(vis.first, 1, "la fila en [10,30) asoma en el viewport [0,40)")
    assert_eq(vis.last, 2, "la fila en [30,50) toca; la de [50,70) no")
  end)

end)

describe("Weave._flowLayout: sangría por fila (FR Coffer 2026-08-26)", function()

  -- Un ítem sangrado: mismo alto, pero cuelga `indent` px a la derecha y su tanda
  -- cabe en menos columnas (el ancho de celda NO cambia: eso lo garantiza el ui).
  local function sub(h, indent, cols)
    return { grid = true, height = h or 40, indent = indent, columns = cols }
  end

  it("un cambio de sangría CIERRA la fila abierta (aunque quedaran columnas libres)", function()
    local W = helper.loadWeave()
    -- 2 ítems a ras + 2 sangrados, con columns = 3: sin sangría irían todos en 1 fila
    local L = W._flowLayout({ item(40), item(40), sub(40, 20, 2), sub(40, 20, 2) },
      { columns = 3 })
    assert_eq(#L.rows, 2, "la sangría rompe el flujo igual que una cabecera")
    assert_eq(L.rows[1].first, 1); assert_eq(L.rows[1].count, 2)
    assert_eq(L.rows[2].first, 3); assert_eq(L.rows[2].count, 2)
  end)

  it("cada fila recuerda su sangría, para que el ui la aplique", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ item(40), sub(40, 20, 2), header(24) }, { columns = 3 })
    assert_eq(L.rows[1].indent, 0, "sin sangría declarada = 0")
    assert_eq(L.rows[2].indent, 20)
    assert_eq(L.rows[3].indent, 0)
  end)

  it("la tanda sangrada empaqueta con SUS columnas, no con las globales", function()
    local W = helper.loadWeave()
    -- columns global 3; la tanda sangrada solo tiene sitio para 2
    local items = { sub(40, 20, 2), sub(40, 20, 2), sub(40, 20, 2), sub(40, 20, 2) }
    local L = W._flowLayout(items, { columns = 3 })
    assert_eq(#L.rows, 2, "4 ítems a 2 por fila")
    assert_eq(L.rows[1].count, 2); assert_eq(L.rows[1].y, 0)
    assert_eq(L.rows[2].count, 2); assert_eq(L.rows[2].y, 40)
    assert_eq(L.contentHeight, 80, "menos columnas = más alto de contenido")
  end)

  it("dos niveles de sangría seguidos: una fila por nivel", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ sub(40, 20, 2), sub(40, 40, 1) }, { columns = 3 })
    assert_eq(#L.rows, 2)
    assert_eq(L.rows[1].indent, 20)
    assert_eq(L.rows[2].indent, 40)
  end)

  it("una fila de ancho completo también lleva su sangría", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ { grid = false, height = 24, indent = 20 } }, { columns = 3 })
    assert_eq(L.rows[1].indent, 20, "la sub-cabecera cuelga como sus ítems")
    assert_eq(L.rows[1].height, 24)
  end)

  it("sin sangría, el plan es EXACTAMENTE el de antes (default 0)", function()
    local W = helper.loadWeave()
    local items = { header(24), item(40), item(40), item(40), item(40) }
    local L = W._flowLayout(items, { columns = 3, spacing = 4 })
    assert_eq(#L.rows, 3)
    assert_eq(L.rows[1].count, 1); assert_eq(L.rows[1].y, 0)
    assert_eq(L.rows[2].count, 3); assert_eq(L.rows[2].y, 28)
    assert_eq(L.rows[3].count, 1); assert_eq(L.rows[3].y, 72)
    assert_eq(L.contentHeight, 112)
  end)

end)

-- Bloque C (FR Coffer 2026-10-26, ADR-0012): SEGMENTOS en línea dentro de una fila de
-- grid. Contrato nuevo del descriptor y de las opts (todo opcional; sin `segment` el
-- planificador se comporta EXACTAMENTE como antes):
--   items[i].segment = clave|nil — entradas grid CONSECUTIVAS con la misma clave forman
--                      un segmento (un bloque = rótulo encima + sus celdas).
--   opts.colWidth, opts.width (ancho útil, ya sin padding), opts.segmentGap (px entre
--   segmentos), opts.labelHeight (alto del rótulo).
-- Empaquetado: un segmento va en línea tras el anterior, a `gap` px; si no cabe en lo
-- que queda de fila abre fila nueva; si es más ancho que la fila entera envuelve desde
-- x=0 (rótulo solo en el primer tramo). Una fila donde EMPIEZA algún segmento mide
-- labelHeight + celda y sus celdas bajan cellY = labelHeight; las de continuación, solo
-- la celda. Cada fila con segmentos lleva
--   row.segs[s] = { first, count, x, key, label = bool, total }   (x relativa a la banda)
-- Pasar de entradas sin clave a con clave (o al revés) cierra la fila.
local function seg(key, h) return { grid = true, height = h or 20, segment = key } end
local SEG = { columns = 5, colWidth = 20, width = 100, segmentGap = 10, labelHeight = 6 }
local function segOpts(extra)
  local o = {}
  for k, v in pairs(SEG) do o[k] = v end
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

describe("Weave._flowLayout: segmentos en línea (FR Coffer 2026-10-26)", function()

  it("dos segmentos caben en la misma fila, separados por el hueco", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ seg("a"), seg("b"), seg("b") }, segOpts())
    assert_eq(#L.rows, 1)
    local r = L.rows[1]
    assert_eq(r.first, 1); assert_eq(r.count, 3)
    assert_eq(#r.segs, 2)
    assert_eq(r.segs[1].key, "a"); assert_eq(r.segs[1].x, 0);  assert_eq(r.segs[1].count, 1)
    assert_eq(r.segs[2].key, "b"); assert_eq(r.segs[2].x, 30, "20 de la celda de 'a' + 10 de hueco")
    assert_eq(r.segs[2].first, 2); assert_eq(r.segs[2].count, 2)
  end)

  it("una fila donde empieza un segmento mide rótulo + celda y baja sus celdas", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ seg("a") }, segOpts())
    assert_eq(L.rows[1].height, 26, "6 de rótulo + 20 de celda")
    assert_eq(L.rows[1].cellY, 6)
    assert_true(L.rows[1].segs[1].label)
    assert_eq(L.contentHeight, 26)
  end)

  it("el segmento que no cabe en lo que queda de fila abre fila nueva", function()
    local W = helper.loadWeave()
    -- a(1) en x0..20, b(1) en x30..50; c(3) pediría x60..120 > 100 → fila nueva
    local L = W._flowLayout({ seg("a"), seg("b"), seg("c"), seg("c"), seg("c") }, segOpts())
    assert_eq(#L.rows, 2)
    assert_eq(#L.rows[1].segs, 2)
    assert_eq(L.rows[2].y, 26)
    assert_eq(L.rows[2].segs[1].key, "c"); assert_eq(L.rows[2].segs[1].x, 0)
    assert_eq(L.rows[2].segs[1].count, 3)
  end)

  it("justo al borde cabe (x + ancho == width)", function()
    local W = helper.loadWeave()
    -- sin hueco: a 0..40, b 40..80, c 80..100 → los tres en una fila
    local L = W._flowLayout({ seg("a"), seg("a"), seg("b"), seg("b"), seg("c") },
      segOpts({ segmentGap = 0 }))
    assert_eq(#L.rows, 1)
    assert_eq(L.rows[1].segs[3].x, 80)
  end)

  it("un segmento más ancho que una fila envuelve desde x=0; rótulo solo en el 1er tramo", function()
    local W = helper.loadWeave()
    local items = {}
    for i = 1, 7 do items[i] = seg("big") end
    local L = W._flowLayout(items, segOpts())
    assert_eq(#L.rows, 2)
    assert_eq(L.rows[1].segs[1].count, 5); assert_true(L.rows[1].segs[1].label)
    assert_eq(L.rows[1].segs[1].total, 7, "total = entradas de todo el segmento")
    assert_eq(L.rows[1].height, 26)
    assert_eq(L.rows[2].segs[1].count, 2); assert_eq(L.rows[2].segs[1].x, 0)
    assert_false(L.rows[2].segs[1].label, "la continuación no repite rótulo")
    assert_eq(L.rows[2].height, 20, "fila de continuación: solo la celda")
    assert_eq(L.rows[2].cellY, 0)
  end)

  it("tras un segmento envuelto, el siguiente sigue en línea en su último tramo", function()
    local W = helper.loadWeave()
    local items = {}
    for i = 1, 6 do items[i] = seg("big") end -- 5 + 1
    items[7] = seg("x")
    local L = W._flowLayout(items, segOpts())
    assert_eq(#L.rows, 2)
    local r2 = L.rows[2]
    assert_eq(#r2.segs, 2)
    assert_eq(r2.segs[2].key, "x"); assert_eq(r2.segs[2].x, 30)
    assert_eq(r2.height, 26, "en la fila 2 EMPIEZA 'x' → lleva rótulo")
    assert_eq(r2.cellY, 6, "y la cola de 'big' baja con ella (celdas alineadas)")
  end)

  it("la misma clave NO consecutiva son dos segmentos", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ seg("a"), seg("b"), seg("a") }, segOpts())
    assert_eq(#L.rows[1].segs, 3)
  end)

  it("pasar de entradas sin clave a con clave cierra la fila (y al revés)", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ item(20), item(20), seg("a"), item(20) }, segOpts())
    assert_eq(#L.rows, 3)
    assert_eq(L.rows[1].count, 2); assert_eq(L.rows[1].segs, nil, "fila clásica: sin segs")
    assert_eq(L.rows[2].segs[1].key, "a")
    assert_eq(L.rows[3].count, 1); assert_eq(L.rows[3].segs, nil)
  end)

  it("una cabecera ancho completo sigue rompiendo la fila", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ seg("a"), header(10), seg("b") }, segOpts())
    assert_eq(#L.rows, 3)
    assert_eq(L.rows[2].height, 10)
  end)

  it("con sangría el segmento usa el ancho de SU banda", function()
    local W = helper.loadWeave()
    local function sseg(key) local d = seg(key); d.indent = 30; d.columns = 3; return d end
    -- banda = 100 - 30 = 70: a(1) 0..20, b(2) 30..70 cabe; c(1) 80..100 > 70 → nueva fila
    local L = W._flowLayout({ sseg("a"), sseg("b"), sseg("b"), sseg("c") }, segOpts())
    assert_eq(#L.rows, 2)
    assert_eq(L.rows[1].indent, 30)
    assert_eq(#L.rows[1].segs, 2)
    assert_eq(L.rows[2].segs[1].key, "c")
  end)

  it("sin ninguna clave el resultado es idéntico al de siempre (y sin segs)", function()
    local W = helper.loadWeave()
    local L = W._flowLayout({ item(20), item(20), item(20) }, segOpts({ columns = 2 }))
    assert_eq(#L.rows, 2)
    assert_eq(L.rows[1].count, 2)
    assert_eq(L.rows[1].segs, nil)
    assert_eq(L.rows[1].height, 20)
    assert_eq(L.contentHeight, 40)
  end)

end)

-- Weave.flowPlan(list, opts): el MISMO algoritmo que pinta la ui, expuesto para que el
-- consumidor estime alturas ("fit" de Coffer) sin instancia. Recibe las MISMAS opts que
-- Weave.virtual heterogéneo (viewport, columns, padding*, spacing, typeOf, types,
-- indentOf, segmentOf, segmentGap, segmentLabel.height); opts.width pisa viewport[1]
-- para simular otro ancho. Devuelve { rows, contentHeight }.
describe("Weave.flowPlan: el planificador público", function()

  local function plainTypes()
    return {
      item   = { grid = true, height = 20, render = function() end },
      header = { height = 10, render = function() end },
    }
  end
  local function typeOf(e) return e.kind end

  it("aplica types/typeOf/columns/padding igual que el virtual", function()
    local W = helper.loadWeave()
    local list = { { kind = "header" }, { kind = "item" }, { kind = "item" }, { kind = "item" } }
    local P = W.flowPlan(list, {
      viewport = { 60, 100 }, columns = 2, padding = 4, typeOf = typeOf, types = plainTypes(),
    })
    assert_eq(#P.rows, 3, "cabecera + 2 filas de grid (3 ítems en 2 columnas)")
    assert_eq(P.rows[1].y, 4, "padTop")
    assert_eq(P.contentHeight, 4 + 10 + 20 + 20 + 4)
  end)

  it("segmentOf + segmentGap + segmentLabel.height empaquetan como la ui", function()
    local W = helper.loadWeave()
    local list = {
      { kind = "item", s = "a" }, { kind = "item", s = "b" },
      { kind = "item", s = "c" }, { kind = "item", s = "c" }, { kind = "item", s = "c" },
    }
    local P = W.flowPlan(list, {
      viewport = { 100, 200 }, columns = 5, typeOf = typeOf, types = plainTypes(),
      segmentOf = function(e) return e.s end, segmentGap = 10,
      segmentLabel = { height = 6, render = function() end },
    })
    assert_eq(#P.rows, 2)
    assert_eq(P.rows[1].segs[2].x, 30)
    assert_eq(P.contentHeight, 52)
  end)

  it("opts.width simula otro ancho sin tocar las opts del virtual", function()
    local W = helper.loadWeave()
    local list = {}
    for i = 1, 6 do list[i] = { kind = "item" } end
    local o = { viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = plainTypes() }
    assert_eq(W.flowPlan(list, o).contentHeight, 40)
    o.width, o.columns = 120, 6
    assert_eq(W.flowPlan(list, o).contentHeight, 20)
  end)

  it("indentOf baja columnas por banda, igual que el virtual", function()
    local W = helper.loadWeave()
    local list = {}
    for i = 1, 4 do list[i] = { kind = "item" } end
    local P = W.flowPlan(list, {
      viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = plainTypes(),
      indentOf = function() return 20 end, -- (60-20)/20 = 2 columnas
    })
    assert_eq(#P.rows, 2)
    assert_eq(P.rows[1].count, 2)
  end)

  it("valida lo mismo que el virtual: typeOf desconocido → error claro", function()
    local W = helper.loadWeave()
    assert_error(function()
      W.flowPlan({ { kind = "nope" } }, {
        viewport = { 60, 100 }, typeOf = typeOf, types = plainTypes(),
      })
    end, "unknown type")
    assert_error(function() W.flowPlan({}, { viewport = { 60, 100 } }) end, "types")
  end)

end)
