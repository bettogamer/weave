-- taint_spec.lua — contract for the taint semantics of the core (API-v0 §3, ADR-0003).
-- M0 block 4. Uses fake secrets (helper) + an injected detector; the wow/ layer will
-- inject the real issecretvalue in M1 via Weave._setSecretDetector.

local helper = dofile("tests/helper.lua")

local function loadWeaveWithDetector()
  local W = helper.loadWeave()
  W._setSecretDetector(helper.isFakeSecret)
  return W
end

describe("señales taint-aware (tabla de verdad API-v0 §3)", function()

  it("un set() normal no marca nada: isSecret() es false", function()
    local W = loadWeaveWithDetector()
    local hp = W.signal(100, { fallback = 0 })
    hp:set(50)
    assert_eq(hp(), 50)
    assert_false(hp:isSecret())
  end)

  it("set(secret) CON fallback declarado: los lectores ven el fallback e isSecret() es true", function()
    local W = loadWeaveWithDetector()
    local hp = W.signal(100, { fallback = 0 })
    hp:set(helper.newFakeSecret())
    assert_eq(hp(), 0, "el lector debe ver el fallback, no el secret")
    assert_true(hp:isSecret())
  end)

  it("un effect enchufado recibe el fallback sin que nada crashee", function()
    local W = loadWeaveWithDetector()
    local hp = W.signal(100, { fallback = 0 })
    local seen
    W.effect(function() seen = hp() + 1 end) -- arithmetic: would blow up on a raw secret
    hp:set(helper.newFakeSecret())
    assert_eq(seen, 1, "el effect debe operar sobre el fallback (0 + 1)")
  end)

  it("set(secret) SIN fallback: el secret circula tal cual (para sinks que lo aceptan) e isSecret() es true", function()
    local W = loadWeaveWithDetector()
    local secret = helper.newFakeSecret()
    local target = W.signal(nil) -- no fallback declared
    target:set(secret)
    assert_eq(target(), secret, "sin fallback, el lector recibe el secret intacto")
    assert_true(target:isSecret())
  end)

  it("al volver un valor normal tras un secret, isSecret() vuelve a false y el valor fluye", function()
    local W = loadWeaveWithDetector()
    local hp = W.signal(100, { fallback = 0 })
    hp:set(helper.newFakeSecret())
    hp:set(75)
    assert_eq(hp(), 75)
    assert_false(hp:isSecret())
  end)

  it("secrets consecutivos con el mismo fallback no spamean a los effects", function()
    local W = loadWeaveWithDetector()
    local hp = W.signal(100, { fallback = 0 })
    local runs = 0
    W.effect(function() hp(); runs = runs + 1 end)
    hp:set(helper.newFakeSecret()) -- fallback 0 (change: 100 → 0)
    hp:set(helper.newFakeSecret()) -- fallback 0 again (no change)
    assert_eq(runs, 2, "el segundo secret con el mismo fallback no debe notificar")
  end)

end)

describe("computeds que degradan por secrets (fila 4 de la tabla)", function()

  it("si la fórmula explota por un secret y hay fallback: devuelve el fallback SIN error Lua", function()
    local W = loadWeaveWithDetector()
    local raw = W.signal(10) -- carries the secret as-is (no fallback on the signal)
    local doubled = W.computed(function() return raw() * 2 end, { fallback = -1 })
    assert_eq(doubled(), 20)
    raw:set(helper.newFakeSecret()) -- formula will blow up on `secret * 2`
    assert_eq(doubled(), -1, "debe degradar al fallback, no propagar el error")
    assert_true(doubled:isSecret())
  end)

  it("sin fallback: conserva el último valor bueno", function()
    local W = loadWeaveWithDetector()
    local raw = W.signal(10)
    local doubled = W.computed(function() return raw() * 2 end) -- no fallback
    assert_eq(doubled(), 20)
    raw:set(helper.newFakeSecret())
    assert_eq(doubled(), 20, "sin fallback, se queda el último valor bueno")
    assert_true(doubled:isSecret())
  end)

  it("cuando la dependencia vuelve a ser normal, recalcula limpio e isSecret() vuelve a false", function()
    local W = loadWeaveWithDetector()
    local raw = W.signal(10)
    local doubled = W.computed(function() return raw() * 2 end, { fallback = -1 })
    raw:set(helper.newFakeSecret())
    assert_eq(doubled(), -1)
    raw:set(30)
    assert_eq(doubled(), 60)
    assert_false(doubled:isSecret())
  end)

  it("un effect aguas abajo vive la degradación sin enterarse (recibe el fallback)", function()
    local W = loadWeaveWithDetector()
    local raw = W.signal(10)
    local doubled = W.computed(function() return raw() * 2 end, { fallback = 0 })
    local seen
    W.effect(function() seen = doubled() end)
    assert_eq(seen, 20)
    raw:set(helper.newFakeSecret())
    assert_eq(seen, 0, "el effect debe recibir el fallback del computed degradado")
  end)

  it("un error NO-secret en la fórmula SÍ se propaga (no se degrada en silencio)", function()
    local W = loadWeaveWithDetector()
    local hp = W.signal(1)
    local c = W.computed(function() hp(); error("bug real del dev") end, { fallback = 0 })
    assert_error(function() c() end, "bug real del dev")
  end)

end)

describe("el detector inyectable (frontera core/wow)", function()

  it("sin detector inyectado, nada se considera secret (default seguro para clientes viejos)", function()
    local W = helper.loadWeave() -- NO detector injected
    local hp = W.signal(100, { fallback = 0 })
    hp:set(42)
    assert_eq(hp(), 42)
    assert_false(hp:isSecret())
  end)

  it("_setSecretDetector exige una función", function()
    local W = helper.loadWeave()
    assert_error(function() W._setSecretDetector(42) end, "function")
  end)

end)
