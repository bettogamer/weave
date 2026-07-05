-- each_spec.lua — contract for Weave.each (API-v0 §4, M6/ADR-0007): reactive
-- lists with combat-safe frame pooling. The design invariant driving everything:
-- render runs ONCE per pooled row (it bakes the frame and plugs the binds);
-- list changes only flow DATA through the per-row item/index signals — frames
-- are reused, hidden into the pool, or materialized, never destroyed, and NEVER
-- created in combat.

local helper = dofile("tests/wow_helper.lua")

-- Standard row used across specs: a Button whose text mirrors item().
local function textRow(W)
  return function(item, index)
    return W.new("Button", {
      text = W.computed(function() return tostring(item()) end),
    })
  end
end

-- Runs fn capturing everything print()ed; returns the list of printed lines.
local function capturePrints(fn)
  local lines, realPrint = {}, print
  _G.print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
  local ok, err = pcall(fn)
  _G.print = realPrint
  if not ok then error(err, 0) end
  return lines
end

describe("Weave.each: materialización", function()

  it("dentro de [W.children] crea una fila por elemento, hija del contenedor", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", {
      [W.children] = { W.each({ "a", "b", "c" }, textRow(W)) },
    })
    local rows = box._eachRows or {} -- see note at the bottom: rows exposed for specs
    assert_eq(#rows, 3)
    for i, want in ipairs({ "a", "b", "c" }) do
      assert_true(rawequal(rows[i]._parent, box), "la fila debe re-parentarse al contenedor")
      assert_eq(rows[i]._set.text, want)
    end
  end)

  it("render corre UNA sola vez por fila, aunque los datos cambien", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a", "b" })
    local calls = 0
    W.new("Frame", {
      [W.children] = {
        W.each(items, function(item)
          calls = calls + 1
          return W.new("Button", { text = item })
        end),
      },
    })
    assert_eq(calls, 2)
    items:set({ "x", "y" })
    assert_eq(calls, 2, "cambiar datos re-glasea, no re-hornea")
  end)

  it("item e index son señales: la fila se actualiza al cambiar el dato", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a", "b" })
    local box = W.new("Frame", { [W.children] = { W.each(items, textRow(W)) } })
    local before = helper.frameCount()
    items:set({ "z", "b" })
    assert_eq(box._eachRows[1]._set.text, "z")
    assert_eq(helper.frameCount(), before, "re-glasear no crea frames")
  end)

  it("con opts.parent se materializa en el acto, sin descripción padre", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", {})
    W.each({ "a" }, textRow(W), { parent = box })
    assert_eq(#box._eachRows, 1)
    assert_eq(box._eachRows[1]._set.text, "a")
  end)

  it("fuente inválida (ni tabla ni llamable) → error claro", function()
    local W = helper.loadWeaveWow()
    assert_error(function()
      local box = W.new("Frame", {})
      W.each(42, textRow(W), { parent = box })
    end, "each")
  end)

end)

describe("Weave.each: pooling (reciclaje de filas)", function()

  it("la lista encoge: la fila sobrante se oculta y conserva su frame", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a", "b", "c" })
    local box = W.new("Frame", { [W.children] = { W.each(items, textRow(W)) } })
    local row3 = box._eachRows[3] -- grab it BEFORE it leaves _eachRows for the pool
    local before = helper.frameCount()
    items:set({ "a", "b" })
    assert_false(row3:IsShown(), "la fila 3 debe esconderse en el pool")
    assert_eq(#box._eachRows, 2, "_eachRows lista solo lo visible")
    assert_true(box._eachRows[1]:IsShown())
    assert_eq(helper.frameCount(), before, "ocultar no destruye ni crea")
  end)

  it("volver a crecer reutiliza la fila del pool sin crear frames", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a", "b", "c" })
    local box = W.new("Frame", { [W.children] = { W.each(items, textRow(W)) } })
    items:set({ "a", "b" })
    local before = helper.frameCount()
    items:set({ "a", "b", "d" })
    assert_eq(helper.frameCount(), before, "la fila oculta se recicla, no se hornea otra")
    assert_true(box._eachRows[3]:IsShown())
    assert_eq(box._eachRows[3]._set.text, "d")
  end)

  it("crecer más allá del pool materializa SOLO las filas que faltan", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a", "b" })
    W.new("Frame", { [W.children] = { W.each(items, textRow(W)) } })
    local before = helper.frameCount()
    items:set({ "a", "b", "c", "d" })
    assert_eq(helper.frameCount(), before + 2)
  end)

end)

describe("Weave.each: identidad con opts.key", function()

  it("reordenar conserva el frame de cada dato (el frame viaja con la key)", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ { id = "pot" }, { id = "sword" } })
    local box = W.new("Frame", {
      [W.children] = {
        W.each(items, function(item)
          return W.new("Button", {
            text = W.computed(function() return item().id end),
          })
        end, { key = function(it) return it.id end }),
      },
    })
    local potFrame = box._eachRows[1]
    assert_eq(potFrame._set.text, "pot")
    items:set({ { id = "sword" }, { id = "pot" } })
    assert_true(rawequal(box._eachRows[2], potFrame),
      "tras reordenar, 'pot' debe seguir en SU frame")
    assert_eq(potFrame._set.text, "pot")
  end)

  it("keys duplicadas → error claro", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ { id = "x" }, { id = "x" } })
    assert_error(function()
      W.new("Frame", {
        [W.children] = {
          W.each(items, textRow(W), { key = function(it) return it.id end }),
        },
      })
    end, "duplicate key")
  end)

  it("una key secreta degrada a índice con aviso, sin romper la lista", function()
    local W = helper.loadWeaveWow({ issecretvalue = helper.isFakeSecret })
    local secret = helper.newFakeSecret()
    local items = W.signal({ { id = "a" }, { id = secret } })
    local box
    helper.silently(function()
      box = W.new("Frame", {
        [W.children] = {
          W.each(items, function()
            -- rows never OPERATE on the (possibly secret) id — literal text is safe
            return W.new("Button", { text = "?" })
          end, { key = function(it) return it.id end }),
        },
      })
    end)
    assert_eq(#box._eachRows, 2, "la lista entera debe pintarse (keying por índice)")
  end)

end)

