-- tween_spec.lua — contract for the PURE interpolation engine behind Weave.tween
-- (API-v0 §2, M8/ADR-0008). Core layer: plain math over numbers/arrays, ZERO WoW,
-- ZERO clock — the engine is told how much time has elapsed, the wow/ driver owns GetTime.
--
-- Weave._tweenEngine(from, to, duration, easing) → anim
--   anim:at(elapsed) → value, done
--     value : interpolated number, OR the SAME reused array (in-place) — §1 no-alloc.
--     done  : true once elapsed >= duration.
-- Weave.easing = { linear, inQuad, outQuad, inOutQuad } — pure easing curves (t→t).

local helper = dofile("tests/helper.lua")

describe("Weave._tweenEngine: motor de interpolación puro", function()

  describe("números", function()

    it("interpola linealmente de A a B según la fracción de tiempo", function()
      local W = helper.loadWeave()
      local a = W._tweenEngine(0, 100, 1, W.easing.linear)
      assert_eq(a:at(0),    0,   "al inicio vale A")
      assert_eq(a:at(0.5),  50,  "a mitad de tiempo, mitad de camino")
      assert_eq(a:at(1),    100, "al final vale B")
    end)

    it("aplica el easing a la fracción antes de interpolar", function()
      local W = helper.loadWeave()
      local a = W._tweenEngine(0, 100, 1, W.easing.outQuad) -- outQuad(0.5) = 0.75
      assert_eq(a:at(0.5), 75, "con outQuad, a mitad de tiempo ya vamos por 75%")
    end)

    it("clampa por arriba: elapsed mayor que la duración da el valor final", function()
      local W = helper.loadWeave()
      local a = W._tweenEngine(0, 100, 1, W.easing.linear)
      assert_eq(a:at(2), 100, "pasado el tiempo, se queda en B")
    end)

    it("elapsed = 0 devuelve el valor inicial", function()
      local W = helper.loadWeave()
      local a = W._tweenEngine(20, 80, 1, W.easing.linear)
      assert_eq(a:at(0), 20, "sin tiempo transcurrido, sigue en A")
    end)

    it("done es false mientras no llega y true al alcanzar la duración", function()
      local W = helper.loadWeave()
      local a = W._tweenEngine(0, 100, 1, W.easing.linear)
      local _, d1 = a:at(0.5)
      local _, d2 = a:at(1)
      local _, d3 = a:at(2)
      assert_false(d1, "a mitad, sigue animando")
      assert_true(d2,  "al llegar a la duración, terminó")
      assert_true(d3,  "pasada la duración, terminó")
    end)

    it("duración 0: done inmediato en el valor final, sin dividir por cero", function()
      local W = helper.loadWeave()
      local a = W._tweenEngine(0, 100, 0, W.easing.linear)
      local v, done = a:at(0)
      assert_eq(v, 100,  "duración cero salta directo a B")
      assert_true(done,  "y ya está terminado")
    end)

  end)

  describe("arrays (color / posición)", function()

    it("interpola cada elemento por separado", function()
      local W = helper.loadWeave()
      local a = W._tweenEngine({ 1, 0, 0 }, { 0, 1, 0 }, 1, W.easing.linear) -- rojo → verde
      local v = a:at(0.5)
      assert_eq(v[1], 0.5, "canal R baja a la mitad")
      assert_eq(v[2], 0.5, "canal G sube a la mitad")
      assert_eq(v[3], 0,   "canal B se queda igual")
    end)

    it("reutiliza la misma tabla-resultado entre frames (cero allocations)", function()
      local W = helper.loadWeave()
      local a = W._tweenEngine({ 0, 0 }, { 10, 10 }, 1, W.easing.linear)
      local b1 = a:at(0.3)
      local b2 = a:at(0.7)
      assert_true(b1 == b2, "el motor no crea una tabla nueva por frame (contrato §1)")
    end)

  end)

  describe("easings", function()

    it("linear es la identidad", function()
      local W = helper.loadWeave()
      local e = W.easing.linear
      assert_eq(e(0), 0)
      assert_eq(e(0.5), 0.5)
      assert_eq(e(1), 1)
    end)

    it("outQuad arranca rápido y frena", function()
      local W = helper.loadWeave()
      local e = W.easing.outQuad
      assert_eq(e(0), 0)
      assert_eq(e(0.5), 0.75, "ya recorrió el 75% a mitad de tiempo")
      assert_eq(e(1), 1)
    end)

    it("inQuad arranca lento", function()
      local W = helper.loadWeave()
      local e = W.easing.inQuad
      assert_eq(e(0.5), 0.25, "solo el 25% a mitad de tiempo")
      assert_eq(e(1), 1)
    end)

    it("inOutQuad es simétrica", function()
      local W = helper.loadWeave()
      local e = W.easing.inOutQuad
      assert_eq(e(0), 0)
      assert_eq(e(0.5), 0.5, "el punto medio cae justo a la mitad")
      assert_eq(e(1), 1)
    end)

  end)

  describe("casos límite", function()

    it("from == to devuelve un valor constante en todo instante", function()
      local W = helper.loadWeave()
      local a = W._tweenEngine(5, 5, 1, W.easing.linear)
      assert_eq(a:at(0),   5)
      assert_eq(a:at(0.5), 5)
      assert_eq(a:at(1),   5)
    end)

  end)

end)
