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
local BUY_ERRORS = { gold = "Not enough gold", slots = "Slots full", gone = "Sold out", pack = "Finish the open pack first" }
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
  local HandView, Tally, PackView = ns.UI.HandView, ns.UI.Tally, ns.UI.PackView
  return (HandView and HandView.IsBusy()) or (Tally and Tally.IsBusy())
    or (PackView and PackView.IsBusy()) or false
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

-- Clears the save and returns to the deck-selection screen.
local function endRun()
  if blocked() then return end
  if AzerothAnteDB then ns.Save.clear(AzerothAnteDB) end
  main().SetRun(nil) -- renders the deck-selection screen
end

-- Small two-click "Abandon Run" button: the first click arms it, and it
-- reverts after ABANDON_ARM seconds. No popup.
local ABANDON_ARM = 3
local function addAbandon(p)
  local armed, token = false, 0
  local b
  local function disarm()
    armed = false
    token = token + 1 -- cancels a pending revert
    b:SetText("Abandon Run")
  end
  b = button(p, "Abandon Run", 150, 22, function()
    if armed then
      disarm()
      endRun()
      return
    end
    armed = true
    token = token + 1
    local mine = token
    b:SetText("Click again to abandon")
    C_Timer.After(ABANDON_ARM, function()
      if token == mine and armed then disarm() end
    end)
  end)
  b:SetWidth(170)
  b:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 16, 20)
  b:SetScript("OnHide", disarm)
  p.abandon = b
  return b
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
  if AzerothAnteDB then ns.Profile.get(AzerothAnteDB).lastDeck = deckId end
  local run = ns.Run.new(newSeed(), deckId)
  main().SetRun(run) -- renders the blind screen and clears the old hand
  persist()
end

local function buildNewRun()
  return ns.UI.DeckSelect.Build({
    makePanel = makePanel, button = button, reasonTip = reasonTip, setReason = setReason, start = startRun,
  })
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
  addAbandon(p)
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
-- Item faces and pack info (shared with the pack view)

local MEDIA = "Interface\\AddOns\\AzerothAnte\\Media\\"
local WINDOW_CY = 78 / 179 -- vertical centre of the consumable cards' icon window (art is 128x179)
local FRAME_ART = { scroll = "Consumable_Scroll", tome = "Consumable_Tome", relic = "Consumable_Relic" }
local KIND_NAMES = { trinket = "Trinket", scroll = "Scroll", tome = "Tome", relic = "Relic" }
local TRINKET_FULL = "Trinket slots full - sell one first"
local CONSUMABLE_FULL = "Consumable slots full"
local GOLD_HEX = "|cffffd100"
local PACK_TYPES = {
  ARCANA = { name = "Arcana", contents = "Scrolls", tint = { 0.72, 0.52, 1 },
    note = "Aim them at cards drawn from your deck" },
  CELESTIAL = { name = "Celestial", contents = "Tomes", tint = { 0.45, 0.7, 1 },
    note = "Each one levels up a hand" },
  STANDARD = { name = "Standard", contents = "playing cards", tint = { 0.92, 0.84, 0.66 },
    note = "Added to your deck" },
  BUFFOON = { name = "Buffoon", contents = "Trinkets", tint = { 0.5, 1, 0.55 },
    note = "Needs a free trinket slot" },
  SPECTRAL = { name = "Spectral", contents = "Relics", tint = { 0.4, 1, 0.9 },
    note = "Aim them at cards drawn from your deck" },
}
local SIZE_NAMES = { normal = "", jumbo = "Jumbo ", mega = "Mega " }

-- Exposed so the pack view builds the same buttons and tooltips.
Screens.Widgets = { text = text, button = button, reasonTip = reasonTip, setReason = setReason }

-- Normalises a shop offer ({ type, id, ed }) or pack choice ({ kind, id } or a
-- trinket offer) into what an item face and its tooltip show.
function Screens.ItemInfo(item)
  local kind = item.kind or item.type
  local info = { kind = kind, ed = item.ed }
  if kind == "trinket" then
    local def = ns.Trinkets.def[item.id]
    local rarity = def.rarity or "common"
    info.name, info.desc, info.icon = def.name, def.desc or "", def.icon
    info.color = Theme.rarity[rarity] or Theme.rarity.common
    info.sub = rarity:sub(1, 1):upper() .. rarity:sub(2) .. " Trinket"
    local ed = ns.CardTypes.ed[item.ed]
    if ed then
      info.edName = ed.name
      info.edDesc = item.ed == "NEGATIVE" and "+1 trinket slot" or ed.desc
    end
  else
    local def = ns.Consumables.def({ kind = kind, id = item.id })
    local run = main() and main().run
    local held = { kind = kind, id = item.id }
    info.def = def
    info.name = def.name
    info.icon = def.icon or TOME_ICON
    info.desc = ns.Consumables.describe(run, held)
    if kind == "tome" then info.level = ns.Consumables.affects(run, held) end
    info.color = Theme.parchment
    info.sub = KIND_NAMES[kind]
  end
  return info
