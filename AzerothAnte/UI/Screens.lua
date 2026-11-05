local _, ns = ...

local Theme = ns.UI.Theme
local Tween = ns.UI.Tween
local Screens = {}

local FADE = 0.15
local ERROR_TIME = 2
local SELL_GAP = 22            -- room under the trinket row for the sell buttons
local PANEL_LEVEL, PAUSE_LEVEL = 600, 900
local RED = { 1, 0.25, 0.2 }
local GREY = { 0.6, 0.6, 0.6 }
local BLIND_NAMES = { "Small Blind", "Big Blind" }
local BUY_ERRORS = { gold = "Not enough gold", slots = "Trinket slots full", gone = "Sold out" }
local TOME_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local FLAT = "Interface\\Buttons\\WHITE8x8"

local panels = {}              -- name -> panel frame
local current                  -- name of the visible screen ("play" = none)
local pausedFrame
local errorToken = 0
local lastSell = 0
local SELL_COOLDOWN = 0.3

local function main()
  return ns.UI.Main
end

local function blocked()
  local HandView, Tally = ns.UI.HandView, ns.UI.Tally
  return (HandView and HandView.IsBusy()) or (Tally and Tally.IsBusy()) or false
end

local function persist()
  if ns.UI.OnRunChanged then ns.UI.OnRunChanged() end
end

-- Saves the live run after every hand and screen action (guarded: the saved
-- variables table is created by a later task).
ns.UI.OnRunChanged = function()
  local m = main()
  if AzerothAnteDB and m and m.run then ns.Save.store(AzerothAnteDB, m.run) end
end

---------------------------------------------------------------------------
-- Widget helpers

local function text(parent, font, point, x, y, width, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint(point, parent, point, x, y)
  if width then fs:SetWidth(width) end
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function button(parent, label, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h or 26)
  b:SetText(label)
  b:SetScript("OnClick", function()
    if blocked() then return end
    onClick()
  end)
  return b
end

-- Disabled buttons still show why they are disabled (b.reason) on hover.
local function reasonTip(b)
  b:SetMotionScriptsWhileDisabled(true)
  b:SetScript("OnEnter", function(self)
    if self:IsEnabled() or not self.reason then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.reason, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function setReason(b, reason)
  b.reason = reason
  if not reason and GameTooltip:GetOwner() == b then GameTooltip:Hide() end
end

local function box(parent, w, h)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
  f:SetBackdropColor(0.15, 0.12, 0.1, 0.9)
  f:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
  return f
end

local function makePanel(name, withTitle)
  local m = main()
  local p = CreateFrame("Frame", nil, m.content, "BackdropTemplate")
  p:SetPoint("TOPLEFT", m.playArea, "TOPLEFT", 0, -SELL_GAP)
  p:SetPoint("BOTTOMRIGHT", m.buttons, "BOTTOMRIGHT", 0, 0)
  p:SetFrameLevel(m.content:GetFrameLevel() + PANEL_LEVEL)
  p:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
  p:SetBackdropColor(0.1, 0.08, 0.06, 0.98)
  p:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
  p:EnableMouse(true) -- swallows clicks meant for the hidden hand
  if withTitle then
    p.title = text(p, Theme.fonts.title, "TOP", 0, -14, 560, "CENTER")
    Theme.setColor(p.title, Theme.gold)
  end
  p:Hide()
  panels[name] = p
  return p
end

---------------------------------------------------------------------------
-- New run

local function newSeed()
  return time() + math.floor(GetTime() * 1000) % 100000
end

local function startRun(deckId)
  if blocked() then return end
  local run = ns.Run.new(newSeed(), deckId)
  main().SetRun(run) -- renders the blind screen and clears the old hand
  persist()
end

local function buildNewRun()
  local p = makePanel("newrun", true)
  p.title:SetText("Choose your deck")
  local tileW, tileH, gap = 138, 220, 8
  local x0 = (p:GetWidth() > 0 and p:GetWidth() or 618) / 2 - (4 * tileW + 3 * gap) / 2
  p.tiles = {}
  for i, id in ipairs(ns.Decks.order) do
    local def = ns.Decks.def[id]
    local t = CreateFrame("Button", nil, p, "BackdropTemplate")
    t:SetSize(tileW, tileH)
    t:SetPoint("TOPLEFT", p, "TOPLEFT", x0 + (i - 1) * (tileW + gap), -56)
    t:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    t:SetBackdropColor(0.16, 0.13, 0.1, 1)
    t:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
    local name = text(t, Theme.fonts.title, "TOP", 0, -14, tileW - 16, "CENTER")
    name:SetText(def.name)
    Theme.setColor(name, Theme.gold)
    local desc = text(t, Theme.fonts.small, "TOP", 0, -48, tileW - 20, "CENTER")
    desc:SetText(def.desc)
    desc:SetHeight(60)
    desc:SetJustifyV("TOP")
    Theme.setColor(desc, Theme.parchment)
    local stats = text(t, Theme.fonts.text, "BOTTOM", 0, 20, tileW - 16, "CENTER")
    stats:SetText("Hands: " .. def.hands .. "\nDiscards: " .. def.discards .. "\nGold: " .. def.gold)
    t:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 1) end)
    t:SetScript("OnLeave", function(self)
      self:SetBackdropColor(0.16, 0.13, 0.1, 1)
      self:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
    end)
    t:SetScript("OnMouseDown", function(self) self:SetBackdropColor(0.3, 0.24, 0.12, 1) end)
    t:SetScript("OnMouseUp", function(self) self:SetBackdropColor(0.16, 0.13, 0.1, 1) end)
    t:SetScript("OnClick", function() startRun(id) end)
    p.tiles[i] = t
  end
  return p
