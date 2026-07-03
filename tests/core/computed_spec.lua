-- computed_spec.lua — contract for Weave.computed (API-v0 §1): lazy, cached, chainable.
-- M0 block 3a.

local helper = dofile("tests/helper.lua")

describe("Weave.computed (fórmulas derivadas)", function()

  it("deriva un valor de otras señales y se lee como una señal", function()
    local W = helper.loadWeave()
    local hp, max = W.signal(50), W.signal(200)
    local pct = W.computed(function() return hp() / max() end)
    assert_eq(pct(), 0.25)
  end)

  it("es LAZY: la fórmula no corre al crearse, solo en la primera lectura", function()
    local W = helper.loadWeave()
    local calls = 0
    local c = W.computed(function() calls = calls + 1 return 1 end)
    assert_eq(calls, 0, "crear el computed no debe ejecutar la fórmula")
    c()
    assert_eq(calls, 1)
  end)

  it("CACHEA: leer varias veces sin cambios ejecuta la fórmula una sola vez", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local calls = 0
    local c = W.computed(function() calls = calls + 1 return hp() * 2 end)
    assert_eq(c(), 200)
    assert_eq(c(), 200)
    assert_eq(c(), 200)
    assert_eq(calls, 1, "sin cambios en las deps, la fórmula no se repite")
  end)

  it("se recalcula cuando cambió una dependencia (al volver a leerse)", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local c = W.computed(function() return hp() * 2 end)
    assert_eq(c(), 200)
    hp:set(10)
    assert_eq(c(), 20)
  end)

  it("un effect que lee un computed se re-ejecuta cuando el computed cambia", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local pct = W.computed(function() return hp() / 100 end)
    local seen
    W.effect(function() seen = pct() end)
    assert_eq(seen, 1)
    hp:set(30)
    assert_eq(seen, 0.3)
  end)

  it("si el recálculo da el MISMO resultado, no molesta a los effects (corta la cadena)", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    -- low stays true while hp >= 30: many hp changes, same derived value
    local low = W.computed(function() return hp() < 30 end)
    local runs = 0
    W.effect(function() low(); runs = runs + 1 end)
    assert_eq(runs, 1)
    hp:set(80) -- low sigue false
    hp:set(50) -- low sigue false
    assert_eq(runs, 1, "el effect no debe correr si el computed no cambió de valor")
    hp:set(10) -- low pasa a true
    assert_eq(runs, 2)
  end)

  it("los computeds se encadenan (computed que lee computed)", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local pct  = W.computed(function() return hp() / 100 end)
    local text = W.computed(function() return ("%d%%"):format(pct() * 100) end)
    assert_eq(text(), "100%")
    hp:set(45)
    assert_eq(text(), "45%")
  end)

  it("DIAMANTE: una señal con dos ramas que convergen propaga UNA vez y consistente", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local double = W.computed(function() return hp() * 2 end)
    local half   = W.computed(function() return hp() / 2 end)
    local runs, seen = 0, nil
    W.effect(function()
      runs = runs + 1
      seen = double() + half() -- both branches must show the SAME hp generation
    end)
    assert_eq(runs, 1)
    assert_eq(seen, 250)   -- 200 + 50
    hp:set(10)
    assert_eq(runs, 2, "un solo set → una sola re-ejecución (sin glitches intermedios)")
    assert_eq(seen, 25)    -- 20 + 5, nunca una mezcla de valores viejos y nuevos
  end)

  it("peek() lee el valor actual sin crear dependencia", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local c = W.computed(function() return hp() * 2 end)
    local runs = 0
    W.effect(function() c:peek(); runs = runs + 1 end)
    hp:set(1)
    assert_eq(runs, 1, "peek de un computed no debe suscribir al effect")
  end)

  it("exige una función", function()
    local W = helper.loadWeave()
    assert_error(function() W.computed(42) end, "function")
  end)

  it("un ciclo (la fórmula se lee a sí misma) da error claro, no cuelgue", function()
    local W = helper.loadWeave()
    local c
    c = W.computed(function() return c() end)
    assert_error(function() c() end, "cycle")
  end)

end)
