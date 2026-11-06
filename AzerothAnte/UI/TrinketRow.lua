local _, ns = ...

local Theme = ns.UI.Theme
local TrinketRow = {}

local MIN_SLOTS = 5 -- slots built up front; Run.trinketSlots grows it (Negative trinkets)
local SLOT_SIZE = 44
local SLOT_GAP = 8
local SELL_W, SELL_H = 44, 18 -- as wide as a slot, so sell buttons never overlap

local sellMode, onSell = false, nil

local function showTooltip(slot)
  local def = slot.def
  if not def then return end
  GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(def.name, Theme.gold[1], Theme.gold[2], Theme.gold[3])
  GameTooltip:AddLine(def.desc or "", 1, 1, 1, true)
  local r = Theme.rarity[def.rarity] or Theme.rarity.common
  GameTooltip:AddLine(def.rarity and (def.rarity:sub(1, 1):upper() .. def.rarity:sub(2)) or "", r[1], r[2], r[3])
  local ed = slot.trinket and ns.CardTypes.ed[slot.trinket.ed]
  if ed then
    GameTooltip:AddLine(ed.name, Theme.gold[1], Theme.gold[2], Theme.gold[3])
    GameTooltip:AddLine(ed.desc, 1, 1, 1, true)
  end
  GameTooltip:Show()
end

-- Shows an "Ng" sell button under each owned trinket while sell mode is on.
local function refreshSell()
  local frame = ns.UI.Main and ns.UI.Main.trinketRow
  if not frame or not frame.slots then return end
  for i = 1, #frame.slots do
    local slot = frame.slots[i]
    if sellMode and slot.def and slot:IsShown() then
      slot.sell.price = ns.Shop.sellValue(slot.trinket)
      slot.sell:SetText(slot.sell.price .. "g")
      slot.sell.trinketId = slot.def.id -- identity captured at render time
      slot.sell:Show()
    else
      slot.sell:Hide()
    end
  end
end

-- onSellFn(slotIndex, trinketId) is called when a sell button is clicked.
function TrinketRow.SetSellMode(enabled, onSellFn)
  sellMode = enabled and true or false
  onSell = enabled and onSellFn or nil
  refreshSell()
end

local function makeSlot(frame, i)
  local slot = CreateFrame("Frame", nil, frame)
  slot:SetSize(SLOT_SIZE, SLOT_SIZE)
  slot:SetPoint("LEFT", frame, "LEFT", (i - 1) * (SLOT_SIZE + SLOT_GAP), 0)
  slot.index = i
  slot:EnableMouse(true)
  slot.holder = CreateFrame("Frame", nil, slot)
  slot.holder:SetSize(SLOT_SIZE, SLOT_SIZE)
  slot.holder:SetPoint("CENTER", slot, "CENTER")
  slot.empty = Theme.EmptySlot(slot.holder)
  slot.icon = slot.holder:CreateTexture(nil, "ARTWORK")
  slot.icon:SetAllPoints()
  slot.icon:Hide()
  local sell = Theme.NewButton(slot, nil, SELL_W, SELL_H)
  sell:SetPoint("TOP", slot, "BOTTOM", 0, -1)
  sell:SetScript("OnClick", function()
    if onSell then onSell(i, sell.trinketId) end
  end)
  sell:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Sell for " .. (self.price or 0) .. "g", 1, 1, 1)
    GameTooltip:Show()
  end)
  sell:SetScript("OnLeave", function() GameTooltip:Hide() end)
  sell:Hide()
  slot.sell = sell
  slot:SetScript("OnEnter", showTooltip)
  slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.slots[i] = slot
  return slot
end

function TrinketRow.Build(frame)
  frame.slots = {}
  frame:SetScript("OnHide", function() GameTooltip:Hide() end)
  for i = 1, MIN_SLOTS do makeSlot(frame, i) end
end

function TrinketRow.Update(run)
  local frame = ns.UI.Main and ns.UI.Main.trinketRow
  if not frame or not frame.slots then return end
  local trinkets = run and run.trinkets or {}
  local count = run and ns.Run.trinketSlots(run) or MIN_SLOTS
  for i = #frame.slots + 1, count do makeSlot(frame, i) end
  -- Tighten the spacing (never below touching) when the row is crowded.
  local pitch = SLOT_SIZE + SLOT_GAP
  if count > 1 and frame:GetWidth() > 0 then
    pitch = math.max(SLOT_SIZE, math.min(pitch, (frame:GetWidth() - SLOT_SIZE) / (count - 1)))
  end
  for i = 1, #frame.slots do
    local slot = frame.slots[i]
    slot:SetShown(i <= count)
    slot:ClearAllPoints()
    slot:SetPoint("LEFT", frame, "LEFT", (i - 1) * pitch, 0)
    local entry = trinkets[i]
    local def = entry and ns.Trinkets.def[entry.id]
    slot.def = def
    slot.trinket = entry
    slot.empty:SetShown(not def)
    slot.icon:SetShown(def ~= nil)
    if def then slot.icon:SetTexture(def.icon) end
    ns.UI.EditionFX.Attach(slot.holder, def and entry.ed or nil)
  end
  refreshSell()
end

-- Short scale pulse on slot `index` (1-5); driven by OnUpdate, no AnimationGroup.
function TrinketRow.Pulse(index)
  local frame = ns.UI.Main and ns.UI.Main.trinketRow
  local slot = frame and frame.slots and frame.slots[index]
  if not slot then return end
  local DURATION = 0.3
  local t = 0
  local holder = slot.holder
  holder:SetScript("OnUpdate", function(self, elapsed)
    t = t + elapsed
    if t >= DURATION then
      self:SetScale(1)
      self:SetScript("OnUpdate", nil)
      return
    end
    self:SetScale(1 + 0.3 * math.sin(math.pi * t / DURATION))
  end)
end

ns.UI.TrinketRow = TrinketRow
