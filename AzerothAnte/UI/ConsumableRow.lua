local _, ns = ...

local Theme = ns.UI.Theme
local ConsumableRow = {}

local MEDIA = "Interface\\AddOns\\AzerothAnte\\Media\\"
local FRAMES = { scroll = "Consumable_Scroll", tome = "Consumable_Tome", relic = "Consumable_Relic" }
local KIND_NAMES = { scroll = "Scroll", tome = "Tome", relic = "Relic" }
local TOME_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local EMPTY_COLOR = { 0.12, 0.1, 0.08, 0.7 }
local MAX_SLOTS = 5
local SLOT_W, SLOT_H, SLOT_GAP = 44, 62, 8   -- 5:7, like a card
local ICON_SIZE = 26
local POP_W, POP_H = 150, 124
local POPOVER_LEVEL = 700                    -- above the shop and blind panels (600)

ConsumableRow.HEIGHT = SLOT_H

local row, popover
local openSlot                                -- slot index the popover belongs to, or nil
local openItem                                -- the item that slot held when it opened

local function main()
  return ns.UI.Main
end

local function persist()
  if ns.UI.OnRunChanged then ns.UI.OnRunChanged() end
end

local function fontPath()
  local f = GameFontNormalLarge
  if type(f) == "table" and f.GetFont then return (f:GetFont()) end
  return "Fonts\\FRIZQT__.TTF"
end

local function busy()
  local HandView, Tally = ns.UI.HandView, ns.UI.Tally
  return (HandView and HandView.IsBusy()) or (Tally and Tally.IsBusy()) or false
end

local function shortName(def)
  local name = def.name or "?"
  return (name:gsub("^%a+ of the ", ""):gsub("^%a+ of ", ""))
end

local function description(def, item)
  if def.desc then return def.desc end
  local hand = def.handId and ns.Hands.def[def.handId]
  return hand and ("Raises " .. hand.name .. " by one level when used.") or ""
end

local function sellValue(item)
  return math.floor(ns.Consumables.COST[item.kind] / 2)
end

-- One line saying exactly what the consumable will touch, so it is never a guess.
local function affectsText(run, item, def)
  local sel = ns.UI.HandView.Selected()
  if def.select then
    if not ns.Consumables.targetCards(run) then return "Needs a hand: use it during a blind." end
    local range = def.select.min == def.select.max and tostring(def.select.min)
      or (def.select.min .. "-" .. def.select.max)
    local n = #sel
    local ok = n >= def.select.min and n <= def.select.max
    return "Affects: " .. n .. " selected card" .. (n == 1 and "" or "s") .. (ok and "" or (" (needs " .. range .. ")"))
  end
  local desc = (description(def, item)):lower()
  if item.kind == "tome" then
    return "Affects: " .. (ns.Hands.def[def.handId] and ns.Hands.def[def.handId].name or "a hand") .. " level only"
  end
  if desc:find("in hand", 1, true) then return "Affects: your hand, not your selection" end
  if desc:find("trinket", 1, true) then return "Affects: your trinkets, not your cards" end
  if desc:find("create", 1, true) then return "Affects: your consumable slots only" end
  if desc:find("gold", 1, true) then return "Affects: your gold only" end
  return "Affects: nothing in your hand"
end

---------------------------------------------------------------------------
-- Slots

local function showTooltip(slot)
  local item = slot.item
  local def = item and ns.Consumables.def(item)
  if not def then return end
  GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(def.name, Theme.gold[1], Theme.gold[2], Theme.gold[3])
  GameTooltip:AddLine(KIND_NAMES[item.kind] or "", 0.7, 0.7, 0.7)
  GameTooltip:AddLine(description(def, item), 1, 1, 1, true)
  GameTooltip:AddLine("Click to use or sell (" .. sellValue(item) .. "g)", 0.6, 0.9, 0.6)
  GameTooltip:Show()
end

