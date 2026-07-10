-- virtual_hetero_spec.lua — contract for Weave.virtual Fase 2 (API-v0 §4, M10/
-- ADR-0010): HETEROGENEOUS rows — grid items + full-width headers interleaved in one
-- virtualized stream. Built on the pure flow planner (core/flow_spec). `render` becomes
-- a per-type `types` map + `opts.typeOf`; each type keeps its OWN pool (a cell baked as
-- a header can't become an item). Collapse is the CONSUMER's job (it re-sets the
-- stream) — virtual is just a window over whatever flat stream it gets.

local helper = dofile("tests/wow_helper.lua")

-- Two row types: "item" flows in the grid (height 20), "header" is full-width (height 10).
-- Their render tags the frame text so specs can read the visible order and type.
local function htypes(W)
  return {
    item = { grid = true, height = 20, render = function(it)
      return W.new("Button", { size = { 18, 18 }, text = W.computed(function()
        local e = it(); return e and ("i" .. e.k) or "" end) }) end },
    header = { height = 10, render = function(it)
      return W.new("Button", { text = W.computed(function()
        local e = it(); return e and ("H" .. e.k) or "" end) }) end },
  }
end

local function H(k) return { kind = "header", k = k } end
local function I(k) return { kind = "item", k = k } end
local function typeOf(e) return e.kind end
local function lastPoint(row) return row._points[#row._points] end

describe("Weave.virtual Fase 2: filas heterogéneas", function()

  it("un render por tipo, pintadas en orden del stream", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    W.virtual({ H(1), I(1), I(2), H(2), I(3) }, {
      parent = box, viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = htypes(W),
    })
    local rows = box._virtualRows
    assert_eq(#rows, 5)
    local want = { "H1", "i1", "i2", "H2", "i3" }
    for i, t in ipairs(want) do assert_eq(rows[i]._set.text, t) end
  end)

  it("la cabecera va a ancho completo (x=0, width=viewport); los ítems en el grid", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    W.virtual({ H(1), I(1), I(2), H(2), I(3) }, {
      parent = box, viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = htypes(W),
    })
    local h1, i1, i2 = box._virtualRows[1], box._virtualRows[2], box._virtualRows[3]
    assert_eq(lastPoint(h1)[4], 0, "cabecera en x=0")
    assert_eq(h1._set.width, 60, "cabecera a ancho completo del viewport")
    assert_eq(h1._set.height, 10, "y virtual le fija la altura declarada (si no, altura 0 = invisible)")
    assert_eq(lastPoint(i1)[4], 0);  assert_eq(lastPoint(i1)[5], -10, "ítem bajo la cabecera (y=10)")
    assert_eq(lastPoint(i2)[4], 20, "2º ítem en la columna 1 (colWidth 20)")
    assert_eq(lastPoint(i2)[5], -10)
  end)

  it("pool POR TIPO: crecer el stream no crea frames nuevos", function()
    local W = helper.loadWeaveWow()
    local source = W.signal({ H(1), I(1) })
    local box = W.new("Frame", { size = { 60, 100 } })
    W.virtual(source, {
      parent = box, viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = htypes(W),
    })
    local before = helper.frameCount()
    local big = { H(1) }
    for k = 1, 200 do big[#big + 1] = I(k) end
    big[#big + 1] = H(2)
    source:set(big)
    assert_eq(helper.frameCount(), before, "los pools están dimensionados al viewport, no al stream")
  end)

  it("scrollear re-glasea filas heterogéneas sin crear frames", function()
    local W = helper.loadWeaveWow()
    local scroll = W.signal(0)
    local box = W.new("Frame", { size = { 60, 40 } }) -- viewport bajo: hay que scrollear
    local data = { H(1) }
    for k = 1, 12 do data[#data + 1] = I(k) end -- header + 4 grid rows (cols 3)
    W.virtual(data, {
      parent = box, viewport = { 60, 40 }, columns = 3, scroll = scroll,
      typeOf = typeOf, types = htypes(W),
    })
    local before = helper.frameCount()
    scroll:set(50) -- content = 10 + 4*20 = 90; max = 50 → al fondo
    assert_eq(helper.frameCount(), before, "scrollear solo re-glasea")
    assert_eq(box._virtualRows[1]._set.text, "i7", "la ventana ahora arranca en la fila de i7..i9")
  end)

  it("contentHeight suma las filas visuales heterogéneas, reactivo", function()
    local W = helper.loadWeaveWow()
    local source = W.signal({ H(1), I(1), I(2), H(2), I(3) })
    local box = W.new("Frame", { size = { 60, 100 } })
    local v = W.virtual(source, {
      parent = box, viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = htypes(W),
    })
    local h = W.computed(function() return v:contentHeight() end)
    assert_eq(h(), 60, "H(10) + fila ítems(20) + H(10) + fila ítem(20)")
    source:set({ H(1), I(1) })
    assert_eq(h(), 30, "H(10) + fila ítem(20)")
  end)

  it("una celda con dato secreto degrada; la ventana entera se pinta", function()
    local W = helper.loadWeaveWow({ issecretvalue = helper.isFakeSecret })
    local secret = helper.newFakeSecret()
    local box = W.new("Frame", { size = { 60, 100 } })
    helper.silently(function()
      W.virtual({ H(1), { kind = "item", k = secret }, I(2) }, {
        parent = box, viewport = { 60, 100 }, columns = 3, typeOf = typeOf,
        types = {
          item = { grid = true, height = 20, render = function(it)
            return W.new("Button", { text = W.computed(function()
              local e = it(); if not e then return "" end
              if issecretvalue(e.k) then return "??" end
              return "i" .. e.k end) }) end },
          header = { height = 10, render = function() return W.new("Button", { text = "H" }) end },
        },
      })
    end)
    assert_eq(#box._virtualRows, 3, "la lista se pinta pese al secreto")
    assert_eq(box._virtualRows[2]._set.text, "??", "la celda del secreto degrada")
  end)

end)

describe("Weave.virtual Fase 2: validación y combate", function()

  it("types sin typeOf → error claro", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    assert_error(function()
      W.virtual({ I(1) }, { parent = box, viewport = { 60, 100 }, types = htypes(W) })
    end, "typeOf")
  end)

  it("render (Fase 1) Y types (Fase 2) a la vez → error claro", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    assert_error(function()
      W.virtual({ I(1) }, {
        parent = box, viewport = { 60, 100 }, rowHeight = 20,
        render = function() return W.new("Button", {}) end,
        typeOf = typeOf, types = htypes(W),
      })
    end, "both")
  end)

  it("crear la lista heterogénea EN combate es error duro", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    helper.setInCombat(true)
    assert_error(function()
      W.virtual({ H(1), I(1) }, {
        parent = box, viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = htypes(W),
      })
    end, "combat")
  end)

end)
