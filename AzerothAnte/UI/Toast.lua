local _, ns = ...

-- Gold achievement toasts at the top of the window. Several queue and play one
-- after another; the toast never takes the mouse, so it cannot block input.
local Theme = ns.UI.Theme
local Tween = ns.UI.Tween
local Toast = {}

local W, H = 340, 46
local TOP_Y = -(Theme.titleHeight + 6)
local RISE = 14
local IN_T, HOLD, OUT_T = 0.25, 3.2, 0.4

local frame
local queue, queued = {}, {}   -- ids waiting, and every id queued or showing
local showing = nil            -- the id on screen

local function content()
  return ns.UI.Main and ns.UI.Main.content
end

local function build()
  local m = ns.UI.Main
  local f = CreateFrame("Frame", nil, m.content)
  f:SetSize(W, H)
  f:SetPoint("TOP", m.content, "TOP", 0, TOP_Y)
  f:SetFrameLevel(m.content:GetFrameLevel() + 950)
  f:EnableMouse(false)
  Theme.Raised(f)
  Theme.Selected(f, true)
  f.title = f:CreateFontString(nil, "OVERLAY", Theme.fonts.text)
  f.title:SetPoint("TOP", f, "TOP", 0, -8)
  f.title:SetWidth(W - 16)
  f.title:SetJustifyH("CENTER")
  Theme.Value(f.title, true)
  f.sub = f:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
  f.sub:SetPoint("TOP", f, "TOP", 0, -26)
  f.sub:SetWidth(W - 16)
  f.sub:SetJustifyH("CENTER")
  Theme.setColor(f.sub, Theme.parchment)
  f:Hide()
  m.frame:HookScript("OnHide", function() Toast.Clear() end)
  frame = f
  return f
end

local function sound()
  if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.UI_70_ARTIFACT_FORGE_TRAIT_RANK_UP then
    pcall(PlaySound, SOUNDKIT.UI_70_ARTIFACT_FORGE_TRAIT_RANK_UP)
  end
end

local function finish(id)
  if showing ~= id then return end
  showing = nil
  queued[id] = nil
  if frame then frame:Hide() end
  Toast.Next()
end

function Toast.Next()
  if showing then return end
  local id = table.remove(queue, 1)
  if not id then return end
  local def = ns.Achievements.def[id]
  local m = ns.UI.Main
  if not def or not m or not m.frame or not m.frame:IsShown() or not content() then
    queued[id] = nil
    return Toast.Next()
  end
  local f = frame or build()
  showing = id
  if AzerothAnteDB then ns.Profile.markAchievementSeen(AzerothAnteDB, id) end
  f.title:SetText("Achievement unlocked: " .. def.name)
  f.sub:SetText("Unlocks " .. ns.Vouchers.def[def.unlocks].name)
  Tween.Cancel(f)
  f:SetPoint("TOP", content(), "TOP", 0, TOP_Y - RISE)
  f:SetAlpha(0)
  f:Show()
  sound()
  Tween.To(f, { alpha = 1, y = TOP_Y }, IN_T, function()
    Tween.To(f, { alpha = 0 }, OUT_T, function() finish(id) end, HOLD)
  end, 0, function() finish(id) end)
end

-- Queues a toast. Dropped (but left unseen for Toast.ShowUnseen) while the window is closed.
function Toast.Achievement(id)
  local m = ns.UI.Main
  if queued[id] or not ns.Achievements.def[id] then return end
  if not m or not m.frame or not m.frame:IsShown() or not m.content then return end
  queued[id] = true
  queue[#queue + 1] = id
  if ns.UI.AchievementsView then ns.UI.AchievementsView.Refresh() end
  Toast.Next()
end

-- Achievements unlocked while the window was closed.
function Toast.ShowUnseen()
  if not AzerothAnteDB then return end
  for _, id in ipairs(ns.Profile.newAchievements(AzerothAnteDB)) do Toast.Achievement(id) end
end

function Toast.Clear()
  queue, queued, showing = {}, {}, nil
  if frame then
    Tween.Cancel(frame)
    frame:Hide()
  end
end

function Toast.Current() return showing end
function Toast.Pending() return #queue end
function Toast.Frame() return frame end

ns.UI.Toast = Toast
