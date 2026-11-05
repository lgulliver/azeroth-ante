local _, ns = ...

local Theme = ns.UI.Theme
local Sidebar = {}

local BLIND_NAMES = { "Small Blind", "Big Blind" }

local function fontString(parent, font, point, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint(point, parent, point, x, y)
  if width then
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
  end
  return fs
end

local function statBox(parent, color, x, y, w, h)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(w, h)
  box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
  })
  box:SetBackdropColor(color[1] * 0.3, color[2] * 0.3, color[3] * 0.3, 0.9)
  box:SetBackdropBorderColor(color[1], color[2], color[3], 1)
  box.text = box:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
  box.text:SetPoint("CENTER")
  Theme.setColor(box.text, color)
  return box
end

-- Builds the sidebar widgets inside `frame` (the .sidebar region).
function Sidebar.Build(frame)
  local w = frame:GetWidth() - 2 * Theme.margin
  local m = Theme.margin
  frame.blindName = fontString(frame, Theme.fonts.title, "TOPLEFT", m, -m, w)
  Theme.setColor(frame.blindName, Theme.gold)
  frame.bossRule = fontString(frame, Theme.fonts.small, "TOPLEFT", m, -m - 24, w)
  Theme.setColor(frame.bossRule, Theme.parchment)
  frame.bossRule:SetHeight(32)
  frame.bossRule:SetJustifyV("TOP")

  frame.targetLabel = fontString(frame, Theme.fonts.small, "TOPLEFT", m, -80, w)
  frame.targetLabel:SetText("Score at least")
  frame.target = fontString(frame, Theme.fonts.big, "TOPLEFT", m, -96, w)
  Theme.setColor(frame.target, Theme.gold)
  frame.scoreLabel = fontString(frame, Theme.fonts.small, "TOPLEFT", m, -132, w)
  frame.scoreLabel:SetText("Round score")
  frame.score = fontString(frame, Theme.fonts.big, "TOPLEFT", m, -148, w)
  Theme.setColor(frame.score, Theme.parchment)

  local boxW = (w - 24) / 2
  frame.chipsBox = statBox(frame, Theme.chips, m, -190, boxW, 40)
  frame.multBox = statBox(frame, Theme.mult, m + boxW + 24, -190, boxW, 40)
  frame.handName = fontString(frame, Theme.fonts.small, "TOPLEFT", m, -233, w)
  Theme.setColor(frame.handName, Theme.gold)
  local x = frame:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
  x:SetPoint("LEFT", frame.chipsBox, "RIGHT", 0, 0)
  x:SetPoint("RIGHT", frame.multBox, "LEFT", 0, 0)
  x:SetText("X")

  frame.hands = fontString(frame, Theme.fonts.text, "TOPLEFT", m, -250, w)
  frame.discards = fontString(frame, Theme.fonts.text, "TOPLEFT", m, -272, w)
  frame.gold = fontString(frame, Theme.fonts.title, "TOPLEFT", m, -302, w)
  Theme.setColor(frame.gold, Theme.gold)
  frame.stage = fontString(frame, Theme.fonts.text, "TOPLEFT", m, -332, w)
  Theme.setColor(frame.stage, Theme.parchment)
end

-- chips and mult are optional (shown as 0 when nil), for live scoring display.
function Sidebar.Update(run, chips, mult)
  local frame = ns.UI.Main and ns.UI.Main.sidebar
  if not frame or not frame.blindName then return end

  if not run then
    frame.blindName:SetText("")
    frame.bossRule:SetText("")
    frame.target:SetText("")
    frame.score:SetText("")
    frame.hands:SetText("")
    frame.discards:SetText("")
    frame.gold:SetText("")
    frame.stage:SetText("")
    frame.chipsBox.text:SetText("0")
    frame.multBox.text:SetText("0")
    frame.handName:SetText("")
    return
  end

  local bossId = ns.Run.bossId(run)
  local boss = bossId and ns.Bosses.def[bossId]
  if boss then
    frame.blindName:SetText(boss.name)
    frame.bossRule:SetText(boss.desc or "")
  else
    frame.blindName:SetText(BLIND_NAMES[run.blind] or "")
    frame.bossRule:SetText("")
  end
  frame.target:SetText(tostring(run.target or 0))
  frame.score:SetText(tostring(run.score or 0))
  frame.chipsBox.text:SetText(tostring(chips or 0))
  frame.multBox.text:SetText(tostring(mult or 0))
  frame.handName:SetText("")
  frame.hands:SetText("Hands: " .. tostring(run.handsLeft or 0))
  frame.discards:SetText("Discards: " .. tostring(run.discardsLeft or 0))
  frame.gold:SetText("Gold: " .. tostring(run.gold or 0))
  frame.stage:SetText("Stage " .. tostring(run.stage or 1) .. " / 8 - Blind " .. tostring(run.blind or 1) .. " / 3")
end

-- Fine-grained setters for the score tally (no run needed).
function Sidebar.SetScore(n)
  local frame = ns.UI.Main and ns.UI.Main.sidebar
  if frame and frame.score then frame.score:SetText(tostring(n)) end
end

function Sidebar.SetChipsMult(chips, mult, handName)
  local frame = ns.UI.Main and ns.UI.Main.sidebar
  if not frame or not frame.chipsBox then return end
  frame.chipsBox.text:SetText(tostring(chips or 0))
  frame.multBox.text:SetText(tostring(mult or 0))
  if handName then frame.handName:SetText(handName) end
end

ns.UI.Sidebar = Sidebar