end

---------------------------------------------------------------------------
-- Blind

local function blindName(run, blind)
  if blind == 3 then
    local boss = ns.Bosses.def[run.bosses[run.stage]]
    return boss and boss.name or "Boss Blind"
  end
  return BLIND_NAMES[blind]
end

local function startBlind()
  local run = main().run
  if not run or run.phase ~= "blind" then return end
  ns.Run.startBlind(run)
  main().Render(run)
  ns.UI.HandView.Update(run, true)
  persist()
end

local function buildBlind()
  local p = makePanel("blind", true)
  p.stage = text(p, Theme.fonts.text, "TOP", 0, -42, 560, "CENTER")
  Theme.setColor(p.stage, Theme.parchment)
  p.label = text(p, Theme.fonts.big, "TOP", 0, -66, 560, "CENTER")
  Theme.setColor(p.label, Theme.gold)
  local tl = text(p, Theme.fonts.small, "TOP", 0, -106, 560, "CENTER")
  tl:SetText("Score at least")
  p.target = text(p, Theme.fonts.big, "TOP", 0, -122, 560, "CENTER")
  p.rule = text(p, Theme.fonts.text, "TOP", 0, -156, 480, "CENTER")
  p.rule:SetHeight(34)
  p.rule:SetJustifyV("TOP")
  Theme.setColor(p.rule, Theme.parchment)

  p.preview = {}
  local w, gap = 170, 10
  local x0 = 618 / 2 - (3 * w + 2 * gap) / 2
  for i = 1, 3 do
    local b = box(p, w, 56)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", x0 + (i - 1) * (w + gap), -206)
    b.name = text(b, Theme.fonts.small, "TOP", 0, -10, w - 12, "CENTER")
    b.score = text(b, Theme.fonts.text, "TOP", 0, -30, w - 12, "CENTER")
    p.preview[i] = b
  end

  p.start = button(p, "Start Blind", 160, 30, startBlind)
  p.start:SetPoint("BOTTOM", p, "BOTTOM", 0, 20)
  return p
end

local function refreshBlind(p, run)
  p.title:SetText("Next Blind")
  p.stage:SetText("Stage " .. run.stage .. " / 8")
  p.label:SetText(blindName(run, run.blind))
  local bossId = ns.Run.bossId(run)
  local boss = bossId and ns.Bosses.def[bossId]
  p.target:SetText(tostring(ns.Run.target(run.stage, run.blind, bossId)))
  p.rule:SetText(boss and boss.desc or "")
  for i = 1, 3 do
    local b = p.preview[i]
    local id = run.bosses[run.stage]
    b.name:SetText(blindName(run, i))
    b.score:SetText(tostring(ns.Run.target(run.stage, i, i == 3 and id or nil)))
    local on = i == run.blind
    local c = on and Theme.gold or { 0.4, 0.33, 0.2 }
    b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    Theme.setColor(b.name, on and Theme.gold or GREY)
    Theme.setColor(b.score, on and Theme.gold or GREY)
  end
