-- wow/Promise.lua — a Loom promise as a read-only signal: fromPromise (API-v0 §2, ADR-0009).
-- The one-shot twin of fromEvent. Weave OWNS this bridge (ADR-0009, mirror of Loom's ADR-0010):
-- it consumes ONLY the promise's PUBLIC surface (:next / :status / :isSecret / :cancel) — never
-- Loom internals — so Loom stays 100% ignorant of Weave and adoptable without it.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave.fromPromise then return end -- lib missing or duplicate copy

-- Public sentinels: distinguishable-by-identity markers a consumer branches on
-- (`if sig() == Weave.pending then ...`). Plain tables, never confused with real data
-- and never a value a promise could legitimately resolve to.
Weave.pending  = Weave.pending  or {}
Weave.rejected = Weave.rejected or {}

-- Turns a Loom promise into a read-only Weave signal. The signal starts at the
-- `pending` sentinel and updates to the resolved value when the promise settles.
function Weave.fromPromise(promise, opts)
  if type(promise) ~= "table" or type(promise.next) ~= "function" then
    error("Weave.fromPromise: expected a Loom promise (a table with :next), got " .. type(promise), 2)
  end
  if opts ~= nil and type(opts) ~= "table" then
    error("Weave.fromPromise: opts must be a table, got " .. type(opts), 2)
  end
  local onError = opts and opts.onError
  if onError ~= nil and type(onError) ~= "function" then
    error("Weave.fromPromise: opts.onError must be a function, got " .. type(onError), 2)
  end
  -- An internal writable signal holds the state; the handle we hand back is a
  -- computed (no :set) so the value stays owned by the promise lifecycle — the
  -- consumer observes it but can't desync it by writing (API-v0 §2, read-only).
  local inner = Weave.signal(Weave.pending, opts)
  promise:next(
    function(value) inner:set(value) end,
    function(reason)
      -- Rejection surfaces as a distinct sentinel so the view can branch on it;
      -- onError is the optional imperative hook (log/toast) with Loom's structured
      -- reason ({ code, message }). Set the signal first so onError sees `rejected`.
      inner:set(Weave.rejected)
      if onError then onError(reason) end
    end
  )
  -- Tie the promise to the active scope: disposing the scope cancels the promise,
  -- which unregisters Loom's underlying event listener (structural cancellation,
  -- Loom ADR-0011) → zero leak. Outside a scope, _attachToScope is a no-op.
  Weave._attachToScope({ dispose = function()
    if promise.cancel then promise:cancel() end
  end })
  return Weave.computed(function() return inner() end)
end
