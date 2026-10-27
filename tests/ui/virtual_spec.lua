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

describe("Weave.virtual: padding (inset — no afeitar fila/columna 0 con el clip, FR Coffer)", function()

  it("desplaza el origen del grid por padding y encoge colWidth simétricamente", function()
    local W = helper.loadWeaveWow()
    -- viewport 240×80, 6 columnas, padding 6 → colWidth (240-12)/6 = 38
    local box = W.new("Frame", { size = { 240, 80 } })
    W.virtual(seq(100), {
      parent = box, viewport = { 240, 80 }, rowHeight = 40, columns = 6, padding = 6,
      render = numberRow(W),
    })
    local e1, e2 = box._virtualRows[1], box._virtualRows[2]
    assert_eq(lastPoint(e1)[4], 6,  "columna 0 arranca en padH, no en 0 (ya no flush con el clip)")
    assert_eq(lastPoint(e1)[5], -6, "fila 0 arranca padV por debajo del tope")
    assert_eq(lastPoint(e2)[4], 44, "columna 1 = padH + colWidth (6 + 38)")
  end)

  it("paddingH/paddingV pisan el escalar por eje", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 240, 80 } })
    W.virtual(seq(100), {
      parent = box, viewport = { 240, 80 }, rowHeight = 40, columns = 6,
      padding = 6, paddingH = 10, paddingV = 0, render = numberRow(W),
    })
    local e1 = box._virtualRows[1]
    assert_eq(lastPoint(e1)[4], 10, "paddingH pisa el escalar")
    assert_eq(lastPoint(e1)[5], 0,  "paddingV 0 pisa el escalar (fila pegada al tope)")
  end)

  it("padding crece contentHeight en padTop+padBottom", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 80, 100 } })
    -- 100 filas × 20 = 2000; +padV 8 arriba + 8 abajo = 2016
    local v = W.virtual(seq(100), {
      parent = box, viewport = { 80, 100 }, rowHeight = 20, padding = 8, render = numberRow(W),
    })
    assert_eq(v:contentHeight(), 2016)
  end)

  it("padding horizontal que no deja hueco para columnas → error claro", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 80, 100 } })
    assert_error(function()
      W.virtual(seq(10), {
        parent = box, viewport = { 80, 100 }, rowHeight = 20, padding = 40, render = numberRow(W),
      })
    end, "no room")
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

local function capturePrints(fn)
  local lines, realPrint = {}, print
  _G.print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
  local ok, err = pcall(fn)
  _G.print = realPrint
  if not ok then error(err, 0) end
  return lines
end

-- Una lista viva de 80x100 con rowHeight 20 → pool de ceil(100/20)+1 = 6 filas.
local function grid(W, opts)
  local box = W.new("Frame", { size = { 80, 100 } })
  local o = {
    parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W),
  }
  for k, v in pairs(opts or {}) do o[k] = v end
  return box, W.virtual(seq(100), o)
end

