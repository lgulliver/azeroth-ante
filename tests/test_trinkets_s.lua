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

-- Part B: literal totals catch missing hooks, wrong amounts and wrong scoring phases.
local partBCases = {
  { "DARK_PACT", single, 7, 3 },
  { "SPRINT", straight, 65, 4 },
  { "TIGULES", single, 107, 1 },
  { "FOUR_WINDS", twoPair, 34, 2 },
  { "PORTAL", function() return { H.card(2), H.card(4, "H"), H.card(6), H.card(8), H.card(10) } end, 60, 4 },
  { "CROWN_KINGS", single, 7, 1.5, { H.card(13) } },
  { "OBELISK", single, 7, 1.2, nil, { handPlays = { PAIR = 3 } } },
  { "SELFIE_CAMERA", function() return { H.card(12) } end, 15, 2 },
  { "GUILD_CHARTER", single, 7, 1 },
  { "TAUREN_CHARGE", single, 31, 1, nil, nil, 12 },
  { "SPARE_TABARD", twoPair, 30, 4 },
  { "GOBLIN_RADIO", function() return { H.card(10) } end, 25, 5 },
  { "MORNING_DEW", single, 9, 1 },
  { "CHEERFUL_GNOME", function() return { H.card(12) } end, 15, 6 },
  { "COURT_JESTER", function() return { H.card(12) } end, 25, 1 },
  { "BLOODSAIL", single, 7, 1 },
  { "MURKY_INK", function() return { H.card(2), H.card(4, "C"), H.card(6), H.card(8, "C"), H.card(10) } end, 65, 4 },
  { "ECHO_DOOM", single, 11, 1 },
  { "ARROWHEAD", single, 57, 1 },
  { "SHADOWGEM", function() return { H.card(2, "C") } end, 7, 8 },
  { "PEACEBLOOM", function() return { H.card(2, "D"), H.card(2, "C"), H.card(2, "H"), H.card(2, "S") } end, 68, 21 },
  { "TINY_GNOME", single, 15, 1 },
  { "DOUBLE_VISION", function() return { H.card(2, "C"), H.card(2, "S") } end, 14, 4 },
  { "TWIN_VALKYR", pair, 14, 4 },
  { "COUNCIL_THREE", triple, 36, 9 },
  { "FOUR_HORSEMEN", function() return { H.card(2), H.card(2, "H"), H.card(2, "C"), H.card(2, "D") } end, 68, 28 },
  { "SILVER_HAND", straight, 50, 12 },
  { "THE_HORDE", flush, 65, 8 },
  { "MOONFIRE", single, 7, 14, { H.card(12) } },
}
for _, case in ipairs(partBCases) do
  H.test(case[1] .. "_effect", function()
    T.ok(ns.Trinkets.def[case[1]], "missing " .. case[1])
    local r = H.score(H.run { trinkets = { case[1] }, gold = case[7] }, case[2](), case[5], case[6])
    T.eq(r.chips, case[3]); T.eq(r.mult, case[4]); T.eq(r.total, math.floor(case[3] * case[4]))
  end)
end

H.test("STABLE_MASTER_effect", function()
  local run = H.run { trinkets = { "STABLE_MASTER" } }
  run.rng = ns.RNG.new(1)
  T.eq(H.score(run, single(), { H.card(12) }).gold, 1)
  run.rng = ns.RNG.new(64000)
  T.eq(H.score(run, single(), { H.card(12) }).gold, 0)
end)
H.test("UNCUT_GEM_effect", function()
  T.eq(H.score(H.run { trinkets = { "UNCUT_GEM" } }, { H.card(2, "D", nil, nil, "RED") }).gold, 2)
end)
H.test("BLOODSTONE_effect", function()
  for _, case in ipairs({ { 1, 1.5 }, { 64000, 1 } }) do
    local run = H.run { trinkets = { "BLOODSTONE" } }
    run.rng = ns.RNG.new(case[1])
    T.eq(H.score(run, { H.card(2, "H") }).mult, case[2])
  end
end)
H.test("LOADED_DICE_effect", function()
  local run = H.run { trinkets = { "LOADED_DICE", "LOADED_DICE" } }
  T.eq(ns.Prob.odds(run.trinkets, 1), 4)
end)
for _, id in ipairs({ "SCHEMATIC", "MIND_CONTROL" }) do
  H.test(id .. "_effect", function()
    T.ok(ns.Trinkets.def[id], "missing " .. id)
    local ids = id == "SCHEMATIC" and { id, "ARCANE_INTELLECT" } or { "ARCANE_INTELLECT", id }
    T.eq(H.score(H.run { trinkets = ids }, single()).mult, 9)
  end)
