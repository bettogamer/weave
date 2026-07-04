-- children_spec.lua — contract for [Weave.children] and [Weave.on] (API-v0 §4).
-- M4 block 2. The WoW quirk driving the design: FontStrings/Textures are REGIONS
-- and can only be created THROUGH a parent — so a region Weave.new without parent
-- returns a lazy descriptor that [Weave.children] materializes.

local helper = dofile("tests/wow_helper.lua")

describe("[Weave.on]: scripts declarativos", function()

  it("asigna cada script al frame", function()
    local W = helper.loadWeaveWow()
    local clicked = false
    local f = W.new("Button", {
      [W.on] = { OnMouseDown = function() clicked = true end },
    })
    f._scripts.OnMouseDown()
    assert_true(clicked)
  end)

  it("valida que cada script sea una función", function()
    local W = helper.loadWeaveWow()
    assert_error(function()
      W.new("Button", { [W.on] = { OnMouseDown = "nope" } })
    end, "function")
  end)

end)

describe("[Weave.children]: regiones hijas (descriptors perezosos)", function()

  it("un FontString hijo se materializa en el padre, con su layer y sus props", function()
    local W = helper.loadWeaveWow()
    local f = W.new("StatusBar", {
      [W.children] = {
        W.new("FontString", { layer = "OVERLAY", point = { "CENTER" }, text = "hola" }),
      },
    })
    local fs = f._regions[1]
    assert_true(fs ~= nil, "el padre debe haber creado la región")
    assert_eq(fs._type, "FontString")
    assert_eq(fs._layer, "OVERLAY")
    assert_eq(fs._points[1][1], "CENTER")
    assert_eq(fs._set.text, "hola")
  end)

  it("una prop con señal en el hijo queda bindeada", function()
    local W = helper.loadWeaveWow()
    local txt = W.signal("a")
    local f = W.new("StatusBar", {
      [W.children] = { W.new("FontString", { text = txt }) },
    })
    assert_eq(f._regions[1]._set.text, "a")
    txt:set("b")
    assert_eq(f._regions[1]._set.text, "b")
  end)

  it("una Texture hija se materializa via CreateTexture", function()
    local W = helper.loadWeaveWow()
    local f = W.new("Frame", {
      [W.children] = {
        W.new("Texture", { layer = "BACKGROUND", vertexColor = { 0, 0, 0, 0.5 } }),
      },
    })
    local tex = f._regions[1]
    assert_eq(tex._type, "Texture")
    assert_eq(tex._set.vertexColor[4], 0.5)
  end)

  it("una región CON parent en props se crea inmediatamente (sin descriptor)", function()
    local W = helper.loadWeaveWow()
    local f = W.new("Frame", {})
    local fs = W.new("FontString", { parent = f, layer = "OVERLAY", text = "ya" })
    assert_eq(f._regions[1], fs, "debe crearse a través del padre, en el acto")
    assert_eq(fs._set.text, "ya")
  end)

  it("un frame REAL como hijo se re-parenta", function()
    local W = helper.loadWeaveWow()
    local inner = W.new("Frame", {})
    local outer = W.new("Frame", { [W.children] = { inner } })
    assert_true(rawequal(inner._parent, outer))
  end)

  it("la forma de la demo canónica (§7) funciona entera: hijo bindeado a computed", function()
    local W = helper.loadWeaveWow()
    local hp = W.signal(50)
    local pct = W.computed(function() return hp() / 100 end)
    local bar = W.new("StatusBar", {
      size = { 200, 20 }, point = { "CENTER" }, minMax = { 0, 1 },
      value = pct,
      [W.children] = {
        W.new("FontString", { layer = "OVERLAY", point = { "CENTER" },
          text = W.computed(function() return ("%d%%"):format(pct() * 100) end) }),
      },
    })
    assert_eq(bar._set.value, 0.5)
    assert_eq(bar._regions[1]._set.text, "50%")
    hp:set(80)
    assert_eq(bar._set.value, 0.8)
    assert_eq(bar._regions[1]._set.text, "80%")
  end)

  it("scope: dispose() mata también los binds de los hijos", function()
    local W = helper.loadWeaveWow()
    local txt = W.signal("a")
    local scope = W.scope()
    local f
    scope:run(function()
      f = W.new("StatusBar", { [W.children] = { W.new("FontString", { text = txt }) } })
    end)
    scope:dispose()
    txt:set("b")
    assert_eq(f._regions[1]._set.text, "a", "el bind del hijo debe morir con el scope")
    assert_false(f:IsShown())
  end)

end)
