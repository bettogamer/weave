-- hydration_spec.lua — contract for store hydration timing (API-v0 §5). M3 block 2.
-- The WoW choreography being simulated: addon files run first (the store may be
-- created there), THEN the client loads the SavedVariables file into the global,
-- THEN ADDON_LOADED fires for the owning addon.

local helper = dofile("tests/wow_helper.lua")

describe("hidratación: store creado ANTES de que cargue su addon dueño", function()

  it("mientras tanto funciona con los defaults", function()
    local W = helper.loadWeaveWow()
    _G.WvHydDB = nil
    local db = W.store("WvHydDB", { scale = 1.0 }, { addon = "MiAddon" })
    assert_eq(db.scale(), 1.0)
  end)

  it("al llegar el ADDON_LOADED del dueño re-sincroniza con lo guardado, y la UI enchufada lo ve en vivo", function()
    local W = helper.loadWeaveWow()
    _G.WvHydDB = nil
    local db = W.store("WvHydDB", { scale = 1.0 }, { addon = "MiAddon" })
    local seen
    W.effect(function() seen = db.scale() end)
    assert_eq(seen, 1.0)
    _G.WvHydDB = { scale = 2.0 }               -- the client loads the SV file...
    helper.fireEvent("ADDON_LOADED", "MiAddon") -- ...and announces the addon
    assert_eq(db.scale(), 2.0, "la señal debe re-sincronizar con lo guardado")
    assert_eq(seen, 2.0, "los effects enchufados deben enterarse solos")
    assert_true(rawequal(db._raw, _G.WvHydDB), "_raw debe re-apuntar a la tabla cargada")
  end)

  it("el ADDON_LOADED de OTRO addon no hidrata", function()
    local W = helper.loadWeaveWow()
    _G.WvHydDB = nil
    local db = W.store("WvHydDB", { scale = 1.0 }, { addon = "MiAddon" })
    _G.WvHydDB = { scale = 2.0 }
    helper.fireEvent("ADDON_LOADED", "OtroAddon")
    assert_eq(db.scale(), 1.0, "solo el dueño dispara la hidratación")
    helper.fireEvent("ADDON_LOADED", "MiAddon")
    assert_eq(db.scale(), 2.0)
  end)

  it("primera ejecución (nada guardado): reclama la global al hidratar y lo escrito ANTES persiste", function()
    local W = helper.loadWeaveWow()
    _G.WvHydDB = nil
    local db = W.store("WvHydDB", { scale = 1.0 }, { addon = "MiAddon" })
    db.scale:set(1.5) -- the user tweaks something during load, before ADDON_LOADED
    helper.fireEvent("ADDON_LOADED", "MiAddon") -- first run: the global is still nil
    assert_true(_G.WvHydDB ~= nil, "el store debe reclamar la global para que WoW guarde algo")
    assert_eq(_G.WvHydDB.scale, 1.5, "la escritura pre-hidratación sobrevive en primera ejecución")
    assert_eq(db.scale(), 1.5)
  end)

  it("lo GUARDADO gana a las escrituras pre-hidratación", function()
    local W = helper.loadWeaveWow()
    _G.WvHydDB = nil
    local db = W.store("WvHydDB", { scale = 1.0 }, { addon = "MiAddon" })
    db.scale:set(9)
    _G.WvHydDB = { scale = 2.0 }
    helper.fireEvent("ADDON_LOADED", "MiAddon")
    assert_eq(db.scale(), 2.0, "el disco es la fuente de verdad al hidratar")
  end)

  it("después de hidratar, set() persiste en la tabla definitiva", function()
    local W = helper.loadWeaveWow()
    _G.WvHydDB = nil
    local db = W.store("WvHydDB", { scale = 1.0 }, { addon = "MiAddon" })
    _G.WvHydDB = { scale = 2.0 }
    helper.fireEvent("ADDON_LOADED", "MiAddon")
    db.scale:set(3.0)
    assert_eq(_G.WvHydDB.scale, 3.0)
  end)

  it("la re-sincronización NO materializa defaults en la SV", function()
    local W = helper.loadWeaveWow()
    _G.WvHydDB = nil
    local db = W.store("WvHydDB", { scale = 1.0, enabled = true }, { addon = "MiAddon" })
    _G.WvHydDB = { scale = 2.0 }
    helper.fireEvent("ADDON_LOADED", "MiAddon")
    assert_true(db.enabled())
    assert_eq(_G.WvHydDB.enabled, nil, "hidratar no debe escribir defaults a disco")
  end)

end)

describe("hidratación: variantes de timing", function()

  it("sin opts.addon (heurística): hidrata en el SIGUIENTE ADDON_LOADED, sea de quien sea", function()
    local W = helper.loadWeaveWow()
    _G.WvHydDB = nil
    local db = W.store("WvHydDB", { scale = 1.0 })
    _G.WvHydDB = { scale = 2.0 }
    helper.fireEvent("ADDON_LOADED", "Cualquiera")
    assert_eq(db.scale(), 2.0, "el patrón file-scope: el siguiente ADDON_LOADED es el del dueño")
  end)

  it("con el dueño YA cargado al crear: hidrata (y reclama) inmediatamente", function()
    local W = helper.loadWeaveWow()
    helper.setAddOnLoaded("MiAddon")
    _G.WvHydDB = nil -- loaded but nothing ever saved (late first run)
    local db = W.store("WvHydDB", { scale = 1.0 }, { addon = "MiAddon" })
    db.scale:set(1.5)
    assert_true(_G.WvHydDB ~= nil, "no hay evento que esperar: reclama al crear")
    assert_eq(_G.WvHydDB.scale, 1.5)
  end)

end)
