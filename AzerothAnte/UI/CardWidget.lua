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

CardWidget.WIDTH, CardWidget.HEIGHT = WIDTH, HEIGHT
CardWidget.LIFT_SELECTED = LIFT_SELECTED
CardWidget.SUIT_COLORS = SUIT_COLORS

-- A widget is a Button (the fixed hit area, tweened for layout) holding a
-- `body` (tweened for hover/selection lift) holding a `face` (scale pop). The
-- hit area never moves with the lift, so hovering cannot flicker.
local Methods = {}
local pool = {}

local function liftY(w)
  if w.selected then return LIFT_SELECTED end
  if w.hover then return LIFT_HOVER end
  return 0
end

function Methods.ApplyLevel(w)
  local level = (w.baseLevel or 1) + (w.hover and 40 or 0) + (w.topmost and 200 or 0)
  w:SetFrameLevel(level)
  w.body:SetFrameLevel(level + 1)
  w.face:SetFrameLevel(level + 2)
end

function Methods.SetBaseLevel(w, level)
  w.baseLevel = level
  w:ApplyLevel()
end

function Methods.RefreshLift(w, instant)
  if w.locked then return end
  local y = liftY(w)
  if instant then
    Tween.Cancel(w.body)
    w.body:SetPoint("BOTTOM", w, "BOTTOM", 0, y)
  else
    Tween.To(w.body, { x = 0, y = y }, LIFT_TIME)
  end
end

function Methods.SetCard(w, card)
  w.card = card
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
  w.card, w.selected, w.hover, w.locked, w.topmost, w.debuffed = nil, false, false, false, false, false
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
  local paper = face:CreateTexture(nil, "BORDER")
  paper:SetPoint("TOPLEFT", 2, -2)
  paper:SetPoint("BOTTOMRIGHT", -2, 2)
  paper:SetColorTexture(ns.UI.Theme.parchment[1], ns.UI.Theme.parchment[2], ns.UI.Theme.parchment[3], 1)

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
  end)
  w:SetScript("OnLeave", function(self)
    self.hover = false
    self:ApplyLevel()
    self:RefreshLift()
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