end

-- Name, kind and rarity, description, then the edition line (Negative says
-- exactly "+1 trinket slot").
function Screens.ShowItemTip(owner, info, hint)
  if not info then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(info.name, Theme.gold[1], Theme.gold[2], Theme.gold[3])
  GameTooltip:AddLine(info.sub or "", info.color[1], info.color[2], info.color[3])
  GameTooltip:AddLine(info.desc, 1, 1, 1, true)
  if info.level then GameTooltip:AddLine(info.level, Theme.gold[1], Theme.gold[2], Theme.gold[3]) end
  if info.edName then
    GameTooltip:AddLine(info.edName, Theme.gold[1], Theme.gold[2], Theme.gold[3])
    GameTooltip:AddLine(info.edDesc, 1, 1, 1, true)
  end
  if hint then GameTooltip:AddLine(hint, 0.6, 0.9, 0.6) end
  GameTooltip:Show()
end

-- A 5:7 card face for a trinket (icon on a dark card, with its edition FX) or a
-- consumable (the kind's frame art, icon on top). withPlate adds the name.
function Screens.NewFace(parent, w, h, withPlate)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f.border = f:CreateTexture(nil, "BACKGROUND")
  f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
  f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
  f.border:Hide()
  f.bg = f:CreateTexture(nil, "BORDER")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0.16, 0.13, 0.1, 1)
  f.art = f:CreateTexture(nil, "ARTWORK")
  f.art:SetAllPoints()
  f.art:SetTexCoord(0, 1, 0, Theme.cardV) -- 5:7 art in the top of the canvas
  local size = math.floor(w * 0.5)
  f.iconBox = CreateFrame("Frame", nil, f)
  f.iconBox:SetSize(size, size)
  f.iconBox:SetPoint("TOP", f, "TOP", 0, -math.floor(h * 0.14))
  f.iconBoxH = h
  f.icon = f.iconBox:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints()
  if withPlate then
    f.plate = f:CreateTexture(nil, "OVERLAY")
    f.plate:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 3, 3)
    f.plate:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    f.plate:SetHeight(28)
    f.plate:SetColorTexture(0, 0, 0, 0.65)
    f.name = f:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
    f.name:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
    f.name:SetWidth(w - 8)
    f.name:SetHeight(24)
    f.name:SetJustifyH("CENTER")
    Theme.setColor(f.name, Theme.parchment)
  end
  return f
end

function Screens.SetFaceSelected(f, on)
  if on then
    f.border:SetColorTexture(Theme.gold[1], Theme.gold[2], Theme.gold[3], 1)
    f.border:Show()
  elseif f.baseBorder then
    f.border:SetColorTexture(f.baseBorder[1], f.baseBorder[2], f.baseBorder[3], 1)
    f.border:Show()
  else
    f.border:Hide()
  end
end

function Screens.SkinFace(f, info)
  f.info = info
  local trinket = info.kind == "trinket"
  f.icon:SetTexture(info.icon)
  f.bg:SetShown(trinket)
  f.art:SetShown(not trinket)
  if not trinket then f.art:SetTexture(MEDIA .. FRAME_ART[info.kind]) end
  -- A consumable card's icon sits centred in the art's icon window (centre at
  -- WINDOW_CY of the card height), clear of the border.
  f.iconBox:ClearAllPoints()
  if trinket then
    f.iconBox:SetPoint("TOP", f, "TOP", 0, -math.floor(f.iconBoxH * 0.14))
  else
    local size = f.iconBox:GetHeight()
    f.iconBox:SetPoint("TOP", f, "TOP", 0, -math.floor(f.iconBoxH * WINDOW_CY - size / 2 + 0.5))
  end
  f.baseBorder = trinket and info.color or nil
  Screens.SetFaceSelected(f, false)
  ns.UI.EditionFX.Attach(f.iconBox, trinket and info.ed or nil)
  if f.name then
    f.name:SetText(info.name)
    f.plate:Show()
  end
end

