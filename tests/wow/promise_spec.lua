-- promise_spec.lua — contract for Weave.fromPromise (API-v0 §2, ADR-0009). M9 block 1.
-- The bridge consumes ONLY a Loom promise's PUBLIC surface, so the fake promise below
-- is plain Lua (:next/:status/:isSecret/:cancel) — NOT a WoW mock. It mimics Loom's
-- contract; the spec drives resolution by hand with p:_resolve()/p:_reject().

local helper = dofile("tests/wow_helper.lua")

-- A stand-in for a Loom promise: exactly the public surface fromPromise may touch.
local function fakePromise()
  local p = { _status = "pending", _cbOk = nil, _cbErr = nil, _secret = false, _cancelled = 0 }
  function p:next(onOk, onErr) self._cbOk = onOk; self._cbErr = onErr; return self end
  function p:status() return self._status end
  function p:isSecret() return self._secret end
  function p:cancel() self._cancelled = self._cancelled + 1; self._status = "cancelled" end
  -- Loom semantics: a settled OR cancelled promise ignores further settles.
  function p:_resolve(v)
    if self._status ~= "pending" then return end
    self._status = "fulfilled"; if self._cbOk then self._cbOk(v) end
  end
  function p:_reject(r)
    if self._status ~= "pending" then return end
    self._status = "rejected"; if self._cbErr then self._cbErr(r) end
  end
  return p
end

describe("Weave.fromPromise — camino feliz (B1)", function()

  it("arranca en Weave.pending mientras la promesa no asienta", function()
    local W = helper.loadWeaveWow()
    local sig = W.fromPromise(fakePromise())
    assert_eq(sig(), W.pending, "antes de resolver, la señal vale el centinela pending")
  end)

  it("actualiza la señal al valor cuando la promesa se cumple", function()
    local W = helper.loadWeaveWow()
    local p = fakePromise()
    local sig = W.fromPromise(p)
    p:_resolve({ link = "ItemLink" })
    assert_eq(sig().link, "ItemLink")
  end)

  it("la señal devuelta es read-only (reactiva pero no writable)", function()
    local W = helper.loadWeaveWow()
    local sig = W.fromPromise(fakePromise())
    assert_true(W.isReactive(sig), "debe ser observable por effects/computeds")
    assert_false(W.isWritable(sig), "el valor lo posee la promesa, no el consumidor")
  end)

  it("Weave.pending y Weave.rejected son tablas centinela distintas", function()
    local W = helper.loadWeaveWow()
    assert_eq(type(W.pending), "table")
    assert_eq(type(W.rejected), "table")
    assert_true(W.pending ~= W.rejected, "cada centinela es una identidad única")
  end)

  it("effects/computeds enchufados reaccionan al resolver (integración con el core)", function()
    local W = helper.loadWeaveWow()
    local p = fakePromise()
    local sig = W.fromPromise(p)
    local seen = W.computed(function()
      local v = sig()
      return v == W.pending and "cargando" or v.name
    end)
    local last
    W.effect(function() last = seen() end)
    assert_eq(last, "cargando", "mientras carga, el consumidor ve el estado pending")
    p:_resolve({ name = "Poción" })
    assert_eq(last, "Poción", "al resolver, el effect re-corre con el valor")
  end)

  it("exige una promesa (tabla con :next)", function()
    local W = helper.loadWeaveWow()
    assert_error(function() W.fromPromise(42) end, "promise")
    assert_error(function() W.fromPromise({}) end, "promise")
  end)

end)

describe("Weave.fromPromise — rechazo (B2)", function()

  it("al rechazar, la señal pasa a Weave.rejected", function()
    local W = helper.loadWeaveWow()
    local p = fakePromise()
    local sig = W.fromPromise(p)
    p:_reject({ code = "not_found", message = "item 999 no existe" })
    assert_eq(sig(), W.rejected)
  end)

  it("opts.onError(reason) recibe el motivo estructurado de Loom", function()
    local W = helper.loadWeaveWow()
    local p, seen = fakePromise(), nil
    W.fromPromise(p, { onError = function(err) seen = err end })
    p:_reject({ code = "timeout", message = "tardó" })
    assert_eq(seen.code, "timeout")
  end)

  it("sin onError, un rechazo no crashea (la señal solo va a rejected)", function()
    local W = helper.loadWeaveWow()
    local p = fakePromise()
    local sig = W.fromPromise(p)
    p:_reject("cualquier cosa")           -- Loom permite reject con cualquier valor
    assert_eq(sig(), W.rejected)
  end)

  it("onError NO se dispara en el camino feliz", function()
    local W = helper.loadWeaveWow()
    local p, calls = fakePromise(), 0
    W.fromPromise(p, { onError = function() calls = calls + 1 end })
    p:_resolve({ ok = true })
    assert_eq(calls, 0)
  end)

  it("exige que opts.onError sea función si se pasa", function()
    local W = helper.loadWeaveWow()
    assert_error(function() W.fromPromise(fakePromise(), { onError = 42 }) end, "onError")
  end)

end)

describe("Weave.fromPromise — taint + cancelación por scope (B3)", function()

  it("valor secret con fallback declarado: el lector ve el fallback, no el secret", function()
    local W = helper.loadWeaveWow({ issecretvalue = helper.isFakeSecret })
    local p = fakePromise()
    local sig = W.fromPromise(p, { fallback = { name = "??" } })
    p:_resolve(helper.newFakeSecret())        -- Loom entregó un secret
    assert_eq(sig().name, "??", "degrada al fallback declarado")
  end)

  it("scope:dispose() cancela la promesa subyacente (cero leak de listeners)", function()
    local W = helper.loadWeaveWow()
    local p = fakePromise()
    local scope = W.scope()
    scope:run(function() W.fromPromise(p) end)
    assert_eq(p._cancelled, 0, "viva mientras el scope vive")
    scope:dispose()
    assert_eq(p._cancelled, 1, "dispose llama p:cancel() una vez")
  end)

  it("tras dispose, una resolución tardía ya no mueve la señal", function()
    local W = helper.loadWeaveWow()
    local p = fakePromise()
    local sig
    local scope = W.scope()
    scope:run(function() sig = W.fromPromise(p) end)
    scope:dispose()
    p:_resolve({ name = "tarde" })            -- cancelada: Loom no la asienta
    assert_eq(sig(), W.pending, "la señal se quedó en pending; sin update fantasma")
  end)

  it("fuera de un scope, fromPromise no intenta cancelar (no hay dueño)", function()
    local W = helper.loadWeaveWow()
    local p = fakePromise()
    W.fromPromise(p)                          -- sin scope activo
    assert_eq(p._cancelled, 0)
  end)

end)
