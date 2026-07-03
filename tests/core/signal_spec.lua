-- signal_spec.lua — contrato de Weave.signal + Weave.effect + Weave.batch (API-v0 §1).
-- Bloque 1 de M0. Se lee como ejemplos de uso: cada `it` es una promesa de la API.

local helper = dofile("tests/helper.lua")

describe("Weave.signal", function()

  it("guarda un valor inicial y lo devuelve al leerla con s()", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    assert_eq(hp(), 100)
  end)

  it("set() cambia el valor", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    hp:set(50)
    assert_eq(hp(), 50)
  end)

  it("peek() lee el valor igual que s() (fuera de un effect son equivalentes)", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    assert_eq(hp:peek(), 100)
  end)

  it("acepta nil como valor (una señal puede estar vacía)", function()
    local W = helper.loadWeave()
    local target = W.signal(nil)
    assert_eq(target(), nil)
    target:set("boss")
    assert_eq(target(), "boss")
    target:set(nil)
    assert_eq(target(), nil)
  end)

end)

describe("Weave.effect (reacciona a las señales que lee)", function()

  it("corre inmediatamente al crearse", function()
    local W = helper.loadWeave()
    local runs = 0
    W.effect(function() runs = runs + 1 end)
    assert_eq(runs, 1)
  end)

  it("se re-ejecuta cuando cambia una señal que leyó", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local seen
    W.effect(function() seen = hp() end)
    hp:set(42)
    assert_eq(seen, 42)
  end)

  it("NO se re-ejecuta si set() recibe el mismo valor (equals corta la propagación)", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local runs = 0
    W.effect(function() hp(); runs = runs + 1 end)
    hp:set(100) -- mismo valor
    assert_eq(runs, 1, "no debió re-ejecutarse")
  end)

  it("NO reacciona a señales leídas con peek()", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local runs = 0
    W.effect(function() hp:peek(); runs = runs + 1 end)
    hp:set(50)
    assert_eq(runs, 1, "peek no debe crear dependencia")
  end)

  it("puede depender de varias señales a la vez", function()
    local W = helper.loadWeave()
    local hp, max = W.signal(50), W.signal(100)
    local pct
    W.effect(function() pct = hp() / max() end)
    assert_eq(pct, 0.5)
    max:set(200)
    assert_eq(pct, 0.25)
  end)

  it("re-trackea sus dependencias en cada ejecución (deps dinámicas)", function()
    local W = helper.loadWeave()
    local useA = W.signal(true)
    local a, b = W.signal("A"), W.signal("B")
    local runs = 0
    W.effect(function()
      runs = runs + 1
      if useA() then a() else b() end
    end)
    assert_eq(runs, 1)
    b:set("B2")            -- b NO es dependencia todavía
    assert_eq(runs, 1, "b no debía disparar mientras no se lee")
    useA:set(false)        -- ahora el effect lee b
    assert_eq(runs, 2)
    a:set("A2")            -- a YA no es dependencia
    assert_eq(runs, 2, "a no debía disparar cuando dejó de leerse")
    b:set("B3")
    assert_eq(runs, 3)
  end)

  it("dispose() lo apaga (y es idempotente)", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local runs = 0
    local h = W.effect(function() hp(); runs = runs + 1 end)
    h:dispose()
    h:dispose() -- segunda vez: no explota
    hp:set(1)
    assert_eq(runs, 1, "un effect dispuesto no reacciona")
  end)

  it("dos effects sobre la misma señal reaccionan ambos", function()
    local W = helper.loadWeave()
    local hp = W.signal(1)
    local total = 0
    W.effect(function() total = total + hp() end)   -- corre con 1
    W.effect(function() total = total + hp() * 10 end) -- corre con 10
    hp:set(2) -- +2 y +20
    assert_eq(total, 33)
  end)

end)

describe("opts.equals (comparador propio)", function()

  it("permite decidir qué cuenta como 'cambió'", function()
    local W = helper.loadWeave()
    -- redondeando: 1.24 → 1.2, 1.26 → 1.3; solo notifica si cambia el redondeo
    local x = W.signal(1.24, { equals = function(a, b)
      return math.floor(a * 10 + 0.5) == math.floor(b * 10 + 0.5)
    end })
    local runs = 0
    W.effect(function() x(); runs = runs + 1 end)
    x:set(1.249) -- mismo redondeo → no notifica
    assert_eq(runs, 1)
    x:set(1.26)  -- cambia el redondeo → notifica
    assert_eq(runs, 2)
  end)

end)

describe("Weave.batch (agrupar escrituras)", function()

  it("varios set() dentro de un batch → los effects corren UNA sola vez al final", function()
    local W = helper.loadWeave()
    local hp, max = W.signal(100), W.signal(100)
    local runs = 0
    W.effect(function() hp(); max(); runs = runs + 1 end)
    W.batch(function()
      hp:set(50)
      max:set(200)
    end)
    assert_eq(runs, 2, "1 al crear + 1 al cerrar el batch (no 3)")
  end)

  it("dentro del batch, leer una señal ya ve el valor nuevo", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    W.batch(function()
      hp:set(50)
      assert_eq(hp:peek(), 50)
    end)
  end)

  it("si la función del batch lanza error, el error se propaga pero el sistema queda usable", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    local runs = 0
    W.effect(function() hp(); runs = runs + 1 end)
    assert_error(function()
      W.batch(function() hp:set(1) error("boom") end)
    end, "boom")
    hp:set(2) -- el sistema sigue vivo
    assert_eq(runs >= 2, true, "los effects deben seguir funcionando tras el error")
  end)

end)

describe("validación de argumentos (errores claros para el dev)", function()

  it("effect exige una función", function()
    local W = helper.loadWeave()
    assert_error(function() W.effect(42) end, "function")
  end)

  it("set exige llamarse con dos puntos (hp:set, no hp.set)", function()
    local W = helper.loadWeave()
    local hp = W.signal(100)
    assert_error(function() hp.set(5) end) -- olvidó el ':' — error, no corrupción silenciosa
  end)

end)
