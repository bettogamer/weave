-- virtual_spec.lua — contract for Weave.virtual (API-v0 §4, M10/ADR-0010, Fase 1):
-- a VIRTUALIZED grid, sibling of Weave.each for lists of THOUSANDS. The invariant
-- that separates it from each: the pool is FIXED to the viewport (not to the list).
-- render runs once per POOLED frame; scrolling only re-assigns DATA to those frames
-- and re-positions them by a fractional pixel offset — no frame is ever created by
-- scrolling, and (like each) never in combat.
--
-- Uses the pure planner Weave._windowPlan under the hood (tested in core/window_spec).
-- Positioning (screen coords, anchored to the container = the viewport):
--   entry j → grid-row r = floor((j-1)/columns), col = (j-1)%columns
--   x = col * (viewportWidth/columns);  yOff = offset - (r - firstRow)*stride

local helper = dofile("tests/wow_helper.lua")

-- A source of N numbered entries (1..N). Signals compare by identity, so every
-- change sets a NEW array.
local function seq(n)
  local t = {}
  for i = 1, n do t[i] = i end
  return t
end

-- Standard row: a Button whose text mirrors item().
local function numberRow(W)
  return function(item, index)
    return W.new("Button", {
      size = { 40, 40 },
      text = W.computed(function()
        local v = item()
        return v == nil and "" or tostring(v) -- idle pooled rows hold nil
      end),
    })
  end
end

local function lastPoint(row) return row._points[#row._points] end

describe("Weave.virtual: pool FIJO (la esencia de virtualizar)", function()

  it("materializa solo las filas del viewport, no una por entrada", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 80, 100 } })
    local before = helper.frameCount()
    -- rowHeight 20, viewport 100 → stride 20, poolRows = ceil(100/20)+1 = 6
    W.virtual(seq(100), {
      parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W),
    })
    assert_eq(helper.frameCount() - before, 6, "1000 entradas caben en un pool de 6 frames")
    assert_eq(#box._virtualRows, 6, "solo se pintan las visibles")
  end)

  it("la fuente crece a miles: el pool NO crece (cero frames nuevos)", function()
    local W = helper.loadWeaveWow()
    local source = W.signal(seq(20))
    local box = W.new("Frame", { size = { 80, 100 } })
    W.virtual(source, { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) })
    local before = helper.frameCount()
    source:set(seq(5000))
    assert_eq(helper.frameCount(), before, "más datos no es más frames: el pool es fijo")
    assert_eq(#box._virtualRows, 6)
  end)

  it("clipa el viewport: la fila extra del scroll fraccional no se sale del panel", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 80, 100 } })
    W.virtual(seq(100), { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) })
    assert_true(box._clipsChildren, "el contenedor recorta lo que sobresale del viewport")
  end)

  it("las filas visibles arrancan en la 1ª entrada", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 80, 100 } })
    W.virtual(seq(100), { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) })
    assert_eq(box._virtualRows[1]._set.text, "1")
    assert_eq(box._virtualRows[6]._set.text, "6")
  end)

end)

describe("Weave.virtual: render una sola vez por fila del pool", function()

  it("scrollear re-glasea datos, no re-hornea (render corre `capacity` veces)", function()
    local W = helper.loadWeaveWow()
    local scroll = W.signal(0)
    local calls = 0
    local box = W.new("Frame", { size = { 80, 100 } })
    W.virtual(seq(100), {
      parent = box, viewport = { 80, 100 }, rowHeight = 20, scroll = scroll,
      render = function(item)
        calls = calls + 1
        return W.new("Button", { text = W.computed(function() return tostring(item()) end) })
      end,
    })
    assert_eq(calls, 6, "una vez por fila del pool")
    scroll:set(200)
    assert_eq(calls, 6, "scrollear NO vuelve a llamar render")
  end)

end)

describe("Weave.virtual: scroll (ventana + fraccional)", function()

  it("scroll de N filas re-asigna datos al pool fijo, sin crear frames", function()
    local W = helper.loadWeaveWow()
    local scroll = W.signal(0)
    local box = W.new("Frame", { size = { 80, 100 } })
    W.virtual(seq(100), { parent = box, viewport = { 80, 100 }, rowHeight = 20, scroll = scroll, render = numberRow(W) })
    local before = helper.frameCount()
    scroll:set(40) -- 2 filas
    assert_eq(helper.frameCount(), before, "scrollear no materializa")
    assert_eq(box._virtualRows[1]._set.text, "3", "la ventana ahora empieza en la 3")
    assert_eq(box._virtualRows[6]._set.text, "8")
  end)

  it("scroll fraccional: el pool se desplaza por offset de píxel (no salta de fila)", function()
    local W = helper.loadWeaveWow()
    local scroll = W.signal(0)
    local box = W.new("Frame", { size = { 80, 100 } })
    W.virtual(seq(100), { parent = box, viewport = { 80, 100 }, rowHeight = 20, scroll = scroll, render = numberRow(W) })
    scroll:set(10) -- media fila
    local p = lastPoint(box._virtualRows[1])
    assert_eq(p[1], "TOPLEFT")
    assert_true(rawequal(p[2], box), "cada celda se ancla al viewport (contenedor)")
    assert_eq(p[4], 0, "columna 0 → x = 0")
    assert_eq(p[5], 10, "la fila superior se empuja 10px por el offset fraccional")
    assert_eq(lastPoint(box._virtualRows[2])[5], -10, "la 2ª fila queda 10px por debajo")
  end)

end)

