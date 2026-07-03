-- store_spec.lua — contract for the flat store (API-v0 §5). M3 block 1.
-- Timing here is the SIMPLE case: the SavedVariable global already exists when
-- Weave.store is called (the "create it in ADDON_LOADED" recommended pattern).
-- First-run (nil global) and early-call hydration are M3 block 2.

local helper = dofile("tests/wow_helper.lua")

describe("store plano: cada campo es una señal (API-v0 §5)", function()

  it("lee los defaults cuando no hay nada guardado", function()
    local W = helper.loadWeaveWow()
    _G.WvTestDB = {} -- SV loaded, empty (nothing ever saved)
    local db = W.store("WvTestDB", { enabled = true, scale = 1.0 })
    assert_eq(db.scale(), 1.0)
    assert_true(db.enabled())
  end)

  it("los valores guardados PISAN a los defaults al crear", function()
    local W = helper.loadWeaveWow()
    _G.WvTestDB = { scale = 2.5 }
    local db = W.store("WvTestDB", { scale = 1.0 })
    assert_eq(db.scale(), 2.5, "lo guardado manda sobre el default")
  end)

  it("un false guardado NO se confunde con 'no guardado'", function()
    local W = helper.loadWeaveWow()
    _G.WvTestDB = { enabled = false }
    local db = W.store("WvTestDB", { enabled = true })
    assert_false(db.enabled(), "false es un valor guardado legítimo, no ausencia")
  end)

  it("set() actualiza la señal Y persiste en la SavedVariable", function()
    local W = helper.loadWeaveWow()
    _G.WvTestDB = {}
    local db = W.store("WvTestDB", { scale = 1.0 })
    db.scale:set(1.2)
    assert_eq(db.scale(), 1.2)
    assert_eq(_G.WvTestDB.scale, 1.2, "la escritura debe llegar a la tabla que WoW serializa")
  end)

  it("los defaults NO se materializan en la SV: solo persiste lo que se escribe", function()
    local W = helper.loadWeaveWow()
    _G.WvTestDB = {}
    local db = W.store("WvTestDB", { scale = 1.0, enabled = true })
    db.scale:set(2.0)
    assert_eq(_G.WvTestDB.scale, 2.0)
    assert_eq(_G.WvTestDB.enabled, nil,
      "un default nunca escrito no debe ensuciar la SV (si el default cambia en v2, aplica)")
  end)

  it("las claves guardadas que ya no están en defaults se preservan (datos del usuario intocables)", function()
    local W = helper.loadWeaveWow()
    _G.WvTestDB = { ajusteViejo = 42 }
    local db = W.store("WvTestDB", { scale = 1.0 })
    assert_eq(db._raw.ajusteViejo, 42, "el store no borra lo que no conoce")
  end)

  it("_raw es la MISMA tabla que la SavedVariable global", function()
    local W = helper.loadWeaveWow()
    _G.WvTestDB = {}
    local db = W.store("WvTestDB", { scale = 1.0 })
    assert_true(rawequal(db._raw, _G.WvTestDB))
  end)

  it("la reactividad completa funciona sobre campos del store (computed + bind)", function()
    local W = helper.loadWeaveWow()
    _G.WvTestDB = {}
    local db = W.store("WvTestDB", { width = 200 })
    local doubled = W.computed(function() return db.width() * 2 end)
    local f = helper.newMockFrame()
    W.bind(f, "width", db.width)
    assert_eq(doubled(), 400)
    assert_eq(f._set.width, 200)
    db.width:set(240)
    assert_eq(doubled(), 480)
    assert_eq(f._set.width, 240, "la UI enchufada se actualiza en vivo al persistir")
  end)

  it("valida: svName string y defaults tabla", function()
    local W = helper.loadWeaveWow()
    assert_error(function() W.store(42, {}) end, "string")
    assert_error(function() W.store("WvTestDB", "nope") end, "table")
  end)

  it("rechaza valores no serializables en set() con error claro", function()
    local W = helper.loadWeaveWow()
    _G.WvTestDB = {}
    local db = W.store("WvTestDB", { cb = false })
    assert_error(function() db.cb:set(function() end) end, "serializable")
  end)

  it("un secret NO se persiste: aviso suave y la escritura se salta", function()
    local W = helper.loadWeaveWow({ issecretvalue = helper.isFakeSecret })
    _G.WvTestDB = {}
    local db = W.store("WvTestDB", { scale = 1.0 })
    helper.silently(function() db.scale:set(helper.newFakeSecret()) end)
    assert_eq(db.scale(), 1.0, "la señal conserva su valor: un secret no puede ir a disco")
    assert_eq(_G.WvTestDB.scale, nil, "y la SV no se toca")
  end)

end)
