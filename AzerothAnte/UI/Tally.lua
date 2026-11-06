local _, ns = ...

local Theme = ns.UI.Theme
local Tween = ns.UI.Tween
local HandView = ns.UI.HandView
local Sidebar = ns.UI.Sidebar
local Tally = {}

local STEP = 0.28            -- seconds between events
local COUNT_TIME = 0.5       -- score count-up
local SHATTER = 0.35      -- a destroyed card's last beat
local HOLD = 0.3             -- beat after the total lands
local FLOAT_RISE, FLOAT_TIME = 30, 0.6
local FAST = 4
local SLIDE, SLIDE_TIME = 160, 0.25
local WATCHDOG = 15          -- real seconds (at least); force-finish a stuck tally. A tally lasting longer gets its length + 5s.
local GREY = { 0.7, 0.7, 0.7 }
local SHAKE = { 4, -4, 4, -4, 4, 0 }
local STACK = 16             -- rise between floats stacked on one target
local CREAM = { 1, 0.95, 0.75 }
local ED_COLOR = {           -- Foil blue, Holo red, Poly purple
  FOIL = Theme.chips, HOLO = Theme.mult, POLY = { 0.75, 0.4, 1 },
}

local driver = CreateFrame("Frame")
local floatPool = {}
local overlay
local hooked = false
local state                  -- non-nil while a tally runs

function Tally.IsBusy()
  return state ~= nil
end

local function main()
  return ns.UI.Main
end

---------------------------------------------------------------------------
-- Floating numbers

local function acquireFloat()
  local f = table.remove(floatPool)
  if not f then
    f = CreateFrame("Frame", nil, main().content)
    f:SetSize(60, 20)
    f.text = f:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
    f.text:SetPoint("CENTER")
  end
  f:SetParent(main().content)
  f:SetFrameLevel(main().playArea:GetFrameLevel() + 450)
  return f
end

