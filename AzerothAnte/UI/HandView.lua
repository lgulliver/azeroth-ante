local _, ns = ...

local Theme = ns.UI.Theme
local Tween = ns.UI.Tween
local CardWidget = ns.UI.CardWidget
local HandView = {}

local CARD_W, CARD_H = CardWidget.WIDTH, CardWidget.HEIGHT
local GAP = 6
local BASE_Y = 12            -- card bottom above the hand area bottom
local MOVE_TIME = 0.2        -- re-layout (sort, refill)
local DEAL_TIME, DEAL_STAGGER = 0.22, 0.04
local PLAY_TIME, PLAY_STAGGER, PLAY_GAP = 0.25, 0.03, 10
local DISCARD_TIME, DISCARD_SLIDE = 0.25, 160
local MAX_SELECT = 5
local SHAKE = { 4, -4, 4, -4, 4, 0 } -- six 0.025s legs = 0.15s
local DECK_W, DECK_H, DECK_INSET = 56, 78, 8

local widgetOf = {}   -- card table -> widget (hand cards only)
local list = {}       -- widgets parallel to run.hand
local held = {}       -- widgets mid play/discard flight (not in the hand)
local busy = false
local gen = 0         -- bumped when the run changes; stale callbacks check it
local hoveredButton

HandView.run = nil

-- Task 12 replaces this with the tally. Must call done() exactly once.
HandView.OnPlayed = function(result, playedWidgets, done) done() end

-- Task 13 sets ns.UI.OnRunChanged (persistence).
function HandView.AfterAction()
  if ns.UI.OnRunChanged then ns.UI.OnRunChanged() end
end

-- Busy while a hand resolves or lifecycle events play (the table is locked for both).
function HandView.IsBusy()
  local LC = ns.UI.Lifecycle
  return busy or (LC ~= nil and LC.IsBusy())
end

-- Locks input for an action that animates outside the hand (a consumable use).
-- Returns a token for Unlock, or nil when already busy.
function HandView.Lock()
  if busy or not HandView.run then return nil end
  busy = true
  HandView.RefreshButtons()
  return gen
end

-- Ends a Lock: clears the selection (the hand's order or length may have
-- changed), re-lays the hand (new cards deal in, hand size changes apply) and
-- re-enables input. A stale token (the run changed meanwhile) does nothing.
function HandView.Unlock(token)
  local run = HandView.run
  if token ~= gen or not busy or not run then return end
  busy = false
  for _, w in ipairs(list) do
    if w.selected then w:SetSelected(false) end
  end
  if run.phase == "play" then
    HandView.Update(run, true)
  else
    HandView.RefreshButtons()
  end
  HandView.AfterAction()
end

-- The hand widget showing the card with this id (also valid for a card that
-- was just destroyed, until the next layout), or nil.
function HandView.WidgetForCard(id)
  for card, w in pairs(widgetOf) do
    if card.id == id and not w.released then return w end
  end
end

-- The hand widgets in run.hand order. During a play they are the held cards
-- (the played ones are detached and the refill has not been laid out yet), so
-- this is the order of ctx.held.
function HandView.HeldWidgets()
  local out = {}
  for i, w in ipairs(list) do out[i] = w end
  return out
end

local function main()
  return ns.UI.Main
end

local function handArea()
  return main() and main().handArea
end

-- Hand-area-relative points (design units, bottom-left origin).
local function deckOrigin()
  local hand, play = main().handArea, main().playArea
  local cx = hand:GetWidth() - DECK_INSET - DECK_W / 2
  local cy = hand:GetHeight() + Theme.margin + play:GetHeight() / 2
  return cx - CARD_W / 2, cy - CARD_H / 2
end

local function playSlot(k, n)
  local hand, play = main().handArea, main().playArea
  local step = CARD_W + PLAY_GAP
  local total = n * CARD_W + (n - 1) * PLAY_GAP
  local x = (hand:GetWidth() - total) / 2 + (k - 1) * step
  local y = hand:GetHeight() + Theme.margin + (play:GetHeight() - CARD_H) / 2
  return x, y
end

-- Row layout, centred; compresses the spacing (overlap) instead of overflowing.
local function rowX(i, n, areaW)
  local step = CARD_W + GAP
  if n > 1 and n * CARD_W + (n - 1) * GAP > areaW then step = (areaW - CARD_W) / (n - 1) end
  local total = CARD_W + (n - 1) * step
  return (areaW - total) / 2 + (i - 1) * step
end

local function place(w, x, y)
  w.lx, w.ly = x, y
  w:ClearAllPoints()
  w:SetPoint("BOTTOMLEFT", handArea(), "BOTTOMLEFT", x, y)
