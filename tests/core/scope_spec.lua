-- scope_spec.lua — contract for Weave.scope (API-v0 §1): effect/bind ownership.
-- M0 block 3b. WoW has no unmount: disposal is explicit, the scope makes it collective.

local helper = dofile("tests/helper.lua")

describe("Weave.scope (dueño colectivo de effects)", function()

  it("los effects creados dentro de scope:run se apagan todos con scope:dispose", function()
    local W = helper.loadWeave()
    local hp = W.signal(1)
    local runsA, runsB = 0, 0
    local scope = W.scope()
    scope:run(function()
      W.effect(function() hp(); runsA = runsA + 1 end)
      W.effect(function() hp(); runsB = runsB + 1 end)
    end)
    hp:set(2) -- both alive
    assert_eq(runsA, 2)
    assert_eq(runsB, 2)
    scope:dispose()
    hp:set(3) -- both gone
    assert_eq(runsA, 2, "un effect del scope dispuesto no debe reaccionar")
    assert_eq(runsB, 2)
  end)

  it("lo creado FUERA del scope no se ve afectado por su dispose", function()
    local W = helper.loadWeave()
    local hp = W.signal(1)
    local runsOut = 0
    W.effect(function() hp(); runsOut = runsOut + 1 end) -- outside any scope
    local scope = W.scope()
    scope:run(function()
      W.effect(function() hp() end)
    end)
    scope:dispose()
    hp:set(2)
    assert_eq(runsOut, 2, "el effect externo debe seguir vivo")
  end)

  it("run() devuelve lo que retorna la función", function()
    local W = helper.loadWeave()
    local scope = W.scope()
    local v = scope:run(function() return 42 end)
    assert_eq(v, 42)
  end)

  it("run() se puede llamar varias veces sobre el mismo scope (acumula ownership)", function()
    local W = helper.loadWeave()
    local hp = W.signal(1)
    local runs = 0
    local scope = W.scope()
    scope:run(function() W.effect(function() hp(); runs = runs + 1 end) end)
    scope:run(function() W.effect(function() hp(); runs = runs + 1 end) end)
    hp:set(2)
    assert_eq(runs, 4) -- 2 al crear + 2 al cambiar
    scope:dispose()
    hp:set(3)
    assert_eq(runs, 4)
  end)

  it("dispose() es idempotente y run() tras dispose da error claro", function()
    local W = helper.loadWeave()
    local scope = W.scope()
    scope:run(function() end)
    scope:dispose()
    scope:dispose() -- second call: must not blow up
    assert_error(function() scope:run(function() end) end, "disposed")
  end)

  it("dos scopes son independientes (disponer uno no toca al otro)", function()
    local W = helper.loadWeave()
    local hp = W.signal(1)
    local runsA, runsB = 0, 0
    local sA, sB = W.scope(), W.scope()
    sA:run(function() W.effect(function() hp(); runsA = runsA + 1 end) end)
    sB:run(function() W.effect(function() hp(); runsB = runsB + 1 end) end)
    sA:dispose()
    hp:set(2)
    assert_eq(runsA, 1, "el scope A está apagado")
    assert_eq(runsB, 2, "el scope B sigue vivo")
  end)

  it("si un effect nace dentro de run() de un scope anidado en otro run(), pertenece al scope INTERNO", function()
    local W = helper.loadWeave()
    local hp = W.signal(1)
    local runs = 0
    local outer, inner = W.scope(), W.scope()
    outer:run(function()
      inner:run(function()
        W.effect(function() hp(); runs = runs + 1 end)
      end)
    end)
    inner:dispose() -- disposing the INNER owner kills the effect
    hp:set(2)
    assert_eq(runs, 1)
    outer:dispose() -- must not blow up even though the effect is already gone
  end)

end)
