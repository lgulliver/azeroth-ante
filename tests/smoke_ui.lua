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

  -- 1. Open the window.
  open()
  check(Main.frame:IsShown(), "window not shown after /ante")
  check(visible("tiles"), "newrun screen not visible")
  step("1 slash opens window on the newrun screen")

  -- 2. Deck tile, then Start Blind.
  local newrun = panel("tiles")
  click(newrun.tiles[1], "deck tile 1")
  stub.advance(1)
  eq(Main.run.phase, "blind", "phase after deck tile")
  check(visible("preview"), "blind screen not visible")
  click(panel("preview").start, "Start Blind")
  stub.advance(3)
  eq(Main.run.phase, "play", "phase after Start Blind")
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
  click(popover().use, "popover Use (2 cards selected)")
  check(HandView.IsBusy(), "input locks during the use animation")
  check(not Main.buttons.play:IsEnabled(), "Play disabled while a consumable resolves")
  stub.advance(3)
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
  click(crow.slots[1], "relic slot")
  click(popover().use, "Use relic of the Court")
  stub.advance(3)
  eq(#runC.hand, handBefore + 2, "Court destroys 1 and adds 3 cards")
  eq(#handWidgets(), handBefore + 2, "hand re-lays out with the added cards")
  check(not HandView.IsBusy(), "unlocked after destroy and add")
  giveSlot(runC, "scroll", "STARS")
  click(crow.slots[1], "stars slot")
  click(popover().use, "Use Scroll of the Stars")
  stub.advance(3)
  eq(#runC.consumables, 2, "Stars created two Tomes")
  check(crow.slots[1].holder:GetAlpha() == 1 and crow.slots[2].holder:GetAlpha() == 1, "created consumables end fully visible")
  eq(crow.slots[2].art:GetTexture(), MEDIA .. "Consumable_Tome", "tome slot frame texture")
  runC.consumables = {}
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

  -- 4. Force a win.
  Main.run.target = 1
  selectCard(1)
  playSelected()
  stub.advance(10)
  eq(Main.run.phase, "shop", "phase after winning")
  check(visible("offerCards"), "shop screen not visible")
  step("4 winning hand opens the shop")

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
  check(#Main.trinketRow.slots == 5, "five trinket slots without a Negative trinket")
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
  click(shop.next, "Next Blind")
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
  stub.advance(2)
  eq(run.gold, 20, "Greed doubled the gold")
  eq(#run.consumables, 0, "Greed consumed")
  eq(Main.sidebar.gold:GetText(), "Gold: 20", "sidebar shows the doubled gold")
  ns.Consumables.add(run, { kind = "scroll", id = "FURY" })
  Main.Render(run)
  click(brow.slots[1], "slot for a targeted scroll")
  check(not bpop.use:IsEnabled() and bpop.use.reason ~= nil, "targeted consumable cannot be used without a hand")
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
  check(visible("tiles"), "newrun screen after New Run")
  check(env.AzerothAnteDB.run == nil, "save cleared by New Run")
  step("8 lose path and New Run")

  -- 9. Hide mid-tally.
  click(panel("tiles").tiles[2], "deck tile 2")
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
  check(visible("tiles"), "abandon returns to the new-run screen")
  step("9c abandon run")

  -- Globals created by the addon files.
  for _, world in ipairs({ w1st, w }) do
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
