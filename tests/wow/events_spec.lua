-- events_spec.lua — contract for fromEvent/fromUnitEvent (API-v0 §2). M1 block 1.
-- Runs over the minimal frame mock in tests/wow_helper.lua; the specs never touch
-- frame internals — they drive the "game" with fireEvent() and observe the signals.

local helper = dofile("tests/wow_helper.lua")

describe("fromEvent (señal alimentada por un evento del juego)", function()

  it("devuelve una señal; antes del primer evento vale nil", function()
    local W = helper.loadWeaveWow()
    local msg = W.fromEvent("CHAT_MSG_SAY")
    assert_eq(msg(), nil)
  end)

  it("opts.initial define el valor de arranque (antes del primer evento)", function()
    local W = helper.loadWeaveWow()
    local zone = W.fromEvent("ZONE_CHANGED", nil, { initial = "?" })
    assert_eq(zone(), "?")
  end)

  it("al disparar el evento, la señal toma el PRIMER arg (map por defecto)", function()
    local W = helper.loadWeaveWow()
    local msg = W.fromEvent("CHAT_MSG_SAY")
    helper.fireEvent("CHAT_MSG_SAY", "hola", "Betto")
    assert_eq(msg(), "hola")
  end)

  it("map transforma los args del evento en el valor de la señal", function()
    local W = helper.loadWeaveWow()
    local who = W.fromEvent("CHAT_MSG_SAY", function(text, author) return author end)
    helper.fireEvent("CHAT_MSG_SAY", "hola", "Betto")
    assert_eq(who(), "Betto")
  end)

  it("effects y computeds enchufados reaccionan al evento (integración con el core)", function()
    local W = helper.loadWeaveWow()
    local msg = W.fromEvent("CHAT_MSG_SAY", nil, { initial = "" })
    local shout = W.computed(function() return msg():upper() end)
    local seen
    W.effect(function() seen = shout() end)
    assert_eq(seen, "")
    helper.fireEvent("CHAT_MSG_SAY", "hola")
    assert_eq(seen, "HOLA")
  end)

  it("dos señales sobre el MISMO evento se actualizan ambas (registro multiplexado)", function()
    local W = helper.loadWeaveWow()
    local a = W.fromEvent("PLAYER_ENTERING_WORLD", function() return "a" end)
    local b = W.fromEvent("PLAYER_ENTERING_WORLD", function() return "b" end)
    helper.fireEvent("PLAYER_ENTERING_WORLD")
    assert_eq(a(), "a")
    assert_eq(b(), "b")
  end)

  it("el corte por igualdad del core aplica: el mismo valor repetido no re-dispara effects", function()
    local W = helper.loadWeaveWow()
    local msg = W.fromEvent("CHAT_MSG_SAY")
    local runs = 0
    W.effect(function() msg(); runs = runs + 1 end)
    helper.fireEvent("CHAT_MSG_SAY", "hola") -- nil → "hola": notifica
    helper.fireEvent("CHAT_MSG_SAY", "hola") -- mismo valor: NO notifica
    assert_eq(runs, 2)
  end)

  it("exige un nombre de evento (string)", function()
    local W = helper.loadWeaveWow()
    assert_error(function() W.fromEvent(42) end, "string")
  end)

end)

describe("fromUnitEvent (evento filtrado por unidad)", function()

  it("se siembra al crear: map(unit) corre una vez y el valor existe ANTES del primer evento", function()
    local health = { player = 100 }
    local W = helper.loadWeaveWow()
    local hp = W.fromUnitEvent("UNIT_HEALTH", "player", function(u) return health[u] end)
    assert_eq(hp(), 100, "el valor debe estar sembrado sin esperar al primer evento")
  end)

  it("reacciona a la unidad registrada e ignora las demás", function()
    local health = { player = 100, target = 50 }
    local W = helper.loadWeaveWow()
    local hp = W.fromUnitEvent("UNIT_HEALTH", "player", function(u) return health[u] end)
    health.player, health.target = 80, 10
    helper.fireEvent("UNIT_HEALTH", "target")
    assert_eq(hp(), 100, "un evento de otra unit no debe tocar la señal")
    helper.fireEvent("UNIT_HEALTH", "player")
    assert_eq(hp(), 80)
  end)

  it("dos units distintas sobre el MISMO evento no se pisan", function()
    local health = { player = 100, target = 50 }
    local W = helper.loadWeaveWow()
    local hpP = W.fromUnitEvent("UNIT_HEALTH", "player", function(u) return health[u] end)
    local hpT = W.fromUnitEvent("UNIT_HEALTH", "target", function(u) return health[u] end)
    health.player = 80
    helper.fireEvent("UNIT_HEALTH", "player")
    assert_eq(hpP(), 80)
    assert_eq(hpT(), 50, "la señal de target conserva su valor sembrado")
    health.target = 10
    helper.fireEvent("UNIT_HEALTH", "target")
    assert_eq(hpT(), 10)
    assert_eq(hpP(), 80, "la señal de player no debe moverse con el evento de target")
  end)

  it("exige la unit (string)", function()
    local W = helper.loadWeaveWow()
    assert_error(function() W.fromUnitEvent("UNIT_HEALTH", nil) end, "string")
  end)

end)

