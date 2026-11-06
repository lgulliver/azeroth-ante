local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

-- First id of a kind that can be used with no selection in `run`.
local function untargeted(run, kind)
  local list = kind == "scroll" and ns.Scrolls.order or ns.Relics.order
  local defs = kind == "scroll" and ns.Scrolls.def or ns.Relics.def
  for _, id in ipairs(list) do
    if not defs[id].select then
      run.consumables = { { kind = kind, id = id } }
      if ns.Consumables.canUse(run, 1) then return id end
    end
  end
end

H.test("usage_counters", function()
  local run = H.run()
  ns.Run.startBlind(run)
  T.eq(run.usage, { scroll = 0, tome = 0, relic = 0, tomeIds = {} })
  run.consumables = { { kind = "tome", id = "PAIR" } }
  ns.Consumables.use(run, 1)
  T.eq(run.usage.tome, 1)
  T.eq(run.usage.tomeIds, { PAIR = true })
  T.ok(untargeted(run, "scroll"), "an untargeted scroll")
  ns.Consumables.use(run, 1)
  T.eq(run.usage.scroll, 1)
  T.ok(untargeted(run, "relic"), "an untargeted relic")
  ns.Consumables.use(run, 1)
  T.eq(run.usage.relic, 1)
  T.eq(run.usage.tome, 1)
end)

H.test("consumable_used_hook_sees_usage", function()
  local seen
  H.stub({ id = "S_USE", onConsumableUsed = function(run, _, item, isCopy)
    seen = { tome = run.usage.tome, id = item.id, kind = item.kind, copy = isCopy }
  end })
  local run = H.run({ trinkets = { "S_USE" } })
  run.consumables = { { kind = "tome", id = "PAIR" } }
  ns.Consumables.use(run, 1)
  T.eq(seen, { tome = 1, id = "PAIR", kind = "tome", copy = false })
end)