end

local function moveTo(w, x, y, duration)
  w.lx, w.ly = x, y
  w:SetFaceUp(true)
  Tween.To(w, { x = x, y = y, alpha = 1 }, duration) -- cancels a deal; its onCancel lands the card
end

---------------------------------------------------------------------------
-- Buttons

local function showButtonTooltip(b)
  if not b:IsVisible() then
    if hoveredButton == b then hoveredButton = nil end
    return
  end
  if b:IsEnabled() or not b.reason then
    if GameTooltip:GetOwner() == b then GameTooltip:Hide() end
    return
  end
  GameTooltip:SetOwner(b, "ANCHOR_TOP")
  GameTooltip:SetText(b.reason, 1, 1, 1, 1, true)
  GameTooltip:Show()
end

local function setButton(b, ok, reason)
  if ok then b:Enable() else b:Disable() end
  b.reason = (not ok) and reason or nil
  if hoveredButton == b then showButtonTooltip(b) end
end

function HandView.Selected()
  local idx = {}
  for i, w in ipairs(list) do
    if w.selected then idx[#idx + 1] = i end
  end
  return idx
end

-- Shows the selected cards' hand name and its base chips x mult at the current
-- level in the sidebar (0 x 0, no name, with nothing selected).
local function updatePreview()
  if busy then return end
  local run = HandView.run
  if not run or run.phase ~= "play" then return end
  local sel = HandView.Selected()
  if #sel < 1 or #sel > MAX_SELECT then
    ns.UI.Sidebar.SetChipsMult(0, 0, "")
    return
  end
  local cards = {}
  for k, i in ipairs(sel) do cards[k] = run.hand[i] end
  local handId = ns.HandEval.evaluate(cards, ns.TrinketRules.set(run.trinkets))
  local level = run.handLevels[handId] or 1
  local chips, mult = ns.Hands.base(handId, level)
  ns.UI.Sidebar.SetChipsMult(chips, mult, ns.Hands.def[handId].name .. " Lv " .. level)
end

function HandView.RefreshButtons()
  local m = main()
  local buttons = m and m.buttons
  if not buttons or not buttons.play then return end
  local run = HandView.run
  local sel = HandView.Selected()
  local playOk, playWhy, discOk, discWhy
  local busy = HandView.IsBusy()
  if busy then
    playOk, playWhy = false, "Resolving the hand..."
    discOk, discWhy = false, playWhy
  elseif not run then
    playOk, playWhy = false, "No active run."
    discOk, discWhy = false, playWhy
  else
    playOk, playWhy = ns.Run.canPlay(run, sel)
    discOk, discWhy = ns.Run.canDiscard(run, sel)
  end
  setButton(buttons.play, playOk, playWhy)
  setButton(buttons.discard, discOk, discWhy)
  local sortOk = (not busy) and run ~= nil and #list > 1
  local sortWhy = busy and "Resolving the hand..." or "Nothing to sort."
  setButton(buttons.sortRank, sortOk, sortWhy)
  setButton(buttons.sortSuit, sortOk, sortWhy)
  updatePreview()
  local row = ns.UI.ConsumableRow
  if row then row.Refresh() end
end

function HandView.ClearSelection()
  for _, w in ipairs(list) do
    if w.selected then w:SetSelected(false) end
  end
  HandView.RefreshButtons()
end

---------------------------------------------------------------------------
-- Layout

local function releaseHeld()
  for i = #held, 1, -1 do
    CardWidget.Release(held[i])
    held[i] = nil
  end
end

local function bossDebuff(run)
  local boss = run and run.bosses and ns.Run.activeBoss(run)
  return boss and boss.debuff
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

local function onCardClick(w)
  local run = HandView.run
  if busy or not run or run.phase ~= "play" then return end
  if w.selected then
    w:SetSelected(false)
  else
    if #HandView.Selected() >= MAX_SELECT then
      shake(w)
      return
    end
    w:SetSelected(true)
  end
  HandView.RefreshButtons()
end

-- Lays the hand out from run.hand. Existing cards tween to their slot; new
-- cards appear in place, or (animate) fly in from the deck, staggered.
function HandView.Update(run, animate)
  local area = handArea()
  if not area then return end
  if busy and run == HandView.run then return end -- the action's done() will call us
  if run ~= HandView.run then
    gen = gen + 1
    busy = false
    releaseHeld()
    HandView.run = run
  end

  if HandView.deck then HandView.deck:SetTexture(CardWidget.BackPath(run and run.deckId)) end
  local hand = run and run.hand or {}
  local inHand = {}
  for _, card in ipairs(hand) do inHand[card] = true end
  for card, w in pairs(widgetOf) do
    if not inHand[card] then
      CardWidget.Release(w)
      widgetOf[card] = nil
    end
  end

  list = {}
  local debuff = bossDebuff(run)
  local rules = ns.TrinketRules.set(run and run.trinkets)
  local n, areaW = #hand, area:GetWidth()
  local ox, oy = deckOrigin()
  local dealt = 0
  for i, card in ipairs(hand) do
    local w = widgetOf[card]
    local isNew = not w
    if isNew then
      w = CardWidget.Acquire(area)
      w:SetCard(card)
      w.onClick = onCardClick
      widgetOf[card] = w
    end
    list[i] = w
    w:SetDebuffed(debuff and debuff(card, rules))
    w:SetBaseLevel(area:GetFrameLevel() + 2 + i * 4)
    local x = rowX(i, n, areaW)
    if isNew and animate then
      place(w, ox, oy)
      w.lx, w.ly = x, BASE_Y
      w:SetAlpha(0)
      w:SetFaceUp(false)
      w:EnableMouse(false) -- not clickable until it has landed
      local function landed()
        if w.locked then return end
        w:SetFaceUp(true)
        w:EnableMouse(true)
      end
      Tween.To(w, { x = x, y = BASE_Y, alpha = 1 }, DEAL_TIME, landed, dealt * DEAL_STAGGER, landed)
      dealt = dealt + 1
    elseif isNew then
      place(w, x, BASE_Y)
    else
      w:SetCard(card) -- a scroll or pack may have changed its type
      moveTo(w, x, BASE_Y, MOVE_TIME)
    end
  end
  HandView.RefreshButtons()
  ns.UI.EditionFX.Wake() -- a re-shown window restarts the shimmer
end

---------------------------------------------------------------------------
-- Actions

-- Detaches the selected widgets from the hand and locks them for flight.
local function detach(sel)
  local out, gone = {}, {}
  for k, i in ipairs(sel) do
    local w = list[i]
    out[k], gone[w] = w, true
    widgetOf[w.card] = nil
    held[#held + 1] = w
    w:SetSelected(false) -- lowers the lift (and the highlight) before it locks
    w.locked, w.hover, w.topmost = true, false, true
    w:EnableMouse(false)
    w:SetFaceUp(true)
    w:SetAlpha(1)
    w:ApplyLevel()
  end
  local rest = {}
  for _, w in ipairs(list) do
    if not gone[w] then rest[#rest + 1] = w end
  end
  list = rest
  return out
end

-- Undoes detach() after a failed Run action: widgets return to the hand, selected.
local function restore(run, widgets)
  for _, w in ipairs(widgets) do
    widgetOf[w.card] = w
    for j = #held, 1, -1 do if held[j] == w then table.remove(held, j) end end
    w.locked, w.topmost = false, false
    w:EnableMouse(true)
    w:SetSelected(true)
    w:ApplyLevel()
  end
  busy = false
  HandView.Update(run, false)
end

local function afterAll(count, fn)
  local pending = count
  return function()
    pending = pending - 1
    if pending == 0 then fn() end
  end
end

local function closeRow()
  local row = ns.UI.ConsumableRow
  if row then row.Close() end
end

local function doPlay()
  local run = HandView.run
  if HandView.IsBusy() or not run then return end
  closeRow()
  local sel = HandView.Selected()
  if not ns.Run.canPlay(run, sel) then return end

  busy = true
  ns.UI.DeckView.Hide() -- it covers the play area the cards fly into
  local myGen = gen
  local widgets = detach(sel)
  local ok, result = pcall(ns.Run.play, run, sel)
  if not ok or not result then
    restore(run, widgets)
    if not ok then geterrorhandler()(result) end
    return
  end

  -- After the tally: hooks the hand fired (a save, a melt, a round-end message) play before the render.
  local function settled()
    if myGen ~= gen or not busy then return end
    releaseHeld()
    busy = false
    main().Render(run, true) -- after the tally and slide-away, before any refill deal
    if run.phase == "play" then
      HandView.Update(run, true)
    else
      HandView.RefreshButtons()
      -- Blue seals made Tomes at round end: they pop into their slots.
      local made = run.phase == "shop" and run.lastPayout and run.lastPayout.created
      if made then
        local items = {}
        for i = math.max(1, #run.consumables - made + 1), #run.consumables do
          items[#items + 1] = run.consumables[i]
        end
        ns.UI.Outcome.Play({ created = items })
      end
    end
    HandView.AfterAction()
  end
  local function done()
    if myGen ~= gen or not busy then return end
    ns.UI.Lifecycle.Drain(run, settled)
  end
  local called = false
  local function doneOnce()
    if called then return end
    called = true
    done()
  end

  local arrived = afterAll(#widgets, function()
    if myGen ~= gen then return end
    local ok, err = pcall(HandView.OnPlayed, result, widgets, doneOnce)
    if not ok then
      geterrorhandler()(err)
      doneOnce() -- a broken hook must not leave the board locked
    end
  end)
  for k, w in ipairs(widgets) do
    local x, y = playSlot(k, #widgets)
    w.lx, w.ly = x, y
    Tween.To(w.body, { x = 0, y = 0 }, 0.1)
    Tween.To(w, { x = x, y = y, alpha = 1 }, PLAY_TIME, arrived, (k - 1) * PLAY_STAGGER)
  end
  -- Show the pre-play score during the flight; the tally counts it up.
  ns.UI.Sidebar.Update(run, 0, 0)
  ns.UI.Sidebar.SetScore((run.score or 0) - (result.total or 0))
  HandView.RefreshButtons()
end

local function doDiscard()
  local run = HandView.run
  if HandView.IsBusy() or not run then return end
  closeRow()
  local sel = HandView.Selected()
  if not ns.Run.canDiscard(run, sel) then return end

  busy = true
  ns.UI.DeckView.Hide() -- it covers the play area the cards fly into
  local myGen = gen
  local widgets = detach(sel)
  local ok, outcome = pcall(ns.Run.discard, run, sel)
  if not ok or not outcome then
    restore(run, widgets)
    if not ok then geterrorhandler()(outcome) end
    return
  end

  -- onDiscard hooks may have melted or made trinkets: the events play while the cards fly, and the
  -- row re-renders once both are done.
  local events = run.lifecycleEvents and #run.lifecycleEvents > 0
  local function settled()
    if myGen ~= gen then return end
    releaseHeld()
    busy = false
    -- An emptied deck loses the blind: the screen waits until the cards have left.
    if run.phase ~= "play" or events then main().Render(run, true) end
    HandView.Update(run, true)
    HandView.AfterAction()
  end
  local barrier = afterAll(2, settled)
  local arrived = afterAll(#widgets, function()
    if myGen ~= gen then return end
    barrier()
  end)
  ns.UI.Lifecycle.Drain(run, function()
    if myGen == gen then barrier() end
  end)
  for k, w in ipairs(widgets) do
    Tween.To(w.body, { x = 0, y = 0 }, 0.1)
    Tween.To(w, { x = w.lx + DISCARD_SLIDE, y = w.ly, alpha = 0 }, DISCARD_TIME, arrived,
      (k - 1) * 0.02)
  end
  if run.phase == "play" then
    if events then ns.UI.Sidebar.Update(run, 0, 0) else main().Render(run, true) end
    -- Purple seals made Scrolls: they pop into their slots.
    if #outcome.created > 0 then ns.UI.Outcome.Play({ created = outcome.created }) end
  else
    ns.UI.Sidebar.Update(run, 0, 0)
  end
  HandView.RefreshButtons()
end

local function doSort(mode)
  local run = HandView.run
  if HandView.IsBusy() or not run then return end
  closeRow()
  ns.Run.sortHand(run, mode)
  HandView.Update(run, false)
  HandView.AfterAction()
end

---------------------------------------------------------------------------

-- Wires the buttons and creates the deck image. Called once from Main.Create.
-- The deck pile belongs to the play screen; the other screens hide it (it would
-- show through their panels as a stray card).
function HandView.SetDeckShown(shown)
  if HandView.deck then HandView.deck:SetShown(shown and true or false) end
end

function HandView.Build(m)
  local deck = m.playArea:CreateTexture(nil, "ARTWORK")
  deck:SetSize(DECK_W, DECK_H)
  deck:SetPoint("RIGHT", m.playArea, "RIGHT", -DECK_INSET, 0)
  deck:SetTexture(CardWidget.BackPath())
  deck:SetTexCoord(0, 1, 0, Theme.cardV)
  HandView.deck = deck

  local buttons = m.buttons
  local actions = {
    play = doPlay,
    discard = doDiscard,
    sortRank = function() doSort("rank") end,
    sortSuit = function() doSort("suit") end,
  }
  for name, action in pairs(actions) do
    local b = buttons[name]
    b:SetMotionScriptsWhileDisabled(true) -- tooltip must work while disabled
    b:SetScript("OnClick", action)
    b:SetScript("OnEnter", function(self)
      hoveredButton = self
      showButtonTooltip(self)
    end)
    b:SetScript("OnLeave", function(self)
      if hoveredButton == self then hoveredButton = nil end
      GameTooltip:Hide()
    end)
  end
  HandView.RefreshButtons()
end

ns.UI.HandView = HandView