end
H.test("TITAN_RELIC_effect", function()
  local run = H.run { trinkets = { "TITAN_RELIC" } }
  local self = run.trinkets[1]
  T.ok(ns.Cards.SUIT_NAMES[self.state.suit])
  T.eq(H.score(run, { H.card(2, self.state.suit) }).mult, 1.5)
  T.eq(ns.Trinkets.def.TITAN_RELIC.status(self), "Suit: " .. ns.Cards.SUIT_NAMES[self.state.suit])
end)
H.test("ZANDALARI_IDOL_effect", function()
  local run = H.run { trinkets = { "ZANDALARI_IDOL" } }
  local self = run.trinkets[1]
  T.ok(self.state.rank and ns.Cards.SUIT_NAMES[self.state.suit])
  T.eq(H.score(run, { H.card(self.state.rank, self.state.suit) }).mult, 2)
  T.eq(H.score(run, { H.card(self.state.rank, self.state.suit, "STONE") }).mult, 1)
  T.eq(H.score(run, { H.card(self.state.rank == 2 and 3 or 2, self.state.suit) }).mult, 1)
end)

H.test("ice_cream_melts", function()
  local run = H.run { trinkets = { "SCHEMATIC", "TIGULES" } }
  for hand = 1, 20 do
    local r = H.score(run, single())
    T.eq(r.chips, 7 + 2 * (105 - 5 * hand))
    T.eq(run.trinkets[2].state.chips, 105 - 5 * hand)
    if hand < 20 then T.eq(r.trinketsAfter[2].state.chips, 100 - 5 * hand)
    else
      T.eq(#r.trinketsAfter, 1); T.eq(r.destroyedTrinkets, { 2 })
      T.eq(r.events[#r.events - 1].msg, "Melted!")
    end
    run.trinkets = r.trinketsAfter
  end
end)
H.test("seltzer_ten_hands", function()
  local run = H.run { trinkets = { "SCHEMATIC", "MORNING_DEW" } }
  for hand = 1, 10 do
    local r = H.score(run, single())
    T.eq(r.chips, 11)
    if hand < 10 then T.eq(r.trinketsAfter[2].state.left, 10 - hand)
    else
      T.eq(#r.trinketsAfter, 1); T.eq(r.destroyedTrinkets, { 2 })
      T.eq(r.events[#r.events - 1].msg, "Drunk!")
    end
    run.trinkets = r.trinketsAfter
  end
  T.eq(H.score(run, single()).chips, 7)
end)
H.test("blueprint_wee_joker_no_double_scale", function()
  local run = H.run { trinkets = { "SCHEMATIC", "TINY_GNOME", "ECHO_DOOM" } }
  local r = H.score(run, single())
  T.eq(r.chips, 59); T.eq(r.trinketsAfter[2].state.chips, 24)
  T.eq(run.trinkets[2].state.chips, 0)
  local upgrades = 0
  for _, event in ipairs(r.events) do
    if event.msg == "Upgrade!" then upgrades = upgrades + 1; T.eq(event.uid, 2) end
  end
  T.eq(upgrades, 3)
end)
H.test("brainstorm_copies_baseball", function()
  local run = H.run { trinkets = { "GUILD_CHARTER", "ARCANE_INTELLECT", "MURKY_INK", "LOADED_DICE", "MIND_CONTROL" } }
  T.eq(H.score(run, single()).mult, 25.3125) -- (1 + 4) * 1.5^4, twice per Uncommon.
end)
H.test("copier_chains_and_cycles", function()
  T.eq(H.score(H.run { trinkets = { "SCHEMATIC", "SCHEMATIC", "ARCANE_INTELLECT", "MIND_CONTROL" } }, single()).mult, 17)
  T.eq(H.score(H.run { trinkets = { "SCHEMATIC", "MIND_CONTROL" } }, single()).mult, 1)
end)
H.test("obelisk_resets", function()
  local run = H.run { trinkets = { "SCHEMATIC", "OBELISK" } }
  local r = H.score(run, single(), nil, { handPlays = { PAIR = 3 } })
  T.eq(r.trinketsAfter[2].state.x, 1.2); T.eq(r.mult, 1.44)
  r = H.score(run, single(), nil, { handPlays = { HIGH_CARD = 2, PAIR = 3 } })
  T.eq(r.trinketsAfter[2].state.x, 1.2); T.eq(r.mult, 1.44)
  run.trinkets = r.trinketsAfter
  r = H.score(run, single(), nil, { handPlays = { HIGH_CARD = 3, PAIR = 3 } })
  T.eq(r.trinketsAfter[2].state.x, 1); T.eq(r.mult, 1)
  T.eq(H.score(H.run { trinkets = { "OBELISK" } }, single()).mult, 1)
end)
H.test("scalers_pay_current_hand_without_copy_scaling", function()
  for _, case in ipairs({ { "SPRINT", straight, 80, "chips", 15 },
      { "FOUR_WINDS", twoPair, 38, "chips", 4 }, { "SPARE_TABARD", twoPair, 30, "mult", 2 } }) do
    local run = H.run { trinkets = { "SCHEMATIC", case[1] } }
    local r = H.score(run, case[2]())
    T.eq(r.chips, case[3]); T.eq(r.trinketsAfter[2].state[case[4]], case[5])
    T.eq(run.trinkets[2].state[case[4]], 0)
    if case[1] == "SPARE_TABARD" then T.eq(r.mult, 6) end
    run.trinkets = r.trinketsAfter
    local nextResult = H.score(run, single())
    T.eq(nextResult.trinketsAfter[2].state[case[4]], case[5])
  end
end)
H.test("idol_reroll_round_end", function()
  local run = H.run()
  run.deck = { H.card(14, "S", "STONE"), H.card(12, "D") }
  run.trinkets = { ns.Trinkets.create(run, "ZANDALARI_IDOL") }
  local self, def = run.trinkets[1], ns.Trinkets.def.ZANDALARI_IDOL
  T.eq({ self.state.rank, self.state.suit }, { 12, "D" })
  run.deck = { H.card(3, "H") }
  local rng = run.rng.s
  T.eq(def.onRoundEnd(run, self, true), nil); T.eq(run.rng.s, rng)
  T.eq({ self.state.rank, self.state.suit }, { 12, "D" })
  ns.Run.winBlind(run)
  T.eq({ self.state.rank, self.state.suit }, { 3, "H" })
  T.eq(def.status(self), "Card: 3 of Hearts")
  run.deck = { H.card(2, "S", "STONE") }
  T.eq(def.onRoundEnd(run, self, false), nil)
  T.eq(H.score(run, single()).mult, 1)
end)
H.test("ancient_reroll_round_end", function()
  local run = H.run { trinkets = { "TITAN_RELIC" } }
  local self, def = run.trinkets[1], ns.Trinkets.def.TITAN_RELIC
  local suit, rng = self.state.suit, run.rng.s
  T.eq(def.onRoundEnd(run, self, true), nil); T.eq(run.rng.s, rng); T.eq(self.state.suit, suit)
  run.rng = ns.RNG.new(1)
  T.eq(def.onRoundEnd(run, self, false), nil); T.eq(self.state.suit, "S")
  run.rng = ns.RNG.new(64000)
  T.eq(def.onRoundEnd(run, self, false), nil); T.eq(self.state.suit, "C")
end)
H.test("oops_doubles_bloodstone", function()
  local plain = H.run { trinkets = { "BLOODSTONE" } }
  local loaded = H.run { trinkets = { "BLOODSTONE", "LOADED_DICE" } }
  local nextRng = ns.RNG.next
  local ok, err = pcall(function()
    local draws = 0
    ns.RNG.next = function() draws = draws + 1; return 0.6 end
    T.eq(H.score(plain, { H.card(2, "H") }).mult, 1)
    T.eq(H.score(loaded, { H.card(2, "H") }).mult, 1.5)
    T.eq(draws, 2)
  end)
  ns.RNG.next = nextRng
  if not ok then error(err, 0) end
end)
H.test("flower_pot_assigns_distinct_cards", function()
  local function score(cards, extra)
    local ids = { "PEACEBLOOM" }
    if extra then ids[#ids + 1] = extra end
    return H.score(H.run { trinkets = ids }, cards).mult
  end
  T.eq(score({ H.card(2, "D"), H.card(2, "C"), H.card(2, "H"), H.card(2, "H", "WILD") }), 21)
  T.eq(score({ H.card(2, "D", "WILD"), H.card(2, "C"), H.card(2, "H"), H.card(2, "D") }), 21)
  T.eq(score({ H.card(2, "S", "WILD"), H.card(2, "S", "WILD"), H.card(2, "S", "WILD"), H.card(2, "S", "WILD") }), 21)
  T.eq(score({ H.card(2, "D"), H.card(2, "C"), H.card(2, "H"), H.card(2, "S", "STONE") }), 3)
  T.eq(score({ H.card(2, "S", "WILD") }), 1)
  T.eq(score({ H.card(2, "D"), H.card(2, "C"), H.card(3, "H"), H.card(4, "S") }), 2)
  T.eq(score({ H.card(2, "S"), H.card(2, "S"), H.card(2, "H"), H.card(2, "H") }, "MURKY_INK"), 21)
end)
H.test("seeing_double_needs_distinct_scoring_cards", function()
  local function score(cards, ids) return H.score(H.run { trinkets = ids or { "DOUBLE_VISION" } }, cards).mult end
  T.eq(score({ H.card(2, "C", "WILD") }), 1)
  T.eq(score({ H.card(2, "C", "WILD"), H.card(2, "C") }), 4)
  T.eq(score({ H.card(2, "C"), H.card(2, "C") }), 2)
  T.eq(score({ H.card(2, "C"), H.card(3, "D") }), 1)
  T.eq(score({ H.card(2, "C"), H.card(2, "S", "STONE") }), 1)
  T.eq(score({ H.card(2, "S"), H.card(2, "S") }, { "DOUBLE_VISION", "MURKY_INK" }), 4)
end)
H.test("photograph_first_face_every_trigger", function()
  local cards = { H.card(2), H.card(12), H.card(12, "H", nil, nil, "RED") }
  local r = H.score(H.run { trinkets = { "SELFIE_CAMERA", "COURT_JESTER" } }, cards)
  T.eq(r.mult, 8) -- Pair base 2, first Queen triggers twice; later Queen never multiplies.
  T.eq(H.score(H.run { trinkets = { "SELFIE_CAMERA", "MIND_VISION", "ECHO_DOOM" } }, single()).mult, 8)
  T.eq(H.score(H.run { trinkets = { "SELFIE_CAMERA" } }, { H.card(13, "S", "STONE") }).mult, 1)
end)
H.test("held_rank_suit_and_face_rules", function()
  local ids = { "DARK_PACT" }
  T.eq(H.score(H.run { trinkets = ids }, single(), { H.card(2, "H", "WILD") }).mult, 3)
  T.eq(H.score(H.run { trinkets = ids }, single(), { H.card(2, "S", "STONE") }).mult, 1)
  T.eq(H.score(H.run { trinkets = ids }, single(), { H.card(2, "D") }).mult, 1)
  for _, id in ipairs({ "CROWN_KINGS", "MOONFIRE" }) do
    T.eq(H.score(H.run { trinkets = { id, "MIND_VISION" } }, single(), { H.card(2) }).mult, 1)
    T.eq(H.score(H.run { trinkets = { id } }, single(), { H.card(id == "MOONFIRE" and 12 or 13, "S", "STONE") }).mult, 1)
  end
  local run = H.run { trinkets = { "CROWN_KINGS", "MIRROR_IMAGE" } }
  T.eq(H.score(run, single(), { H.card(13, "S", nil, nil, "RED") }).mult, 3.375)
  run = H.run { trinkets = { "STABLE_MASTER", "MIND_VISION" } }; run.rng = ns.RNG.new(1)
  T.eq(H.score(run, single(), { H.card(2) }).gold, 1)
end)
H.test("suit_effects_use_rules_and_ignore_stones", function()
  for _, case in ipairs({ { "UNCUT_GEM", "H", "gold", 1 }, { "ARROWHEAD", "C", "chips", 57 },
      { "SHADOWGEM", "S", "mult", 8 } }) do
    local r = H.score(H.run { trinkets = { case[1], "MURKY_INK" } }, { H.card(2, case[2]) })
    T.eq(r[case[3]], case[4])
  end
  for _, id in ipairs({ "UNCUT_GEM", "BLOODSTONE", "ARROWHEAD", "SHADOWGEM", "GOBLIN_RADIO", "CHEERFUL_GNOME", "TINY_GNOME", "COURT_JESTER" }) do
    local r = H.score(H.run { trinkets = { id, "MIND_VISION" } }, { H.card(4, "D", "STONE") })
    T.eq(r.chips, 55, id); T.eq(r.mult, 1, id); T.eq(r.gold, 0, id)
  end
end)
H.test("bull_and_swashbuckler_live_values", function()
  T.eq(H.score(H.run { trinkets = { "UNCUT_GEM", "TAUREN_CHARGE" }, gold = 0 }, { H.card(2, "D") }).chips, 9)
  T.eq(H.score(H.run { trinkets = { "TAUREN_CHARGE" }, gold = -10 }, single()).chips, 7)
  local run = H.run { trinkets = { "BLOODSAIL", "ARCANE_INTELLECT", "SCHEMATIC" } }
  run.trinkets[2].paid, run.trinkets[2].sellBonus = 10, 3
  run.trinkets[3].ed = "FOIL"
  T.eq(H.score(run, single()).mult, 19) -- 1 + (8 + 6) + 4; Blueprint has no target.
end)
H.test("part_b_rules_incompatible", function()
  for _, id in ipairs({ "PORTAL", "MURKY_INK", "LOADED_DICE" }) do
    T.eq(ns.Trinkets.def[id].copyable, false)
    T.eq(ns.TrinketEngine.source(H.run { trinkets = { "SCHEMATIC", id } }.trinkets, 1), nil)
  end
end)
H.test("bot_handles_every_part_b_trinket", function()
  local bot = dofile("tools/sim/bot.lua")(ns)
  local ids = { "STABLE_MASTER", "UNCUT_GEM", "BLOODSTONE", "LOADED_DICE", "SCHEMATIC", "MIND_CONTROL", "TITAN_RELIC", "ZANDALARI_IDOL" }
  for _, case in ipairs(partBCases) do ids[#ids + 1] = case[1] end
  for _, id in ipairs(ids) do
    T.ok(ns.Trinkets.def[id], "missing " .. id)
    local run = H.run { trinkets = { id } }
    run.hand = { H.card(2), H.card(2, "H"), H.card(12, "C") }
    local rng = run.rng.s
    local total, idx = bot.bestPlay(run)
    T.ok(total > 0, id); T.ok(#idx > 0, id); T.eq(run.rng.s, rng, id)
  end
end)
H.test("part_b_hand_conditions_do_not_fire_without_matching_hand", function()
  for _, id in ipairs({ "TWIN_VALKYR", "COUNCIL_THREE", "FOUR_HORSEMEN", "SILVER_HAND", "THE_HORDE" }) do
    T.eq(H.score(H.run { trinkets = { id } }, single()).mult, 1, id)
  end
end)
H.test("echo_retriggers_first_scoring_index_not_first_played", function()
  local cards = { H.card(2), H.card(12), H.card(12, "H") }
  local r = H.score(H.run { trinkets = { "ECHO_DOOM" } }, cards)
  T.eq(r.chips, 50); T.eq(r.mult, 2)
  local indexes = {}
  for _, event in ipairs(r.events) do
    if event.kind == "retrigger" then indexes[#indexes + 1] = event.index end
  end
  T.eq(indexes, { 2, 2 })
end)
