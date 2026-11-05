local _, ns = ...

local Theme = ns.UI.Theme
local Tween = ns.UI.Tween
local Outcome = {}

local FLIP_TIME = 0.25           -- shrink to nothing, swap the face, grow back
local SHATTER_TIME, SHATTER_SCALE = 0.3, 1.35
local STAGGER = 0.04
local POP_TIME, POP_SCALE, POP_DELAY = 0.12, 1.2, 0.1
local FLOAT_TIME, FLOAT_RISE = 0.9, 34
local WATCHDOG = 2.5             -- onDone is guaranteed even if a widget vanishes mid-tween
local RED = { 1, 0.25, 0.2 }

local resolvers = {}
local floatPool = {}

-- A resolver is fn(cardId) -> widget|nil. The hand is registered below; the
-- pack view adds its own so pack picks reuse these animations.
function Outcome.AddResolver(fn)
  resolvers[#resolvers + 1] = fn
end

Outcome.AddResolver(function(id)
  return ns.UI.HandView.WidgetForCard(id)
end)

-- Newest resolver first. The pack hand holds the same card tables as the stale,
-- hidden play hand, so while a pack is shown its widgets must win. A resolver
-- returns nil when it does not apply (PackView returns nil when it is not shown).
local function widgetFor(id)
  for i = #resolvers, 1, -1 do
    local w = resolvers[i](id)
    if w then return w end
  end
end

---------------------------------------------------------------------------
-- Floating text

local function acquireFloat()
  local main = ns.UI.Main
  local f = table.remove(floatPool)
  if not f then
    f = CreateFrame("Frame", nil, main.content)
    f:SetSize(80, 20)
    f.text = f:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
    f.text:SetPoint("CENTER")
  end
  f:SetParent(main.content)
  f:SetFrameLevel(main.content:GetFrameLevel() + 850)
  return f
end

-- Rises above `target` and fades.
function Outcome.Float(target, text, color)
  if not target then return end
  local f = acquireFloat()
  f.text:SetText(text)
  Theme.setColor(f.text, color)
  f:ClearAllPoints()
  f:SetPoint("BOTTOM", target, "TOP", 0, 0)
  f:SetAlpha(1)
  f:Show()
  Tween.To(f, { y = FLOAT_RISE, alpha = 0 }, FLOAT_TIME, function()
    f:Hide()
    f:ClearAllPoints()
    floatPool[#floatPool + 1] = f
  end)
end

function Outcome.FloatGold(delta)
  local sidebar = ns.UI.Main and ns.UI.Main.sidebar
  if not delta or delta == 0 or not sidebar or not sidebar.gold then return end
  local text = (delta > 0 and "+" or "-") .. math.abs(delta) .. "g"
  Outcome.Float(sidebar.gold, text, delta > 0 and Theme.gold or RED)
end

-- "Pair Lv 3" over the sidebar for one levelled hand; one line for many (Cosmos),
-- which also keeps unseen secret hands unnamed.
function Outcome.FloatLevels(levelled)
  local sidebar = ns.UI.Main and ns.UI.Main.sidebar
  local anchor = sidebar and (sidebar.handName or sidebar.target)
  if not anchor then return end
  local ids = {}
  for _, id in ipairs(ns.Hands.order) do
    if levelled[id] then ids[#ids + 1] = id end
  end
  if #ids == 0 then return end
  if #ids == 1 then
    Outcome.Float(anchor, ns.Hands.def[ids[1]].name .. " Lv " .. levelled[ids[1]], Theme.gold)
  else
    Outcome.Float(anchor, "All hands level up", Theme.gold)
  end
end

function Outcome.FloatHandSize(delta)
  local area = ns.UI.Main and ns.UI.Main.handArea
  if not delta or delta == 0 or not area then return end
  Outcome.Float(area, "Hand size " .. (delta > 0 and "+" or "-") .. math.abs(delta), delta > 0 and Theme.gold or RED)
end

-- Short scale pulse on a frame; the caller guarantees nothing else tweens it.
local function pulse(frame, done)
  Tween.To(frame, { scale = 1.25 }, 0.1, function()
    Tween.To(frame, { scale = 1 }, 0.1, done, 0, done)
  end, 0, done)
end

---------------------------------------------------------------------------
-- Per-card animations. Each calls done exactly once, even if cancelled.

-- Scale X 1 -> 0 -> 1 with the face swap at zero width (SetCard re-skins).
-- The face clips its children while it narrows, so suits, seal and
-- ranks are cut off with the art instead of sitting full size on a sliver; at
-- width 1 nothing shows, and the swap happens there.
local function flip(w, delay, done)
  local half = FLIP_TIME / 2
  local face = w.face
  local function finishFlip()
    face:SetClipsChildren(false)
    done()
  end
  face:SetClipsChildren(true)
  Tween.To(face, { width = 1 }, half, function()
    if w.card then
      w.cardKey = nil -- force the re-skin even when only a seal/edition changed
      w:SetCard(w.card)
    end
    Tween.To(face, { width = ns.UI.CardWidget.WIDTH }, half, finishFlip, 0, finishFlip)
  end, delay, finishFlip)
end

local function shatter(w, delay, done)
  w.locked = true
  w:EnableMouse(false)
  Tween.To(w.face, { scale = SHATTER_SCALE, alpha = 0 }, SHATTER_TIME, done, delay, done)
end

-- Shared with the tally, which shatters a destroyed Glass card in place.
Outcome.Shatter = shatter

local function pop(holder, delay, done)
  holder:SetAlpha(0)
  holder:SetScale(0.4)
  Tween.To(holder, { scale = POP_SCALE, alpha = 1 }, POP_TIME, function()
    Tween.To(holder, { scale = 1 }, POP_TIME, done, 0, done)
  end, delay, done)
end

-- Plays a Consumables outcome ({ changed, destroyed, created, added, gold,
-- levelled, trinkets, handSize, nope }), all effects together (cards
-- staggered), then calls onDone once. `added` cards are dealt in by the view's
-- own re-layout after onDone. The caller may set `slot` (the consumable slot
-- just used, which pulses) and `anchor` (the frame "Nope!" floats over).
function Outcome.Play(outcome, onDone)
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    if onDone then onDone() end
  end

  local jobs = {}
  for i, id in ipairs(outcome.changed or {}) do
    local w = widgetFor(id)
    if w then jobs[#jobs + 1] = function(done) flip(w, (i - 1) * STAGGER, done) end end
  end
  for i, id in ipairs(outcome.destroyed or {}) do
    local w = widgetFor(id)
    if w then jobs[#jobs + 1] = function(done) shatter(w, (i - 1) * STAGGER, done) end end
  end
  local row = ns.UI.ConsumableRow
  local popping = {}
  for i, item in ipairs(outcome.created or {}) do
    local holder = row and row.HolderFor(item)
    if holder then
      popping[holder] = true
      holder:SetAlpha(0) -- hidden now, so it never shows before its pop
      jobs[#jobs + 1] = function(done) pop(holder, POP_DELAY + (i - 1) * STAGGER, done) end
    end
  end
  -- The used slot pulses (unless a created item is popping into it).
  local used = outcome.slot and row and row.SlotHolder(outcome.slot)
  if used and not popping[used] then
    jobs[#jobs + 1] = function(done) pulse(used, done) end
  end
  for _, index in ipairs(outcome.trinkets or {}) do
    ns.UI.TrinketRow.Pulse(index)
  end
  if outcome.gold and outcome.gold ~= 0 then Outcome.FloatGold(outcome.gold) end
  if outcome.levelled and next(outcome.levelled) then Outcome.FloatLevels(outcome.levelled) end
  if outcome.handSize and outcome.handSize ~= 0 then Outcome.FloatHandSize(outcome.handSize) end
  if outcome.nope then Outcome.Float(outcome.anchor, "Nope!", RED) end

  local pending = #jobs
  if pending == 0 then return finish() end
  local function one()
    pending = pending - 1
    if pending <= 0 then finish() end
  end
  C_Timer.After(WATCHDOG, finish)
  for _, job in ipairs(jobs) do
    local called = false
    job(function()
      if called then return end
      called = true
      one()
    end)
  end
end

ns.UI.Outcome = Outcome
