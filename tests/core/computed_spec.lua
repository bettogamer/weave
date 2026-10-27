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

-- Bloque A (FR Coffer 2026-09-02, ADR-0012): un computed que NADIE observa no trabaja.
-- Antes la cola recalculaba todo computed sucio aunque nadie lo leyera; ahora, si una
-- dependencia cambia y el computed no tiene observadores en ese instante, se queda
-- SUCIO (O(1)) y suelta sus dependencias: no necesita más avisos, la próxima lectura
-- lo recalcula contra el valor ACTUAL. Con observadores, todo sigue igual (empuje).
describe("Weave.computed sin observadores (perezoso de verdad)", function()

  it("leído a mano (sin effect), un cambio de dependencia NO lo recalcula", function()
    local W = helper.loadWeave()
    local hp = W.signal(1)
    local calls = 0
    local c = W.computed(function() calls = calls + 1 return hp() * 10 end)
    assert_eq(c(), 10)
    hp:set(2); hp:set(3); hp:set(4)
    assert_eq(calls, 1, "nadie lo observa: tres cambios, cero recálculos")
    assert_eq(c(), 40, "pero la siguiente lectura ve el valor actual")
    assert_eq(calls, 2, "y paga UN recálculo, no tres")
  end)

  it("peek() también lo pone al día", function()
    local W = helper.loadWeave()
    local hp = W.signal(1)
    local c = W.computed(function() return hp() + 1 end)
    c()
    hp:set(9)
    assert_eq(c:peek(), 10)
  end)

  it("con un effect observándolo sigue siendo de empuje: recalcula y avisa", function()
    local W = helper.loadWeave()
    local hp = W.signal(1)
    local calls, seen = 0, nil
    local c = W.computed(function() calls = calls + 1 return hp() * 2 end)
    W.effect(function() seen = c() end)
    hp:set(5)
    assert_eq(calls, 2)
    assert_eq(seen, 10, "el effect se enteró sin que nadie leyera a mano")
  end)

  it("cuando su último effect deja de leerlo, vuelve a ser perezoso", function()
    local W = helper.loadWeave()
    local hp, awake = W.signal(1), W.signal(true)
    local calls = 0
    local c = W.computed(function() calls = calls + 1 return hp() end)
    W.effect(function() if awake() then c() end end)
    assert_eq(calls, 1)
    awake:set(false)            -- el effect ya no lee c (re-traquea en cada pasada)
    hp:set(2); hp:set(3)
    assert_eq(calls, 1, "dormido, el pipeline de arriba no se recalcula")
    awake:set(true)             -- al despertar lee el valor ACTUAL
    assert_eq(calls, 2)
    assert_eq(c(), 3)
  end)

  it("en cadena (A → B) la pereza sube: tras soltarse, A deja de recalcularse", function()
    local W = helper.loadWeave()
    local src = W.signal(1)
    local aCalls, bCalls = 0, 0
    local a = W.computed(function() aCalls = aCalls + 1 return src() + 1 end)
    local b = W.computed(function() bCalls = bCalls + 1 return a() * 2 end)
    assert_eq(b(), 4)
    for v = 2, 6 do src:set(v) end
    assert_true(aCalls <= 2, "a lo sumo un recálculo de más por nivel (fue " .. aCalls .. ")")
    assert_eq(bCalls, 1, "B nadie lo observa: no se recalcula")
    assert_eq(b(), 14, "la lectura reconstruye la cadena con el valor actual")
  end)

  it("re-ejecutar un effect NO ensucia sus computeds (no se recalculan sin cambios)", function()
    local W = helper.loadWeave()
    local hp, other = W.signal(1), W.signal(0)
    local calls = 0
    local c = W.computed(function() calls = calls + 1 return hp() end)
    W.effect(function() c(); other() end)
    other:set(1); other:set(2) -- el effect se re-ejecuta, c no cambió
    assert_eq(calls, 1, "soltar y re-coger deps en la misma pasada no cuenta como 'sin observadores'")
  end)

end)
