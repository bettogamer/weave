-- nested_spec.lua — contract for nested sub-stores and version/migrate (API-v0 §5).
-- M3 block 3. Same philosophy as the flat store: defaults never touch the disk,
-- saved data wins, unknown keys are user data.

local helper = dofile("tests/wow_helper.lua")

describe("sub-stores anidados (tablas en defaults)", function()

  it("una tabla en defaults crea un sub-store: se lee y escribe anidado", function()
    local W = helper.loadWeaveWow()
    _G.WvNestDB = {}
    local db = W.store("WvNestDB", { bar = { width = 200, locked = false } })
    assert_eq(db.bar.width(), 200)
    assert_false(db.bar.locked())
    db.bar.width:set(240)
    assert_eq(db.bar.width(), 240)
  end)

  it("escribir un campo anidado persiste creando la sub-tabla al vuelo", function()
    local W = helper.loadWeaveWow()
    _G.WvNestDB = {}
    local db = W.store("WvNestDB", { bar = { width = 200 } })
    assert_eq(_G.WvNestDB.bar, nil, "sin escrituras, ni la sub-tabla existe en la SV")
    db.bar.width:set(240)
    assert_eq(_G.WvNestDB.bar.width, 240)
  end)

  it("los defaults anidados tampoco se materializan", function()
    local W = helper.loadWeaveWow()
    _G.WvNestDB = {}
    local db = W.store("WvNestDB", { bar = { width = 200, locked = false } })
    db.bar.width:set(240)
    assert_eq(_G.WvNestDB.bar.locked, nil, "solo persiste lo escrito, también anidado")
  end)

  it("lo guardado anidado pisa los defaults (y lo no guardado conserva el default)", function()
    local W = helper.loadWeaveWow()
    _G.WvNestDB = { bar = { width = 300 } }
    local db = W.store("WvNestDB", { bar = { width = 200, locked = false } })
    assert_eq(db.bar.width(), 300)
    assert_false(db.bar.locked())
  end)

  it("la hidratación re-sincroniza también los campos anidados (UI en vivo)", function()
    local W = helper.loadWeaveWow()
    _G.WvNestDB = nil
    local db = W.store("WvNestDB", { bar = { width = 200 } }, { addon = "MiAddon" })
    local seen
    W.effect(function() seen = db.bar.width() end)
    assert_eq(seen, 200)
    _G.WvNestDB = { bar = { width = 320 } }
    helper.fireEvent("ADDON_LOADED", "MiAddon")
    assert_eq(seen, 320, "el effect anidado debe re-sincronizar solo")
    db.bar.width:set(330)
    assert_eq(_G.WvNestDB.bar.width, 330, "y las escrituras van a la tabla definitiva")
  end)

  it("claves guardadas desconocidas dentro del sub-store se preservan", function()
    local W = helper.loadWeaveWow()
    _G.WvNestDB = { bar = { colorViejo = "rojo" } }
    local db = W.store("WvNestDB", { bar = { width = 200 } })
    db.bar.width:set(240)
    assert_eq(_G.WvNestDB.bar.colorViejo, "rojo", "datos del usuario intocables, también anidados")
  end)

  it("si lo guardado bajo la clave anidada NO es una tabla, valen los defaults y el set la repara", function()
    local W = helper.loadWeaveWow()
    _G.WvNestDB = { bar = 5 } -- corrupt / old format
    local db = W.store("WvNestDB", { bar = { width = 200 } })
    assert_eq(db.bar.width(), 200, "un guardado corrupto no debe romper la carga")
    db.bar.width:set(240)
    assert_eq(_G.WvNestDB.bar.width, 240, "la escritura repara la sub-tabla")
  end)

  it("dos niveles de anidamiento funcionan", function()
    local W = helper.loadWeaveWow()
    _G.WvNestDB = {}
    local db = W.store("WvNestDB", { ui = { bar = { height = 20 } } })
    assert_eq(db.ui.bar.height(), 20)
    db.ui.bar.height:set(24)
    assert_eq(_G.WvNestDB.ui.bar.height, 24)
  end)

  it("la reactividad completa funciona sobre campos anidados", function()
    local W = helper.loadWeaveWow()
    _G.WvNestDB = {}
    local db = W.store("WvNestDB", { bar = { width = 200 } })
    local half = W.computed(function() return db.bar.width() / 2 end)
    assert_eq(half(), 100)
    db.bar.width:set(300)
    assert_eq(half(), 150)
  end)

end)

describe("version y migrate (patrón _version del estándar, automatizado)", function()

  it("primera ejecución: estampa _version SIN llamar a migrate (no hay nada que migrar)", function()
    local W = helper.loadWeaveWow()
    _G.WvVerDB = nil
    local called = false
    local db = W.store("WvVerDB", { width = 100 }, {
      addon = "MiAddon", version = 2,
      migrate = function() called = true end,
    })
    helper.fireEvent("ADDON_LOADED", "MiAddon")
    assert_false(called)
    assert_eq(_G.WvVerDB._version, 2)
  end)

  it("datos con versión vieja: migrate(raw, oldVersion) corre ANTES del re-sync y la UI ve lo migrado", function()
    local W = helper.loadWeaveWow()
    _G.WvVerDB = nil
    local db = W.store("WvVerDB", { width = 100 }, {
      addon = "MiAddon", version = 2,
      migrate = function(raw, oldVersion)
        assert_eq(oldVersion, 1)
        raw.width = raw.ancho -- v1 used a Spanish key
        raw.ancho = nil
      end,
    })
    _G.WvVerDB = { _version = 1, ancho = 250 }
    helper.fireEvent("ADDON_LOADED", "MiAddon")
    assert_eq(db.width(), 250, "la señal debe re-sincronizar con el dato YA migrado")
    assert_eq(_G.WvVerDB._version, 2, "y la versión queda re-estampada")
    assert_eq(_G.WvVerDB.ancho, nil)
  end)

  it("misma versión: migrate NO corre", function()
    local W = helper.loadWeaveWow()
    local called = false
    _G.WvVerDB = { _version = 2, width = 250 }
    local db = W.store("WvVerDB", { width = 100 }, {
      version = 2,
      migrate = function() called = true end,
    })
    assert_false(called)
    assert_eq(db.width(), 250)
  end)

  it("datos pre-versionado (sin _version): migrate recibe nil como oldVersion", function()
    local W = helper.loadWeaveWow()
    local sawOld = "unset"
    _G.WvVerDB = { width = 250 }
    W.store("WvVerDB", { width = 100 }, {
      version = 2,
      migrate = function(raw, oldVersion) sawOld = oldVersion end,
    })
    assert_eq(sawOld, nil, "datos de antes del versionado: oldVersion es nil")
  end)

  it("version sin migrate: solo re-estampa, sin errores", function()
    local W = helper.loadWeaveWow()
    _G.WvVerDB = { _version = 1, width = 250 }
    local db = W.store("WvVerDB", { width = 100 }, { version = 3 })
    assert_eq(db.width(), 250)
    assert_eq(_G.WvVerDB._version, 3)
  end)

end)
