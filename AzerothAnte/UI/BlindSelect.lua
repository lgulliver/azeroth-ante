local _, ns = ...

-- The blind-select screen: three tall panels (Small, Big, Boss), Balatro style.
-- The current blind lifts, glows and carries the Play button; upcoming ones are
-- dimmed; beaten ones are dimmed under a gold DEFEATED stamp.
--
-- Frame structure per panel:
--   slot   (tweened: position and fade for the entrance)
--     glow   soft gold halo behind the body (current only)
--     body   (CENTER-anchored, scaled for the settle pop; dimmed via its alpha)
--     stamp  (above the body; scaled for the landing pop)
local Theme = ns.UI.Theme
local Tween = ns.UI.Tween
local BlindSelect = {}

local MEDIA = "Interface\\AddOns\\AzerothAnte\\Media\\"
local FLAT = "Interface\\Buttons\\WHITE8x8"

local PANEL_W, PANEL_H, GAP = 184, 330, 12
local TOP_Y = -46                       -- slot top, below the stage header
local LIFT = 10                         -- the current panel sits this much higher
local CHIP = 76
local RISE = 14                         -- entrance: panels rise this far
local ENTER_T, STAGGER = 0.25, 0.06
local POP_UP, POP_DOWN, POP_SCALE = 0.1, 0.14, 1.06
local STAMP_T, STAMP_FROM = 0.2, 2.4

local RED = { 1, 0.25, 0.2 }
local RED_EDGE = { 0.65, 0.18, 0.15 }
local EDGE = { 0.4, 0.33, 0.2 }
local GOLD_HEX = "|cffffd100"
local NAMES = { "Small Blind", "Big Blind" }
local CHIPS = { "Chip_SMALL", "Chip_BIG", "Chip_BOSS" }
local DIM = { CURRENT = 1, UPCOMING = 0.6, DEFEATED = 0.45 }

-- Chip tint per boss (SetVertexColor multiplies the near-white Chip_BOSS base).
BlindSelect.BOSS_TINT = {
  HOGGER = { 1, 0.9, 0.3 },       -- yellow
  VANCLEEF = { 0.35, 0.55, 1 },   -- blue
  ARUGAL = { 0.75, 0.4, 1 },      -- violet
  VAELASTRASZ = { 1, 0.28, 0.28 }, -- red
  MUTANUS = { 0.35, 1, 0.35 },    -- green
  HEROD = { 1, 0.55, 0.78 },      -- pink
  RIVENDARE = { 0.35, 0.95, 0.95 }, -- cyan
  ONYXIA = { 0.5, 0.5, 0.58 },    -- slate
  RAGNAROS = { 1, 0.5, 0.1 },     -- orange
}
local NO_TINT = { 1, 1, 1 }

local function fontPath()
  local f = GameFontNormalLarge
  if type(f) == "table" and f.GetFont then return (f:GetFont()) end
  return "Fonts\\FRIZQT__.TTF"
end