local function makeSlot(i)
  local slot = CreateFrame("Button", nil, row)
  slot:SetSize(SLOT_W, SLOT_H)
  slot:RegisterForClicks("LeftButtonUp")
  slot.index = i
  slot.glow = slot:CreateTexture(nil, "BACKGROUND")
  slot.glow:SetPoint("TOPLEFT", -3, 3)
  slot.glow:SetPoint("BOTTOMRIGHT", 3, -3)
  slot.glow:SetColorTexture(Theme.gold[1], Theme.gold[2], Theme.gold[3], 1)
  slot.glow:Hide()

  local holder = CreateFrame("Frame", nil, slot)
  holder:SetSize(SLOT_W, SLOT_H)
  holder:SetPoint("CENTER", slot, "CENTER")
  slot.holder = holder
  slot.empty = holder:CreateTexture(nil, "BACKGROUND")
  slot.empty:SetAllPoints()
  slot.empty:SetColorTexture(EMPTY_COLOR[1], EMPTY_COLOR[2], EMPTY_COLOR[3], EMPTY_COLOR[4])
  slot.art = holder:CreateTexture(nil, "ARTWORK")
  slot.art:SetAllPoints()
  slot.art:SetTexCoord(0, 1, 0, Theme.cardV)
  slot.icon = holder:CreateTexture(nil, "OVERLAY")
  slot.icon:SetSize(ICON_SIZE, ICON_SIZE)
  slot.icon:SetPoint("TOP", holder, "TOP", 0, -10)
  slot.plate = holder:CreateTexture(nil, "OVERLAY")
  slot.plate:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 3, 3)
  slot.plate:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -3, 3)
  slot.plate:SetHeight(14)
  slot.plate:SetColorTexture(0, 0, 0, 0.6)
  slot.name = holder:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
  slot.name:SetFont(fontPath(), 8, "OUTLINE")
  slot.name:SetPoint("BOTTOM", holder, "BOTTOM", 0, 5)
  slot.name:SetWidth(SLOT_W - 6)
  slot.name:SetWordWrap(false)
  Theme.setColor(slot.name, Theme.parchment)

  slot:SetScript("OnEnter", showTooltip)
  slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
  slot:SetScript("OnClick", function(self)
    if self.item then ConsumableRow.Toggle(i) end
  end)
  row.slots[i] = slot
  return slot
end

local function skin(slot, item)
  slot.item = item
  local def = item and ns.Consumables.def(item)
  if not def then
    slot.item = nil
    slot.empty:Show()
    slot.art:Hide()
    slot.icon:Hide()
    slot.plate:Hide()
    slot.name:SetText("")
    slot:EnableMouse(false)
    return
  end
  slot.empty:Hide()
  slot.art:SetTexture(MEDIA .. FRAMES[item.kind])
  slot.art:Show()
  slot.icon:SetTexture(def.icon or TOME_ICON)
  slot.icon:Show()
  slot.plate:Show()
  slot.name:SetText(shortName(def))
  slot:EnableMouse(true)
end

-- The pop animation target for a freshly created consumable item.
function ConsumableRow.HolderFor(item)
  if not row then return nil end
  for i = 1, #row.slots do
    local slot = row.slots[i]
    if slot.item == item and slot:IsShown() then return slot.holder end
  end
end

---------------------------------------------------------------------------
-- Popover

local function setButton(b, ok, reason)
  if ok then b:Enable() else b:Disable() end
  b.reason = (not ok) and reason or nil
  if not ok and GameTooltip:GetOwner() == b then
    GameTooltip:SetText(reason or "", 1, 1, 1, 1, true)
  end
end

-- Re-evaluates Use against the current hand selection (called on every
-- selection change) and refreshes the "Affects" line.
function ConsumableRow.Refresh()
  if not popover or not popover:IsShown() or not openSlot then return end
  local run = main() and main().run
  local item = run and run.consumables[openSlot]
  if not item or item ~= openItem then return ConsumableRow.Close() end
  local def = ns.Consumables.def(item)
  popover.affects:SetText(affectsText(run, item, def))
  local ok, reason
  if busy() then
    ok, reason = false, "Resolving..."
  else
    ok, reason = ns.Consumables.canUse(run, openSlot, ns.UI.HandView.Selected())
  end
  setButton(popover.use, ok, reason)
  setButton(popover.sell, not busy(), "Resolving...")
end

function ConsumableRow.Close()
  openSlot, openItem = nil, nil
  if popover then popover:Hide() end
  if row then
    for i = 1, #row.slots do row.slots[i].glow:Hide() end
  end
end

function ConsumableRow.Open(i)
  local run = main() and main().run
  local item = run and run.consumables[i]
  local def = item and ns.Consumables.def(item)
  if not def then return end
  openSlot, openItem = i, item
  for k = 1, #row.slots do row.slots[k].glow:SetShown(k == i) end
  popover.title:SetText(def.name)
  popover.sell:SetText("Sell (" .. sellValue(item) .. "g)")
  popover:Show()
  ConsumableRow.Refresh()
