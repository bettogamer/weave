-- virtual_segments_spec.lua — contract for Weave.virtual SEGMENTS (FR Coffer 2026-10-26,
-- ADR-0012): sub-groups that sit IN LINE inside a grid row, each one a block = a short
-- label ABOVE its cells. Built on the pure planner (core/flow_spec, "segmentos").
--
--   opts.segmentOf(entry) → key|nil   consecutive grid entries with the same key = a segment
--   opts.segmentGap = px               free gap between segments (the consumer paints any divider)
--   opts.segmentLabel = { height, render = function(info) → frame }
--       render runs ONCE per pooled label frame (own pool, O(visible)); `info` is a
--       signal of { key, entry, first, count, width } — count = entries of the WHOLE
--       segment, width = px of the labelled stretch. virtual owns the label's size
--       (width × height) and position, like it owns full-width rows.
-- Labelled frames are exposed on box._virtualLabels (visible ones, in paint order).

local helper = dofile("tests/wow_helper.lua")

local function lastPoint(f) return f._points[#f._points] end

local function H(k)    return { kind = "header", k = k } end
local function I(k, s) return { kind = "item", k = k, s = s } end
local function typeOf(e) return e.kind end
local function segmentOf(e) return e.s end

local function types(W)
  return {
    item = { grid = true, height = 20, render = function(it)
      return W.new("Button", { size = { 18, 18 }, text = W.computed(function()
        local e = it(); return e and ("i" .. e.k) or "" end) }) end },
    header = { height = 10, render = function(it)
      return W.new("Button", { text = W.computed(function()
        local e = it(); return e and ("H" .. e.k) or "" end) }) end },
  }
end

-- Counts label renders; the label text mirrors info().key.."/"..info().count.
local function labelSpec(W, counter)
  return { height = 6, render = function(info)
    if counter then counter.n = counter.n + 1 end
    return W.new("Button", { text = W.computed(function()
      local v = info(); return v and (v.key .. "/" .. v.count) or "" end) })
  end }
end

-- viewport 100 wide, 5 columns → colWidth 20; gap 10; label 6.
-- Layout: header y0 h10 | row y10 h26 [a x0][b x30] | row y36 h26 [c x0 ×3]
local function armor(W, extra)
  local box = W.new("Frame", { size = { 100, 200 } })
  local o = {
    parent = box, viewport = { 100, 200 }, columns = 5, typeOf = typeOf, types = types(W),
    segmentOf = segmentOf, segmentGap = 10, segmentLabel = labelSpec(W, extra and extra.counter),
  }
  for k, v in pairs(extra or {}) do if k ~= "counter" then o[k] = v end end
  local src = extra and extra.source or
    { H("Armor"), I(1, "a"), I(2, "b"), I(3, "c"), I(4, "c"), I(5, "c") }
  return box, W.virtual(src, o)
end

describe("Weave.virtual: segmentos en línea (FR Coffer 2026-10-26)", function()

  it("las celdas de cada segmento van en línea, a hueco de distancia, bajo su rótulo", function()
    local W = helper.loadWeaveWow()
    local box = armor(W)
    local rows = box._virtualRows
    assert_eq(#rows, 6)
    assert_eq(rows[2]._set.text, "i1")
    assert_eq(lastPoint(rows[2])[4], 0);  assert_eq(lastPoint(rows[2])[5], -16, "cabecera 10 + rótulo 6")
    assert_eq(lastPoint(rows[3])[4], 30, "'b' tras 20 de 'a' + 10 de hueco")
    assert_eq(lastPoint(rows[3])[5], -16)
  end)

  it("el segmento que no cabe salta de fila y sus celdas siguen la rejilla desde x=0", function()
    local W = helper.loadWeaveWow()
    local box = armor(W)
    local rows = box._virtualRows
    assert_eq(lastPoint(rows[4])[4], 0);  assert_eq(lastPoint(rows[4])[5], -42, "36 + rótulo 6")
    assert_eq(lastPoint(rows[5])[4], 20)
    assert_eq(lastPoint(rows[6])[4], 40)
  end)

  it("un rótulo por segmento, encima de sus celdas, con el tamaño que fija virtual", function()
    local W = helper.loadWeaveWow()
    local box = armor(W)
    local labels = box._virtualLabels
    assert_eq(#labels, 3)
    assert_eq(labels[1]._set.text, "a/1")
    assert_eq(lastPoint(labels[1])[4], 0);  assert_eq(lastPoint(labels[1])[5], -10)
    assert_eq(labels[1]._set.width, 20);    assert_eq(labels[1]._set.height, 6)
    assert_eq(lastPoint(labels[2])[4], 30)
    assert_eq(labels[3]._set.text, "c/3")
    assert_eq(lastPoint(labels[3])[5], -36)
    assert_eq(labels[3]._set.width, 60, "ancho del tramo: 3 celdas")
  end)

  it("info lleva la clave, la 1ª entrada, su índice, el total y el ancho", function()
    local W = helper.loadWeaveWow()
    local seen
    local box = W.new("Frame", { size = { 100, 200 } })
    W.virtual({ I(1, "a"), I(2, "a") }, {
      parent = box, viewport = { 100, 200 }, columns = 5, typeOf = typeOf, types = types(W),
      segmentOf = segmentOf, segmentLabel = { height = 6, render = function(info)
        return W.new("Button", { text = W.computed(function()
          local v = info(); if v then seen = v end; return "" end) })
      end },
    })
    assert_eq(seen.key, "a"); assert_eq(seen.first, 1); assert_eq(seen.count, 2)
    assert_eq(seen.entry.k, 1); assert_eq(seen.width, 40)
  end)

  it("un segmento más ancho que la fila envuelve; el rótulo solo en el 1er tramo", function()
    local W = helper.loadWeaveWow()
    local src = {}
    for i = 1, 7 do src[i] = I(i, "big") end
    local box = armor(W, { source = src })
    assert_eq(#box._virtualLabels, 1)
    assert_eq(box._virtualLabels[1]._set.text, "big/7")
    assert_eq(box._virtualLabels[1]._set.width, 100)
    local rows = box._virtualRows
    assert_eq(lastPoint(rows[6])[4], 0, "la 6ª vuelve a la columna 0")
    assert_eq(lastPoint(rows[6])[5], -26, "fila de continuación: sin rótulo (26 = 6 + 20)")
  end)

  it("render del rótulo corre UNA vez por marco del pool; scrollear no crea frames", function()
    local W = helper.loadWeaveWow()
    local src = {}
    for g = 1, 60 do src[#src + 1] = I(g, "g" .. g) end -- 60 segmentos de 1 celda
    local scroll = W.signal(0)
    local counter = { n = 0 }
    local box = armor(W, { source = src, scroll = scroll, counter = counter })
    local frames, renders = helper.frameCount(), counter.n
    for s = 0, 400, 13 do scroll:set(s) end
    assert_eq(helper.frameCount(), frames, "scrollear jamás crea frames")
    assert_eq(counter.n, renders, "ni re-hornea rótulos")
    assert_true(#box._virtualLabels > 0)
  end)

  it("los rótulos que sobran se ocultan y sueltan su info", function()
    local W = helper.loadWeaveWow()
    local src = W.signal({ I(1, "a"), I(2, "b") })
    local box = armor(W, { source = src })
    local labelA = box._virtualLabels[1]
    assert_eq(labelA._set.text, "a/1")
    src:set({ I(3) })            -- ya no hay segmentos
    assert_eq(#box._virtualLabels, 0)
    assert_false(labelA:IsShown(), "el rótulo ocioso se oculta")
    assert_eq(labelA._set.text, "", "y no retiene datos (info → nil)")
  end)

  it("con segmentOf → nil para todo, el grid es el de siempre", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 100, 200 } })
    W.virtual({ I(1), I(2), I(3) }, {
      parent = box, viewport = { 100, 200 }, columns = 5, typeOf = typeOf, types = types(W),
      segmentOf = function() return nil end, segmentLabel = labelSpec(W),
    })
    assert_eq(lastPoint(box._virtualRows[2])[4], 20)
    assert_eq(lastPoint(box._virtualRows[2])[5], 0, "sin rótulo, sin desplazamiento")
    assert_eq(#box._virtualLabels, 0)
  end)

  it("indentOf + segmentos: el segmento empaqueta en el ancho de su banda", function()
    local W = helper.loadWeaveWow()
    -- banda = 100 - 30 = 70: a(1) 0..20, b(2) 30..70; c(1) no cabe → fila nueva
    local box = armor(W, {
      source = { I(1, "a"), I(2, "b"), I(3, "b"), I(4, "c") },
      indentOf = function() return 30 end,
    })
    local rows = box._virtualRows
    assert_eq(lastPoint(rows[2])[4], 30 + 30, "sangría 30 + x del segmento 30")
    assert_eq(lastPoint(rows[4])[4], 30, "'c' arranca la fila siguiente en la banda")
    assert_eq(lastPoint(box._virtualLabels[1])[4], 30, "el rótulo también va sangrado")
  end)

  it("contentHeight cuenta las filas con rótulo", function()
    local W = helper.loadWeaveWow()
    local _, inst = armor(W)
    assert_eq(inst:contentHeight(), 10 + 26 + 26)
  end)

  it("Weave.flowPlan con las MISMAS opts da el mismo alto que la instancia", function()
    local W = helper.loadWeaveWow()
    local src = { H("Armor"), I(1, "a"), I(2, "b"), I(3, "c"), I(4, "c"), I(5, "c") }
    local opts = {
      viewport = { 100, 200 }, columns = 5, typeOf = typeOf, types = types(W),
      segmentOf = segmentOf, segmentGap = 10, segmentLabel = labelSpec(W),
    }
    local plan = W.flowPlan(src, opts)
    opts.parent = W.new("Frame", { size = { 100, 200 } })
    local inst = W.virtual(src, opts)
    assert_eq(plan.contentHeight, inst:contentHeight())
  end)

  it("validación: segmentLabel sin segmentOf, segmentOf sin types, formas inválidas", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 100, 200 } })
    local base = { parent = box, viewport = { 100, 200 }, typeOf = typeOf, types = types(W) }
    local function with(extra)
      local o = {}
      for k, v in pairs(base) do o[k] = v end
      for k, v in pairs(extra) do o[k] = v end
      return o
    end
    assert_error(function() W.virtual({}, with({ segmentLabel = labelSpec(W) })) end, "segmentOf")
    assert_error(function()
      W.virtual({}, { parent = box, viewport = { 100, 200 }, rowHeight = 20,
        render = function() end, segmentOf = segmentOf })
    end, "types")
    assert_error(function() W.virtual({}, with({ segmentOf = 3 })) end, "segmentOf")
    assert_error(function()
      W.virtual({}, with({ segmentOf = segmentOf, segmentGap = -1 }))
    end, "segmentGap")
    assert_error(function()
      W.virtual({}, with({ segmentOf = segmentOf, segmentLabel = { height = 0, render = print } }))
    end, "segmentLabel")
  end)

end)
