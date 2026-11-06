local _, ns = ...

local Theme = ns.UI.Theme
local TrinketRow = {}

local MIN_SLOTS = 5 -- slots built up front; Run.trinketSlots grows it (Negative trinkets)
local SLOT_SIZE = 44
local SLOT_GAP = 8
local SELL_W, SELL_H = 44, 18 -- as wide as a slot, so sell buttons never overlap
local PICKUP = 6          -- screen pixels of travel before a press becomes a drag
local LIFT = 1.08         -- a held slot's scale
local SHIFT_TIME = 0.12   -- other slots sliding aside, and a dropped slot settling
local LIFT_TIME = 0.08
local GREEN = { 0.3, 1, 0.3 }

local sellMode, onSell = false, nil
local pitch = SLOT_SIZE + SLOT_GAP -- distance between slot origins, set by Update
local currentRun
local press                -- the left button is down on a slot: { slot, rawX, cx, active, from, target, startX, x }
local lastX = {}           -- trinket uid -> x it was last shown at, so re-renders slide instead of jumping
local settle               -- { uid, x, scale }: the slot just dropped, which Update lets glide into place

local function Tween() return ns.UI.Tween end -- loads after this file

local function locked()
  local HandView, Tally = ns.UI.HandView, ns.UI.Tally
  return (HandView and HandView.IsBusy()) or (Tally and Tally.IsBusy())
end

local function slotX(i) return (i - 1) * pitch end

local function showTooltip(slot)
  local def = slot.def
  if not def then GameTooltip:Hide() return end -- an emptied slot must not keep the old tooltip
  if press and press.active then return end
  local run = currentRun
  local r = Theme.rarity[def.rarity] or Theme.rarity.common
  GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(def.name, r[1], r[2], r[3])
  GameTooltip:AddLine(def.rarity and (def.rarity:sub(1, 1):upper() .. def.rarity:sub(2)) or "", r[1], r[2], r[3])
  GameTooltip:AddLine(ns.Trinkets.describe(def, run), 1, 1, 1, true)
  local ed = slot.trinket and ns.CardTypes.ed[slot.trinket.ed]
  if ed then
    GameTooltip:AddLine(ed.name, Theme.gold[1], Theme.gold[2], Theme.gold[3])
    GameTooltip:AddLine(ed.desc, 1, 1, 1, true)
  end
  if def.status and slot.trinket and run then
    local ok, status = pcall(def.status, slot.trinket, run)
    if ok and status then GameTooltip:AddLine(status, GREEN[1], GREEN[2], GREEN[3], true) end
  end
  if def.copies and run then
    local _, target = ns.TrinketEngine.source(run.trinkets, slot.index)
    GameTooltip:AddLine("Copies: " .. (target and target.name or "nothing (incompatible)"), 1, 1, 1)
  end
  if sellMode and slot.trinket then
    GameTooltip:AddLine("Sells for " .. ns.Shop.sellValue(slot.trinket) .. "g", Theme.gold[1], Theme.gold[2], Theme.gold[3])
  end
  GameTooltip:Show()
end

-- Shows an "Ng" sell button under each owned trinket while sell mode is on.
local function refreshSell()
  local frame = ns.UI.Main and ns.UI.Main.trinketRow
  if not frame or not frame.slots then return end
  for i = 1, #frame.slots do
    local slot = frame.slots[i]
    if sellMode and slot.def and slot:IsShown() and not (press and press.active) then
      slot.sell.price = ns.Shop.sellValue(slot.trinket)
      slot.sell:SetText(slot.sell.price .. "g")
      slot.sell.trinketId = slot.def.id -- identity captured at render time
      slot.sell:Show()
    else
      slot.sell:Hide()
    end
  end
end

-- onSellFn(slotIndex, trinketId) is called when a sell button is clicked.
function TrinketRow.SetSellMode(enabled, onSellFn)
  sellMode = enabled and true or false
  onSell = enabled and onSellFn or nil
  refreshSell()
end

---------------------------------------------------------------------------
-- Drag to reorder. Press, move past PICKUP pixels, and the slot lifts and follows
-- the cursor; the others slide aside live. Release over the row commits through
-- Run.moveTrinket; anywhere else (or while a hand resolves) everything glides back.

local function rowFrame() return ns.UI.Main and ns.UI.Main.trinketRow end

-- Cursor position in the row's own units.
local function cursor()
  local frame = rowFrame()
  local x, y = GetCursorPosition()
  local scale = frame:GetEffectiveScale()
  return x / scale, y / scale, x
end