end

---------------------------------------------------------------------------
-- Shop

local function showError(p, code)
  errorToken = errorToken + 1
  local mine = errorToken
  p.err:SetText(BUY_ERRORS[code] or "Can't do that")
  p.err:Show()
  C_Timer.After(ERROR_TIME, function()
    if errorToken == mine then p.err:Hide() end
  end)
end

-- Runs a Shop action, reports a failure inline, then re-renders everything
-- (sidebar gold, trinket row, shop buttons) and persists.
local function shopAction(fn, ...)
  local run = main().run
  if blocked() or not run or run.phase ~= "shop" then return end
  local ok, why = fn(run, ...)
  if ok == false then showError(panels.shop, why) end
  main().Render(run)
  persist()
end

local function onSell(slot, id)
  local run = main().run
  if blocked() or not run or run.phase ~= "shop" then return end
  -- A sell shifts the next trinket's button under the cursor: ignore the
  -- follow-up click, and ignore clicks whose trinket is no longer in that slot.
  local now = GetTime()
  if now - lastSell < SELL_COOLDOWN then return end
  local owned = run.trinkets[slot]
  if not owned or owned.id ~= id then return end
  lastSell = now
  ns.Shop.sell(run, slot)
  main().Render(run)
  persist()
end

local function nextBlind()
  local run = main().run
  if blocked() or not run or run.phase ~= "shop" then return end
  ns.Run.nextBlind(run)
  main().Render(run)
  persist()
end

local CARD_W, CARD_H = 124, 190

local function makeCard(p, x, onBuy)
  local c = box(p, CARD_W, CARD_H)
  c:SetPoint("TOPLEFT", p, "TOPLEFT", x, -44)
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetSize(36, 36)
  c.icon:SetPoint("TOP", c, "TOP", 0, -8)
  c.name = text(c, Theme.fonts.text, "TOP", 0, -50, CARD_W - 12, "CENTER")
  c.name:SetHeight(30)
  c.name:SetJustifyV("TOP")
  c.desc = text(c, Theme.fonts.small, "TOP", 0, -82, CARD_W - 14, "CENTER")
  c.desc:SetHeight(56)
  c.desc:SetJustifyV("TOP")
  Theme.setColor(c.desc, Theme.parchment)
  c.cost = text(c, Theme.fonts.text, "BOTTOM", 0, 40, CARD_W - 12, "CENTER")
  c.buy = button(c, "Buy", 100, 24, onBuy)
  c.buy:SetPoint("BOTTOM", c, "BOTTOM", 0, 10)
  reasonTip(c.buy)
  c.sold = text(c, Theme.fonts.title, "CENTER", 0, 0, CARD_W - 12, "CENTER")
  c.sold:SetText("Sold")
  Theme.setColor(c.sold, GREY)
  return c
end

-- item: nil/false = sold; otherwise { icon, name, color, desc, cost, affordable, reason }
local function setCard(c, item)
  local live = item and true or false
  c.icon:SetShown(live)
  c.name:SetShown(live)
  c.desc:SetShown(live)
  c.cost:SetShown(live)
  c.buy:SetShown(live)
  c.sold:SetShown(not live)
  c:SetAlpha(live and 1 or 0.5)
  if not live then return end
  c.icon:SetTexture(item.icon)
  c.name:SetText(item.name)
  Theme.setColor(c.name, item.color)
  c.desc:SetText(item.desc)
  c.cost:SetText(item.cost .. "g")
  Theme.setColor(c.cost, item.affordable and Theme.gold or RED)
  c.buy:SetText(item.blockedText or "Buy")
  if item.ok then c.buy:Enable() else c.buy:Disable() end
  setReason(c.buy, (not item.ok) and item.reason or nil)
end

