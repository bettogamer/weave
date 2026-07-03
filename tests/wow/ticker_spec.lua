-- ticker_spec.lua — contract for onUpdate (API-v0 §2) and the visible chokepoint
-- warning the wow/ layer installs. M1 block 3. Time is driven by the fake clock in
-- wow_helper (advanceTime fires OnUpdate scripts by hand).

local helper = dofile("tests/wow_helper.lua")

describe("onUpdate (señal de tiempo throttleada)", function()

  it("devuelve una señal sembrada con el GetTime() actual", function()
    local W = helper.loadWeaveWow()
    local t = W.onUpdate(0.1)
    assert_eq(t:peek(), 1000, "la señal debe nacer con la hora actual, no vacía")
  end)

  it("con un suscriptor, tickea al acumular el intervalo y publica el GetTime() del tick", function()
    local W = helper.loadWeaveWow()
    local t = W.onUpdate(0.1)
    local seen
    W.effect(function() seen = t() end)
    assert_eq(seen, 1000)
    helper.advanceTime(0.06) -- 0.06 < 0.1: aún no
    assert_eq(seen, 1000)
    helper.advanceTime(0.06) -- acumulado 0.12 ≥ 0.1: tick
    -- same additions the fake clock performs (float equality is exact that way)
    assert_eq(seen, 1000 + 0.06 + 0.06)
  end)

  it("SIN suscriptores no tickea; al enchufar un effect, empieza", function()
    local W = helper.loadWeaveWow()
    local t = W.onUpdate(0.1)
    helper.advanceTime(0.5)
    assert_eq(t:peek(), 1000, "sin suscriptores la señal no debe moverse")
    local seen
    W.effect(function() seen = t() end)
    helper.advanceTime(0.1)
    assert_eq(seen, 1000 + 0.5 + 0.1)
  end)

  it("el mismo intervalo devuelve la MISMA señal (se comparte)", function()
    local W = helper.loadWeaveWow()
    assert_true(W.onUpdate(0.1) == W.onUpdate(0.1))
  end)

  it("todos los onUpdate comparten UN solo frame ticker", function()
    local W = helper.loadWeaveWow()
    W.onUpdate(0.1)
    W.onUpdate(0.5)
    assert_eq(helper.frameCount(), 1)
  end)

  it("clampa el intervalo al mínimo efectivo (~0.05)", function()
    local W = helper.loadWeaveWow()
    local t = W.onUpdate(0.01) -- effective 0.05
    local seen
    W.effect(function() seen = t() end)
    helper.advanceTime(0.02)
    assert_eq(seen, 1000, "por debajo del mínimo no debe tickear")
    helper.advanceTime(0.04) -- acumulado 0.06 ≥ 0.05
    assert_eq(seen, 1000 + 0.02 + 0.04)
  end)

  it("exige un intervalo numérico positivo", function()
    local W = helper.loadWeaveWow()
    assert_error(function() W.onUpdate("rapido") end, "number")
    assert_error(function() W.onUpdate(0) end, "positive")
  end)

end)

describe("la capa wow instala la advertencia visible del chokepoint", function()

  it("un effect que degrada por secret imprime UNA advertencia suave, sin popup de error", function()
    local prints = {}
    local realPrint = print
    _G.print = function(msg) prints[#prints + 1] = tostring(msg) end
    local ok, err = pcall(function()
      local W = helper.loadWeaveWow()
      local s = W.signal(1)
      local sink
      W.effect(function() sink = s() + 1 end)
      s:set(helper.newFakeSecret()) -- blows inside the effect → chokepoint degrades
      s:set(helper.newFakeSecret()) -- same site again → no second warning
    end)
    _G.print = realPrint
    assert_true(ok, "nada debe propagar error Lua: " .. tostring(err))
    assert_eq(#prints, 1, "una sola advertencia por sitio")
    assert_true(prints[1]:find("Weave", 1, true) ~= nil, "el aviso debe identificar a Weave")
  end)

end)
