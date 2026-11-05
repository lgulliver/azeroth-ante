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

ns.UI.Theme = Theme
