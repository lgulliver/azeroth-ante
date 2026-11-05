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
  selectCard(2)
  click(Main.buttons.discard, "Discard")
  stub.advance(3)
  eq(Main.run.discardsLeft, discardsBefore - 1, "discard used")
  eq(#Main.run.hand, 8, "hand refilled after discard")
  check(not HandView.IsBusy(), "busy after discard")
  step("2b sort and discard")

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
  Main.Render(run)
  stub.advance(1)
  local shop = panel("offerCards")
  local gold = run.gold
  click(shop.offerCards[1].buy, "buy offer 1")
  check(run.gold < gold, "buying offer 1 spends gold")
  eq(#run.trinkets, 1, "trinket owned")
  gold = run.gold
  local tomeHand = run.shop.tome and run.shop.tome.handId
  click(shop.tomeCard.buy, "buy tome")
  check(run.gold < gold, "buying the tome spends gold")
  check(run.handLevels[tomeHand] == 2, "tome levelled the hand")
  gold = run.gold
  click(shop.reroll, "Reroll")
  check(run.gold < gold, "reroll spends gold")
  gold = run.gold
  stub.advance(1)
  local slot1 = Main.trinketRow.slots[1]
  check(slot1.sell:IsVisible(), "sell button visible in the shop")
  click(slot1.sell, "sell trinket")
  check(run.gold > gold, "selling refunds gold")
  eq(#run.trinkets, 0, "trinket sold")
  click(shop.next, "Next Blind")
  stub.advance(1)
  eq(run.phase, "blind", "phase after Next Blind")
  check(visible("preview"), "blind screen visible after shop")
  step("5 shop buy, tome, reroll, sell, next blind")

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
