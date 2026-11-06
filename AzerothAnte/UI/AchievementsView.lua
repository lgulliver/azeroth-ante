local _, ns = ...

-- The Achievements panel: all 16 voucher unlocks with condition, progress and reward.
-- Unlocked rows are gold, locked rows are dim.
local Theme = ns.UI.Theme
local AchievementsView = {}

local LEVEL = 700            -- over the screen panels (600), under the queue pause overlay (900)
local ROW_H, ROW_Y = 27, 46
local PAD = 12
local BAR_W = 104
local DIM = { 0.55, 0.5, 0.42 }
local GREEN = { 0.3, 0.75, 0.3 }
-- Historical bests, not live values: only the highest ever reached counts.
local BEST = { GLOW_UP = true, MONEY_TREE = true }

local panel

local function db()
  return AzerothAnteDB or {}
end

local function makeRow(p, i)
  local row = CreateFrame("Frame", nil, p)
  row:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(ROW_Y + (i - 1) * ROW_H))
  row:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -(ROW_Y + (i - 1) * ROW_H))
  row:SetHeight(ROW_H - 2)
  row:EnableMouse(true)
  Theme.Raised(row)
  row.name = row:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
  row.name:SetWidth(200)
  row.name:SetJustifyH("LEFT")
  row.cond = row:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
  row.cond:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -13)
  row.cond:SetWidth(330)
  row.cond:SetJustifyH("LEFT")
  row.bar = CreateFrame("Frame", nil, row)
  row.bar:SetSize(BAR_W, 10)
  row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 352, -4)
  Theme.Inset(row.bar)
  row.fill = row.bar:CreateTexture(nil, "ARTWORK")
  row.fill:SetPoint("LEFT", row.bar, "LEFT", 1, 0)
  row.fill:SetHeight(8)
  row.count = row:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
  row.count:SetPoint("TOPLEFT", row, "TOPLEFT", 352, -14)
  row.count:SetWidth(BAR_W)
  row.count:SetJustifyH("CENTER")
  row.unlocks = row:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
  row.unlocks:SetPoint("TOPLEFT", row, "TOPLEFT", 464, -3)
  row.unlocks:SetWidth(132)
  row.unlocks:SetHeight(22)
  row.unlocks:SetJustifyH("LEFT")
  row.unlocks:SetJustifyV("TOP")
  row:SetScript("OnEnter", function(self)
    if self.id then ns.UI.Screens.ShowVoucherTip(self, self.id, "ANCHOR_LEFT") end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

local function create()
  local m = ns.UI.Main
  local p = CreateFrame("Frame", nil, m.content)
  -- The same area as the deck-select screen, so the whole right-hand side is covered.
  p:SetPoint("TOPLEFT", m.trinketRow, "TOPLEFT", 0, 0)
  p:SetPoint("BOTTOMRIGHT", m.buttons, "BOTTOMRIGHT", 0, 0)
  p:SetFrameLevel(m.content:GetFrameLevel() + LEVEL)
  Theme.Inset(p)
  p:EnableMouse(true)
  p.title = p:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
  p.title:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -12)
  Theme.Value(p.title, true)
  local close = Theme.NewButton(p, "Close", 72, 24)
  close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() AchievementsView.Hide() end)
  p.close = close
  p.rows = {}
  for i, id in ipairs(ns.Achievements.order) do
    p.rows[i] = makeRow(p, i)
    p.rows[i].id = id
  end
  m.frame:HookScript("OnHide", function() AchievementsView.Hide() end)
  p:Hide()
  return p
end

local function fill(row, id)
  local def = ns.Achievements.def[id]
  local have, need = ns.Profile.achievementProgress(db(), id)
  local done = ns.Profile.hasAchievement(db(), id)
  local shown = done and math.max(have, need) or have
  row.id = id
  row.done = done
  row.name:SetText(def.name)
  row.cond:SetText(def.desc)
  row.unlocks:SetText((done and "Unlocked: " or "Unlocks: ") .. ns.Vouchers.def[def.unlocks].desc)
  local text = (BEST[id] and "best: " or "") .. math.min(shown, need) .. " / " .. need
  if need == 1 and not def.counter then text = done and "Done" or "Not yet" end
  row.count:SetText(text)
  local frac = need > 0 and math.min(1, have / need) or 0
  if done then frac = 1 end
  row.fill:SetWidth(math.max(1, (BAR_W - 2) * frac))
  row.fill:SetShown(frac > 0)
  local gold, dim = Theme.gold, DIM
  Theme.setColor(row.name, done and gold or dim)
  Theme.setColor(row.cond, done and Theme.parchment or dim)
  Theme.setColor(row.count, done and gold or dim)
  Theme.setColor(row.unlocks, done and Theme.parchment or dim)
  local c = done and gold or GREEN
  row.fill:SetColorTexture(c[1], c[2], c[3], done and 1 or 0.8)
  row:SetAlpha(done and 1 or 0.8)
end

function AchievementsView.Refresh()
  if not panel or not panel:IsShown() then return end
  local unlocked = 0
  for i, id in ipairs(ns.Achievements.order) do
    fill(panel.rows[i], id)
    if panel.rows[i].done then unlocked = unlocked + 1 end
  end
  panel.title:SetText("Achievements (" .. unlocked .. " / " .. #ns.Achievements.order .. ")")
end

function AchievementsView.IsShown()
  return panel ~= nil and panel:IsShown()
end

function AchievementsView.Panel() return panel end

function AchievementsView.Hide()
  if panel and panel:IsShown() then panel:Hide() end
end

function AchievementsView.Toggle()
  if panel and panel:IsShown() then
    AchievementsView.Hide()
    return
  end
  local m = ns.UI.Main
  if not m or not m.content then return end
  panel = panel or create()
  panel:Show()
  AchievementsView.Refresh()
end

-- Unlocked count for the sidebar button.
function AchievementsView.Count()
  local n = 0
  for _, id in ipairs(ns.Achievements.order) do
    if ns.Profile.hasAchievement(db(), id) then n = n + 1 end
  end
  return n, #ns.Achievements.order
end

ns.UI.AchievementsView = AchievementsView