-- label, tint, contents and a one-line description for a pack offer or an open pack.
function Screens.PackInfo(pack)
  local t = PACK_TYPES[pack.type]
  local size = ns.Packs.SIZES[pack.size]
  local show = ns.Packs.showCount(pack.type, pack.size)
  return {
    label = SIZE_NAMES[pack.size] .. t.name .. " Pack", tint = t.tint, show = show, picks = size.pick,
    sizeText = pack.size == "normal" and "" or pack.size:upper(),
    desc = ("Choose %d of %d %s\n%s"):format(size.pick, show, t.contents, t.note),
  }
end

---------------------------------------------------------------------------
-- Shop

local function slotsMessage(offerType)
  return offerType == "trinket" and TRINKET_FULL or CONSUMABLE_FULL
end

local function showError(p, code, offerType)
  errorToken = errorToken + 1
  local mine = errorToken
  p.err:SetText(code == "slots" and slotsMessage(offerType) or BUY_ERRORS[code] or "Can't do that")
  p.err:Show()
  C_Timer.After(ERROR_TIME, function()
    if errorToken == mine then p.err:Hide() end
  end)
end

-- Runs a Shop action, reports a failure inline, then re-renders everything
-- (sidebar gold, trinket row, shop buttons) and persists. onOk(run) plays the
-- success animation after the render; the gold change floats over the sidebar.
local function shopAction(fn, onOk, offerType, ...)
  local run = main().run
  if blocked() or not run or run.phase ~= "shop" then return end
  local before = run.gold
  local ok, why = fn(run, ...)
  if ok == false then showError(panels.shop, why, offerType) end
  main().Render(run, true)
  persist()
  if ok ~= false then
    ns.UI.Outcome.FloatGold(run.gold - before)
    if onOk then onOk(run) end
  end
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
  local gained = ns.Shop.sellTrinket(run, slot)
  main().Render(run, true) -- a pack open on this screen re-checks its Pick button
  ns.UI.Outcome.FloatGold(gained)
  persist()
end

local function nextBlind()
  local run = main().run
  if blocked() or not run or run.phase ~= "shop" then return end
  ns.Run.nextBlind(run)
  main().Render(run)
  persist()
end

local COL_W, FACE_H, COL_H = 90, 126, 276 -- 5:7 face
local COL_Y = -64

-- Fades a column in (new offers after a reroll).
local function fadeIn(c, delay)
  c:SetAlpha(0)
  Tween.To(c, { alpha = 1 }, 0.2, nil, delay or 0)
end

local function makeColumn(p, x, actionLabel, onClick)
  local c = CreateFrame("Frame", nil, p)
  c:SetSize(COL_W, COL_H)
  c:SetPoint("TOPLEFT", p, "TOPLEFT", x, COL_Y)
  c.name = text(c, Theme.fonts.small, "TOP", 0, -(FACE_H + 6), COL_W, "CENTER")
  c.name:SetHeight(26)
  c.name:SetJustifyV("TOP")
  c.desc = text(c, Theme.fonts.small, "TOP", 0, -(FACE_H + 34), COL_W, "CENTER")
  c.desc:SetHeight(64)
  c.desc:SetJustifyV("TOP")
  Theme.setColor(c.desc, Theme.parchment)
  c.cost = text(c, Theme.fonts.text, "BOTTOM", 0, 30, COL_W, "CENTER")
  c.buy = button(c, actionLabel, COL_W - 6, 24, onClick)
  c.buy:SetPoint("BOTTOM", c, "BOTTOM", 0, 0)
  reasonTip(c.buy)
  c.sold = text(c, Theme.fonts.title, "TOP", 0, -(FACE_H / 2 - 8), COL_W, "CENTER")
  c.sold:SetText("Sold")
  Theme.setColor(c.sold, GREY)
  return c
end

local function makeOfferColumn(p, x, onBuy)
  local c = makeColumn(p, x, "Buy", onBuy)
  c.face = Screens.NewFace(c, COL_W, FACE_H, false)
  c.face:SetPoint("TOP", c, "TOP", 0, 0)
  c.face:EnableMouse(true)
  c.face:SetScript("OnEnter", function(self) Screens.ShowItemTip(self, self.info) end)
  c.face:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return c
end

