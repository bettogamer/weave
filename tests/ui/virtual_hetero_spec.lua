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

  it("padding insetea cabeceras (ancho completo) e ítems del grid por igual (FR Coffer)", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    -- columns 3, padding 6 → colWidth (60-12)/3 = 16; cabecera ancho completo = 60-12 = 48
    W.virtual({ H(1), I(1), I(2) }, {
      parent = box, viewport = { 60, 100 }, columns = 3, padding = 6,
      typeOf = typeOf, types = htypes(W),
    })
    local h1, i1, i2 = box._virtualRows[1], box._virtualRows[2], box._virtualRows[3]
    assert_eq(lastPoint(h1)[4], 6, "la cabecera arranca en padH, no en 0")
    assert_eq(h1._set.width, 48, "ancho completo menos el inset horizontal")
    assert_eq(lastPoint(h1)[5], -6, "la cabecera arranca padV por debajo del tope")
    assert_eq(lastPoint(i1)[4], 6, "ítem col 0 en padH")
    assert_eq(lastPoint(i1)[5], -16, "ítem bajo la cabecera: padV(6) + altura cabecera(10)")
    assert_eq(lastPoint(i2)[4], 22, "ítem col 1 = padH + colWidth (6 + 16)")
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

-- Un stream con nivel: I2(k) es un ítem que cuelga 20px de su sub-cabecera H2(k).
local function I2(k) return { kind = "item", k = k, depth = 1 } end
local function H2(k) return { kind = "header", k = k, depth = 1 } end
local function indentOf(e) return (e.depth or 0) * 20 end

describe("Weave.virtual Fase 2: sangría por fila (FR Coffer 2026-08-26)", function()

  -- viewport 60 de ancho, 3 columnas → colWidth 20. Una tanda sangrada 20px solo
  -- tiene 40px útiles → 2 columnas, con las celdas midiendo LO MISMO (20).
  it("desplaza la x de las celdas y reduce las columnas de esa tanda", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    W.virtual({ I(1), I(2), I(3), I2(4), I2(5), I2(6) }, {
      parent = box, viewport = { 60, 100 }, columns = 3,
      typeOf = typeOf, indentOf = indentOf, types = htypes(W),
    })
    local r = box._virtualRows
    assert_eq(lastPoint(r[1])[4], 0);  assert_eq(lastPoint(r[2])[4], 20)
    assert_eq(lastPoint(r[3])[4], 40, "la sección madre llena las 3 columnas")
    assert_eq(lastPoint(r[4])[4], 20, "la tanda sangrada arranca en la sangría")
    assert_eq(lastPoint(r[5])[4], 40)
    assert_eq(lastPoint(r[6])[4], 20, "solo caben 2: el tercero baja de fila")
    assert_eq(lastPoint(r[6])[5], -40, "y ocupa una fila visual nueva (y = 40)")
  end)

  it("las celdas sangradas MIDEN lo mismo que las de la sección madre", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    W.virtual({ I(1), I(2), I2(3), I2(4) }, {
      parent = box, viewport = { 60, 100 }, columns = 3,
      typeOf = typeOf, indentOf = indentOf, types = htypes(W),
    })
    local r = box._virtualRows
    local stepTop = lastPoint(r[2])[4] - lastPoint(r[1])[4]
    local stepSub = lastPoint(r[4])[4] - lastPoint(r[3])[4]
    assert_eq(stepSub, stepTop, "mismo paso de columna = misma celda, solo movida")
  end)

  it("una sub-cabecera de ancho completo se inseta Y encoge", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    W.virtual({ H2(1), I2(1) }, {
      parent = box, viewport = { 60, 100 }, columns = 3,
      typeOf = typeOf, indentOf = indentOf, types = htypes(W),
    })
    local h = box._virtualRows[1]
    assert_eq(lastPoint(h)[4], 20, "cuelga de la sangría, como sus ítems")
    assert_eq(h._set.width, 40, "y su ancho se recorta para no salirse del viewport")
  end)

  it("sin indentOf, el layout es EXACTAMENTE el de antes", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    W.virtual({ H(1), I(1), I(2), I(3) }, {
      parent = box, viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = htypes(W),
    })
    local r = box._virtualRows
    assert_eq(lastPoint(r[2])[4], 0); assert_eq(lastPoint(r[3])[4], 20)
    assert_eq(lastPoint(r[4])[4], 40)
  end)

  it("indentOf exige el modo heterogéneo (types)", function()
    local W = helper.loadWeaveWow()
    assert_error(function()
      W.virtual({ 1, 2, 3, 4 }, {
        parent = W.new("Frame", { size = { 60, 100 } }), viewport = { 60, 100 },
        rowHeight = 20, render = function() end, indentOf = indentOf,
      })
    end, "indentOf")
  end)

  it("indentOf debe ser una función y devolver un número >= 0", function()
    local W = helper.loadWeaveWow()
    assert_error(function()
      W.virtual({ I(1) }, {
        parent = W.new("Frame", { size = { 60, 100 } }), viewport = { 60, 100 },
        columns = 3, typeOf = typeOf, types = htypes(W), indentOf = 20,
      })
    end, "indentOf")
    assert_error(function()
      W.virtual({ I(1) }, {
        parent = W.new("Frame", { size = { 60, 100 } }), viewport = { 60, 100 },
        columns = 3, typeOf = typeOf, types = htypes(W),
        indentOf = function() return -5 end,
      })
    end, "indentOf")
  end)

end)

describe("Weave.virtual Fase 2: Resize (FR Coffer 2026-08-27)", function()

  it("Resize{ height } re-ventana el stream sin recrear la lista", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 40 } })
    -- viewport 40 de alto, ítems de 20 en 1 columna → asoman 3 filas (2 + la fraccional)
    local stream = {}
    for i = 1, 20 do stream[i] = I(i) end
    local inst = W.virtual(stream, {
      parent = box, viewport = { 60, 40 }, columns = 1, typeOf = typeOf, types = htypes(W),
    })
    local shown = #box._virtualRows
    inst:Resize({ height = 100 })
    assert_true(#box._virtualRows > shown, "más alto = más filas del stream a la vista")
    assert_eq(box._virtualRows[1]._set.text, "i1", "y sigue siendo la misma lista")
  end)

  it("Resize{ columns } re-empaqueta el flujo y re-ancha las celdas", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    local inst = W.virtual({ I(1), I(2), I(3) }, {
      parent = box, viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = htypes(W),
    })
    assert_eq(lastPoint(box._virtualRows[2])[4], 20, "3 columnas → colWidth 20")
    inst:Resize({ columns = 2 })
    local r = box._virtualRows
    assert_eq(lastPoint(r[2])[4], 30, "2 columnas → colWidth 30")
    assert_eq(lastPoint(r[3])[4], 0,  "el tercero baja a una fila nueva")
    assert_eq(lastPoint(r[3])[5], -20)
  end)

  it("Resize{ width } re-ancha las filas de ancho completo", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    local inst = W.virtual({ H(1), I(1) }, {
      parent = box, viewport = { 60, 100 }, columns = 3, typeOf = typeOf, types = htypes(W),
    })
    assert_eq(box._virtualRows[1]._set.width, 60)
    inst:Resize({ width = 90 })
    assert_eq(box._virtualRows[1]._set.width, 90, "la cabecera sigue al viewport")
  end)

  it("crecer añade frames al pool DEL TIPO que los necesita", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 40 } })
    local stream = {}
    for i = 1, 20 do stream[i] = I(i) end
    local inst = W.virtual(stream, {
      parent = box, viewport = { 60, 40 }, columns = 1, typeOf = typeOf, types = htypes(W),
    })
    local before = helper.frameCount()
    inst:Resize({ height = 200 })
    assert_true(helper.frameCount() > before, "el pool crece con el viewport")
  end)

end)
