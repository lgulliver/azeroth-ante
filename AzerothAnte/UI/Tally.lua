local _, ns = ...

local Theme = ns.UI.Theme
local Tween = ns.UI.Tween
local HandView = ns.UI.HandView
local Tally = {}

local STEP = 0.28            -- seconds between events
local COUNT_TIME = 0.5       -- score count-up
local HOLD = 0.3             -- beat after the total lands
local FLOAT_RISE, FLOAT_TIME = 30, 0.6
local FAST = 4
local WATCHDOG = 15          -- real seconds; force-finish a stuck tally
local GREY = { 0.7, 0.7, 0.7 }
local SHAKE = { 4, -4, 4, -4, 4, 0 }

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

local function isNoop(e)
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

local function fire(e)
  local s = state
  if e.kind == "base" then
    local hand = ns.Hands.def[e.handId]
    showRun(e, hand and hand.name)
  elseif e.kind == "card" then
    local w = s.widgets[e.index]
    if w then w:Pop() end
    floatText(w, "+" .. e.chips, Theme.chips)
    showRun(e)
  elseif e.kind == "debuff" then
    local w = s.widgets[e.index]
    if w then
      shakeCard(w)
      floatText(w, "X", GREY)
    end
  elseif e.kind == "trinket" then
    local slot = slotFrame(e.slot)
    ns.UI.TrinketRow.Pulse(e.slot)
    if e.index and s.widgets[e.index] then s.widgets[e.index]:Pop() end
    local lift = 0
    if e.chips and e.chips ~= 0 then
      floatText(slot, (e.chips > 0 and "+" or "") .. e.chips, Theme.chips, lift)
      lift = lift + 16
    end
    if e.mult and e.mult ~= 0 then
      floatText(slot, (e.mult > 0 and "+" or "") .. e.mult, Theme.mult, lift)
      lift = lift + 16
    end
    if e.xmult and e.xmult ~= 1 then
      floatText(slot, "\195\151" .. e.xmult, Theme.mult, lift)
    end
    showRun(e)
  elseif e.kind == "total" then
    s.count = { from = s.from, to = s.run.score, t = 0 }
  end
end

---------------------------------------------------------------------------
-- Scheduler: one OnUpdate, installed only while a tally runs.

local function stop()
  driver:SetScript("OnUpdate", nil)
  if overlay then overlay:Hide() end
end

local function finish()
  local s = state
  if not s then return end
  state = nil
  stop()
  if HandView.run == s.run then
    ns.UI.Sidebar.SetScore(s.run.score)
    ns.UI.Sidebar.SetChipsMult(s.result.chips, s.result.mult)
  end
  s.done()
end

local function onUpdate(_, dt)
  local s = state
  if not s then return stop() end
  s.real = s.real + dt
  if s.real >= WATCHDOG then return finish() end
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
    if state then finish() end
  end)
end

-- HandView.OnPlayed hook. Calls done() exactly once.
function Tally.Play(result, playedWidgets, done)
  if state then finish() end -- never leave an earlier tally's done() uncalled
  local run = HandView.run
  local m = main()
  if not run or not m or not m.frame or not result or not result.events then
    return done()
  end
  hookHide()

  local steps, at = {}, 0
  for _, e in ipairs(result.events) do
    if not (e.kind == "trinket" and isNoop(e)) then
      steps[#steps + 1] = { at = at, event = e }
      at = at + STEP
    end
  end
  -- The total step starts the count-up; the last step is `total`.
  local from = (run.score or 0) - (result.total or 0)
  state = {
    run = run, result = result, widgets = playedWidgets or {}, done = done,
    steps = steps, next = 1, clock = 0, real = 0, speed = 1,
    from = from, endAt = (at - STEP) + COUNT_TIME + HOLD,
  }
  if #steps == 0 then state.endAt = HOLD end

  ns.UI.Sidebar.SetScore(from)
  getOverlay():Show()
  driver:SetScript("OnUpdate", onUpdate)
end

ns.UI.Tally = Tally
HandView.OnPlayed = Tally.Play