local function makePackColumn(p, x, onOpen)
  local c = makeColumn(p, x, "Open", onOpen)
  local f = CreateFrame("Frame", nil, c)
  f:SetSize(COL_W, FACE_H)
  f:SetPoint("TOP", c, "TOP", 0, 0)
  f:EnableMouse(true)
  f.art = f:CreateTexture(nil, "ARTWORK")
  f.art:SetAllPoints()
  f.art:SetTexture(MEDIA .. "Pack")
  f.art:SetTexCoord(0, 1, 0, Theme.cardV)
  f.size = f:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
  f.size:SetPoint("CENTER", f, "CENTER", 0, 0)
  f:SetScript("OnEnter", function(self)
    if not self.pack then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.pack.label, Theme.gold[1], Theme.gold[2], Theme.gold[3])
    GameTooltip:AddLine(self.pack.desc, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  c.face = f
  return c
end

local function buildShop()
  local p = makePanel("shop", true)
  p.title:SetText("Shop")

  local hdr = text(p, Theme.fonts.text, "TOPLEFT", 16, -44, 180)
  hdr:SetText("Payout")
  Theme.setColor(hdr, Theme.gold)
  p.payout = {}
  local rows = { "reward", "hands", "discards", "interest", "trinkets", "held", "total" }
  for i, key in ipairs(rows) do
    local y = -68 - (i - 1) * 22
    local label = text(p, key == "total" and Theme.fonts.text or Theme.fonts.small, "TOPLEFT", 16, y, 120)
    local value = text(p, key == "total" and Theme.fonts.text or Theme.fonts.small, "TOPLEFT", 130, y, 56, "RIGHT")
    if key == "total" then
      Theme.setColor(label, Theme.gold)
      Theme.setColor(value, Theme.gold)
    end
    p.payout[key] = { label = label, value = value }
  end

  local cardsHdr = text(p, Theme.fonts.small, "TOPLEFT", 200, -46, 2 * COL_W + 8, "CENTER")
  cardsHdr:SetText("Cards")
  Theme.setColor(cardsHdr, Theme.gold)
  local packsHdr = text(p, Theme.fonts.small, "TOPLEFT", 200 + 2 * COL_W + 8 + 24, -46, 2 * COL_W + 8, "CENTER")
  packsHdr:SetText("Packs")
  Theme.setColor(packsHdr, Theme.gold)

  p.offerCards, p.packOffers = {}, {}
  for i = 1, 2 do
    local item = i
    p.offerCards[i] = makeOfferColumn(p, 200 + (i - 1) * (COL_W + 8), function()
      local run = main().run
      local offer = run and run.shop and run.shop.cards[item]
      local offerType = offer and offer.type
      shopAction(ns.Shop.buy, function(r)
        if offerType == "trinket" then
          ns.UI.TrinketRow.Pulse(#r.trinkets)
        else
          local held = r.consumables[#r.consumables]
          if held then ns.UI.Outcome.Play({ created = { held } }) end
        end
      end, offerType, item)
    end)
    p.packOffers[i] = makePackColumn(p, 200 + 2 * COL_W + 8 + 24 + (i - 1) * (COL_W + 8), function()
      shopAction(ns.Packs.open, nil, nil, item)
    end)
  end

  p.err = text(p, Theme.fonts.text, "BOTTOM", 0, 56, 560, "CENTER")
  Theme.setColor(p.err, RED)
  p.err:Hide()

  p.reroll = button(p, "Reroll", 150, 28, function()
    shopAction(ns.Shop.reroll, function()
      for i = 1, 2 do
        fadeIn(p.offerCards[i], (i - 1) * 0.06)
      end
    end)
  end)
  p.reroll:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 200, 20)
  reasonTip(p.reroll)
  p.next = button(p, "Next Blind", 150, 28, nextBlind)
  p.next:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 20)
  addAbandon(p)
  return p
end

local function setColumn(c, live)
  c.face:SetShown(live)
  c.name:SetShown(live)
  c.desc:SetShown(live)
  c.cost:SetShown(live)
  c.buy:SetShown(live)
  c.sold:SetShown(not live)
  c:SetAlpha(live and 1 or 0.5)
end

-- Fills an offer column. spec = { name, color, desc, cost, affordable, ok, reason, blockedText }.
local function fillColumn(c, spec)
  c.name:SetText(spec.name)
  Theme.setColor(c.name, spec.color)
  c.desc:SetText(spec.desc)
  c.cost:SetText(spec.cost .. "g")
  Theme.setColor(c.cost, spec.affordable and Theme.gold or RED)
  c.buy:SetText(spec.blockedText or spec.action)
  if spec.ok then c.buy:Enable() else c.buy:Disable() end
  setReason(c.buy, (not spec.ok) and spec.reason or nil)
end

local function refreshShop(p, run)
  local pay = run.lastPayout or {}
  local deck = ns.Decks.def[run.deckId] or {}
  local interestLabel = "Interest"
  if deck.noInterest then interestLabel = "Interest (none: " .. (deck.name or ""):gsub(" Deck$", "") .. ")" end
  local lines = {
    reward = { "Blind reward", pay.reward },
    hands = { "Hands left (" .. (run.handsLeft or 0) .. " x " .. (deck.goldPerHand or 1) .. "g)", pay.hands },
    discards = { "Discards left (" .. (run.discardsLeft or 0) .. " x " .. (deck.goldPerDiscard or 0) .. "g)", pay.discards },
    interest = { interestLabel, pay.interest },
    trinkets = { "Trinkets", pay.trinkets },
    held = { "Held Gold cards", pay.held },
    total = { "Total", pay.total },
  }
  local y = -68
  for _, key in ipairs({ "reward", "hands", "discards", "interest", "trinkets", "held", "total" }) do
    local row = p.payout[key]
    local show = key ~= "discards" or (pay.discards or 0) > 0
    row.label:SetShown(show)
    row.value:SetShown(show)
    if show then
      row.label:SetText(lines[key][1])
      row.value:SetText("+" .. (lines[key][2] or 0) .. "g")
      row.label:ClearAllPoints()
      row.value:ClearAllPoints()
      row.label:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y)
      row.value:SetPoint("TOPLEFT", p, "TOPLEFT", 130, y)
      y = y - 22
    end
  end

  local shop = run.shop or { cards = {}, packs = {}, rerollCost = 0 }
  local blockedByPack = shop.openPack ~= nil
  for i = 1, 2 do
    local c = p.offerCards[i]
    local offer = shop.cards[i]
    setColumn(c, offer and true or false)
    if offer then
      local info = Screens.ItemInfo(offer)
      local full
      if offer.type == "trinket" then
        full = #run.trinkets >= ns.Run.trinketSlots(run) + (offer.ed == "NEGATIVE" and 1 or 0)
      else
        full = #run.consumables >= run.maxConsumables
      end
      local afford = run.gold >= offer.cost
      Screens.SkinFace(c.face, info)
      local desc = info.desc
      if info.edName then desc = desc .. "\n" .. GOLD_HEX .. info.edName .. ": " .. info.edDesc .. "|r" end
      local reason
      if blockedByPack then reason = BUY_ERRORS.pack
      elseif not afford then reason = BUY_ERRORS.gold
      else reason = slotsMessage(offer.type) end
      fillColumn(c, {
        name = info.name, color = info.color, desc = desc, cost = offer.cost, action = "Buy",
        affordable = afford, ok = afford and not full and not blockedByPack,
        blockedText = (full and afford) and "Slots full" or nil, reason = reason,
      })
    end
  end

  for i = 1, 2 do
    local c = p.packOffers[i]
    local offer = shop.packs[i]
    setColumn(c, offer and true or false)
    if offer then
      local info = Screens.PackInfo(offer)
      local afford = run.gold >= offer.cost
      c.face.pack = info
      c.face.art:SetVertexColor(info.tint[1], info.tint[2], info.tint[3])
      c.face.size:SetText(info.sizeText)
      fillColumn(c, {
        name = info.label, color = Theme.parchment, desc = info.desc, cost = offer.cost, action = "Open",
        affordable = afford, ok = afford and not blockedByPack,
        reason = blockedByPack and BUY_ERRORS.pack or BUY_ERRORS.gold,
      })
    end
  end

  p.reroll:SetText("Reroll (" .. shop.rerollCost .. "g)")
  local canReroll = run.gold >= shop.rerollCost and not blockedByPack
  if canReroll then p.reroll:Enable() else p.reroll:Disable() end
  setReason(p.reroll, blockedByPack and BUY_ERRORS.pack or ((not canReroll) and BUY_ERRORS.gold or nil))
end

---------------------------------------------------------------------------
-- Won / lost

local newRunClicked = endRun

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
  -- A finished run counts once: the flag travels with the saved run, so a reload
  -- of a won or lost save never records it again. Abandoning never records.
  if run and (run.phase == "won" or run.phase == "lost") and not run.recorded and AzerothAnteDB then
    run.recorded = true
    pcall(ns.Profile.recordRun, AzerothAnteDB, run)
    persist()
  end
end

local PANEL_OF = {
  newrun = { "newrun", buildNewRun, function() ns.UI.DeckSelect.Refresh() end },
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
      m.handArea:Show()
      current = "play"
      ns.UI.EditionFX.Wake() -- the hand's shimmer resumes
    end
    return
  end

  local key = entry[1]
  local p = panels[key] or entry[2]()
  if entry[3] and (run or name == "newrun") then entry[3](p, run) end
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
  -- The stale play hand sits under the panel: hidden, it neither shimmers nor takes clicks.
  m.handArea:Hide()
  ns.UI.EditionFX.Wake()
  p:SetAlpha(0)
  p:Show()
  Tween.To(p, { alpha = 1 }, FADE)
end

ns.UI.Screens = Screens