local function buildShop()
  local p = makePanel("shop", true)
  p.title:SetText("Shop")

  local hdr = text(p, Theme.fonts.text, "TOPLEFT", 16, -44, 180)
  hdr:SetText("Payout")
  Theme.setColor(hdr, Theme.gold)
  p.payout = {}
  local rows = { "reward", "hands", "interest", "trinkets", "total" }
  for i, key in ipairs(rows) do
    local y = -68 - (i - 1) * 22
    local label = text(p, key == "total" and Theme.fonts.text or Theme.fonts.small, "TOPLEFT", 16, y, 120)
    local value = text(p, key == "total" and Theme.fonts.text or Theme.fonts.small, "TOPLEFT", 136, y, 60, "RIGHT")
    if key == "total" then
      Theme.setColor(label, Theme.gold)
      Theme.setColor(value, Theme.gold)
    end
    p.payout[key] = { label = label, value = value }
  end

  local x = 208
  p.offerCards = {}
  for i = 1, 2 do
    p.offerCards[i] = makeCard(p, x + (i - 1) * (CARD_W + 8), function() shopAction(ns.Shop.buyTrinket, i) end)
  end
  p.tomeCard = makeCard(p, x + 2 * (CARD_W + 8), function() shopAction(ns.Shop.buyTome) end)

  p.err = text(p, Theme.fonts.text, "BOTTOM", 0, 64, 560, "CENTER")
  Theme.setColor(p.err, RED)
  p.err:Hide()

  p.reroll = button(p, "Reroll", 150, 28, function() shopAction(ns.Shop.reroll) end)
  p.reroll:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 208, 20)
  reasonTip(p.reroll)
  p.next = button(p, "Next Blind", 150, 28, nextBlind)
  p.next:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 20)
  return p
end

local function refreshShop(p, run)
  local pay = run.lastPayout or {}
  local lines = {
    reward = { "Blind reward", pay.reward },
    hands = { "Hands left (" .. (pay.hands or 0) .. " x 1g)", pay.hands },
    interest = { "Interest", pay.interest },
    trinkets = { "Trinkets", pay.trinkets },
    total = { "Total", pay.total },
  }
  for key, row in pairs(p.payout) do
    row.label:SetText(lines[key][1])
    row.value:SetText("+" .. (lines[key][2] or 0) .. "g")
  end

  local shop = run.shop or { offers = {}, tome = false, rerollCost = 0 }
  local full = #run.trinkets >= run.maxTrinkets
  for i = 1, 2 do
    local offer = shop.offers[i]
    if offer then
      local def = ns.Trinkets.def[offer.id]
      local afford = run.gold >= offer.cost
      setCard(p.offerCards[i], {
        icon = def.icon, name = def.name, desc = def.desc, cost = offer.cost,
        color = Theme.rarity[def.rarity] or Theme.rarity.common,
        affordable = afford, ok = afford and not full,
        blockedText = full and "Slots full" or nil,
        reason = afford and BUY_ERRORS.slots or BUY_ERRORS.gold,
      })
    else
      setCard(p.offerCards[i], false)
    end
  end

  local tome = shop.tome
  if tome then
    local afford = run.gold >= tome.cost
    local lvl = run.handLevels[tome.handId] or 1
    setCard(p.tomeCard, {
      icon = TOME_ICON, name = ns.Shop.tomeName(tome.handId),
      desc = "Raises " .. ns.Hands.def[tome.handId].name .. " to level " .. (lvl + 1) .. ".",
      cost = tome.cost, color = Theme.rarity.uncommon, affordable = afford, ok = afford,
      reason = BUY_ERRORS.gold,
    })
  else
    setCard(p.tomeCard, false)
  end

  p.reroll:SetText("Reroll (" .. shop.rerollCost .. "g)")
  local canReroll = run.gold >= shop.rerollCost
  if canReroll then p.reroll:Enable() else p.reroll:Disable() end
  setReason(p.reroll, (not canReroll) and BUY_ERRORS.gold or nil)
end

---------------------------------------------------------------------------
-- Won / lost

local function newRunClicked()
  if blocked() then return end
  if AzerothAnteDB then ns.Save.clear(AzerothAnteDB) end
  main().SetRun(nil) -- renders the deck-selection screen
end

local function buildEnd()
  local p = makePanel("end", false)
  p.head = text(p, Theme.fonts.big, "TOP", 0, -50, 560, "CENTER")
  p.stage = text(p, Theme.fonts.title, "TOP", 0, -120, 560, "CENTER")
  Theme.setColor(p.stage, Theme.parchment)
  p.deck = text(p, Theme.fonts.text, "TOP", 0, -156, 560, "CENTER")
  Theme.setColor(p.deck, Theme.parchment)
  p.best = text(p, Theme.fonts.title, "TOP", 0, -190, 560, "CENTER")
  Theme.setColor(p.best, Theme.gold)
  p.new = button(p, "New Run", 160, 30, newRunClicked)
  p.new:SetPoint("BOTTOM", p, "BOTTOM", 0, 30)
  return p
