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
