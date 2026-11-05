local _, ns = ...

local Tween = ns.UI.Tween
local CardWidget = {}

local MEDIA = "Interface\\AddOns\\AzerothAnte\\Media\\"
local WIDTH, HEIGHT = 80, 112
local LIFT_SELECTED, LIFT_HOVER, LIFT_TIME = 24, 8, 0.08
local SUIT_COLORS = {
  S = { 0.2, 0.2, 0.3 },
  C = { 0.15, 0.45, 0.25 },
  H = { 0.85, 0.15, 0.2 },
  D = { 0.9, 0.45, 0.1 },
}
local BORDER = { 0.1, 0.08, 0.06 }
local BORDER_SELECTED = { 1, 0.82, 0 }
local PAPER = ns.UI.Theme.parchment
local PAPER_GLASS = { 0.12, 0.18, 0.24 } -- opaque, so the see-through Glass face hides cards behind it
local SEAL_SIZE = 20
local TIP_DELAY = 0.4

CardWidget.WIDTH, CardWidget.HEIGHT = WIDTH, HEIGHT
CardWidget.LIFT_SELECTED = LIFT_SELECTED
CardWidget.SUIT_COLORS = SUIT_COLORS

-- A widget is a Button (the fixed hit area, tweened for layout) holding a
-- `body` (tweened for hover/selection lift) holding a `face` (scale pop). The
-- hit area never moves with the lift, so hovering cannot flicker.
local Methods = {}
local pool = {}

local function liftY(w)
  if w.mini then return 0 end
  if w.selected then return LIFT_SELECTED end
  if w.hover then return LIFT_HOVER end
  return 0
end

function Methods.ApplyLevel(w)
  local level = (w.baseLevel or 1) + (w.hover and 40 or 0) + (w.topmost and 200 or 0)
  w:SetFrameLevel(level)
  w.body:SetFrameLevel(level + 1)
  w.face:SetFrameLevel(level + 2)
  local fx = w.face.fx
  if fx then fx.root:SetFrameLevel(level + 3) end
end

function Methods.SetBaseLevel(w, level)
  w.baseLevel = level
  w:ApplyLevel()
end

function Methods.RefreshLift(w, instant)
  if w.locked or w.mini then return end
  local y = liftY(w)
  if instant then
    Tween.Cancel(w.body)
    w.body:SetPoint("BOTTOM", w, "BOTTOM", 0, y)
  else
    Tween.To(w.body, { x = 0, y = y }, LIFT_TIME)
  end
end

-- Enhancement, edition and seal names and descriptions, shown after a short delay.
local function showTip(w)
  local card = w.card
  if not card or not w.hover or w.released then return end
  local CardTypes = ns.CardTypes
  local defs = { CardTypes.enh[card.enh], CardTypes.ed[card.ed], CardTypes.seal[card.seal] }
  if not next(defs) then return end
  local gold = ns.UI.Theme.gold
  GameTooltip:SetOwner(w, "ANCHOR_TOP", 0, LIFT_SELECTED + 4) -- anchored to the fixed hit area, not the lifting body
  for i = 1, 3 do
    local def = defs[i]
    if def then
      GameTooltip:AddLine(def.name, gold[1], gold[2], gold[3])
      GameTooltip:AddLine(def.desc, 1, 1, 1, true)
    end
  end
  GameTooltip:Show()
end

local function hideTip(w)
  w.tipToken = (w.tipToken or 0) + 1
  if GameTooltip:GetOwner() == w then GameTooltip:Hide() end
end

local function armTip(w)
  local card = w.card
  if not card or not (card.enh or card.ed or card.seal) then return end
  w.tipToken = (w.tipToken or 0) + 1
  local token = w.tipToken
  C_Timer.After(TIP_DELAY, function()
    if w.tipToken == token then showTip(w) end
  end)
end

function Methods.SetCard(w, card)
  local key = ("%s%s|%s|%s|%s"):format(card.rank, card.suit, card.enh or "", card.ed or "", card.seal or "")
  if w.card == card and w.cardKey == key then return end
  w.card, w.cardKey = card, key
  local FX = ns.UI.EditionFX
  local stone = card.enh == "STONE"
  local enh = ns.CardTypes.enh[card.enh] and card.enh or nil
  w.art:SetTexture(MEDIA .. "Face_" .. (enh or "Plain"))
  local p = enh == "GLASS" and PAPER_GLASS or PAPER
  w.paper:SetColorTexture(p[1], p[2], p[3], 1)

  local c = SUIT_COLORS[card.suit] or SUIT_COLORS.S
  local label = ns.Cards.label(card)
  w.rankTL:SetText(label)
  w.rankBR:SetText(label)
  w.rankTL:SetTextColor(c[1], c[2], c[3])
  w.rankBR:SetTextColor(c[1], c[2], c[3])
  local path = MEDIA .. "Suit_" .. card.suit
  w.suitBig:SetTexture(path)
  w.suitBig:SetVertexColor(c[1], c[2], c[3])
  w.suitSmall:SetTexture(path)
  w.suitSmall:SetVertexColor(c[1], c[2], c[3])
  -- Stone keeps its rank and suit in the data but shows neither.
  w.rankTL:SetShown(not stone)
  w.rankBR:SetShown(not stone)
  w.suitBig:SetShown(not stone)
  w.suitSmall:SetShown(not stone)

  if card.seal and ns.CardTypes.seal[card.seal] then
    w.seal:SetTexture(MEDIA .. "Seal_" .. card.seal)
    w.seal:Show()
  else
    w.seal:Hide()
  end

  FX.Attach(w.face, card.ed)
  if w.back:IsShown() then FX.SetShown(w.face, false) end
  if w.hover then armTip(w) end
