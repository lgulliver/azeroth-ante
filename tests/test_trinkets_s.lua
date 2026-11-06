local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function single() return { H.card(2) } end
local function pair() return { H.card(2), H.card(2, "H") } end
local function triple() return { H.card(2), H.card(2, "H"), H.card(2, "D") } end
local function twoPair() return { H.card(2), H.card(2, "H"), H.card(3), H.card(3, "D") } end
local function straight() return { H.card(2), H.card(3, "H"), H.card(4), H.card(5), H.card(6) } end
local function flush() return { H.card(2), H.card(4), H.card(6), H.card(8), H.card(10) } end

-- Literal totals derived from level-1 hands; catches wrong conditions and effect amounts.
local cases = {
  { "ARCANE_INTELLECT", single, 7, 5 },
  { "JEWELERS_KIT", function() return { H.card(2, "D") } end, 7, 4 },
  { "HEALTHSTONE", function() return { H.card(2, "H") } end, 7, 4 },
  { "WHETSTONE", single, 7, 4 },
  { "OGRE_CUDGEL", function() return { H.card(2, "C") } end, 7, 4 },
  { "TWIN_BLADES", pair, 14, 10 }, { "CLEAVE", triple, 36, 15 },
  { "TWIN_FANGS", twoPair, 30, 12 }, { "MULTI_SHOT", straight, 50, 16 },
  { "ELEMENTAL", flush, 65, 14 }, { "PICKPOCKET", pair, 64, 2 },
  { "TRICKS_TRADE", triple, 136, 3 }, { "DOUBLE_AGENT", twoPair, 110, 2 },
  { "SHADOWSTEP", straight, 150, 4 }, { "TOTEMIC_RECALL", flush, 145, 4 },
  { "SHRINK_RAY", single, 7, 21 }, { "SPIRIT_HEALER", single, 7, 5 },
  { "SLEIGHT_HAND", function() return { H.card(2), H.card(3, "H"), H.card(4), H.card(5) } end, 44, 4 },
  { "COMBO_POINTS", single, 97, 1, { discardsLeft = 3 } },
  { "MOUNT_HYJAL", single, 7, 16, { discardsLeft = 0 } },
  { "FORTITUDE", single, 41, 1, { pileCount = 17 } },
  { "AVENGING_WRATH", single, 7, 3, { roundHandPlays = { HIGH_CARD = 1 } } },
  { "EXECUTE", single, 7, 3, { isLastHand = true } },
  { "BATTLE_SHOUT", single, 7, 4 },
  { "GOBLIN_BANK", single, 7, 5, nil, 12 },
  { "HUNTERS_MARK", function() return { H.card(14) } end, 36, 5 },
  { "ROYAL_GUARD", function() return { H.card(12) } end, 45, 1 },
  { "EVENTIDE", single, 9, 1, { isLastHand = true } },
  { "TITANIC_RATIO", single, 7, 9 }, { "HACK_SLASH", single, 9, 1 },
  { "MIND_VISION", single, 7, 1 }, { "BALANCE_POWER", single, 7, 5 },
  { "ODD_GOBLIN", function() return { H.card(14) } end, 47, 1 },
  { "STARFALL", single, 7, 5, { handPlays = { HIGH_CARD = 3 } } },
  { "FLIGHT_PATH", single, 7, 2 },
}
for _, case in ipairs(cases) do
  H.test(case[1] .. "_effect", function()
    T.ok(ns.Trinkets.def[case[1]], "missing " .. case[1])
    local r = H.score(H.run { trinkets = { case[1] }, gold = case[6] }, case[2](), nil, case[5])
    T.eq(r.chips, case[3]); T.eq(r.mult, case[4]); T.eq(r.total, math.floor(case[3] * case[4]))
  end)
end

H.test("BLOODLUST_effect", function()
  local run = H.run { trinkets = { "BLOODLUST" } }
  run.trinkets[1].state.hands = 5
  local r = H.score(run, single())
  T.eq(r.total, 28); T.eq(r.trinketsAfter[1].state.hands, 6)
  T.eq(run.trinkets[1].state.hands, 5)
end)
H.test("loyalty_countdown", function()
  local run = H.run { trinkets = { "BLOODLUST" } }
  for hand = 1, 12 do
    local r = H.score(run, single(), nil, { handsPlayedTotal = 100 + hand })
    T.eq(r.mult, hand % 6 == 0 and 4 or 1)
    run.trinkets = r.trinketsAfter
    T.eq(ns.Trinkets.def.BLOODLUST.status(run.trinkets[1]), (6 - hand % 6) .. " remaining")
  end
end)
H.test("HEARTHSTONE_effect", function()
  local run = H.run { trinkets = { "HEARTHSTONE" } }
  T.eq(H.score(run, single()).total, 7)
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.trinkets, 4)
  T.eq(run.lastPayout.trinketLines, { { id = "HEARTHSTONE", gold = 4, uid = 1 } })
  T.eq(ns.Trinkets.def.HEARTHSTONE.copyable, false)
