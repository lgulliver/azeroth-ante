local _, ns = ...

local Theme = ns.UI.Theme
local ConsumableRow = {}

local MEDIA = "Interface\\AddOns\\AzerothAnte\\Media\\"
local FRAMES = { scroll = "Consumable_Scroll", tome = "Consumable_Tome", relic = "Consumable_Relic" }
local KIND_NAMES = { scroll = "Scroll", tome = "Tome", relic = "Relic" }
local TOME_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local MAX_SLOTS = 5
local SLOT_W, SLOT_H, SLOT_GAP = 44, 62, 6   -- 5:7, like a card
local ICON_SIZE = 26
local POP_W, POP_H = 150, 124
local POP_FROM, POP_TIME = 0.6, 0.2          -- a created consumable pops into its slot
local POPOVER_LEVEL = 700                    -- above the shop and blind panels (600)

ConsumableRow.HEIGHT = SLOT_H

local row, popover
local openSlot                                -- slot index the popover belongs to, or nil
local USE_IN_PLAY = "Use while playing a hand"
local USE_IN_SHOP = "Use in a hand, or open an Arcana or Spectral pack"
local openPhase, catcher, globalMouse
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
  local HandView, Tally, PackView = ns.UI.HandView, ns.UI.Tally, ns.UI.PackView
  local Lifecycle = ns.UI.Lifecycle
  return (HandView and HandView.IsBusy()) or (Tally and Tally.IsBusy())
    or (PackView and PackView.IsBusy()) or (Lifecycle and Lifecycle.IsBusy()) or false
end

-- Whether a pack with a drawn hand is the thing being aimed at (it has its own selection).
local function packHandOpen(run)
  return run and run.phase ~= "play" and ns.UI.PackView ~= nil
    and ns.Consumables.targetCards(run) ~= nil
end

local function selection(run)
  if packHandOpen(run) then return ns.UI.PackView.Selected() end
  return ns.UI.HandView.Selected()
end

local function clearSelection(run)
  if packHandOpen(run) then ns.UI.PackView.ClearSelection() else ns.UI.HandView.ClearSelection() end
end

local function shortName(def)
  local name = def.name or "?"
  return (name:gsub("^%a+ of the ", ""):gsub("^%a+ of ", ""))
end

local function sellValue(item)
  return ns.Consumables.sellValue(item)
end

-- One line saying exactly what the consumable touches (explicit `affects` on
-- every Scroll and Relic def); targeted ones also show the live selection count.
local function affectsText(run, item, def)
  local text = ns.Consumables.affects(run, item)
  if item.kind == "tome" then return text end
  if def.select then
    local n = #selection(run)
    text = text .. " (" .. n .. " selected)"
  end
  return text
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
  local run = main() and main().run
  GameTooltip:AddLine(ns.Consumables.describe(run, item), 1, 1, 1, true)
  if item.kind == "tome" then
    GameTooltip:AddLine(ns.Consumables.affects(run, item), Theme.gold[1], Theme.gold[2], Theme.gold[3])
  end
  GameTooltip:AddLine("Click to use or sell (" .. sellValue(item) .. "g)", 0.6, 0.9, 0.6)
  GameTooltip:Show()
end

local function makeSlot(i)
  local slot = CreateFrame("Button", nil, row)
  slot:SetSize(SLOT_W, SLOT_H)
  slot:RegisterForClicks("LeftButtonUp")
  slot.index = i
  Theme.Selected(slot, false) -- the open slot gets a thin gold outline and soft glow

  local holder = CreateFrame("Frame", nil, slot)
  holder:SetSize(SLOT_W, SLOT_H)
  holder:SetPoint("CENTER", slot, "CENTER")
  slot.holder = holder
  slot.empty = Theme.EmptySlot(holder)
  slot.art = holder:CreateTexture(nil, "ARTWORK")
  slot.art:SetAllPoints()
  slot.art:SetTexCoord(0, 1, 0, Theme.cardV)
  slot.icon = holder:CreateTexture(nil, "OVERLAY")
  slot.icon:SetSize(ICON_SIZE, ICON_SIZE)
  slot.icon:SetPoint("CENTER", holder, "TOP", 0, -math.floor(SLOT_H * 78 / 179 + 0.5)) -- centred in the card art's icon window
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
-- The holder of consumable slot `index` (pulse target), or nil.
function ConsumableRow.SlotHolder(index)
  local slot = row and row.slots and row.slots[index]
  return slot and slot:IsShown() and slot.holder or nil
