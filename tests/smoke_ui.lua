-- Headless UI smoke run. Usage: luajit tests/smoke_ui.lua   (from the repo root)
-- Loads every file in the .toc against the WoW API stub and scripts a full
-- session through the real UI code. Exits 0 on success, 1 on any error.
local wowstub = dofile("tests/wowstub.lua")

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[deepCopy(k)] = deepCopy(x) end
  return out
end

local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deepEq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function check(cond, msg)
  if not cond then error("ASSERT FAILED: " .. msg, 2) end
end

local function eq(a, b, msg)
  if a ~= b then error(("ASSERT FAILED: %s (got %s, want %s)"):format(msg, tostring(a), tostring(b)), 2) end
end

-- Creates a fresh WoW environment and loads every .toc file into it.
local ALLOWED_GLOBALS = { AzerothAnteDB = true, SLASH_AZEROTHANTE1 = true }
local function newWorld(db)
  local world = { newGlobals = {} }
  local env = setmetatable({}, {
    __index = _G,
    __newindex = function(t, k, v)
      world.newGlobals[k] = true
      rawset(t, k, v)
    end,
  })
  world.env = env
  world.stub = wowstub.install(env)
  world.ns = {}
  rawset(env, "AzerothAnteDB", db)

  local toc = assert(io.open("AzerothAnte/AzerothAnte.toc", "r"))
  for line in toc:lines() do
    line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local chunk = assert(loadfile("AzerothAnte/" .. line:gsub("\\", "/")))
      setfenv(chunk, env)("AzerothAnte", world.ns)
    end
  end
  toc:close()
  world.stub.fire("ADDON_LOADED", "AzerothAnte")
  return world
end

