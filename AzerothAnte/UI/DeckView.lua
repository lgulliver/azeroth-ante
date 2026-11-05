local _, ns = ...

local Theme = ns.UI.Theme
local CardWidget = ns.UI.CardWidget
local DeckView = {}

local LEVEL = 700            -- over the screen panels (600), under the queue pause overlay (900)
local PAD = 10
local GRID_TOP = 68          -- title, suit counts and type counts sit above the grid
local MAX_SCALE = 0.45
local GAP_X, GAP_Y = 4, 3
local ENH_ORDER = { "BONUS", "MULT", "WILD", "GLASS", "STEEL", "STONE", "GOLD", "LUCKY" }
local ED_ORDER = { "FOIL", "HOLO", "POLY", "NEGATIVE" }
local SEAL_ORDER = { "GOLD", "RED", "BLUE", "PURPLE" }

local panel
local minis = {}

local function release()
  for i = #minis, 1, -1 do
    CardWidget.Release(minis[i])
    minis[i] = nil
  end
end

local function byRank(a, b)
  if a.rank ~= b.rank then return a.rank < b.rank end
  return (a.id or 0) < (b.id or 0)
end

-- One row per suit (empty rows are dropped); Stone cards get a row of their own.
local function groupRows(deck)
  local bySuit, stone = {}, {}
  for _, card in ipairs(deck) do
    if ns.Cards.isStone(card) then
      stone[#stone + 1] = card
    else
      bySuit[card.suit] = bySuit[card.suit] or {}
      table.insert(bySuit[card.suit], card)
    end
  end
  local rows = {}
  for _, suit in ipairs(ns.Cards.SUITS) do
    if bySuit[suit] then rows[#rows + 1] = bySuit[suit] end
  end
  if #stone > 0 then rows[#rows + 1] = stone end
  for _, row in ipairs(rows) do table.sort(row, byRank) end
  return rows, bySuit, #stone
end

local function typeCounts(deck)
  local n = { enh = {}, ed = {}, seal = {} }
  for _, card in ipairs(deck) do
    if card.enh then n.enh[card.enh] = (n.enh[card.enh] or 0) + 1 end
    if card.ed then n.ed[card.ed] = (n.ed[card.ed] or 0) + 1 end
    if card.seal then n.seal[card.seal] = (n.seal[card.seal] or 0) + 1 end
  end
  local parts = {}
  for _, group in ipairs({ { "enh", ENH_ORDER }, { "ed", ED_ORDER }, { "seal", SEAL_ORDER } }) do
    for _, id in ipairs(group[2]) do
      local count = n[group[1]][id]
      if count then parts[#parts + 1] = ns.CardTypes[group[1]][id].name .. " " .. count end
    end
  end
  return #parts > 0 and table.concat(parts, "   ") or "No enhanced cards"
end

local function build(run)
  release()
  local deck = run and run.deck or {}
  local rows, bySuit, stoneCount = groupRows(deck)
  panel.deckTitle:SetText("Deck: " .. #deck .. " cards")
  local suits = {}
  for _, suit in ipairs(ns.Cards.SUITS) do
    suits[#suits + 1] = ns.Cards.SUIT_NAMES[suit] .. " " .. (bySuit[suit] and #bySuit[suit] or 0)
  end
  suits[#suits + 1] = "Stone " .. stoneCount
  panel.suitCounts:SetText(table.concat(suits, "   "))
  panel.typeCounts:SetText(typeCounts(deck))
  if #rows == 0 then return end

  local maxPer = 0
  for _, row in ipairs(rows) do maxPer = math.max(maxPer, #row) end
  local availW = panel:GetWidth() - 2 * PAD
  local availH = panel:GetHeight() - GRID_TOP - PAD / 2
  local s = math.min(MAX_SCALE, (availH - (#rows - 1) * GAP_Y) / (#rows * CardWidget.HEIGHT))
  local cw, ch = CardWidget.WIDTH * s, CardWidget.HEIGHT * s
  local pitch = cw + GAP_X
  if maxPer > 1 and (maxPer - 1) * pitch + cw > availW then pitch = (availW - cw) / (maxPer - 1) end

  local base = panel:GetFrameLevel() + 2
  for r, row in ipairs(rows) do
    local y = GRID_TOP + (r - 1) * (ch + GAP_Y)
    for c, card in ipairs(row) do
      local w = CardWidget.Acquire(panel)
      w:SetMini(s)
      w:SetCard(card)
      w:SetBaseLevel(base + c * 4)
      w:ClearAllPoints()
      w:SetPoint("TOPLEFT", panel, "TOPLEFT", (PAD + (c - 1) * pitch) / s, -y / s) -- offsets are in the widget's own scale
      minis[#minis + 1] = w
    end
  end
  ns.UI.EditionFX.Wake()
end

local function create()
  local m = ns.UI.Main
  local p = CreateFrame("Frame", nil, m.content, "BackdropTemplate")
  p:SetSize(m.playArea:GetWidth(), m.playArea:GetHeight())
  p:SetPoint("TOPLEFT", m.playArea, "TOPLEFT", 0, 0)
  p:SetFrameLevel(m.content:GetFrameLevel() + LEVEL)
  p:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
  })
  p:SetBackdropColor(0.1, 0.08, 0.06, 0.98)
  p:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
  p:EnableMouse(true) -- swallows clicks meant for what is underneath

  p.deckTitle = p:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
  p.deckTitle:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -8)
  Theme.setColor(p.deckTitle, Theme.gold)
  p.suitCounts = p:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
  p.suitCounts:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -32)
  p.typeCounts = p:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
  p.typeCounts:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -46)
  p.typeCounts:SetWidth(p:GetWidth() - 2 * PAD)
  p.typeCounts:SetJustifyH("LEFT")
  Theme.setColor(p.typeCounts, Theme.parchment)

  local close = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  close:SetSize(70, 22)
  close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -6)
  close:SetText("Close")
  close:SetScript("OnClick", function() DeckView.Hide() end)
  p.close = close

  m.frame:HookScript("OnHide", function() DeckView.Hide() end)
  p:Hide()
  return p
end

function DeckView.IsShown()
  return panel ~= nil and panel:IsShown()
end

function DeckView.Hide()
  if not panel or not panel:IsShown() then return end
  panel:Hide()
  release()
end

-- Rebuilds the open panel after the deck changes.
function DeckView.Refresh(run)
  if panel and panel:IsShown() then build(run) end
end

function DeckView.Toggle(run)
  if panel and panel:IsShown() then
    DeckView.Hide()
    return
  end
  local m = ns.UI.Main
  if not m or not m.content then return end
  local HandView, Tally = ns.UI.HandView, ns.UI.Tally
  if (HandView and HandView.IsBusy()) or (Tally and Tally.IsBusy()) then return end -- the hand is resolving
  panel = panel or create()
  panel:Show()
  build(run or m.run)
end

ns.UI.DeckView = DeckView