-- The frame indices in display order while slot `from` is held over position `target`.
local function dragOrder(from, target, n)
  local order = {}
  for i = 1, n do
    if i ~= from then order[#order + 1] = i end
  end
  table.insert(order, target, from)
  return order
end

local function shiftOthers(p)
  local frame = rowFrame()
  local order = dragOrder(p.from, p.target, p.n)
  for k, i in ipairs(order) do
    if i ~= p.from then Tween().To(frame.slots[i], { x = slotX(k) }, SHIFT_TIME) end
  end
end

local function beginDrag(p)
  local frame = rowFrame()
  local slot = p.slot
  p.active = true
  p.from = slot.index
  p.n = #currentRun.trinkets
  p.target = p.from
  p.startX = slotX(p.from)
  GameTooltip:Hide()
  slot.sell:Hide()
  Tween().Cancel(slot)
  slot.holder:SetScript("OnUpdate", nil) -- a pulse in flight would fight the lift
  slot:SetFrameLevel(frame:GetFrameLevel() + 30)
  Tween().To(slot.holder, { scale = LIFT }, LIFT_TIME)
end

local function endPress(p)
  p.slot:SetScript("OnUpdate", nil)
  if press == p then press = nil end
end

-- Everything glides back to the grid; the order is unchanged.
local function snapBack(p)
  local frame = rowFrame()
  for i = 1, p.n do
    local s = frame.slots[i]
    if s ~= p.slot then Tween().To(s, { x = slotX(i) }, SHIFT_TIME) end
  end
  local slot = p.slot
  Tween().To(slot, { x = slotX(p.from) }, SHIFT_TIME)
  Tween().To(slot.holder, { scale = 1 }, SHIFT_TIME, function() slot:SetFrameLevel(slot.baseLevel) end)
  refreshSell()
end

local function drop(p)
  local frame = rowFrame()
  local run = ns.UI.Main.run
  local over = frame:IsMouseOver(12, -12, -12, 12) -- a little slack above and below the row
  if not over or locked() or run ~= currentRun or p.target == p.from
    or not run.trinkets[p.from] or #run.trinkets ~= p.n then
    return snapBack(p)
  end
  -- Record where everything is now so the re-render glides from here, not from the old order.
  local order = dragOrder(p.from, p.target, p.n)
  for k, i in ipairs(order) do
    local t = run.trinkets[i]
    if t.uid then lastX[t.uid] = (i == p.from) and p.x or slotX(k) end
  end
  settle = { uid = run.trinkets[p.from].uid, scale = LIFT }
  if not ns.Run.moveTrinket(run, p.from, p.target) then
    settle = nil
    return snapBack(p)
  end
  if ns.UI.OnRunChanged then ns.UI.OnRunChanged() end
  TrinketRow.Update(run)
end

local function onDragUpdate(slot)
  local p = press
  if not p or p.slot ~= slot then return endPress({ slot = slot }) end
  if not IsMouseButtonDown("LeftButton") then -- the release went elsewhere
    endPress(p)
    if p.active then drop(p) end
    return
  end
  local cx, _, raw = cursor()
  if not p.active then
    if math.abs(raw - p.rawX) <= PICKUP or locked() or not currentRun then return end
    beginDrag(p)
  end
  p.x = p.startX + (cx - p.cx)
  slot:SetPoint("LEFT", rowFrame(), "LEFT", p.x, 0)
  local target = math.max(1, math.min(p.n, math.floor(p.x / pitch + 0.5) + 1))
  if target ~= p.target then
    p.target = target
    shiftOthers(p)
  end
end

local function onMouseDown(slot, button)
  if button ~= "LeftButton" or not slot.def or slot.dying then return end
  local cx, _, raw = cursor()
  press = { slot = slot, cx = cx, rawX = raw }
  slot:SetScript("OnUpdate", onDragUpdate)
end

local function onMouseUp(slot)
  local p = press
  if not p or p.slot ~= slot then return end
  endPress(p)
  if p.active then drop(p) end
end

---------------------------------------------------------------------------

local function makeSlot(frame, i)
  local slot = CreateFrame("Frame", nil, frame)
  slot:SetSize(SLOT_SIZE, SLOT_SIZE)
  slot:SetPoint("LEFT", frame, "LEFT", (i - 1) * (SLOT_SIZE + SLOT_GAP), 0)
  slot.index = i
  slot.baseLevel = slot:GetFrameLevel()
  slot:EnableMouse(true)
  slot.holder = CreateFrame("Frame", nil, slot)
  slot.holder:SetSize(SLOT_SIZE, SLOT_SIZE)
  slot.holder:SetPoint("CENTER", slot, "CENTER")
  slot.empty = Theme.EmptySlot(slot.holder)
  slot.icon = slot.holder:CreateTexture(nil, "ARTWORK")
  slot.icon:SetAllPoints()
  slot.icon:Hide()
  local sell = Theme.NewButton(slot, nil, SELL_W, SELL_H)
  sell:SetPoint("TOP", slot, "BOTTOM", 0, -1)
  sell:SetScript("OnClick", function()
    if onSell then onSell(i, sell.trinketId) end
  end)
  sell:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Sell for " .. (self.price or 0) .. "g", 1, 1, 1)
    GameTooltip:Show()
  end)
  sell:SetScript("OnLeave", function() GameTooltip:Hide() end)
  sell:Hide()
  slot.sell = sell
  slot:SetScript("OnEnter", showTooltip)
  slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
  slot:SetScript("OnMouseDown", onMouseDown)
  slot:SetScript("OnMouseUp", onMouseUp)
  frame.slots[i] = slot
  return slot
