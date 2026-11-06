local _, ns = ...

local Theme = ns.UI.Theme
local Tween = ns.UI.Tween
local CardWidget = ns.UI.CardWidget
local Screens = ns.UI.Screens
local Outcome = ns.UI.Outcome
local W = Screens.Widgets
local PackView = {}

local FADE = 0.15
local PANEL_LEVEL = 650        -- over the shop panel (600), under the consumable popover (700)
local SELL_GAP = 22            -- same top inset as the screen panels
local CHOICE_W, CHOICE_H = 72, 101        -- 5:7
local CHOICE_STEP = 92
local ARC = 2                  -- the fan: outer choices sit lower
local LIFT_SELECTED, LIFT_HOVER, LIFT_TIME = 14, 6, 0.08
local TOP_HAND, TOP_NOHAND = -46, -70      -- choice row top, with and without a drawn hand
local DETAIL_HAND, DETAIL_NOHAND = -156, -196
local HAND_H, BASE_Y, GAP = 140, 6, 6
local MAX_SELECT = 5
local DEAL_TIME, DEAL_STAGGER, MOVE_TIME = 0.22, 0.04, 0.2
local PICK_TIME, PICK_SCALE = 0.25, 1.25
local WATCHDOG = 3
local ERROR_TIME = 2
local SHAKE = { 4, -4, 4, -4, 4, 0 }
local RED = { 1, 0.25, 0.2 }
local RANK_NAMES = { [11] = "Jack", [12] = "Queen", [13] = "King", [14] = "Ace" }
local GOLD_HEX, GREEN_HEX, RED_HEX = "|cffffd100", "|cff66e066", "|cffff6655"
local PICK_ERRORS = {
  slots = "Trinket slots full - sell one first", gone = "Already taken", pack = "Finish the open pack first",
}

local frame                          -- the overlay (built on first use)
local shown                          -- the pack table currently displayed
local entries = {}                   -- choice index -> { item, frame, face?, widget? }
local buttons = {}                   -- choice index -> custom choice button (reused)
local handOf = {}                    -- card table -> widget (the pack hand)
local handList = {}                  -- widgets parallel to pack.hand
local selectedChoice, hoveredChoice
local busy = false
local errorToken = 0

local function main()
  return ns.UI.Main
end

local function persist()
  if ns.UI.OnRunChanged then ns.UI.OnRunChanged() end
end

local function currentPack()
  local run = main() and main().run
  return run and run.phase == "shop" and run.shop and run.shop.openPack or nil
end

local function handBusy()
  local HandView = ns.UI.HandView
  return HandView and HandView.IsBusy() or false
end

local function once(fn)
  local called = false
  return function()
    if called then return end
    called = true
    fn()
  end
end

local function cardName(card)
  if ns.Cards.isStone(card) then return "Stone card" end
  return (RANK_NAMES[card.rank] or tostring(card.rank)) .. " of " .. ns.Cards.SUIT_NAMES[card.suit]
end

local function liveCount(pack)
  local n = 0
  for c = 1, #pack.choices do
    if pack.choices[c] then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------------------
-- Selection