local function run(w)
  local w1st = w
  local ns, stub, env = w.ns, w.stub, w.env
  local Main, HandView, Tally = ns.UI.Main, ns.UI.HandView, ns.UI.Tally

  local function step(name) print("ok  " .. name) end

  -- Finds a screen panel under the canvas by a field only that panel has.
  local function panel(field)
    for _, c in ipairs(Main.content._children) do
      if c[field] then return c end
    end
  end
  local function visible(field)
    local p = panel(field)
    return p ~= nil and p:IsVisible()
  end

  -- A real click: the frame must be visible, enabled and accept the mouse.
  local function click(f, what)
    check(f, "missing frame: " .. what)
    check(f:IsVisible(), what .. " is not visible")
    check(f:IsEnabled(), what .. " is disabled")
    check(f:IsMouseEnabled(), what .. " does not accept the mouse")
    f:Click()
  end

  local function handWidgets()
    local out = {}
    for _, c in ipairs(Main.handArea._children) do
      if c.card and not c.released and c:IsShown() then out[#out + 1] = c end
    end
    table.sort(out, function(a, b) return a._points[1][4] < b._points[1][4] end)
    return out
  end

  local function selectCard(i)
    local w = handWidgets()[i or 1]
    click(w, "hand card " .. tostring(i or 1))
    check(w.selected, "card did not become selected")
  end

  local function playSelected()
    click(Main.buttons.play, "Play button")
  end

  local function open()
    env.SlashCmdList.AZEROTHANTE()
    stub.advance(1)
  end

  -- Picks a deck in the carousel (unlocking it in the profile first) and presses Play.
  local function startDeck(id)
    local profile = ns.Profile.get(env.AzerothAnteDB)
    local need = ns.Profile.unlockThreshold(id)
    for i = ns.Profile.discoveredCount(env.AzerothAnteDB) + 1, need do profile.discovered["test:" .. i] = true end
    local p = panel("carousel")
    ns.UI.DeckSelect.Select(id, true)
    click(p.play, "Play " .. id)
  end

  -- 1. Open the window.
  open()
  check(Main.frame:IsShown(), "window not shown after /ante")
  check(visible("carousel"), "deck-select screen not visible")
  step("1 slash opens window on the deck-select screen")

  -- 1b. The carousel: ROGUE centred on a fresh profile, arrows, locks, sidebar totals.
  local DS = ns.UI.DeckSelect
  local CardWidget = ns.UI.CardWidget
  do
    local p = panel("carousel")
    local sb = Main.sidebar
    eq(DS.Selected(), "ROGUE", "ROGUE is centred on a fresh profile")
    local function cardArt(id) return DS.Card(id).art:GetTexture() or "" end
    check(cardArt("ROGUE"):find("BackSq_ROGUE", 1, true), "the centre card shows the Rogue back")
    check(math.abs(DS.Card("ROGUE"):GetWidth() - CardWidget.WIDTH * 1.35) < 0.5, "centre card is 1.35x a playing card")
    check(math.abs(DS.Card("WARRIOR"):GetWidth() - CardWidget.WIDTH * 0.8) < 0.5, "neighbours are 0.8x")
    check(DS.Card("WARRIOR"):IsShown() and DS.Card("WARLOCK"):IsShown(), "both neighbours peek")
    check(not DS.Card("GOBLIN"):IsShown(), "decks two away are hidden")
    eq(p.name:GetText(), "Rogue Deck", "deck name")
    eq(p.desc:GetText(), "+1 discard every round", "rule text")
    eq(p.stats:GetText(), "4 hands \194\183 4 discards \194\183 4g", "deck numbers")
    eq(p.best:GetText(), "Best: Stage 0 \194\183 Wins: 0", "profile stats for the deck")
    check(p.play:IsEnabled(), "Rogue is playable")
    check(not p.progress:IsShown(), "no progress bar on an unlocked deck")
    check(not DS.Card("ROGUE").lock:IsShown(), "no padlock on the open deck")
    -- Sidebar: profile totals, no round stats; rows hidden.
    eq(sb.profileRuns:GetText(), "Runs: 0", "sidebar runs")
    eq(sb.profileWins:GetText(), "Wins: 0", "sidebar wins")
    eq(sb.profileBest:GetText(), "Best stage: 0", "sidebar best stage")
    eq(sb.profileDecks:GetText(), "Decks unlocked: 1/5", "sidebar decks unlocked")
    eq(sb.profileFound:GetText(), "Discovered: 0/" .. ns.Profile.totalDiscoverable(), "sidebar discovered")
    check(not sb.targetLabel:IsShown() and not sb.scoreLabel:IsShown() and not sb.chipsBox:IsShown()
      and not sb.multBox:IsShown() and not sb.hands:IsShown() and not sb.gold:IsShown(), "round stats hidden")
    check(not sb.deckButton:IsShown(), "Deck button hidden on the select screen")
    check(not Main.trinketRow:IsShown() and not Main.consumableRow:IsShown(), "item rows hidden")

    -- Arrows slide with a tween and wrap.
    click(p.nextBtn, "next arrow")
    eq(DS.Selected(), "WARRIOR", "next arrow selects WARRIOR")
    stub.advance(0.1)
    local mid = DS.Card("WARRIOR"):GetWidth()
    check(mid > CardWidget.WIDTH * 0.8 + 1 and mid < CardWidget.WIDTH * 1.35 - 1, "the slide is mid-tween at 0.1s (" .. mid .. ")")
    stub.advance(0.3)
    check(math.abs(DS.Card("WARRIOR"):GetWidth() - CardWidget.WIDTH * 1.35) < 0.5, "slide settled")
    check(DS.Card("WARRIOR").lock:IsShown() and DS.Card("WARRIOR").art:IsDesaturated(), "locked deck: padlock and desaturated art")
    check(not p.play:IsEnabled(), "locked deck: Play disabled")
    local warriorNeed = ns.Profile.unlockThreshold("WARRIOR")
    local warlockNeed = ns.Profile.unlockThreshold("WARLOCK")
    local warriorText = ("Discover %d items to unlock (0/%d)"):format(warriorNeed, warriorNeed)
    check(p.play.reason and p.play.reason:find(warriorText, 1, true), "locked deck: reason")
    p.play._scripts.OnEnter(p.play)
    check(stub.tooltip:IsShown() and stub.tooltip._tipText:find("Discover " .. warriorNeed, 1, true), "reason tooltip on hover")
    p.play._scripts.OnLeave(p.play)
    eq(p.desc:GetText(), warriorText, "unlock text replaces the rule")
    check(p.progress:IsShown(), "progress bar on a locked deck")
    p.play:Click()
    check(Main.run == nil, "a disabled Play does not start a run")
    click(p.prevBtn, "prev arrow")
    click(p.prevBtn, "prev arrow (wrap)")
    stub.advance(0.5)
    eq(DS.Selected(), "WARLOCK", "prev wraps around to WARLOCK")
    eq(p.desc:GetText(), ("Discover %d items to unlock (0/%d)"):format(warlockNeed, warlockNeed), "locked text for Warlock")
    click(p.nextBtn, "next arrow (wrap)")
    stub.advance(0.5)
    eq(DS.Selected(), "ROGUE", "next wraps back to ROGUE")
    -- Clicking a peeking deck slides to it.
    click(DS.Card("WARRIOR"), "peeking WARRIOR")
    eq(DS.Selected(), "WARRIOR", "clicking the right neighbour selects it")
    stub.advance(0.5)
    click(DS.Card("ROGUE"), "peeking ROGUE")
    stub.advance(0.5)
    eq(DS.Selected(), "ROGUE", "clicking the left neighbour selects it")
  end
  step("1b deck-select carousel, locks, arrows and sidebar totals")

  -- 2. Play on the chosen deck, then Start Blind.
  local newrun = panel("carousel")
  click(newrun.play, "Play")
  stub.advance(1)
  eq(Main.run.deckId, "ROGUE", "Play starts a run with the chosen deck")
  eq(env.AzerothAnteDB.profile.lastDeck, "ROGUE", "the last-played deck is stored")
  check(Main.sidebar.gold:IsShown() and Main.sidebar.deckButton:IsShown(), "run info returns in a run")
  check(not Main.sidebar.profileRuns:IsShown(), "profile totals hide in a run")
  check(Main.trinketRow:IsShown() and Main.consumableRow:IsShown(), "item rows return in a run")
  check(HandView.deck:GetTexture():find("Back_ROGUE", 1, true), "the deck pile uses the deck's back")
  eq(CardWidget.BackPath("ADVENTURER"):match("[^\\]+$"), "CardBack", "ADVENTURER keeps the plain back")
  eq(CardWidget.BackPath("NOPE"):match("[^\\]+$"), "CardBack", "an unknown deck keeps the plain back")
  eq(Main.run.phase, "blind", "phase after Play")
  check(visible("preview"), "blind screen not visible")

  -- 2-pre. The Balatro-style blind screen: three panels, states, rewards, boss rule, sidebar, stray card.
  do
    local bs = panel("preview")
    local Tw = ns.UI.Tween
    local function countText(t)
      local n = 0
      for _, f in ipairs(stub.frames) do
        if f._text == t and f:IsVisible() then n = n + 1 end
      end
      return n
    end
    local function rewardG(t) return tonumber(t:match("|cffffd100(%d+)g|r")) end
    -- mid-entrance: staggered, the last panel has not started yet
    stub.advance(0.05)
    check(Tw.Count() > 0 or bs.panels[1]:GetAlpha() == 1, "entrance tweens run")
    stub.advance(1)
    eq(Tw.Count(), 0, "panels finished animating in, nothing left running")
    eq(#bs.panels, 3, "three blind panels")
    local run0 = Main.run
    run0.bosses[run0.stage] = "MUTANUS"
    Main.Render(run0, true)
    local want = { "CURRENT", "UPCOMING", "UPCOMING" }
    for i = 1, 3 do
      eq(bs.panels[i].state, want[i], "panel " .. i .. " state before blind 1")
      eq(bs.panels[i].tag:GetText(), want[i], "panel " .. i .. " tag text")
    end
    eq(countText("Stage 1 of 8"), 1, "the stage header shows once")
    eq(countText("Score at least"), 3, "one Score at least per panel, no centred duplicate")
    eq(countText("Start Blind"), 0, "the bottom Start Blind button is gone")
    eq(countText("Next Blind"), 0, "no Next Blind title")
    check(bs.panels[1].play:IsVisible() and bs.panels[1].play:IsEnabled(), "current Play is live")
    check(not (bs.panels[2].play:IsVisible() and bs.panels[2].play:IsEnabled()), "upcoming Play is disabled or hidden")
    check(not (bs.panels[3].play:IsVisible() and bs.panels[3].play:IsEnabled()), "boss Play is disabled or hidden")
    eq(bs.panels[1].target:GetText(), tostring(ns.Run.target(1, 1)), "small target")
    eq(bs.panels[2].target:GetText(), tostring(ns.Run.target(1, 2)), "big target")
    eq(bs.panels[3].target:GetText(), tostring(ns.Run.target(1, 3, "MUTANUS")), "Mutanus target matches Run.target")
    eq(rewardG(bs.panels[1].reward:GetText()), 3, "small reward 3g")
    eq(rewardG(bs.panels[2].reward:GetText()), 4, "big reward 4g")
    eq(rewardG(bs.panels[3].reward:GetText()), 5, "boss reward 5g")
    eq(bs.panels[3].name:GetText(), "Mutanus the Devourer", "boss name")
    eq(bs.panels[3].rule:GetText(), ns.Bosses.def.MUTANUS.desc, "the boss rule text is shown")
    eq(bs.panels[1].rule:GetText(), "", "small blind has no rule")
    check(bs.panels[3].rule:IsVisible(), "boss rule is visible")
    check(bs.panels[3].isBoss and not bs.panels[1].isBoss, "only the third panel is the boss")
    check(bs.panels[3].chip:GetTexture():find("Chip_BOSS", 1, true), "boss chip texture")
    check(bs.panels[1].chip:GetTexture():find("Chip_SMALL", 1, true), "small chip texture")
    check(bs.panels[2].chip:GetTexture():find("Chip_BIG", 1, true), "big chip texture")
    check(bs.panels[3].chip._vertex and bs.panels[3].chip._vertex[2] ~= bs.panels[3].chip._vertex[1], "boss chip is tinted")
    local function lift(b) return select(5, b:GetPoint(1)) end
    eq(lift(bs.panels[1]) - lift(bs.panels[2]), 10, "the current panel is lifted 10px")
    check(bs.panels[1].glow:IsShown() and not bs.panels[2].glow:IsShown(), "only the current panel glows")
    check(not bs.panels[1].stamp:IsShown(), "no DEFEATED stamp before beating anything")
    -- sidebar: run info, no 0x0 boxes
    local sb = Main.sidebar
    check(not sb.chipsBox:IsShown() and not sb.multBox:IsShown() and not sb.xMark:IsShown(), "no 0 x 0 boxes on the blind screen")
    check(not sb.blindName:IsShown() and not sb.target:IsShown() and not sb.score:IsShown()
      and not sb.scoreLabel:IsShown() and not sb.targetLabel:IsShown(), "no duplicate blind, target or round score in the sidebar")
    check(sb.deckName:IsShown() and sb.deckName:GetText() == "Rogue Deck", "sidebar shows the deck name")
    check(sb.deckIcon:IsShown() and sb.deckIcon:GetTexture():find("Back_ROGUE", 1, true), "sidebar shows the deck's back icon")
    eq(sb.hands:GetText(), "Hands: 4", "hands for the upcoming blind")
    eq(sb.discards:GetText(), "Discards: 4", "discards for the upcoming blind")
    eq(sb.gold:GetText(), "Gold: 4g", "gold")
    eq(sb.stage:GetText(), "Stage 1 / 8", "stage line")
    check(sb.deckButton:IsShown(), "Deck button stays")
    -- the stray deck pile is hidden outside play
    check(not HandView.deck:IsShown(), "the stray deck pile is hidden on the blind screen")
    -- empty trinket and consumable slots share one subtle look: no grey squares, no dragon icons
    do
      local t1, c1 = Main.trinketRow.slots[1], Main.consumableRow.slots[1]
      check(t1.empty:IsShown() and t1.empty.isEmptySlot, "empty trinket slot shows the empty look")
      check(not t1.icon:IsShown(), "no empty-slot icon in an empty trinket slot")
      check(c1.empty:IsShown() and c1.empty.isEmptySlot, "empty consumable slot shows the empty look")
      check(not c1.art:IsShown() and not c1.icon:IsShown(), "no art or icon in an empty consumable slot")
      check(ns.UI.Theme.emptySlotEdgeAlpha > 0 and ns.UI.Theme.emptySlotEdgeAlpha <= 0.35, "the outline is low alpha")
    end
    -- boss overrides in the sidebar (look ahead at the boss blind)
    run0.blind = 3
    Main.Render(run0, true)
    eq(sb.discards:GetText(), "Discards: 0", "Mutanus: no discards shown in the sidebar")
    run0.bosses[run0.stage] = "ONYXIA"
    Main.Render(run0, true)
    eq(sb.hands:GetText(), "Hands: 1", "Onyxia: one hand shown in the sidebar")
    eq(bs.panels[3].state, "CURRENT", "third panel current at blind 3")
    eq(bs.panels[1].state, "DEFEATED", "first panel defeated at blind 3")
    check(bs.panels[1].stamp:IsShown(), "stamp on a defeated panel")
    check(not bs.panels[1].play:IsShown(), "no Play on a defeated panel")
    eq(bs.panels[3].rule:GetText(), ns.Bosses.def.ONYXIA.desc, "boss rule follows the boss")
    run0.blind = 1
    run0.bosses[run0.stage] = "MUTANUS"
    Main.Render(run0, true)
  end
  step("2-pre blind select panels, states, rewards, boss rule, sidebar info, stray pile")
  click(panel("preview").start, "Play (current blind)")
  stub.advance(3)
  eq(Main.run.phase, "play", "phase after Play")
  check(HandView.deck:IsShown(), "the deck pile shows in play")
  do
    local sb = Main.sidebar
    check(sb.chipsBox:IsShown() and sb.multBox:IsShown() and sb.target:IsShown() and sb.score:IsShown(), "round stats in play")
    check(not sb.deckName:IsShown() and not sb.deckIcon:IsShown(), "deck name and icon are blind-screen only")
    eq(sb.stage:GetText(), "Stage 1 / 8 - Blind 1 / 3", "play keeps the stage and blind line")
  end
  do
    local w = handWidgets()[1]
    w:SetFaceUp(false)
    check(w.back:IsShown() and w.back:GetTexture():find("Back_ROGUE", 1, true), "a face-down card shows the deck's back")
    w:SetFaceUp(true)
  end
  eq(#Main.run.hand, 8, "hand size")
  eq(#handWidgets(), 8, "hand widgets")
  step("2 deck tile and Start Blind deal 8 cards")

  -- Hover and button tooltip paths.
  local playBtn = Main.buttons.play
  check(not playBtn:IsEnabled(), "Play should be disabled with nothing selected")
  playBtn._scripts.OnEnter(playBtn)
  check(stub.tooltip:IsShown(), "disabled Play shows its reason tooltip")
  playBtn._scripts.OnLeave(playBtn)
  check(not stub.tooltip:IsShown(), "tooltip hides on leave")
  local w1 = handWidgets()[1]
  w1._scripts.OnEnter(w1)
  stub.advance(0.2)
  w1._scripts.OnLeave(w1)
  stub.advance(0.2)

  -- Sort and discard.
  click(Main.buttons.sortRank, "Sort Rank")
  stub.advance(1)
  click(Main.buttons.sortSuit, "Sort Suit")
  stub.advance(1)
  local discardsBefore = Main.run.discardsLeft
  selectCard(1)
  check(Main.sidebar.handName:GetText() ~= "", "selection preview shows a hand name")
  check(Main.sidebar.chipsBox.text:GetText() ~= "0", "selection preview shows chips")
  selectCard(2)
  click(Main.buttons.discard, "Discard")
  stub.advance(3)
  eq(Main.run.discardsLeft, discardsBefore - 1, "discard used")
  eq(#Main.run.hand, 8, "hand refilled after discard")
  check(not HandView.IsBusy(), "busy after discard")
  eq(Main.sidebar.handName:GetText(), "", "preview clears after the discard")
  eq(Main.sidebar.chipsBox.text:GetText(), "0", "preview chips clear after the discard")
  step("2b sort and discard")

  -- 2c. Card type visuals, edition FX and the deck view.
  local FX, DeckView = ns.UI.EditionFX, ns.UI.DeckView
  local MEDIA = "Interface\\AddOns\\AzerothAnte\\Media\\"
  local run0 = Main.run
  local function widgetFor(card, parent)
    for _, c in ipairs((parent or Main.handArea)._children) do
      if c.card == card and not c.released and c:IsShown() then return c end
    end
  end
  local c1, c2 = run0.hand[1], run0.hand[2]
  c1.enh, c1.ed, c1.seal = "BONUS", "FOIL", "RED"
  c2.enh = "STONE"
  HandView.Update(run0, false)
  stub.advance(1)
  local cw1, cw2 = widgetFor(c1), widgetFor(c2)
  eq(cw1.art:GetTexture(), MEDIA .. "Face_BONUS", "Bonus card face texture")
  check(cw1.seal:IsShown(), "seal visible on a sealed card")
  eq(cw1.seal:GetTexture(), MEDIA .. "Seal_RED", "seal texture")
  check(cw1.rankTL:IsShown() and cw1.suitBig:IsShown(), "normal card shows rank and suit")
  -- Rank and suit print straight onto the face: no plates, no halo, a text colour per face.
  check(cw1.plateTL == nil and cw1.plateBR == nil and cw1.halo == nil, "no index plates or halo on a card")
  do
    local known = { cw1.border, cw1.paper, cw1.art, cw1.suitBig, cw1.suitSmall, cw1.seal, cw1.shade, cw1.back }
    local isKnown, extra = {}, 0
    for _, t in ipairs(known) do isKnown[t] = true end
    for _, ch in ipairs(cw1.face._children) do
      if ch._kind == "Texture" and not isKnown[ch] then extra = extra + 1 end
    end
    check(extra <= 1, "card face has no plate textures (only the edition tint beyond the named regions)")
    local function lum(r, g, b) return 0.2126 * r + 0.7152 * g + 0.0722 * b end
    local saved, savedSuit = c1.enh, c1.suit
    for _, enh in ipairs({ false, "BONUS", "MULT", "WILD", "LUCKY", "GOLD", "GLASS", "STEEL" }) do
      for _, suit in ipairs({ "S", "C", "H", "D" }) do
        c1.enh, c1.suit = enh or nil, suit
        cw1:SetCard(c1)
        local r, g, b = cw1.rankTL:GetTextColor()
        local sr, sg, sb = cw1.suitBig:GetVertexColor()
        local _, _, flags = cw1.rankTL:GetFont()
        local tag = (enh or "Plain") .. " " .. suit
        check(sr == r and sg == g and sb == b, tag .. ": suit and rank share one ink")
        if enh == "GLASS" then
          check(lum(r, g, b) > 0.8 and flags == "OUTLINE", tag .. ": Glass has a light ink and an outline")
        else
          check(lum(r, g, b) < 0.4 and flags == "", tag .. ": light and steel faces have a deep ink, no outline")
        end
      end
    end
    c1.enh, c1.suit = saved, savedSuit
    cw1:SetCard(c1)
  end
  eq(cw2.art:GetTexture(), MEDIA .. "Face_STONE", "Stone card face texture")
  check(not cw2.rankTL:IsShown() and not cw2.rankBR:IsShown(), "Stone hides its rank")
  check(not cw2.suitBig:IsShown() and not cw2.suitSmall:IsShown(), "Stone hides its suit")
  check(not cw2.seal:IsShown(), "unsealed card hides the seal")
  check(FX.IsRunning(), "EditionFX driver runs while an edition card is visible")

  -- Tooltip after a short delay, and the lift is unaffected by it.
  cw1._scripts.OnEnter(cw1)
  stub.advance(0.1)
  check(not stub.tooltip:IsShown(), "card tooltip waits for its delay")
  stub.advance(0.5)
  check(stub.tooltip:IsShown() and stub.tooltip:GetOwner() == cw1, "card tooltip shows after the delay")
  cw1._scripts.OnLeave(cw1)
  check(not stub.tooltip:IsShown(), "card tooltip hides on leave")
  stub.advance(0.3)

  -- Glass and Lucky tooltips show the effective odds, never a raw {N} token.
  for _, odds in ipairs({ { 1, "1 in 4", "1 in 5" }, { 2, "2 in 4", "2 in 5" } }) do
    if odds[1] == 2 then run0.trinkets[#run0.trinkets + 1] = ns.Trinkets.create(run0, "LOADED_DICE") end
    for _, enh in ipairs({ "GLASS", "LUCKY" }) do
      c1.enh = enh
      HandView.Update(run0, false)
      stub.advance(1)
      local gw = widgetFor(c1)
      gw._scripts.OnEnter(gw)
      stub.advance(0.6)
      local text = table.concat(stub.tooltip._lines, "|")
      check(not text:find("{%d+}"), enh .. " tooltip has a raw odds token: " .. text)
      check(text:find(enh == "GLASS" and odds[2] or odds[3], 1, true), enh .. " tooltip shows " .. odds[1] .. "x odds: " .. text)
      gw._scripts.OnLeave(gw)
      stub.advance(0.3)
    end
  end
  run0.trinkets[#run0.trinkets] = nil
  c1.enh = "BONUS"
  HandView.Update(run0, false)
  stub.advance(1)

  -- Deck view over the play area.
  local nDeck = #run0.deck
  check(Main.sidebar.deckButton:GetText() == "Deck (" .. nDeck .. ")", "sidebar Deck button shows the count")
  click(Main.sidebar.deckButton, "Deck button")
  stub.advance(0.2)
  check(visible("deckTitle"), "deck view visible")
  eq(panel("deckTitle").deckTitle:GetText(), "Deck: " .. nDeck .. " cards", "deck view count text")
  local deckPanel = panel("deckTitle")
  local minis = {}
  for _, c in ipairs(deckPanel._children) do
    if c.card and not c.released and c:IsShown() then minis[#minis + 1] = c end
  end
  eq(#minis, nDeck, "deck view mini widgets")
  local m1, m2 = widgetFor(c1, deckPanel), widgetFor(c2, deckPanel)
  eq(m1.art:GetTexture(), MEDIA .. "Face_BONUS", "mini card face texture")
  check(m1.seal:IsShown(), "mini card shows its seal")
  check(not m2.rankTL:IsShown(), "mini Stone hides its rank")
  local lowestY = 0
  for _, mw in ipairs(minis) do lowestY = math.min(lowestY, mw._points[1][5]) end
  eq(m2._points[1][5], lowestY, "Stone cards end the last suit row")
  local rowsY = {}
  for _, mw in ipairs(minis) do rowsY[mw._points[1][5]] = true end
  local nRows = 0
  for _ in pairs(rowsY) do nRows = nRows + 1 end
  eq(nRows, 4, "Stone shares the last suit row (four rows)")
  m1._scripts.OnEnter(m1)
  stub.advance(0.6)
  check(stub.tooltip:IsShown() and stub.tooltip:GetOwner() == m1, "mini card tooltip shows")
  local lines = table.concat(stub.tooltip._lines, "|")
  check(lines:find(" of ", 1, true), "mini tooltip names rank and suit")
  check(lines:find("Bonus", 1, true) and lines:find("Foil", 1, true) and lines:find("Red Seal", 1, true), "mini tooltip lists the types")
  m1._scripts.OnLeave(m1)
  check(not stub.tooltip:IsShown(), "mini tooltip hides on leave")
  check(m1.rankTL:GetText() ~= nil and not m1.rankBR:IsShown(), "mini shows one rank")
  do
    local _, _, flags = m1.rankTL:GetFont()
    eq(flags, "OUTLINE", "mini rank is outlined")
    check(m1.plateTL == nil and m1.halo == nil, "mini has no plate or halo")
    local r, g, b = m1.rankTL:GetTextColor()
    local ink = ns.UI.CardWidget.INKS.deep[m1.card.suit]
    check(r == ink[1] and g == ink[2] and b == ink[3], "mini uses the same per-face ink as the full card")
  end
  -- A locked (in-flight) card never shows a tooltip.
  cw1._scripts.OnEnter(cw1)
  cw1.locked = true
  stub.advance(0.6)
  check(not stub.tooltip:IsShown(), "locked card shows no tooltip")
  cw1.locked = false
  cw1._scripts.OnLeave(cw1)
  click(deckPanel.close, "deck view Close")
  check(not DeckView.IsShown(), "deck view closes")
  eq(#deckPanel._children > 0 and (function()
    local n = 0
    for _, c in ipairs(deckPanel._children) do
      if c.card and not c.released then n = n + 1 end
    end
    return n
  end)(), 0, "deck view releases its minis")

  -- Hiding the window stops the driver; showing it restarts it.
  Main.Hide()
  stub.advance(0.1)
  check(not FX.IsRunning(), "EditionFX driver stops when the window is hidden")
  open()
  check(FX.IsRunning(), "EditionFX driver restarts when the window is shown")

  -- Twelve cards fit the hand area; every edition animates without errors.
  local added = {}
  for i, ed in ipairs({ "FOIL", "HOLO", "POLY", "NEGATIVE" }) do
    local c = ns.Deck.add(run0, { rank = 2 + i, suit = "D", ed = ed, seal = i == 2 and "PURPLE" or nil })
    run0.hand[#run0.hand + 1] = c
    added[i] = c
  end
  HandView.Update(run0, false)
  stub.advance(3)
  local wide = handWidgets()
  eq(#wide, 12, "twelve hand widgets")
  local areaW = Main.handArea:GetWidth()
  for i, cw in ipairs(wide) do
    local x = cw._points[1][4]
    check(x >= 0 and x + ns.UI.CardWidget.WIDTH <= areaW + 1e-6, "hand card " .. i .. " inside the hand area")
  end
  local polyW = widgetFor(added[3])
  eq(polyW.face.fx.ed, "POLY", "Polychrome attached")
  check(widgetFor(added[4]).face.fx.tint:IsShown(), "Negative shows its tint")
  for _, c in ipairs(added) do ns.Deck.destroy(run0, c.id) end
  HandView.Update(run0, false)
  stub.advance(1)
  eq(#handWidgets(), 8, "hand back to eight")
  check(not polyW.face.fx.active, "released widgets detach their edition FX")

  c1.enh, c1.ed, c1.seal, c2.enh = nil, nil, nil, nil
  HandView.Update(run0, false)
  stub.advance(1)
  eq(cw1.art:GetTexture(), MEDIA .. "Face_Plain", "plain card face texture")
  check(not cw1.seal:IsShown(), "seal hides when removed")
  check(cw2.rankTL:IsShown() and cw2.suitBig:IsShown(), "rank and suit return when no longer Stone")
  check(not FX.IsRunning(), "EditionFX driver idles with no edition cards")
  step("2c card visuals, tooltip, deck view, edition FX, 12-card hand")

  -- 2d. Consumable slots and the Use flow in play.
  local runC = Main.run
  local crow = Main.consumableRow
  local function popover() return panel("use") end
  local function giveSlot(r, kind, id)
    r.consumables = {}
    ns.Consumables.add(r, { kind = kind, id = id })
    Main.Render(r)
  end
  giveSlot(runC, "scroll", "FURY")
  eq(#crow.slots, 5, "consumable row builds its slot frames")
  check(crow.slots[1]:IsShown() and crow.slots[2]:IsShown() and not crow.slots[3]:IsShown(), "row shows maxConsumables slots")
  eq(crow.slots[1].art:GetTexture(), MEDIA .. "Consumable_Scroll", "scroll slot frame texture")
  eq(crow.slots[1].name:GetText(), "Fury", "slot shows a short name")
  check(not crow.slots[2].art:IsShown(), "empty slot hides the frame art")
  crow.slots[1]._scripts.OnEnter(crow.slots[1])
  check(stub.tooltip:IsShown() and stub.tooltip:GetOwner() == crow.slots[1], "consumable slot tooltip")
  crow.slots[1]._scripts.OnLeave(crow.slots[1])

  selectCard(1)
  selectCard(2)
  local furyIdx = HandView.Selected()
  local fa, fb = runC.hand[furyIdx[1]], runC.hand[furyIdx[2]]
  click(crow.slots[1], "consumable slot 1")
  check(popover() and popover():IsVisible(), "popover opens on slot click")
  local wa0, wb0 = widgetFor(fa), widgetFor(fb)
  eq(wa0.art:GetTexture(), MEDIA .. "Face_Plain", "card starts with the plain face")
  click(popover().use, "popover Use (2 cards selected)")
  check(HandView.IsBusy(), "input locks during the use animation")
  check(not Main.buttons.play:IsEnabled(), "Play disabled while a consumable resolves")
  -- Midpoint of the flip: the first card is at zero width, clipped, and already swapped;
  -- the second (staggered) has not changed yet, so nothing ever changes in place.
  stub.advance(0.13)
  check(wa0.face:DoesClipChildren(), "a flipping card clips its contents")
  check(wa0.face:GetWidth() < ns.UI.CardWidget.WIDTH / 2, "flipping card is narrowed at the midpoint")
  eq(wa0.art:GetTexture(), MEDIA .. "Face_MULT", "face swaps at the midpoint of the flip")
  eq(wb0.art:GetTexture(), MEDIA .. "Face_Plain", "staggered card has not swapped early")
  check(wb0.face:DoesClipChildren(), "staggered card already clips while narrowing")
  stub.advance(3)
  check(not wa0.face:DoesClipChildren() and not wb0.face:DoesClipChildren(), "clipping ends with the flip")
  check(not HandView.IsBusy(), "unlocked after the use animation")
  eq(fa.enh, "MULT", "first selected card became Mult")
  eq(fb.enh, "MULT", "second selected card became Mult")
  eq(widgetFor(fa).art:GetTexture(), MEDIA .. "Face_MULT", "first widget shows the Mult face")
  eq(widgetFor(fb).art:GetTexture(), MEDIA .. "Face_MULT", "second widget shows the Mult face")
  eq(widgetFor(fa).face:GetWidth(), ns.UI.CardWidget.WIDTH, "flip restores the card width")
  eq(#HandView.Selected(), 0, "selection clears after a use")
  eq(#runC.consumables, 0, "used consumable leaves its slot")
  check(not crow.slots[1].art:IsShown(), "used slot renders empty")
  check(not popover():IsShown(), "popover closes after Use")
  check(env.AzerothAnteDB.run ~= nil, "use persists the run")

  -- Disabled Use shows its reason.
  giveSlot(runC, "scroll", "FURY")
  selectCard(1)
  selectCard(2)
  selectCard(3)
  click(crow.slots[1], "consumable slot 1 (again)")
  local use = popover().use
  check(not use:IsEnabled(), "Use disabled with 3 cards selected for Fury")
  eq(use.reason, "Select 1 to 2 cards", "disabled Use explains why")
  use._scripts.OnEnter(use)
  check(stub.tooltip:IsShown() and stub.tooltip:GetOwner() == use, "disabled Use shows its reason on hover")
  use._scripts.OnLeave(use)
  check(popover().affects:GetText():find("3 selected", 1, true), "popover states what it will affect")
  HandView.ClearSelection() -- the selection-change refresh re-evaluates Use
  check(not use:IsEnabled(), "Use disabled with nothing selected")
  selectCard(1)
  check(use:IsEnabled(), "Use enables when the selection becomes valid")
  click(crow.slots[1], "consumable slot 1 (close)")
  check(not popover():IsShown(), "second click closes the popover")
  HandView.ClearSelection()

  -- Destroy, add and create outcomes.
  giveSlot(runC, "relic", "COURT")
  local handBefore = #runC.hand
  local before = {}
  for _, c in ipairs(runC.hand) do before[c] = widgetFor(c) end
  click(crow.slots[1], "relic slot")
  click(popover().use, "Use relic of the Court")
  local doomed, doomedW
  for c, w in pairs(before) do
    local alive = false
    for _, h in ipairs(runC.hand) do if h == c then alive = true end end
    if not alive then doomed, doomedW = c, w end
  end
  check(doomedW ~= nil, "Court destroyed a card in hand")
  stub.advance(0.15)
  check(doomedW.face:GetAlpha() < 1 and doomedW.face:GetAlpha() > 0, "destroyed card fades mid-shatter")
  check(not doomedW.released, "destroyed card is still shown while it shatters")
  stub.advance(3)
  check(widgetFor(doomed) == nil and doomedW.card ~= doomed, "destroyed card's widget is released after the shatter")
  check(doomedW.face:GetAlpha() == 1 and doomedW.face:GetScale() == 1, "released widget is reset for reuse")
  eq(#runC.hand, handBefore + 2, "Court destroys 1 and adds 3 cards")
  eq(#handWidgets(), handBefore + 2, "hand re-lays out with the added cards")
  check(not HandView.IsBusy(), "unlocked after destroy and add")
  -- Whispers: every card flips to one rank, the hand size drops, and the hand relays out.
  giveSlot(runC, "relic", "WHISPERS")
  local modBefore = runC.handSizeMod
  click(crow.slots[1], "whispers slot")
  click(popover().use, "Use Relic of Whispers")
  stub.advance(0.1)
  check(stub.findText("Hand size -1"), "Whispers floats the hand size change")
  stub.advance(3)
  eq(runC.handSizeMod, modBefore - 1, "Whispers lowers the hand size")
  for _, c in ipairs(runC.hand) do
    eq(widgetFor(c).rankTL:GetText(), ns.Cards.label(c), "every card shows its new rank")
  end
  eq(#handWidgets(), #runC.hand, "hand widgets match the hand after Whispers")
  runC.handSizeMod = modBefore

  -- Tome: the level floats over the sidebar, the used slot pulses, the preview shows the level.
  local pairLvl = runC.handLevels.PAIR
  giveSlot(runC, "tome", "PAIR")
  crow.slots[1]._scripts.OnEnter(crow.slots[1])
  local sawLevelLine = false
  for _, line in ipairs(stub.tooltip._lines) do
    if line == "Pair: Lv " .. pairLvl .. " -> " .. (pairLvl + 1) then sawLevelLine = true end
  end
  check(sawLevelLine, "Tome tooltip shows the level change")
  crow.slots[1]._scripts.OnLeave(crow.slots[1])
  click(crow.slots[1], "tome slot")
  check(popover().affects:GetText() == "Pair: Lv " .. pairLvl .. " -> " .. (pairLvl + 1), "Tome popover shows the level change")
  click(popover().use, "Use Tome of Pair")
  stub.advance(0.05)
  check(crow.slots[1].holder:GetScale() > 1, "the used consumable slot pulses")
  stub.advance(0.1)
  check(stub.findText("Pair Lv " .. (pairLvl + 1)), "the Tome's level floats over the sidebar")
  stub.advance(3)
  eq(runC.handLevels.PAIR, pairLvl + 1, "Tome levelled Pair")
  runC.hand[1].rank, runC.hand[2].rank = 9, 9
  HandView.Update(runC, false)
  stub.advance(1)
  selectCard(1)
  selectCard(2)
  eq(Main.sidebar.handName:GetText(), "Pair Lv " .. (pairLvl + 1), "the selection preview shows the hand level")
  HandView.ClearSelection()
  runC.handLevels.PAIR = pairLvl

  -- Chance: a hit pulses the trinket slot, a miss floats Nope! over the used slot.
  local function forceChance(hit)
    for i = 1, 500 do
      local seed = i * 10007919
      local probe = { s = seed }
      if (ns.RNG.next(probe) < 0.25) == hit then
        runC.rng.s = seed
        return
      end
    end
    error("no seed found")
  end
  runC.trinkets = { { id = ns.Trinkets.order[1] } }
  Main.Render(runC)
  giveSlot(runC, "scroll", "CHANCE")
  forceChance(false)
  click(crow.slots[1], "chance slot (miss)")
  click(popover().use, "Use Scroll of Chance (miss)")
  stub.advance(0.1)
  check(stub.findText("Nope!"), "a Chance miss floats Nope!")
  stub.advance(3)
  eq(runC.trinkets[1].ed, nil, "a Chance miss changes nothing")
  giveSlot(runC, "scroll", "CHANCE")
  forceChance(true)
  click(crow.slots[1], "chance slot (hit)")
  click(popover().use, "Use Scroll of Chance (hit)")
  stub.advance(0.15)
  check(Main.trinketRow.slots[1].holder:GetScale() > 1.05, "the changed trinket slot pulses")
  stub.advance(3)
  check(runC.trinkets[1].ed ~= nil, "a Chance hit gave the trinket an edition")
  runC.trinkets = {}
  Main.Render(runC)

  -- Rule trinkets reach the selection preview; tooltips show effective odds; an emptied slot
  -- drops its tooltip.
  do
    local saved = {}
    for i = 1, 4 do saved[i] = { runC.hand[i].rank, runC.hand[i].suit } end
    for i, rank in ipairs({ 2, 5, 7, 9 }) do runC.hand[i].rank, runC.hand[i].suit = rank, "H" end
    HandView.ClearSelection()
    HandView.Update(runC, false)
    stub.advance(1)
    for i = 1, 4 do selectCard(i) end
    check(not Main.sidebar.handName:GetText():find("Flush", 1, true), "4 hearts are no flush without Sleight of Hand")
    HandView.ClearSelection()
    runC.trinkets = { ns.Trinkets.create(runC, "SLEIGHT_HAND") }
    Main.Render(runC)
    for i = 1, 4 do selectCard(i) end
    check(Main.sidebar.handName:GetText():find("Flush", 1, true) == 1, "Sleight of Hand previews a 4-card Flush")
    HandView.ClearSelection()
    for i = 1, 4 do runC.hand[i].rank, runC.hand[i].suit = saved[i][1], saved[i][2] end
    HandView.Update(runC, false)
    stub.advance(1)

    runC.trinkets = { ns.Trinkets.create(runC, "BLOODSTONE") }
    Main.Render(runC)
    local slot1 = Main.trinketRow.slots[1]
    slot1._scripts.OnEnter(slot1)
    check(table.concat(stub.tooltip._lines, "|"):find("1 in 2", 1, true), "tooltip shows base odds")
    slot1._scripts.OnLeave(slot1)
    runC.trinkets[2] = ns.Trinkets.create(runC, "LOADED_DICE")
    Main.Render(runC)
    slot1._scripts.OnEnter(slot1)
    check(table.concat(stub.tooltip._lines, "|"):find("2 in 2", 1, true), "tooltip shows Loaded Dice odds")
    local info = ns.UI.Screens.ItemInfo({ type = "trinket", id = "BLOODSTONE" })
    check(info.desc:find("2 in 2", 1, true), "shop item info shows Loaded Dice odds")
    runC.trinkets = {}
    Main.Render(runC)
    check(not stub.tooltip:IsShown(), "an emptied slot drops its stale tooltip")
  end

  -- A Purple-sealed discard pops its new Scroll into the slot.
  runC.consumables = {}
  HandView.ClearSelection()
  runC.discardsLeft = math.max(runC.discardsLeft, 1)
  local purple = runC.hand[1]
  purple.seal = "PURPLE"
  HandView.Update(runC, false)
  stub.advance(1)
  selectCard(1)
  click(Main.buttons.discard, "Discard a Purple-sealed card")
  stub.advance(0.05)
  eq(#runC.consumables, 1, "the Purple seal made a Scroll")
  check(crow.slots[1].holder:GetAlpha() < 1 or crow.slots[1].holder:GetScale() ~= 1, "the new Scroll pops into its slot")
  stub.advance(3)
  check(crow.slots[1].holder:GetAlpha() == 1 and crow.slots[1].holder:GetScale() == 1, "the popped Scroll ends fully visible")
  purple.seal = nil
  runC.consumables = {}
  Main.Render(runC)

  -- A widget released mid-flip (cancelled tween) never leaves the board locked or the card squashed.
  giveSlot(runC, "scroll", "FURY")
  HandView.ClearSelection()
  selectCard(3)
  local cancelled = widgetFor(runC.hand[HandView.Selected()[1]])
  click(crow.slots[1], "fury slot (cancel test)")
  click(popover().use, "Use Fury (cancel test)")
  stub.advance(0.05)
  check(cancelled.face:DoesClipChildren(), "flip is under way")
  ns.UI.CardWidget.Release(cancelled)
  stub.advance(3)
  check(not HandView.IsBusy(), "a cancelled flip still unlocks the hand")
  eq(cancelled.face:GetWidth(), ns.UI.CardWidget.WIDTH, "cancelled flip restores the width")
  check(not cancelled.face:DoesClipChildren(), "cancelled flip restores clipping")

  -- An error during Use unlocks the board and reaches the error handler.
  giveSlot(runC, "scroll", "FURY")
  selectCard(1)
  click(crow.slots[1], "fury slot (error test)")
  local realUse, caught = ns.Consumables.use, nil
  ns.Consumables.use = function() error("boom") end
  local realHandler = env.geterrorhandler
  env.geterrorhandler = function() return function(err) caught = err end end
  click(popover().use, "Use Fury (forced error)")
  ns.Consumables.use = realUse
  env.geterrorhandler = realHandler
  check(caught and tostring(caught):find("boom", 1, true), "a use error reaches the error handler")
  check(not HandView.IsBusy(), "the hand is not left locked after a failed use")
  eq(#runC.consumables, 1, "a failed use keeps the consumable")
  stub.advance(1)
  HandView.ClearSelection()

  -- Popover closes from outside clicks, the action buttons and a phase change; hand clicks still work.
  click(crow.slots[1], "fury slot (outside-click test)")
  check(popover():IsVisible(), "popover open for the outside-click test")
  local function mouseDown(over)
    stub.over = {}
    if over then stub.over[over] = true end
    stub.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
  end
  mouseDown(popover())
  check(popover():IsShown(), "a mouse-down on the popover keeps it open")
  mouseDown(crow.slots[1])
  check(popover():IsShown(), "a mouse-down on its own slot keeps it open (the click toggles it)")
  mouseDown(Main.handArea)
  selectCard(4)
  check(popover():IsVisible(), "selecting a hand card keeps the popover open")
  mouseDown(Main.sidebar)
  check(not popover():IsShown(), "a mouse-down elsewhere closes the popover")
  stub.over = {}
  stub.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
  check(not popover():IsShown(), "closed popover ignores further mouse-downs")

  -- Without GLOBAL_MOUSE_DOWN (RegisterEvent errors) a click-catcher is the fallback.
  stub.noGlobalMouse = true
  click(crow.slots[1], "fury slot (fallback test)")
  local catcherF
  for _, c in ipairs(Main.content._children) do
    if c._scripts.OnClick and c.RegisterForClicks and not c.use and c:IsShown() and c ~= crow.slots[1] and c._points[1]
      and c._points[1][2] == Main.content and c._level < popover():GetFrameLevel() and c._level > 500 then catcherF = c end
  end
  check(catcherF, "click catcher is the fallback when the event is unavailable")
  eq(catcherF._points[2][2], Main.handArea, "catcher stops above the hand area while playing")
  catcherF:Click()
  check(not popover():IsShown() and not catcherF:IsShown(), "fallback catcher closes the popover")
  stub.noGlobalMouse = false
  click(crow.slots[1], "fury slot (button-close test)")
  click(Main.buttons.sortRank, "Sort Rank closes the popover")
  check(not popover():IsShown(), "Sort closes the popover")
  click(crow.slots[1], "fury slot (hide test)")
  Main.Hide()
  check(not popover():IsShown(), "hiding the window closes the popover")
  open()
  runC.consumables = {}
  Main.Render(runC)
  HandView.ClearSelection()

  giveSlot(runC, "scroll", "STARS")
  click(crow.slots[1], "stars slot")
  click(popover().use, "Use Scroll of the Stars")
  stub.advance(3)
  eq(#runC.consumables, 2, "Stars created two Tomes")
  check(crow.slots[1].holder:GetAlpha() == 1 and crow.slots[2].holder:GetAlpha() == 1, "created consumables end fully visible")
  eq(crow.slots[2].art:GetTexture(), MEDIA .. "Consumable_Tome", "tome slot frame texture")
  runC.consumables = {}
  Main.Render(runC)
  -- Eight trinkets and five consumables never overlap.
  runC.maxTrinkets, runC.maxConsumables = 8, 5
  runC.trinkets = {}
  for i = 1, 8 do runC.trinkets[i] = { id = ns.Trinkets.order[i] } end
  Main.Render(runC)
  local tslots = Main.trinketRow.slots
  check(tslots[8]:IsShown() and crow.slots[5]:IsShown(), "all 13 slots are shown")
  check(tslots[8]._points[1][4] + 44 <= Main.trinketRow:GetWidth() + 1e-6, "trinket slots fit their row")
  check(Main.trinketRow:GetWidth() + Main.consumableRow:GetWidth() + ns.UI.Theme.margin <= Main.rowsWidth + 1e-6, "trinket and consumable rows do not overlap")
  check(tslots[2]._points[1][4] - tslots[1]._points[1][4] >= 44, "trinket slots never overlap each other")
  runC.maxTrinkets, runC.maxConsumables, runC.trinkets = 5, 2, {}
  Main.Render(runC)
  step("2d consumable slots, popover, use animations")

  -- 3. Play a card.
  local scoreBefore = Main.run.score
  local handsBefore = Main.run.handsLeft
  selectCard(1)
  playSelected()
  stub.advance(10)
  check(not HandView.IsBusy(), "HandView still busy after play")
  check(not Tally.IsBusy(), "Tally still busy after play")
  check(Main.run.score > scoreBefore or Main.run.phase ~= "play", "score did not change")
  eq(Main.run.handsLeft, handsBefore - 1, "hands left")
  eq(Main.sidebar.score:GetText(), tostring(Main.run.score), "sidebar score text")
  step("3 play a card, tally finishes")

  -- 3b. A Glass card that breaks, a Red-sealed card that retriggers and a held Steel card.
  do
    local r = Main.run
    r.handsLeft = math.max(r.handsLeft, 2)
    r.target = 10 ^ 9
    for _, c in ipairs(r.deck) do c.enh, c.ed, c.seal = nil, nil, nil end
    local glass = ns.Deck.add(r, { rank = 13, suit = "S", enh = "GLASS" })
    local red = ns.Deck.add(r, { rank = 13, suit = "H", seal = "RED" })
    local steel = ns.Deck.add(r, { rank = 7, suit = "C", enh = "STEEL" })
    r.hand[1], r.hand[2], r.hand[3] = glass, red, steel
    r.rng.s = 1 -- the Glass destroy roll comes up under 25%
    HandView.Update(r, false)
    stub.advance(1)
    local deckBefore, glassId = #r.deck, glass.id
    local gw, rw, sw = HandView.WidgetForCard(glass.id), HandView.WidgetForCard(red.id), HandView.WidgetForCard(steel.id)
    click(gw, "glass card")
    click(rw, "red card")
    playSelected()
    local sawAgain, sawSteelPulse, sawShatter, steelLifted = false, false, false, false
    for _ = 1, 100 do
      stub.advance(0.1)
      if stub.findText("Again!") then sawAgain = true end
      if sw.face:GetScale() > 1.01 then sawSteelPulse = true end
      if sw.body._y and sw.body._y ~= 0 then steelLifted = true end
      if gw.face:GetAlpha() < 1 then sawShatter = true end
      if not Tally.IsBusy() and not HandView.IsBusy() then break end
    end
    check(not Tally.IsBusy() and not HandView.IsBusy(), "board unlocked after the Glass/Red/Steel tally")
    check(sawAgain, "the Red seal showed Again!")
    check(sawSteelPulse and not steelLifted, "held Steel pulsed in place")
    check(sawShatter, "the Glass card shattered")
    eq(#r.deck, deckBefore - 1, "the broken Glass card left the deck")
    check(ns.Deck.find(r, glassId) == nil, "Glass card is gone")
    eq(Main.sidebar.score:GetText(), tostring(r.score), "tally reached total")
    eq(r.lastResult.destroyed[1], glassId, "result lists the destroyed card")
    HandView.Update(r, false)
    stub.advance(1)
  end
  step("3b tally: glass shatter, red retrigger, held steel")

  -- 3c. A very long tally runs to its last event: the watchdog never cuts it short.
  do
    local r = Main.run
    local events = {}
    for i = 1, 130 do
      events[i] = { kind = "base", handId = "PAIR", runChips = i, runMult = 1 }
    end
    local fired, realSet = 0, ns.UI.Sidebar.SetChipsMult
    ns.UI.Sidebar.SetChipsMult = function(chips, mult, name)
      if name then fired = fired + 1 end -- only the tally's own steps pass a hand name
      return realSet(chips, mult, name)
    end
    local doneCalled = false
    Tally.Play({ events = events, total = 0, chips = 1, mult = 1 }, {}, function() doneCalled = true end)
    for _ = 1, 400 do
      stub.advance(0.1)
      if doneCalled then break end
    end
    ns.UI.Sidebar.SetChipsMult = realSet
    check(doneCalled and not Tally.IsBusy(), "the long tally completed")
    eq(fired, 130, "every one of the 130 events fired")
  end
  step("3c long tally is not cut short by the watchdog")

  -- 4. Force a win.
  Main.run.target = 1
  selectCard(1)
  playSelected()
  stub.advance(10)
  eq(Main.run.phase, "shop", "phase after winning")
  check(visible("offerCards"), "shop screen not visible")
  -- The stale play hand sits hidden under the shop: it must not keep the shimmer driver running.
  do
    local r = Main.run
    local keep = r.trinkets
    r.trinkets = {}
    r.shop.cards = { { type = "scroll", id = "FURY", cost = 3 }, { type = "scroll", id = "GREED", cost = 3 } }
    r.shop.packs = {}
    for _, c in ipairs(r.hand) do c.ed = "FOIL" end
    Main.Render(r)
    stub.advance(1)
    check(not Main.handArea:IsShown(), "the play hand is hidden on the shop screen")
    check(not ns.UI.EditionFX.IsRunning(), "EditionFX driver idles on the shop screen")
    for _, c in ipairs(r.deck) do c.ed = nil end
    r.trinkets = keep
  end
  step("4 winning hand opens the shop")

  -- 4b. Shop v2: item cards, packs and the pack screen.
  do
    local r = Main.run
    r.gold = 100
    r.consumables = {}
    r.shop.cards = {
      { type = "scroll", id = "FURY", cost = 3 },
      { type = "trinket", id = "BLOODLUST", ed = "NEGATIVE", cost = 13 },
    }
    r.shop.packs = { { type = "ARCANA", size = "mega", cost = 8 }, { type = "BUFFOON", size = "normal", cost = 4 } }
    Main.Render(r)
    stub.advance(1)
    local sp = panel("offerCards")
    eq(sp.packOffers[1].name:GetText(), "Mega Arcana Pack", "pack label")
    check(sp.packOffers[1].desc:GetText():find("Choose 2 of 5 Scrolls", 1, true), "pack says what it holds")
    eq(sp.packOffers[2].name:GetText(), "Buffoon Pack", "normal pack label")
    check(sp.offerCards[2].desc:GetText():find("+1 trinket slot", 1, true), "Negative offer says +1 trinket slot")
    local iconFx = sp.offerCards[2].face.iconBox.fx
    check(iconFx and iconFx.active and iconFx.ed == "NEGATIVE", "offered trinket shows its edition FX")
    check(sp.payout.held ~= nil and sp.payout.held.label:GetText():find("Gold"), "payout shows the held-gold row")
    stub.advance(0.1)
    sp.offerCards[2].face._scripts.OnEnter(sp.offerCards[2].face)
    check(stub.tooltip:IsShown(), "offer tooltip shows")
    local sawEdition = false
    for _, line in ipairs(stub.tooltip._lines) do
      if line == "+1 trinket slot" then sawEdition = true end
    end
    check(sawEdition, "offer tooltip has the Negative line")
    sp.offerCards[2].face._scripts.OnLeave(sp.offerCards[2].face)

    -- Buy a Scroll into a consumable slot; a full row disables Buy with a reason.
    local gold0 = r.gold
    click(sp.offerCards[1].buy, "buy Fury")
    eq(r.gold, gold0 - 3, "Scroll cost spent")
    eq(r.consumables[1].kind, "scroll", "scroll in a consumable slot")
    eq(r.consumables[1].id, "FURY", "bought the offered scroll")
    stub.advance(1)
    r.shop.cards[1] = { type = "scroll", id = "GREED", cost = 3 }
    r.maxConsumables = 1
    Main.Render(r)
    check(not sp.offerCards[1].buy:IsEnabled(), "Buy disabled with consumable slots full")
    eq(sp.offerCards[1].buy.reason, "Consumable slots full", "disabled Buy says why")
    eq(sp.offerCards[1].buy:GetText(), "Slots full", "disabled Buy label")
    r.maxConsumables = 2
    r.shop.cards[1] = false
    Main.Render(r)

    -- Open the Mega Arcana pack.
    gold0 = r.gold
    click(sp.packOffers[1].buy, "Open Mega Arcana")
    stub.advance(1)
    eq(r.gold, gold0 - 8, "pack cost spent")
    local pack = r.shop.openPack
    check(pack and pack.type == "ARCANA" and pack.hand and #pack.hand > 0, "Arcana pack drew a hand")
    eq(pack.picksLeft, 2, "Mega gives 2 picks")
    check(visible("packChoices"), "PackView shows while a pack is open")
    local pv = panel("packChoices")
    eq(pv.title:GetText(), "Mega Arcana Pack", "pack screen title")
    eq(pv.picksLeft:GetText(), "Picks left: 2", "picks left shown")
    check(not pv.pick:IsEnabled(), "Pick disabled with nothing selected")
    eq(pv.pick.reason, "Select a choice first", "Pick says what to do first")
    pack.choices[1] = { kind = "scroll", id = "FURY" }
    pack.choices[2] = { kind = "scroll", id = "GREED" }
    Main.Render(r)
    ns.UI.OnRunChanged() -- the forced choices are saved like any other state
    stub.advance(1)
    local function packHand()
      local out = {}
      for _, c in ipairs(pv.hand._children) do
        if c.card and not c.released and c:IsShown() then out[#out + 1] = c end
      end
      table.sort(out, function(a, b) return a._points[1][4] < b._points[1][4] end)
      return out
    end
    eq(#packHand(), #pack.hand, "pack hand widgets")
    check(not panel("preview") or not panel("preview"):IsVisible(), "blind screen not shown")

    -- Reload mid-pack: a fresh world shows the same pack.
    do
      local db3 = deepCopy(env.AzerothAnteDB)
      local w3 = newWorld(db3)
      w3.env.SlashCmdList.AZEROTHANTE()
      w3.stub.advance(1)
      local pv3
      for _, c in ipairs(w3.ns.UI.Main.content._children) do
        if c.packChoices then pv3 = c end
      end
      check(pv3 and pv3:IsVisible(), "PackView shows after a reload mid-pack")
      local p3 = w3.ns.UI.Main.run.shop.openPack
      eq(p3.picksLeft, 2, "reloaded pack keeps its picks")
      eq(p3.choices[1].id, "FURY", "reloaded pack keeps its choices")
      eq(#p3.hand, #pack.hand, "reloaded pack keeps its hand")
      check(pv3.packChoices[1] and pv3.packChoices[1].frame:IsVisible(), "reloaded choices are shown")
    end

    -- Aim the Scroll in the consumable slot at the pack hand (its own selection).
    local wA, wB = packHand()[1], packHand()[2]
    click(wA, "pack card A")
    click(wB, "pack card B")
    check(wA.selected and wB.selected, "pack cards select")
    check(#HandView.Selected() == 0, "pack selection is separate from the hand's")
    click(Main.consumableRow.slots[1], "Fury slot while a pack is open")
    local pop = panel("use")
    check(pop.affects:GetText():find("(2 selected)", 1, true), "Affects counts the pack selection")
    check(pop.use:IsEnabled(), "Use enabled with 2 pack cards selected")
    local cardA, cardB = wA.card, wB.card
    click(pop.use, "Use Fury on the pack hand")
    stub.advance(0.15)
    check(wA.face:GetWidth() < 80, "the pack card flips (the pack widget is found by id)")
    stub.advance(2)
    eq(cardA.enh, "MULT", "Fury changed pack card A")
    eq(cardB.enh, "MULT", "Fury changed pack card B")
    eq(#r.consumables, 0, "the Scroll was used up")
    check(not HandView.IsBusy(), "unlocked after the use")
    eq(#ns.UI.PackView.Selected(), 0, "pack selection cleared after the use")
    check(not panel("use"):IsShown(), "popover closed after the use")

    -- Pick Fury from the pack: needs the choice AND 1-2 pack cards.
    local entry1 = pv.packChoices[1]
    click(entry1.frame, "Fury choice")
    check(not pv.pick:IsEnabled(), "Pick disabled until cards are selected")
    eq(pv.pick.reason, "Select 1 to 2 cards", "Pick says how many cards")
    check(pv.detailTitle:GetText():find("Fury", 1, true), "detail names the selected choice")
    local wC, wD = packHand()[3], packHand()[4]
    wC.card.enh, wD.card.enh = nil, nil
    click(wC, "pack card C")
    click(wD, "pack card D")
    check(pv.pick:IsEnabled(), "Pick enabled with a choice and 2 cards")
    check(pv.status:GetText():find("Ready", 1, true), "status says ready")
    local cardC, cardD = wC.card, wD.card
    gold0 = r.gold
    click(pv.pick, "Pick Fury")
    stub.advance(2)
    eq(cardC.enh, "MULT", "picked Fury changed card C")
    eq(cardD.enh, "MULT", "picked Fury changed card D")
    eq(pack.picksLeft, 1, "one pick left")
    eq(pack.choices[1], false, "the taken choice is gone")
    check(r.shop.openPack == pack and pv:IsVisible(), "pack stays open with a pick left")
    eq(pv.picksLeft:GetText(), "Picks left: 1", "picks left updates")
    check(env.AzerothAnteDB.run.shop.openPack.picksLeft == 1, "pick was saved")

    -- Skip closes it and returns to the shop.
    check(pv.skip:IsEnabled(), "Skip is available")
    click(pv.skip, "Skip")
    stub.advance(1)
    eq(r.shop.openPack, nil, "skip closes the pack")
    check(not pv:IsVisible(), "PackView hides when the pack closes")
    check(visible("offerCards"), "the shop is back")
    check(env.AzerothAnteDB.run.shop.openPack == nil, "skip was saved")

    -- Buffoon pack: trinket slot rules, and the Negative choice still fits when full.
    r.trinkets = {}
    for i = 1, 5 do r.trinkets[i] = { id = "ARCANE_INTELLECT" } end
    click(sp.packOffers[2].buy, "Open Buffoon")
    stub.advance(1)
    local bp = r.shop.openPack
    check(bp and bp.type == "BUFFOON", "Buffoon pack open")
    bp.choices = { { type = "trinket", id = "HEALTHSTONE" }, { type = "trinket", id = "BLOODLUST", ed = "NEGATIVE" } }
    bp.picksLeft = 1
    Main.Render(r)
    stub.advance(1)
    check(not bp.hand, "Buffoon has no drawn hand")
    click(pv.packChoices[1].frame, "plain trinket choice")
    check(not pv.pick:IsEnabled(), "Pick disabled with trinket slots full")
    eq(pv.pick.reason, "Trinket slots full - sell one first", "full slots say why")
    click(pv.packChoices[2].frame, "Negative trinket choice")
    check(pv.detailBody:GetText():find("+1 trinket slot", 1, true), "detail says +1 trinket slot")
    check(pv.pick:IsEnabled(), "a Negative trinket fits when slots are full")
    click(pv.pick, "Pick Negative trinket")
    stub.advance(2)
    eq(#r.trinkets, 6, "Negative trinket taken into the sixth slot")
    eq(r.shop.openPack, nil, "pack closes after the last pick")
    check(not pv:IsVisible(), "PackView closed after the last pick")
    r.trinkets = {}

    -- Standard pack: the choices are real cards; picking adds one to the deck.
    r.shop.packs[2] = { type = "STANDARD", size = "normal", cost = 4 }
    Main.Render(r)
    local deckBefore = #r.deck
    click(sp.packOffers[2].buy, "Open Standard")
    stub.advance(1)
    local sc = r.shop.openPack
    check(sc and sc.type == "STANDARD" and #sc.choices == 3, "Standard pack shows 3 cards")
    sc.choices[1] = { rank = 12, suit = "H", enh = "GOLD", ed = "FOIL" }
    Main.Render(r)
    stub.advance(1)
    local cw = pv.packChoices[1].widget
    check(cw and cw.art:GetTexture() == MEDIA .. "Face_GOLD", "Standard choice is a real card with its enhancement")
    click(cw, "Standard card choice")
    check(pv.detailBody:GetText():find("Gold", 1, true) and pv.detailBody:GetText():find("Foil", 1, true),
      "detail lists the card's enhancement and edition")
    click(pv.pick, "Pick the card")
    stub.advance(2)
    eq(#r.deck, deckBefore + 1, "picked card joined the deck")
    eq(r.shop.openPack, nil, "Standard pack closed")

    -- Celestial pack: the picked Tome levels its hand at once.
    r.shop.packs[2] = { type = "CELESTIAL", size = "normal", cost = 4 }
    Main.Render(r)
    click(sp.packOffers[2].buy, "Open Celestial")
    stub.advance(1)
    local cp = r.shop.openPack
    cp.choices[1] = { kind = "tome", id = "PAIR" }
    Main.Render(r)
    stub.advance(1)
    local lvl = r.handLevels.PAIR
    click(pv.packChoices[1].frame, "Tome choice")
    check(pv.pick:IsEnabled(), "a Tome needs no card selection")
    click(pv.pick, "Pick the Tome")
    stub.advance(0.1)
    check(stub.findText("Pair Lv " .. (lvl + 1)), "the level-up floats over the choice")
    stub.advance(2)
    eq(r.handLevels.PAIR, lvl + 1, "Tome levelled its hand")
    r.handLevels.PAIR = lvl -- later steps expect a level-1 Pair
    eq(r.shop.openPack, nil, "Celestial pack closed after its only pick")

    -- An empty pack is never a dead end.
    r.shop.packs[2] = { type = "BUFFOON", size = "normal", cost = 4 }
    Main.Render(r)
    click(sp.packOffers[2].buy, "Open an empty Buffoon")
    stub.advance(1)
    local ep = r.shop.openPack
    ep.choices, ep.picksLeft = {}, 0
    Main.Render(r)
    stub.advance(1)
    check(pv:IsVisible() and pv.empty:IsShown(), "empty pack says Nothing to choose")
    eq(pv.empty:GetText(), "Nothing to choose", "empty pack message")
    check(pv.skip:IsEnabled() and pv.skip:GetWidth() >= 200, "Skip is prominent on an empty pack")
    check(not pv.pick:IsShown(), "no Pick on an empty pack")
    click(pv.skip, "Skip the empty pack")
    stub.advance(1)
    eq(r.shop.openPack, nil, "empty pack skipped")
    r.consumables = {}
    Main.Render(r)
    stub.advance(1)
  end
  step("4b shop v2: item cards, packs, pack screen, reload, skip")

  -- 4c. The LAST pick of a pack still animates; pooled faces come back clean; a
  -- reloaded pack applies its Scroll to the real deck cards.
  do
    local r = Main.run
    r.gold = 200
    r.consumables = {}
    local sp = panel("offerCards")
    local pv = panel("packChoices")
    local function packHand(view)
      local out = {}
      for _, c in ipairs(view.hand._children) do
        if c.card and not c.released and c:IsShown() then out[#out + 1] = c end
      end
      table.sort(out, function(a, b) return a._points[1][4] < b._points[1][4] end)
      return out
    end
    local function openPack(def)
      r.shop.packs[1] = def
      Main.Render(r)
      click(sp.packOffers[1].buy, "Open " .. def.type)
      stub.advance(1)
      return r.shop.openPack
    end

    -- Normal Arcana (1 pick): Fury on 2 pack-hand cards, as the last pick.
    local pack = openPack({ type = "ARCANA", size = "normal", cost = 4 })
    pack.choices[1] = { kind = "scroll", id = "FURY" }
    Main.Render(r)
    stub.advance(1)
    click(pv.packChoices[1].frame, "Fury choice (last pick)")
    local a, b = packHand(pv)[1], packHand(pv)[2]
    a.card.enh, b.card.enh = nil, nil
    click(a, "card A")
    click(b, "card B")
    local ca, cb = a.card, b.card
    click(pv.pick, "Pick Fury (last pick)")
    check(r.shop.openPack == nil, "the last pick closed the pack in the run")
    check(pv:IsVisible(), "the overlay stays up while the last pick animates")
    do
      local col = pv.insetFill and pv.insetFill._color
      check(pv.themeInset and col and col[4] == 1, "pack overlay inset fill texture is fully opaque")
      eq(pv:GetAlpha(), 1, "pack overlay frame alpha")
    end
    stub.advance(0.15)
    check(a.face:GetWidth() < 80 and not a.released, "the last pick's flip ran on the pack card")
    stub.advance(2)
    eq(ca.enh, "MULT", "last-pick Fury changed card A")
    eq(cb.enh, "MULT", "last-pick Fury changed card B")
    check(not pv:IsVisible(), "the overlay closes after the animation")
    check(not HandView.IsBusy() and not ns.UI.PackView.IsBusy(), "unlocked after the last pick")

    -- Standard pack text shows effective odds for a Lucky card, never a raw {N} token.
    pack = openPack({ type = "STANDARD", size = "normal", cost = 4 })
    pack.choices[1] = { rank = 9, suit = "S", enh = "LUCKY" }
    Main.Render(r)
    stub.advance(1)
    click(pv.packChoices[1].widget, "Lucky Standard card")
    do
      local body = pv.detailBody:GetText()
      check(not body:find("{%d+}") and body:find("1 in 5", 1, true), "Standard pack text shows odds: " .. body)
      r.trinkets[#r.trinkets + 1] = ns.Trinkets.create(r, "LOADED_DICE")
      ns.UI.PackView.Show(r)
      body = pv.detailBody:GetText()
      check(not body:find("{%d+}") and body:find("2 in 5", 1, true), "Standard pack text shows doubled odds: " .. body)
      r.trinkets[#r.trinkets] = nil
    end
    click(pv.skip, "Skip the Lucky pack")
    stub.advance(1)

    -- A Standard card as the last pick: the float is visible.
    pack = openPack({ type = "STANDARD", size = "normal", cost = 4 })
    pack.choices[1] = { rank = 9, suit = "S" }
    Main.Render(r)
    stub.advance(1)
    click(pv.packChoices[1].widget, "Standard card (last pick)")
    click(pv.pick, "Pick the card (last pick)")
    stub.advance(0.1)
    check(stub.findText("Added to deck"), "Added to deck floats on the last pick")
    stub.advance(2)
    check(not pv:IsVisible(), "Standard overlay closed")

    -- Opening more packs: every choice face is fresh (alpha 1, scale 1).
    for _, def in ipairs({ { type = "ARCANA", size = "normal", cost = 4 }, { type = "STANDARD", size = "normal", cost = 4 } }) do
      pack = openPack(def)
      stub.advance(1)
      local n = 0
      for _, e in pairs(pv.packChoices) do
        n = n + 1
        eq(e.face:GetAlpha(), 1, def.type .. " choice face alpha")
        eq(e.face:GetScale(), 1, def.type .. " choice face scale")
      end
      check(n > 0, "choices built")
      click(pv.skip, "Skip " .. def.type)
      stub.advance(1)
    end

    -- Reload mid-pack, then pick a Scroll in the reloaded world.
    pack = openPack({ type = "ARCANA", size = "normal", cost = 4 })
    pack.choices[1] = { kind = "scroll", id = "FURY" }
    ns.UI.OnRunChanged()
    local w3 = newWorld(deepCopy(env.AzerothAnteDB))
    w3.env.SlashCmdList.AZEROTHANTE()
    w3.stub.advance(1)
    local pv3
    for _, c in ipairs(w3.ns.UI.Main.content._children) do
      if c.packChoices then pv3 = c end
    end
    check(pv3 and pv3:IsVisible(), "reloaded pack shows")
    local run3 = w3.ns.UI.Main.run
    local hand3 = packHand(pv3)
    local c1, c2 = hand3[1].card, hand3[2].card
    c1.enh, c2.enh = nil, nil
    check(w3.ns.Deck.find(run3, c1.id) == c1, "reloaded pack hand shares the deck's card tables")
    click(pv3.packChoices[1].frame, "reloaded Fury choice")
    click(hand3[1], "reloaded card 1")
    click(hand3[2], "reloaded card 2")
    click(pv3.pick, "Pick in the reloaded world")
    w3.stub.advance(2)
    eq(w3.ns.Deck.find(run3, c1.id).enh, "MULT", "reloaded pick changed the deck card 1")
    eq(w3.ns.Deck.find(run3, c2.id).enh, "MULT", "reloaded pick changed the deck card 2")
    check(run3.shop.openPack == nil, "reloaded pack closed")
    -- Back in the original world, clear the open pack.
    click(pv.skip, "Skip the original pack")
    stub.advance(1)
    r.consumables = {}
  end
  step("4c last pick animates, faces reset, reload pick hits the deck")

  -- 4d. A playing-card offer (Magic Trick) renders as a card face, buys into the
  -- deck, and an unbought one survives a reload.
  do
    local r = Main.run
    local sp = panel("offerCards")
    check(r.phase == "shop" and r.shop and not r.shop.openPack, "4d starts in the shop")
    r.gold = 50
    r.consumables = { { kind = "scroll", id = "FURY" }, { kind = "scroll", id = "FURY" } } -- slots full
    r.shop.cards[1] = { type = "card", rank = 12, suit = "H", enh = "GLASS", ed = "FOIL", seal = "RED", cost = 5, baseCost = 5 }
    r.shop.cards[2] = { type = "card", rank = 7, suit = "S", cost = 1, baseCost = 1 }
    local ok, err = pcall(Main.Render, r, true)
    check(ok, "the shop renders a playing-card offer: " .. tostring(err))
    stub.advance(1)
    local col = sp.offerCards[1]
    local w = col.cardWidget
    check(w and not w.released and w:IsShown(), "the card offer shows a CardWidget face")
    check(w.card.rank == 12 and w.card.suit == "H" and w.card.ed == "FOIL", "the face shows the offered card")
    check(w.face.fx ~= nil, "the card face carries its edition FX")
    check(not col.face:IsShown(), "the item face is hidden for a card")
    eq(col.name:GetText(), "Queen of Hearts", "card name")
    check(col.desc:GetText():find("Glass", 1, true) and col.desc:GetText():find("Red Seal", 1, true)
      and col.desc:GetText():find("Foil", 1, true), "description lists enhancement, seal and edition")
    check(col.buy:IsEnabled() and col.buy:GetText() == "Buy", "a card never says Slots full")
    local before, count = r.gold, #r.deck
    click(col.buy, "Buy the card")
    stub.advance(1)
    eq(#r.deck, count + 1, "the card joined the deck")
    eq(r.gold, before - 5, "gold dropped by the price")
    eq(#r.consumables, 2, "no consumable was added")
    eq(Main.sidebar.deckButton:GetText(), "Deck (" .. #r.deck .. ")", "the sidebar deck count updated")
    check(r.shop.cards[1] == false and not col.cardWidget, "the sold column released its card face")
    check(sp.offerCards[2].cardWidget ~= nil, "the second card offer still shows")
    -- Reload with an unbought card offer.
    ns.UI.OnRunChanged()
    local w4 = newWorld(deepCopy(env.AzerothAnteDB))
    w4.env.SlashCmdList.AZEROTHANTE()
    w4.stub.advance(1)
    local sp4
    for _, c in ipairs(w4.ns.UI.Main.content._children) do
      if c.offerCards then sp4 = c end
    end
    check(sp4 and sp4:IsVisible(), "the reloaded shop shows")
    check(sp4.offerCards[2].cardWidget and sp4.offerCards[2].cardWidget.card.rank == 7, "the reloaded card offer renders")
    r.consumables = {}
  end
  step("4d shop playing-card offer: render, buy into deck, reload")

  -- 5. Shop.
  local run = Main.run
  run.gold = 100
  run.shop.cards = {
    { type = "trinket", id = "BLOODLUST", cost = 4 },
    { type = "tome", id = "PAIR", cost = 3 },
  }
  Main.Render(run)
  stub.advance(1)
  local shop = panel("offerCards")
  local gold = run.gold
  click(shop.offerCards[1].buy, "buy offer 1")
  check(run.gold < gold, "buying offer 1 spends gold")
  eq(#run.trinkets, 1, "trinket owned")
  run.trinkets[1].ed = "HOLO"
  Main.Render(run)
  check(Main.trinketRow.slots[1].holder.fx and Main.trinketRow.slots[1].holder.fx.active, "trinket edition FX attached")
  check(FX.IsRunning(), "EditionFX driver runs for a trinket edition")
  check(not (Main.trinketRow.slots[6] and Main.trinketRow.slots[6]:IsShown()), "five trinket slots without a Negative trinket")
  run.trinkets[1].ed = "NEGATIVE"
  Main.Render(run)
  check(Main.trinketRow.slots[6] and Main.trinketRow.slots[6]:IsShown(), "a Negative trinket adds a sixth slot")
  run.trinkets[1].ed = "HOLO"
  Main.Render(run)
  check(not Main.trinketRow.slots[6]:IsShown(), "the extra slot goes when the edition does")
  stub.advance(1)
  gold = run.gold
  click(shop.offerCards[2].buy, "buy tome")
  check(run.gold < gold, "buying the tome spends gold")
  eq(run.handLevels.PAIR, 1, "bought tome waits for use")
  eq(run.consumables[1].kind, "tome", "tome stored in consumable slot")
  eq(run.consumables[1].id, "PAIR", "bought the offered tome")
  gold = run.gold
  click(shop.reroll, "Reroll")
  check(run.gold < gold, "reroll spends gold")
  gold = run.gold
  stub.advance(1)
  local slot1 = Main.trinketRow.slots[1]
  check(slot1.sell:IsVisible(), "sell button visible in the shop")
  check(slot1.sell:GetText():match("^%d+g$"), "sell button is labelled Ng")
  click(slot1.sell, "sell trinket")
  check(run.gold > gold, "selling refunds gold")
  eq(#run.trinkets, 0, "trinket sold")
  -- With the popover open, ONE click on a shop button both acts and closes the popover.
  click(Main.consumableRow.slots[1], "consumable slot in the shop")
  check(panel("use"):IsShown(), "popover open on the shop screen")
  gold = run.gold
  stub.over = { [shop.reroll] = true }
  stub.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
  click(shop.reroll, "Reroll (popover open)")
  stub.over = {}
  check(run.gold < gold, "the first click on Reroll still rerolls")
  check(not panel("use"):IsShown(), "and the same click closed the popover")
  click(shop.next, "Next Blind")
  do -- the panels animate in and the new current one settles, the beaten one is stamped
    local bs = panel("preview")
    local Tw = ns.UI.Tween
    eq(run.blind, 2, "second blind next")
    check(Tw.Count() > 0, "the entrance animation is running")
    stub.advance(0.03)
    check(bs.panels[3]:GetAlpha() < 0.01, "the last panel has not faded in yet (staggered)")
    stub.advance(0.1)
    local a1, a3 = bs.panels[1]:GetAlpha(), bs.panels[3]:GetAlpha()
    check(a1 > 0.3 and a1 < 1 and a3 < a1, "mid-entrance: fading in, staggered (" .. a1 .. ", " .. a3 .. ")")
    check(not HandView.IsBusy() and not ns.UI.Tally.IsBusy(), "animation is not a busy hang")
    stub.advance(0.2)
    check(Tw.IsActive(bs.panels[2].body) or bs.panels[2].body:GetScale() > 1, "the new current panel pops")
    check(bs.panels[1].stamp:IsShown(), "the beaten blind shows its DEFEATED stamp")
    check(Tw.IsActive(bs.panels[1].stamp) or bs.panels[1].stamp:GetScale() ~= 1, "the stamp lands with a pop")
    stub.advance(1)
    eq(Tw.Count(), 0, "all panel tweens have finished")
    local st = {}
    for i = 1, 3 do st[i] = bs.panels[i].state end
    eq(table.concat(st, ","), "DEFEATED,CURRENT,UPCOMING", "after beating blind 1")
    eq(bs.panels[1].stamp:GetScale(), 1, "stamp settled")
    eq(bs.panels[2].body:GetScale(), 1, "settle pop finished")
    check(bs.panels[2].play:IsEnabled() and bs.panels[2].play:IsVisible(), "the current Play is clickable once its panel is in")
  end
  stub.advance(1)
  eq(run.phase, "blind", "phase after Next Blind")
  check(visible("preview"), "blind screen visible after shop")
  step("5 shop buy, tome, reroll, sell, next blind")

  -- 5b. Consumables on the blind screen: untargeted use and sell.
  run.gold = 10
  run.consumables = {}
  ns.Consumables.add(run, { kind = "scroll", id = "GREED" })
  Main.Render(run)
  stub.advance(1)
  local brow = Main.consumableRow
  local bpop = panel("use")
  click(brow.slots[1], "consumable slot on the blind screen")
  check(bpop:IsVisible(), "popover visible over the blind screen")
  check(bpop:GetFrameLevel() > panel("preview"):GetFrameLevel(), "popover sits above the screen panel")
  click(bpop.use, "Use Greed")
  stub.advance(0.1)
  check(stub.findText("+10g"), "gold floats over the sidebar")
  stub.advance(2)
  check(not stub.findText("+10g"), "the gold float fades away")
  eq(run.gold, 20, "Greed doubled the gold")
  eq(#run.consumables, 0, "Greed consumed")
  eq(Main.sidebar.gold:GetText(), "Gold: 20g", "sidebar shows the doubled gold")
  ns.Consumables.add(run, { kind = "scroll", id = "FURY" })
  Main.Render(run)
  click(brow.slots[1], "slot for a targeted scroll")
  check(not bpop.use:IsEnabled(), "targeted consumable cannot be used without a hand")
  eq(bpop.use.reason, "Use while playing a hand", "reason says to use it while playing")
  eq(bpop.sell:GetText(), "Sell (1g)", "sell button shows its price")
  click(bpop.sell, "Sell scroll")
  stub.advance(1)
  eq(run.gold, 21, "selling refunds half the cost")
  eq(#run.consumables, 0, "sold consumable leaves its slot")
  check(not bpop:IsShown(), "popover closes after Sell")
  step("5b consumables on the blind screen, sell")

  -- 6. Persistence.
  local saved = env.AzerothAnteDB.run
  check(saved ~= nil, "AzerothAnteDB.run saved")
  eq(saved.phase, "blind", "saved phase")
  local db = deepCopy(env.AzerothAnteDB)
  local w2 = newWorld(db)
  w2.env.SlashCmdList.AZEROTHANTE()
  w2.stub.advance(1)
  local M2 = w2.ns.UI.Main
  check(M2.frame:IsShown(), "window shown after reload")
  check(deepEq(M2.run, db.run), "resumed run equals saved run")
  local blind2
  for _, c in ipairs(M2.content._children) do
    if c.preview then blind2 = c end
  end
  check(blind2 and blind2:IsVisible(), "blind screen shows after reload")
  do -- a reload into the blind phase: panel states, run info, hidden pile
    local bs2 = blind2
    local st = {}
    for i = 1, 3 do st[i] = bs2.panels[i].state end
    eq(table.concat(st, ","), "DEFEATED,CURRENT,UPCOMING", "reloaded blind screen shows the right states")
    check(bs2.panels[1].stamp:IsShown() and bs2.panels[1].stamp:GetScale() == 1, "reloaded: the stamp is simply there")
    check(M2.sidebar.deckName:IsShown() and M2.sidebar.deckName:GetText() == "Rogue Deck", "reloaded sidebar shows the deck")
    eq(M2.sidebar.gold:GetText(), "Gold: " .. M2.run.gold .. "g", "reloaded sidebar gold")
    check(not M2.sidebar.chipsBox:IsShown(), "reloaded sidebar has no 0 x 0 boxes")
    check(not w2.ns.UI.HandView.deck:IsShown(), "reloaded blind screen hides the deck pile")
    for id in pairs(w2.ns.Bosses.def) do
      check(w2.ns.UI.BlindSelect.BOSS_TINT[id], "boss tint for " .. id)
    end
    local nTint = 0
    for _ in pairs(w2.ns.UI.BlindSelect.BOSS_TINT) do nTint = nTint + 1 end
    eq(nTint, 9, "nine boss tints")
    for i = 1, 3 do
      eq(tonumber(bs2.panels[i].reward:GetText():match("|cffffd100(%d+)g|r")), w2.ns.Run.BLIND_REWARDS[i], "reward g amount matches Run.BLIND_REWARDS")
    end
    -- Play mid-entrance starts the blind, and a reload into play shows the pile
    local db2 = deepCopy(db)
    local w3 = newWorld(db2)
    w3.env.SlashCmdList.AZEROTHANTE()
    w3.stub.advance(0.05)
    local m3 = w3.ns.UI.Main
    check(w3.ns.UI.Tween.Count() > 0, "mid-entrance: tweens still running")
    local play3 = m3.content._children
    local bs3
    for _, c in ipairs(play3) do if c.preview then bs3 = c end end
    check(bs3.panels[2].play:IsVisible() and bs3.panels[2].play:IsEnabled() and bs3.panels[2].play:IsMouseEnabled(), "Play is clickable mid-entrance")
    bs3.panels[2].play:Click()
    eq(m3.run.phase, "play", "clicking Play mid-entrance starts the blind")
    w3.stub.advance(3)
    eq(w3.ns.UI.Tween.Count(), 0, "no tweens left after starting mid-entrance")
    check(w3.ns.UI.HandView.deck:IsShown(), "the pile shows in play")
    local w4 = newWorld(deepCopy(db2))
    w4.env.SlashCmdList.AZEROTHANTE()
    w4.stub.advance(1)
    eq(w4.ns.UI.Main.run.phase, "play", "reloaded into play")
    check(w4.ns.UI.HandView.deck:IsShown(), "a reload into play shows the deck pile")
  end
  step("6 persistence and reload resume")

  -- From here on drive the reloaded world.
  w, ns, stub, env = w2, w2.ns, w2.stub, w2.env
  Main, HandView, Tally = ns.UI.Main, ns.UI.HandView, ns.UI.Tally

  -- 7. Queue.
  env.SlashCmdList.AZEROTHANTE() -- hide
  stub.advance(1)
  check(not Main.frame:IsShown(), "window hidden by toggle")
  stub.lfg[1] = "queued"
  stub.fire("LFG_UPDATE")
  stub.advance(1)
  check(Main.frame:IsShown(), "queue join shows the window")
  stub.fire("LFG_PROPOSAL_SHOW")
  stub.advance(1)
  check(stub.findText("Queue popped!"), "paused overlay visible")
  eq(Main.frame:GetFrameStrata(), "HIGH", "main window sits above world nameplates")
  eq(Main.content:GetFrameStrata(), "HIGH", "window children inherit the HIGH strata (popovers, pause overlay)")
  eq(stub.tooltip:GetFrameStrata(), "TOOLTIP", "tooltips stay above the window")
  eq(stub.sounds[#stub.sounds], 8960, "ready check sound")
  stub.fire("LFG_PROPOSAL_SUCCEEDED")
  stub.advance(1)
  check(not Main.frame:IsShown(), "window hides when the queue is accepted")
  check(not stub.findText("Queue popped!"), "paused overlay hidden")
  stub.lfg[1] = nil
  stub.fire("LFG_UPDATE")
  step("7 queue join, proposal, accepted")

  -- 8. Lose path.
  open()
  check(Main.frame:IsShown(), "window shown")
  click(panel("preview").start, "Start Blind")
  stub.advance(3)
  eq(Main.run.phase, "play", "phase after Start Blind")
  Main.run.handsLeft = 1
  Main.run.target = 10 ^ 9
  selectCard(1)
  playSelected()
  stub.advance(10)
  eq(Main.run.phase, "lost", "phase after the last hand")
  check(visible("head"), "end screen visible")
  eq(panel("head").head:GetText(), "Defeated", "end screen headline")
  click(panel("head").new, "New Run")
  stub.advance(1)
  check(visible("carousel"), "newrun screen after New Run")
  check(env.AzerothAnteDB.run == nil, "save cleared by New Run")
  step("8 lose path and New Run")

  -- 8b. A hand and deck that run out lose the blind at once, with the board unlocked.
  do
    local function newBlind()
      startDeck("ROGUE")
      stub.advance(1)
      click(panel("preview").start, "Start Blind (8b)")
      stub.advance(3)
      eq(Main.run.phase, "play", "phase after Start Blind (8b)")
      local r = Main.run
      r.target = 10 ^ 9
      r.pile = {}
      r.hand = { r.hand[1], r.hand[2] }
      r.deck = { r.hand[1], r.hand[2] }
      HandView.Update(r, false)
      stub.advance(1)
      return r
    end
    -- Discarding the last cards.
    local r = newBlind()
    selectCard(1)
    selectCard(2)
    click(Main.buttons.discard, "Discard the last two cards")
    stub.advance(5)
    eq(r.phase, "lost", "an empty hand and deck lose the blind (discard)")
    check(visible("head") and panel("head").head:GetText() == "Defeated", "the defeat screen shows")
    check(not HandView.IsBusy() and not Tally.IsBusy(), "nothing stays busy after the discard loss")
    click(panel("head").new, "New Run (8b discard)")
    stub.advance(1)
    -- Sacrificing the last cards.
    r = newBlind()
    r.consumables = {}
    ns.Consumables.add(r, { kind = "scroll", id = "SACRIFICE" })
    Main.Render(r)
    selectCard(1)
    selectCard(2)
    click(Main.consumableRow.slots[1], "Sacrifice slot")
    click(panel("use").use, "Use Scroll of Sacrifice")
    stub.advance(5)
    eq(r.phase, "lost", "an empty hand and deck lose the blind (consumable)")
    check(visible("head") and panel("head").head:GetText() == "Defeated", "the defeat screen shows (consumable)")
    check(not HandView.IsBusy(), "nothing stays busy after the consumable loss")
    click(panel("head").new, "New Run (8b consumable)")
    stub.advance(1)
    check(visible("carousel"), "newrun screen after the 8b losses")
  end
  step("8b empty hand and deck lose the blind without sticking")

  -- 9. Hide mid-tally.
  startDeck("WARRIOR")
  stub.advance(1)
  click(panel("preview").start, "Start Blind")
  stub.advance(3)
  selectCard(1)
  playSelected()
  Main.Hide()
  stub.advance(10)
  check(not HandView.IsBusy(), "busy after hiding immediately")
  check(not Tally.IsBusy(), "tally busy after hiding immediately")
  open()
  eq(Main.run.phase, "play", "still playing")
  selectCard(1)
  playSelected()
  local waited = 0
  while not Tally.IsBusy() and waited < 5 do
    stub.advance(0.05)
    waited = waited + 0.05
  end
  check(Tally.IsBusy(), "tally started")
  stub.advance(0.4)
  Main.Hide()
  stub.advance(10)
  check(not HandView.IsBusy(), "HandView busy after hiding mid-tally")
  check(not Tally.IsBusy(), "Tally busy after hiding mid-tally")
  step("9 hide mid-flight and mid-tally")

  -- 9b. A queue event mid-tally must not render the post-hand screens early.
  open()
  eq(Main.run.phase, "play", "still playing before the queue-event step")
  Main.run.target = 1
  selectCard(1)
  playSelected()
  waited = 0
  while not Tally.IsBusy() and waited < 5 do
    stub.advance(0.05)
    waited = waited + 0.05
  end
  check(Tally.IsBusy(), "tally started for the queue-event step")
  stub.advance(0.4)
  check(Tally.IsBusy(), "tally still running")
  stub.fire("LFG_PROPOSAL_SHOW")
  check(Tally.IsBusy(), "tally still running after the queue event")
  check(not visible("offerCards"), "shop screen appeared early on a queue event")
  stub.fire("LFG_PROPOSAL_FAILED")
  stub.advance(10)
  check(not Tally.IsBusy() and not HandView.IsBusy(), "board still locked after the tally")
  eq(Main.run.phase, "shop", "phase after the winning hand")
  check(visible("offerCards"), "shop screen shows once the tally is done")
  step("9b queue event mid-tally does not re-render")

  -- 9c. Abandon Run: two clicks, with a revert after 3s.
  local abandon = panel("offerCards").abandon
  eq(abandon:GetText(), "Abandon Run", "abandon label")
  click(abandon, "Abandon Run")
  eq(abandon:GetText(), "Click again to abandon", "abandon armed label")
  check(Main.run ~= nil and env.AzerothAnteDB.run ~= nil, "first abandon click keeps the run")
  stub.advance(3.5)
  eq(abandon:GetText(), "Abandon Run", "abandon reverts after 3s")
  click(abandon, "Abandon Run")
  click(abandon, "Abandon Run (confirm)")
  stub.advance(1)
  check(env.AzerothAnteDB.run == nil, "abandon clears the save")
  check(visible("carousel"), "abandon returns to the new-run screen")
  step("9c abandon run")

  -- 9d. Title-bar Abandon Run: any phase with a run, hidden on deck select.
  do
    local ab = Main.abandon
    check(ab and ab.themeButton == "danger", "title-bar Abandon exists, danger variant")
    check(not ab:IsShown(), "title-bar Abandon hidden on deck select")
    local function runsRecorded()
      local st = ns.Profile.get(env.AzerothAnteDB).stats.ROGUE
      return st and st.runs or 0
    end
    local before = runsRecorded()
    startDeck("ROGUE")
    stub.advance(1)
    check(ab:IsVisible(), "title-bar Abandon shown on the blind screen")
    click(panel("preview").start, "Start Blind (9d)")
    stub.advance(3)
    eq(Main.run.phase, "play", "9d: playing")
    Main.run.target = 1e9
    check(ab:IsVisible(), "title-bar Abandon shown during play")
    check(#handWidgets() > 0, "9d: a hand is dealt")
    -- a first click, then 3s: disarmed
    click(ab, "title Abandon")
    check(ab:GetText() ~= "Abandon Run", "title Abandon arms")
    stub.advance(3.5)
    eq(ab:GetText(), "Abandon Run", "title Abandon disarms after 3s")
    check(Main.run ~= nil and env.AzerothAnteDB.run ~= nil, "a lone click keeps the run")
    -- ignored while a tally runs
    selectCard(1)
    playSelected()
    local waited = 0
    while not Tally.IsBusy() and waited < 5 do
      stub.advance(0.05)
      waited = waited + 0.05
    end
    check(Tally.IsBusy(), "9d: tally started")
    stub.advance(0.3)
    ab:Click()
    ab:Click()
    check(Main.run ~= nil and env.AzerothAnteDB.run ~= nil, "Abandon is ignored during a tally")
    eq(ab:GetText(), "Abandon Run", "a blocked click does not arm")
    stub.advance(10)
    check(not Tally.IsBusy() and not HandView.IsBusy(), "9d: tally finished")
    eq(Main.run.phase, "play", "9d: still in the play phase")
    -- two clicks during play return to deck select, clean
    click(ab, "title Abandon (arm)")
    click(ab, "title Abandon (confirm)")
    stub.advance(1)
    check(Main.run == nil and env.AzerothAnteDB.run == nil, "play-phase abandon clears run and save")
    check(visible("carousel"), "play-phase abandon returns to deck select")
    check(not HandView.IsBusy() and not Tally.IsBusy(), "no busy state after abandon")
    eq(#handWidgets(), 0, "no hand widgets after abandon")
    eq(#HandView.HeldWidgets(), 0, "HandView holds no widgets after abandon")
    check(not HandView.deck:IsShown(), "deck pile hidden after abandon")
    check(not ab:IsShown(), "title-bar Abandon hidden again on deck select")
    eq(runsRecorded(), before, "play-phase abandon records no run")
    -- the shop
    startDeck("ROGUE")
    stub.advance(1)
    click(panel("preview").start, "Start Blind (9d shop)")
    stub.advance(3)
    Main.run.target = 1
    selectCard(1)
    playSelected()
    stub.advance(15)
    eq(Main.run.phase, "shop", "9d: reached the shop")
    check(ab:IsVisible(), "title-bar Abandon shown in the shop")
    click(ab, "title Abandon (shop arm)")
    click(ab, "title Abandon (shop confirm)")
    stub.advance(1)
    check(Main.run == nil and visible("carousel"), "shop abandon returns to deck select")
  end
  step("9d title-bar abandon: phases, arm timeout, tally block, clean play-phase exit")

  -- 9e. Danger variant contrast (WCAG 2.x).
  do
    local Theme = ns.UI.Theme
    local function lin(c) return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
    local function lum(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end
    local function ratio(a, b)
      local x, y = lum(a), lum(b)
      if x < y then x, y = y, x end
      return (x + 0.05) / (y + 0.05)
    end
    local d = Theme.buttons.danger
    check(ratio(d.text, d.fill) >= 4.5, "danger text/fill contrast " .. ratio(d.text, d.fill))
    check(ratio(d.border, Theme.insetFill) >= 3, "danger border/panel contrast " .. ratio(d.border, Theme.insetFill))
    check(ratio(d.border, Theme.bg) >= 3, "danger border/window contrast")
  end
  step("9e danger button contrast")

  local SMOKE_SEED = tonumber(os.getenv("SMOKE_SEED")) or 424242
  -- 10. The balance bot plays a scripted run through the UI: it decides, we click.
  do
    -- The world was swapped at step 6, so re-fetch everything from the live ns.
    local Main, HandView, Tally = ns.UI.Main, ns.UI.HandView, ns.UI.Tally
    local PackView, DeckView = ns.UI.PackView, ns.UI.DeckView
    local bot = dofile("tools/sim/bot.lua")(ns)
    local started = os.clock()
    local used = { consumables = 0, picks = 0, packs = 0, deck = 0, checked = 0, vouchers = 0 }
    -- Real saves, counted through a wrapper (Screens saves via ns.Save.store).
    local storeCalls, realStore = 0, ns.Save.store
    ns.Save.store = function(...)
      storeCalls = storeCalls + 1
      return realStore(...)
    end
    local played = {}

    local function busy()
      return HandView.IsBusy() or Tally.IsBusy() or PackView.IsBusy()
    end
    -- Lets animations finish, then checks nothing is stuck and the save matches the live run.
    local function settle(what, extra)
      local t = 0
      while busy() and t < 20 do
        stub.advance(0.25)
        t = t + 0.25
      end
      stub.advance(extra or 0.5) -- dealing is not "busy", so deals pass a longer wait
      check(not busy(), what .. ": stuck busy")
      check(env.AzerothAnteDB.run ~= nil and deepEq(env.AzerothAnteDB.run, Main.run), what .. ": save is out of date")
      used.checked = used.checked + 1
    end

    local function widgetOf(parent, card)
      for _, c in ipairs(parent._children) do
        if c.card == card and not c.released and c:IsShown() then return c end
      end
    end
    local function selectIn(parent, cards)
      for _, card in ipairs(cards) do
        local w = widgetOf(parent, card)
        click(w, "card widget")
        check(w.selected, "card did not become selected")
      end
    end

    -- Uses every consumable the bot wants to use: select, open the slot, click Use.
    local function useConsumables(inPlay, what)
      local slot = 1
      while slot <= #Main.run.consumables do
        local r = Main.run
        local item = r.consumables[slot]
        local cards = inPlay and r.hand or nil -- re-read: the hand changes between uses
        local idx = bot.usePlan(r, slot, cards)
        local done = false
        if idx then
          HandView.ClearSelection()
          local picked = {}
          for _, i in ipairs(idx) do picked[#picked + 1] = cards[i] end
          selectIn(Main.handArea, picked)
          click(Main.consumableRow.slots[slot], what .. " consumable slot " .. slot)
          click(popover().use, what .. " Use")
          settle(what .. " use", 2)
          done = Main.run.consumables[slot] ~= item
          if done then used.consumables = used.consumables + 1 end
        end
        if not done then slot = slot + 1 end
      end
      HandView.ClearSelection()
    end

    local function pickFromPack()
      while Main.run.shop.openPack do
        local r = Main.run
        local pack = r.shop.openPack
        local pv = panel("packChoices")
        check(pv and pv:IsVisible(), "PackView visible while a pack is open")
        local choice, idx = bot.choosePick(r, pack, played)
        if not choice then break end
        PackView.ClearSelection()
        local cards = {}
        for _, i in ipairs(idx) do cards[#cards + 1] = pack.hand[i] end
        selectIn(pv.hand, cards)
        click(pv.packChoices[choice].frame, "pack choice " .. choice)
        local left = pack.picksLeft
        click(pv.pick, "Pick")
        settle("pack pick")
        used.picks = used.picks + 1
        if Main.run.shop.openPack == pack then check(pack.picksLeft < left, "pick did not use a pick") end
      end
      if Main.run.shop.openPack then
        click(panel("packChoices").skip, "Skip")
        settle("pack skip")
      end
      eq(Main.run.shop.openPack, nil, "pack closed")
    end

    local function shopPhase(first)
      local r = Main.run
      -- Deliberate test bypass: seed the first shop's offers (and gold) so a pack,
      -- a Scroll and a trinket are always there to click, whatever the RNG dealt.
      if first then -- make sure the first shop has something of everything to click
        r.gold = 100
        r.shopVoucher = { id = "GRABBER", cost = 10 } -- seeded so a voucher is always reachable
        r.shop.cards = {
          { type = "scroll", id = "GREED", cost = 3 }, -- untargeted: usable in the shop
          { type = "trinket", id = "BLOODLUST", cost = 4 },
        }
        r.shop.packs = { { type = "ARCANA", size = "mega", cost = 8 }, { type = "CELESTIAL", size = "normal", cost = 4 } }
        Main.Render(r)
        ns.UI.OnRunChanged()
        stub.advance(1)
        -- Guaranteed consumable use on any seed: buy the Scroll and Use it here, by clicks.
        click(panel("offerCards").offerCards[1].buy, "buy Greed")
        settle("buy Greed")
        eq(Main.run.consumables[1] and Main.run.consumables[1].id, "GREED", "bought Greed")
        -- And a voucher, via the tile's own Buy button.
        local goldBefore = Main.run.gold
        local tile = panel("voucher").voucher
        check(tile.buy:IsEnabled(), "voucher Buy is enabled")
        click(tile.buy, "buy voucher")
        settle("buy voucher")
        check(Main.run.vouchers.GRABBER, "the voucher was bought")
        eq(Main.run.gold, goldBefore - 10, "the voucher cost its price")
        eq(Main.run.shopVoucher, false, "the voucher is sold out")
        used.vouchers = 1
      end
      useConsumables(nil, "shop")
      if first then check(used.consumables >= 1, "the seeded shop's Scroll was used") end
      local function offers() return panel("offerCards") end
      -- Trinkets, best first.
      local again = true
      while again do
        again = false
        r = Main.run
        local bestI, bestWeight = nil, 0
        for i, offer in ipairs(r.shop.cards) do
          if offer and offer.type == "trinket" and offer.cost <= r.gold and #r.trinkets < ns.Run.trinketSlots(r) then
            local weight = bot.trinketWeight(offer)
            if weight > bestWeight then bestI, bestWeight = i, weight end
          end
        end
        if bestI then
          click(offers().offerCards[bestI].buy, "buy trinket")
          settle("buy trinket")
          again = true
        end
      end
      local favourite = bot.mostPlayed(Main.run, played)
      for i, offer in ipairs(Main.run.shop.cards) do
        if offer and offer.type == "tome" and offer.id == favourite and offers().offerCards[i].buy:IsEnabled() then
          click(offers().offerCards[i].buy, "buy tome")
          settle("buy tome")
        end
      end
      for i, offer in ipairs(Main.run.shop.packs) do
        if offer and (offer.type == "ARCANA" or offer.type == "CELESTIAL")
          and Main.run.gold >= 8 and offer.cost <= Main.run.gold then
          click(offers().packOffers[i].buy, "open pack")
          settle("open pack")
          used.packs = used.packs + 1
          pickFromPack()
        end
      end
      for i, offer in ipairs(Main.run.shop.cards) do
        if offer and offer.type == "scroll" and bot.SCROLL_RANK[offer.id] and Main.run.gold >= 8
          and offers().offerCards[i].buy:IsEnabled() then
          click(offers().offerCards[i].buy, "buy scroll")
          settle("buy scroll")
        end
      end
      useConsumables(nil, "shop")
      click(offers().next, "Next Blind")
      settle("next blind")
    end

    local beaten = 0
    local function beatenSoFar() return beaten end
    local function playBlind()
      local r = Main.run
      click(panel("preview").start, "Start Blind")
      settle("start blind", 3)
      eq(Main.run.phase, "play", "phase after Start Blind")
      if beatenSoFar() == 0 then
        -- Deliberate test bypass: the first blind must be winnable whatever the deal,
        -- so the later steps (shop, packs, consumables) are always reached.
        Main.run.target = 100
        ns.UI.OnRunChanged()
      end
      if used.deck == 0 then -- the deck view, opened and closed by clicks
        click(Main.sidebar.deckButton, "Deck button")
        stub.advance(0.3)
        check(DeckView.IsShown() and visible("deckTitle"), "deck view opens")
        click(panel("deckTitle").close, "deck view Close")
        check(not DeckView.IsShown(), "deck view closes")
        used.deck = used.deck + 1
      end
      useConsumables(true, "blind")
      while Main.run.phase == "play" do
        r = Main.run
        HandView.ClearSelection()
        local best, idx = bot.bestPlay(r)
        local need = (r.target - r.score) / r.handsLeft
        local plan
        if best < need and best < r.target - r.score and r.discardsLeft > 0 then
          plan = bot.discardPlan(r, idx)
          if #plan == 0 then plan = nil end
        end
        local cards = {}
        for _, i in ipairs(plan or idx) do cards[#cards + 1] = r.hand[i] end
        selectIn(Main.handArea, cards)
        if plan then
          click(Main.buttons.discard, "Discard")
        else
          click(Main.buttons.play, "Play")
        end
        local handId
        if not plan then handId = ns.HandEval.evaluate(cards).id end
        settle(plan and "discard" or "play", 3)
        if handId then played[handId] = (played[handId] or 0) + 1 end
      end
    end

    -- Pin the seed so the whole run is reproducible.
    local realNew = ns.Run.new
    ns.Run.new = function(_, deckId) return realNew(SMOKE_SEED, deckId) end
    startDeck("ROGUE")
    stub.advance(1)
    while beaten < 6 and Main.run.phase ~= "lost" and Main.run.phase ~= "won" do
      playBlind()
      if Main.run.phase == "shop" then
        beaten = beaten + 1
        shopPhase(beaten == 1)
      end
    end
    check(beaten >= 1 and (beaten >= 6 or Main.run.phase == "lost" or Main.run.phase == "won"), "the bot got through its blinds")
    check(used.consumables >= 1, "a consumable was used through the UI")
    check(used.packs >= 1 and used.picks >= 1, "a pack was opened and picked from")
    check(used.deck >= 1, "the deck view was used")
    check(used.vouchers >= 1 and Main.run.vouchers.GRABBER, "a voucher was bought through the UI")
    check(used.checked > 10 and storeCalls >= used.checked, "the run saved after every checked action")
    ns.Save.store = realStore
    ns.Run.new = realNew
    local elapsed = os.clock() - started
    check(elapsed < 60, "bot-driven run took " .. elapsed .. "s")
    print(("    bot run: %d blinds beaten, ended %s, %d consumables, %d packs, %d picks, %d actions checked, %d saves, %.1fs"):format(
      beaten, Main.run.phase, used.consumables, used.packs, used.picks, used.checked, storeCalls, elapsed))
  end
  step("10 bot drives a full run through the UI")

  -- 11. Deck-select unlocks, run recording and the Monk payout, each in a fresh world.
  local extraWorlds = {}
  local function boot(db)
    local w2 = newWorld(db)
    extraWorlds[#extraWorlds + 1] = w2
    local m = w2.ns.UI.Main
    local function open2(t)
      w2.env.SlashCmdList.AZEROTHANTE()
      w2.stub.advance(t or 1)
    end
    local function panel2(field)
      for _, c in ipairs(m.content._children) do
        if c[field] then return c end
      end
    end
    return w2, open2, panel2, m
  end

  do -- 11a. The unlock flourish
    local db = {}
    local w2, open2, panel2, m = boot(db)
    local ns2, stub2 = w2.ns, w2.stub
    local DS2 = ns2.UI.DeckSelect
    open2()
    eq(DS2.Selected(), "ROGUE", "fresh profile centres ROGUE")
    check(not DS2.Flourishing(), "the starter deck gets no flourish")
    check(ns2.Profile.get(db).seenUnlocks.ROGUE, "the starter deck is marked seen silently")
    m.Hide()
    local prof = ns2.Profile.get(db)
    for i = 1, ns2.Profile.unlockThreshold("WARRIOR") do prof.discovered["test:" .. i] = true end
    local seen = {}
    local realMark = ns2.Profile.markSeen
    ns2.Profile.markSeen = function(d, id)
      seen[#seen + 1] = id
      return realMark(d, id)
    end
    w2.env.SlashCmdList.AZEROTHANTE()
    stub2.advance(0.2)
    eq(DS2.Selected(), "WARRIOR", "reopening centres the newly unlocked deck")
    eq(DS2.Flourishing(), "WARRIOR", "the unlock flourish plays for WARRIOR")
    local p2 = panel2("carousel")
    check(p2.unlockedText:IsShown() and p2.unlockedText:GetText() == "Unlocked!", "the Unlocked! text shows")
    check(DS2.Card("WARRIOR").lock:IsShown(), "the padlock is still up at the start")
    local fadeAlpha = DS2.Card("WARRIOR").lock:GetAlpha()
    check(fadeAlpha > 0.02 and fadeAlpha < 0.98, "the padlock is mid-fade at 0.2s (" .. fadeAlpha .. ")")
    -- Navigation is ignored while the flourish plays, so it can never land on the wrong deck.
    click(p2.nextBtn, "next arrow during the flourish")
    click(DS2.Card("ROGUE"), "a neighbour during the flourish")
    eq(DS2.Selected(), "WARRIOR", "arrows and cards are ignored during a flourish")
    eq(DS2.Flourishing(), "WARRIOR", "the flourish stays on its deck")
    eq(#seen, 0, "markSeen waits for the flourish to finish")
    stub2.advance(0.5)
    stub2.advance(2.5)
    check(not DS2.Flourishing(), "the flourish ends")
    eq(seen[1], "WARRIOR", "markSeen called for WARRIOR")
    check(not DS2.Card("WARRIOR").lock:IsShown(), "the padlock is gone")
    check(not DS2.Card("WARRIOR").art:IsDesaturated(), "the art saturates")
    check(not p2.unlockedText:IsShown(), "the Unlocked! text is gone")
    check(p2.play:IsEnabled(), "WARRIOR is playable")
    m.Hide()
    open2()
    eq(#seen, 1, "no second flourish for a seen deck")
    -- Several unlocks play one at a time.
    m.Hide()
    for i = ns2.Profile.unlockThreshold("WARRIOR") + 1, ns2.Profile.unlockThreshold("WARLOCK") do prof.discovered["test:" .. i] = true end
    w2.env.SlashCmdList.AZEROTHANTE()
    stub2.advance(0.2)
    eq(DS2.Flourishing(), "GOBLIN", "first of several")
    stub2.advance(2.7)
    eq(DS2.Flourishing(), "MONK", "then the next one")
    eq(DS2.Selected(), "MONK", "the carousel follows to the next unlock")
    stub2.advance(10)
    check(not DS2.Flourishing(), "all flourishes done")
    eq(table.concat(seen, ","), "WARRIOR,GOBLIN,MONK,WARLOCK", "each unlock is marked seen once, in order")
    eq(#ns2.Profile.newlyUnlocked(db), 0, "nothing left to announce")
    -- Closing mid-flourish still marks the deck seen.
    ns2.Profile.get(db).seenUnlocks.WARLOCK = nil
    m.Hide()
    w2.env.SlashCmdList.AZEROTHANTE()
    stub2.advance(0.3)
    eq(DS2.Flourishing(), "WARLOCK", "replay for an unseen deck")
    m.Hide()
    check(not DS2.Flourishing() and ns2.Profile.get(db).seenUnlocks.WARLOCK, "closing the window ends the flourish and marks it seen")
    ns2.Profile.markSeen = realMark
  end
  step("11a unlock flourish centres, plays, marks seen, queues")

  do -- 11b. Run recording
    local db = {}
    local w2, open2, panel2, m = boot(db)
    local ns2, stub2 = w2.ns, w2.stub
    open2()
    panel2("carousel").play:Click()
    stub2.advance(1)
    local run2 = m.run
    run2.phase, run2.stage = "lost", 3
    m.Render(run2, true)
    stub2.advance(1)
    local stats = ns2.Profile.get(db).stats
    eq(stats.ROGUE.runs, 1, "a lost run is recorded")
    eq(stats.ROGUE.bestStage, 3, "best stage recorded")
    eq(run2.recorded, true, "the run carries recorded = true")
    m.Render(run2, true)
    m.Render(run2, true)
    eq(stats.ROGUE.runs, 1, "re-rendering does not record twice")
    check(db.run and db.run.recorded == true, "the flag is saved with the run")
    -- Reload the lost save: not counted again.
    local db3 = deepCopy(db)
    local w3, _, panel3, m3 = boot(db3)
    eq(m3.run and m3.run.phase, "lost", "the lost run reloads")
    eq(w3.ns.Profile.get(db3).stats.ROGUE.runs, 1, "a reload does not record the run again")
    -- A lost save from before recording (no flag) is counted once, then not again.
    local db4 = deepCopy(db)
    db4.run.recorded = nil
    db4.profile.stats = {}
    local w4, _, _, m4 = boot(db4)
    eq(w4.ns.Profile.get(db4).stats.ROGUE.runs, 1, "an unrecorded finished save is recorded on load")
    m4.Render(m4.run, true)
    eq(w4.ns.Profile.get(db4).stats.ROGUE.runs, 1, "and only once")
    -- Wins count, New Run clears, abandon does not record.
    w3.env.SlashCmdList.AZEROTHANTE()
    w3.stub.advance(1)
    local won = w3.ns.Run.new(5, "ROGUE")
    won.phase, won.stage = "won", 8
    m3.SetRun(won)
    eq(w3.ns.Profile.get(db3).stats.ROGUE.wins, 1, "a won run is recorded")
    eq(w3.ns.Profile.get(db3).stats.ROGUE.runs, 2, "runs counts both")
    click(panel3("head").new, "New Run")
    w3.stub.advance(1)
    panel3("carousel").play:Click()
    w3.stub.advance(1)
    local ab = panel3("preview").abandon
    click(ab, "Abandon")
    click(ab, "Abandon (confirm)")
    w3.stub.advance(1)
    eq(w3.ns.Profile.get(db3).stats.ROGUE.runs, 2, "abandoning a run does not record it")
  end
  step("11b a finished run records once, also across reloads; abandon does not")

  do -- 11c. Discovery binding is crash-proof
    local db = {}
    local w2 = boot(db)
    local ns2 = w2.ns
    check(type(ns2.Profile.onObtain) == "function", "onObtain is bound")
    ns2.Profile.onObtain("trinket", "BLOODLUST")
    eq(ns2.Profile.discoveredCount(db), 1, "obtaining an item discovers it")
    local realDiscover = ns2.Profile.discover
    ns2.Profile.discover = function() error("boom") end
    ns2.Profile.onObtain("trinket", "HEARTHSTONE")
    ns2.Profile.discover = realDiscover
    w2.env.AzerothAnteDB = nil
    ns2.Profile.onObtain("trinket", "HEARTHSTONE")
    w2.env.AzerothAnteDB = db
    eq(ns2.Profile.discoveredCount(db), 1, "errors and a missing DB are swallowed")
  end
  step("11c onObtain survives errors and a missing DB")

  do -- 11d. Monk payout rows add up to Total
    local db = { profile = { discovered = {} } }
    for i = 1, 18 do db.profile.discovered["test:" .. i] = true end
    local w2, open2, panel2, m = boot(db)
    local ns2, stub2 = w2.ns, w2.stub
    open2()
    ns2.UI.DeckSelect.Select("MONK", true)
    panel2("carousel").play:Click()
    stub2.advance(1)
    panel2("preview").start:Click()
    stub2.advance(3)
    local run2 = m.run
    eq(run2.deckId, "MONK", "Monk run")
    run2.handsLeft, run2.discardsLeft, run2.gold = 2, 3, 29
    ns2.Run.winBlind(run2)
    m.Render(run2, true)
    stub2.advance(1)
    local shop = panel2("offerCards")
    local function rowSum(p)
      local sum = 0
      for key, row in pairs(p.payout) do
        if key ~= "total" and row.label:IsShown() then sum = sum + tonumber(row.value:GetText():match("%d+")) end
      end
      return sum, tonumber(p.payout.total.value:GetText():match("%d+"))
    end
    eq(shop.payout.hands.label:GetText(), "Hands left (2 x 2g)", "Monk hands rate")
    eq(shop.payout.discards.label:GetText(), "Discards left (3 x 1g)", "Monk discards row")
    check(shop.payout.discards.label:IsShown(), "discards row shown when it pays")
    check(shop.payout.interest.label:GetText():find("none", 1, true), "interest row says none for Monk")
    local sum, total = rowSum(shop)
    eq(sum, total, "visible payout rows sum to Total (Monk)")
    eq(total, run2.lastPayout.total, "Total matches the run")
    -- A deck with interest and no per-discard pay.
    local run3 = ns2.Run.new(9, "ROGUE")
    m.SetRun(run3)
    ns2.Run.startBlind(run3)
    run3.handsLeft, run3.discardsLeft, run3.gold = 2, 3, 29
    ns2.Run.winBlind(run3)
    m.Render(run3, true)
    stub2.advance(1)
    check(not shop.payout.discards.label:IsShown(), "no discards row when it pays nothing")
    eq(shop.payout.hands.label:GetText(), "Hands left (2 x 1g)", "default hands rate")
    eq(shop.payout.interest.label:GetText(), "Interest", "interest row for other decks")
    -- Every deck's visible rows add up to Total.
    for _, id in ipairs({ "ROGUE", "WARRIOR", "GOBLIN", "MONK", "WARLOCK", "ADVENTURER" }) do
      local r = ns2.Run.new(9, id)
      m.SetRun(r)
      ns2.Run.startBlind(r)
      r.handsLeft, r.discardsLeft, r.gold = 2, 3, 29
      ns2.Run.winBlind(r)
      m.Render(r, true)
      stub2.advance(1)
      sum, total = rowSum(shop)
      eq(sum, total, "visible payout rows sum to Total (" .. id .. ")")
      eq(total, r.lastPayout.total, "Total matches the run (" .. id .. ")")
    end
  end
  step("11d payout rows for Monk add up")

  -- 11d2. Trinket UI: drag to reorder, live tooltips, tally events, round-end lines.
  do
    -- A play-phase board in its own world with the given trinkets; target is out of reach.
    local function board(ids)
      local w2, open2, panel2, m = boot({})
      local ns2, stub2 = w2.ns, w2.stub
      open2()
      local r = ns2.Run.new(SMOKE_SEED, "ROGUE")
      ns2.Run.startBlind(r)
      r.target = 1e9
      for _, id in ipairs(ids) do r.trinkets[#r.trinkets + 1] = ns2.Trinkets.create(r, id) end
      m.SetRun(r)
      stub2.advance(3)
      return w2, panel2, m, r
    end
    local function order(r)
      local out = {}
      for i, t in ipairs(r.trinkets) do out[i] = t.id end
      return table.concat(out, ",")
    end
    local function tipLines(stub2) return table.concat(stub2.tooltip._lines or {}, "\n") end
    -- Presses slot `from`, drags the cursor to slot `to`'s x in small steps, releases.
    local function drag(stub2, m, from, to, over)
      local row = m.trinketRow
      local es = row:GetEffectiveScale()
      local slots = row.slots
      local dx = slots[to]._points[1][4] - slots[from]._points[1][4]
      stub2.cursor.x, stub2.cursor.y = 600, 300
      stub2.mouseDown(slots[from])
      stub2.advance(0.03)
      for k = 1, 8 do
        stub2.cursor.x = 600 + dx * es * k / 8
        stub2.advance(0.03)
      end
      stub2.over[row] = over
      stub2.mouseUp(slots[from])
      stub2.over[row] = nil
    end
    local function startTally(w2, panel2, m)
      local ns2, stub2 = w2.ns, w2.stub
      local ws = {}
      for _, c in ipairs(m.handArea._children) do
        if c.card and not c.released and c:IsShown() then ws[#ws + 1] = c end
      end
      table.sort(ws, function(a, b) return a._points[1][4] < b._points[1][4] end)
      ws[1]:Click()
      m.buttons.play:Click()
      local waited = 0
      while not ns2.UI.Tally.IsBusy() and waited < 5 do
        stub2.advance(0.05)
        waited = waited + 0.05
      end
      check(ns2.UI.Tally.IsBusy(), "a tally started")
    end

    do -- trinket_drag_reorder
      local w2, panel2, m, r = board({ "FLIGHT_PATH", "SCHEMATIC", "ARCANE_INTELLECT" })
      local stub2 = w2.stub
      local uids = { r.trinkets[1].uid, r.trinkets[2].uid, r.trinkets[3].uid }
      drag(stub2, m, 1, 3, true)
      eq(order(r), "SCHEMATIC,ARCANE_INTELLECT,FLIGHT_PATH", "drag 1 -> 3 reorders the trinkets")
      eq(r.trinkets[3].uid, uids[1], "the dragged instance moved intact")
      stub2.advance(0.5)
      eq(m.trinketRow.slots[3].def.id, "FLIGHT_PATH", "the row shows the new order")
      eq(m.trinketRow.slots[1]._points[1][4], 0, "slots settle back on the grid")
      drag(stub2, m, 3, 2, true)
      eq(order(r), "SCHEMATIC,FLIGHT_PATH,ARCANE_INTELLECT", "drag 3 -> 2")
      check(not w2.ns.UI.Tally.IsBusy(), "a drag never starts a tally")
    end
    step("trinket_drag_reorder")

    do -- trinket_drag_busy_noop
      local w2, panel2, m, r = board({ "FLIGHT_PATH", "SCHEMATIC", "ARCANE_INTELLECT" })
      local stub2 = w2.stub
      startTally(w2, panel2, m)
      local before = order(r)
      drag(stub2, m, 1, 3, true)
      eq(order(r), before, "a drag during the tally changes nothing")
      stub2.advance(10)
      eq(order(r), before, "and nothing after it either")
      eq(#r.trinkets, 3, "no trinket dropped")
    end
    step("trinket_drag_busy_noop")

    do -- trinket_drag_outside_noop
      local w2, panel2, m, r = board({ "FLIGHT_PATH", "SCHEMATIC", "ARCANE_INTELLECT" })
      local stub2 = w2.stub
      local before = order(r)
      drag(stub2, m, 1, 3, nil)
      eq(order(r), before, "releasing outside the row changes nothing")
      stub2.advance(0.5)
      for i = 1, 3 do
        check(m.trinketRow.slots[i]._points[1][4] == (i - 1) * (m.trinketRow.slots[2]._points[1][4]),
          "slot " .. i .. " snapped back")
        eq(m.trinketRow.slots[i].holder:GetScale(), 1, "slot " .. i .. " is back to normal size")
      end
      -- A press with no real movement is a click: nothing moves.
      stub2.cursor.x = 600
      stub2.mouseDown(m.trinketRow.slots[2])
      stub2.cursor.x = 603
      stub2.advance(0.05)
      stub2.over[m.trinketRow] = true
      stub2.mouseUp(m.trinketRow.slots[2])
      stub2.over[m.trinketRow] = nil
      eq(order(r), before, "a click does not reorder")
    end
    step("trinket_drag_outside_noop")

    do -- tooltip_status_and_copies
      local w2, panel2, m, r = board({ "FLIGHT_PATH", "SCHEMATIC", "ARCANE_INTELLECT" })
      local stub2 = w2.stub
      local slots = m.trinketRow.slots
      slots[1]._scripts.OnEnter(slots[1])
      local t = tipLines(stub2)
      check(t:find("Flight Path", 1, true), "tooltip names the trinket")
      check(t:find("Common", 1, true), "tooltip shows the rarity")
      check(t:find("Currently +0 Mult", 1, true), "tooltip shows the status line")
      check(not t:find("Copies", 1, true), "a plain trinket has no Copies line")
      -- The tooltip follows the state while it is open.
      r.trinkets[1].state.mult = 7
      m.Render(r, true)
      check(tipLines(stub2):find("Currently +7 Mult", 1, true), "an open tooltip refreshes on render")
      slots[2]._scripts.OnEnter(slots[2])
      check(tipLines(stub2):find("Copies: Arcane Intellect", 1, true), "Blueprint names what it copies")
      slots[3]._scripts.OnLeave(slots[3])
      check(not stub2.tooltip:IsShown(), "leaving hides the tooltip")
    end
    step("tooltip_status_and_copies")

    do -- tally_destroy_ice_cream
      local w2, panel2, m, r = board({ "TIGULES", "FLIGHT_PATH" })
      local stub2, ns2 = w2.stub, w2.ns
      r.trinkets[1].state.chips = 5
      local fpUid = r.trinkets[2].uid
      local tigUid = r.trinkets[1].uid
      startTally(w2, panel2, m)
      local row = m.trinketRow
      eq(#r.trinkets, 1, "the engine already dropped the melted trinket")
      eq(row.slots[1].def.id, "TIGULES", "the row keeps showing it during the tally")
      local minAlpha, melted, waited = 1, false, 0
      while ns2.UI.Tally.IsBusy() and waited < 20 do
        stub2.advance(0.03)
        waited = waited + 0.03
        minAlpha = math.min(minAlpha, row.slots[1].holder:GetAlpha())
        melted = melted or stub2.findText("Melted!") ~= nil
      end
      check(not ns2.UI.Tally.IsBusy(), "the tally completed")
      check(minAlpha < 1, "the melting slot faded")
      check(melted, "the Melted! message floated")
      stub2.advance(0.5)
      eq(row.slots[1].def.id, "FLIGHT_PATH", "the survivor moved up")
      eq(row.slots[1].trinket.uid, fpUid, "the survivor is the same instance")
      check(row.slots[1].trinket == r.trinkets[1], "the row shows the live instance and its state")
      check(row.slots[2].def == nil, "the melted slot is gone")
      eq(row.slots[1].holder:GetAlpha(), 1, "the survivor is fully visible")
      eq(row.slots[2].holder:GetScale(), 1, "the empty slot is reset")
      check(r.trinkets[1].uid ~= tigUid, "Ice Cream is no longer owned")
    end
    step("tally_destroy_ice_cream")

    do -- tally_new_events: synthetic retrigger, message and level-up events
      local w2, panel2, m, r = board({ "FLIGHT_PATH", "ARCANE_INTELLECT" })
      local stub2, ns2 = w2.stub, w2.ns
      local uid = r.trinkets[2].uid
      local done = false
      ns2.UI.Tally.Play({ total = 0, chips = 1, mult = 1, events = {
        { kind = "base", handId = "PAIR", runChips = 10, runMult = 2 },
        { kind = "retrigger", index = 1, slot = 2, uid = uid },
        { kind = "trinketMsg", slot = 2, uid = uid, msg = "Upgrade!" },
        { kind = "levelUp", handId = "PAIR", slot = 2, uid = uid },
        { kind = "trinket", slot = 2, uid = uid, gold = 2, runChips = 10, runMult = 2 },
        { kind = "trinketMsg", slot = 9, uid = 12345, msg = "Ghost!" },
        { kind = "total", total = 20 },
      } }, {}, function() done = true end)
      local seen = {}
      for _ = 1, 400 do
        stub2.advance(0.05)
        for _, t in ipairs({ "Upgrade!", "Level up!", "+2g" }) do
          if stub2.findText(t) then seen[t] = true end
        end
        if done then break end
      end
      check(done, "the synthetic tally completed")
      check(seen["Upgrade!"], "trinketMsg floats its message")
      check(seen["Level up!"], "levelUp floats Level up!")
      check(seen["+2g"], "a gold-only trinket event shows its gold")
    end
    step("tally_new_events")

    do -- round_end_lines
      local w2, panel2, m, r = board({ "HEARTHSTONE", "SCHEMATIC", "FLIGHT_PATH" })
      local stub2, ns2 = w2.stub, w2.ns
      r.handsLeft, r.discardsLeft = 2, 0
      ns2.Run.winBlind(r)
      m.Render(r, true)
      stub2.advance(1)
      local shop = panel2("offerCards")
      local lines = {}
      for key, row in pairs(shop.payout) do
        if key:find("^trinket") and row.label:IsShown() then
          lines[#lines + 1] = row.label:GetText() .. " " .. row.value:GetText()
        end
      end
      eq(#lines, 1, "one payout line per paying trinket")
      eq(lines[1], "Hearthstone +4g", "the Hearthstone line")
      local sum = 0
      for key, row in pairs(shop.payout) do
        if key ~= "total" and row.label:IsShown() then sum = sum + tonumber(row.value:GetText():match("%d+")) end
      end
      eq(sum, tonumber(shop.payout.total.value:GetText():match("%d+")), "the lines add up to Total")
      -- Blueprint cannot copy Hearthstone.
      r.trinkets = { ns2.Trinkets.create(r, "SCHEMATIC"), ns2.Trinkets.create(r, "HEARTHSTONE") }
      m.Render(r, true)
      local slot1 = m.trinketRow.slots[1]
      slot1._scripts.OnEnter(slot1)
      check(tipLines(stub2):find("Copies: nothing (incompatible)", 1, true),
        "Blueprint beside Hearthstone says incompatible")
      -- A second paying trinket gets its own line.
      r.trinkets = { ns2.Trinkets.create(r, "HEARTHSTONE"), ns2.Trinkets.create(r, "HEARTHSTONE") }
      r.phase = "play"
      r.handsLeft = 2
      ns2.Run.winBlind(r)
      m.Render(r, true)
      stub2.advance(1)
      local n = 0
      for key, row in pairs(shop.payout) do
        if key:find("^trinket") and row.label:IsShown() then n = n + 1 end
      end
      eq(n, 2, "two paying trinkets give two lines")
    end
    step("round_end_lines")

    -- Lifecycle and economy UI (wave 2). Stub trinkets stand in for the real ones; each world is
    -- discarded afterwards, and the stubs are removed from its registry anyway.
    local function stubDef(ns2, def)
      def.name, def.rarity, def.cost = def.name or def.id, "common", def.cost or 4
      def.icon = def.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
      ns2.Trinkets.add(def)
    end
    local function unstub(ns2, defs)
      for _, def in ipairs(defs) do
        ns2.Trinkets.def[def.id] = nil
        for i, o in ipairs(ns2.Trinkets.order) do
          if o == def.id then table.remove(ns2.Trinkets.order, i) break end
        end
      end
    end
    -- A fresh world with a run in `phase` ("blind" or "play") owning `ids` (stub `defs` registered first).
    local function lifeBoard(ids, phase, defs)
      local w2, open2, panel2, m = boot({})
      local ns2, stub2 = w2.ns, w2.stub
      for _, def in ipairs(defs or {}) do stubDef(ns2, def) end
      open2()
      local r = ns2.Run.new(SMOKE_SEED, "ROGUE")
      for _, id in ipairs(ids) do r.trinkets[#r.trinkets + 1] = ns2.Trinkets.create(r, id) end
      if phase == "play" then
        ns2.Run.startBlind(r)
        r.target = 1e9
      end
      m.SetRun(r)
      stub2.advance(3)
      return w2, panel2, m, r
    end
    local function handCount(m)
      local n = 0
      for _, c in ipairs(m.handArea._children) do
        if c.card and not c.released and c:IsShown() then n = n + 1 end
      end
      return n
    end
    local function overlayOf(m)
      for _, c in ipairs(m.content._children) do
        if c.lifecycleOverlay and c:IsShown() then return c end
      end
    end
    local SMALLHAND = { id = "S_SMALLHAND", handSize = -2 } -- selling it grows the hand
    local function killer()
      return { id = "S_KILLER", onBlindSelect = function(run)
        return { msg = "Boom!", destroyTrinket = run.trinkets[2].uid, createTrinkets = { rarity = "common", n = 2 } }
      end }
    end

    do -- sell_trinket_mid_blind
      local defs = { SMALLHAND }
      local w2, panel2, m, r = lifeBoard({ "S_SMALLHAND", "FLIGHT_PATH" }, "play", defs)
      local stub2, ns2 = w2.stub, w2.ns
      eq(#r.hand, 6, "the hand starts at the stub's smaller size")
      eq(handCount(m), 6, "six card widgets")
      local slot1 = m.trinketRow.slots[1]
      check(slot1.sell:IsVisible(), "sell buttons show in a blind")
      local gold, uid2 = r.gold, r.trinkets[2].uid
      click(slot1.sell, "sell in a blind")
      stub2.advance(1)
      check(r.gold > gold, "selling in a blind refunds gold")
      eq(#r.trinkets, 1, "one trinket left")
      eq(m.trinketRow.slots[1].def.id, "FLIGHT_PATH", "the row closed the gap")
      eq(m.trinketRow.slots[1].trinket.uid, uid2, "the survivor is the same instance")
      check(m.trinketRow.slots[2].def == nil, "the sold slot is gone")
      eq(#r.hand, 8, "the hand refilled to the new size")
      eq(handCount(m), 8, "the hand view shows eight cards")
      eq(m.sidebar.gold:GetText(), "Gold: " .. r.gold .. "g", "the sidebar shows the new gold")
      check(m.trinketRow.slots[1].sell:IsVisible(), "sell stays available after a sell")
      unstub(ns2, defs)
    end
    step("sell_trinket_mid_blind")

    do -- sell_consumable_plays_lifecycle: a consumable sale that moves a trinket plays its events
      local w2, panel2, m, r = board({ "COOKING_FIRE" })
      local stub2, ns2 = w2.stub, w2.ns
      r.consumables = {}
      ns2.Consumables.add(r, { kind = "scroll", id = "CHANCE" })
      m.Render(r, true)
      stub2.advance(0.5)
      click(m.consumableRow.slots[1], "consumable slot")
      local pop
      for _, c in ipairs(m.content._children) do if c.use then pop = c end end
      check(pop and pop:IsVisible(), "the consumable popover opens")
      local seen = false
      click(pop.sell, "popover Sell")
      for _ = 1, 40 do
        stub2.advance(0.05)
        if stub2.findText("Upgrade!") then seen = true end
      end
      check(seen, "the Cooking Fire upgrade message floated after a consumable sale")
      eq(#(r.lifecycleEvents or {}), 0, "the sale's events were drained")
      eq(r.trinkets[1].state.x, 1.25, "Cooking Fire grew")
    end
    step("sell_consumable_plays_lifecycle")

    do -- sell_locked_during_tally
      local w2, panel2, m, r = lifeBoard({ "FLIGHT_PATH", "SCHEMATIC" }, "play")
      local stub2, ns2 = w2.stub, w2.ns
      local slots = m.trinketRow.slots
      check(slots[1].sell:IsEnabled(), "sell is live while idle")
      startTally(w2, panel2, m)
      stub2.advance(0.05)
      check(not slots[1].sell:IsEnabled(), "sell is disabled during the tally")
      slots[1].sell:Click()
      slots[1].sell._scripts.OnClick(slots[1].sell)
      eq(#r.trinkets, 2, "a click during the tally sells nothing")
      local waited = 0
      while ns2.UI.Tally.IsBusy() and waited < 20 do
        stub2.advance(0.1)
        waited = waited + 0.1
      end
      stub2.advance(1)
      check(slots[1].sell:IsEnabled(), "sell is live again after the tally")
      click(slots[1].sell, "sell after the tally")
      stub2.advance(1)
      eq(#r.trinkets, 1, "and sells")
    end
    step("sell_locked_during_tally")

    do -- blind_select_destroy_and_create
      local defs = { killer() }
      local w2, panel2, m, r = lifeBoard({ "S_KILLER", "FLIGHT_PATH" }, "blind", defs)
      local stub2, ns2 = w2.stub, w2.ns
      local LC = ns2.UI.Lifecycle
      check(LC and not LC.IsBusy(), "the lifecycle player exists and is idle")
      local victim = r.trinkets[2].uid
      click(panel2("preview").start, "Start Blind")
      eq(r.phase, "play", "the blind started")
      eq(#r.trinkets, 3, "the engine destroyed one and created two")
      check(LC.IsBusy(), "the events are playing")
      local row = m.trinketRow
      eq(row.slots[2].trinket.uid, victim, "the destroyed trinket is still shown while it melts")
      local seenBoom, minAlpha, minScale, waited = false, 1, 1, 0
      while LC.IsBusy() and waited < 5 do
        stub2.advance(0.03)
        waited = waited + 0.03
        seenBoom = seenBoom or stub2.findText("Boom!") ~= nil
        for i = 1, 3 do
          if row.slots[i].trinket and row.slots[i].trinket.uid == victim then
            minAlpha = math.min(minAlpha, row.slots[i].holder:GetAlpha())
          end
          if row.slots[i].trinket and i >= 2 and row.slots[i].trinket.uid ~= victim then
            minScale = math.min(minScale, row.slots[i].holder:GetScale())
          end
        end
      end
      check(waited < 2, "the queue drains in about queue length x 0.25s: " .. waited)
      check(seenBoom, "the message floated")
      check(minAlpha < 1, "the destroyed slot faded")
      check(minScale < 1, "a created slot popped in")
      stub2.advance(0.5)
      eq(row.slots[1].def.id, "S_KILLER", "the killer stays in slot 1")
      check(row.slots[2].def and row.slots[3].def, "two new trinkets fill slots 2 and 3")
      check(row.slots[2].trinket.uid ~= victim and row.slots[3].trinket.uid ~= victim, "the victim is gone")
      for i = 1, 3 do
        eq(row.slots[i].holder:GetAlpha(), 1, "slot " .. i .. " is fully visible")
        eq(row.slots[i].holder:GetScale(), 1, "slot " .. i .. " is full size")
        check(row.slots[i].trinket == r.trinkets[i], "slot " .. i .. " shows the live instance")
      end
      eq(#r.lifecycleEvents, 0, "the events were drained")
      eq(handCount(m), #r.hand, "the hand is dealt")
      check(m.handArea:IsShown(), "the play screen is up")
      unstub(ns2, defs)
    end
    step("blind_select_destroy_and_create")

    do -- lifecycle_click_speeds_up
      local defs = { killer() }
      local w2, panel2, m = lifeBoard({ "S_KILLER", "FLIGHT_PATH" }, "blind", defs)
      local stub2, ns2 = w2.stub, w2.ns
      click(panel2("preview").start, "Start Blind")
      stub2.advance(0.1)
      check(ns2.UI.Lifecycle.IsBusy(), "still playing")
      local ov = overlayOf(m)
      check(ov, "a click catcher covers the table while events play")
      ov:Click()
      stub2.advance(0.4)
      check(not ns2.UI.Lifecycle.IsBusy(), "a click speeds the queue up")
      unstub(ns2, defs)
    end
    step("lifecycle_click_speeds_up")

    do -- lifecycle_long_queue_autospeeds
      local w2, panel2, m, r = lifeBoard({ "FLIGHT_PATH" }, "play")
      local stub2, ns2 = w2.stub, w2.ns
      local uid = r.trinkets[1].uid
      for _ = 1, 20 do
        r.lifecycleEvents[#r.lifecycleEvents + 1] = { kind = "money", uid = uid, slot = 1, amount = 1 }
      end
      local finished = false
      ns2.UI.Lifecycle.Drain(r, function() finished = true end)
      check(ns2.UI.Lifecycle.IsBusy(), "the long queue is playing")
      local t = 0
      while not finished and t < 10 do
        stub2.advance(0.05)
        t = t + 0.05
      end
      check(finished and t <= 3.5, "a 20-event queue finishes in 3.5s: " .. t)
    end
    step("lifecycle_long_queue_autospeeds")

    do -- consumable_sell_locked_during_drain: a lifecycle queue in flight locks the consumable sale
      local w2, panel2, m, r = lifeBoard({ "FLIGHT_PATH" }, "play")
      local stub2, ns2 = w2.stub, w2.ns
      r.consumables = {}
      ns2.Consumables.add(r, { kind = "scroll", id = "CHANCE" })
      m.Render(r, true)
      stub2.advance(0.5)
      click(m.consumableRow.slots[1], "consumable slot")
      local pop
      for _, c in ipairs(m.content._children) do if c.use then pop = c end end
      check(pop and pop:IsVisible(), "the consumable popover opens")
      check(pop.sell:IsEnabled(), "sell is live while idle")
      local uid = r.trinkets[1].uid
      for _ = 1, 6 do
        r.lifecycleEvents[#r.lifecycleEvents + 1] = { kind = "money", uid = uid, slot = 1, amount = 1 }
      end
      local finished = false
      ns2.UI.Lifecycle.Drain(r, function() finished = true end)
      check(ns2.UI.Lifecycle.IsBusy(), "the queue is playing")
      ns2.UI.ConsumableRow.Refresh()
      check(not pop.sell:IsEnabled(), "sell is disabled while the queue plays")
      pop.sell._scripts.OnClick(pop.sell)
      eq(#r.consumables, 1, "a sale during the drain sells nothing")
      local t = 0
      while not finished and t < 10 do
        stub2.advance(0.05)
        t = t + 0.05
      end
      check(finished, "the queue finished")
      ns2.UI.ConsumableRow.Refresh()
      check(pop.sell:IsEnabled(), "sell is live again after the drain")
    end
    step("consumable_sell_locked_during_drain")

    do -- saved_payout_line
      local defs = { { id = "S_BONES", onLose = function(run)
        if run.score * 4 >= run.target then return { save = true, destroySelf = true, msg = "Saved!" } end
      end } }
      local w2, panel2, m, r = lifeBoard({ "S_BONES" }, "play", defs)
      local stub2, ns2 = w2.stub, w2.ns
      r.target, r.score, r.hand, r.pile = 300, 80, {}, {}
      ns2.Run.checkHand(r)
      eq(r.phase, "shop", "Bones saved the blind")
      m.Render(r, true)
      stub2.advance(1)
      local shop = panel2("offerCards")
      eq(shop.payout.reward.label:GetText(), "Saved by S_BONES", "the reward line names the saver")
      check(not shop.payout.reward.value:IsShown(), "and shows no reward amount")
      local sum = 0
      for key, row in pairs(shop.payout) do
        if key ~= "total" and row.label:IsShown() and row.value:IsShown() then
          sum = sum + tonumber(row.value:GetText():match("%d+"))
        end
      end
      eq(sum, tonumber(shop.payout.total.value:GetText():match("%d+")), "the other lines still add up to Total")
      local function col(fs) local c = fs._textColor; return c and (c[1] .. "," .. c[2] .. "," .. c[3]) end
      local g = ns2.UI.Theme.gold
      eq(col(shop.payout.total.label), g[1] .. "," .. g[2] .. "," .. g[3], "Total stays gold")
      eq(col(shop.payout.reward.label), g[1] .. "," .. g[2] .. "," .. g[3], "the saved line is gold")
      unstub(ns2, defs)
      -- A normal win keeps the ordinary line.
      local w3, panel3, m3, r3 = lifeBoard({}, "play")
      w3.ns.Run.winBlind(r3)
      m3.Render(r3, true)
      w3.stub.advance(1)
      eq(panel3("offerCards").payout.reward.label:GetText(), "Blind reward", "a normal win says Blind reward")
      local c3 = panel3("offerCards").payout.reward.label._textColor
      check(not c3 or (c3[1] == 1 and c3[2] == 1 and c3[3] == 1), "the reward line is normal again")
      local gt = w3.ns.UI.Theme.gold
      local ct = panel3("offerCards").payout.total.label._textColor
      check(ct and ct[1] == gt[1] and ct[2] == gt[2], "Total is still gold")
      check(panel3("offerCards").payout.reward.value:IsShown(), "with its amount")
    end
    step("saved_payout_line")

    do -- free_reroll_label
      local defs = { { id = "S_CHAOS", rule = "CHAOS", cost = 4 } }
      local w2, panel2, m, r = lifeBoard({ "S_CHAOS" }, "play", defs)
      local stub2, ns2 = w2.stub, w2.ns
      ns2.Run.winBlind(r)
      m.Render(r, true)
      stub2.advance(1)
      local shop = panel2("offerCards")
      eq(r.shop.freeRerolls, 1, "Chaos gives a free reroll")
      r.gold = 0
      m.Render(r, true)
      stub2.advance(0.5)
      eq(shop.reroll:GetText(), "Reroll (free)", "the button says free")
      check(shop.reroll:IsEnabled(), "a free reroll works with no gold")
      click(shop.reroll, "free reroll")
      stub2.advance(1)
      eq(r.shop.freeRerolls, 0, "the free reroll was used")
      eq(r.gold, 0, "and cost nothing")
      check(shop.reroll:GetText() ~= "Reroll (free)", "the label reverts")
      check(not shop.reroll:IsEnabled(), "a paid reroll needs gold")
      unstub(ns2, defs)
    end
    step("free_reroll_label")

    do -- negative_gold_display
      local defs = { { id = "S_CC", rule = "CREDIT_CARD", cost = 4 } }
      local w2, panel2, m, r = lifeBoard({ "S_CC" }, "play", defs)
      local stub2, ns2 = w2.stub, w2.ns
      ns2.Run.winBlind(r)
      m.Render(r, true)
      stub2.advance(1)
      local shop = panel2("offerCards")
      r.gold = 2
      r.shop.cards[1] = { type = "card", rank = 7, suit = "S", cost = 5, baseCost = 5 }
      r.shop.cards[2] = { type = "card", rank = 8, suit = "S", cost = 0, baseCost = 0 }
      m.Render(r, true)
      stub2.advance(0.5)
      check(shop.offerCards[1].buy:IsEnabled(), "Credit Card lets a 5g buy go through at 2g")
      check(shop.offerCards[2].buy:IsEnabled(), "a 0g offer is always affordable")
      click(shop.offerCards[1].buy, "overdraw")
      stub2.advance(1)
      eq(r.gold, -3, "the buy overdrew")
      eq(m.sidebar.gold:GetText(), "Gold: -3g", "negative gold shows as -Ng")
      local c = m.sidebar.gold._textColor
      check(c and c[1] > 0.9 and c[2] < 0.4 and c[3] < 0.4, "in red")
      r.gold = 7
      m.Render(r, true)
      eq(m.sidebar.gold:GetText(), "Gold: 7g", "positive gold keeps the g and is not red")
      local c2 = m.sidebar.gold._textColor
      check(c2 and not (c2[2] < 0.4), "and not red")
      -- Without the card the same buy is blocked.
      r.trinkets = {}
      r.gold = 2
      r.shop.cards[1] = { type = "card", rank = 9, suit = "S", cost = 5, baseCost = 5 }
      m.Render(r, true)
      stub2.advance(0.5)
      check(not shop.offerCards[1].buy:IsEnabled(), "no Credit Card, no overdraft")
      unstub(ns2, defs)
    end
    step("negative_gold_display")

    do -- discard_and_play_drain
      local defs = {
        { id = "S_DISC", onDiscard = function() return { msg = "Swish!", destroySelf = true } end },
        { id = "S_SAVE", onLose = function() return { save = true, destroySelf = true, msg = "Saved!" } end },
      }
      local function firstCard(m)
        local ws = {}
        for _, c in ipairs(m.handArea._children) do
          if c.card and not c.released and c:IsShown() then ws[#ws + 1] = c end
        end
        table.sort(ws, function(a, b) return a._points[1][4] < b._points[1][4] end)
        return ws[1]
      end
      -- A discard plays onDiscard's events, then the row ends correct.
      local w2, panel2, m, r = lifeBoard({ "S_DISC", "FLIGHT_PATH" }, "play", defs)
      local stub2, ns2 = w2.stub, w2.ns
      firstCard(m):Click()
      m.buttons.discard:Click()
      local seen, waited = false, 0
      while (ns2.UI.HandView.IsBusy()) and waited < 10 do
        stub2.advance(0.05)
        waited = waited + 0.05
        seen = seen or stub2.findText("Swish!") ~= nil
      end
      stub2.advance(0.5)
      check(seen, "onDiscard's message floated")
      check(not ns2.UI.HandView.IsBusy(), "the board is unlocked again")
      eq(#r.trinkets, 1, "the discarder melted away")
      eq(m.trinketRow.slots[1].def.id, "FLIGHT_PATH", "the row closed the gap")
      eq(#r.lifecycleEvents, 0, "events drained")
      -- A hand that would lose the blind is saved: the save plays after the tally, then the shop.
      local w3, panel3, m3, r3 = lifeBoard({ "S_SAVE" }, "play", defs)
      local stub3, ns3 = w3.stub, w3.ns
      r3.handsLeft = 1
      firstCard(m3):Click()
      m3.buttons.play:Click()
      local savedSeen, waited3 = false, 0
      while waited3 < 15 and not (r3.phase == "shop" and not ns3.UI.HandView.IsBusy() and not ns3.UI.Tally.IsBusy()) do
        stub3.advance(0.05)
        waited3 = waited3 + 0.05
        savedSeen = savedSeen or stub3.findText("Saved!") ~= nil
      end
      stub3.advance(1)
      eq(r3.phase, "shop", "the blind was saved")
      check(savedSeen, "the save message floated")
      check(not ns3.UI.Lifecycle.IsBusy(), "nothing is left playing")
      eq(panel3("offerCards").payout.reward.label:GetText(), "Saved by S_SAVE", "the payout names the saver")
      eq(#r3.trinkets, 0, "the saviour is spent")
      eq(m3.trinketRow.slots[1].def, nil, "and gone from the row")
    end
    step("discard_and_play_drain")
  end

  do -- 11e. A client without SetRotation / SetDesaturation still gets a working carousel
    local db = {}
    local w2, _, panel2, m = boot(db)
    local ns2, stub2 = w2.ns, w2.stub
    stub2.noRotation = true
    local DS2 = ns2.UI.DeckSelect
    w2.env.SlashCmdList.AZEROTHANTE()
    stub2.advance(1)
    local p2 = panel2("carousel")
    check(DS2.Card("ROGUE").art.SetRotation == nil, "the stub really lacks SetRotation")
    p2.nextBtn:Click()
    stub2.advance(0.4)
    eq(DS2.Selected(), "WARRIOR", "arrows work without rotation")
    p2.prevBtn:Click()
    stub2.advance(0.4)
    m.Hide()
    for i = 1, ns2.Profile.unlockThreshold("WARRIOR") do ns2.Profile.get(db).discovered["test:" .. i] = true end
    w2.env.SlashCmdList.AZEROTHANTE()
    stub2.advance(0.3)
    eq(DS2.Flourishing(), "WARRIOR", "the flourish plays without those APIs")
    stub2.advance(3)
    check(not DS2.Flourishing() and p2.play:IsEnabled(), "and completes")
    p2.play:Click()
    stub2.advance(1)
    eq(m.run and m.run.deckId, "WARRIOR", "a run still starts")
  end
  step("11e carousel and flourish survive missing rotation and desaturation APIs")

  -- 11f. Vouchers: the shop tile, owned icons, boss reroll, achievement toasts and the achievements view.
  local function voucherScenario(noRotation)
    local db = {}
    local w2, open2, panel2, m = boot(db)
    local ns2, stub2 = w2.ns, w2.stub
    if noRotation then stub2.noRotation = true end
    local Toast, AV = ns2.UI.Toast, ns2.UI.AchievementsView
    local function clickOn(f, what)
      check(f and f:IsVisible() and f:IsEnabled(), what .. " is live")
      f:Click()
      stub2.advance(0.1)
    end
    open2()

    -- The achievements view opens from the deck-select sidebar and lists all 16.
    check(m.sidebar.achievementsButton:IsVisible(), "Achievements button on deck select")
    eq(m.sidebar.achievementsButton:GetText(), "Achievements (0 / 16)", "button label")
    clickOn(m.sidebar.achievementsButton, "Achievements button")
    check(AV.IsShown(), "achievements view opens")
    local av = AV.Panel()
    eq(#av.rows, 16, "16 rows")
    for _, row in ipairs(av.rows) do
      check(row.name:GetText() and row.cond:GetText() and row.count:GetText(), "row has name, condition and progress")
      eq(row.unlocks:GetText(), "Unlocks: " .. ns2.Vouchers.def[row.id].name, "locked row names the voucher it unlocks")
    end
    check(av.rows[1].count:GetText():find("0 / 2500", 1, true), "progress shows have / need")
    for _, row in ipairs(av.rows) do
      if row.id == "GLOW_UP" or row.id == "MONEY_TREE" then
        check(row.count:GetText():find("best: ", 1, true), row.id .. " progress is labelled as a best")
      end
    end
    clickOn(av.close, "view Close")
    check(not AV.IsShown(), "view closes")

    -- Start a run and reach the shop.
    ns2.UI.DeckSelect.Select("ROGUE", true)
    panel2("carousel").play:Click()
    stub2.advance(1)
    local run = m.run
    local bp = panel2("preview")
    local boss = bp.panels[3]
    check(not boss.reroll:IsShown(), "no boss reroll without the vouchers")
    check(not AV.IsShown(), "view is closed during a run")
    clickOn(bp.start, "Play")
    stub2.advance(3)
    run.gold = 100
    ns2.Run.winBlind(run)
    run.gold = 100
    m.Render(run, true)
    stub2.advance(1)
    local shop = panel2("offerCards")
    local v = shop.voucher
    check(shop:IsVisible() and v.content:IsShown(), "shop shows the voucher")
    local offer = run.shopVoucher
    check(type(offer) == "table", "a voucher is on offer")
    local def = ns2.Vouchers.def[offer.id]
    eq(v.name:GetText(), def.name, "voucher name")
    eq(v.desc:GetText(), def.desc, "voucher effect")
    eq(v.price:GetText(), "10g", "full price")
    check(not v.orig:IsShown(), "no struck-through original at full price")

    -- A discount shows the discounted price with the original struck through.
    run.vouchers.CLEARANCE_SALE = true
    run.shopVoucher = { id = "OVERSTOCK", cost = 10 }
    offer, def = run.shopVoucher, ns2.Vouchers.def.OVERSTOCK
    m.Render(run, true)
    local discount = ns2.Vouchers.price(run, def.cost)
    eq(discount, 8, "25% off 10")
    eq(v.price:GetText(), "8g", "discounted price")
    eq(v.orig:GetText(), "10g", "original price")
    check(v.orig:IsShown() and v.strike:IsShown(), "original is struck through")
    local priced = 0
    for i = 1, 2 do
      local item = run.shop.cards[i]
      if item then
        priced = priced + 1
        eq(shop.offerCards[i].cost:GetText(), item.cost .. "g", "card price label is the discounted price")
      end
    end
    check(priced > 0, "a card was priced")

    -- A reroll keeps the voucher; the pack gate and gold gate give reasons.
    local before = run.shopVoucher
    run.gold = 5
    m.Render(run, true)
    check(not v.buy:IsEnabled() and v.buy.reason, "cannot afford: disabled with a reason")
    run.gold = 100
    m.Render(run, true)
    clickOn(shop.reroll, "Reroll")
    check(run.shopVoucher == before, "the voucher persists across a reroll")

    -- Buy it.
    local gold = run.gold
    clickOn(v.buy, "voucher Buy")
    eq(run.gold, gold - discount, "gold drops by the discounted price")
    check(run.vouchers[offer.id], "the run owns the voucher")
    check(run.shopVoucher == false, "the offer is gone")
    check(v.ghost:IsShown(), "the stamp animation plays")
    stub2.advance(2)
    check(not v.ghost:IsShown() and not v.content:IsShown(), "the coupon fades away")
    check(v.soldBox:IsShown() and v.soldBox:GetAlpha() == 1, "Sold out this stage shows")
    run.shopVoucher = nil
    m.Render(run, true)
    eq(v.soldBox.text:GetText(), "No voucher this stage", "nil offer says so")
    run.shopVoucher = false
    m.Render(run, true)
    eq(v.soldBox.text:GetText(), "Sold out this stage", "sold text")
    -- The sidebar row lists it, with a tooltip.
    local owned = {}
    for _, icon in ipairs(m.sidebar.voucherIcons) do
      if icon:IsShown() then owned[#owned + 1] = icon end
    end
    eq(#owned, 2, "owned icons")
    local icon
    for _, i in ipairs(owned) do if i.id == offer.id then icon = i end end
    check(icon, "an icon for the bought voucher")
    icon._scripts.OnEnter(icon)
    icon._scripts.OnLeave(icon)
    -- Buying outside the shop phase is refused at the UI.
    local fake = { id = "GRABBER" }
    run.shopVoucher = fake
    run.phase = "blind"
    local g2 = run.gold
    shop.voucher.buy:Click()
    check(run.gold == g2 and not run.vouchers.GRABBER, "no buy outside the shop phase")
    ns2.UI.Screens.Show("shop", run) -- refresh the open shop panel with a non-shop phase
    check(not shop.voucher.buy:IsEnabled(), "voucher Buy is disabled outside the shop phase")
    eq(shop.voucher.buy.reason, "Only in the shop", "the reason says so")
    run.phase = "shop"
    run.shopVoucher = false

    -- Overstock adds card slots that the shop actually shows.
    run.vouchers.OVERSTOCK = true
    ns2.Shop.open(run)
    m.Render(run, true)
    check(shop.offerCards[3]:IsShown(), "a third card column shows with Overstock")
    check(shop.offerCards[1]:GetWidth() < 90, "columns narrow to fit")

    -- The voucher changes after the boss.
    run.shopVoucher = nil
    run.blind = 3
    run.phase = "blind"
    ns2.Run.startBlind(run)
    ns2.Run.winBlind(run)
    m.Render(run, true)
    stub2.advance(1)
    check(type(run.shopVoucher) == "table" and run.shopVoucher ~= before, "a fresh voucher after the boss")
    check(v.content:IsShown(), "the tile shows the new offer")

    -- Boss reroll: once per stage with Director's Cut, never at stage 8.
    ns2.Run.nextBlind(run)
    m.Render(run, true)
    stub2.advance(1)
    check(panel2("preview") and panel2("preview"):IsVisible(), "blind screen")
    bp = panel2("preview")
    boss = bp.panels[3]
    check(not boss.reroll:IsShown(), "still no boss reroll")
    -- The sidebar shows the hands and discards the blind will really start with.
    run.vouchers.GRABBER, run.vouchers.WASTEFUL = true, true
    m.Render(run, true)
    eq(m.sidebar.hands:GetText(), "Hands: 5", "sidebar hands include Grabber")
    eq(m.sidebar.discards:GetText(), "Discards: 5", "sidebar discards include Wasteful")
    run.vouchers.GRABBER, run.vouchers.WASTEFUL = nil, nil
    m.Render(run, true)
    eq(m.sidebar.hands:GetText(), "Hands: 4", "and drop back without them")
    run.vouchers.DIRECTORS_CUT = true
    run.gold = 50
    m.Render(run, true)
    check(boss.reroll:IsShown() and boss.reroll:IsEnabled(), "Reroll Boss shows and is live")
    eq(boss.reroll:GetText(), "Reroll Boss (10g)", "label")
    local oldBoss = run.bosses[run.stage]
    clickOn(boss.reroll, "Reroll Boss")
    stub2.advance(1)
    check(run.bosses[run.stage] ~= oldBoss, "the boss changed")
    eq(run.gold, 40, "boss reroll costs 10g")
    eq(boss.name:GetText(), ns2.Bosses.def[run.bosses[run.stage]].name, "the chip shows the new boss")
    eq(boss.rule:GetText(), ns2.Bosses.def[run.bosses[run.stage]].desc, "and its rule")
    check(not boss.reroll:IsEnabled(), "once per stage")
    eq(boss.reroll.reason, select(2, ns2.Run.canRerollBoss(run)), "reason comes from Run.canRerollBoss")
    run.stage = 8
    m.Render(run, true)
    check(not boss.reroll:IsShown(), "hidden at stage 8")
    run.stage = 2
    m.Render(run, true)

    -- Toasts: crossing a threshold toasts once, several queue, input is not blocked.
    ns2.Profile.onEvent("reroll", 100, run)
    ns2.Profile.onEvent("cardsPlayed", 2500, run)
    check(Toast.Current() == "REROLL_GLUT", "first toast shows")
    eq(Toast.Pending(), 1, "second toast queued")
    local tf = Toast.Frame()
    check(tf:IsShown() and not tf:IsMouseEnabled(), "toast never takes the mouse")
    check(tf.title:GetText():find("Achievement unlocked: " .. ns2.Vouchers.def.REROLL_GLUT.name, 1, true), "toast title")
    check(tf.sub:GetText():find("Unlocks ", 1, true), "toast subtitle")
    check(ns2.Profile.get(db).seenAchievements.REROLL_GLUT, "shown toast is marked seen")
    stub2.advance(4.2)
    eq(Toast.Current(), "NACHO_TONG", "the queue moves on")
    stub2.advance(4.2)
    check(Toast.Current() == nil and not tf:IsShown(), "toasts finish and hide")
    ns2.Profile.onEvent("reroll", 1, run)
    check(Toast.Current() == nil, "no repeat toast")
    clickOn(m.sidebar.deckButton, "Deck button is not blocked by toasts")
    ns2.UI.DeckView.Hide()
    -- The view shows the unlocked ones in gold.
    AV.Toggle()
    for _, row in ipairs(AV.Panel().rows) do
      if row.id == "REROLL_GLUT" then
        check(row.done and row.count:GetText() == "100 / 100", "unlocked row shows full progress")
      end
    end
    check(AV.Panel().title:GetText():find("(2 / 16)", 1, true), "view counts 2 unlocked")
    AV.Hide()
    -- Unseen achievements toast when the window opens again.
    ns2.Profile.get(db).achievements.PALETTE = true
    m.Hide()
    m.Show()
    check(Toast.Current() == "PALETTE", "unseen achievement toasts on open")
    stub2.advance(10)
    -- Earning the achievement lets the tier-two voucher into the pool.
    run.vouchers = { OVERSTOCK = true }
    ns2.Profile.get(db).achievements.OVERSTOCK_PLUS = true
    local seenPlus = false
    for seed = 1, 60 do
      run.rng = ns2.RNG.new(seed)
      local o = ns2.Shop.rollVoucher(run)
      if o and o.id == "OVERSTOCK_PLUS" then seenPlus = true end
    end
    check(seenPlus, "the achievement unlocks the upgrade in the shop")
  end
  voucherScenario(false)
  step("11f vouchers: shop tile, owned row, boss reroll, toasts, achievements view")
  voucherScenario(true)
  step("11g the voucher UI survives a client without rotation APIs")

  -- 12. The window theme: set-in panels, raised tiles, outline-free chips and mult, themed buttons.
  do
    local Theme = ns.UI.Theme
    local sb = Main.sidebar
    -- chips and mult are filled tiles with no outline
    check(sb.chipsBox.themeTile == "chips" and sb.multBox.themeTile == "mult", "chips and mult are Theme tiles")
    for _, box in ipairs({ sb.chipsBox, sb.multBox }) do
      check(box.themeEdges == nil and box.selectedEdges == nil and not box.themeSelected, "a tile has no edge textures")
      check(box._template == nil, "a tile uses no stock template")
      local n = 0
      for _, c in ipairs(box._children) do
        if c._kind == "Texture" then n = n + 1 end
      end
      eq(n, 3, "a tile is a base, a gradient and a bottom lip only")
    end
    check(stub.unknown.SetBackdrop == nil and stub.unknown.SetBackdropBorderColor == nil,
      "no backdrop borders anywhere in the window")
    -- inset (set-in) panels
    check(sb.themeInset and #sb.themeEdges == 4, "the sidebar is set in")
    check(Main.stage and Main.stage.themeInset, "the table behind the hand is set in")
    for _, field in ipairs({ "carousel", "stageText", "payout", "head", "deckTitle", "packChoices" }) do
      local p = panel(field)
      check(p and p.themeInset, "panel with " .. field .. " is set in")
      check(p.insetFillColor[4] == 1, field .. " panel fill is opaque")
    end
    -- raised tiles
    for i = 1, 3 do
      local body = panel("stageText").panels[i].body
      check(body.themeRaised, "blind panel " .. i .. " is raised")
    end
    check(panel("payout").offerCards[1].themeRaised and panel("payout").packOffers[2].themeRaised, "shop items are raised")
    check(panel("carousel").plate.themeRaised, "the deck details tile is raised")
    check(panel("use").themeRaised, "the consumable popover is raised")
    -- selected: outline and glow only while on
    local cur = panel("stageText").panels[1].body
    Theme.Selected(cur, true)
    check(cur.themeSelected and #cur.selectedEdges == 4, "Theme.Selected adds the gold outline")
    Theme.Selected(cur, false)
    check(not cur.themeSelected, "and removes it")
    -- every Button in the window is themed; none uses a stock template
    local function inWindow(f)
      while f do
        if f == Main.frame then return true end
        f = f._parent
      end
      return false
    end
    local buttons = 0
    for _, f in ipairs(stub.frames) do
      if f._kind == "Button" and inWindow(f) then
        check(f._template ~= "UIPanelButtonTemplate" and f._template ~= "UIPanelCloseButton",
          "a Button uses a stock red template")
        if f ~= Main.grip then
          local hit = f._text == nil and f.themeButton == nil -- card and slot hit areas carry no text
          if not hit then
            check(f.themeButton, "Button " .. tostring(f._text) .. " uses the theme")
            check(f.themeEdges and #f.themeEdges == 4 and f.label, "Button " .. tostring(f._text) .. " has the themed parts")
            buttons = buttons + 1
          end
        end
      end
    end
    check(buttons >= 15, "the themed buttons were found (" .. buttons .. ")")
    for _, b in ipairs({ Main.buttons.play, Main.buttons.discard, Main.buttons.sortRank, Main.buttons.sortSuit,
      sb.deckButton, Main.close }) do
      check(b.themeButton, "main-frame button is themed")
    end
    eq(Main.buttons.play.themeButton, "primary", "Play is the primary variant")
    eq(panel("stageText").abandon.themeButton, "danger", "Abandon Run is the danger variant")
    -- disabled dims, hover brightens (state tracking)
    local b = Main.buttons.discard
    local was = b:IsEnabled()
    b:Disable()
    eq(b.themeState, "disabled", "a disabled button dims")
    b:Enable()
    eq(b.themeState, "normal", "and returns when enabled")
    b:SetEnabled(was)
    -- a hovered, then disabled, then re-enabled button: hover is recomputed from the cursor
    b:Enable()
    b._scripts.OnEnter(b)
    b.hover = true
    b:Disable()
    check(not b.pressed, "disabling clears pressed")
    b:Enable()
    eq(b.themeState, "normal", "re-enabled with the cursor gone: not stuck on hover")
    stub.over[b] = true
    b:Disable()
    b:Enable()
    eq(b.themeState, "hover", "re-enabled under the cursor: hover")
    stub.over[b] = nil
    b:Disable()
    b:Enable()
    b:SetEnabled(was)
    -- the selected deck card carries the gold outline
    local DS = ns.UI.DeckSelect
    local center = DS.Card(DS.Selected())
    check(center.themeSelected, "the carousel's centre card is selected")
  end
  step("12 window theme: inset, raised, outline-free tiles, themed buttons")

  -- 13 pixel-perfect borders: every themed edge is at least one physical pixel at any scale
  do
    local Theme = ns.UI.Theme
    local frame = Main.frame
    local DW, DH = Theme.width, Theme.height
    local function registered()
      local n = 0
      for _ in pairs(Theme.edgeRegistry) do n = n + 1 end
      return n
    end
    local function assertEdges(label)
      local n, worst = 0, 0
      for t, info in pairs(Theme.edgeRegistry) do
        local px = Theme.Pixel(t:GetParent() or t)
        local got = info.axis == "w" and t:GetWidth() or t:GetHeight()
        check(got >= px - 1e-9, label .. ": edge thinner than one pixel (" .. got .. " < " .. px .. ")")
        check(got >= info.thickness - 1e-9, label .. ": edge thinner than its design thickness")
        check(t._snap == false and t._bias == 0, label .. ": edge snapping not disabled")
        n = n + 1
        if px > worst then worst = px end
      end
      check(n > 40, label .. ": expected many registered edges, got " .. n)
      return worst
    end
    check(registered() > 40, "theme edges are registered")
    -- 1: UI scale 0.64 on a 1440p screen, default window
    stub.uiScale, stub.physical = 0.64, { 2560, 1440 }
    frame:SetSize(DW + 1, DH)
    frame:SetSize(DW, DH)
    assertEdges("scale 0.64 @1440p")
    -- 2: the same with the window shrunk so the canvas scale is 0.64 too: 1 unit is under 1 pixel
    frame:SetSize(DW * 0.64, DH * 0.64)
    local worst = assertEdges("shrunk window")
    check(worst > 1.2, "a pixel is wider than a design unit here (" .. worst .. ")")
    -- 3: a UI scale change re-applies every thickness (no resize involved)
    local before = {}
    for t in pairs(Theme.edgeRegistry) do before[t] = t:GetHeight() + t:GetWidth() end
    stub.uiScale = 0.45
    stub.fire("UI_SCALE_CHANGED")
    local worst2 = assertEdges("after UI_SCALE_CHANGED")
    check(worst2 > worst, "thickness grew with the smaller scale")
    stub.physical = { 1920, 1080 }
    stub.fire("DISPLAY_SIZE_CHANGED")
    assertEdges("after DISPLAY_SIZE_CHANGED")
    -- 4: without the Retail APIs the fallbacks still give a sane pixel
    local gps = env.GetPhysicalScreenSize
    rawset(env, "GetPhysicalScreenSize", nil)
    check(math.abs(Theme.Pixel(frame) - 768 / 1080 / frame:GetEffectiveScale()) < 1e-9, "fallback to GetScreenHeight")
    local gsh = env.GetScreenHeight
    rawset(env, "GetScreenHeight", nil)
    eq(Theme.Pixel(frame), 1, "no screen APIs: one unit")
    rawset(env, "GetPhysicalScreenSize", gps)
    rawset(env, "GetScreenHeight", gsh)
    -- restore the default scale
    stub.uiScale = 1
    frame:SetSize(DW, DH)
    stub.fire("UI_SCALE_CHANGED")
    -- every themed button's label fits, including the armed "Click again to abandon" and "Skip (N left)"
    for _, f in ipairs(stub.frames) do
      if f.themeButton and f:GetText() == "Abandon Run" and f._scripts.OnClick then
        f._scripts.OnClick(f) -- arm it
      elseif f.themeButton and f:GetText() == "Skip" then
        f:SetText("Skip (3 left)")
      end
    end
    local checked = 0
    for _, f in ipairs(stub.frames) do
      if f.themeButton and f.label and f:GetText() and f:GetText() ~= "" then
        checked = checked + 1
        local need = f.label:GetStringWidth()
        check(need <= f:GetWidth(), ("label '%s' (%.0f) overflows its %.0fpx button"):format(f:GetText(), need, f:GetWidth()))
      end
    end
    check(checked > 10, "button labels were checked: " .. checked)
  end
  step("13 pixel-perfect edges and buttons that fit their labels")

  -- Globals created by the addon files.
  for _, world in ipairs({ w1st, w, unpack(extraWorlds) }) do
    for name in pairs(world.newGlobals) do
      check(ALLOWED_GLOBALS[name], "addon leaked global: " .. name)
    end
  end
  step("globals clean")
end

local ok, err = xpcall(function()
  local w = newWorld(nil)
  run(w)
end, debug.traceback)
if not ok then
  print("SMOKE FAILED")
  print(err)
  os.exit(1)
end
print("smoke ok")