end

function ConsumableRow.Toggle(i)
  if openSlot == i and popover:IsShown() then ConsumableRow.Close() else ConsumableRow.Open(i) end
end

local function onUse()
  ConsumableRow.Use(openSlot)
end

local function onSell()
  local slot = openSlot
  local run = main() and main().run
  if not slot or not run or busy() then return end
  local gained = ns.Consumables.sell(run, slot)
  ConsumableRow.Close()
  main().Render(run, true)
  ns.UI.Outcome.FloatGold(gained)
  persist()
end

local function buildPopover()
  local p = CreateFrame("Frame", nil, main().content, "BackdropTemplate")
  p:SetSize(POP_W, POP_H)
  p:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -4)
  p:SetFrameLevel(main().content:GetFrameLevel() + POPOVER_LEVEL)
  p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  p:SetBackdropColor(0.1, 0.08, 0.06, 0.98)
  p:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
  p:EnableMouse(true)
  p.title = p:CreateFontString(nil, "OVERLAY", Theme.fonts.text)
  p.title:SetPoint("TOP", p, "TOP", 0, -8)
  p.title:SetWidth(POP_W - 12)
  Theme.setColor(p.title, Theme.gold)
  p.affects = p:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
  p.affects:SetPoint("TOP", p, "TOP", 0, -26)
  p.affects:SetWidth(POP_W - 16)
  p.affects:SetHeight(30)
  p.affects:SetJustifyV("TOP")
  Theme.setColor(p.affects, Theme.parchment)

  local function button(label, y, onClick)
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(POP_W - 20, 24)
    b:SetPoint("TOP", p, "TOP", 0, y)
    b:SetText(label)
    b:SetMotionScriptsWhileDisabled(true) -- the reason must show while disabled
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
      if self:IsEnabled() or not self.reason then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(self.reason, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end
  p.use = button("Use", -60, onUse)
  p.sell = button("Sell", -90, onSell)
  p:SetScript("OnHide", function() GameTooltip:Hide() end)
  p:Hide()
  popover = p
end

---------------------------------------------------------------------------
-- Use flow

-- Lock, apply, animate, re-render, unlock, persist. Returns true if it ran.
function ConsumableRow.Use(slot)
  local m = main()
  local run = m and m.run
  local HandView = ns.UI.HandView
  if not run or not slot or busy() then return false end
  local idx = HandView.Selected()
  if not ns.Consumables.canUse(run, slot, idx) then return false end
  local token = HandView.Lock()
  if not token then return false end
  local outcome = ns.Consumables.use(run, slot, idx)
  if not outcome then
    HandView.Unlock(token)
    return false
  end
  ConsumableRow.Close()
  HandView.ClearSelection() -- order and length may change; the cards animate unselected
  persist()
  m.Render(run, true)       -- gold, trinkets, slots and screens update now; effects play over them
  ns.UI.Outcome.Play(outcome, function()
    HandView.Unlock(token)  -- relayout (deals added cards, applies hand size), unlock
    m.Render(run, true)
    persist()
  end)
  return true
end

---------------------------------------------------------------------------

function ConsumableRow.Build(frame)
  row = frame
  frame.slots = {}
  for i = 1, MAX_SLOTS do makeSlot(i) end
  frame:SetScript("OnHide", function()
    ConsumableRow.Close()
    GameTooltip:Hide()
  end)
  buildPopover()
end

function ConsumableRow.Update(run)
  if not row or not row.slots then return end
  local count = math.min(MAX_SLOTS, run and run.maxConsumables or 0)
  local pitch = SLOT_W + SLOT_GAP
  for i = 1, #row.slots do
    local slot = row.slots[i]
    local shown = i <= count
    slot:SetShown(shown)
    slot:ClearAllPoints()
    -- Right-aligned, so the row grows leftwards from the window edge.
    slot:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(count - i) * pitch, 0)
    if shown then
      skin(slot, run and run.consumables[i])
      if not ns.UI.Tween.IsActive(slot.holder) then
        slot.holder:SetAlpha(1)
        slot.holder:SetScale(1)
      end
    else
      slot.item = nil
    end
  end
  if openSlot then ConsumableRow.Refresh() end
end

ns.UI.ConsumableRow = ConsumableRow