describe("Weave.virtual: grid (N columnas)", function()

  it("coloca cada celda en (columna, fila) del grid", function()
    local W = helper.loadWeaveWow()
    -- 6 columnas, rowHeight 40, viewport 240×80 → colWidth 40, stride 40, capacity 18
    local box = W.new("Frame", { size = { 240, 80 } })
    W.virtual(seq(100), {
      parent = box, viewport = { 240, 80 }, rowHeight = 40, columns = 6, render = numberRow(W),
    })
    assert_eq(#box._virtualRows, 18, "3 filas × 6 columnas visibles")
    local e1, e7, e8 = box._virtualRows[1], box._virtualRows[7], box._virtualRows[8]
    assert_eq(lastPoint(e1)[4], 0);  assert_eq(lastPoint(e1)[5], 0)    -- fila0 col0
    assert_eq(lastPoint(e7)[4], 0);  assert_eq(lastPoint(e7)[5], -40)  -- fila1 col0
    assert_eq(lastPoint(e8)[4], 40); assert_eq(lastPoint(e8)[5], -40)  -- fila1 col1
  end)

end)

describe("Weave.virtual: contentHeight (para la barra de Craft)", function()

  it("expone el alto total de la lista completa, reactivo al tamaño de la fuente", function()
    local W = helper.loadWeaveWow()
    local source = W.signal(seq(100))
    local box = W.new("Frame", { size = { 80, 100 } })
    local v = W.virtual(source, { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) })
    local h = W.computed(function() return v:contentHeight() end)
    assert_eq(h(), 2000, "100 filas × 20px")
    source:set(seq(50))
    assert_eq(h(), 1000, "la barra reacciona: la lista encogió")
  end)

  it("contentHeight en grid usa ceil(total/columns) filas", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 240, 80 } })
    local v = W.virtual(seq(100), { parent = box, viewport = { 240, 80 }, rowHeight = 40, columns = 6, render = numberRow(W) })
    assert_eq(v:contentHeight(), 680, "ceil(100/6)=17 filas × 40px")
  end)

end)

describe("Weave.virtual: dueño del scroll", function()

  it("sin opts.scroll: crea su propia señal y la rueda del ratón mueve la ventana", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 80, 100 } })
    W.virtual(seq(100), { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) })
    assert_eq(box._virtualRows[1]._set.text, "1")
    local onWheel = box._scripts.OnMouseWheel
    assert_true(onWheel ~= nil, "engancha la rueda cuando es dueño del scroll")
    onWheel(box, -1) -- una muesca hacia abajo = una fila
    assert_eq(box._virtualRows[1]._set.text, "2", "la rueda avanza la ventana")
  end)

end)

describe("Weave.virtual: combate", function()

  it("scrollear en combate no crea frames (el pool ya es fijo)", function()
    local W = helper.loadWeaveWow()
    local scroll = W.signal(0)
    local box = W.new("Frame", { size = { 80, 100 } })
    W.virtual(seq(100), { parent = box, viewport = { 80, 100 }, rowHeight = 20, scroll = scroll, render = numberRow(W) })
    helper.setInCombat(true)
    local before = helper.frameCount()
    scroll:set(400)
    assert_eq(helper.frameCount(), before, "en combate scrollear solo re-glasea")
    assert_eq(box._virtualRows[1]._set.text, "21", "y la ventana sí se movió")
  end)

  it("crear la lista EN combate es error duro (como each/new)", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 80, 100 } })
    helper.setInCombat(true)
    assert_error(function()
      W.virtual(seq(100), { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) })
    end, "combat")
  end)

end)

describe("Weave.virtual: taint", function()

  it("un dato secreto no rompe la lista: la fila degrada, la ventana se pinta", function()
    local W = helper.loadWeaveWow({ issecretvalue = helper.isFakeSecret })
    local secret = helper.newFakeSecret()
    local data = seq(100)
    data[1] = secret
    local box = W.new("Frame", { size = { 80, 100 } })
    helper.silently(function()
      W.virtual(data, {
        parent = box, viewport = { 80, 100 }, rowHeight = 20,
        render = function(item)
          return W.new("Button", {
            text = W.computed(function()
              local v = item()
              if issecretvalue and issecretvalue(v) then return "??" end
              return tostring(v)
            end),
          })
        end,
      })
    end)
    assert_eq(#box._virtualRows, 6, "la ventana entera se pinta pese al secreto")
    assert_eq(box._virtualRows[1]._set.text, "??", "la fila del secreto degrada su texto")
  end)

end)

describe("Weave.virtual: scopes", function()

  it("dispose() del scope libera los binds del pool y oculta los frames", function()
    local W = helper.loadWeaveWow()
    local source = W.signal(seq(100))
    local box = W.new("Frame", { size = { 80, 100 } })
    local scope = W.scope()
    scope:run(function()
      W.virtual(source, { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) })
    end)
    local row1 = box._virtualRows[1]
    scope:dispose()
    source:set(seq(3)) -- would re-window if the effect were still alive
    assert_eq(row1._set.text, "1", "el bind de la fila muere con el scope")
    assert_false(row1:IsShown(), "las filas se ocultan al disponer")
  end)

end)
