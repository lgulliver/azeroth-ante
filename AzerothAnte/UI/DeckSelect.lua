local _, ns = ...

-- The deck-select screen: a Balatro-style carousel. One big deck card in the
-- centre, its neighbours peeking either side (smaller, tilted, dimmed), arrows
-- and click-to-slide, a short tween that wraps around, and the unlock flourish.
local Theme = ns.UI.Theme
local CardWidget = ns.UI.CardWidget
local DeckSelect = {}

local MEDIA = "Interface\\AddOns\\AzerothAnte\\Media\\"
local FLAT = "Interface\\Buttons\\WHITE8x8"
local DOT = "\194\183" -- middle dot

local SLIDE = 0.2                                -- seconds per slide
local CENTER_SCALE, SIDE_SCALE, FAR_SCALE = 1.35, 0.8, 0.6
local SIDE_X, FAR_X = 76, 118                    -- card-centre offsets from the middle
local TILT = math.rad(6)
local DIM = 0.5
local SQ, ART = 256, 160                         -- BackSq_* canvas, and the card's width inside it
local FADE_INFO = 0.15
local BAR_W = 240

local DIM_TEXT = { 0.62, 0.58, 0.5 }
local GREEN = { 0.3, 0.75, 0.3 }

-- Flourish timeline (seconds after the carousel has settled).
local LOCK_T = 0.5
local SAT_FROM, SAT_T = 0.15, 0.5
local TEXT_FROM, TEXT_HOLD, TEXT_END, TEXT_RISE = 0.1, 0.9, 1.5, 34
local FLASH_T = 0.35
local FLOURISH_END = 1.55
local QUEUE_GAP = -0.3                           -- lead-in while the carousel slides to the next unlock

local panel, api
local order
local selRaw, pos = 0, 0                         -- target and displayed carousel position (unbounded)
local slide, fade                                -- running tweens
local flourish, queue, held = nil, {}, {}
local opened = false
local cards = {}
local driver
local fallbackDb = {}

local function db()
  return AzerothAnteDB or fallbackDb
end

local function ease(k)
  local u = 1 - k
  return 1 - u * u * u
end