-- Rises FLOAT_RISE units above `target` and fades; `lift` stacks several numbers.
local function floatText(target, text, color, lift)
  if not target then return end
  local f = acquireFloat()
  f.text:SetText(text)
  Theme.setColor(f.text, color)
  f:ClearAllPoints()
  f:SetPoint("BOTTOM", target, "TOP", 0, lift or 0)
  f:SetAlpha(1)
  f:SetScale(1)
  f:Show()
  local speed = state and state.speed or 1
  Tween.To(f, { y = (lift or 0) + FLOAT_RISE, alpha = 0 }, FLOAT_TIME / speed, function()
    f:Hide()
    f:ClearAllPoints()
    floatPool[#floatPool + 1] = f
  end)
end

---------------------------------------------------------------------------
-- Effects

local function popBox(box)
  if not box then return end
  Tween.To(box, { scale = 1.12 }, 0.06, function()
    Tween.To(box, { scale = 1 }, 0.12)
  end)
end

local function shakeCard(w)
  local i = 0
  local function leg()
    i = i + 1
    if i > #SHAKE then return end
    Tween.To(w.body, { x = SHAKE[i], y = 0 }, 0.025, leg)
  end
  w:SetDebuffed(true)
  leg()
end

local function slotFrame(slot)
  local m = main()
  return m and m.trinketRow and m.trinketRow.slots and m.trinketRow.slots[slot]
end

-- Trinkets with no effect and zero-chip cards (Stone) spend no beat.
local function isNoop(e)
  if e.kind ~= "trinket" and e.kind ~= "card" then return false end
  local xm = e.xmult
  return (not e.chips or e.chips == 0) and (not e.mult or e.mult == 0) and (not xm or xm == 1)
end

local function showRun(e, handName)
  local sb = main().sidebar
  ns.UI.Sidebar.SetChipsMult(e.runChips, e.runMult, handName)
  if sb then
    popBox(sb.chipsBox)
    popBox(sb.multBox)
  end
end

-- Floats on a target started close together stack upward instead of overlapping.
local function stackedFloat(s, target, text, color)
  if not target then return end
  local rec = s.floats[target]
  if rec and s.clock - rec.t < FLOAT_TIME * 0.8 then
    rec.n = (rec.n + 1) % 4
  else
    rec = { n = 0 }
    s.floats[target] = rec
  end
  rec.t = s.clock
  floatText(target, text, color, rec.n * STACK)
end

-- Floats an effect's chips, mult and xmult deltas; `color` overrides the usual colours.
local function floatDeltas(s, target, e, color)
  if e.chips and e.chips ~= 0 then
    stackedFloat(s, target, (e.chips > 0 and "+" or "") .. Sidebar.round2(e.chips), color or Theme.chips)
  end
  if e.mult and e.mult ~= 0 then
    stackedFloat(s, target, (e.mult > 0 and "+" or "") .. Sidebar.round2(e.mult), color or Theme.mult)
  end
  if e.xmult and e.xmult ~= 1 then
    stackedFloat(s, target, "\195\151" .. Sidebar.round2(e.xmult), color or Theme.mult)
  end
end

-- The widget an event is about: a played card (index) or a held card (heldIndex).
local function widgetFor(s, e)
  if e.index then return s.widgets[e.index] end
  if e.heldIndex then return s.held[e.heldIndex] end
end

local function fire(e)
  local s = state
  if not s or HandView.run ~= s.run then return end
  local kind = e.kind
  if kind == "base" then
    local hand = ns.Hands.def[e.handId]
    local level = s.run.handLevels and s.run.handLevels[e.handId]
    showRun(e, hand and (hand.name .. (level and (" Lv " .. level) or "")))
  elseif kind == "card" then
    local w = s.widgets[e.index]
    if w then w:Pop() end
    stackedFloat(s, w, "+" .. e.chips, Theme.chips)
    showRun(e)
  elseif kind == "enh" then
    local w = s.widgets[e.index]
    if w then w:Pop() end
    floatDeltas(s, w, e)
    showRun(e)
  elseif kind == "edition" then
    local color = ED_COLOR[e.ed] or Theme.chips
    if e.slot then
      ns.UI.TrinketRow.Pulse(e.slot)
      floatDeltas(s, slotFrame(e.slot), e, color)
    else
      local w = s.widgets[e.index]
      if w then w:Pop() end
      floatDeltas(s, w, e, color)
    end
    showRun(e)
  elseif kind == "seal" or kind == "money" then
    local w = s.widgets[e.index]
    if w then w:Pop() end
    stackedFloat(s, w, "$" .. (e.gold or 0), Theme.gold)
  elseif kind == "held" then
    local w = s.held[e.heldIndex]
    if w then w:Pop() end -- pulses in place; the card does not lift
    floatDeltas(s, w, e)
    showRun(e)
  elseif kind == "retrigger" then
    stackedFloat(s, widgetFor(s, e), "Again!", CREAM)
  elseif kind == "debuff" then
    local w = widgetFor(s, e)
    if w then
      shakeCard(w)
      stackedFloat(s, w, "X", GREY)
    end
  elseif kind == "trinket" then
    local slot = slotFrame(e.slot)
    ns.UI.TrinketRow.Pulse(e.slot)
    if e.index and s.widgets[e.index] then s.widgets[e.index]:Pop() end
    local lift = 0
    if e.chips and e.chips ~= 0 then
      floatText(slot, (e.chips > 0 and "+" or "") .. Sidebar.round2(e.chips), Theme.chips, lift)
      lift = lift + 16
    end
    if e.mult and e.mult ~= 0 then
      floatText(slot, (e.mult > 0 and "+" or "") .. Sidebar.round2(e.mult), Theme.mult, lift)
      lift = lift + 16
    end
    if e.xmult and e.xmult ~= 1 then
      floatText(slot, "\195\151" .. Sidebar.round2(e.xmult), Theme.mult, lift)
    end
    showRun(e)
  elseif kind == "voucher" then
    -- Observatory: the Tome in the consumable row pulses and floats its multiplier.
    local CR = ns.UI.ConsumableRow
    local holder
    for i, item in ipairs(s.run.consumables) do
      if item.kind == "tome" and item.id == s.run.lastHandId then
        holder = CR and CR.SlotHolder and CR.SlotHolder(i)
        if holder then break end
      end
    end
    holder = holder or (CR and CR.SlotHolder and CR.SlotHolder(1))
    if holder then
      popBox(holder)
      stackedFloat(s, holder, "\195\151" .. Sidebar.round2(e.xmult), Theme.mult)
    end
    showRun(e)
  elseif kind == "total" then
    s.count = { from = s.from, to = s.run.score, t = 0 }
  elseif kind == "destroy" then
    local w = s.widgets[e.index]
    if w and not s.destroyed[w] then
      s.destroyed[w] = true -- it does not slide away afterwards
      ns.UI.Outcome.Shatter(w, 0, function() end)
    end
  end
end

---------------------------------------------------------------------------
-- Scheduler: one OnUpdate, installed only while a tally runs.

local function stop()
  driver:SetScript("OnUpdate", nil)
  if overlay then overlay:Hide() end
end

-- Ends the tally exactly once and calls done().
local function complete(s)
  if s.completed then return end
  s.completed = true
  if state == s then state = nil end
  stop()
  s.done()
end

-- Normal end slides the played cards away, then completes. `instant` (hide,
-- watchdog, superseded) completes at once.
local function finish(instant)
  local s = state
  if not s then return end
  if s.sliding then
    if instant then complete(s) end
    return
  end
  stop()
  if HandView.run == s.run then
    pcall(Sidebar.SetScore, s.run.score)
    pcall(Sidebar.SetChipsMult, s.result.chips, s.result.mult)
  end
  local ws = {}
  for _, w in ipairs(s.widgets) do
    if not s.destroyed[w] then ws[#ws + 1] = w end
  end
  if instant or #ws == 0 then return complete(s) end
  s.sliding = true
  local pending = #ws
  local function slid()
    pending = pending - 1
    if pending == 0 then complete(s) end
  end
  for k, w in ipairs(ws) do
    Tween.To(w, { x = (w.lx or 0) + SLIDE, y = w.ly or 0, alpha = 0 }, SLIDE_TIME, slid, (k - 1) * 0.02, slid)
  end
end

-- The run was replaced mid-tally: drop everything without calling done.
local function abandon()
  state = nil
  stop()
end

local function onUpdate(_, dt)
  local s = state
  if not s then return stop() end
  if HandView.run ~= s.run then return abandon() end
  s.real = s.real + dt
  -- Real time vs the tally's own length: a long tally (many events) is never cut short.
  if s.real >= math.max(WATCHDOG, s.endAt + 5) then return finish(true) end
  dt = dt * s.speed
  s.clock = s.clock + dt

  while s.steps[s.next] and s.steps[s.next].at <= s.clock do
    local step = s.steps[s.next]
    s.next = s.next + 1
    local ok, err = pcall(fire, step.event)
    if not ok then geterrorhandler()(err) end
  end

  local c = s.count
  if c then
    c.t = c.t + dt
    local k = math.min(1, c.t / COUNT_TIME)
    local u = 1 - k
    ns.UI.Sidebar.SetScore(math.floor(c.from + (c.to - c.from) * (1 - u * u * u)))
    if k >= 1 then s.count = nil end
  end

  if s.clock >= s.endAt then finish() end
end

local function getOverlay()
  if not overlay then
    overlay = CreateFrame("Button", nil, main().playArea)
    overlay:SetAllPoints(main().playArea)
    overlay:RegisterForClicks("LeftButtonUp")
    overlay:SetScript("OnClick", function()
      if state then state.speed = FAST end
    end)
    overlay:Hide()
  end
  overlay:SetFrameLevel(main().playArea:GetFrameLevel() + 400)
  return overlay
end

-- OnHide: finish instantly with the final state (and release the lock).
local function hookHide()
  if hooked then return end
  hooked = true
  main().frame:HookScript("OnHide", function()
    if state then finish(true) end
  end)
end

-- HandView.OnPlayed hook. Calls done() exactly once.
function Tally.Play(result, playedWidgets, done)
  if state then finish(true) end -- never leave an earlier tally's done() uncalled
  local run = HandView.run
  local m = main()
  if not run or not m or not m.frame or not m.frame:IsShown() or not result or not result.events then
    return done()
  end
  hookHide()
  local overlayBtn = getOverlay() -- build before state exists

  local list = {}
  for _, e in ipairs(result.events) do
    if not isNoop(e) then list[#list + 1] = e end
  end
  -- Long tallies stay brisk (about 6s at most at 1x).
  local step = math.max(0.12, math.min(STEP, 6 / math.max(1, #list)))
  local steps, at, totalAt = {}, 0, 0
  for i, e in ipairs(list) do
    steps[i] = { at = at, event = e }
    if e.kind == "total" then totalAt = at end
    at = at + step
  end
  -- The total step starts the count-up; the last step is `total`.
  local from = (run.score or 0) - (result.total or 0)
  state = {
    run = run, result = result, widgets = playedWidgets or {}, done = done,
    steps = steps, next = 1, clock = 0, real = 0, speed = 1,
    from = from, floats = {}, destroyed = {}, held = HandView.HeldWidgets(),
    -- The count-up and any shatter after `total` both finish before the hold.
    endAt = math.max(totalAt + COUNT_TIME, (at - step) + SHATTER) + HOLD,
  }
  if #steps == 0 then state.endAt = HOLD end

  ns.UI.Sidebar.SetScore(from)
  overlayBtn:Show()
  driver:SetScript("OnUpdate", onUpdate)
end

ns.UI.Tally = Tally
HandView.OnPlayed = Tally.Play
