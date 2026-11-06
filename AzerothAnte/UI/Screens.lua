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
local BUY_ERRORS = { gold = "Not enough gold", slots = "Slots full", gone = "Sold out", pack = "Finish the open pack first" }
local TOME_ICON = "Interface\\Icons\\INV_Misc_Book_09"

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

-- variant: nil, "primary" (the main action on a screen) or "danger" (see Theme.Button).
local function button(parent, label, w, h, onClick, variant)
  local b = Theme.NewButton(parent, label, w, h or 28, variant)
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

-- Clears the save and returns to the deck-selection screen.
local function endRun()
  if blocked() then return end
  if AzerothAnteDB then ns.Save.clear(AzerothAnteDB) end
  main().SetRun(nil) -- renders the deck-selection screen
end

-- Two-click "Abandon Run": the first click arms the button, and it reverts after
-- ABANDON_ARM seconds. No popup. Shared by the panel buttons and the title-bar
-- button. A click while a hand, tally or pack is busy is ignored (reason tooltip).
local ABANDON_ARM = 3
local BUSY_REASON = "Finish the current action first"
Screens.Blocked = blocked
Screens.BUSY_REASON = BUSY_REASON
function Screens.AttachAbandon(b, idle, armedLabel)
  local armed, token = false, 0
  local function disarm()
    armed = false
    token = token + 1 -- cancels a pending revert
    b:SetText(idle)
  end
  b:SetScript("OnClick", function(self)
    if blocked() then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(BUSY_REASON, 1, 1, 1, 1, true)
      GameTooltip:Show()
      return
    end
    if armed then
      disarm()
      endRun()
      return
    end
    armed = true
    token = token + 1
    local mine = token
    b:SetText(armedLabel)
    C_Timer.After(ABANDON_ARM, function()
      if token == mine and armed then disarm() end
    end)
  end)
  b:HookScript("OnHide", disarm)
  return b
end

local function addAbandon(p)
  local b = Theme.NewButton(p, "Abandon Run", 176, 24, "danger")
  Screens.AttachAbandon(b, "Abandon Run", "Click again to abandon")
  b:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 16, 16)
  p.abandon = b
  return b
end

local function makePanel(name, withTitle)
  local m = main()
  local p = CreateFrame("Frame", nil, m.content)
  p:SetPoint("TOPLEFT", m.playArea, "TOPLEFT", 0, -SELL_GAP)
  p:SetPoint("BOTTOMRIGHT", m.buttons, "BOTTOMRIGHT", 0, 0)
  p:SetFrameLevel(m.content:GetFrameLevel() + PANEL_LEVEL)
  Theme.Inset(p)
  p:EnableMouse(true) -- swallows clicks meant for the hidden hand
  if withTitle then
    p.title = text(p, Theme.fonts.title, "TOP", 0, -16, 560, "CENTER")
    Theme.Value(p.title, true)
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

local function startBlind()
  local run = main().run
  if not run or run.phase ~= "blind" then return end
  ns.Run.startBlind(run)
  main().Render(run)
  ns.UI.HandView.Update(run, true)
  persist()
end

-- Director's Cut / Retcon: re-draws this stage's boss. The button is only live
-- when Run.canRerollBoss agrees, but the guard is repeated here.
local function rerollBoss()
  local run = main().run
  if blocked() or not run or run.phase ~= "blind" then return end
  local before = run.gold
  local ok = ns.Run.rerollBoss(run)
  main().Render(run, true)
  persist()
  if ok then
    ns.UI.Outcome.FloatGold(run.gold - before)
    ns.UI.BlindSelect.FlipBoss(panels.blind)
  end
end

local function buildBlind()
  return ns.UI.BlindSelect.Build({
    makePanel = makePanel, button = button, reasonTip = reasonTip, setReason = setReason,
    addAbandon = addAbandon, start = startBlind, rerollBoss = rerollBoss,
  })
end

