local _, ns = ...

ns.UI = ns.UI or {}

local Theme = {
  gold = { 1, 0.82, 0 },
  parchment = { 0.95, 0.91, 0.8 },
  bg = { 0.08, 0.06, 0.05, 0.95 },
  chips = { 0.2, 0.55, 1 },
  mult = { 1, 0.25, 0.2 },
  rarity = {
    common = { 1, 1, 1 },
    uncommon = { 0.12, 1, 0 },
    rare = { 0, 0.44, 0.87 },
    legendary = { 1, 0.5, 0 },
  },
  fonts = {
    title = "GameFontNormalLarge",
    text = "GameFontHighlight",
    small = "GameFontHighlightSmall",
    big = "GameFontNormalHuge",
  },
  -- Fixed design size; all layout is in these units and scaled to the window.
  -- Card textures are 128x256 with the card in the top 128x179 (5:7).
  cardV = 179 / 256,
  width = 900,
  height = 560,
  sidebarFraction = 0.28,
  margin = 10,
  titleHeight = 30,
  backdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  },
}

-- Applies an {r, g, b[, a]} colour to a texture or font string.
function Theme.setColor(region, c, isTexture)
  if isTexture then
    region:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  else
    region:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  end
end

-- The look of an empty trinket or consumable slot: a dark inset with a thin,
-- soft gold outline at low alpha. One helper so both rows match. The returned
-- frame fills `parent`; Show/Hide it as the slot empties and fills.
local FLAT = "Interface\\Buttons\\WHITE8x8"
Theme.emptySlotEdgeAlpha = 0.28
function Theme.EmptySlot(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints(parent)
  f.isEmptySlot = true
  local inset = f:CreateTexture(nil, "BACKGROUND")
  inset:SetAllPoints(f)
  inset:SetColorTexture(0.04, 0.03, 0.02, 0.6)
  local g, a = Theme.gold, Theme.emptySlotEdgeAlpha
  local function edge(p1, p2, w, h)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetPoint(p1, f, p1, 0, 0)
    t:SetPoint(p2, f, p2, 0, 0)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    t:SetColorTexture(g[1], g[2], g[3], a)
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 1)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
  return f
end

ns.UI.Theme = Theme
