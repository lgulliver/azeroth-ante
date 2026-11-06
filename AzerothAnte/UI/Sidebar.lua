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
  frame.xMark = x

  -- Profile totals, shown instead of the round stats on the deck-select screen.
  frame.profileTitle = fontString(frame, Theme.fonts.title, "TOPLEFT", m, -m, w)
  frame.profileTitle:SetText("Your profile")
  Theme.setColor(frame.profileTitle, Theme.gold)
  local y = -52
  for _, key in ipairs({ "profileRuns", "profileWins", "profileBest", "profileDecks", "profileFound" }) do
    frame[key] = fontString(frame, Theme.fonts.text, "TOPLEFT", m, y, w)
    Theme.setColor(frame[key], Theme.parchment)
    y = y - 26
  end

  frame.hands = fontString(frame, Theme.fonts.text, "TOPLEFT", m, -250, w)
  frame.discards = fontString(frame, Theme.fonts.text, "TOPLEFT", m, -272, w)
  frame.gold = fontString(frame, Theme.fonts.title, "TOPLEFT", m, -302, w)
  Theme.setColor(frame.gold, Theme.gold)
  frame.stage = fontString(frame, Theme.fonts.text, "TOPLEFT", m, -332, w)
  Theme.setColor(frame.stage, Theme.parchment)

  local deck = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  deck:SetSize(w, 26)
  deck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", m, m)
  deck:SetText("Deck (0)")
  deck:SetScript("OnClick", function()
    ns.UI.DeckView.Toggle(ns.UI.Main and ns.UI.Main.run)
  end)
  frame.deckButton = deck
end

-- The round stats show during a run; the profile totals show on the deck-select screen.
local ROUND_WIDGETS = { "blindName", "bossRule", "targetLabel", "target", "scoreLabel", "score", "chipsBox",
  "multBox", "xMark", "handName", "hands", "discards", "gold", "stage", "deckButton" }
local PROFILE_WIDGETS = { "profileTitle", "profileRuns", "profileWins", "profileBest", "profileDecks", "profileFound" }

local function showGroup(frame, names, shown)
  for _, key in ipairs(names) do
    if frame[key] then frame[key]:SetShown(shown) end
  end
end

local function showProfile(frame)
  local t = ns.UI.DeckSelect.Totals()
  frame.profileRuns:SetText("Runs: " .. t.runs)
  frame.profileWins:SetText("Wins: " .. t.wins)
  frame.profileBest:SetText("Best stage: " .. t.best)
  frame.profileDecks:SetText("Decks unlocked: " .. t.decks .. "/" .. t.totalDecks)
  frame.profileFound:SetText("Discovered: " .. t.found .. "/" .. t.totalFound)
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
    frame.targetLabel:SetText("Score at least")
    frame.deckButton:SetText("Deck (0)")
    ns.UI.DeckView.Hide()
    showGroup(frame, ROUND_WIDGETS, false)
    showGroup(frame, PROFILE_WIDGETS, true)
    showProfile(frame)
    return
  end
  showGroup(frame, ROUND_WIDGETS, true)
  showGroup(frame, PROFILE_WIDGETS, false)

  local bossId = ns.Run.bossId(run)
  local boss = bossId and ns.Bosses.def[bossId]
  if boss then
    frame.blindName:SetText(boss.name)
    frame.bossRule:SetText(boss.desc or "")
  else
    frame.blindName:SetText(BLIND_NAMES[run.blind] or "")
    frame.bossRule:SetText("")
  end
  -- Run.nextBlind leaves the old target/score in place, so the blind screen
  -- shows the upcoming blind's target and a zero score. The shop screen shows
  -- the just-finished blind's values, labelled as such.
  local target, score = run.target, run.score
  if run.phase == "blind" then
    target, score = ns.Run.target(run.stage, run.blind, bossId), 0
  end
  frame.targetLabel:SetText(run.phase == "shop" and "Cleared blind, target was" or "Score at least")
  frame.target:SetText(tostring(target or 0))
  frame.score:SetText(tostring(score or 0))
  frame.chipsBox.text:SetText(tostring(chips or 0))
  frame.multBox.text:SetText(tostring(mult or 0))
  frame.handName:SetText("")
  frame.hands:SetText("Hands: " .. tostring(run.handsLeft or 0))
  frame.discards:SetText("Discards: " .. tostring(run.discardsLeft or 0))
  frame.gold:SetText("Gold: " .. tostring(run.gold or 0))
  frame.stage:SetText("Stage " .. tostring(run.stage or 1) .. " / 8 - Blind " .. tostring(run.blind or 1) .. " / 3")
  frame.deckButton:SetText("Deck (" .. #(run.deck or {}) .. ")")
  ns.UI.DeckView.Refresh(run)
end

local function round2(n)
  n = tonumber(n) or 0
  return math.floor(n * 100 + 0.5) / 100
end
Sidebar.round2 = round2

-- Fine-grained setters for the score tally (no run needed).
function Sidebar.SetScore(n)
  local frame = ns.UI.Main and ns.UI.Main.sidebar
  if frame and frame.score then frame.score:SetText(tostring(n)) end
end

function Sidebar.SetChipsMult(chips, mult, handName)
  local frame = ns.UI.Main and ns.UI.Main.sidebar
  if not frame or not frame.chipsBox then return end
  frame.chipsBox.text:SetText(tostring(round2(chips)))
  frame.multBox.text:SetText(tostring(round2(mult)))
  if handName then frame.handName:SetText(handName) end
end

ns.UI.Sidebar = Sidebar