end

function Methods.SetSelected(w, selected)
  selected = selected and true or false
  w.selected = selected
  local c = selected and BORDER_SELECTED or BORDER
  w.border:SetColorTexture(c[1], c[2], c[3], 1)
  w:RefreshLift()
end

function Methods.SetDebuffed(w, debuffed)
  w.debuffed = debuffed and true or false
  if w.debuffed then w.shade:Show() else w.shade:Hide() end
end

function Methods.SetFaceUp(w, up)
  if up then w.back:Hide() else w.back:Show() end
  ns.UI.EditionFX.SetShown(w.face, up and true or false)
end

-- Small, no-lift version for the deck view (hover still raises it above its
-- neighbours and shows the tooltip). Reset undoes it.
function Methods.SetMini(w, scale)
  w.mini = true
  w:SetScale(scale)
  w:SetHitRectInsets(0, 0, 0, 0)
end

-- Score pop: quick scale up and back.
function Methods.Pop(w)
  local face = w.face
  Tween.To(face, { scale = 1.2 }, 0.07, function()
    Tween.To(face, { scale = 1 }, 0.12)
  end)
end

function Methods.Reset(w)
  Tween.Cancel(w)
  Tween.Cancel(w.body)
  Tween.Cancel(w.face)
  hideTip(w)
  ns.UI.EditionFX.Detach(w.face)
  w.card, w.cardKey, w.mini = nil, nil, false
  w.selected, w.hover, w.locked, w.topmost, w.debuffed = false, false, false, false, false
  w:SetScale(1)
  w:SetHitRectInsets(0, 0, -LIFT_SELECTED, 0)
  w.seal:Hide()
  w.lx, w.ly = nil, nil
  w.onClick = nil
  w.border:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
  w.shade:Hide()
  w.back:Hide()
  w.body:ClearAllPoints()
  w.body:SetPoint("BOTTOM", w, "BOTTOM", 0, 0)
  w.face:SetScale(1)
  w:SetAlpha(1)
  w:EnableMouse(true)
end

local function create(parent)
  local w = CreateFrame("Button", nil, parent)
  w:SetSize(WIDTH, HEIGHT)
  w:RegisterForClicks("LeftButtonUp")
  -- The visible card rises when selected; keep its top clickable.
  w:SetHitRectInsets(0, 0, -LIFT_SELECTED, 0)

  local body = CreateFrame("Frame", nil, w)
  body:SetSize(WIDTH, HEIGHT)
  body:SetPoint("BOTTOM", w, "BOTTOM", 0, 0)
  w.body = body

  local face = CreateFrame("Frame", nil, body)
  face:SetSize(WIDTH, HEIGHT)
  face:SetPoint("CENTER", body, "CENTER")
  w.face = face

  w.border = face:CreateTexture(nil, "BACKGROUND")
  w.border:SetAllPoints()
  w.paper = face:CreateTexture(nil, "BORDER") -- opaque backing under the face art
  w.paper:SetPoint("TOPLEFT", 2, -2)
  w.paper:SetPoint("BOTTOMRIGHT", -2, 2)
  w.art = face:CreateTexture(nil, "ARTWORK", nil, -1)
  w.art:SetAllPoints()

  w.suitBig = face:CreateTexture(nil, "ARTWORK")
  w.suitBig:SetSize(44, 44)
  w.suitBig:SetPoint("CENTER", face, "CENTER", 0, 0)
  w.suitSmall = face:CreateTexture(nil, "ARTWORK")
  w.suitSmall:SetSize(14, 14)
  w.suitSmall:SetPoint("TOPLEFT", face, "TOPLEFT", 7, -28)

  w.rankTL = face:CreateFontString(nil, "OVERLAY", ns.UI.Theme.fonts.title)
  w.rankTL:SetPoint("TOPLEFT", face, "TOPLEFT", 6, -7)
  w.rankBR = face:CreateFontString(nil, "OVERLAY", ns.UI.Theme.fonts.title)
  w.rankBR:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", -6, 7)

  w.seal = face:CreateTexture(nil, "OVERLAY", nil, 2)
  w.seal:SetSize(SEAL_SIZE, SEAL_SIZE)
  w.seal:SetPoint("TOPRIGHT", face, "TOPRIGHT", -3, -3)
  w.shade = face:CreateTexture(nil, "OVERLAY", nil, 5)
  w.shade:SetPoint("TOPLEFT", 2, -2)
  w.shade:SetPoint("BOTTOMRIGHT", -2, 2)
  w.shade:SetColorTexture(0.35, 0.35, 0.35, 0.65)
  w.back = face:CreateTexture(nil, "OVERLAY", nil, 7)
  w.back:SetAllPoints()
  w.back:SetTexture(MEDIA .. "CardBack")

  for k, v in pairs(Methods) do w[k] = v end

  w:SetScript("OnEnter", function(self)
    if self.locked then return end
    self.hover = true
    self:ApplyLevel()
    self:RefreshLift()
    armTip(self)
  end)
  w:SetScript("OnLeave", function(self)
    self.hover = false
    self:ApplyLevel()
    self:RefreshLift()
    hideTip(self)
  end)
  w:SetScript("OnClick", function(self)
    if self.onClick and not self.locked then self.onClick(self) end
  end)
  w:Reset()
  return w
end

function CardWidget.Acquire(parent)
  local w = table.remove(pool)
  if w then
    w:SetParent(parent)
  else
    w = create(parent)
  end
  w.released = false
  w:Show()
  return w
end

function CardWidget.Release(w)
  if w.released then return end
  w.released = true
  w:Reset()
  w:Hide()
  w:ClearAllPoints()
  pool[#pool + 1] = w
end

ns.UI.CardWidget = CardWidget
