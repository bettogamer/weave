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

end)
