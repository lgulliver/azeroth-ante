local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local LEGENDARIES = { "FROSTMOURNE", "SHALAMAYNE", "SHADOWMOURNE", "ASHBRINGER", "DRAGONWRATH" }

local function shopRun()
  local run = H.run()
  run.phase, run.gold = "shop", 100
  return run
end

local function useHeart(run)
  local item = { kind = "relic", id = "LEGENDS" }
  run.consumables = { item }
  T.ok(ns.Consumables.use(run, 1), "Heart of Azeroth used")
end

T.test("legendaries_defined", function()
  for _, id in ipairs(LEGENDARIES) do
    local def = ns.Trinkets.def[id]
    T.eq({ def.rarity, def.cost }, { "legendary", 20 }, id)
  end
end)

T.test("legendaries_never_random", function()
  for _, id in ipairs(LEGENDARIES) do T.eq(ns.Trinkets.inPool(H.run(), id), false, id) end
  local run = shopRun()
  for _ = 1, 300 do
    local offer = ns.Shop.rollTrinket(run, {})
    T.ok(ns.Trinkets.def[offer.id].rarity ~= "legendary", "shop rolled " .. offer.id)
  end
  local item = { kind = "scroll", id = "SUMMONING" }
  for _ = 1, 200 do
    run.trinkets, run.consumables = {}, { item }
    T.ok(ns.Consumables.use(run, 1), "Summoning used")
    T.ok(ns.Trinkets.def[run.trinkets[1].id].rarity ~= "legendary", "Summoning made " .. run.trinkets[1].id)
  end
end)

T.test("heart_of_azeroth_spreads_over_legendaries", function()
  local seen = {}
  for seed = 1, 200 do
    local run = ns.Run.new(seed, "ROGUE")
    run.phase = "shop"
    useHeart(run)
    seen[run.trinkets[1].id] = true
  end
  for _, id in ipairs(LEGENDARIES) do T.ok(seen[id], "never made " .. id) end
end)

T.test("heart_of_azeroth_skips_owned_legendaries", function()
  local run = shopRun()
  for i = 1, 4 do run.trinkets[i] = ns.Trinkets.create(run, LEGENDARIES[i]) end
  useHeart(run)
  T.eq(run.trinkets[5].id, "DRAGONWRATH")
end)

T.test("darkmoon_fizz_sells_for_bonus_roll", function()
  local run = H.run({ trinkets = { "DARKMOON_FIZZ" } })
  run.phase = "shop"
  T.ok(ns.Run.sellTrinket(run, 1))
  T.eq(run.tags, { "DOUBLE" })
end)

T.test("timewalking_badge_scales_with_skips", function()
  local run = H.run({ trinkets = { "TIMEWALKING_BADGE" } })
  local cards = { H.card(2, "S") }
  local plain = H.score(run, cards).total
  run.skips = 4
  T.eq(H.score(run, cards).total, plain * 2)
  run.phase, run.blind = "blind", 1
  ns.Run.skipBlind(run)
  T.eq(run.skips, 5)
end)

T.test("frostmourne_gains_per_face_destroyed", function()
  local run = H.run({ trinkets = { "FROSTMOURNE" } })
  ns.TrinketEngine.fire(run, "onCardsDestroyed", { H.card(13), H.card(11), H.card(5) })
  T.eq(run.trinkets[1].state.x, 3)
  local cards = { H.card(2, "S") }
  run.trinkets[1].state.x = 1
  local plain = H.score(run, cards).total
  run.trinkets[1].state.x = 3
  T.eq(H.score(run, cards).total, plain * 3)
end)

T.test("shalamayne_kings_and_queens", function()
  local run = H.run({ trinkets = { "SHALAMAYNE" } })
  local trinket = ns.Trinkets.def.SHALAMAYNE
  T.eq(trinket.onCard(nil, nil, H.card(13)), { xmult = 2 })
  T.eq(trinket.onCard(nil, nil, H.card(12)), { xmult = 2 })
  T.eq(trinket.onCard(nil, nil, H.card(11)), nil)
  T.eq(trinket.onCard(nil, nil, H.card(13, "S", "STONE")), nil)
  local bare = H.run()
  local pair = { H.card(13, "S"), H.card(13, "H") }
  T.eq(H.score(run, pair).total, H.score(bare, pair).total * 4)
end)

T.test("shadowmourne_every_23_discarded", function()
  local run = H.run({ trinkets = { "SHADOWMOURNE" } })
  local self = run.trinkets[1]
  local five = {}
  for i = 1, 5 do five[i] = H.card(i + 1) end
  for _ = 1, 4 do ns.TrinketEngine.fire(run, "onDiscard", five) end
  T.eq({ self.state.x, self.state.left }, { 1, 3 })
  ns.TrinketEngine.fire(run, "onDiscard", five)
  T.eq({ self.state.x, self.state.left }, { 2, 21 })
end)

T.test("ashbringer_disables_boss_at_start", function()
  local run = ns.Run.new(3, "ROGUE")
  run.trinkets = { ns.Trinkets.create(run, "ASHBRINGER") }
  run.stage, run.blind = 2, 3
  run.bosses[2] = "PATCHWERK"
  T.startBlind(run)
  T.ok(run.bossDisabled, "boss disabled")
  T.eq(run.target, math.floor(ns.Run.BASE_TARGETS[2] * 2))
  run = ns.Run.new(3, "ROGUE")
  run.trinkets = { ns.Trinkets.create(run, "ASHBRINGER") }
  T.startBlind(run)
  T.ok(not run.bossDisabled, "small blind untouched")
end)

T.test("ashbringer_from_heart_mid_boss", function()
  local run = ns.Run.new(3, "ROGUE")
  run.stage, run.blind = 2, 3
  run.bosses[2] = "THREDD"
  T.startBlind(run)
  T.ok(not run.bossDisabled)
  for i = 1, 4 do run.trinkets[i] = ns.Trinkets.create(run, LEGENDARIES[i == 4 and 5 or i]) end
  useHeart(run)
  T.eq(run.trinkets[5].id, "ASHBRINGER")
  T.ok(run.bossDisabled, "disabled on arrival")
end)

T.test("dragonwrath_negative_copy_on_leaving_shop", function()
  local run = shopRun()
  run.trinkets = { ns.Trinkets.create(run, "DRAGONWRATH") }
  run.maxConsumables = 2
  run.consumables = { { kind = "scroll", id = "LIGHT" }, { kind = "tome", id = "PAIR" } }
  local base = ns.Consumables.slots(run)
  ns.Run.nextBlind(run)
  T.eq(#run.consumables, 3)
  T.eq(run.consumables[3].ed, "NEGATIVE")
  T.eq(ns.Consumables.slots(run), base + 1)
  -- A full row still takes the copy.
  run.phase = "shop"
  ns.Run.nextBlind(run)
  T.eq(#run.consumables, 4)
  T.eq(ns.Consumables.slots(run), base + 2)
end)

T.test("dragonwrath_nothing_to_copy", function()
  local run = shopRun()
  run.trinkets = { ns.Trinkets.create(run, "DRAGONWRATH") }
  run.consumables = {}
  ns.Run.nextBlind(run)
  T.eq(run.consumables, {})
end)

T.test("negative_consumable_survives_save", function()
  local run = shopRun()
  run.consumables = { { kind = "scroll", id = "LIGHT", ed = "NEGATIVE" } }
  local db = {}
  ns.Save.store(db, run)
  local loaded = ns.Save.load(db)
  T.eq(loaded.consumables[1].ed, "NEGATIVE")
end)