function PackView.Selected()
  local idx = {}
  for i, w in ipairs(handList) do
    if w.selected then idx[#idx + 1] = i end
  end
  return idx
end

local refreshState

function PackView.ClearSelection()
  for _, w in ipairs(handList) do
    if w.selected then w:SetSelected(false) end
  end
  if refreshState then refreshState() end
end

function PackView.IsBusy()
  return busy
end

function PackView.IsOpen()
  return shown ~= nil
end

-- The strip holding the pack hand (clicks there must not close the consumable popover).
function PackView.HandFrame()
  return shown and frame and frame.hand or nil
end

-- The pack hand widget showing this card id (valid until the next layout, even
-- for a card just destroyed), or nil. Always nil when the overlay is not shown,
-- so the play hand's widgets resolve normally.
function PackView.WidgetForCard(id)
  if not shown then return nil end
  for card, w in pairs(handOf) do
    if card.id == id and not w.released then return w end
  end
end

Outcome.AddResolver(function(id)
  return PackView.WidgetForCard(id)
end)

---------------------------------------------------------------------------
-- What a pick would do

local function slotsFull(run, item)
  return #run.trinkets >= ns.Run.trinketSlots(run) + (item.ed == "NEGATIVE" and 1 or 0)
end

-- ok, reason for picking the selected choice right now.
local function evaluate(run, pack)
  if busy or handBusy() then return false, "Resolving..." end
  local item = selectedChoice and pack.choices[selectedChoice]
  if not item then return false, "Select a choice first" end
  if pack.type == "BUFFOON" then
    if slotsFull(run, item) then return false, PICK_ERRORS.slots end
    return true
  end
  if pack.type == "STANDARD" then return true end
  local def = ns.Consumables.def(item)
  local cards = {}
  if def and def.select then
    for _, i in ipairs(PackView.Selected()) do cards[#cards + 1] = pack.hand[i] end
  end
  return ns.Consumables.canApply(run, item, cards)
end

local function selectedNames(pack)
  local names = {}
  for _, i in ipairs(PackView.Selected()) do names[#names + 1] = cardName(pack.hand[i]) end
  return names
end

-- title, body for the choice at index c.
local function describe(run, pack, c)
  local item = pack.choices[c]
  if pack.type == "STANDARD" then
    local lines = { "Added to your deck." }
    for _, def in ipairs({ ns.CardTypes.enh[item.enh] or false, ns.CardTypes.ed[item.ed] or false,
      ns.CardTypes.seal[item.seal] or false }) do
      if def then lines[#lines + 1] = GOLD_HEX .. def.name .. ":|r " .. def.desc end
    end
    return cardName(item), table.concat(lines, "\n")
  end
  local info = Screens.ItemInfo(item)
  local lines = { info.desc }
  if info.level then lines[#lines + 1] = GOLD_HEX .. info.level .. "|r" end
  if info.edName then lines[#lines + 1] = GOLD_HEX .. info.edName .. ": " .. info.edDesc .. "|r" end
  local def = info.def
  if def and def.select then
    local sel = def.select
    local need = sel.min == sel.max and tostring(sel.min) or (sel.min .. " to " .. sel.max)
    local names = selectedNames(pack)
    lines[#lines + 1] = "Selected cards (need " .. need .. "): "
      .. (#names > 0 and table.concat(names, ", ") or "none")
  end
  return info.name .. "  (" .. info.sub .. ")", table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Buttons

local function setButton(b, ok, reason)
  if ok then b:Enable() else b:Disable() end
  b.reason = (not ok) and reason or nil
  if GameTooltip:GetOwner() == b then
    if ok then
      GameTooltip:Hide()
    else
      GameTooltip:SetOwner(b, "ANCHOR_TOP")
      GameTooltip:SetText(reason or "", 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end
end

local function showError(text)
  errorToken = errorToken + 1
  local mine = errorToken
  frame.err:SetText(text)
  frame.err:Show()
  C_Timer.After(ERROR_TIME, function()
    if errorToken == mine and frame then frame.err:Hide() end
  end)
end

refreshState = function()
  if not frame or not shown then return end
  local run = main().run
  local pack = currentPack()
  if not run or not pack then return end
  local live = liveCount(pack)
  frame.picksLeft:SetText("Picks left: " .. pack.picksLeft)

  local shownChoice = hoveredChoice or selectedChoice
  if shownChoice and pack.choices[shownChoice] then
    local title, body = describe(run, pack, shownChoice)
    frame.detailTitle:SetText(title)
    frame.detailBody:SetText(body)
  elseif live == 0 then
    frame.detailTitle:SetText("")
    frame.detailBody:SetText("")
  else
    frame.detailTitle:SetText("Pick a choice")
    frame.detailBody:SetText("Hover a choice to read it, click it to select it, then press Pick.")
  end

  local ok, reason = evaluate(run, pack)
  local showStatus = live > 0 and selectedChoice ~= nil and (not hoveredChoice or hoveredChoice == selectedChoice)
  if showStatus then
    frame.status:SetText(ok and (GREEN_HEX .. "Ready: press Pick|r") or (RED_HEX .. reason .. "|r"))
  else
    frame.status:SetText("")
  end

  frame.empty:SetShown(live == 0)
  frame.pick:SetShown(live > 0)
  frame.skip:SetSize(live == 0 and 200 or 120, live == 0 and 34 or 28)
  frame.skip:ClearAllPoints()
  if live == 0 then
    frame.skip:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
  else
    frame.skip:SetPoint("BOTTOM", frame, "BOTTOM", 70, 14)
  end
  frame.skip:SetText((live > 0 and pack.picksLeft > 0) and ("Skip (" .. pack.picksLeft .. " left)") or "Skip")
  setButton(frame.pick, ok, reason)
  setButton(frame.skip, not busy and not handBusy(), "Resolving...")
  frame.handNote:SetShown(pack.hand ~= nil and #pack.hand == 0)
  local row = ns.UI.ConsumableRow
  if row then row.Refresh() end
end

---------------------------------------------------------------------------
-- Choices

local function choiceTop(pack)
  return pack.hand and TOP_HAND or TOP_NOHAND
end

-- Offset of the k-th of n live choices: a gentle fan, centred.
local function slotPos(k, n, pack)
  local t = k - (n + 1) / 2
  return t * CHOICE_STEP, choiceTop(pack) - ARC * t * t
end

local function setChoiceSelected(entry, on)
  entry.selected = on
  if entry.widget then
    entry.widget:SetSelected(on)
  else
    Screens.SetFaceSelected(entry.face, on)
    Tween.To(entry.frame.body, { x = 0, y = on and LIFT_SELECTED or (entry.hover and LIFT_HOVER or 0) }, LIFT_TIME)
  end
end

local function setHover(c, on)
  local pack = currentPack()
  if on then
    hoveredChoice = c
  elseif hoveredChoice == c then
    hoveredChoice = nil
  end
  local entry = entries[c]
  if entry then
    entry.hover = on
    if not entry.widget and not entry.selected then
      Tween.To(entry.frame.body, { x = 0, y = on and LIFT_HOVER or 0 }, LIFT_TIME)
    end
  end
  if pack then refreshState() end
end

local function onChoiceClick(c)
  if busy or handBusy() then return end
  local pack = currentPack()
  if not pack or not pack.choices[c] or not entries[c] then return end
  local prev = selectedChoice
  if prev and entries[prev] then setChoiceSelected(entries[prev], false) end
  if prev == c then
    selectedChoice = nil
  else
    selectedChoice = c
    setChoiceSelected(entries[c], true)
  end
  refreshState()
end

local function makeButton(c)
  local b = CreateFrame("Button", nil, frame)
  b:SetSize(CHOICE_W, CHOICE_H)
  b:RegisterForClicks("LeftButtonUp")
  b:SetHitRectInsets(0, 0, -LIFT_SELECTED, 0) -- the lifted card stays clickable
  b.body = CreateFrame("Frame", nil, b)
  b.body:SetSize(CHOICE_W, CHOICE_H)
  b.body:SetPoint("BOTTOM", b, "BOTTOM", 0, 0)
  b.face = Screens.NewFace(b.body, CHOICE_W, CHOICE_H, true)
  b.face:SetPoint("CENTER", b.body, "CENTER", 0, 0)
  b:SetScript("OnClick", function() onChoiceClick(c) end)
  b:SetScript("OnEnter", function() setHover(c, true) end)
  b:SetScript("OnLeave", function() setHover(c, false) end)
  buttons[c] = b
  return b
end

-- A Standard choice is a real card, so its enhancement, seal and edition look
-- exactly as they will in the deck. Its tooltip stays the card's own.
local function hookHover(w, c)
  if not w.pvWrapped then
    local enter, leave = w:GetScript("OnEnter"), w:GetScript("OnLeave")
    w:SetScript("OnEnter", function(self)
      if enter then enter(self) end
      if self.pvHover then self.pvHover(true) end
    end)
    w:SetScript("OnLeave", function(self)
      if leave then leave(self) end
      if self.pvHover then self.pvHover(false) end
    end)
    w.pvWrapped = true
  end
  w.pvHover = function(on) setHover(c, on) end
end

local function releaseEntry(c)
  local entry = entries[c]
  if not entry then return end
  entries[c] = nil
  Tween.Cancel(entry.face)
  if entry.widget then
    entry.widget.pvHover = nil
    CardWidget.Release(entry.widget)
  else
    Tween.Cancel(entry.frame)
    Tween.Cancel(entry.frame.body)
    ns.UI.EditionFX.Detach(entry.face.iconBox)
    entry.face:SetScale(1)
    entry.face:SetAlpha(1)
    entry.frame:SetAlpha(1)
    entry.frame:Hide()
  end
end

local function buildEntry(c, item, pack)
  local entry = { item = item }
  if pack.type == "STANDARD" then
    local w = CardWidget.Acquire(frame)
    w:SetCard(item)
    w.onClick = function() onChoiceClick(c) end
    w:SetBaseLevel(frame:GetFrameLevel() + 4)
    hookHover(w, c)
    entry.frame, entry.widget, entry.face = w, w, w.face
    Tween.Cancel(w.face)
    w.face:SetScale(1)
    w.face:SetAlpha(1)
  else
    local b = buttons[c] or makeButton(c)
    b:SetFrameLevel(frame:GetFrameLevel() + 3)
    b.body:SetFrameLevel(b:GetFrameLevel() + 1)
    b.body:ClearAllPoints()
    b.body:SetPoint("BOTTOM", b, "BOTTOM", 0, 0)
    b.face:SetFrameLevel(b.body:GetFrameLevel() + 1)
    Tween.Cancel(b.face)
    b.face:SetScale(1)
    b.face:SetAlpha(1)
    Screens.SkinFace(b.face, Screens.ItemInfo(item))
    b:Show()
    entry.frame, entry.face = b, b.face
  end
  entries[c] = entry
  return entry
end

local function layoutChoices(pack, fresh)
  local live, n = {}, 0
  for c = 1, #pack.choices do
    local item = pack.choices[c]
    local entry = entries[c]
    if entry and entry.item ~= item then
      releaseEntry(c)
      entry = nil
    end
    if item then
      n = n + 1
      live[n] = c
    end
  end
  local dealt = 0
  for k, c in ipairs(live) do
    local entry = entries[c]
    local isNew = not entry
    if isNew then entry = buildEntry(c, pack.choices[c], pack) end
    local x, y = slotPos(k, n, pack)
    local f = entry.frame
    if isNew then
      f:ClearAllPoints()
      f:SetPoint("TOP", frame, "TOP", 0, y + 24)
      f:SetAlpha(0)
      Tween.To(f, { x = x, y = y, alpha = 1 }, DEAL_TIME, nil, dealt * DEAL_STAGGER)
      dealt = dealt + 1
    else
      Tween.To(f, { x = x, y = y, alpha = 1 }, MOVE_TIME)
    end
  end
  for c = 1, #pack.choices do
    if not pack.choices[c] then releaseEntry(c) end
  end
  for c in pairs(entries) do
    if c > #pack.choices then releaseEntry(c) end
  end
end

---------------------------------------------------------------------------
-- The drawn hand (Arcana and Spectral)

local function rowX(i, n, areaW)
  local step = CardWidget.WIDTH + GAP
  if n > 1 and n * CardWidget.WIDTH + (n - 1) * GAP > areaW then
    step = (areaW - CardWidget.WIDTH) / (n - 1)
  end
  local total = CardWidget.WIDTH + (n - 1) * step
  return (areaW - total) / 2 + (i - 1) * step
end

local function shake(w)
  local i = 0
  local function leg()
    i = i + 1
    if i > #SHAKE then return end
    Tween.To(w.body, { x = SHAKE[i], y = w.selected and CardWidget.LIFT_SELECTED or (w.hover and 8 or 0) },
      0.025, leg)
  end
  leg()
end

local function onHandClick(w)
  if busy or handBusy() or not currentPack() then return end
  if w.selected then
    w:SetSelected(false)
  else
    if #PackView.Selected() >= MAX_SELECT then
      shake(w)
      return
    end
    w:SetSelected(true)
  end
  refreshState()
end

local function releaseHand()
  for card, w in pairs(handOf) do
    CardWidget.Release(w)
    handOf[card] = nil
  end
  handList = {}
end

-- Lays the hand out from pack.hand. Existing cards tween to their slot; new
-- cards (the first deal, or cards a Scroll added) fade up into place.
local function layoutHand(pack, fresh)
  local hand = pack.hand or {}
  local inHand = {}
  for _, card in ipairs(hand) do inHand[card] = true end
  for card, w in pairs(handOf) do
    if not inHand[card] then
      CardWidget.Release(w)
      handOf[card] = nil
    end
  end
  handList = {}
  local area = frame.hand
  local n, areaW = #hand, area:GetWidth()
  local dealt = 0
  for i, card in ipairs(hand) do
    local w = handOf[card]
    local isNew = not w
    if isNew then
      w = CardWidget.Acquire(area)
      w:SetCard(card)
      w.onClick = onHandClick
      handOf[card] = w
    end
    handList[i] = w
    w:SetBaseLevel(area:GetFrameLevel() + 2 + i * 4)
    local x = rowX(i, n, areaW)
    if isNew then
      w:ClearAllPoints()
      w:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", areaW / 2 - CardWidget.WIDTH / 2, BASE_Y - 20)
      w:SetAlpha(0)
      w:SetFaceUp(true)
      Tween.To(w, { x = x, y = BASE_Y, alpha = 1 }, DEAL_TIME, nil, 0.1 + dealt * DEAL_STAGGER)
      dealt = dealt + 1
    else
      w:SetCard(card)
      Tween.To(w, { x = x, y = BASE_Y, alpha = 1 }, MOVE_TIME)
    end
  end
  ns.UI.EditionFX.Wake()
end

---------------------------------------------------------------------------
-- Pick and skip

local function doPick()
  local run, pack = main().run, currentPack()
  if not run or not pack or busy or handBusy() then return end
  local ok, reason = evaluate(run, pack)
  if not ok then
    showError(reason)
    return
  end
  local c = selectedChoice
  local item = pack.choices[c]
  local entry = entries[c]
  local idx = PackView.Selected()
  busy = true
  local okCall, success, why, outcome = pcall(ns.Packs.pick, run, c, idx)
  if not okCall then
    busy = false
    refreshState()
    geterrorhandler()(success)
    return
  end
  if not success then
    busy = false
    showError(PICK_ERRORS[why] or why or "Can't pick that")
    refreshState()
    return
  end
  persist()
  selectedChoice, hoveredChoice = nil, nil
  for _, w in ipairs(handList) do
    if w.selected then w:SetSelected(false) end
  end
  main().Render(run, true) -- gold, trinkets and consumable slots update; effects play over them

  local function finish()
    busy = false
    GameTooltip:Hide()
    -- The overlay stayed up for the animations (Hide waits while busy). Now it
    -- compacts the remaining choices, or closes if the pack is done, then the screens render.
    PackView.Show(main().run)
    if main().run == run then
      main().Render(run, true)
      refreshState()
    end
  end
  finish = once(finish)
  C_Timer.After(WATCHDOG, finish)

  if pack.type == "BUFFOON" then
    ns.UI.TrinketRow.Pulse(#run.trinkets)
  elseif pack.type == "STANDARD" then
    Outcome.Float(entry.frame, "Added to deck", Theme.gold)
  end
  if outcome then outcome.anchor = entry.frame end

  local pending = 2
  local function part()
    pending = pending - 1
    if pending <= 0 then finish() end
  end
  local partChoice, partOutcome = once(part), once(part)
  Tween.To(entry.face, { scale = PICK_SCALE, alpha = 0 }, PICK_TIME, partChoice, 0, partChoice)
  local playOk, err = pcall(Outcome.Play, outcome or {}, partOutcome)
  if not playOk then
    partOutcome()
    geterrorhandler()(err)
  end
  refreshState()
end

local function doSkip()
  local run = main().run
  if not run or not currentPack() or busy or handBusy() then return end
  ns.Packs.skip(run)
  persist()
  main().Render(run, true) -- the shop returns; this closes the overlay
end

---------------------------------------------------------------------------
-- Build and show

local function build()
  local m = main()
  local p = CreateFrame("Frame", nil, m.content)
  p:SetPoint("TOPLEFT", m.playArea, "TOPLEFT", 0, -SELL_GAP)
  p:SetPoint("BOTTOMRIGHT", m.buttons, "BOTTOMRIGHT", 0, 0)
  p:SetFrameLevel(m.content:GetFrameLevel() + PANEL_LEVEL)
  Theme.Inset(p) -- its fill is fully opaque: nothing from the shop shows through
  p:EnableMouse(true) -- swallows clicks meant for the screen under it
  p.packChoices = entries
  frame = p

  p.title = W.text(p, Theme.fonts.title, "TOP", 0, -10, 400, "CENTER")
  Theme.Value(p.title, true)
  p.picksLeft = W.text(p, Theme.fonts.text, "TOPRIGHT", -16, -14, 120, "RIGHT")
  Theme.setColor(p.picksLeft, Theme.parchment)

  p.detailTitle = W.text(p, Theme.fonts.text, "TOP", 0, DETAIL_HAND, 540, "CENTER")
  Theme.setColor(p.detailTitle, Theme.gold)
  p.detailBody = W.text(p, Theme.fonts.small, "TOP", 0, DETAIL_HAND - 18, 540, "CENTER")
  p.detailBody:SetHeight(52)
  p.detailBody:SetJustifyV("TOP")
  Theme.setColor(p.detailBody, Theme.parchment)
  p.status = W.text(p, Theme.fonts.small, "TOP", 0, DETAIL_HAND - 72, 540, "CENTER")

  p.empty = W.text(p, Theme.fonts.big, "CENTER", 0, 20, 540, "CENTER")
  p.empty:SetText("Nothing to choose")
  Theme.setColor(p.empty, Theme.parchment)
  p.empty:Hide()
  p.handNote = W.text(p, Theme.fonts.small, "BOTTOM", 0, 90, 400, "CENTER")
  p.handNote:SetText("No cards left in your deck to aim at")
  Theme.setColor(p.handNote, Theme.parchment)
  p.handNote:Hide()

  p.hand = CreateFrame("Frame", nil, p)
  p.hand:SetSize(m.rowsWidth or 618, HAND_H)
  p.hand:SetPoint("BOTTOM", p, "BOTTOM", 0, 50)

  p.err = W.text(p, Theme.fonts.text, "BOTTOM", 0, 48, 540, "CENTER")
  Theme.setColor(p.err, RED)
  p.err:Hide()

  p.pick = W.button(p, "Pick", 120, 28, doPick, "primary")
  p.pick:SetPoint("BOTTOM", p, "BOTTOM", -68, 16)
  W.reasonTip(p.pick)
  p.skip = W.button(p, "Skip", 120, 28, doSkip)
  p.skip:SetPoint("BOTTOM", p, "BOTTOM", 68, 16)
  W.reasonTip(p.skip)
  p:Hide()
  return p
end

local function resetAll()
  for c in pairs(entries) do releaseEntry(c) end
  releaseHand()
  selectedChoice, hoveredChoice = nil, nil
  errorToken = errorToken + 1
  if frame then frame.err:Hide() end
  GameTooltip:Hide()
end

function PackView.Hide()
  if not frame then return end
  if busy and shown then return end -- a pick is animating: its finish closes the overlay
  if shown then
    Tween.Cancel(frame)
    resetAll()
    shown = nil
  end
  frame:SetAlpha(1)
  frame:Hide()
end

-- Shows the overlay for run.shop.openPack, or hides it when there is none. Cheap
-- and idempotent. While an animation plays the layout waits: its finish re-lays out.
function PackView.Show(run)
  local pack = run and run.phase == "shop" and run.shop and run.shop.openPack
  if not pack then return PackView.Hide() end
  if not frame then build() end
  if shown == pack and (busy or handBusy()) then
    refreshState()
    return
  end
  local fresh = shown ~= pack
  if fresh then
    resetAll()
    shown = pack
    frame.title:SetText(Screens.PackInfo(pack).label)
    local top = pack.hand and DETAIL_HAND or DETAIL_NOHAND
    frame.detailTitle:SetPoint("TOP", frame, "TOP", 0, top)
    frame.detailBody:SetPoint("TOP", frame, "TOP", 0, top - 18)
    frame.status:SetPoint("TOP", frame, "TOP", 0, top - 72)
  end
  layoutChoices(pack, fresh)
  layoutHand(pack, fresh)
  if fresh then
    frame:SetAlpha(0)
    frame:Show()
    Tween.To(frame, { alpha = 1 }, FADE)
  elseif not frame:IsShown() then
    frame:SetAlpha(1)
    frame:Show()
  end
  refreshState()
end

ns.UI.PackView = PackView