local function lerp(a, b, k) return a + (b - a) * k end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function idAt(raw)
  return order[(raw % #order) + 1]
end

local function indexOf(id)
  for i, v in ipairs(order) do
    if v == id then return i end
  end
end

-- Signed whole-card distance from the current selection to `id`, shortest way round.
local function stepsTo(id)
  local n = #order
  local half = math.floor(n / 2)
  local d = (indexOf(id) - 1) - (selRaw % n)
  return (d + half) % n - half
end

function DeckSelect.Selected()
  return idAt(selRaw)
end

function DeckSelect.Card(id)
  return cards[id]
end

function DeckSelect.Flourishing()
  return flourish and flourish.id or nil
end

---------------------------------------------------------------------------
-- Deck facts

local function isUnlocked(id)
  return (ns.Profile.isUnlocked(db(), id))
end

local function unlockText(id)
  local _, have, need = ns.Profile.isUnlocked(db(), id)
  return ("Discover %d items to unlock (%d/%d)"):format(need, have, need), have, need
end

-- 0 = locked look (dark, grey, padlock), 1 = open.
local function lookOf(id)
  if flourish and flourish.id == id then
    return clamp((flourish.t - SAT_FROM) / SAT_T, 0, 1)
  end
  if held[id] then return 0 end
  return isUnlocked(id) and 1 or 0
end

---------------------------------------------------------------------------
-- Layout: every card is positioned from its continuous offset to the centre.

-- Optional texture APIs: a client lacking one just loses that effect.
local function setDesaturation(tex, amount)
  if tex.SetDesaturation then
    tex:SetDesaturation(amount)
  elseif tex.SetDesaturated then
    tex:SetDesaturated(amount > 0.5)
  end
end

local function layout()
  if not panel then return end
  local n = #order
  local baseLevel = panel.carousel:GetFrameLevel() + 5
  for i, id in ipairs(order) do
    local card = cards[id]
    local t = ((i - 1) - pos + n / 2) % n - n / 2
    local a, sgn = math.abs(t), t < 0 and -1 or 1
    local scale, x, alpha, tilt, dim
    if a <= 1 then
      scale, x = lerp(CENTER_SCALE, SIDE_SCALE, a), sgn * lerp(0, SIDE_X, a)
      tilt, dim, alpha = -sgn * TILT * a, lerp(1, DIM, a), 1
    elseif a < 2 then
      local f = a - 1
      scale, x = lerp(SIDE_SCALE, FAR_SCALE, f), sgn * lerp(SIDE_X, FAR_X, f)
      tilt, dim, alpha = -sgn * TILT, DIM, 1 - f
    end
    if not scale or alpha <= 0.01 then
      card:Hide()
    else
      local w, h = CardWidget.WIDTH * scale, CardWidget.HEIGHT * scale
      card:Show()
      card:SetSize(w, h)
      card:ClearAllPoints()
      card:SetPoint("CENTER", panel.carousel, "CENTER", x, 0)
      card:SetFrameLevel(baseLevel + math.floor((2 - math.min(a, 2)) * 20))
      card:SetAlpha(alpha)
      local side = w * SQ / ART
      card.art:SetSize(side, side)
      if card.art.SetRotation then card.art:SetRotation(tilt) end
      local look = lookOf(id)
      if card.hover and a > 0.5 then dim = math.min(1, dim + 0.2) end
      local shade = dim * (0.35 + 0.65 * look)
      card.art:SetVertexColor(shade, shade, shade)
      setDesaturation(card.art, 1 - look)
      -- The padlock: up while locked, popping and fading during the flourish.
      local lockAlpha, lockScale = 1, 1
      if flourish and flourish.id == id then
        local k = clamp(flourish.t / LOCK_T, 0, 1)
        lockAlpha, lockScale = 1 - ease(k), 1 + 0.6 * ease(k)
      end
      local lockShown = look < 0.999 and lockAlpha > 0.01
      card.lock:SetShown(lockShown)
      if lockShown then
        card.lock:SetSize(w * 0.55 * lockScale, w * 0.55 * lockScale)
        card.lock:SetAlpha(lockAlpha)
      end
      local flash = 0
      if flourish and flourish.id == id and flourish.t > SAT_FROM then
        flash = 0.55 * (1 - clamp((flourish.t - SAT_FROM) / FLASH_T, 0, 1))
      end
      card.flash:SetShown(flash > 0.01)
      if flash > 0.01 then card.flash:SetAlpha(flash) end
    end
  end
end

---------------------------------------------------------------------------
-- Info under the card

local function refreshInfo()
  if not panel then return end
  local id = DeckSelect.Selected()
  local def = ns.Decks.def[id]
  local stats = ns.Profile.get(db()).stats[id] or {}
  panel.name:SetText(def.name)
  panel.flavour:SetText("\"" .. (def.flavour or "") .. "\"")
  panel.stats:SetText(("%d hands %s %d discards %s $%d"):format(def.hands, DOT, def.discards, DOT, def.gold))
  panel.best:SetText(("Best: Stage %d %s Wins: %d"):format(stats.bestStage or 0, DOT, stats.wins or 0))
  if isUnlocked(id) then
    panel.desc:SetText(def.desc)
    Theme.setColor(panel.desc, Theme.parchment)
    panel.progress:Hide()
    api.setReason(panel.play, nil)
    panel.play:Enable()
  else
    local text, have, need = unlockText(id)
    panel.desc:SetText(text)
    Theme.setColor(panel.desc, DIM_TEXT)
    panel.progress:Show()
    local frac = need > 0 and clamp(have / need, 0, 1) or 1
    panel.progressFill:SetShown(frac > 0)
    panel.progressFill:SetWidth(math.max(1, (BAR_W - 2) * frac))
    api.setReason(panel.play, text)
    panel.play:Disable()
  end
end

---------------------------------------------------------------------------
-- Animation driver (one OnUpdate, set only while something is moving)

local function markSeen(id)
  held[id] = nil
  pcall(ns.Profile.markSeen, db(), id)
end

local function rawFor(id)
  return selRaw + stepsTo(id)
end

-- Moves the carousel to raw position `raw`, sliding unless `instant`.
local wake
local function goTo(raw, instant)
  selRaw = raw
  if instant then
    slide, fade = nil, nil
    pos = raw
    panel.info:SetAlpha(1)
    layout()
  else
    slide = { from = pos, to = raw, t = 0 }
    -- One cross-fade per burst of clicks: a running fade is left alone.
    if not fade then
      fade = { t = 0 }
      panel.info:SetAlpha(0)
    end
    wake()
  end
  refreshInfo()
end

local function startNext(first)
  local id = table.remove(queue, 1)
  if not id then
    flourish = nil
    return
  end
  flourish = { id = id, t = first and 0 or QUEUE_GAP }
  held[id] = true
  goTo(rawFor(id), first)
  wake()
end

local function updateText()
  local f = flourish
  if f and f.t >= TEXT_FROM and f.t < TEXT_END then
    local alpha = f.t < TEXT_HOLD and 1 or 1 - (f.t - TEXT_HOLD) / (TEXT_END - TEXT_HOLD)
    panel.unlockedText:SetAlpha(clamp(alpha, 0, 1))
    panel.unlockedText:ClearAllPoints()
    panel.unlockedText:SetPoint("CENTER", panel.fx, "CENTER", 0,
      TEXT_RISE * ease(clamp((f.t - TEXT_FROM) / (TEXT_END - TEXT_FROM), 0, 1)))
    panel.unlockedText:Show()
  else
    panel.unlockedText:Hide()
  end
end

local function onUpdate(_, dt)
  local moving = false
  if slide then
    slide.t = slide.t + dt
    local k = slide.t / SLIDE
    if k >= 1 then
      pos = slide.to
      slide = nil
      -- Rebase so the unbounded counters never drift.
      local shift = math.floor(selRaw / #order) * #order
      if shift ~= 0 then selRaw, pos = selRaw - shift, pos - shift end
    else
      pos = lerp(slide.from, slide.to, ease(k))
      moving = true
    end
  end
  if fade then
    fade.t = fade.t + dt
    local k = fade.t / FADE_INFO
    if k >= 1 then
      panel.info:SetAlpha(1)
      fade = nil
    else
      panel.info:SetAlpha(k)
      moving = true
    end
  end
  if flourish then
    flourish.t = flourish.t + dt
    if flourish.t >= FLOURISH_END then
      local done = flourish
      flourish = nil
      panel.unlockedText:Hide()
      markSeen(done.id)
      startNext(false)
    end
    moving = moving or flourish ~= nil
  end
  layout()
  if flourish then updateText() end
  if not moving then driver:SetScript("OnUpdate", nil) end
end

wake = function()
  driver:SetScript("OnUpdate", onUpdate)
end

function DeckSelect.Select(id, instant)
  if not panel or not indexOf(id) then return end
  if flourish then DeckSelect.Finish() end
  goTo(rawFor(id), instant)
end

-- The flourish owns the carousel for its ~1.5s: arrow and card clicks are ignored
-- meanwhile, so the text, flash and padlock never end up over another deck.
function DeckSelect.Step(dir)
  if not panel or flourish then return end
  goTo(selRaw + dir, false)
end

local finishAll
function DeckSelect.Finish() finishAll() end

-- Window closed or the screen left: finish everything instantly, marking decks seen.
finishAll = function()
  if flourish then markSeen(flourish.id) end
  for _, id in ipairs(queue) do markSeen(id) end
  flourish, queue = nil, {}
  if panel then
    panel.unlockedText:Hide()
    layout()
  end
end

local function onOpen()
  finishAll()
  local want = ns.Profile.get(db()).lastDeck
  if not (want and indexOf(want)) then want = "ROGUE" end
  goTo(rawFor(want), true)
  -- Decks without an unlock requirement are never announced.
  local announce = {}
  for _, id in ipairs(ns.Profile.newlyUnlocked(db())) do
    if ns.Decks.def[id].unlock then
      announce[#announce + 1] = id
    else
      markSeen(id)
    end
  end
  for _, id in ipairs(announce) do held[id] = true end
  queue = announce
  if #queue > 0 then startNext(true) end
  layout()
end

---------------------------------------------------------------------------
-- Build

local function makeCard(p, id)
  local card = CreateFrame("Button", nil, p.carousel)
  card:SetSize(CardWidget.WIDTH, CardWidget.HEIGHT)
  -- A square, centre-padded texture so SetRotation turns it rigidly.
  card.art = card:CreateTexture(nil, "ARTWORK")
  card.art:SetPoint("CENTER", card, "CENTER", 0, 0)
  card.art:SetTexture(MEDIA .. "BackSq_" .. id)
  card.art:SetTexCoord(0, 1, 0, 1)
  card.flash = card:CreateTexture(nil, "OVERLAY")
  card.flash:SetAllPoints()
  card.flash:SetColorTexture(1, 0.9, 0.5, 1)
  card.flash:Hide()
  card.lock = card:CreateTexture(nil, "OVERLAY", nil, 2)
  card.lock:SetPoint("CENTER", card, "CENTER", 0, 0)
  card.lock:SetTexture(MEDIA .. "Lock")
  card.lock:SetTexCoord(0, 1, 0, 1)
  card.lock:Hide()
  card:SetScript("OnClick", function()
    local d = stepsTo(id)
    if d ~= 0 then DeckSelect.Step(d) end
  end)
  card:SetScript("OnEnter", function(self)
    self.hover = true
    if not driver:GetScript("OnUpdate") then layout() end
  end)
  card:SetScript("OnLeave", function(self)
    self.hover = false
    if not driver:GetScript("OnUpdate") then layout() end
  end)
  cards[id] = card
  return card
end

local function text(parent, font, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOP", parent, "TOP", 0, y)
  fs:SetWidth(width)
  fs:SetJustifyH("CENTER")
  return fs
end

-- `host` supplies makePanel, button, reasonTip, setReason and start (see Screens).
function DeckSelect.Build(host)
  api = host
  order = ns.Decks.order
  local m = ns.UI.Main
  local p = host.makePanel("newrun", true)
  panel = p
  p.title:SetText("Choose your deck")
  -- Covers the (hidden) item rows too, so the carousel has the whole right-hand side.
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", m.trinketRow, "TOPLEFT", 0, 0)
  p:SetPoint("BOTTOMRIGHT", m.buttons, "BOTTOMRIGHT", 0, 0)

  p.carousel = CreateFrame("Frame", nil, p)
  p.carousel:SetSize(618, 260)
  p.carousel:SetPoint("TOP", p, "TOP", 0, -40)
  p.carousel:SetFrameLevel(p:GetFrameLevel() + 2)
  for _, id in ipairs(order) do makeCard(p, id) end

  -- Effects sit above every card.
  p.fx = CreateFrame("Frame", nil, p)
  p.fx:SetAllPoints(p.carousel)
  p.fx:SetFrameLevel(p:GetFrameLevel() + 120)
  p.unlockedText = p.fx:CreateFontString(nil, "OVERLAY", Theme.fonts.big)
  p.unlockedText:SetText("Unlocked!")
  Theme.setColor(p.unlockedText, Theme.gold)
  p.unlockedText:Hide()

  p.prevBtn = host.button(p, "<", 40, 56, function() DeckSelect.Step(-1) end)
  p.prevBtn:SetPoint("CENTER", p.carousel, "CENTER", -(SIDE_X + 118), 0)
  p.nextBtn = host.button(p, ">", 40, 56, function() DeckSelect.Step(1) end)
  p.nextBtn:SetPoint("CENTER", p.carousel, "CENTER", SIDE_X + 118, 0)

  p.info = CreateFrame("Frame", nil, p)
  p.info:SetAllPoints(p)
  p.name = text(p.info, Theme.fonts.title, -276, 480)
  Theme.setColor(p.name, Theme.gold)
  p.desc = text(p.info, Theme.fonts.text, -304, 440)
  p.desc:SetHeight(36)
  p.desc:SetJustifyV("TOP")
  p.progress = CreateFrame("Frame", nil, p.info, "BackdropTemplate")
  p.progress:SetSize(BAR_W, 10)
  p.progress:SetPoint("TOP", p.info, "TOP", 0, -326)
  p.progress:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
  p.progress:SetBackdropColor(0.05, 0.04, 0.03, 0.95)
  p.progress:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
  p.progressFill = p.progress:CreateTexture(nil, "ARTWORK")
  p.progressFill:SetPoint("LEFT", p.progress, "LEFT", 1, 0)
  p.progressFill:SetHeight(8)
  p.progressFill:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 1)
  p.flavour = text(p.info, Theme.fonts.small, -346, 440)
  Theme.setColor(p.flavour, DIM_TEXT)
  p.stats = text(p.info, Theme.fonts.text, -370, 440)
  Theme.setColor(p.stats, Theme.parchment)
  p.best = text(p.info, Theme.fonts.small, -392, 440)
  Theme.setColor(p.best, Theme.gold)

  p.play = host.button(p, "Play", 170, 32, function()
    local id = DeckSelect.Selected()
    if isUnlocked(id) then host.start(id) end
  end)
  p.play:SetPoint("BOTTOM", p, "BOTTOM", 0, 28)
  host.reasonTip(p.play)

  driver = CreateFrame("Frame", nil, p)

  -- A fresh open (also a reopened window) resets the selection and may flourish.
  p:SetScript("OnShow", function() DeckSelect.Refresh() end)
  p:SetScript("OnHide", function()
    opened = false
    finishAll()
  end)
  m.frame:HookScript("OnHide", function()
    opened = false
    finishAll()
  end)

  pos, selRaw = 0, 0
  refreshInfo()
  layout()
  return p
end

-- Called whenever the screen is rendered; cheap and idempotent.
function DeckSelect.Refresh()
  if not panel then return end
  if panel:IsVisible() then
    if not opened then
      opened = true
      onOpen()
    end
  else
    opened = false
  end
  refreshInfo()
  layout()
end

-- Profile totals for the sidebar.
function DeckSelect.Totals()
  local profile = ns.Profile.get(db())
  local runs, wins, best = 0, 0, 0
  for _, s in pairs(profile.stats) do
    runs = runs + (s.runs or 0)
    wins = wins + (s.wins or 0)
    best = math.max(best, s.bestStage or 0)
  end
  local unlocked = 0
  for _, id in ipairs(ns.Decks.order) do
    if ns.Profile.isUnlocked(db(), id) then unlocked = unlocked + 1 end
  end
  return {
    runs = runs, wins = wins, best = best, decks = unlocked, totalDecks = #ns.Decks.order,
    found = ns.Profile.discoveredCount(db()), totalFound = ns.Profile.totalDiscoverable(),
  }
end

ns.UI.DeckSelect = DeckSelect