local function text(parent, font, point, x, y, width, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint(point, parent, point, x, y)
  if width then fs:SetWidth(width) end
  fs:SetJustifyH(justify or "CENTER")
  return fs
end

local function stateOf(run, i)
  if i < run.blind then return "DEFEATED" end
  return i == run.blind and "CURRENT" or "UPCOMING"
end

local function slotY(current)
  return TOP_Y + (current and LIFT or 0)
end

local function placeSlot(slot, dx, y)
  slot:ClearAllPoints()
  slot:SetPoint("TOP", slot:GetParent(), "TOP", dx, y)
end

---------------------------------------------------------------------------
-- Build

local function makeBlind(p, i, host)
  local dx = (i - 2) * (PANEL_W + GAP)
  local slot = CreateFrame("Frame", nil, p)
  slot:SetSize(PANEL_W, PANEL_H)
  slot.dx = dx
  placeSlot(slot, dx, TOP_Y)

  -- Soft glow: stacked translucent gold rims behind the body.
  local glow = CreateFrame("Frame", nil, slot)
  glow:SetAllPoints(slot)
  glow:SetFrameLevel(slot:GetFrameLevel()) -- pinned under the body
  for k, pad in ipairs({ 7, 4, 2 }) do
    local t = glow:CreateTexture(nil, "BACKGROUND")
    t:SetPoint("TOPLEFT", slot, "TOPLEFT", -pad, pad)
    t:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", pad, -pad)
    t:SetColorTexture(Theme.gold[1], Theme.gold[2], Theme.gold[3], 0.07 * k)
  end
  glow:Hide()
  slot.glow = glow

  local body = CreateFrame("Frame", nil, slot, "BackdropTemplate")
  body:SetFrameLevel(glow:GetFrameLevel() + 1)
  body:SetSize(PANEL_W, PANEL_H)
  body:SetPoint("CENTER", slot, "CENTER", 0, 0)
  body:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 2 })
  slot.body = body

  local bar = body:CreateTexture(nil, "ARTWORK") -- the boss's red accent
  bar:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -2)
  bar:SetPoint("TOPRIGHT", body, "TOPRIGHT", -2, -2)
  bar:SetHeight(4)
  bar:SetColorTexture(RED[1], RED[2], RED[3], 0.9)
  bar:Hide()
  slot.bar = bar

  slot.tag = text(body, Theme.fonts.small, "TOP", 0, -14, PANEL_W - 12)
  slot.kind = text(body, Theme.fonts.small, "TOP", 0, -28, PANEL_W - 12)
  slot.chip = body:CreateTexture(nil, "ARTWORK")
  slot.chip:SetSize(CHIP, CHIP)
  slot.chip:SetPoint("TOP", body, "TOP", 0, -46)
  slot.chip:SetTexture(MEDIA .. CHIPS[i])
  slot.chip:SetTexCoord(0, 1, 0, 1) -- its own square texture: the full range, not cardV
  slot.name = text(body, Theme.fonts.title, "TOP", 0, -130, PANEL_W - 20)
  slot.name:SetHeight(40)
  slot.name:SetJustifyV("TOP")
  slot.rule = text(body, Theme.fonts.small, "TOP", 0, -172, PANEL_W - 24)
  slot.rule:SetHeight(32)
  slot.rule:SetJustifyV("TOP")
  Theme.setColor(slot.rule, RED)
  local label = text(body, Theme.fonts.small, "TOP", 0, -212, PANEL_W - 12)
  label:SetText("Score at least")
  Theme.setColor(label, Theme.parchment)
  slot.target = text(body, Theme.fonts.big, "TOP", 0, -228, PANEL_W - 12)
  slot.reward = text(body, Theme.fonts.text, "TOP", 0, -268, PANEL_W - 12)
  Theme.setColor(slot.reward, Theme.parchment)

  slot.play = host.button(body, "Play", 120, 28, host.start)
  slot.play:SetPoint("BOTTOM", body, "BOTTOM", 0, 14)
  host.reasonTip(slot.play)

  local stamp = CreateFrame("Frame", nil, slot)
  stamp:SetSize(PANEL_W, 44)
  stamp:SetPoint("CENTER", slot, "CENTER", 0, 10)
  stamp:SetFrameLevel(slot:GetFrameLevel() + 20)
  stamp.text = stamp:CreateFontString(nil, "OVERLAY", Theme.fonts.big)
  stamp.text:SetPoint("CENTER", stamp, "CENTER", 0, 0)
  stamp.text:SetFont(fontPath(), 26, "OUTLINE")
  stamp.text:SetText("DEFEATED")
  Theme.setColor(stamp.text, Theme.gold)
  -- Rotated where the client can rotate a font string (guarded: it is optional).
  if stamp.text.SetRotation then pcall(stamp.text.SetRotation, stamp.text, math.rad(14)) end
  stamp:Hide()
  slot.stamp = stamp

  slot.isBoss = i == 3
  slot.host = host
  return slot
end

function BlindSelect.Build(host)
  local p = host.makePanel("blind", false)
  p.stageText = text(p, Theme.fonts.text, "TOP", 0, -14, 560)
  Theme.setColor(p.stageText, Theme.parchment)
  p.panels = {}
  p.preview = p.panels -- the field the screen is looked up by
  for i = 1, 3 do p.panels[i] = makeBlind(p, i, host) end
  host.addAbandon(p)
  return p
end

---------------------------------------------------------------------------
-- Refresh: the static look from the run. Never disturbs a running tween.

local function setBorder(body, c, w)
  if body.borderWidth ~= w then -- the backdrop only changes with the width
    body:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = w })
    body.borderWidth = w
  end
  body.borderColor = c
  body:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