end

function TrinketRow.Build(frame)
  frame.slots = {}
  frame:SetScript("OnHide", function()
    GameTooltip:Hide()
    if press then endPress(press) end
  end)
  for i = 1, MIN_SLOTS do makeSlot(frame, i) end
end

function TrinketRow.Update(run)
  local frame = ns.UI.Main and ns.UI.Main.trinketRow
  if not frame or not frame.slots then return end
  if press then endPress(press) end -- a render ends any drag; the order only ever changes on release
  currentRun = run
  local trinkets = run and run.trinkets or {}
  local count = run and ns.Run.trinketSlots(run) or MIN_SLOTS
  for i = #frame.slots + 1, count do makeSlot(frame, i) end
  -- Tighten the spacing (never below touching) when the row is crowded.
  local newPitch = SLOT_SIZE + SLOT_GAP
  if count > 1 and frame:GetWidth() > 0 then
    newPitch = math.max(SLOT_SIZE, math.min(newPitch, (frame:GetWidth() - SLOT_SIZE) / (count - 1)))
  end
  if newPitch ~= pitch then lastX = {} end
  pitch = newPitch
  local shown = {}
  for i = 1, #frame.slots do
    local slot = frame.slots[i]
    slot:SetShown(i <= count)
    local entry = trinkets[i]
    local def = entry and ns.Trinkets.def[entry.id]
    local x = slotX(i)
    -- A slot that moved since the last render glides from where its trinket was.
    local from = def and entry.uid and lastX[entry.uid]
    Tween().Cancel(slot)
    Tween().Cancel(slot.holder)
    slot.holder:SetScript("OnUpdate", nil)
    slot.holder:SetAlpha(1)
    slot.holder:SetScale(1)
    slot:SetFrameLevel(slot.baseLevel)
    slot.dying = nil
    slot:ClearAllPoints()
    if from and from ~= x and slot:IsShown() then
      slot:SetPoint("LEFT", frame, "LEFT", from, 0)
      Tween().To(slot, { x = x }, SHIFT_TIME)
    else
      slot:SetPoint("LEFT", frame, "LEFT", x, 0)
    end
    if def and entry.uid then
      shown[entry.uid] = x
      if settle and settle.uid == entry.uid then
        slot:SetFrameLevel(slot.baseLevel + 30) -- the dropped slot glides over its neighbours
        slot.holder:SetScale(settle.scale)
        Tween().To(slot.holder, { scale = 1 }, SHIFT_TIME, function() slot:SetFrameLevel(slot.baseLevel) end)
      end
    end
    slot.def = def
    slot.trinket = entry
    slot.empty:SetShown(not def)
    slot.icon:SetShown(def ~= nil)
    if def then slot.icon:SetTexture(def.icon) end
    ns.UI.EditionFX.Attach(slot.holder, def and entry.ed or nil)
  end
  settle = nil
  lastX = shown
  refreshSell()
  -- An open tooltip shows the new state (status values, what a copier copies).
  local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
  if owner and owner.index and frame.slots[owner.index] == owner then showTooltip(owner) end
end

-- The slot frame currently showing the trinket with this uid, or nil.
function TrinketRow.SlotByUid(uid)
  local frame = rowFrame()
  if not uid or not frame or not frame.slots then return nil end
  for _, slot in ipairs(frame.slots) do
    if slot.trinket and slot.trinket.uid == uid and slot:IsShown() then return slot end
  end
end

-- Short scale pulse on a slot frame; driven by OnUpdate, no AnimationGroup.
function TrinketRow.PulseSlot(slot)
  if not slot or slot.dying then return end
  local DURATION = 0.3
  local t = 0
  local holder = slot.holder
  holder:SetScript("OnUpdate", function(self, elapsed)
    t = t + elapsed
    if t >= DURATION then
      self:SetScale(1)
      self:SetScript("OnUpdate", nil)
      return
    end
    self:SetScale(1 + 0.3 * math.sin(math.pi * t / DURATION))
  end)
end

-- Pulse on slot `index` (1-5); the shop and packs know the slot, not the uid.
function TrinketRow.Pulse(index)
  local frame = rowFrame()
  TrinketRow.PulseSlot(frame and frame.slots and frame.slots[index])
end

function TrinketRow.PulseUid(uid)
  TrinketRow.PulseSlot(TrinketRow.SlotByUid(uid))
end

-- Fades and shrinks the slot showing `uid`. The next Update (after the tally) clears it.
function TrinketRow.Destroy(uid, duration)
  local slot = TrinketRow.SlotByUid(uid)
  if not slot then return end
  slot.dying = true
  slot.holder:SetScript("OnUpdate", nil)
  Tween().To(slot.holder, { scale = 0.3, alpha = 0 }, duration or 0.3)
end

ns.UI.TrinketRow = TrinketRow
