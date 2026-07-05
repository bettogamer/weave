-- predicates_spec.lua — contract for Weave.isReactive / Weave.isWritable (API-v0 §1).
-- FR de consumidores (Craft, BACKLOG): predicados públicos para "señal-o-literal" sin
-- que el consumidor hurgue en la forma interna de un signal. Semántica ESTRUCTURAL:
-- reactivo = función o tabla callable (lo que effect puede observar).

local helper = dofile("tests/helper.lua")

describe("Weave.isReactive", function()

  it("true para una signal", function()
    local W = helper.loadWeave()
    assert_true(W.isReactive(W.signal(1)))
  end)

  it("true para un computed", function()
    local W = helper.loadWeave()
    local n = W.signal(1)
    assert_true(W.isReactive(W.computed(function() return n() * 2 end)))
  end)

  it("true para una función normal (effect puede observarla)", function()
    local W = helper.loadWeave()
    assert_true(W.isReactive(function() return 1 end))
  end)

  it("true para una tabla callable ajena (semántica estructural: tiene __call)", function()
    local W = helper.loadWeave()
    local callable = setmetatable({}, { __call = function() return 7 end })
    assert_true(W.isReactive(callable))
  end)

  it("false para escalares: número, string, boolean, nil", function()
    local W = helper.loadWeave()
    assert_eq(W.isReactive(42), false)
    assert_eq(W.isReactive("hp"), false)
    assert_eq(W.isReactive(true), false)
    assert_eq(W.isReactive(nil), false)
  end)

  it("false para una tabla plana (sin __call)", function()
    local W = helper.loadWeave()
    assert_eq(W.isReactive({ 1, 2, 3 }), false)
  end)

end)

describe("Weave.isWritable", function()

  it("true para una signal (tiene :set)", function()
    local W = helper.loadWeave()
    assert_true(W.isWritable(W.signal(1)))
  end)

  it("false para un computed (read-only)", function()
    local W = helper.loadWeave()
    local n = W.signal(1)
    assert_eq(W.isWritable(W.computed(function() return n() * 2 end)), false)
  end)

  it("false para una función", function()
    local W = helper.loadWeave()
    assert_eq(W.isWritable(function() return 1 end), false)
  end)

  it("false para escalares y tablas planas", function()
    local W = helper.loadWeave()
    assert_eq(W.isWritable(42), false)
    assert_eq(W.isWritable("hp"), false)
    assert_eq(W.isWritable(nil), false)
    assert_eq(W.isWritable({ set = "no soy método" }), false)
  end)

  it("writable ⊆ reactive: todo lo escribible es también reactivo", function()
    local W = helper.loadWeave()
    local s = W.signal(1)
    assert_true(W.isWritable(s))
    assert_true(W.isReactive(s))
  end)

end)

describe("coherencia interna: Props._isCallable delega en Weave.isReactive", function()

  it("_isCallable da el mismo veredicto que isReactive (una sola definición)", function()
    -- La capa wow/ es la que expone _isCallable; se carga como extraFile.
    local W = helper.loadWeave({ "Weave/wow/Props.lua" })
    local samples = {
      W.signal(1),
      W.computed(function() return 1 end),
      function() return 1 end,
      setmetatable({}, { __call = function() end }),
      42, "hp", true, { 1, 2 },
    }
    for _, v in ipairs(samples) do
      assert_eq(W.props._isCallable(v), W.isReactive(v))
    end
  end)

end)