end

function ConsumableRow.HolderFor(item)
  if not row then return nil end
  for i = 1, #row.slots do
    local slot = row.slots[i]
    if slot.item == item and slot:IsShown() then return slot.holder end
  end
end

-- Shows an item just added to run.consumables: the row catches up, then its slot pops in
-- (scale 0.6 to 1, 0.2s / speed). Returns the holder, or nil when it has no slot.
function ConsumableRow.PopIn(run, item, speed)
  ConsumableRow.Update(run)
  local holder = ConsumableRow.HolderFor(item)
  if not holder then return nil end
  holder:SetScale(POP_FROM)
  holder:SetAlpha(0)
  ns.UI.Tween.To(holder, { scale = 1, alpha = 1 }, POP_TIME / (speed or 1))
  return holder
end

---------------------------------------------------------------------------
-- Popover

-- Keeps a hovered button's tooltip truthful when it flips between states.
local function setButton(b, ok, reason)
  if ok then b:Enable() else b:Disable() end
  b.reason = (not ok) and reason or nil
  if GameTooltip:GetOwner() == b then
    if ok then
      GameTooltip:Hide()
    else
      GameTooltip:SetOwner(b, "ANCHOR_LEFT")
      GameTooltip:SetText(reason or "", 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end
end

-- Re-evaluates Use against the current hand selection (called on every
-- selection change) and refreshes the "Affects" line.
function ConsumableRow.Refresh()
  if not popover or not popover:IsShown() or not openSlot then return end
  local run = main() and main().run
  local item = run and run.consumables[openSlot]
  if not item or item ~= openItem or run.phase ~= openPhase then return ConsumableRow.Close() end
  local def = ns.Consumables.def(item)
  popover.affects:SetText(affectsText(run, item, def))
  local ok, reason
  if busy() then
    ok, reason = false, "Resolving..."
  else
    ok, reason = ns.Consumables.canUse(run, openSlot, selection(run))
    if reason == ns.Consumables.REASON_NO_HAND then
      reason = run.phase == "shop" and USE_IN_SHOP or USE_IN_PLAY
    end
  end
  setButton(popover.use, ok, reason)
  setButton(popover.sell, not busy(), "Resolving...")
end

function ConsumableRow.Close()
  openSlot, openItem, openPhase = nil, nil, nil
  if globalMouse then
    row:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    globalMouse = false
  end
  if catcher then catcher:Hide() end
  if popover then popover:Hide() end
  if row then
    for i = 1, #row.slots do Theme.Selected(row.slots[i], false) end
  end
end

function ConsumableRow.Open(i)
  local run = main() and main().run
  local item = run and run.consumables[i]
  local def = item and ns.Consumables.def(item)
  if not def then return end
  openSlot, openItem, openPhase = i, item, run.phase
  -- Preferred: watch every mouse-down and close on one outside the popover; the
  -- click itself still reaches what was clicked. Where the event does not exist,
  -- fall back to a click-catcher.
  globalMouse = pcall(row.RegisterEvent, row, "GLOBAL_MOUSE_DOWN")
  if not globalMouse then
    ConsumableRow.LayoutCatcher(run)
    catcher:Show()
  end
  for k = 1, #row.slots do Theme.Selected(row.slots[k], k == i) end
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
  persist() -- saved before the events play, like a trinket sale
  ns.UI.Outcome.FloatGold(gained)
  -- Selling can move a trinket (Cooking Fire grows): its events play before the table renders.
  ns.UI.Lifecycle.Drain(run, function()
    main().Render(run, true)
    if run.phase == "play" then ns.UI.HandView.Update(run, true) end
    persist()
  end)
end

-- Transparent click-catcher under the popover: a click anywhere else closes it.
-- While playing a hand it stops above the hand area, so cards stay clickable
-- (selecting is how you aim a targeted consumable).
function ConsumableRow.LayoutCatcher(run)
  local m = main()
  catcher:ClearAllPoints()
  catcher:SetPoint("TOPLEFT", m.content, "TOPLEFT", 0, 0)
  if run and run.phase == "play" then
    catcher:SetPoint("BOTTOMRIGHT", m.handArea, "TOPRIGHT", Theme.margin, 0)
  elseif packHandOpen(run) and ns.UI.PackView.HandFrame() then
    catcher:SetPoint("BOTTOMRIGHT", ns.UI.PackView.HandFrame(), "TOPRIGHT", Theme.margin, 0)
  else
    catcher:SetPoint("BOTTOMRIGHT", m.content, "BOTTOMRIGHT", 0, 0)
  end
end

local function buildPopover()
  catcher = CreateFrame("Button", nil, main().content)
  catcher:SetFrameLevel(main().content:GetFrameLevel() + POPOVER_LEVEL - 1)
  catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  catcher:SetScript("OnClick", function() ConsumableRow.Close() end)
  catcher:Hide()
  local p = CreateFrame("Frame", nil, main().content)
  p:SetSize(POP_W, POP_H)
  p:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -4)
  p:SetFrameLevel(main().content:GetFrameLevel() + POPOVER_LEVEL)
  Theme.Raised(p) -- floats above the window: a raised tile, not a set-in panel
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

  local function button(label, y, onClick, variant)
    local b = Theme.NewButton(p, label, POP_W - 20, 24, variant)
    b:SetPoint("TOP", p, "TOP", 0, y)
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
  p.use = button("Use", -60, onUse, "primary")
  p.sell = button("Sell", -90, onSell)
  p:SetScript("OnHide", function() GameTooltip:Hide() end)
  p:Hide()
  popover = p