describe("Weave.virtual: Resize — viewport y columnas mutables (FR Coffer 2026-08-27)", function()

  it("Resize{ height } re-ventana: más alto = más filas, y el pool crece con él", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    assert_eq(#box._virtualRows, 6)
    local before = helper.frameCount()
    inst:Resize({ height = 200 })
    assert_eq(#box._virtualRows, 11, "ceil(200/20)+1 = 11 filas")
    assert_eq(helper.frameCount() - before, 5, "solo se crean las que faltaban")
    assert_eq(box._virtualRows[11]._set.text, "11", "y traen su dato")
  end)

  it("encoger NUNCA crea frames: oculta las sobrantes y conserva el pool", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    inst:Resize({ height = 200 })
    local pooled = helper.frameCount()
    inst:Resize({ height = 40 })
    assert_eq(helper.frameCount(), pooled, "encoger no materializa nada")
    assert_eq(#box._virtualRows, 3, "ceil(40/20)+1 = 3 filas a la vista")
    inst:Resize({ height = 200 })
    assert_eq(helper.frameCount(), pooled, "y volver a crecer reusa el pool que ya había")
    assert_eq(#box._virtualRows, 11)
  end)

  it("Resize{ columns } re-planifica: nuevo ancho de celda y nueva rejilla", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    assert_eq(lastPoint(box._virtualRows[1])[4], 0)
    inst:Resize({ columns = 2 })
    local r = box._virtualRows
    assert_eq(lastPoint(r[1])[4], 0)
    assert_eq(lastPoint(r[2])[4], 40, "2 columnas sobre 80px → colWidth 40")
    assert_eq(lastPoint(r[2])[5], 0, "y el segundo va en la MISMA fila")
    assert_eq(lastPoint(r[3])[5], -20, "el tercero baja")
  end)

  it("Resize{ width } recalcula el ancho de columna", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W, { columns = 2 })
    assert_eq(lastPoint(box._virtualRows[2])[4], 40)
    inst:Resize({ width = 120 })
    assert_eq(lastPoint(box._virtualRows[2])[4], 60, "120/2 = 60")
  end)

  it("contentHeight se re-anuncia (la barra de Craft lo sigue)", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    assert_eq(inst:contentHeight(), 2000, "100 filas de 20")
    inst:Resize({ columns = 2 })
    assert_eq(inst:contentHeight(), 1000, "50 filas de 20")
  end)

  it("es idempotente: los mismos valores no repintan nada", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    local row = box._virtualRows[1]
    local painted = #row._points
    inst:Resize({ height = 100 })
    inst:Resize({ width = 80, height = 100, columns = 1 })
    assert_eq(#row._points, painted, "sin cambio de geometría, ni un SetPoint")
  end)

  it("SetViewport y SetColumns son azúcar de Resize", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    inst:SetViewport(120, 200)
    assert_eq(#box._virtualRows, 11)
    inst:SetColumns(2)
    assert_eq(lastPoint(box._virtualRows[2])[4], 60, "120/2 = 60")
  end)

  it("valida lo mismo que el constructor", function()
    local W = helper.loadWeaveWow()
    local _, inst = grid(W)
    assert_error(function() inst:Resize(5) end, "Resize")
    assert_error(function() inst:Resize({ height = 0 }) end, "height")
    assert_error(function() inst:Resize({ width = -1 }) end, "width")
    assert_error(function() inst:Resize({ columns = 0 }) end, "columns")
  end)

  it("el padding sigue sin poder dejar el viewport sin sitio", function()
    local W = helper.loadWeaveWow()
    local _, inst = grid(W, { padding = 10 })
    assert_error(function() inst:Resize({ width = 20 }) end, "padding")
  end)

end)

describe("Weave.virtual: Resize en combate (crecer se difiere, encoger no)", function()

  it("agrandar en combate no crea frames: pinta lo que hay y avisa UNA vez", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    helper.setInCombat(true)
    local lines = capturePrints(function()
      inst:Resize({ height = 200 })
      local before = helper.frameCount() -- el vigía de PLAYER_REGEN_ENABLED ya existe
      inst:Resize({ height = 300 })      -- segundo desbordamiento: mismo silencio
      assert_eq(helper.frameCount(), before, "jamás crear filas en combate")
    end)
    assert_eq(#box._virtualRows, 6, "se ve lo que el pool permite")
    assert_eq(#lines, 1, "el aviso suena una sola vez por lista")
  end)

  it("encoger SÍ se aplica en el acto durante el combate", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    helper.setInCombat(true)
    local lines = capturePrints(function() inst:Resize({ height = 40 }) end)
    assert_eq(#box._virtualRows, 3, "encoger no necesita crear nada")
    assert_eq(#lines, 0, "y por tanto no hay nada que avisar")
  end)

  it("al salir de combate (PLAYER_REGEN_ENABLED) salda el pool y repinta", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    helper.setInCombat(true)
    helper.silently(function() inst:Resize({ height = 200 }) end)
    assert_eq(#box._virtualRows, 6, "durante el combate se ven menos filas de las ideales")
    helper.setInCombat(false)
    helper.fireEvent("PLAYER_REGEN_ENABLED")
    assert_eq(#box._virtualRows, 11, "la deuda de pool se salda al salir de combate")
    assert_eq(box._virtualRows[11]._set.text, "11")
  end)

  it("re-planifica igual en combate: la geometría no espera", function()
    local W = helper.loadWeaveWow()
    local box, inst = grid(W)
    helper.setInCombat(true)
    helper.silently(function() inst:Resize({ columns = 2 }) end)
    assert_eq(lastPoint(box._virtualRows[2])[4], 40, "colWidth nuevo YA, sin frames nuevos")
    assert_eq(inst:contentHeight(), 1000)
  end)

end)

-- Bloque B (FR Coffer 2026-09-02, ADR-0012): un virtual que nadie mira no trabaja.
-- Automático: virtual se engancha (HookScript, sin pisar al consumidor) a OnShow/OnHide
-- de su viewport y mira IsVisible(). Dormido, el effect de ventaneo sale sin leer ni
-- la fuente ni el scroll (deja de trackearlos); al despertar reconcilia contra el
-- valor ACTUAL de la fuente, no contra el que tenía al dormirse.
describe("Weave.virtual: se pausa cuando su viewport no está a la vista", function()

  local function live(W, opts)
    local box = W.new("Frame", { size = { 80, 100 } })
    local src = W.signal(seq(100))
    local o = { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) }
    for k, v in pairs(opts or {}) do o[k] = v end
    return box, src, W.virtual(src, o)
  end

  local function reversed(n)
    local t = {}
    for i = 1, n do t[i] = n - i + 1 end
    return t
  end

  it("oculto, un cambio de la fuente no replanifica ni repinta", function()
    local W = helper.loadWeaveWow()
    local box, src, inst = live(W)
    box:Hide()
    src:set(reversed(10))
    assert_eq(box._virtualRows[1]._set.text, "1", "la fila sigue con el dato de antes")
    assert_eq(inst:contentHeight(), 2000, "ni siquiera re-anuncia el alto")
  end)

  it("al volver a mostrarse se pone al día contra el valor ACTUAL", function()
    local W = helper.loadWeaveWow()
    local box, src, inst = live(W)
    box:Hide()
    src:set(reversed(10))
    src:set(reversed(3))      -- el último gana: nada de reproducir la historia
    box:Show()
    assert_eq(box._virtualRows[1]._set.text, "3")
    assert_eq(#box._virtualRows, 3)
    assert_eq(inst:contentHeight(), 60)
  end)

  it("ocultar un ANCESTRO también lo duerme (IsVisible, no IsShown)", function()
    local W = helper.loadWeaveWow()
    local win = W.new("Frame", { size = { 80, 100 } })
    local box = W.new("Frame", { parent = win, size = { 80, 100 } })
    local src = W.signal(seq(100))
    W.virtual(src, { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) })
    win:Hide()                -- la ventana de Coffer se cierra; el viewport sigue IsShown()
    src:set(reversed(10))
    assert_eq(box._virtualRows[1]._set.text, "1")
    win:Show()
    assert_eq(box._virtualRows[1]._set.text, "10")
  end)

  it("no pisa los OnShow/OnHide del consumidor (se engancha con HookScript)", function()
    local W = helper.loadWeaveWow()
    local box, src = live(W)
    local shows = 0
    box:SetScript("OnShow", function() shows = shows + 1 end) -- incluso puesto DESPUÉS
    box:Hide()
    src:set(reversed(5))
    box:Show()
    assert_eq(shows, 1, "el script del consumidor sigue corriendo")
    assert_eq(box._virtualRows[1]._set.text, "5", "y el virtual despertó igual")
  end)

  it("nace oculto: la primera pasada se hace igual (contentHeight válido desde el nacimiento)", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 80, 100 } })
    box:Hide()
    local inst = W.virtual(seq(100), {
      parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W),
    })
    assert_eq(inst:contentHeight(), 2000)
  end)

  it("scrollear dormido tampoco repinta; al despertar respeta el scroll actual", function()
    local W = helper.loadWeaveWow()
    local scroll = W.signal(0)
    local box = live(W, { scroll = scroll })
    box:Hide()
    scroll:set(40)
    assert_eq(box._virtualRows[1]._set.text, "1")
    box:Show()
    assert_eq(box._virtualRows[1]._set.text, "3", "scroll 40 / stride 20 → arranca en la 3ª")
  end)

  it("Resize mientras duerme se aplica al despertar", function()
    local W = helper.loadWeaveWow()
    local box, _, inst = live(W)
    box:Hide()
    inst:Resize({ columns = 2 })
    box:Show()
    assert_eq(lastPoint(box._virtualRows[2])[4], 40, "colWidth 80/2 = 40 al despertar")
    assert_eq(inst:contentHeight(), 1000)
  end)

  it("el caso Coffer de punta a punta: dormido, el computed del stream NO se recalcula", function()
    local W = helper.loadWeaveWow()
    local rev = W.signal(0)   -- ns.rev.* de Coffer: se re-publica en cada BAG_UPDATE
    local calls = 0
    local stream = W.computed(function() calls = calls + 1; rev(); return seq(50) end)
    local box = W.new("Frame", { size = { 80, 100 } })
    W.virtual(stream, { parent = box, viewport = { 80, 100 }, rowHeight = 20, render = numberRow(W) })
    assert_eq(calls, 1)
    box:Hide()
    for v = 1, 5 do rev:set(v) end
    assert_true(calls <= 2, "a lo sumo un recálculo hasta que se suelta (fue " .. calls .. ")")
    local asleep = calls
    rev:set(6)
    assert_eq(calls, asleep, "y desde ahí, cero: el pipeline de una ventana cerrada no corre")
    box:Show()
    assert_eq(calls, asleep + 1, "al abrir, una pasada contra el valor actual")
  end)

  it("también duerme en modo heterogéneo (types)", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { size = { 60, 100 } })
    local typeCalls = 0
    local src = W.signal({ 1, 2, 3 })
    W.virtual(src, {
      parent = box, viewport = { 60, 100 }, columns = 3,
      typeOf = function() typeCalls = typeCalls + 1 return "item" end,
      types = { item = { grid = true, height = 20, render = numberRow(W) } },
    })
    local before = typeCalls
    box:Hide()
    src:set({ 4, 5, 6, 7 })
    assert_eq(typeCalls, before, "oculto no recorre el stream (O(total)) ni replanifica")
    box:Show()
    assert_eq(#box._virtualRows, 4)
    assert_eq(box._virtualRows[1]._set.text, "4")
  end)

end)