local function refreshOne(b, run, i, bossId)
  local st = stateOf(run, i)
  local boss = i == 3 and ns.Bosses.def[bossId] or nil
  local current = st == "CURRENT"
  b.state = st
  b.tag:SetText(st)
  Theme.setColor(b.tag, current and Theme.gold or Theme.parchment)
  b.kind:SetText(i == 3 and "BOSS" or "")
  Theme.setColor(b.kind, RED)
  b.bar:SetShown(i == 3)

  b.name:SetText(i == 3 and (boss and boss.name or "Boss Blind") or NAMES[i])
  Theme.setColor(b.name, current and Theme.gold or Theme.parchment)
  b.rule:SetText(boss and boss.desc or "")
  b.target:SetText(tostring(ns.Run.target(run.stage, i, i == 3 and bossId or nil)))
  Theme.setColor(b.target, current and Theme.gold or Theme.parchment)
  b.reward:SetText("Reward: " .. GOLD_HEX .. string.rep("$", ns.Run.BLIND_REWARDS[i]) .. "|r")

  local tint = i == 3 and (BlindSelect.BOSS_TINT[bossId] or NO_TINT) or NO_TINT
  b.chip:SetVertexColor(tint[1], tint[2], tint[3])

  if current then
    setBorder(b.body, Theme.gold, 2)
  else
    setBorder(b.body, i == 3 and RED_EDGE or EDGE, 1)
  end
  b.body:SetBackdropColor(current and 0.18 or 0.13, current and 0.13 or 0.1, current and 0.08 or 0.07, 0.98)
  b.glow:SetShown(current)

  -- Play: live on the current panel, visibly disabled on upcoming ones, gone on beaten ones.
  b.play:SetShown(st ~= "DEFEATED")
  if current then b.play:Enable() else b.play:Disable() end
  b.host.setReason(b.play, st == "UPCOMING" and "Beat the earlier blinds first" or nil)

  b.stamp:SetShown(st == "DEFEATED")

  -- Static pose, unless an entrance or pop owns the frame right now.
  if not Tween.IsActive(b) then
    placeSlot(b, b.dx, slotY(current))
    b:SetAlpha(1)
  end
  if not Tween.IsActive(b.body) then
    b.body:SetScale(1)
    b.body:SetAlpha(DIM[st])
  end
  if not Tween.IsActive(b.stamp) then
    b.stamp:SetScale(1)
    b.stamp:SetAlpha(1)
  end
end

function BlindSelect.Refresh(p, run)
  if not run then return end
  p.stageText:SetText("Stage " .. run.stage .. " of 8")
  local bossId = run.bosses[run.stage]
  for i = 1, 3 do refreshOne(p.panels[i], run, i, bossId) end
  p.start = p.panels[run.blind].play -- the live Play button
end

---------------------------------------------------------------------------
-- Motion

-- Staggered fade and rise as the screen opens. `settle` (coming back from the
-- shop after a win): the new current panel pops, the beaten one's stamp lands.
function BlindSelect.Enter(p, run, settle)
  if not run then return end
  for i = 1, 3 do
    local b = p.panels[i]
    local st = b.state
    local base = slotY(st == "CURRENT")
    local delay = (i - 1) * STAGGER
    b:SetAlpha(0)
    placeSlot(b, b.dx, base - RISE)
    Tween.To(b, { alpha = 1, y = base }, ENTER_T, nil, delay)

    if settle then
      local after = delay + ENTER_T
      if st == "CURRENT" then
        Tween.To(b.body, { scale = POP_SCALE }, POP_UP, function()
          Tween.To(b.body, { scale = 1 }, POP_DOWN)
        end, after)
      elseif st == "DEFEATED" and i == run.blind - 1 then
        b.stamp:SetAlpha(0)
        b.stamp:SetScale(STAMP_FROM)
        Tween.To(b.stamp, { scale = 1, alpha = 1 }, STAMP_T, nil, after)
      end
    end
  end
end

-- True while any panel tween is running (for tests).
function BlindSelect.IsAnimating(p)
  for i = 1, 3 do
    local b = p.panels[i]
    if Tween.IsActive(b) or Tween.IsActive(b.body) or Tween.IsActive(b.stamp) then return true end
  end
  return false
end

ns.UI.BlindSelect = BlindSelect
