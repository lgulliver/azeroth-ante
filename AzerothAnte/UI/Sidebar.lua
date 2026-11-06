local _, ns = ...

local Theme = ns.UI.Theme
local Sidebar = {}

local BLIND_NAMES = { "Small Blind", "Big Blind" }
local ICON_W, ICON_H = 40, math.floor(40 * 7 / 5 + 0.5) -- a card back, 5:7

local function fontString(parent, font, point, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint(point, parent, point, x, y)
  if width then
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
  end
  return fs
end

-- A chips or mult tile: a gradient fill with no outline (Theme.Tile).
local function statBox(parent, kind, x, y, w, h)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(w, h)
  box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  Theme.Tile(box, kind)
  box.text = box:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
  box.text:SetPoint("CENTER", box, "CENTER", 0, 0)
  Theme.setColor(box.text, box.tileText)
  return box
end

-- Builds the sidebar widgets inside `frame` (the .sidebar region). The sections
-- are separated by thin dim gold rules, on an 8px rhythm.
function Sidebar.Build(frame)
  local m = Theme.margin
  local w = frame:GetWidth() - 2 * m
  Theme.Inset(frame)
  frame.rules = { round = {}, blind = {}, profile = {} }
  local function rule(group, y) frame.rules[group][#frame.rules[group] + 1] = Theme.Rule(frame, y, m) end

  frame.blindName = fontString(frame, Theme.fonts.title, "TOPLEFT", m, -m, w)
  Theme.Value(frame.blindName, true)
  frame.bossRule = fontString(frame, Theme.fonts.small, "TOPLEFT", m, -32, w)
  Theme.setColor(frame.bossRule, Theme.parchment)
  frame.bossRule:SetHeight(32)
  frame.bossRule:SetJustifyV("TOP")
  rule("round", -72)

  frame.targetLabel = fontString(frame, Theme.fonts.small, "TOPLEFT", m, -80, w)
  frame.targetLabel:SetText("Score at least")
  Theme.Label(frame.targetLabel)
  frame.target = fontString(frame, Theme.fonts.big, "TOPLEFT", m, -96, w)
  Theme.Value(frame.target, true)
  frame.scoreLabel = fontString(frame, Theme.fonts.small, "TOPLEFT", m, -136, w)
  frame.scoreLabel:SetText("Round score")
  Theme.Label(frame.scoreLabel)
  frame.score = fontString(frame, Theme.fonts.big, "TOPLEFT", m, -152, w)
  Theme.Value(frame.score, false)
  rule("round", -192)

  local gap = 24
  local boxW = (w - gap) / 2
  frame.chipsBox = statBox(frame, "chips", m, -200, boxW, 40)
  frame.multBox = statBox(frame, "mult", m + boxW + gap, -200, boxW, 40)
  frame.handName = fontString(frame, Theme.fonts.small, "TOPLEFT", m, -244, w)
  Theme.Value(frame.handName, true)
  local x = frame:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
  x:SetPoint("LEFT", frame.chipsBox, "RIGHT", 0, 0)
  x:SetPoint("RIGHT", frame.multBox, "LEFT", 0, 0)
  x:SetText("\195\151") -- the multiplication sign, in gold
  Theme.setColor(x, Theme.goldBright)
  frame.xMark = x
  rule("round", -264)

-- Profile totals, shown instead of the round stats on the deck-select screen.
  frame.profileTitle = fontString(frame, Theme.fonts.title, "TOPLEFT", m, -m, w)
  frame.profileTitle:SetText("Your profile")
  Theme.Value(frame.profileTitle, true)
  rule("profile", -40)
  local y = -48
  for _, key in ipairs({ "profileRuns", "profileWins", "profileBest", "profileDecks", "profileFound" }) do
    frame[key] = fontString(frame, Theme.fonts.text, "TOPLEFT", m, y, w)
    Theme.Value(frame[key], false)
    y = y - 24
  end

  frame.hands = fontString(frame, Theme.fonts.text, "TOPLEFT", m, -272, w)
  Theme.Value(frame.hands, false)
  frame.discards = fontString(frame, Theme.fonts.text, "TOPLEFT", m, -296, w)
  Theme.Value(frame.discards, false)
  rule("round", -320)
  frame.gold = fontString(frame, Theme.fonts.title, "TOPLEFT", m, -328, w)
  Theme.Value(frame.gold, true)
  frame.stage = fontString(frame, Theme.fonts.text, "TOPLEFT", m, -360, w)
  Theme.Value(frame.stage, false)

  -- Blind screen only: the deck, with its small back icon, above the run info.
  frame.deckIcon = frame:CreateTexture(nil, "ARTWORK")
  frame.deckIcon:SetSize(ICON_W, ICON_H)
  frame.deckIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", m, -m)
  frame.deckIcon:SetTexCoord(0, 1, 0, Theme.cardV)
  frame.deckName = fontString(frame, Theme.fonts.title, "TOPLEFT", m + ICON_W + 8, -m - 4, w - ICON_W - 8)
  frame.deckName:SetHeight(ICON_H - 8)
  frame.deckName:SetJustifyV("TOP")
  Theme.Value(frame.deckName, true)
  rule("blind", -72)

  local deck = Theme.NewButton(frame, nil, w, 28)
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
-- The blind screen shows run info instead of the blind and the round score.
local BLIND_WIDGETS = { "deckIcon", "deckName", "hands", "discards", "gold", "stage", "deckButton" }
-- Where the shared rows sit: below the deck line on the blind screen, as before otherwise.
local ROW_Y = {
  round = { hands = -272, discards = -296, gold = -328, stage = -360 },
  blind = { stage = -80, gold = -108, hands = -148, discards = -172 },
}
local PROFILE_WIDGETS = { "profileTitle", "profileRuns", "profileWins", "profileBest", "profileDecks", "profileFound" }

local RULE_GROUP = { [ROUND_WIDGETS] = "round", [BLIND_WIDGETS] = "blind", [PROFILE_WIDGETS] = "profile" }

local function showGroup(frame, names, shown)
  for _, key in ipairs(names) do
    if frame[key] then frame[key]:SetShown(shown) end
  end
  local rules = frame.rules and frame.rules[RULE_GROUP[names]]
  if rules then
    for _, r in ipairs(rules) do r:SetShown(shown) end
  end
end

local function layoutRows(frame, mode)
  if frame.rowMode == mode then return end
  frame.rowMode = mode
  for key, y in pairs(ROW_Y[mode]) do
    frame[key]:ClearAllPoints()
    frame[key]:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.margin, y)
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
    showGroup(frame, BLIND_WIDGETS, false)
    showGroup(frame, PROFILE_WIDGETS, true)
    showProfile(frame)
    return
  end
  showGroup(frame, ROUND_WIDGETS, false)
  showGroup(frame, BLIND_WIDGETS, false)
  showGroup(frame, PROFILE_WIDGETS, false)
  if run.phase == "blind" then
    layoutRows(frame, "blind")
    showGroup(frame, BLIND_WIDGETS, true)
    local deck = ns.Decks.def[run.deckId]
    local bossId = run.bosses and run.bosses[run.stage]
    local boss = run.blind == 3 and bossId and ns.Bosses.def[bossId] or nil
    frame.deckName:SetText(deck and deck.name or "")
    frame.deckIcon:SetTexture(ns.UI.CardWidget.BackPath(run.deckId))
    -- Hands and discards the upcoming blind will start with (a boss may override them).
    frame.hands:SetText("Hands: " .. tostring((boss and boss.hands) or (deck and deck.hands) or 0))
    frame.discards:SetText("Discards: " .. tostring(boss and boss.discards or (deck and deck.discards) or 0))
    frame.gold:SetText("Gold: " .. tostring(run.gold or 0))
    frame.stage:SetText("Stage " .. tostring(run.stage or 1) .. " / 8")
    frame.deckButton:SetText("Deck (" .. #(run.deck or {}) .. ")")
    ns.UI.DeckView.Refresh(run)
    return
  end
  layoutRows(frame, "round")
  showGroup(frame, ROUND_WIDGETS, true)

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
