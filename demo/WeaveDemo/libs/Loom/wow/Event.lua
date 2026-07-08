-- Event.lua — the wow/ primitive: request -> event -> match -> resolve -> auto-deregister.
-- Everything in the catalog is built on this. One shared frame multiplexes all listeners;
-- an event is unregistered as soon as its last listener is gone (no leak). Check-first and
-- in-flight dedup are opt-in via opts (ADR-0007 / ADR-0008); a match that crashes on a secret
-- degrades instead of rejecting (ADR-0004).

local Loom = LibStub("Loom-1.0")

local frame = CreateFrame("Frame")
local listeners = {} -- event -> array of rec { event, match, resolve, key, promise, _warned }
local inflight = {}  -- key -> promise (in-flight dedup)

-- Pack event varargs into an array with an explicit count (Lua 5.1 has no table.pack, and
-- {...} drops trailing nils). The primitive resolves with this table (API-v0 §2).
local function pack(...)
  local t = { ... }
  t.n = select("#", ...)
  return t
end

-- Remove a listener; unregister the event if it was the last one; clear its dedup entry.
local function removeRec(rec)
  local list = listeners[rec.event]
  if list then
    for i = #list, 1, -1 do
      if list[i] == rec then table.remove(list, i); break end
    end
    if #list == 0 then
      listeners[rec.event] = nil
      frame:UnregisterEvent(rec.event)
    end
  end
  if rec.key and inflight[rec.key] == rec.promise then inflight[rec.key] = nil end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = listeners[event]
  if not list then return end
  -- Backwards: a matching listener resolves and is removed mid-iteration.
  for i = #list, 1, -1 do
    local rec = list[i]
    local ok, matched = pcall(rec.match, ...)
    if not ok then
      -- match crashed. If it hit a secret, degrade (log once, keep listening) — ADR-0004.
      -- Any other error is also swallowed at this frontier (defensive): never reject here.
      if Loom._isSecretError(matched) and not rec._warned then
        rec._warned = true
        print("|cffffcc00Loom|r: event match hit a secret value; degraded (still listening).")
      end
    elseif matched then
      rec.resolve(pack(...))
      removeRec(rec)
    end
  end
end)

--- The primitive. See API-v0 §2. `opts`: { checkCache = fn?, key = string? }.
function Loom.event(request, event, match, opts)
  opts = opts or {}
  if opts.key and inflight[opts.key] then return inflight[opts.key] end

  local p, resolve = Loom._deferred()
  local rec = { event = event, match = match, resolve = resolve, key = opts.key, promise = p }
  if opts.key then inflight[opts.key] = p end
  Loom._setOnCancel(p, function() removeRec(rec) end)

  -- Check-first: if the data is already cached, resolve async (next frame, not sync — §3.3)
  -- WITHOUT registering the event (ADR-0008). The cached value is delivered as-is.
  if opts.checkCache then
    local cached = opts.checkCache()
    if cached ~= nil then
      C_Timer.After(0, function()
        resolve(cached) -- no-op if cancelled meanwhile
        removeRec(rec)  -- clears the dedup entry
      end)
      return p
    end
  end

  -- Listen BEFORE firing the request, so an instant response can't be missed.
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], rec)
  frame:RegisterEvent(event)
  if request then request() end
  return p
end
