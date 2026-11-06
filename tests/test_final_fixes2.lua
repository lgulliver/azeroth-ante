local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function texts(run)
  local out = {}
  for _, e in ipairs(run.lifecycleEvents or {}) do
    if e.kind == "trinketMsg" then out[#out + 1] = e.text end
  end
  return out
end
local function hasText(run, text)
  for _, t in ipairs(texts(run)) do if t == text then return true end end
  return false
end
local function discard(run, cards)
  run.hand = cards
  for i = 1, 20 do run.pile[#run.pile + 1] = H.card(2) end
  local idx = {}
  for i = 1, #cards do idx[i] = i end
  T.ok(ns.Run.discard(run, idx))
end
local function boss(run, id) run.blind, run.bosses[run.stage] = 3, id end

-- 1. Blind-select hooks fire before the hand is drawn.
H.test("blind select destroys a hand-size trinket before the draw", function()
  local run = H.run { trinkets = { "OLD_GODS", "FERTILE_SEED" } }
  ns.Run.startBlind(run)
  T.eq(#run.trinkets, 1)
  T.eq(#run.hand, ns.Deck.handSize(run))
  T.eq(#run.hand, 8)
end)
H.test("Soul Harvest eating Reagent Bag leaves a normal hand", function()
  local run = H.run { trinkets = { "SOUL_HARVEST", "REAGENT_BAG" } }
  ns.Run.startBlind(run)
  T.eq(#run.trinkets, 1)
  T.eq(#run.hand, 8)
end)
H.test("blind select hooks still see hands and discards set", function()
  local run = H.run { trinkets = { "SI7_AGENT" } }
  ns.Run.startBlind(run)
  T.eq(run.discardsLeft, 0)
  T.eq(run.handsLeft, ns.Run.blindHands(run) + 3)
end)
H.test("blind select still draws up to a hand-size trinket", function()
  local run = H.run { trinkets = { "REAGENT_BAG" } }
  ns.Run.startBlind(run)
  T.eq(#run.hand, 9)
end)

-- 2. One save, one Soulstone.
H.test("two Soulstones: one save consumes exactly one", function()
  local run = H.run { trinkets = { "SILAS", "SOULSTONE", "SOULSTONE" } }
  run.score, run.target = 75, 300
  ns.Run.checkHand(run)
  T.eq(run.phase, "shop")
  T.eq(#run.trinkets, 2)
  T.eq(run.lastPayout.savedId, "SOULSTONE")
end)

-- 3. Discard trinkets skip boss-debuffed cards.
H.test("Faceless One ignores face cards the boss debuffs", function()
  local run = H.run { trinkets = { "FACELESS_ONE" }, gold = 0 }
  boss(run, "HOGGER")
  discard(run, { H.card(11), H.card(12), H.card(13) })
  T.eq(run.gold, 0)
  local plain = H.run { trinkets = { "FACELESS_ONE" }, gold = 0 }
  discard(plain, { H.card(11), H.card(12), H.card(13) })
  T.eq(plain.gold, 5)
end)
H.test("Postmaster ignores debuffed cards", function()
  local run = H.run { trinkets = { "POSTMASTER" }, gold = 0 }
  run.trinkets[1].state.rank = 13
  boss(run, "HOGGER")
  discard(run, { H.card(13) })
  T.eq(run.gold, 0)
end)
H.test("Stormwind Keep ignores debuffed suit cards", function()
  local run = H.run { trinkets = { "STORMWIND_KEEP" } }
  run.trinkets[1].state.suit = "S"
  boss(run, "VANCLEEF")
  discard(run, { H.card(2, "S"), H.card(3, "S") })
  T.eq(run.trinkets[1].state.chips, 0)
end)
H.test("Mount Up ignores debuffed Jacks", function()
  local run = H.run { trinkets = { "MOUNT_UP" } }
  boss(run, "HOGGER")
  discard(run, { H.card(11) })
  T.eq(run.trinkets[1].state.x, 1)
  local plain = H.run { trinkets = { "MOUNT_UP" } }
  discard(plain, { H.card(11) })
  T.eq(plain.trinkets[1].state.x, 1.5)
end)

-- 4. Invisibility Potion message lands on a live slot.
H.test("Invisibility Potion Duplicated! attaches to the copy", function()
  local run = H.run { trinkets = { "INVIS_POTION", "ARCANE_INTELLECT" } }
  run.trinkets[1].state.rounds = 2
  T.ok(ns.Run.sellTrinket(run, 1))
  T.eq(#run.trinkets, 2)
  local copy = run.trinkets[2]
  local found
  for _, e in ipairs(run.lifecycleEvents) do
    if e.kind == "trinketMsg" and e.text == "Duplicated!" then found = e end
  end
  T.ok(found, "message emitted")
  T.eq(found.uid, copy.uid)
  T.eq(found.slot, 2)
end)

-- 5. Scaling changes show a message.
H.test("Cooking Fire shows Upgrade! on a sale and Reset on boss defeat", function()
  local run = H.run { trinkets = { "COOKING_FIRE", "ARCANE_INTELLECT" } }
  T.ok(ns.Run.sellTrinket(run, 2))
  T.ok(hasText(run, "Upgrade!"))
  run.lifecycleEvents = {}
  run.blind = 3
  ns.Run.winBlind(run)
  T.ok(hasText(run, "Reset"))
  local fresh = H.run { trinkets = { "COOKING_FIRE" } }
  fresh.blind = 3
  ns.Run.winBlind(fresh)
  T.ok(not hasText(fresh, "Reset"), "no Reset when nothing to reset")
end)
H.test("Flash Heal shows a message per reroll", function()
  local run = H.run { trinkets = { "FLASH_HEAL" }, gold = 20 }
  ns.Shop.open(run)
  T.ok(ns.Shop.reroll(run))
  T.ok(hasText(run, "Upgrade!"))
end)
H.test("Mount Up and Stormwind Keep show Upgrade! and Mount Up Reset", function()
  local run = H.run { trinkets = { "MOUNT_UP", "STORMWIND_KEEP" } }
  run.trinkets[2].state.suit = "S"
  discard(run, { H.card(11, "S") })
  local n = 0
  for _, t in ipairs(texts(run)) do if t == "Upgrade!" then n = n + 1 end end
  T.eq(n, 2)
  run.lifecycleEvents = {}
  ns.Run.winBlind(run)
  T.ok(hasText(run, "Reset"))
  local quiet = H.run { trinkets = { "MOUNT_UP", "STORMWIND_KEEP" } }
  quiet.trinkets[2].state.suit = "S"
  discard(quiet, { H.card(5, "H") })
  T.eq(#texts(quiet), 0)
  ns.Run.winBlind(quiet)
  T.ok(not hasText(quiet, "Reset"))
end)
H.test("Goblin Rocket shows Upgrade! on a boss", function()
  local run = H.run { trinkets = { "GOBLIN_ROCKET" } }
  run.blind = 3
  ns.Run.winBlind(run)
  T.ok(hasText(run, "Upgrade!"))
end)

-- 6. Consumable sell value is at least 1.
H.test("consumable sell value has a floor of 1", function()
  T.eq(ns.Consumables.sellValue({ kind = "scroll", paid = 0 }), 1)
  T.eq(ns.Consumables.sellValue({ kind = "scroll", paid = 1, sellBonus = 2 }), 3)
end)

-- 7. Stormwind Keep picks the suit of a deck card, never the current one.
H.test("Stormwind Keep suit comes from the deck, excluding the current suit", function()
  local run = H.run()
  run.deck = { H.card(2, "S", "STONE"), H.card(3, "H"), H.card(4, "S"), H.card(5, "H", "STONE") }
  run.trinkets = { ns.Trinkets.create(run, "STORMWIND_KEEP") }
  local inst = run.trinkets[1]
  T.ok(inst.state.suit == "H" or inst.state.suit == "S")
  for _ = 1, 20 do
    local before = inst.state.suit
    ns.TrinketEngine.fire(run, "roundUpdate")
    T.ok(inst.state.suit ~= before, "suit changes")
  end
  run.deck = { H.card(2, "C"), H.card(3, "C") }
  inst.state.suit = "C"
  ns.TrinketEngine.fire(run, "roundUpdate")
  T.eq(inst.state.suit, "C", "only one suit in the deck keeps it")
end)

-- 8. Trading Post is not Blueprint-compatible.
H.test("Trading Post is not copyable", function()
  T.eq(ns.Trinkets.def.TRADING_POST.copyable, false)
  local run = H.run { trinkets = { "SCHEMATIC", "TRADING_POST" }, gold = 0 }
  discard(run, { H.card(5) })
  T.eq(run.gold, 3)
end)

-- 10. A scoring-phase destroy settles mods.
H.test("a scoring-phase trinket destroy settles hands", function()
  H.stub { id = "T_FLEETING", hands = 1, after = function(_, _, isCopy)
    if not isCopy then return { destroySelf = true, msg = "Gone!" } end
  end }
  local run = H.run { trinkets = { "T_FLEETING" } }
  run.handsLeft, run.discardsLeft, run.target = 4, 3, 1e9
  run.hand = { H.card(2), H.card(3) }
  for _ = 1, 20 do run.pile[#run.pile + 1] = H.card(4) end
  T.ok(ns.Run.play(run, { 1 }))
  T.eq(#run.trinkets, 0)
  T.eq(run.handsLeft, 2, "the destroyed trinket's extra hand is gone")
end)
