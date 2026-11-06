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
