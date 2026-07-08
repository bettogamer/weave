-- Catalog.lua — the 80/20 data catalog: Loom.item / Loom.spell (inspect lands in M2e).
-- Thin wrappers over Loom.event (ADR-0008, amended): check-first uses Blizzard's own cache
-- (IsItemDataCachedByID), dedup via key, cancellation/no-leak inherited from the primitive.
-- Item/Spell data is NOT secretable in 12.0.7 (secrets are combat/unit-scoped) — opts.fallback
-- (M3) exists for symmetry but rarely triggers here.

local Loom = LibStub("Loom-1.0")

-- C_Item.GetItemInfo returns 18 positional values (12.0.0+, with itemDescription). Pack them
-- into a named table so consumers read info.name / info.quality / … instead of positions.
local function itemInfo(id)
  local name, link, quality, level, minLevel, itemType, subType, stackCount, equipLoc, texture,
    sellPrice, classID, subclassID, bindType, expansionID, setID, isCraftingReagent, description =
    C_Item.GetItemInfo(id)
  if not name then return nil end
  return {
    name = name, link = link, quality = quality, level = level, minLevel = minLevel,
    type = itemType, subType = subType, stackCount = stackCount, equipLoc = equipLoc,
    texture = texture, sellPrice = sellPrice, classID = classID, subclassID = subclassID,
    bindType = bindType, expansionID = expansionID, setID = setID,
    isCraftingReagent = isCraftingReagent, description = description,
  }
end

-- Apply the default 5s timeout unless opts.timeout is false (disable) or a number (override).
local function withTimeout(p, opts)
  if opts.timeout == false then return p end
  return p:timeout(opts.timeout or 5)
end

--- Loads item info. Resolves with a named table (see itemInfo), rejects { code="not_found" }
--- if the server has no data. Check-first + in-flight dedup. (API-v0 §2.)
function Loom.item(idOrLink, opts)
  opts = opts or {}
  local p = Loom.event(
    function() C_Item.RequestLoadItemDataByID(idOrLink) end,
    "GET_ITEM_INFO_RECEIVED",
    function(loadedId) return loadedId == idOrLink end,
    {
      key = "item:" .. tostring(idOrLink),
      checkCache = function() if C_Item.IsItemDataCachedByID(idOrLink) then return true end end,
    }
  ):next(function()
    local info = itemInfo(idOrLink)
    if not info then
      return Loom.reject({ code = "not_found", message = "item not found: " .. tostring(idOrLink) })
    end
    return info
  end)
  return withTimeout(Loom._withFallback(p, opts.fallback), opts)
end

--- Loads spell info. C_Spell.GetSpellInfo already returns a table. Same shape as Loom.item.
function Loom.spell(idOrName, opts)
  opts = opts or {}
  local p = Loom.event(
    function() C_Spell.RequestLoadSpellData(idOrName) end,
    "SPELL_DATA_LOAD_RESULT",
    function(loadedId) return loadedId == idOrName end,
    {
      key = "spell:" .. tostring(idOrName),
      checkCache = function() if C_Spell.IsSpellDataCached(idOrName) then return true end end,
    }
  ):next(function()
    local info = C_Spell.GetSpellInfo(idOrName)
    if not info then
      return Loom.reject({ code = "not_found", message = "spell not found: " .. tostring(idOrName) })
    end
    return info
  end)
  return withTimeout(Loom._withFallback(p, opts.fallback), opts)
end
