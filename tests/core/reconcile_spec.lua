-- reconcile_spec.lua — contract for the PURE keyed-list reconciler (API-v0 §4,
-- Weave.each, M6/ADR-0007). Core layer: plain Lua over plain keys, zero WoW.
--
-- Weave._reconcileKeys(prev, next) → plan
--   prev / next: dense arrays of keys (string|number) — prev is what the rows
--   show today, next is what the list wants to show now.
--   plan.slots[i] = index into prev whose row should display next[i]:
--     * a key present in both keeps ITS row (state preservation — the point of keying)
--     * a new key recycles a freed row if any (pooling), else nil = "needs a fresh row"
--   plan.freed = prev indices left over AFTER recycling, ascending (rows to hide).
-- The ui layer turns this plan into signal re-assignments; core never sees frames.

local helper = dofile("tests/helper.lua")

describe("Weave._reconcileKeys: reconciliador puro de listas con key", function()

  it("lista idéntica: cada fila se queda donde está y no sobra ninguna", function()
    local W = helper.loadWeave()
    local plan = W._reconcileKeys({ "a", "b", "c" }, { "a", "b", "c" })
    assert_eq(plan.slots[1], 1)
    assert_eq(plan.slots[2], 2)
    assert_eq(plan.slots[3], 3)
    assert_eq(#plan.freed, 0)
  end)

  it("reordenar: cada key conserva SU fila (el frame viaja con el dato)", function()
    local W = helper.loadWeave()
    local plan = W._reconcileKeys({ "a", "b", "c" }, { "c", "a", "b" })
    assert_eq(plan.slots[1], 3, "la fila de 'c' era la 3")
    assert_eq(plan.slots[2], 1, "la fila de 'a' era la 1")
    assert_eq(plan.slots[3], 2, "la fila de 'b' era la 2")
    assert_eq(#plan.freed, 0)
  end)

  it("inserción sin filas libres: la key nueva pide fila fresca (slot nil)", function()
    local W = helper.loadWeave()
    local plan = W._reconcileKeys({ "a", "b" }, { "a", "x", "b" })
    assert_eq(plan.slots[1], 1)
    assert_eq(plan.slots[2], nil, "'x' es nueva y no hay fila libre que reciclar")
    assert_eq(plan.slots[3], 2)
    assert_eq(#plan.freed, 0)
  end)

  it("eliminación: la fila del dato que se fue queda liberada (a ocultar)", function()
    local W = helper.loadWeave()
    local plan = W._reconcileKeys({ "a", "b", "c" }, { "a", "c" })
    assert_eq(plan.slots[1], 1)
    assert_eq(plan.slots[2], 3)
    assert_eq(#plan.freed, 1)
    assert_eq(plan.freed[1], 2)
  end)

  it("reemplazo: la key nueva RECICLA la fila liberada antes que pedir una fresca", function()
    local W = helper.loadWeave()
    local plan = W._reconcileKeys({ "a", "b" }, { "a", "x" })
    assert_eq(plan.slots[1], 1)
    assert_eq(plan.slots[2], 2, "'x' recicla la fila que 'b' dejó libre")
    assert_eq(#plan.freed, 0, "tras reciclar no sobra ninguna")
  end)

  it("desde cero y hacia cero: prev vacío pide todo fresco; next vacío libera todo", function()
    local W = helper.loadWeave()
    local plan = W._reconcileKeys({}, { "a", "b" })
    assert_eq(plan.slots[1], nil)
    assert_eq(plan.slots[2], nil)
    assert_eq(#plan.freed, 0)
    plan = W._reconcileKeys({ "a", "b" }, {})
    assert_eq(plan.freed[1], 1)
    assert_eq(plan.freed[2], 2)
  end)

  it("keys numéricas y de string conviven (2 y '2' son keys distintas)", function()
    local W = helper.loadWeave()
    local plan = W._reconcileKeys({ 2, "2" }, { "2", 2 })
    assert_eq(plan.slots[1], 2)
    assert_eq(plan.slots[2], 1)
  end)

  it("keys duplicadas en la lista nueva → error claro", function()
    local W = helper.loadWeave()
    assert_error(function()
      W._reconcileKeys({}, { "a", "b", "a" })
    end, "duplicate key")
  end)

end)
