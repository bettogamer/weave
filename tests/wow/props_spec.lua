-- props_spec.lua — contract for the props registry + bind (API-v0 §2). M1 block 2.
-- The mock frame only RECORDS setter calls (f._set.<prop>); the specs assert the
-- right call happened with the right value, never how anything renders.

local helper = dofile("tests/wow_helper.lua")

describe("Weave.props (registro de cómo se aplica cada prop)", function()

  it("las props built-in de un solo valor aplican su setter", function()
    local W = helper.loadWeaveWow()
    local f = helper.newMockFrame()
    local cases = {
      { prop = "text",    v = "hola" },
      { prop = "value",   v = 0.5 },
      { prop = "shown",   v = false },
      { prop = "alpha",   v = 0.7 },
      { prop = "width",   v = 200 },
      { prop = "height",  v = 20 },
      { prop = "texture", v = "Interface\\Icons\\foo" },
    }
    for _, c in ipairs(cases) do
      W.bind(f, c.prop, W.signal(c.v))
      assert_eq(f._set[c.prop], c.v, "prop: " .. c.prop)
    end
  end)

  it("las props de varios args (minMax, vertexColor, statusBarColor) desempaquetan la tabla", function()
    local W = helper.loadWeaveWow()
    local f = helper.newMockFrame()
    W.bind(f, "minMax", W.signal({ 0, 1 }))
    assert_eq(f._set.minMax[1], 0)
    assert_eq(f._set.minMax[2], 1)
    W.bind(f, "vertexColor", W.signal({ 1, 0.2, 0.3 }))
    assert_eq(f._set.vertexColor[1], 1)
    assert_eq(f._set.vertexColor[3], 0.3)
    W.bind(f, "statusBarColor", W.signal({ 0.2, 0.8, 0.2, 0.5 }))
    assert_eq(f._set.statusBarColor[4], 0.5)
  end)

  it("props.register extiende el registro con props custom", function()
    local W = helper.loadWeaveWow()
    local applied
    W.props.register("glow", function(frame, v) applied = v end)
    local on = W.signal(true)
    W.bind(helper.newMockFrame(), "glow", on)
    assert_true(applied)
    on:set(false)
    assert_false(applied)
  end)

  it("una prop desconocida da error claro con su nombre", function()
    local W = helper.loadWeaveWow()
    assert_error(function()
      W.bind(helper.newMockFrame(), "wombo", W.signal(1))
    end, "wombo")
  end)

  it("register valida nombre (string) y aplicador (function)", function()
    local W = helper.loadWeaveWow()
    assert_error(function() W.props.register(42, function() end) end, "string")
    assert_error(function() W.props.register("x", "nope") end, "function")
  end)

end)

describe("bind (enchufar una señal a una prop de un frame)", function()

  it("aplica el valor ACTUAL inmediatamente, sin esperar al primer cambio", function()
    local W = helper.loadWeaveWow()
    local f = helper.newMockFrame()
    W.bind(f, "text", W.signal("ya"))
    assert_eq(f._set.text, "ya")
  end)

  it("re-aplica cada vez que la señal cambia", function()
    local W = helper.loadWeaveWow()
    local f = helper.newMockFrame()
    local s = W.signal("a")
    W.bind(f, "text", s)
    s:set("b")
    assert_eq(f._set.text, "b")
  end)

  it("funciona igual con un computed", function()
    local W = helper.loadWeaveWow()
    local f = helper.newMockFrame()
    local hp = W.signal(50)
    local pct = W.computed(function() return hp() / 100 end)
    W.bind(f, "value", pct)
    assert_eq(f._set.value, 0.5)
    hp:set(80)
    assert_eq(f._set.value, 0.8)
  end)

  it("devuelve un EffectHandle: dispose() desconecta", function()
    local W = helper.loadWeaveWow()
    local f = helper.newMockFrame()
    local s = W.signal("a")
    local h = W.bind(f, "text", s)
    h:dispose()
    s:set("b")
    assert_eq(f._set.text, "a", "tras dispose(), el frame no debe enterarse de nada")
  end)

  it("creado dentro de scope:run(), scope:dispose() lo desconecta", function()
    local W = helper.loadWeaveWow()
    local f = helper.newMockFrame()
    local s = W.signal(1)
    local scope = W.scope()
    scope:run(function() W.bind(f, "value", s) end)
    s:set(2)
    assert_eq(f._set.value, 2)
    scope:dispose()
    s:set(3)
    assert_eq(f._set.value, 2, "un bind del scope dispuesto no debe seguir aplicando")
  end)

  it("NUNCA crea frames (combat-safe por diseño, AGENTS.md §5)", function()
    local W = helper.loadWeaveWow()
    local f = helper.newMockFrame()
    local before = helper.frameCount()
    W.bind(f, "value", W.signal(1))
    assert_eq(helper.frameCount(), before)
  end)

  it("valida frame (table), prop (string) y source (llamable)", function()
    local W = helper.loadWeaveWow()
    local f = helper.newMockFrame()
    assert_error(function() W.bind(nil, "text", W.signal("x")) end, "frame")
    assert_error(function() W.bind(f, 42, W.signal("x")) end, "prop")
    assert_error(function() W.bind(f, "text", 42) end, "callable")
  end)

end)

describe("taint de punta a punta a través de bind", function()

  it("cuando llega un secret, el frame recibe el fallback declarado, sin error Lua", function()
    local W = helper.loadWeaveWow({ issecretvalue = helper.isFakeSecret })
    local f = helper.newMockFrame()
    local hp = W.signal(100, { fallback = 0 })
    W.bind(f, "value", hp)
    assert_eq(f._set.value, 100)
    hp:set(helper.newFakeSecret())
    assert_eq(f._set.value, 0, "el frame debe recibir el fallback, no el secret")
  end)

end)