describe("guard del map: un map que OPERA un secret degrada, no revienta el OnEvent (M2)", function()

  it("el error de secret del map no se propaga: se salta esa actualización", function()
    local W = helper.loadWeaveWow()
    local s = W.fromEvent("EV", function(v) return v + 1 end) -- +1 blows on a secret
    helper.fireEvent("EV", 1)
    assert_eq(s(), 2)
    helper.silently(function() helper.fireEvent("EV", helper.newFakeSecret()) end) -- must NOT raise
    assert_eq(s(), 2, "la actualización con secret se salta; queda el último valor bueno")
  end)

  it("cuando vuelven args normales, el map funciona otra vez", function()
    local W = helper.loadWeaveWow()
    local s = W.fromEvent("EV", function(v) return v + 1 end)
    helper.silently(function() helper.fireEvent("EV", helper.newFakeSecret()) end)
    helper.fireEvent("EV", 10)
    assert_eq(s(), 11, "el guard degrada la actualización, no mata el registro")
  end)

  it("los demás suscriptores del mismo evento no se ven afectados", function()
    local W = helper.loadWeaveWow()
    local bad  = W.fromEvent("EV", function(v) return v + 1 end) -- degrades on secret
    local good = W.fromEvent("EV", function() return "ok" end)   -- never touches args
    helper.silently(function() helper.fireEvent("EV", helper.newFakeSecret()) end)
    assert_eq(good(), "ok", "la degradación de un suscriptor no corta el fan-out")
    assert_eq(bad(), nil)
  end)

  it("la siembra de fromUnitEvent también degrada: crear no lanza, la señal arranca vacía", function()
    local W = helper.loadWeaveWow()
    local secretHealth = helper.newFakeSecret()
    local hp
    helper.silently(function()
      hp = W.fromUnitEvent("UNIT_HEALTH", "player", function() return secretHealth + 1 end)
    end)
    assert_eq(hp(), nil, "siembra degradada: sin valor inicial, sin error Lua")
  end)

  it("la advertencia sale UNA sola vez por registro (print suave, identifica a Weave)", function()
    local prints = {}
    local realPrint = print
    _G.print = function(msg) prints[#prints + 1] = tostring(msg) end
    local ok, err = pcall(function()
      local W = helper.loadWeaveWow()
      W.fromEvent("EV", function(v) return v + 1 end)
      helper.fireEvent("EV", helper.newFakeSecret())
      helper.fireEvent("EV", helper.newFakeSecret()) -- same registration: no second warning
    end)
    _G.print = realPrint
    assert_true(ok, "nada debe propagar error Lua: " .. tostring(err))
    assert_eq(#prints, 1, "una advertencia por registro, no una por evento")
    assert_true(prints[1]:find("Weave", 1, true) ~= nil)
  end)

  it("un error NO-secret del map SÍ se propaga (bug real del dev)", function()
    local W = helper.loadWeaveWow()
    W.fromEvent("EV", function() error("bug real del dev") end)
    assert_error(function() helper.fireEvent("EV") end, "bug real del dev")
  end)

end)

describe("taint en señales de evento (API-v0 §3 aplica igual)", function()

  it("al cargar, la capa wow inyecta el issecretvalue del cliente al detector del core", function()
    -- headless stand-in for the client API: our fake-secret detector
    local W = helper.loadWeaveWow({ issecretvalue = helper.isFakeSecret })
    local s = W.signal(1, { fallback = 0 })
    s:set(helper.newFakeSecret())
    assert_eq(s(), 0, "con issecretvalue presente al cargar, el detector debe quedar inyectado")
    assert_true(s:isSecret())
  end)

  it("sin issecretvalue en el cliente (pre-12.0), nada es secret y nada crashea", function()
    local W = helper.loadWeaveWow() -- no client API exposed
    local s = W.signal(1, { fallback = 0 })
    s:set(2)
    assert_eq(s(), 2)
    assert_false(s:isSecret())
  end)

  it("si map devuelve un secret y hay fallback declarado, los lectores ven el fallback", function()
    local W = helper.loadWeaveWow({ issecretvalue = helper.isFakeSecret })
    local hp = W.fromEvent("UNIT_HEALTH_FAKE",
      function() return helper.newFakeSecret() end,
      { fallback = 0 })
    helper.fireEvent("UNIT_HEALTH_FAKE", "player")
    assert_eq(hp(), 0, "el lector debe ver el fallback, no el secret")
    assert_true(hp:isSecret())
  end)

end)