H.test("card_log_flush_once_per_action", function()
  local calls = {}
  H.stub({ id = "S_ADD", onCardsAdded = function(_, _, cards) calls[#calls + 1] = #cards end })
  local run = H.run({ trinkets = { "S_ADD" } })
  run.phase = "shop"
  run.shop = { cards = {}, packs = {}, openPack = {
    type = "STANDARD", size = "normal", picksLeft = 1, paid = 4,
    choices = { { rank = 5, suit = "H" } } } }
  ns.Packs.pick(run, 1)
  T.eq(calls, { 1 })
  T.eq(run.cardLog, { added = {}, destroyed = {} })
  T.eq(#run.deck, 53)
end)

H.test("cards_destroyed_by_glass_fire_hook", function()
  local got
  H.stub({ id = "S_GONE", onCardsDestroyed = function(_, _, cards, isCopy) got = { cards = cards, copy = isCopy } end })
  H.stub({ id = "S_KILLER", onDiscard = function(_, _, cards) return { destroyCard = cards[1].id } end })
  local run = H.run({ trinkets = { "S_KILLER", "S_GONE" } })
  ns.Run.startBlind(run)
  local id = run.hand[1].id
  local rank = run.hand[1].rank
  ns.Run.discard(run, { 1 })
  T.eq(#run.deck, 51)
  T.eq(#got.cards, 1)
  T.eq(got.cards[1].id, id)
  T.eq(got.cards[1].rank, rank)
  T.eq(got.copy, false)
  T.eq(run.cardLog, { added = {}, destroyed = {} })
end)

H.test("pack_opened_hook", function()
  local seen
  H.stub({ id = "S_PACK", onPackOpened = function(_, _, pack, isCopy) seen = { type = pack.type, copy = isCopy } end })
  local run = H.run({ trinkets = { "S_PACK" }, gold = 20 })
  run.phase = "shop"
  run.shop = { cards = {}, packs = { { type = "BUFFOON", size = "normal", cost = 4, baseCost = 4 } } }
  T.ok(ns.Packs.open(run, 1))
  T.eq(seen, { type = "BUFFOON", copy = false })
end)

H.test("first_draw_after_draw", function()
  local handSeen, runs = nil, 0
  H.stub({ id = "S_FIRST", onFirstDraw = function(run) runs = runs + 1; handSeen = #run.hand end })
  local run = H.run({ trinkets = { "S_FIRST" } })
  ns.Run.startBlind(run)
  T.eq(runs, 1)
  T.eq(handSeen, ns.Deck.handSize(run))
end)

H.test("create_consumable_room_lifecycle", function()
  H.stub({ id = "S_MAKE", onBlindSelect = function() return { createConsumable = { kind = "tome" } } end })
  local run = H.run({ trinkets = { "S_MAKE" } })
  run.maxConsumables = 2
  run.consumables = { { kind = "scroll", id = "FORTUNE" } }
  ns.Run.startBlind(run)
  T.eq(#run.consumables, 2)
  T.eq(run.consumables[2].kind, "tome")
  ns.Run.startBlind(run)
  T.eq(#run.consumables, 2, "full: nothing created")
end)

H.test("create_card_lifecycle_pile_and_hand", function()
  H.stub({ id = "S_CARD", onBlindSelect = function()
    return { createCard = { card = { rank = 9, suit = "H", enh = "STONE" }, toHand = false } }
  end })
  local run = H.run({ trinkets = { "S_CARD" } })
  ns.Run.startBlind(run)
  T.eq(#run.deck, 53)
  local found = 0
  for _, list in ipairs({ run.pile, run.hand }) do
    for _, c in ipairs(list) do if c.enh == "STONE" and c.rank == 9 then found = found + 1 end end
  end
  T.eq(found, 1, "the new card is in the pile or drawn")
  T.eq(#run.pile + #run.hand, 53)

  H.stub({ id = "S_HAND", onDiscard = function()
    return { createCard = { card = { rank = 3, suit = "C" }, toHand = true } }
  end })
  run = H.run({ trinkets = { "S_HAND" } })
  ns.Run.startBlind(run)
  ns.Run.discard(run, { 1 })
  T.eq(#run.deck, 53)
  local inHand = false
  for _, c in ipairs(run.hand) do if c.rank == 3 and c.suit == "C" and c.id > 52 then inHand = true end end
  T.ok(inHand, "created into the hand")
end)

H.test("disable_boss_restores", function()
  H.stub({ id = "S_OFF", onBlindSelect = function() return { disableBoss = true } end })
  local run = H.run({ trinkets = { "S_OFF" } })
  run.blind, run.bosses[1] = 3, "MUTANUS"
  ns.Run.startBlind(run)
  T.eq(run.bossDisabled, true)
  T.eq(run.discardsLeft, ns.Decks.def.ROGUE.discards, "Mutanus's 0 is topped up to the deck's")
  T.eq(run.target, ns.Run.target(1, 3, "MUTANUS"))
  T.eq(ns.Run.bossId(run), "MUTANUS")
  T.eq(ns.Run.activeBoss(run), nil)
  T.eq(run.lifecycleEvents[#run.lifecycleEvents].kind, "bossDisabled")
  T.eq(ns.Run.blindDiscards(run), ns.Decks.def.ROGUE.discards)
  T.eq(ns.Run.canPlay(run, { 1 }), true)
end)

H.test("disable_boss_lifts_debuff", function()
  local run = H.run()
  run.blind, run.bosses[1] = 3, "HOGGER"
  ns.Run.startBlind(run)
  local king = H.card(13, "S")
  T.eq(H.score(run, { king }).bossTriggered, true)
  T.ok(ns.Run.disableBoss(run))
  T.eq(H.score(run, { king }).bossTriggered, false)
  run.hand = { H.card(13, "S"), H.card(2, "C") }
  local result = ns.Run.play(run, { 1 })
  T.eq(result.bossTriggered, false)
  T.ok(result.total > 0)
  ns.Run.startBlind(run)
  T.eq(run.bossDisabled, false, "reset on the next blind")
end)

H.test("v5_save_migrates", function()
  local run = H.run()
  ns.Run.startBlind(run)
  local db = {}
  ns.Save.store(db, run)
  T.eq(db.version, 6)
  db.version = 5
  db.run.usage, db.run.cardLog, db.run.bossDisabled, db.run.startDeckSize = nil, nil, nil, nil
  db.run.handsPlayedRound = nil
  local loaded = ns.Save.load(db)
  T.eq(loaded.usage, { scroll = 0, tome = 0, relic = 0, tomeIds = {} })
  T.eq(loaded.cardLog, { added = {}, destroyed = {} })
  T.eq(loaded.bossDisabled, false)
  T.eq(loaded.startDeckSize, 52)
  T.eq(loaded.handsPlayedRound, 0)
end)

-- Fix round 1.
H.test("score_ctx_bot_and_helper_respect_disabled_boss", function()
  local bot = dofile("tools/sim/bot.lua")(ns)
  local run = H.run()
  run.blind, run.bosses[1] = 3, "HOGGER"
  ns.Run.startBlind(run)
  run.hand = { H.card(13, "S") }
  local debuffed = bot.bestPlay(run)
  T.ok(ns.Run.disableBoss(run))
  T.eq(ns.Run.scoreCtx(run, run.hand).bossId, nil)
  local lifted = bot.bestPlay(run)
  T.ok(lifted > debuffed, "the bot scores the face card undebuffed: " .. lifted .. " vs " .. debuffed)
  T.eq(lifted, H.score(run, { run.hand[1] }).total)
end)

H.test("score_ctx_usage_through_helper_and_bot", function()
  H.stub({ id = "S_FT", before = function(ctx) return { mult = 10 * ctx.usage.scroll } end })
  local bot = dofile("tools/sim/bot.lua")(ns)
  local run = H.run({ trinkets = { "S_FT" } })
  ns.Run.startBlind(run)
  run.hand = { H.card(9, "H") }
  local none = H.score(run, { run.hand[1] }).total
  local botNone = bot.bestPlay(run)
  run.usage.scroll = 3
  T.ok(H.score(run, { run.hand[1] }).total > none, "helper sees usage")
  T.ok(bot.bestPlay(run) > botNone, "bot sees usage")
end)

H.test("disable_boss_only_in_play", function()
  local run = H.run()
  run.blind, run.bosses[1] = 3, "MUTANUS"
  run.phase = "shop"
  T.eq(ns.Run.disableBoss(run), false)
  T.eq(run.bossDisabled, false)
end)

H.test("save_load_clears_card_log", function()
  local run = H.run()
  ns.Deck.add(run, H.card(5, "H"))
  T.eq(#run.cardLog.added, 1)
  local db = {}
  ns.Save.store(db, run)
  T.eq(ns.Save.load(db).cardLog, { added = {}, destroyed = {} })
end)

H.test("sell_trinket_flushes_card_log", function()
  local got = 0
  H.stub({ id = "S_WATCH", onCardsDestroyed = function(_, _, cards) got = got + #cards end })
  H.stub({ id = "S_FAREWELL", onSelfSold = function(run) return { destroyCard = run.deck[1].id } end })
  local run = H.run({ trinkets = { "S_FAREWELL", "S_WATCH" } })
  ns.Run.startBlind(run)
  T.ok(ns.Run.sellTrinket(run, 1))
  T.eq(got, 1)
  T.eq(run.cardLog, { added = {}, destroyed = {} })
end)

H.test("flush_loops_with_cap", function()
  local calls = 0
  H.stub({ id = "S_CHAIN", onCardsAdded = function()
    calls = calls + 1
    return { createCard = { card = { rank = 2, suit = "C" } } }
  end })
  local run = H.run({ trinkets = { "S_CHAIN" } })
  ns.Deck.add(run, H.card(5, "H"))
  ns.TrinketEngine.flushCards(run)
  T.eq(calls, 5, "capped at five passes")

  calls = 0
  H.cleanup()
  H.stub({ id = "S_ONCE", onCardsAdded = function(_, _, cards)
    calls = calls + 1
    if cards[1].rank == 5 then return { createCard = { card = { rank = 6, suit = "C" } } } end
  end })
  run = H.run({ trinkets = { "S_ONCE" } })
  ns.Deck.add(run, H.card(5, "H"))
  ns.TrinketEngine.flushCards(run)
  T.eq(calls, 2, "the made card is announced in a second pass")
  T.eq(run.cardLog, { added = {}, destroyed = {} })
end)

H.test("v5_mid_shop_save_migrates", function()
  local run = H.run()
  run.phase = "shop"
  run.shop = { cards = {}, packs = {}, rerollCost = 5, freeRerolls = 0 }
  local db = {}
  ns.Save.store(db, run)
  db.version = 5
  db.run.usage, db.run.cardLog, db.run.bossDisabled, db.run.startDeckSize = nil, nil, nil, nil
  local loaded = ns.Save.load(db)
  T.eq(loaded.phase, "shop")
  T.eq(loaded.shop.rerollCost, 5)
  T.eq(loaded.usage, { scroll = 0, tome = 0, relic = 0, tomeIds = {} })
  T.eq(loaded.cardLog, { added = {}, destroyed = {} })
  T.eq(loaded.bossDisabled, false)
  T.eq(loaded.startDeckSize, 52)
  T.eq(loaded.handsPlayedRound, 0)
end)
