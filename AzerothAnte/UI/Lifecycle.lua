local _, ns = ...

local Theme = ns.UI.Theme
local Tween = ns.UI.Tween
local Lifecycle = {}

local STEP = 0.25            -- seconds between events
local TAIL = 0.3             -- beat after the last one, so a melt or pop finishes before the row re-renders
local MELT = 0.3             -- a destroyed trinket fades and shrinks
local POP_TIME, POP_FROM = 0.2, 0.6
local FAST = 4               -- clicking speeds the queue up
local LONG = 8               -- events after this many play at FAST, so a long queue never holds input
local WATCHDOG = 5           -- real seconds beyond the queue's own length
local STACK = 16             -- rise between floats stacked on one target
local CREAM = { 1, 0.95, 0.75 }
local RED = { 1, 0.25, 0.2 }

local driver = CreateFrame("Frame")
local overlay
local hooked = false
local state                  -- non-nil while a queue plays

function Lifecycle.IsBusy()
  return state ~= nil
end

local function main()
  return ns.UI.Main
end

local function TR() return ns.UI.TrinketRow end

---------------------------------------------------------------------------
-- Effects

-- Floats on a target started close together stack upward instead of overlapping.
local function stackedFloat(s, target, text, color)
  if not target then return end
  local rec = s.floats[target]
  if rec and s.clock - rec.t < 0.9 * s.speed then
    rec.n = (rec.n + 1) % 4
  else
    rec = { n = 0 }
    s.floats[target] = rec
  end
  rec.t = s.clock
  ns.UI.Outcome.Float(target, text, color, rec.n * STACK)
end

local function pop(slot)
  if not slot then return end
  local holder = slot.holder
  holder:SetScale(POP_FROM)
  holder:SetAlpha(0)
  Tween.To(holder, { scale = 1, alpha = 1 }, POP_TIME)
end

-- Does the event have anything to show? Events about a slot that is not on screen cost no beat.
local function visual(e)
  local kind = e.kind
  if kind == "trinketMsg" or kind == "trinketDestroyed" then
    return TR().SlotByUid(e.uid) ~= nil
  end
  return kind == "money" or kind == "trinketCreated" or kind == "levelUp" or kind == "cardDestroyed"
    or kind == "cardCreated" or kind == "consumableCreated" or kind == "bossDisabled"
end

local function fire(s, e)
  local kind, row = e.kind, TR()
  local sb = main().sidebar
  if kind == "trinketMsg" then
    local slot = row.SlotByUid(e.uid)
    row.PulseSlot(slot)
    stackedFloat(s, slot, e.text or e.msg or "", CREAM)
  elseif kind == "money" then
    local n = e.amount or e.gold or 0
    local slot = row.SlotByUid(e.uid)
    row.PulseSlot(slot)
    stackedFloat(s, slot or (sb and sb.gold), (n < 0 and "-" or "+") .. math.abs(n) .. "g", n < 0 and RED or Theme.gold)
  elseif kind == "trinketDestroyed" then
    row.Destroy(e.uid, MELT / s.speed)
  elseif kind == "trinketCreated" then
    -- The row still shows the old order: render it so the newcomer has a slot, then pop it in.
    row.Update(s.run)
    pop(row.SlotByUid(e.uid))
  elseif kind == "levelUp" then
    row.PulseUid(e.uid)
    stackedFloat(s, sb and sb.handName, "Level up!", Theme.gold)
  elseif kind == "cardDestroyed" then
    ns.UI.Outcome.Play({ destroyed = { e.cardId or e.id } })
  elseif kind == "cardCreated" then
    -- With the hand on screen a card made into it flies out of the Deck button; otherwise (a card for the
    -- deck, or a hand not dealt yet: the render deals it) the Deck button just pulses.
    row.PulseUid(e.uid)
    local card = ns.Deck.find(s.run, e.cardId)
    ns.UI.Screens.PulseDeckButton(s.run)
    if e.toHand then ns.UI.HandView.FlyIn(card, s.speed) end
  elseif kind == "consumableCreated" then
    row.PulseUid(e.uid)
    ns.UI.ConsumableRow.PopIn(s.run, e.item, s.speed)
  elseif kind == "bossDisabled" then
    -- Markers and the boss panel change now; the render after the queue only confirms it.
    ns.UI.HandView.ClearDebuffs()
    ns.UI.Sidebar.ShowBoss(s.run)
    local target = sb and sb.blindName and sb.blindName:IsShown() and sb.blindName or main().playArea
    stackedFloat(s, target, "Boss disabled!", Theme.gold)
  end
