local _, ns = ...

local Theme = ns.UI.Theme
local TrinketRow = {}

local SLOTS = 5
local SLOT_SIZE = 44
local SLOT_GAP = 8
local EMPTY_ICON = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local function showTooltip(slot)
  local def = slot.def
  if not def then return end
  GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(def.name, Theme.gold[1], Theme.gold[2], Theme.gold[3])
  GameTooltip:AddLine(def.desc or "", 1, 1, 1, true)
  local r = Theme.rarity[def.rarity] or Theme.rarity.common
  GameTooltip:AddLine(def.rarity and (def.rarity:sub(1, 1):upper() .. def.rarity:sub(2)) or "", r[1], r[2], r[3])
  GameTooltip:Show()
end

function TrinketRow.Build(frame)
  frame.slots = {}
  frame:SetScript("OnHide", function() GameTooltip:Hide() end)
  for i = 1, SLOTS do
    local slot = CreateFrame("Frame", nil, frame)
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)
    slot:SetPoint("LEFT", frame, "LEFT", (i - 1) * (SLOT_SIZE + SLOT_GAP), 0)
    slot:EnableMouse(true)
    slot.holder = CreateFrame("Frame", nil, slot)
    slot.holder:SetSize(SLOT_SIZE, SLOT_SIZE)
    slot.holder:SetPoint("CENTER", slot, "CENTER")
    slot.icon = slot.holder:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints()
    slot.icon:SetTexture(EMPTY_ICON)
    slot.icon:SetAlpha(0.4)
    slot:SetScript("OnEnter", showTooltip)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.slots[i] = slot
  end
end

function TrinketRow.Update(run)
  local frame = ns.UI.Main and ns.UI.Main.trinketRow
  if not frame or not frame.slots then return end
  local trinkets = run and run.trinkets or {}
  for i = 1, SLOTS do
    local slot = frame.slots[i]
    local entry = trinkets[i]
    local def = entry and ns.Trinkets.def[entry.id]
    slot.def = def
    if def then
      slot.icon:SetTexture(def.icon)
      slot.icon:SetAlpha(1)
    else
      slot.icon:SetTexture(EMPTY_ICON)
      slot.icon:SetAlpha(0.4)
    end
  end
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