end

---------------------------------------------------------------------------
-- Use flow

-- Lock, apply, animate, re-render, unlock, persist. Returns true if it ran.
-- Everything after the lock is protected: an error unlocks the board and is
-- forwarded to the error handler, so the hand can never stay locked.
function ConsumableRow.Use(slot)
  local m = main()
  local run = m and m.run
  local HandView = ns.UI.HandView
  if not run or not slot or busy() then return false end
  local idx = selection(run)
  if not ns.Consumables.canUse(run, slot, idx) then return false end
  local token = HandView.Lock()
  if not token then return false end
  local function finish()
    HandView.Unlock(token)  -- relayout (deals added cards, applies hand size), unlock
    if m.run == run then m.Render(run, true) end
    persist()
  end
  local ok, result = pcall(function()
    local outcome = ns.Consumables.use(run, slot, idx)
    if not outcome then error("consumable use refused", 0) end
    outcome.slot = slot
    outcome.anchor = row.slots[slot]
    ConsumableRow.Close()
    clearSelection(run)       -- order and length may change; the cards animate unselected
    persist()
    if run.phase == "lost" then
      -- Nothing left to play: the effects play first, the finish shows the defeat.
      ns.UI.Sidebar.Update(run, 0, 0)
      ns.UI.ConsumableRow.Update(run)
      ns.UI.TrinketRow.Update(run)
    else
      m.Render(run, true)     -- gold, trinkets, slots and screens update now; effects play over them
    end
    ns.UI.Outcome.Play(outcome, finish)
  end)
  if not ok then
    ConsumableRow.Close()
    pcall(finish)
    geterrorhandler()(result)
    return false
  end
  return true
end

---------------------------------------------------------------------------

function ConsumableRow.Build(frame)
  row = frame
  frame.slots = {}
  for i = 1, MAX_SLOTS do makeSlot(i) end
  -- frame:IsMouseOver() rather than the global MouseIsOver, which the live client lacks.
  local function over(f) return f ~= nil and f:IsVisible() and f:IsMouseOver() end
  frame:SetScript("OnEvent", function(_, event)
    if event ~= "GLOBAL_MOUSE_DOWN" or not openSlot then return end
    local run = main() and main().run
    if over(popover) or over(row.slots[openSlot]) then return end
    if run and run.phase == "play" and over(main().handArea) then return end -- keep selecting cards
    if packHandOpen(run) and over(ns.UI.PackView.HandFrame()) then return end
    ConsumableRow.Close()
  end)
  frame:SetScript("OnHide", function()
    ConsumableRow.Close()
    GameTooltip:Hide()
  end)
  buildPopover()
end

function ConsumableRow.Update(run)
  if not row or not row.slots then return end
  local count = math.min(MAX_SLOTS, run and ns.Consumables.slots(run) or 0)
  local pitch = SLOT_W + SLOT_GAP
  -- The row takes only the width it needs; the trinket row gets the rest, so
  -- 8 trinkets and 5 consumables never overlap.
  local used = count > 0 and (count * SLOT_W + (count - 1) * SLOT_GAP) or 0
  row:SetWidth(math.max(used, 1))
  local m = main()
  if m.trinketRow and m.rowsWidth then m.trinketRow:SetWidth(m.rowsWidth - used - Theme.margin) end
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
