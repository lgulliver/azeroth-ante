local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function near(actual, expected)
  T.ok(math.abs(actual - expected) < 1e-9, tostring(actual) .. " ~= " .. tostring(expected))
end
local function single(rank, enh) return { H.card(rank or 2, "S", enh) } end
local function created(result, kind)
  local out = {}
  for _, fx in ipairs(result.sideEffects) do
    if fx.kind == kind then out[#out + 1] = fx end
  end
  return out
end
local function play(run, cards)
  run.hand, run.deck, run.pile, run.target = {}, {}, {}, 1000000
  for i, card in ipairs(cards) do run.hand[i], run.deck[i] = card, card end
  local idx = {}
  for i = 1, #cards do idx[i] = i end
  return assert(ns.Run.play(run, idx))
end
local function straight(ace, flush)
  local cards = {}
  for i = 1, 5 do cards[i] = H.card((ace and 9 or 1) + i, (flush or i % 2 == 0) and "S" or "H") end
  return cards
end

H.test("STONEFORM_effect", function()
  local run = H.run { trinkets = { "STONEFORM" } }
  ns.Run.startBlind(run)
  T.eq(#run.deck, 53)
  local card = run.deck[53]
  T.eq(card.enh, "STONE"); T.ok(card.rank >= 2 and card.rank <= 14)
  T.ok(ns.Cards.SUIT_NAMES[card.suit])
  local n = 0
  for _, list in ipairs({ run.hand, run.pile }) do
    for _, c in ipairs(list) do if c == card then n = n + 1 end end
  end
  T.eq(n, 1)
end)
H.test("marble_stone_drawable_same_round", function()
  local run = H.run { trinkets = { "STONEFORM" } }
  run.deck = { H.card(2) }
  ns.Run.startBlind(run)
  T.eq(#run.hand, 2); T.eq(#run.pile, 0)
  local stones = 0
  for _, c in ipairs(run.hand) do if c.enh == "STONE" then stones = stones + 1 end end
  T.eq(stones, 1)
end)
H.test("FORTUNE_CARD_effect", function()
  local run = H.run { trinkets = { "FORTUNE_CARD" } }
  local r = H.score(run, single(8), nil, { rng = ns.RNG.new(1) })
  T.eq(created(r, "createConsumable"), { { kind = "createConsumable", consumableKind = "scroll" } })
  T.eq(#run.consumables, 0)
  T.eq(#created(H.score(run, single(7)), "createConsumable"), 0)
  T.eq(#created(H.score(run, single(8, "STONE")), "createConsumable"), 0)
  T.eq(#created(H.score(run, single(8), nil, { rng = ns.RNG.new(100000) }), "createConsumable"), 0)
end)
H.test("fortune_probability_loaded_dice_and_retriggers", function()
  for _, loaded in ipairs({ false, true }) do
    local ids = { "FORTUNE_CARD" }
    if loaded then ids[2] = "LOADED_DICE" end
    local run = H.run { trinkets = ids }
    local rng = ns.RNG.new(40000)
    T.eq(#created(H.score(run, single(8), nil, { rng = rng }), "createConsumable"), loaded and 1 or 0)
    T.eq(rng.s, 672296807)
  end
  local run = H.run { trinkets = { "FORTUNE_CARD", "ECHO_DOOM" } }
  T.eq(#created(H.score(run, single(8), nil, { rng = ns.RNG.new(0) }), "createConsumable"), 2)
end)
H.test("IRONFORGE_ANVIL_effect", function()
  local run = H.run { trinkets = { "IRONFORGE_ANVIL" } }
  run.deck = { H.card(2, "H", "STEEL"), H.card(3, "D", "STEEL"), H.card(4) }
  near(H.score(run, single()).mult, 1.4)
  T.eq(ns.Trinkets.def.IRONFORGE_ANVIL.status(run.trinkets[1], run), "Currently ×1.4")
  run.deck = {}
  T.eq(H.score(run, single()).mult, 1)
end)
H.test("steel_pool_gate", function()
  local run = H.run()
  T.eq(ns.Trinkets.inPool(run, "IRONFORGE_ANVIL"), false)
  run.deck[1].enh = "STEEL"
  T.eq(ns.Trinkets.inPool(run, "IRONFORGE_ANVIL"), true)
end)
H.test("CLONING_DEVICE_effect", function()
  local run = H.run { trinkets = { "CLONING_DEVICE" } }
  local c = H.card(12, "D", "BONUS", "FOIL", "PURPLE")
  c.bonusChips = 17
  local r = H.score(run, { c })
  T.eq(created(r, "createCard"), { { kind = "createCard", toHand = true,
    card = { rank = 12, suit = "D", enh = "BONUS", ed = "FOIL", seal = "PURPLE", bonusChips = 17 } } })
  local msg
  for _, e in ipairs(r.events) do if e.kind == "trinketMsg" then msg = e.msg end end
  T.eq(msg, "Copied!"); T.eq(#run.deck, 52)
  play(run, { c })
  T.eq(#run.deck, 2); T.eq(#run.hand, 1)
  T.ok(run.hand[1].id ~= c.id); T.eq(run.hand[1].bonusChips, 17)
end)
H.test("dna_only_first_hand_single_card", function()
  local run = H.run { trinkets = { "CLONING_DEVICE" } }
  T.eq(#created(H.score(run, { H.card(2), H.card(3) }), "createCard"), 0)
  run.handsPlayedRound = 1
  T.eq(#created(H.score(run, single()), "createCard"), 0)
end)
H.test("DIVINATION_effect", function()
  for _, room in ipairs({ 0, 1 }) do
    local run = H.run { trinkets = { "DIVINATION" } }
    run.maxConsumables = room
    local c = H.card(6)
    local r = play(run, { c })
    T.eq(created(r, "destroyCard"), { { kind = "destroyCard", id = c.id } })
    T.eq(#run.deck, 0); T.eq(#run.consumables, room)
    if room > 0 then T.eq(run.consumables[1].kind, "relic") end
  end
end)
H.test("divination_only_first_single_nonstone_six", function()
  local run = H.run { trinkets = { "DIVINATION" } }
  for _, cards in ipairs({ single(5), single(6, "STONE"), { H.card(6), H.card(6, "H") } }) do
    T.eq(#H.score(run, cards).sideEffects, 0)
  end
  run.handsPlayedRound = 1
  T.eq(#H.score(run, single(6)).sideEffects, 0)
end)
H.test("STARLIGHT_CODEX_effect", function()
  local run = H.run { trinkets = { "STARLIGHT_CODEX" } }
  T.eq(H.score(run, single()).mult, 1)
  ns.TrinketEngine.fire(run, "onConsumableUsed", { kind = "tome", id = "PAIR" })
  near(H.score(run, single()).mult, 1.1)
  ns.TrinketEngine.fire(run, "onConsumableUsed", { kind = "scroll", id = "FOOL" })
  ns.TrinketEngine.fire(run, "onConsumableUsed", { kind = "relic", id = "WRAITH" })
  near(H.score(run, single()).mult, 1.1)
end)
H.test("PILGRIM_effect", function()
  local run = H.run { trinkets = { "PILGRIM" } }
  local c = H.card(2)
  local r = H.score(run, { c })
  T.eq(r.cardsAfter[c.id].bonusChips, 5); T.eq(c.bonusChips, nil)
  T.eq(r.chips, 7)
  r = H.score(run, { c, H.card(14) })
  T.eq(r.cardsAfter[c.id], nil)
end)
H.test("hiker_permanent_across_hands", function()
  local run = H.run { trinkets = { "PILGRIM" } }
  local c = H.card(2, "S", nil, nil, "RED")
  play(run, { c })
  T.eq(c.bonusChips, 10)
  local r = H.score(run, { c })
  T.eq(r.chips, 34); T.eq(r.cardsAfter[c.id].bonusChips, 20)
  T.eq(c.bonusChips, 10)
end)
H.test("CHRONOMANCY_effect", function()
  local run = H.run { trinkets = { "CHRONOMANCY" } }
  T.eq(created(H.score(run, straight(true)), "createConsumable"),
    { { kind = "createConsumable", consumableKind = "scroll" } })
  T.eq(#H.score(run, straight(false)).sideEffects, 0)
  T.eq(#H.score(run, single(14)).sideEffects, 0)
  local wheel = { H.card(14), H.card(2), H.card(3), H.card(4), H.card(5) }
  T.eq(#created(H.score(run, wheel), "createConsumable"), 1)
end)
H.test("SPEAK_DEAD_effect", function()
  local run = H.run { trinkets = { "SPEAK_DEAD" } }
  T.eq(created(H.score(run, straight(true, true)), "createConsumable"),
    { { kind = "createConsumable", consumableKind = "relic" } })
  T.eq(#H.score(run, straight(true)).sideEffects, 0)
end)
H.test("VAMPIRIC_effect", function()
  local run = H.run { trinkets = { "VAMPIRIC" } }
  local cards = { H.card(2, "S", "BONUS"), H.card(2, "H", "MULT"), H.card(14, "D", "GLASS") }
  local r = H.score(run, cards)
  near(r.mult, 2.4); near(r.trinketsAfter[1].state.x, 1.2)
  T.eq(r.cardsAfter[cards[1].id].enh, nil); T.eq(r.cardsAfter[cards[3].id], nil)
  T.eq(cards[1].enh, "BONUS"); T.eq(run.trinkets[1].state.x, 1)
end)
H.test("vampire_strips_before_scoring", function()
  local run = H.run { trinkets = { "VAMPIRIC" } }
  local c = H.card(8, "S", "GLASS")
  local r = H.score(run, { c })
  near(r.mult, 1.1); T.eq(#r.destroyed, 0); T.eq(r.chips, 13)
  T.eq(r.cardsAfter[c.id].enh, nil); T.eq(c.enh, "GLASS")
  play(run, { c }); T.eq(c.enh, nil)
end)
H.test("vampire_and_midas_respect_boss_debuff", function()
  for _, id in ipairs({ "VAMPIRIC", "GILDED_MASK" }) do
    local run = H.run { trinkets = { id } }
    local c = H.card(12, "S", "BONUS")
    local r = H.score(run, { c }, nil, { bossId = "HOGGER" })
    T.eq(r.cardsAfter[c.id], nil)
    T.eq(r.chips, 5)
    if id == "VAMPIRIC" then T.eq(r.trinketsAfter[1].state.x, 1) end
  end
end)
H.test("PHANTASM_effect", function()
  local run = H.run { trinkets = { "PHANTASM" } }
  T.eq(H.score(run, single()).mult, 1)
  ns.Deck.add(run, H.card(2)); ns.Deck.add(run, H.card(3))
  ns.TrinketEngine.flushCards(run)
  T.eq(H.score(run, single()).mult, 1.5)
  ns.TrinketEngine.flushCards(run)
  T.eq(H.score(run, single()).mult, 1.5)
  ns.Deck.destroy(run, run.deck[1].id); ns.TrinketEngine.flushCards(run)
  T.eq(H.score(run, single()).mult, 1.5)
end)
H.test("PEDDLER_effect", function()
  for _, gold in ipairs({ -1, 0, 4, 5 }) do
    local run = H.run { trinkets = { "PEDDLER" }, gold = gold }
    T.eq(#created(H.score(run, single()), "createConsumable"), gold <= 4 and 1 or 0)
  end
end)
H.test("GILDED_MASK_effect", function()
  local run = H.run { trinkets = { "GILDED_MASK" } }
  local c = H.card(12, "S", "GLASS")
  local r = H.score(run, { c })
  T.eq(r.cardsAfter[c.id].enh, "GOLD"); T.eq(r.mult, 1); T.eq(r.gold, 0)
  T.eq(c.enh, "GLASS"); T.eq(#r.destroyed, 0)
  play(run, { c }); T.eq(c.enh, "GOLD")
  T.eq(#created(r, "createConsumable"), 0)
end)
H.test("midas_rules_and_scoring_cards_only", function()
  local run = H.run { trinkets = { "GILDED_MASK", "MIND_VISION" } }
  local cards = { H.card(2), H.card(2, "H"), H.card(13, "D"), H.card(9, "C", "STONE") }
  local r = H.score(run, cards)
  T.eq(r.cardsAfter[cards[1].id].enh, "GOLD")
  T.eq(r.cardsAfter[cards[2].id].enh, "GOLD")
  T.eq(r.cardsAfter[cards[3].id], nil); T.eq(r.cardsAfter[cards[4].id], nil)
end)
H.test("d_copy_guards_and_scaling", function()
  local run = H.run { trinkets = { "SCHEMATIC", "STARLIGHT_CODEX" } }
  ns.TrinketEngine.fire(run, "onConsumableUsed", { kind = "tome", id = "PAIR" })
  near(run.trinkets[2].state.x, 1.1); near(H.score(run, single()).mult, 1.21)
  run = H.run { trinkets = { "SCHEMATIC", "PHANTASM" } }
  ns.Deck.add(run, H.card(2)); ns.TrinketEngine.flushCards(run)
  T.eq(run.trinkets[2].state.x, 1.25); T.eq(H.score(run, single()).mult, 1.5625)
  run = H.run { trinkets = { "SCHEMATIC", "PILGRIM" } }
  local c = H.card(2)
  T.eq(H.score(run, { c }).cardsAfter[c.id].bonusChips, 5)
  run = H.run { trinkets = { "SCHEMATIC", "VAMPIRIC" } }
  local r = H.score(run, single(2, "BONUS"))
  near(r.trinketsAfter[2].state.x, 1.1); near(r.mult, 1.21)
  for _, id in ipairs({ "DIVINATION", "GILDED_MASK" }) do
    run = H.run { trinkets = { "SCHEMATIC", id } }
    T.eq(ns.TrinketEngine.source(run.trinkets, 1), nil, id)
  end
end)
H.test("d_creation_copies_and_capacity", function()
  local run = H.run { trinkets = { "SCHEMATIC", "CLONING_DEVICE", "PHANTASM" } }
  play(run, single(2))
  T.eq(#run.deck, 3); T.eq(#run.hand, 2); T.eq(run.trinkets[3].state.x, 1.5)
  run = H.run { trinkets = { "SCHEMATIC", "STONEFORM", "PHANTASM" } }
  ns.Run.startBlind(run)
  T.eq(#run.deck, 54); T.eq(run.trinkets[3].state.x, 1.5)
  run = H.run { trinkets = { "SCHEMATIC", "PEDDLER" }, gold = 4 }
  run.maxConsumables = 1
  play(run, single()); T.eq(#run.consumables, 1); T.eq(run.consumables[1].kind, "scroll")
  run = H.run { trinkets = { "PEDDLER" }, gold = 4 }
  run.maxConsumables = 0
  play(run, single()); T.eq(#run.consumables, 0)
end)
