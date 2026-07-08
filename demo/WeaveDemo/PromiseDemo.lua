-- WeaveDemo/PromiseDemo.lua — M9 field test for Weave.fromPromise (ADR-0009): a Loom
-- promise driving a Weave signal. Loading an item shows the whole boundary — a skeleton
-- while the data is in flight (signal == W.pending), then the real item when it settles,
-- or a "failed" state on rejection (W.rejected + onError). Each load runs in its own
-- scope: firing a new load DISPOSES the previous scope, which cancels the previous promise
-- (structural cancellation, zero leak) and clears its binds — B3 of M9, live.
--   /weavepromise          → load a Hearthstone (item 6948): skeleton → value
--   /weavepromise <itemID> → load that item
--   /weavepromise bad      → load a non-existent item: skeleton → rejected
-- Loom is vendored (READ-ONLY) under libs/Loom (v0.1.0); LibStub comes from the Weave addon.

local W = LibStub("Weave-1.0")
local Loom = LibStub("Loom-1.0", true) -- silent: degrade gracefully if the embed is missing

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- VIEW: a persistent panel, created once. The binds are (re)made per load, inside a scope.
local panel = CreateFrame("Frame", "WeavePromiseDemo", UIParent)
panel:SetSize(300, 92)
panel:SetPoint("TOP", UIParent, "TOP", 0, -260)
panel:Hide()

local bg = panel:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(true)
bg:SetColorTexture(0, 0, 0, 0.7)

local icon = panel:CreateTexture(nil, "ARTWORK")
icon:SetSize(48, 48)
icon:SetPoint("LEFT", 14, 0)

local nameFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
nameFS:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -4)
nameFS:SetPoint("RIGHT", -12, 0)
nameFS:SetJustifyH("LEFT")

local statusFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
statusFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -8)
statusFS:SetPoint("RIGHT", -12, 0)
statusFS:SetJustifyH("LEFT")

local loadScope

local function load(itemID)
  if not Loom then
    print("|cffff4444WeavePromise:|r Loom is not loaded (check libs/Loom embed)")
    return
  end
  -- Dispose the previous load: cancels the in-flight promise (unregisters its event,
  -- zero leak) and clears the old binds before we make new ones.
  if loadScope then loadScope:dispose() end
  loadScope = W.scope()
  loadScope:run(function()
    local sig = W.fromPromise(Loom.item(itemID, { timeout = 3 }), {
      onError = function(err)
        local code = type(err) == "table" and err.code or tostring(err)
        print("|cffff4444WeavePromise:|r load failed (" .. tostring(code) .. ")")
      end,
    })
    -- Item info is NOT a secret value in 12.0.7, so indexing the resolved table is safe;
    -- the sentinels are plain tables, compared by identity.
    W.bind(icon, "texture", W.computed(function()
      local v = sig()
      if v == W.pending or v == W.rejected then return QUESTION end
      return v.texture or QUESTION
    end))
    W.bind(nameFS, "text", W.computed(function()
      local v = sig()
      if v == W.pending  then return "|cffaaaaaaLoading item…|r" end
      if v == W.rejected then return "|cffff4444Load failed|r" end
      return v.link or v.name or "?"
    end))
    W.bind(statusFS, "text", W.computed(function()
      local v = sig()
      if v == W.pending  then return "state: pending — waiting for the item to load" end
      if v == W.rejected then return "state: rejected" end
      return ("state: fulfilled — quality %s, ilvl %s"):format(tostring(v.quality), tostring(v.level))
    end))
  end)
  panel:Show()
end

SLASH_WEAVEPROMISE1 = "/weavepromise"
SlashCmdList["WEAVEPROMISE"] = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "bad" then
    print("|cff44ff44WeavePromise:|r loading a non-existent item (expect rejected)")
    load(999999)
  else
    local id = tonumber(msg) or 6948 -- default: Hearthstone (usually cached → resolves fast)
    print(("|cff44ff44WeavePromise:|r loading item %d (skeleton → value)"):format(id))
    load(id)
  end
end