end

local function refreshEnd(p, run)
  local won = run.phase == "won"
  p.head:SetText(won and "Victory!" or "Defeated")
  Theme.setColor(p.head, won and Theme.gold or RED)
  p.stage:SetText("Stage reached: " .. run.stage .. " / 8")
  local deck = ns.Decks.def[run.deckId]
  p.deck:SetText(deck and (deck.name .. " deck") or "")
  p.best:SetText("Best hand: " .. (run.bestHand or 0))
end

---------------------------------------------------------------------------
-- Paused overlay

local function buildPaused()
  local m = main()
  local f = CreateFrame("Frame", nil, m.content)
  f:SetAllPoints(m.content)
  f:SetFrameLevel(m.content:GetFrameLevel() + PAUSE_LEVEL)
  f:EnableMouse(true)
  local dim = f:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints()
  dim:SetColorTexture(0, 0, 0, 0.75)
  local msg = f:CreateFontString(nil, "OVERLAY", Theme.fonts.big)
  msg:SetPoint("CENTER", f, "CENTER", 0, 20)
  msg:SetText("Queue popped!")
  Theme.setColor(msg, Theme.gold)
  local resume = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  resume:SetSize(140, 30)
  resume:SetPoint("CENTER", f, "CENTER", 0, -30)
  resume:SetText("Resume")
  resume:SetScript("OnClick", function() Screens.HidePaused() end)
  f:Hide()
  pausedFrame = f
  return f
end

function Screens.ShowPaused()
  if not main() or not main().content then return end
  local f = pausedFrame or buildPaused()
  if f:IsShown() then return end
  f:SetAlpha(0)
  f:Show()
  Tween.To(f, { alpha = 1 }, FADE)
end

function Screens.HidePaused()
  if not pausedFrame then return end
  Tween.Cancel(pausedFrame)
  pausedFrame:SetAlpha(1)
  pausedFrame:Hide()
end

---------------------------------------------------------------------------
-- Dispatch

-- Runs from Main.Render because every hand ends in a Render (post-tally or discard), so no result is missed.
-- Tracks the best single-hand score on the run itself (UI-only field, saved with it).
function Screens.Track(run)
  local r = run and run.lastResult
  if r and r.total and r.total > (run.bestHand or 0) then run.bestHand = r.total end
end

local PANEL_OF = {
  newrun = { "newrun", buildNewRun },
  blind = { "blind", buildBlind, refreshBlind },
  shop = { "shop", buildShop, refreshShop },
  won = { "end", buildEnd, refreshEnd },
  lost = { "end", buildEnd, refreshEnd },
}

local function hideAll()
  for _, p in pairs(panels) do
    Tween.Cancel(p)
    p:SetAlpha(1)
    p:Hide()
  end
end

-- Shows screen `name` ("newrun", "blind", "play", "shop", "won", "lost" or
-- "paused"). Cheap and idempotent: an already-visible screen is only refreshed.
function Screens.Show(name, run)
  local m = main()
  if not m or not m.content then return end
  if name == "paused" then return Screens.ShowPaused() end

  local entry = PANEL_OF[name]
  if not entry then -- "play": the hand view owns the canvas
    if current ~= "play" then
      hideAll()
      ns.UI.TrinketRow.SetSellMode(false)
      m.buttons:Show()
      current = "play"
    end
    return
  end

  local key = entry[1]
  local p = panels[key] or entry[2]()
  if entry[3] and run then entry[3](p, run) end
  ns.UI.TrinketRow.SetSellMode(name == "shop", onSell)
  if current == name then return end
  current = name
  if panels.shop then
    errorToken = errorToken + 1 -- cancels any pending hide timer
    panels.shop.err:SetText("")
    panels.shop.err:Hide()
  end
  hideAll()
  m.buttons:Hide()
  p:SetAlpha(0)
  p:Show()
  Tween.To(p, { alpha = 1 }, FADE)
end

ns.UI.Screens = Screens
