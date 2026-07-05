-- WeaveDemo/EachDemo.lua — M6 field test for Weave.each: a dynamic list panel
-- driven entirely by ONE signal. /weavelist exercises every contract in-game:
--   * add/del      → pooling (hidden rows come back with no CreateFrame)
--   * shuffle      → keying (click a row to mark it: the mark TRAVELS with the item)
--   * secret       → taint (values become secrets: text degrades to "??", no popup)
--   * in combat    → the pool only recycles; overflow warns once and catches up
--                    on leaving combat (warm pre-bakes 6 rows to play with)
--
-- The whole "view" is one description + one render recipe. No list code at all.

local W = LibStub("Weave-1.0")

-- 12.0+ client API; the shim keeps pre-12.0 clients working (nothing is secret there)
local issecretvalue = issecretvalue or function() return false end

-- STATE: one signal holding the array. Every change sets a NEW array (signals
-- compare by identity — mutating the same table in place would not notify).
local NAMES = { "alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
  "golf", "hotel", "india", "juliett", "kilo", "lima" }
local counter = 0

local function newItem()
  counter = counter + 1
  return { id = NAMES[counter] or ("item" .. counter), value = math.random(1, 99) }
end

local function initialItems()
  counter = 0
  return { newItem(), newItem(), newItem() }
end

local items = W.signal(initialItems())

local function snapshot()
  local t = {}
  for i, v in ipairs(items:peek()) do t[i] = v end
  return t
end

-- RENDER: runs ONCE per pooled row. `selected` is row-local state — shuffle
-- must carry it with the item (that is what opts.key buys).
local function renderRow(item, index)
  local selected = W.signal(false)
  return W.new("Button", {
    size = { 240, 18 },
    [W.children] = {
      W.new("Texture", {
        layer = "BACKGROUND",
        points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } },
        texture = "Interface\\Buttons\\WHITE8x8",
        vertexColor = W.computed(function()
          return selected() and { 0.9, 0.75, 0.2, 0.35 } or { 1, 1, 1, 0.06 }
        end),
      }),
      W.new("FontString", {
        layer = "OVERLAY", point = { "LEFT", 4, 0 },
        template = "GameFontHighlightSmall",
        text = W.computed(function()
          local it = item()
          if not it then return "" end -- warm rows idle in the pool with nil items
          local v = it.value
          if issecretvalue(v) then v = "??" end
          return ("%d. %s — %s"):format(index() or 0, it.id, tostring(v))
        end),
      }),
    },
    [W.on] = {
      OnMouseDown = function() selected:set(not selected:peek()) end,
    },
  })
end

-- VIEW
W.new("Frame", {
  name  = "WeaveEachDemo",
  point = { "CENTER", -330, 40 },
  size  = { 250, 300 },
  [W.children] = {
    W.new("FontString", {
      layer = "OVERLAY", point = { "BOTTOMLEFT", "WeaveEachDemo", "TOPLEFT", 4, 4 },
      template = "GameFontNormal", text = "Weave.each — /weavelist",
    }),
    W.each(items, renderRow, {
      key     = function(it) return it.id end,
      spacing = 2,
      warm    = 6,
    }),
  },
})

-- /weavelist: the knobs
SLASH_WEAVELIST1 = "/weavelist"
SlashCmdList.WEAVELIST = function(msg)
  local cmd, arg = msg:match("^(%S*)%s*(%S*)$")
  if cmd == "add" then
    local t = snapshot()
    for _ = 1, math.max(1, math.min(tonumber(arg) or 1, 30)) do t[#t + 1] = newItem() end
    items:set(t)
  elseif cmd == "del" then
    local t = snapshot()
    table.remove(t, tonumber(arg)) -- no arg = last
    items:set(t)
  elseif cmd == "shuffle" then
    local t = snapshot()
    for i = #t, 2, -1 do
      local j = math.random(i)
      t[i], t[j] = t[j], t[i]
    end
    items:set(t)
  elseif cmd == "secret" then
    -- 12.0.7: UnitHealth returns a secret in addon code, always — each row's
    -- text must degrade to "??" with zero popups (the item itself is fine).
    local t = snapshot()
    for i, it in ipairs(t) do t[i] = { id = it.id, value = UnitHealth("player") } end
    items:set(t)
  elseif cmd == "reset" then
    items:set(initialItems())
  else
    print("|cffffd100WeaveEachDemo:|r /weavelist add [n] · del [i] · shuffle · secret"
      .. " · reset — rows now: " .. #items:peek())
    print("  click a row to mark it, then shuffle: the mark travels with the item."
      .. " In combat, add past the pool: one warning, catches up after combat.")
  end
end
