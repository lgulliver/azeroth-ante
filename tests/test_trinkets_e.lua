local _, ns = ...
local T = ns
ns = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function single() return { H.card(2) } end
local function discard(run, cards)
  run.hand = cards
  if #run.pile == 0 then
    for i = 1, 20 do run.pile[i] = H.card(2) end
  end
  local idx = {}
  for i = 1, #cards do idx[i] = i end
  T.ok(ns.Run.discard(run, idx))
end
local function forced(value, fn)
  local nextRng = ns.RNG.next
  local draws = 0
  ns.RNG.next = function() draws = draws + 1; return value end
  local ok, err = pcall(fn, function() return draws end)
  ns.RNG.next = nextRng
  if not ok then error(err, 0) end
end

H.test("VENTURE_LOAN_effect", function()
  local run = H.run { trinkets = { "VENTURE_LOAN" }, gold = 0 }
  ns.Shop.open(run)
  run.shop.cards = { { type = "trinket", id = "ARCANE_INTELLECT", cost = 20 } }
  T.ok(ns.Shop.buy(run, 1)); T.eq(run.gold, -20)
  T.eq(ns.Run.canAfford(run, 1), false)
  T.eq(ns.Run.canAfford(H.run { gold = 0 }, 1), false)
end)
H.test("SOUL_HARVEST_effect", function()
  local run = H.run { trinkets = { "SOUL_HARVEST", "ARCANE_INTELLECT" } }
  ns.Run.startBlind(run)
  T.eq(#run.trinkets, 1); T.eq(run.trinkets[1].state.mult, 2)
  T.eq(H.score(run, single()).mult, 3)
end)
H.test("dagger_eats_right_neighbour_doubles_sell", function()
  local run = H.run { trinkets = { "SOUL_HARVEST", "WHELP_EGG" } }
  run.trinkets[2].paid, run.trinkets[2].sellBonus = 10, 3
  ns.Run.startBlind(run)
  T.eq(run.trinkets[1].state.mult, 16)
  T.eq(run.lifecycleEvents[1].text, "+16 Mult")
  ns.Run.startBlind(run); T.eq(run.trinkets[1].state.mult, 16)
end)
H.test("DARKMOON_TICKET_effect", function()
  local run = H.run { trinkets = { "DARKMOON_TICKET" }, gold = 10 }
  ns.Shop.open(run)
  T.ok(ns.Shop.reroll(run)); T.eq(run.gold, 10)
  T.ok(ns.Shop.reroll(run)); T.eq(run.gold, 5)
  ns.Shop.open(run)
  T.ok(ns.Shop.reroll(run)); T.eq(run.gold, 5)
end)
H.test("INNER_PEACE_effect", function()
  local run = H.run { trinkets = { "INNER_PEACE" } }
  run.discardsLeft = 3
  ns.Run.winBlind(run); T.eq(run.lastPayout.trinkets, 6)
  run = H.run { trinkets = { "INNER_PEACE" } }
  discard(run, single())
  ns.Run.winBlind(run); T.eq(run.lastPayout.trinkets, 0)
  run = H.run { trinkets = { "INNER_PEACE" } }
  run.discardsLeft = 0
  ns.Run.winBlind(run); T.eq(run.lastPayout.trinkets, 0)
end)
H.test("RIPE_BANANA_effect", function()
  local run = H.run { trinkets = { "RIPE_BANANA" } }
  T.eq(H.score(run, single()).mult, 16)
  forced(0.9, function() ns.Run.winBlind(run) end)
  T.eq(#run.trinkets, 1); T.eq(run.flags.grosMichelExtinct, nil)
end)
H.test("gros_michel_extinct_unlocks_cavendish", function()
  local run = H.run { trinkets = { "RIPE_BANANA" } }
  T.eq(ns.Trinkets.inPool(run, "GOLDEN_BANANA"), false)
  T.eq(ns.Trinkets.inPool(run, "RIPE_BANANA"), true)
  forced(0, function() ns.Run.winBlind(run) end)
  T.eq(#run.trinkets, 0); T.eq(run.flags.grosMichelExtinct, true)
  T.eq(ns.Trinkets.inPool(run, "GOLDEN_BANANA"), true)
  T.eq(ns.Trinkets.inPool(run, "RIPE_BANANA"), false)
  T.eq(run.lifecycleEvents[1].text, "Extinct!")
end)
H.test("WHELP_EGG_effect", function()
  local run = H.run { trinkets = { "WHELP_EGG" } }
  ns.Run.winBlind(run)
  T.eq(run.trinkets[1].sellBonus, 3); T.eq(ns.Shop.sellValue(run.trinkets[1]), 5)
  ns.Run.winBlind(run)
  T.eq(run.trinkets[1].sellBonus, 6); T.eq(run.lifecycleEvents[1].text, "Value up!")
end)
H.test("SI7_AGENT_effect", function()
  local run = H.run { trinkets = { "SI7_AGENT" } }
  ns.Run.startBlind(run)
  T.eq(run.handsLeft, 7); T.eq(run.discardsLeft, 0)
end)
H.test("FACELESS_ONE_effect", function()
  local run = H.run { trinkets = { "FACELESS_ONE" }, gold = 0 }
  discard(run, { H.card(11), H.card(12), H.card(13) }); T.eq(run.gold, 5)
  discard(run, { H.card(11), H.card(12), H.card(2) }); T.eq(run.gold, 5)
  run = H.run { trinkets = { "FACELESS_ONE", "MIND_VISION" }, gold = 0 }
  discard(run, { H.card(2), H.card(3), H.card(4) }); T.eq(run.gold, 5)
  discard(run, { H.card(11), H.card(12), H.card(13, "S", "STONE") }); T.eq(run.gold, 5)
end)
H.test("FEL_INFUSION_effect", function()
  local run = H.run { trinkets = { "FEL_INFUSION" } }
  local r = H.score(run, single())
  T.eq(r.mult, 2); T.eq(run.trinkets[1].state.mult, 0)
  run.trinkets = r.trinketsAfter
  r = H.score(run, single()); T.eq(r.mult, 3)
  run.trinkets = r.trinketsAfter
  discard(run, { H.card(2), H.card(3), H.card(4) })
  T.eq(run.trinkets[1].state.mult, 1)
end)
H.test("green_joker_never_negative", function()
  local run = H.run { trinkets = { "FEL_INFUSION" } }
  discard(run, single()); discard(run, single())
  T.eq(run.trinkets[1].state.mult, 0)
  T.eq(H.score(run, single()).mult, 2)
end)
H.test("DAILY_QUEST_effect", function()
  local run = H.run { trinkets = { "DAILY_QUEST" } }
  local self = run.trinkets[1]
  T.ok(self.state.hand)
  T.eq(ns.Trinkets.def.DAILY_QUEST.status(self), "Hand: " .. ns.Hands.def[self.state.hand].name)
  self.state.hand = "HIGH_CARD"
  T.eq(H.score(run, single()).gold, 4)
  T.eq(H.score(run, { H.card(2), H.card(2, "H") }).gold, 0)
  ns.Run.winBlind(run); T.ok(self.state.hand ~= "HIGH_CARD")
end)
H.test("to_do_list_excludes_current_and_unseen_secret_hands", function()
  local run = H.run()
  forced(0.99999, function(draws)
    run.trinkets = { ns.Trinkets.create(run, "DAILY_QUEST") }
    T.eq(run.trinkets[1].state.hand, "STRAIGHT_FLUSH"); T.eq(draws(), 1)
    ns.Run.winBlind(run)
    T.eq(run.trinkets[1].state.hand, "FOUR_KIND")
  end)
  run.seenHands.FLUSH_FIVE = true
  forced(0.99999, function() ns.Run.winBlind(run) end)
  T.eq(run.trinkets[1].state.hand, "FLUSH_FIVE")
end)
H.test("GOLDEN_BANANA_effect", function()
  local run = H.run { trinkets = { "GOLDEN_BANANA" } }
  T.eq(H.score(run, single()).mult, 3)
  forced(0.9, function() ns.Run.winBlind(run) end); T.eq(#run.trinkets, 1)
  forced(0, function() ns.Run.winBlind(run) end); T.eq(#run.trinkets, 0)
  T.eq(run.flags.grosMichelExtinct, nil)
end)
H.test("bananas_use_loaded_dice_and_one_draw", function()
  for _, case in ipairs({ { "RIPE_BANANA", 0.2 }, { "GOLDEN_BANANA", 0.0015 } }) do
    for _, loaded in ipairs({ false, true }) do
      local ids = { case[1] }
      if loaded then ids[2] = "LOADED_DICE" end
      local run = H.run { trinkets = ids }
      forced(case[2], function(draws)
        ns.TrinketEngine.fire(run, "roundUpdate")
        T.eq(draws(), 1)
      end)
      T.eq(run.trinkets[1].id, loaded and "LOADED_DICE" or case[1])
    end
  end
end)
H.test("PACK_RAT_effect", function()
  local run = H.run { trinkets = { "PACK_RAT" } }
  T.eq(H.score(run, single()).mult, 1)
  ns.Shop.open(run)
  run.shop.openPack = { picksLeft = 1 }
  ns.Packs.skip(run)
  T.eq(H.score(run, single()).mult, 4)
  ns.Packs.skip(run); T.eq(run.trinkets[1].state.mult, 3)
end)
H.test("OLD_GODS_effect", function()
  local run = H.run { trinkets = { "OLD_GODS", "ARCANE_INTELLECT" } }
  ns.Run.startBlind(run)
  T.eq(#run.trinkets, 1); T.eq(run.trinkets[1].id, "OLD_GODS")
  T.eq(H.score(run, single()).mult, 1.5)
  run.blind = 2
  ns.Run.startBlind(run); T.eq(H.score(run, single()).mult, 2)
end)
H.test("madness_skips_boss_blind", function()
  local run = H.run { trinkets = { "OLD_GODS", "ARCANE_INTELLECT" } }
  run.blind = 3
  ns.Run.startBlind(run)
  T.eq(#run.trinkets, 2); T.eq(run.trinkets[1].state.x, 1)
end)
H.test("CALL_TO_ARMS_effect", function()
  local run = H.run { trinkets = { "CALL_TO_ARMS" } }
  ns.Run.startBlind(run); T.eq(#run.trinkets, 3)
  for i = 2, 3 do
    T.eq(ns.Trinkets.def[run.trinkets[i].id].rarity, "common")
    T.ok(run.trinkets[i].id ~= "CALL_TO_ARMS")
  end
  T.ok(run.trinkets[2].id ~= run.trinkets[3].id)
end)
H.test("riff_raff_respects_room", function()
  for _, room in ipairs({ 0, 1 }) do
    local run = H.run { trinkets = { "CALL_TO_ARMS", "ARCANE_INTELLECT", "WHETSTONE", "HEALTHSTONE" } }
    run.maxTrinkets = 4 + room
    ns.Run.startBlind(run); T.eq(#run.trinkets, 4 + room)
  end
end)
H.test("dagger_and_madness_skip_marked_victims", function()
  H.stub { id = "E_MARK", onBlindSelect = function(run) return { destroyTrinket = run.trinkets[3].uid } end }
  local run = H.run { trinkets = { "E_MARK", "SOUL_HARVEST", "ARCANE_INTELLECT" } }
  ns.Run.startBlind(run); T.eq(run.trinkets[2].state.mult, 0)
  run = H.run { trinkets = { "SOUL_HARVEST", "ARCANE_INTELLECT", "OLD_GODS", "WHETSTONE" } }
  forced(0.5, function() ns.Run.startBlind(run) end)
  T.eq(#run.trinkets, 2); T.eq(run.trinkets[1].id, "SOUL_HARVEST")
  T.eq(run.trinkets[2].id, "OLD_GODS"); T.eq(run.trinkets[2].state.x, 1.5)
end)
H.test("copy_guards_preserve_single_scaling", function()
  local run = H.run { trinkets = { "SCHEMATIC", "FEL_INFUSION" } }
  local r = H.score(run, single())
  T.eq(r.mult, 3); T.eq(r.trinketsAfter[2].state.mult, 1)
  run.trinkets = r.trinketsAfter
  discard(run, single()); T.eq(run.trinkets[2].state.mult, 0)
  run = H.run { trinkets = { "SCHEMATIC", "SOUL_HARVEST", "ARCANE_INTELLECT" } }
  ns.Run.startBlind(run); T.eq(#run.trinkets, 2)
  T.eq(run.trinkets[2].state.mult, 2); T.eq(H.score(run, single()).mult, 5)
  run = H.run { trinkets = { "SCHEMATIC", "OLD_GODS" } }
  ns.Run.startBlind(run)
  T.eq(#run.trinkets, 1); T.eq(run.trinkets[1].state.x, 1.5)
  run = H.run { trinkets = { "SCHEMATIC", "PACK_RAT" } }
  ns.Shop.open(run); run.shop.openPack = { picksLeft = 1 }; ns.Packs.skip(run)
  T.eq(run.trinkets[2].state.mult, 3); T.eq(H.score(run, single()).mult, 7)
end)
H.test("noncopyable_economy_trinkets", function()
  for _, id in ipairs({ "VENTURE_LOAN", "DARKMOON_TICKET", "INNER_PEACE", "WHELP_EGG" }) do
    local run = H.run { trinkets = { "SCHEMATIC", id } }
    T.ok(ns.Trinkets.def[id], "missing " .. id)
    T.eq(ns.Trinkets.def[id].copyable, false)
    T.eq(ns.TrinketEngine.source(run.trinkets, 1), nil, id)
  end
end)

H.test("SKY_GOLEM_effect", function()
  local run = H.run { trinkets = { "SKY_GOLEM" } }
  run.deck = { H.card(9), H.card(9, "H"), H.card(9, "S", "STONE"), H.card(8) }
  ns.Run.winBlind(run); T.eq(run.lastPayout.trinkets, 2)
end)
H.test("GOBLIN_ROCKET_effect", function()
  local run = H.run { trinkets = { "GOBLIN_ROCKET" } }
  ns.Run.winBlind(run); T.eq(run.lastPayout.trinkets, 1)
  run.blind = 3
  ns.Run.winBlind(run); T.eq(run.lastPayout.trinkets, 3)
  ns.Run.winBlind(run); T.eq(run.lastPayout.trinkets, 5)
end)
H.test("WINTER_VEIL_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "WINTER_VEIL", "WHELP_EGG" } }
  run.consumables = { { kind = "tome", id = "PAIR", sellBonus = 2 } }
  ns.Run.winBlind(run)
  for i = 1, 2 do T.eq(run.trinkets[i].sellBonus, 1) end
  T.eq(run.trinkets[3].sellBonus, 4); T.eq(run.consumables[1].sellBonus, 3)
end)
H.test("FERTILE_SEED_effect", function()
  local run = H.run { trinkets = { "FERTILE_SEED" } }
  T.eq(ns.Deck.handSize(run), 13)
  ns.Run.startBlind(run); T.eq(#run.hand, 13)
end)
H.test("turtle_bean_decays_and_shrinks_hand", function()
  local run = H.run { trinkets = { "SCHEMATIC", "FERTILE_SEED" } }
  for n = 4, 0, -1 do
    ns.Run.winBlind(run)
    T.eq(ns.Deck.handSize(run), 8 + n)
  end
  T.eq(#run.trinkets, 1); T.eq(run.lifecycleEvents[1].text, "Eaten!")
end)
H.test("POSTMASTER_effect", function()
  local run = H.run()
  run.deck = { H.card(9, "S", "STONE"), H.card(14) }
  forced(0, function() run.trinkets = { ns.Trinkets.create(run, "POSTMASTER") } end)
  T.eq(run.trinkets[1].state.rank, 14)
  T.eq(ns.Trinkets.def.POSTMASTER.status(run.trinkets[1]), "Rank: A")
  run.gold = 0
  discard(run, { H.card(14), H.card(14, "H"), H.card(14, "S", "STONE"), H.card(9) })
  T.eq(run.gold, 10)
  run.deck = { H.card(12) }
  ns.TrinketEngine.fire(run, "roundUpdate"); T.eq(run.trinkets[1].state.rank, 12)
end)
H.test("GOBLIN_INVEST_effect", function()
  local run = H.run { trinkets = { "GOBLIN_INVEST" }, gold = 15 }
  ns.Run.winBlind(run); T.eq(run.lastPayout.interest, 6)
end)
H.test("to_the_moon_interest", function()
  for _, gold in ipairs({ -5, 0, 4, 5, 24, 25, 100 }) do
    local run = H.run { trinkets = { "SCHEMATIC", "GOBLIN_INVEST", "GOBLIN_INVEST" }, gold = gold }
    ns.Run.winBlind(run)
    T.eq(run.lastPayout.interest, math.min(5, math.floor(math.max(0, gold) / 5)) * 3)
  end
end)
H.test("REAGENT_BAG_effect", function()
  local run = H.run { trinkets = { "REAGENT_BAG" } }
  ns.Run.startBlind(run); T.eq(#run.hand, 9)
end)
H.test("DWARVEN_STOUT_effect", function()
  local run = H.run { trinkets = { "DWARVEN_STOUT" } }
  ns.Run.startBlind(run); T.eq(run.discardsLeft, 5)
end)
H.test("TRADING_POST_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "TRADING_POST" }, gold = 0 }
  local card = H.card(9)
  run.deck[#run.deck + 1] = card
  discard(run, { card }); T.eq(run.gold, 3) -- Blueprint no longer copies it
  for _, c in ipairs(run.deck) do T.ok(c.id ~= card.id) end
  discard(run, single()); T.eq(run.gold, 3)
  run = H.run { trinkets = { "TRADING_POST" }, gold = 0 }
  discard(run, { H.card(2), H.card(3) }); discard(run, single()); T.eq(run.gold, 0)
end)
H.test("FLASH_HEAL_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "FLASH_HEAL" }, gold = 20 }
  T.eq(H.score(run, single()).mult, 1)
  ns.Shop.open(run); T.ok(ns.Shop.reroll(run))
  T.eq(run.trinkets[2].state.mult, 2); T.eq(H.score(run, single()).mult, 5)
  T.ok(ns.Shop.reroll(run)); T.eq(H.score(run, single()).mult, 9)
end)
H.test("POPCORN_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "POPCORN" } }
  T.eq(H.score(run, single()).mult, 41)
  ns.Run.winBlind(run); T.eq(H.score(run, single()).mult, 33)
  for _ = 1, 4 do ns.Run.winBlind(run) end
  T.eq(#run.trinkets, 1); T.eq(run.lifecycleEvents[1].text, "Eaten!")
end)
H.test("NOODLES_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "NOODLES" } }
  T.eq(H.score(run, single()).mult, 4)
  discard(run, { H.card(2), H.card(3) })
  T.ok(math.abs(run.trinkets[2].state.x - 1.98) < 1e-9)
  T.ok(math.abs(H.score(run, single()).mult - 1.98^2) < 1e-9)
end)
H.test("ramen_eaten_at_one", function()
  local run = H.run { trinkets = { "NOODLES" } }
  run.trinkets[1].state.x = 1.01
  discard(run, single()); T.eq(#run.trinkets, 0)
  T.eq(run.lifecycleEvents[1].text, "Eaten!")
end)
H.test("STORMWIND_KEEP_effect", function()
  local run = H.run()
  forced(0, function() run.trinkets = { ns.Trinkets.create(run, "STORMWIND_KEEP") } end)
  T.eq(run.trinkets[1].state.suit, "S")
  run.trinkets[#run.trinkets + 1] = ns.Trinkets.create(run, "MURKY_INK")
  run.trinkets[#run.trinkets + 1] = ns.Trinkets.create(run, "SCHEMATIC")
  T.ok(ns.Run.moveTrinket(run, 3, 1))
  discard(run, { H.card(2, "S"), H.card(3, "C"), H.card(4, "H", "WILD"), H.card(5, "S", "STONE") })
  T.eq(run.trinkets[2].state.chips, 9); T.eq(H.score(run, single()).chips, 25)
  forced(0, function() ns.TrinketEngine.fire(run, "roundUpdate") end)
  T.eq(run.trinkets[2].state.suit, "H")
  T.eq(ns.Trinkets.def.STORMWIND_KEEP.status(run.trinkets[2]), "Suit: Hearts")
end)
H.test("COOKING_FIRE_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "COOKING_FIRE", "ARCANE_INTELLECT" } }
  T.eq(H.score(run, single()).mult, 5)
  T.ok(ns.Run.sellTrinket(run, 3)); T.eq(run.trinkets[2].state.x, 1.25)
  T.eq(H.score(run, single()).mult, 1.25^2)
  run.consumables = { { kind = "tome", id = "PAIR" } }
  T.ok(ns.Consumables.sell(run, 1)); T.eq(run.trinkets[2].state.x, 1.5)
end)
H.test("campfire_resets_on_boss", function()
  local run = H.run { trinkets = { "COOKING_FIRE", "ARCANE_INTELLECT" } }
  ns.Run.sellTrinket(run, 2)
  ns.Run.winBlind(run); T.eq(run.trinkets[1].state.x, 1.25)
  run.blind = 3
  ns.Run.winBlind(run); T.eq(run.trinkets[1].state.x, 1)
end)
H.test("SOULSTONE_effect", function()
  for _, score in ipairs({ 74, 75 }) do
    local run = H.run { trinkets = { "SOULSTONE" } }
    run.score, run.target = score, 300
    ns.Run.checkHand(run)
    T.eq(run.phase, score == 75 and "shop" or "lost")
    T.eq(#run.trinkets, score == 75 and 0 or 1)
    if score == 75 then
      T.eq(run.lastPayout.reward, 0); T.eq(run.lastPayout.savedId, "SOULSTONE")
      T.eq(run.lifecycleEvents[1].text, "Saved!")
    end
  end
end)
H.test("mr_bones_saves_once", function()
  local run = H.run { trinkets = { "SCHEMATIC", "SOULSTONE" } }
  run.score = 75
  ns.Run.checkHand(run); T.eq(#run.trinkets, 1)
  ns.Run.startBlind(run)
  run.hand, run.pile, run.score = {}, {}, 75
  ns.Run.checkHand(run); T.eq(run.phase, "lost")
end)
H.test("MINSTREL_effect", function()
  local run = H.run { trinkets = { "MINSTREL" } }
  ns.Run.startBlind(run); T.eq(#run.hand, 10); T.eq(run.handsLeft, 3)
end)
H.test("SILAS_effect", function()
  local run = H.run { trinkets = { "SILAS" } }
  T.ok(ns.TrinketRules.has(run.trinkets, "SHOWMAN"))
  -- Owning every common leaves no pool unless Showman allows repeats.
  for _, id in ipairs(ns.Trinkets.order) do
    if ns.Trinkets.def[id].rarity == "common" then
      run.trinkets[#run.trinkets + 1] = ns.Trinkets.create(run, id)
    end
  end
  T.ok(ns.Trinkets.rollOfRarity(run, "common"))
  table.remove(run.trinkets, 1)
  T.eq(ns.Trinkets.rollOfRarity(run, "common"), nil)
end)
H.test("BRAWLER_effect", function()
  local run = H.run { trinkets = { "BRAWLER" } }
  ns.Run.startBlind(run); T.eq(#run.hand, 7); T.eq(run.discardsLeft, 7)
end)
H.test("MOUNT_UP_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "MOUNT_UP" } }
  discard(run, { H.card(11), H.card(11, "H"), H.card(11, "S", "STONE"), H.card(12) })
  T.eq(run.trinkets[2].state.x, 2); T.eq(H.score(run, single()).mult, 4)
  ns.Run.winBlind(run); T.eq(run.trinkets[2].state.x, 1)
end)
H.test("LEEROY_effect", function()
  local run = H.run { trinkets = { "LEEROY" } }
  ns.Run.startBlind(run); T.eq(#run.hand, 6)
  T.eq(H.score(run, single()).chips, 257)
end)
H.test("stuntman_chips_copyable_hand_size_not", function()
  local run = H.run { trinkets = { "SCHEMATIC", "LEEROY" } }
  ns.Run.startBlind(run); T.eq(#run.hand, 6)
  T.eq(H.score(run, single()).chips, 507)
end)
H.test("INVIS_POTION_effect", function()
  for _, ed in ipairs({ "NEGATIVE", "FOIL", "HOLO", "POLY" }) do
    local run = H.run { trinkets = { "INVIS_POTION", "FLASH_HEAL" } }
    run.trinkets[2].ed, run.trinkets[2].state.mult, run.trinkets[2].sellBonus = ed, 8, 3
    local original = run.trinkets[2]
    ns.Run.winBlind(run); ns.Run.winBlind(run)
    T.eq(ns.Trinkets.def.INVIS_POTION.status(run.trinkets[1]), "Ready!")
    forced(0, function(draws) ns.Run.sellTrinket(run, 1); T.eq(draws(), 1) end)
    T.eq(#run.trinkets, 2)
    local copy = run.trinkets[2]
    T.eq(copy.id, "FLASH_HEAL"); T.eq(copy.ed, ed ~= "NEGATIVE" and ed or nil)
    T.ok(copy.uid ~= original.uid); T.eq(copy.state.mult, 8); T.eq(copy.sellBonus, 3)
    copy.state.mult = 10; T.eq(original.state.mult, 8)
  end
end)
H.test("invisible_emits_created_event", function()
  local run = H.run { trinkets = { "ARCANE_INTELLECT", "INVIS_POTION", "FLASH_HEAL" } }
  ns.Run.winBlind(run); ns.Run.winBlind(run)
  run.lifecycleEvents = {}
  forced(0, function() ns.Run.sellTrinket(run, 2) end)
  T.eq(#run.trinkets, 3)
  local copy = run.trinkets[3]
  local created
  for _, e in ipairs(run.lifecycleEvents) do
    if e.kind == "trinketCreated" then T.ok(not created, "one event"); created = e end
  end
  T.ok(created, "trinketCreated emitted")
  T.eq(created.uid, copy.uid); T.eq(created.slot, 3); T.eq(created.id, copy.id)
end)
H.test("ramen_eaten_on_100th_discard", function()
  local run = H.run { trinkets = { "NOODLES" } }
  for i = 1, 100 do
    run.discardsLeft = 3
    discard(run, single())
    if i < 100 then
      T.eq(#run.trinkets, 1, "alive after discard " .. i)
      T.eq(run.trinkets[1].state.x, math.floor((2 - 0.01 * i) * 100 + 0.5) / 100)
    end
  end
  T.eq(#run.trinkets, 0)
  local eaten = 0
  for _, e in ipairs(run.lifecycleEvents) do if e.text == "Eaten!" then eaten = eaten + 1 end end
  T.eq(eaten, 1)
end)
H.test("sell_hand_size_and_discard_trinkets_mid_blind", function()
  local run = H.run { trinkets = { "REAGENT_BAG", "DWARVEN_STOUT" } }
  ns.Run.startBlind(run)
  local base = ns.Decks.def[run.deckId].discards
  T.eq(#run.hand, 9); T.eq(run.discardsLeft, base + 1)
  local hand = {}
  for i, c in ipairs(run.hand) do hand[i] = c end
  T.ok(ns.Run.sellTrinket(run, 1))
  T.eq(run.discardsLeft, base + 1) -- Bag sold: discards untouched.
  T.eq(#run.hand, 9); for i, c in ipairs(hand) do T.ok(run.hand[i] == c, "hand card kept") end
  T.ok(ns.Run.sellTrinket(run, 1))
  T.eq(run.discardsLeft, base)
  T.eq(#run.hand, 9)
  -- Never below 0.
  run.trinkets = { ns.Trinkets.create(run, "DWARVEN_STOUT") }
  run.discardsLeft = 0
  T.ok(ns.Run.sellTrinket(run, 1)); T.eq(run.discardsLeft, 0)
  -- The next blind deals the base hand size.
  run.phase = "play"; ns.Run.startBlind(run)
  T.eq(#run.hand, 8); T.eq(run.discardsLeft, base)
end)
H.test("invisible_needs_two_rounds", function()
  local run = H.run { trinkets = { "INVIS_POTION", "ARCANE_INTELLECT" } }
  T.eq(ns.Trinkets.def.INVIS_POTION.status(run.trinkets[1]), "0/2 rounds")
  ns.Run.winBlind(run)
  T.eq(ns.Trinkets.def.INVIS_POTION.status(run.trinkets[1]), "1/2 rounds")
  ns.Run.sellTrinket(run, 1); T.eq(#run.trinkets, 1)
  run = H.run { trinkets = { "INVIS_POTION" } }
  ns.Run.winBlind(run); ns.Run.winBlind(run)
  forced(0, function(draws) ns.Run.sellTrinket(run, 1); T.eq(draws(), 0) end)
  T.eq(#run.trinkets, 0)
end)
H.test("STARGAZER_effect", function()
  local run = H.run { trinkets = { "STARGAZER" } }
  T.ok(ns.TrinketRules.has(run.trinkets, "ASTRONOMER"))
  for _, kind in ipairs({ "tome", "CELESTIAL", "scroll" }) do
    T.eq(ns.Shop.priceOf(run, { type = kind, cost = 5 }), kind == "scroll" and 5 or 0)
  end
end)
H.test("BURNT_OFFERING_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "BURNT_OFFERING", "MURKY_INK" } }
  discard(run, { H.card(2, "H"), H.card(5, "D"), H.card(8, "H"), H.card(10, "D"), H.card(13, "H") })
  T.eq(run.handLevels.FLUSH, 3)
  discard(run, { H.card(2), H.card(2, "H") }); T.eq(run.handLevels.PAIR, 1)
end)
H.test("part_b_noncopyable_trinkets", function()
  for _, id in ipairs({ "WINTER_VEIL", "FERTILE_SEED", "SKY_GOLEM", "GOBLIN_ROCKET", "GOBLIN_INVEST",
    "REAGENT_BAG", "DWARVEN_STOUT", "SOULSTONE", "MINSTREL", "SILAS", "BRAWLER", "INVIS_POTION", "STARGAZER" }) do
    T.ok(ns.Trinkets.def[id], "missing " .. id)
    T.eq(ns.Trinkets.def[id].copyable, false, id)
    local run = H.run { trinkets = { "SCHEMATIC", id } }
    T.eq(ns.TrinketEngine.source(run.trinkets, 1), nil, id)
  end
end)