end

---------------------------------------------------------------------------
-- Scheduler: one OnUpdate, installed only while a queue plays.

local function stop()
  driver:SetScript("OnUpdate", nil)
  if overlay then overlay:Hide() end
end

-- Ends the queue exactly once and calls done().
local function finish()
  local s = state
  if not s then return end
  state = nil
  stop()
  ns.UI.ConsumableRow.ClearPending()
  if ns.UI.HandView then pcall(ns.UI.HandView.RefreshButtons) end
  s.done()
end

-- The run was replaced mid-queue: drop everything without calling done.
local function abandon()
  state = nil
  stop()
  ns.UI.ConsumableRow.ClearPending()
end

local function onUpdate(_, dt)
  local s = state
  if not s then return stop() end
  if main().run ~= s.run then return abandon() end
  s.real = s.real + dt
  if s.real >= WATCHDOG + s.endAt then return finish() end
  s.clock = s.clock + dt * s.speed
  while s.steps[s.next] and s.steps[s.next].at <= s.clock do
    local step = s.steps[s.next]
    s.next = s.next + 1
    local ok, err = pcall(fire, s, step.event)
    if not ok then geterrorhandler()(err) end
  end
  if s.clock >= s.endAt then finish() end
end

local function getOverlay()
  if not overlay then
    local m = main()
    overlay = CreateFrame("Button", nil, m.content)
    overlay:SetAllPoints(m.content)
    overlay:RegisterForClicks("LeftButtonUp")
    overlay.lifecycleOverlay = true
    overlay:SetScript("OnClick", function()
      if state then state.speed = FAST end
    end)
    overlay:Hide()
  end
  overlay:SetFrameLevel(main().content:GetFrameLevel() + 800)
  return overlay
end

-- OnHide: finish instantly (the queue's own done still runs, so the screen ends up correct).
local function hookHide()
  if hooked then return end
  hooked = true
  main().frame:HookScript("OnHide", function()
    if state then finish() end
  end)
end

-- Plays run.lifecycleEvents in order, STEP apart, then calls done() once. An empty list calls done
-- at once, so an action with nothing to show has no delay. The row is left as it was until done:
-- the caller re-renders then.
function Lifecycle.Drain(run, done)
  done = done or function() end
  local events = run and run.lifecycleEvents
  if not events or #events == 0 then return done() end
  run.lifecycleEvents = {}
  local m = main()
  if not m or not m.frame or not m.frame:IsShown() or m.run ~= run then return done() end
  if state then finish() end -- never leave an earlier queue's done() uncalled
  hookHide()
  local overlayBtn = getOverlay() -- build before state exists

  local steps, at = {}, 0
  for _, e in ipairs(events) do
    if visual(e) then
      steps[#steps + 1] = { at = at, event = e }
      at = at + ((#steps >= LONG) and STEP / FAST or STEP)
    end
  end
  if #steps == 0 then return done() end
  local made = {}
  for _, st in ipairs(steps) do
    if st.event.kind == "consumableCreated" and st.event.item then made[#made + 1] = st.event.item end
  end
  ns.UI.ConsumableRow.MarkPending(made) -- hidden until their own pop
  state = {
    run = run, done = done, steps = steps, next = 1, clock = 0, real = 0, speed = 1, floats = {},
    endAt = steps[#steps].at + TAIL,
  }
  if ns.UI.HandView then ns.UI.HandView.RefreshButtons() end -- Play and Discard wait for the queue
  overlayBtn:Show()
  driver:SetScript("OnUpdate", onUpdate)
end

ns.UI.Lifecycle = Lifecycle
