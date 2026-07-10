-- window_spec.lua — contract for the PURE window planner (API-v0 §4, Weave.virtual,
-- M10/ADR-0010, Fase 1). Core layer: plain arithmetic, zero WoW. It answers "given a
-- huge list and a scroll position, which slice is visible and where does it sit?" so
-- the ui layer can fill a FIXED pool without ever materializing the whole list.
--
-- Weave._windowPlan(total, opts) → plan
--   total : number of entries in the FULL list.
--   opts  : { rowHeight, viewportHeight, scroll?, columns?, spacing? }
--           rowHeight/viewportHeight in px; scroll in px (default 0); columns default 1
--           (grid width); spacing px between grid-rows (default 0). Inputs are assumed
--           valid — Weave.virtual validates opts; core is pure math (like Reconcile).
--   plan  : {
--     first,         -- 1-based index of the first entry to paint (1 when the list is empty)
--     count,         -- entries to fill THIS frame (0..capacity), clamped at the tail
--     offset,        -- px the top painted grid-row sits ABOVE the viewport top (0 <= offset < stride)
--     firstRow,      -- 0-based grid-row index of `first` (for vertical placement)
--     capacity,      -- FIXED pool size = poolRows*columns (scroll-invariant — the point of virtualization)
--     contentHeight, -- total px height of the full list (drives Craft's scrollbar thumb)
--     maxScroll,     -- max(0, contentHeight - viewportHeight)
--   }
--
-- stride = rowHeight + spacing. poolRows = ceil(viewportHeight/stride) + 1 (the +1 row
-- covers a fractional top). The ui positions entry j at grid-row floor((j-1)/columns),
-- column (j-1)%columns, screen-y = (row - firstRow)*stride - offset.

local helper = dofile("tests/helper.lua")

describe("Weave._windowPlan: planificador de ventana puro (virtualización)", function()

  it("scroll 0, una columna: arranca en la 1ª entrada, sin offset, en la fila 0", function()
    local W = helper.loadWeave()
    -- rowHeight 20, viewport 100 → stride 20, poolRows = ceil(100/20)+1 = 6
    local p = W._windowPlan(100, { rowHeight = 20, viewportHeight = 100 })
    assert_eq(p.first, 1)
    assert_eq(p.offset, 0)
    assert_eq(p.firstRow, 0)
    assert_eq(p.capacity, 6, "pool fijo = ceil(100/20)+1")
    assert_eq(p.count, 6, "llena el pool: hay 100 entradas, caben 6")
  end)

  it("pool FIJO: la capacidad no cambia con el scroll (la esencia de virtualizar)", function()
    local W = helper.loadWeave()
    local top = W._windowPlan(100, { rowHeight = 20, viewportHeight = 100, scroll = 0 })
    local mid = W._windowPlan(100, { rowHeight = 20, viewportHeight = 100, scroll = 500 })
    assert_eq(top.capacity, mid.capacity, "el pool no crece al scrollear")
  end)

  it("scroll fraccional (media fila): el pool se desplaza por offset, no salta de fila", function()
    local W = helper.loadWeave()
    -- stride 20, scroll 10 = media fila → seguimos en la fila 0 pero desplazados 10px
    local p = W._windowPlan(100, { rowHeight = 20, viewportHeight = 100, scroll = 10 })
    assert_eq(p.firstRow, 0)
    assert_eq(p.offset, 10)
    assert_eq(p.first, 1, "la fila 0 sigue parcialmente visible arriba")
  end)

  it("scroll de exactamente una fila: avanza a la fila 1, offset vuelve a 0", function()
    local W = helper.loadWeave()
    local p = W._windowPlan(100, { rowHeight = 20, viewportHeight = 100, scroll = 20 })
    assert_eq(p.firstRow, 1)
    assert_eq(p.offset, 0)
    assert_eq(p.first, 2, "una columna: fila 1 ↔ entrada 2")
  end)

  it("grid de N columnas: la entrada `first` se mapea a fila*columns+1", function()
    local W = helper.loadWeave()
    -- 6 columnas, rowHeight 40, viewport 400 → stride 40, poolRows = ceil(400/40)+1 = 11
    -- scroll 45 = 1 fila + 5px → firstRow 1, offset 5, first = 1*6+1 = 7
    local p = W._windowPlan(100, { rowHeight = 40, viewportHeight = 400, columns = 6, scroll = 45 })
    assert_eq(p.firstRow, 1)
    assert_eq(p.offset, 5)
    assert_eq(p.first, 7, "fila 1 en grid de 6 → primera entrada de esa fila es la 7")
    assert_eq(p.capacity, 66, "poolRows 11 × 6 columnas")
  end)

  it("altura de contenido en grid: filas = ceil(total/columns), sin gap final", function()
    local W = helper.loadWeave()
    -- 100 entradas / 6 columnas = 17 filas; 17*40 = 680; viewport 400 → maxScroll 280
    local p = W._windowPlan(100, { rowHeight = 40, viewportHeight = 400, columns = 6 })
    assert_eq(p.contentHeight, 680)
    assert_eq(p.maxScroll, 280)
  end)

  it("altura de contenido con spacing: rowHeight*n + spacing*(n-1)", function()
    local W = helper.loadWeave()
    -- 10 entradas, rowHeight 20, spacing 5 → 10*20 + 9*5 = 245
    local p = W._windowPlan(10, { rowHeight = 20, viewportHeight = 100, spacing = 5 })
    assert_eq(p.contentHeight, 245)
    assert_eq(p.maxScroll, 145)
  end)

  it("final de la lista: count se recorta a lo que queda, jamás lee de más", function()
    local W = helper.loadWeave()
    -- stride 20, maxScroll = 100*20 - 100 = 1900; scroll al fondo → firstRow 95, first 96
    local p = W._windowPlan(100, { rowHeight = 20, viewportHeight = 100, scroll = 1900 })
    assert_eq(p.firstRow, 95)
    assert_eq(p.first, 96)
    assert_eq(p.count, 5, "de la 96 a la 100 quedan 5, aunque el pool sea 6")
  end)

  it("scroll más allá del máximo: se clampa al fondo (no sobre-scrollea)", function()
    local W = helper.loadWeave()
    local atMax   = W._windowPlan(100, { rowHeight = 20, viewportHeight = 100, scroll = 1900 })
    local beyond  = W._windowPlan(100, { rowHeight = 20, viewportHeight = 100, scroll = 99999 })
    assert_eq(beyond.first, atMax.first, "pasarse de scroll = quedarse en el fondo")
    assert_eq(beyond.offset, atMax.offset)
  end)

  it("lista más corta que el viewport: sin scroll, count = total", function()
    local W = helper.loadWeave()
    -- 3 entradas en un viewport de 100 → contentHeight 60 < 100 → maxScroll 0
    local p = W._windowPlan(3, { rowHeight = 20, viewportHeight = 100, scroll = 40 })
    assert_eq(p.maxScroll, 0)
    assert_eq(p.first, 1, "no hay scroll posible: clampa a 0")
    assert_eq(p.offset, 0)
    assert_eq(p.count, 3, "pinta las 3 que hay, no la capacidad entera")
  end)

  it("lista vacía: count 0, contentHeight 0, first 1 (sin leer nada)", function()
    local W = helper.loadWeave()
    local p = W._windowPlan(0, { rowHeight = 20, viewportHeight = 100 })
    assert_eq(p.count, 0)
    assert_eq(p.contentHeight, 0)
    assert_eq(p.maxScroll, 0)
    assert_eq(p.first, 1)
  end)

end)