end)
H.test("LUCKY_CHARM_effect", function()
  for _, seed in ipairs({ 1, 64000, 123456 }) do
    local run = H.run { trinkets = { "LUCKY_CHARM" } }
    run.rng = ns.RNG.new(seed)
    local expectedRng = ns.RNG.new(seed)
    local want = math.floor(ns.RNG.next(expectedRng) * 24)
    T.eq(H.score(run, single()).mult, 1 + want)
    T.eq(run.rng, expectedRng)
  end
end)
H.test("MIRROR_IMAGE_effect", function()
  T.ok(ns.Trinkets.def.MIRROR_IMAGE)
  local r = H.score(H.run { trinkets = { "MIRROR_IMAGE" } }, single(), { H.card(7, "H", "STEEL") })
  T.eq(r.mult, 2.25); T.eq(r.total, 15)
end)
H.test("FIST_JUSTICE_effect", function()
  T.ok(ns.Trinkets.def.FIST_JUSTICE)
  local held = { H.card(2), H.card(14, "H", "STONE"), H.card(2, "H", nil, nil, "RED") }
  local r = H.score(H.run { trinkets = { "FIST_JUSTICE" } }, single(), held)
  T.eq(r.mult, 9)
  local hits = {}
  for _, e in ipairs(r.events) do if e.kind == "trinket" then hits[#hits + 1] = e.heldIndex end end
  T.eq(hits, { 3, 3 })
  T.eq(H.score(H.run { trinkets = { "FIST_JUSTICE" } }, single(), { H.card(14) }).mult, 23)
  T.eq(H.score(H.run { trinkets = { "FIST_JUSTICE" } }, single(), { H.card(2, "S", "STONE") }).mult, 1)
end)
H.test("TRADE_PRINCE_effect", function()
  T.ok(ns.Trinkets.def.TRADE_PRINCE)
  for _, case in ipairs({ { 1, 2 }, { 64000, 0 } }) do
    local run = H.run { trinkets = { "TRADE_PRINCE" } }
    run.rng = ns.RNG.new(case[1])
    local r = H.score(run, { H.card(12) })
    T.eq(r.gold, case[2]); T.eq(r.total, 15)
  end
end)
H.test("TWISTING_NETHER_effect", function()
  T.ok(ns.Trinkets.def.TWISTING_NETHER)
  for _, case in ipairs({ { 1, 1, 17, 2 }, { 64000, nil, 7, 1 } }) do
    local run = H.run { trinkets = { "TWISTING_NETHER" } }
    run.rng = ns.RNG.new(case[1])
    local r = H.score(run, single())
    T.eq(r.levelUps.HIGH_CARD, case[2]); T.eq(r.chips, case[3]); T.eq(r.mult, case[4])
    T.eq(run.handLevels.HIGH_CARD, 1)
  end
end)
H.test("pareidolia_with_scary_face", function()
  T.eq(H.score(H.run { trinkets = { "ROYAL_GUARD", "MIND_VISION" } }, single()).chips, 37)
end)
H.test("four_fingers_with_droll", function()
  local r = H.score(H.run { trinkets = { "ELEMENTAL", "SLEIGHT_HAND" } },
    { H.card(2), H.card(4), H.card(6), H.card(8) })
  T.eq(r.handId, "FLUSH"); T.eq(r.chips, 55); T.eq(r.mult, 14)
end)
H.test("ARCANE_EXPLOSION_effect", function()
  T.ok(ns.Trinkets.def.ARCANE_EXPLOSION)
  local r = H.score(H.run { trinkets = { "ARCANE_EXPLOSION" } }, { H.card(2), H.card(7, "H"), H.card(10) })
  T.eq(r.chips, 24); T.eq(r.mult, 1)
end)
H.test("rule_trinkets_incompatible", function()
  H.stub { id = "S_COPY", copies = "right" }
  for _, id in ipairs({ "SLEIGHT_HAND", "MIND_VISION", "ARCANE_EXPLOSION" }) do
    T.eq(ns.Trinkets.def[id].copyable, false)
    T.eq(ns.TrinketEngine.source(H.run { trinkets = { "S_COPY", id } }.trinkets, 1), nil)
  end
end)
H.test("scoring_conditions_and_stones", function()
  for _, id in ipairs({ "TWIN_FANGS", "PICKPOCKET", "TRICKS_TRADE", "DOUBLE_AGENT", "SHADOWSTEP", "TOTEMIC_RECALL" }) do
    T.eq(H.score(H.run { trinkets = { id } }, single()).total, 7, id)
  end
  for _, id in ipairs({ "TITANIC_RATIO", "HACK_SLASH", "BALANCE_POWER", "ODD_GOBLIN", "HUNTERS_MARK", "ROYAL_GUARD", "TRADE_PRINCE" }) do
    local r = H.score(H.run { trinkets = { id } }, { H.card(14, "S", "STONE") })
    T.eq(r.chips, 55, id); T.eq(r.mult, 1, id); T.eq(r.gold, 0, id)
  end
  T.eq(H.score(H.run { trinkets = { "EVENTIDE" } }, single(), nil, { isLastHand = false }).chips, 7)
  T.eq(H.score(H.run { trinkets = { "AVENGING_WRATH" } }, single()).mult, 1)
  T.eq(H.score(H.run { trinkets = { "MOUNT_HYJAL" } }, single(), nil, { discardsLeft = 1 }).mult, 1)
  T.eq(H.score(H.run { trinkets = { "SHRINK_RAY" } }, twoPair()).mult, 2)
end)
H.test("flight_path_state_and_copy_guards", function()
  H.stub { id = "S_COPY", copies = "right" }
  local run = H.run { trinkets = { "S_COPY", "FLIGHT_PATH" } }
  local r = H.score(run, { H.card(2), H.card(2, "H"), H.card(12) })
  T.eq(r.mult, 4); T.eq(r.trinketsAfter[2].state.mult, 1)
  T.eq(run.trinkets[2].state.mult, 0)
  run.trinkets = r.trinketsAfter
  r = H.score(run, { H.card(12) })
  T.eq(r.mult, 1); T.eq(r.trinketsAfter[2].state.mult, 0)
  r = H.score(H.run { trinkets = { "FLIGHT_PATH", "MIND_VISION" } }, single())
  T.eq(r.mult, 1)
  run = H.run { trinkets = { "S_COPY", "BLOODLUST" } }
  run.trinkets[2].state.hands = 4
  r = H.score(run, single())
  T.eq(r.mult, 1); T.eq(r.trinketsAfter[2].state.hands, 5)
  run.trinkets = r.trinketsAfter
  r = H.score(run, single())
  T.eq(r.mult, 16); T.eq(r.trinketsAfter[2].state.hands, 6)
end)
H.test("stencil_counts_instances_and_empty_slots", function()
  local run = H.run { trinkets = { "SPIRIT_HEALER", "SPIRIT_HEALER", "ARCANE_INTELLECT" } }
  T.eq(H.score(run, single()).mult, 20)
  run = H.run { trinkets = { "SPIRIT_HEALER", "ARCANE_INTELLECT", "ARCANE_INTELLECT", "ARCANE_INTELLECT", "ARCANE_INTELLECT" } }
  T.eq(H.score(run, single()).mult, 17)
end)
H.test("remap_rarity_cost", function()
  local expected = {
    ARCANE_INTELLECT = { "common", 2 }, JEWELERS_KIT = { "common", 5 },
    HEALTHSTONE = { "common", 5 }, WHETSTONE = { "common", 5 }, OGRE_CUDGEL = { "common", 5 },
    TWIN_BLADES = { "common", 3 }, CLEAVE = { "common", 4 }, MULTI_SHOT = { "common", 4 },
    ELEMENTAL = { "common", 4 }, COMBO_POINTS = { "common", 5 }, BLOODLUST = { "uncommon", 5 },
    LUCKY_CHARM = { "common", 4 }, ROYAL_GUARD = { "common", 4 }, BATTLE_SHOUT = { "common", 4 },
    HUNTERS_MARK = { "common", 4 }, FORTITUDE = { "common", 5 }, AVENGING_WRATH = { "uncommon", 6 },
    HEARTHSTONE = { "common", 6 }, EXECUTE = { "uncommon", 6 }, GOBLIN_BANK = { "uncommon", 7 },
  }
  for id, want in pairs(expected) do
    local d = ns.Trinkets.def[id]
    T.eq({ d.rarity, d.cost }, want, id)
  end
end)

H.test("bot_passes_wave1_scoring_context", function()
  local run = H.run { trinkets = { "FORTITUDE", "STARFALL", "AVENGING_WRATH", "SPIRIT_HEALER", "BLOODLUST" } }
  run.hand, run.pile = single(), {}
  for i = 1, 17 do run.pile[i] = H.card(3) end
  run.handPlays.HIGH_CARD, run.roundHandPlays.HIGH_CARD = 3, 1
  run.trinkets[5].state.hands = 4
  local bot = dofile("tools/sim/bot.lua")(ns)
  local rng = run.rng.s
  local total, idx = bot.bestPlay(run)
  T.eq(total, 615) -- (5 + 2 + 2*17) * (1 + 4) * 3; Stencil counts itself only.
  T.eq(idx, { 1 }); T.eq(run.trinkets[5].state.hands, 4); T.eq(run.rng.s, rng)
end)