local function refreshBlind(p, run)
  ns.UI.BlindSelect.Refresh(p, run)
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
local CARD_RANK_NAMES = { [11] = "Jack", [12] = "Queen", [13] = "King", [14] = "Ace" }
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
  elseif kind == "card" then
    local CT = ns.CardTypes
    info.name = (CARD_RANK_NAMES[item.rank] or tostring(item.rank)) .. " of " .. ns.Cards.SUIT_NAMES[item.suit]
    local lines = {}
    local defs = { CT.enh[item.enh], CT.seal[item.seal], CT.ed[item.ed] }
    for i = 1, 3 do
      if defs[i] then lines[#lines + 1] = defs[i].name .. ": " .. defs[i].desc end
    end
    info.desc = #lines > 0 and table.concat(lines, "\n") or "A plain playing card."
    info.color = Theme.parchment
    info.sub = "Playing Card"
    info.card = item
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

-- Name, tier and effect of a voucher (shop tile and sidebar icons).
function Screens.ShowVoucherTip(owner, id, anchor)
  local def = ns.Vouchers.def[id]
  if not def then return end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  GameTooltip:AddLine(def.name, Theme.gold[1], Theme.gold[2], Theme.gold[3])
  GameTooltip:AddLine(def.tier == 2 and "Voucher (upgrade)" or "Voucher", Theme.parchment[1], Theme.parchment[2], Theme.parchment[3])
  GameTooltip:AddLine(def.desc, 1, 1, 1, true)
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
  Theme.Selected(f, on) -- thin gold outline and a soft glow
  if f.baseBorder then
    f.border:SetColorTexture(f.baseBorder[1], f.baseBorder[2], f.baseBorder[3], 1)
    f.border:Show()
  else
    f.border:Hide()
  end
end

function Screens.SkinFace(f, info)
  if info.kind == "card" then return end -- playing cards use a CardWidget, not an item face
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

-- A bought playing card goes to the deck: update the sidebar count and pulse the button.
function Screens.PulseDeckButton(run)
  local btn = main().sidebar and main().sidebar.deckButton
  if not btn then return end
  btn:SetText("Deck (" .. #(run.deck or {}) .. ")")
  Tween.Cancel(btn)
  Tween.To(btn, { scale = 1.12 }, 0.1, function() Tween.To(btn, { scale = 1 }, 0.15) end)
end

local function nextBlind()
  local run = main().run
  if blocked() or not run or run.phase ~= "shop" then return end
  ns.Run.nextBlind(run)
  main().Render(run)
  persist()
end

local COL_W, FACE_H, COL_H = 90, 126, 276 -- 5:7 face
local MAX_CARDS = 4                    -- 2 slots, +1 per Overstock tier
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
  c.buy = button(c, actionLabel, COL_W - 8, 24, onClick, "primary")
  c.buy:SetPoint("BOTTOM", c, "BOTTOM", 0, 4)
  Theme.Raised(c) -- each offer is a raised tile
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

-- Offer columns shrink when Overstock adds card slots: n cards and 2 packs share one row.
local CARDS_X = 200
local function shopMetrics(n)
  if n <= 2 then return COL_W, 8, 24 end
  return math.floor((416 - 16 - (n + 1) * 6) / (n + 2)), 6, 16
end

local function layoutColumn(c, x, cw, compact)
  local fh = math.floor(cw * 7 / 5 + 0.5)
  c.compact = compact
  c:SetSize(cw, compact and (fh + 82) or COL_H)
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", c:GetParent(), "TOPLEFT", x, COL_Y)
  c.name:ClearAllPoints()
  c.name:SetPoint("TOP", c, "TOP", 0, -(fh + 6))
  c.name:SetWidth(cw)
  c.desc:ClearAllPoints()
  c.desc:SetPoint("TOP", c, "TOP", 0, -(fh + 34))
  c.desc:SetWidth(cw)
  c.cost:SetWidth(cw)
  c.buy:SetWidth(cw - 8)
  c.sold:SetWidth(cw)
  c.sold:ClearAllPoints()
  c.sold:SetPoint("TOP", c, "TOP", 0, -(fh / 2 - 8))
  c.face:SetSize(cw, fh)
  if c.face.iconBox then
    c.face.iconBox:SetSize(math.floor(cw * 0.5), math.floor(cw * 0.5))
    c.face.iconBoxH = fh
    if c.face.info then Screens.SkinFace(c.face, c.face.info) end
  end
end

local function layoutShop(p, n)
  if p.cardCount == n then return end
  p.cardCount = n
  local cw, gap, groupGap = shopMetrics(n)
  local compact = n > 2
  for i = 1, #p.offerCards do
    layoutColumn(p.offerCards[i], CARDS_X + (i - 1) * (cw + gap), cw, compact)
  end
  local packsX = CARDS_X + n * cw + (n - 1) * gap + groupGap
  for i = 1, 2 do layoutColumn(p.packOffers[i], packsX + (i - 1) * (cw + gap), cw, compact) end
  p.cardsHdr:SetWidth(n * cw + (n - 1) * gap)
  p.packsHdr:ClearAllPoints()
  p.packsHdr:SetPoint("TOPLEFT", p, "TOPLEFT", packsX, -46)
  p.packsHdr:SetWidth(2 * cw + gap)
end

---------------------------------------------------------------------------
-- The voucher tile: one coupon per shop visit, under the payout.

local VW, VH, VX, VY = 176, 156, 12, -226
local SOLD_IN_DELAY = 0.6

local function voucherArt(def)
  return MEDIA .. (def.tier == 2 and "Voucher_Plus" or "Voucher")
end

local function buildVoucherTile(p)
  local v = CreateFrame("Frame", nil, p)
  v:SetSize(VW, VH)
  v:SetPoint("TOPLEFT", p, "TOPLEFT", VX, VY)
  Theme.Raised(v)
  local header = text(v, Theme.fonts.small, "TOPLEFT", 8, -6, 100)
  header:SetText("Voucher")
  Theme.Label(header)

  local c = CreateFrame("Frame", nil, v)
  c:SetAllPoints(v)
  v.content = c
  v.face = CreateFrame("Frame", nil, c)
  v.face:SetSize(48, 67)
  v.face:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -22)
  v.face:EnableMouse(true)
  v.face.art = v.face:CreateTexture(nil, "ARTWORK")
  v.face.art:SetAllPoints()
  v.face.art:SetTexCoord(0, 1, 0, Theme.cardV)
  v.face:SetScript("OnEnter", function(self)
    if self.voucherId then Screens.ShowVoucherTip(self, self.voucherId) end
  end)
  v.face:SetScript("OnLeave", function() GameTooltip:Hide() end)
  v.name = text(c, Theme.fonts.small, "TOPLEFT", 62, -22, 106)
  v.name:SetHeight(28)
  v.name:SetJustifyV("TOP")
  Theme.setColor(v.name, Theme.gold)
  v.orig = text(c, Theme.fonts.small, "TOPLEFT", 62, -52, 60)
  Theme.Label(v.orig)
  v.strike = c:CreateTexture(nil, "OVERLAY")
  v.strike:SetPoint("LEFT", v.orig, "LEFT", 0, 0)
  v.strike:SetColorTexture(RED[1], RED[2], RED[3], 1)
  Theme.Edge(v.strike, "h", 1)
  v.price = text(c, Theme.fonts.text, "TOPLEFT", 62, -66, 106)
  v.desc = text(c, Theme.fonts.small, "TOPLEFT", 8, -91, 160)
  v.desc:SetHeight(36)
  v.desc:SetJustifyV("TOP")
  Theme.setColor(v.desc, Theme.parchment)
  v.buy = button(c, "Buy", 160, 22, function()
    local run = main().run
    local offer = run and run.shopVoucher
    local id = offer and offer.id
    shopAction(ns.Shop.buyVoucher, function() Screens.PlayVoucherSold(p, id) end, nil)
  end, "primary")
  v.buy:SetPoint("BOTTOM", c, "BOTTOM", 0, 4)
  reasonTip(v.buy)

  -- Bought: the coupon is stamped, then fades out under "Sold out this stage".
  local ghost = CreateFrame("Frame", nil, v)
  ghost:SetAllPoints(v)
  ghost:SetFrameLevel(v:GetFrameLevel() + 5)
  ghost.art = ghost:CreateTexture(nil, "ARTWORK")
  ghost.art:SetSize(48, 67)
  ghost.art:SetPoint("TOPLEFT", ghost, "TOPLEFT", 8, -22)
  ghost.art:SetTexCoord(0, 1, 0, Theme.cardV)
  ghost.name = text(ghost, Theme.fonts.small, "TOPLEFT", 62, -22, 106)
  Theme.setColor(ghost.name, Theme.gold)
  ghost.stamp = CreateFrame("Frame", nil, ghost)
  ghost.stamp:SetSize(120, 30)
  ghost.stamp:SetPoint("CENTER", ghost, "CENTER", 0, 10)
  ghost.stamp.text = ghost.stamp:CreateFontString(nil, "OVERLAY", Theme.fonts.big)
  ghost.stamp.text:SetPoint("CENTER", ghost.stamp, "CENTER", 0, 0)
  ghost.stamp.text:SetText("BOUGHT")
  Theme.setColor(ghost.stamp.text, Theme.gold)
  if ghost.stamp.text.SetRotation then pcall(ghost.stamp.text.SetRotation, ghost.stamp.text, math.rad(12)) end
  ghost:Hide()
  v.ghost = ghost

  local soldBox = CreateFrame("Frame", nil, v)
  soldBox:SetAllPoints(v)
  soldBox.text = text(soldBox, Theme.fonts.text, "CENTER", 0, -8, VW - 16, "CENTER")
  soldBox.text:SetText("Sold out this stage")
  Theme.setColor(soldBox.text, GREY)
  soldBox:Hide()
  v.soldBox = soldBox
  p.voucher = v
  return v
end

-- The stamp-and-fade after a purchase. Safe if cancelled: refreshShop restores the static look.
function Screens.PlayVoucherSold(p, id)
  local v, def = p.voucher, id and ns.Vouchers.def[id]
  if not v or not def then return end
  local g = v.ghost
  Tween.Cancel(g)
  Tween.Cancel(g.stamp)
  Tween.Cancel(v.soldBox)
  g.art:SetTexture(voucherArt(def))
  g.name:SetText(def.name)
  g:SetAlpha(1)
  g:Show()
  g.stamp:SetAlpha(0)
  g.stamp:SetScale(2.4)
  Tween.To(g.stamp, { scale = 1, alpha = 1 }, 0.2)
  Tween.To(g, { alpha = 0 }, 0.35, function() g:Hide() end, SOLD_IN_DELAY)
  v.soldBox:SetAlpha(0)
  Tween.To(v.soldBox, { alpha = 1 }, 0.3, nil, SOLD_IN_DELAY)
end

local function refreshVoucher(p, run)
  local v = p.voucher
  local offer = run.shopVoucher
  local def = offer and ns.Vouchers.def[offer.id]
  if not def then
    v.soldBox.text:SetText(offer == nil and "No voucher this stage" or "Sold out this stage")
    v.content:Hide()
    v.soldBox:Show()
    if not Tween.IsActive(v.soldBox) then v.soldBox:SetAlpha(1) end
    if not Tween.IsActive(v.ghost) then v.ghost:Hide() end
    return
  end
  Tween.Cancel(v.ghost)
  Tween.Cancel(v.ghost.stamp)
  Tween.Cancel(v.soldBox)
  v.ghost:Hide()
  v.soldBox:Hide()
  v.content:Show()
  local price = ns.Vouchers.price(run, def.cost)
  local afford = run.gold >= price
  local blockedByPack = run.shop and run.shop.openPack ~= nil
  v.face.voucherId = def.id
  v.face.art:SetTexture(voucherArt(def))
  v.name:SetText(def.name)
  v.desc:SetText(def.desc)
  local discounted = price ~= def.cost
  v.orig:SetShown(discounted)
  v.strike:SetShown(discounted)
  if discounted then
    v.orig:SetText(def.cost .. "g")
    v.strike:SetWidth(v.orig:GetStringWidth())
  end
  v.price:SetText(price .. "g")
  Theme.setColor(v.price, afford and Theme.gold or RED)
  local ok = afford and not blockedByPack and run.phase == "shop"
  if ok then v.buy:Enable() else v.buy:Disable() end
  local why = blockedByPack and BUY_ERRORS.pack or (not afford and BUY_ERRORS.gold) or "Only in the shop"
  setReason(v.buy, (not ok) and why or nil)
end

local function buildShop()
  local p = makePanel("shop", true)
  p.title:SetText("Shop")

  local hdr = text(p, Theme.fonts.text, "TOPLEFT", 16, -44, 180)
  hdr:SetText("Payout")
  Theme.Label(hdr)
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
  Theme.Label(cardsHdr)
  local packsHdr = text(p, Theme.fonts.small, "TOPLEFT", 200 + 2 * COL_W + 8 + 24, -46, 2 * COL_W + 8, "CENTER")
  packsHdr:SetText("Packs")
  Theme.Label(packsHdr)
  p.cardsHdr, p.packsHdr = cardsHdr, packsHdr

  p.offerCards, p.packOffers = {}, {}
  for i = 1, MAX_CARDS do
    local item = i
    p.offerCards[i] = makeOfferColumn(p, 200 + (i - 1) * (COL_W + 8), function()
      local run = main().run
      local offer = run and run.shop and run.shop.cards[item]
      local offerType = offer and offer.type
      shopAction(ns.Shop.buy, function(r)
        if offerType == "trinket" then
          ns.UI.TrinketRow.Pulse(#r.trinkets)
        elseif offerType == "card" then
          Screens.PulseDeckButton(r)
        else
          local held = r.consumables[#r.consumables]
          if held then ns.UI.Outcome.Play({ created = { held } }) end
        end
      end, offerType, item)
    end)
    if i <= 2 then
      p.packOffers[i] = makePackColumn(p, 200 + 2 * COL_W + 8 + 24 + (i - 1) * (COL_W + 8), function()
        shopAction(ns.Packs.open, nil, nil, item)
      end)
    end
  end
  buildVoucherTile(p)

  p.err = text(p, Theme.fonts.text, "BOTTOM", 0, 56, 560, "CENTER")
  Theme.setColor(p.err, RED)
  p.err:Hide()

  p.reroll = button(p, "Reroll", 150, 28, function()
    shopAction(ns.Shop.reroll, function()
      for i = 1, MAX_CARDS do
        if p.offerCards[i]:IsShown() then fadeIn(p.offerCards[i], (i - 1) * 0.06) end
      end
    end)
  end)
  p.reroll:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 200, 16)
  reasonTip(p.reroll)
  p.next = button(p, "Next Blind", 150, 28, nextBlind, "primary")
  p.next:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 16)
  addAbandon(p)
  return p
end

-- A playing-card offer shows the same CardWidget the Standard pack uses, scaled to the column.
local function releaseCard(c)
  if c.cardWidget then
    ns.UI.CardWidget.Release(c.cardWidget)
    c.cardWidget = nil
  end
end

local function showCard(c, card)
  local CardWidget = ns.UI.CardWidget
  local w = c.cardWidget
  if not w then
    w = CardWidget.Acquire(c)
    c.cardWidget = w
  end
  w:SetCard(card)
  w:SetBaseLevel(c:GetFrameLevel() + 3)
  w:SetScale(c:GetWidth() / CardWidget.WIDTH)
  w:ClearAllPoints()
  w:SetPoint("TOP", c, "TOP", 0, 0)
  w:Show()
end

local function setColumn(c, live)
  c.face:SetShown(live)
  c.name:SetShown(live)
  c.desc:SetShown(live and not c.compact)
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
  local slots = math.max(2, math.min(MAX_CARDS, math.max(ns.Vouchers.shopCardSlots(run), #shop.cards)))
  layoutShop(p, slots)
  refreshVoucher(p, run)
  for i = 1, MAX_CARDS do
    local c = p.offerCards[i]
    local offer = shop.cards[i]
    c:SetShown(i <= slots)
    setColumn(c, offer and true or false)
    if i > slots then c:Hide() end
    if not offer or offer.type ~= "card" or i > slots then releaseCard(c) end
    if offer then
      local info = Screens.ItemInfo(offer)
      local full
      if offer.type == "card" then
        full = false -- cards go to the deck: never "Slots full"
      elseif offer.type == "trinket" then
        full = #run.trinkets >= ns.Run.trinketSlots(run) + (offer.ed == "NEGATIVE" and 1 or 0)
      else
        full = #run.consumables >= ns.Consumables.slots(run)
      end
      local afford = run.gold >= offer.cost
      if offer.type == "card" then
        c.face:Hide()
        showCard(c, offer)
      else
        Screens.SkinFace(c.face, info)
      end
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

  -- Lucky Coin and Gambler's Charm make rerolls cheaper (Shop.reroll's formula).
  local rerollCost = math.max(0, shop.rerollCost - ns.Vouchers.rerollDelta(run))
  p.reroll:SetText("Reroll (" .. rerollCost .. "g)")
  local canReroll = run.gold >= rerollCost and not blockedByPack
  if canReroll then p.reroll:Enable() else p.reroll:Disable() end
  setReason(p.reroll, blockedByPack and BUY_ERRORS.pack or ((not canReroll) and BUY_ERRORS.gold or nil))
end

---------------------------------------------------------------------------
-- Won / lost

local newRunClicked = endRun

local function buildEnd()
  local p = makePanel("end", false)
  p.head = text(p, Theme.fonts.big, "TOP", 0, -48, 560, "CENTER")
  p.stage = text(p, Theme.fonts.title, "TOP", 0, -120, 560, "CENTER")
  Theme.Value(p.stage, false)
  p.deck = text(p, Theme.fonts.text, "TOP", 0, -156, 560, "CENTER")
  Theme.Label(p.deck)
  p.best = text(p, Theme.fonts.title, "TOP", 0, -192, 560, "CENTER")
  Theme.Value(p.best, true)
  Theme.Rule(p, -104, 96) -- under the headline
  p.new = button(p, "New Run", 160, 32, newRunClicked, "primary")
  p.new:SetPoint("BOTTOM", p, "BOTTOM", 0, 32)
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
  dim:SetColorTexture(Theme.bg[1], Theme.bg[2], Theme.bg[3], 0.82)
  local msg = f:CreateFontString(nil, "OVERLAY", Theme.fonts.big)
  msg:SetPoint("CENTER", f, "CENTER", 0, 20)
  msg:SetText("Queue popped!")
  Theme.setColor(msg, Theme.gold)
  local resume = Theme.NewButton(f, "Resume", 140, 32, "primary")
  resume:SetPoint("CENTER", f, "CENTER", 0, -32)
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
      ns.UI.HandView.SetDeckShown(true)
      current = "play"
      ns.UI.EditionFX.Wake() -- the hand's shimmer resumes
    end
    return
  end

  local key = entry[1]
  local previous = current
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
  ns.UI.HandView.SetDeckShown(false) -- and so does the deck pile on the play area
  ns.UI.EditionFX.Wake()
  p:SetAlpha(0)
  p:Show()
  Tween.To(p, { alpha = 1 }, FADE)
  -- The blind panels animate in; coming back from the shop they also settle.
  if name == "blind" then ns.UI.BlindSelect.Enter(p, run, previous == "shop") end
end

ns.UI.Screens = Screens
