-- core/Reconcile.lua — pure keyed-list reconciler: the brain of Weave.each (M6,
-- ADR-0007). PURE Lua 5.1: this file must not call any WoW API (ADR-0004) — it
-- plans over plain keys; frames and signals are the ui layer's business.
--
-- Weave._reconcileKeys(prevKeys, nextKeys) → plan
--   prevKeys: keys the rows display today, in row order (dense array).
--   nextKeys: keys the list wants to display now (dense array, unique).
--   plan.slots[i] = index into prevKeys whose row should display nextKeys[i]:
--     * a key present in both keeps ITS row (state preservation — the point of keying)
--     * a new key recycles a freed row if any (pooling), else nil = needs a fresh row
--   plan.freed = prev indices still left AFTER recycling, ascending (rows to hide).
--
-- Note: reconciliation allocates its plan tables — it runs per LIST change, not on
-- the signal set()→notify hot path, so the §1 zero-allocation contract doesn't apply.

local Weave = LibStub("Weave-1.0", true)
if not Weave or Weave._reconcileKeys then return end -- lib missing or duplicate copy

function Weave._reconcileKeys(prevKeys, nextKeys)
  local slotByKey = {}
  for j = 1, #prevKeys do slotByKey[prevKeys[j]] = j end

  -- Pass 1: keys present in both sides keep their own row.
  local slots, used, seen = {}, {}, {}
  for i = 1, #nextKeys do
    local k = nextKeys[i]
    if seen[k] then
      error("Weave.each: duplicate key '" .. tostring(k) .. "' — keys must be unique", 2)
    end
    seen[k] = true
    local j = slotByKey[k]
    if j then
      slots[i] = j
      used[j] = true
    end
  end

  -- Pass 2: recycle the rows nobody kept into the new keys, in order.
  local freed = {}
  for j = 1, #prevKeys do
    if not used[j] then freed[#freed + 1] = j end
  end
  local nextFree = 1
  for i = 1, #nextKeys do
    if slots[i] == nil and nextFree <= #freed then
      slots[i] = freed[nextFree]
      nextFree = nextFree + 1
    end
  end

  -- Whatever survived recycling is surplus: the ui layer hides it into the pool.
  local surplus = {}
  for f = nextFree, #freed do surplus[#surplus + 1] = freed[f] end
  return { slots = slots, freed = surplus }
end