describe("Weave.each: layout", function()

  it("pila vertical: la fila 1 se ancla al contenedor y cada fila bajo la anterior", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", { [W.children] = { W.each({ "a", "b" }, textRow(W)) } })
    local r1, r2 = box._eachRows[1], box._eachRows[2]
    assert_eq(r1._points[#r1._points][1], "TOPLEFT")
    assert_true(rawequal(r1._points[#r1._points][2], box))
    local p2 = r2._points[#r2._points]
    assert_eq(p2[1], "TOPLEFT")
    assert_true(rawequal(p2[2], r1), "la fila 2 se ancla a la fila 1")
    assert_eq(p2[3], "BOTTOMLEFT")
    assert_eq(p2[5], 0, "sin spacing el offset vertical es 0")
  end)

  it("opts.spacing separa las filas", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", {
      [W.children] = { W.each({ "a", "b" }, textRow(W), { spacing = 4 }) },
    })
    local p2 = box._eachRows[2]._points[#box._eachRows[2]._points]
    assert_eq(p2[5], -4, "spacing empuja la fila hacia abajo")
  end)

  it("opts.layout = false: each no posiciona (el consumidor manda)", function()
    local W = helper.loadWeaveWow()
    local box = W.new("Frame", {
      [W.children] = { W.each({ "a" }, textRow(W), { layout = false }) },
    })
    assert_eq(#box._eachRows[1]._points, 0)
  end)

end)

describe("Weave.each: combate (la razón de ser del pooling)", function()

  it("en combate, re-glasear y reciclar funciona — y jamás se crean frames", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a", "b", "c" })
    local box = W.new("Frame", { [W.children] = { W.each(items, textRow(W)) } })
    helper.setInCombat(true)
    local before = helper.frameCount()
    items:set({ "c", "b", "a" }) -- reassign
    items:set({ "c", "b" })      -- shrink (hide into pool)
    items:set({ "c", "b", "x" }) -- grow back within pool (recycle)
    assert_eq(helper.frameCount(), before, "en combate el pool solo recicla")
    assert_eq(box._eachRows[3]._set.text, "x")
  end)

  it("en combate con el pool agotado: pinta lo que hay y avisa UNA vez", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a", "b" })
    local box = W.new("Frame", { [W.children] = { W.each(items, textRow(W)) } })
    helper.setInCombat(true)
    local before = helper.frameCount()
    local lines = capturePrints(function()
      items:set({ "a", "b", "c", "d" })
      items:set({ "a", "b", "c", "d", "e" }) -- second overflow: same silence
    end)
    assert_eq(helper.frameCount(), before, "jamás crear frames en combate")
    assert_eq(#box._eachRows, 2, "se pinta lo que el pool permite")
    assert_eq(#lines, 1, "el aviso suena una sola vez por each")
  end)

  it("al salir de combate (PLAYER_REGEN_ENABLED) completa la reconciliación solo", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a", "b" })
    local box = W.new("Frame", { [W.children] = { W.each(items, textRow(W)) } })
    helper.setInCombat(true)
    helper.silently(function() items:set({ "a", "b", "c", "d" }) end)
    helper.setInCombat(false)
    helper.fireEvent("PLAYER_REGEN_ENABLED")
    assert_eq(#box._eachRows, 4, "la deuda de filas se salda al salir de combate")
    assert_eq(box._eachRows[4]._set.text, "d")
  end)

  it("opts.warm pre-hornea filas que absorben crecimiento EN combate", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a", "b" })
    local box = W.new("Frame", {
      [W.children] = { W.each(items, textRow(W), { warm = 4 }) },
    })
    helper.setInCombat(true)
    local before = helper.frameCount()
    local lines = capturePrints(function() items:set({ "a", "b", "c", "d" }) end)
    assert_eq(#lines, 0, "con pool suficiente no hay nada que avisar")
    assert_eq(helper.frameCount(), before)
    assert_eq(#box._eachRows, 4)
    assert_eq(box._eachRows[4]._set.text, "d")
  end)

end)

describe("Weave.each: scopes", function()

  it("dispose() del scope libera los binds de las filas y las oculta", function()
    local W = helper.loadWeaveWow()
    local items = W.signal({ "a" })
    local box
    local scope = W.scope()
    scope:run(function()
      box = W.new("Frame", { [W.children] = { W.each(items, textRow(W)) } })
    end)
    scope:dispose()
    items:set({ "z" })
    assert_eq(box._eachRows[1]._set.text, "a", "el bind de la fila debe morir con el scope")
    assert_false(box._eachRows[1]:IsShown())
  end)

end)

-- NOTE for the implementation (Bloque 3): specs reach rows via `container._eachRows`
-- (array of row frames in LIST order; pooled spares excluded). Frames are plain
-- tables in WoW, so each keeps this bookkeeping field on the real container too —
-- one shared contract for specs, DevTools (v2) and debugging in-game.
