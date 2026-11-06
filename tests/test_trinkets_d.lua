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
  T.eq(H.score(run, { c }).cardsAfter[c.id].bonusChips, 10)
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

H.test("chronomancy_requires_scoring_ace", function()
  local run = H.run { trinkets = { "CHRONOMANCY", "SLEIGHT_HAND" } }
  local cards = { H.card(5), H.card(6, "H"), H.card(7), H.card(8, "H"), H.card(14) }
  local r = H.score(run, cards)
  T.eq(r.handId, "STRAIGHT")
  T.eq(#created(r, "createConsumable"), 0)
end)
H.test("GLAD_MEDALLION_effect", function()
  local run = H.run { trinkets = { "GLAD_MEDALLION" } }
  run.blind, run.bosses[1] = 3, "HOGGER"
  T.ok(ns.Run.sellTrinket(run, 1))
  T.eq(run.bossDisabled, true); T.eq(ns.Run.activeBoss(run), nil)
  local msg
  for _, e in ipairs(run.lifecycleEvents) do if e.kind == "trinketMsg" then msg = e.text end end
  T.eq(msg, nil, "the bossDisabled event floats it, not a trinketMsg")
  local disabled = 0
  for _, e in ipairs(run.lifecycleEvents) do if e.kind == "bossDisabled" then disabled = disabled + 1 end end
  T.eq(disabled, 1)
end)
H.test("luchador_only_in_boss", function()
  for _, phase in ipairs({ "play", "shop", "blind" }) do
    for blind = 1, 3 do
      local run = H.run { trinkets = { "GLAD_MEDALLION" } }
      run.phase, run.blind = phase, blind
      local def = assert(ns.Trinkets.def.GLAD_MEDALLION)
      T.eq(def.onSelfSold(run, run.trinkets[1]), phase == "play" and blind == 3
        and { disableBoss = true } or nil)
    end
  end
end)
H.test("SANDSTORM_effect", function()
  local run = H.run { trinkets = { "SANDSTORM" } }
  run.startDeckSize = 3
  for n = 0, 4 do
    run.deck = {}
    for i = 1, n do run.deck[i] = H.card(2) end
    T.eq(H.score(run, single()).mult, 1 + 4 * math.max(0, 3 - n))
  end
end)
H.test("DREAMWALKER_effect", function()
  for _, loaded in ipairs({ false, true }) do
    local ids = { "DREAMWALKER" }
    if loaded then ids[2] = "LOADED_DICE" end
    local run = H.run { trinkets = ids }
    run.rng = ns.RNG.new(70000)
    local expected = { s = run.rng.s }
    ns.RNG.next(expected)
    ns.TrinketEngine.fire(run, "onPackOpened", { kind = "celestial" })
    T.eq(#run.consumables, loaded and 1 or 0)
    if loaded then T.eq(run.consumables[1].kind, "scroll") else T.eq(run.rng.s, expected.s) end
  end
  local run = H.run { trinkets = { "SCHEMATIC", "DREAMWALKER", "LOADED_DICE" } }
  ns.TrinketEngine.fire(run, "onPackOpened", {})
  T.eq(#run.consumables, 2)
  ns.TrinketEngine.fire(run, "onPackOpened", {})
  T.eq(#run.consumables, 2)
end)
H.test("DREAMWALKER_full_slots_no_roll", function()
  local run = H.run { trinkets = { "DREAMWALKER", "LOADED_DICE" } }
  for i = 1, ns.Consumables.slots(run) do run.consumables[i] = { kind = "scroll", id = "X" } end
  run.rng = ns.RNG.new(70000)
  local before = run.rng.s
  ns.TrinketEngine.fire(run, "onPackOpened", { kind = "celestial" })
  T.eq(run.rng.s, before)
  T.eq(#run.consumables, ns.Consumables.slots(run))
end)
H.test("SEER_effect", function()
  local run = H.run { trinkets = { "SEER" } }
  T.eq(H.score(run, single()).mult, 1)
  run.usage.scroll, run.usage.tome = 7, 100
  T.eq(H.score(run, single()).mult, 8)
  T.eq(run.usage.scroll, 7)
end)
H.test("EARTHEN_RING_effect", function()
  local run = H.run { trinkets = { "EARTHEN_RING" } }
  run.deck = { H.card(2, "H", "STONE"), H.card(3, "D", "STONE"), H.card(4) }
  T.eq(H.score(run, single()).chips, 57)
  run.deck = {}; T.eq(H.score(run, single()).chips, 7)
end)
H.test("FORTUNE_CAT_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "FORTUNE_CAT" } }
  local r = H.score(run, single(2, "LUCKY"), nil, { rng = ns.RNG.new(1) })
  T.eq(r.luckyTriggers, 1)
  T.eq(r.trinketsAfter[2].state.x, 1.25)
  near(r.mult, 21 * 1.25 * 1.25)
  T.eq(run.trinkets[2].state.x, 1)
  r = H.score(run, single(2, "LUCKY"), nil, { rng = ns.RNG.new(100000) })
  T.eq(r.luckyTriggers, 0); T.eq(r.trinketsAfter[2].state.x, 1)
end)
H.test("GOLDEN_TICKET_effect", function()
  local run = H.run { trinkets = { "GOLDEN_TICKET", "ECHO_DOOM" } }
  T.eq(H.score(run, single(2, "GOLD")).gold, 12)
  T.eq(H.score(run, single()).gold, 0)
  T.eq(H.score(run, { H.card(2, "S", "GOLD"), H.card(14) }).gold, 0)
  T.eq(H.score(run, single(2, "GOLD"), nil, { bossId = "VANCLEEF" }).gold, 0)
end)
H.test("COMMENDATION_effect", function()
  local run = H.run { trinkets = { "COMMENDATION" } }
  ns.Run.startBlind(run)
  T.eq(#run.deck, 53); T.eq(#run.hand, ns.Deck.handSize(run) + 1)
  local c = run.deck[53]
  T.ok(c.rank >= 2 and c.rank <= 14); T.ok(ns.Cards.SUIT_NAMES[c.suit])
  T.ok(({ GOLD = true, RED = true, BLUE = true, PURPLE = true })[c.seal])
  T.eq(c.enh, nil); T.eq(c.ed, nil)
  local n = #run.deck
  ns.Run.discard(run, { 1 }); T.eq(#run.deck, n)
end)
H.test("certificate_card_permanent", function()
  local run = H.run { trinkets = { "SCHEMATIC", "COMMENDATION", "PHANTASM" } }
  ns.Run.startBlind(run)
  T.eq(#run.deck, 54); T.eq(run.trinkets[3].state.x, 1.5)
  local c = run.deck[53]
  T.ok(c == ns.Deck.find(run, c.id)); T.ok(run.deck[54].id ~= c.id)
  run.blind = 2; ns.Run.startBlind(run)
  T.eq(#run.deck, 56); T.ok(ns.Deck.find(run, c.id) == c)
end)
H.test("GLASS_CANNON_effect", function()
  local run = H.run { trinkets = { "SCHEMATIC", "GLASS_CANNON" } }
  T.eq(H.score(run, single()).mult, 1)
  run.deck = { H.card(2, "S", "GLASS"), H.card(3), H.card(4, "H", "GLASS") }
  local ids = { run.deck[1].id, run.deck[2].id, run.deck[3].id }
  for _, id in ipairs(ids) do ns.Deck.destroy(run, id) end
  ns.TrinketEngine.flushCards(run)
  T.eq(run.trinkets[2].state.x, 2.5)
  T.eq(H.score(run, single()).mult, 6.25)
  ns.TrinketEngine.flushCards(run); T.eq(run.trinkets[2].state.x, 2.5)
end)
H.test("glass_joker_counts_breaks", function()
  local run = H.run { trinkets = { "GLASS_CANNON" } }
  run.rng = ns.RNG.new(1)
  local r = play(run, single(2, "GLASS"))
  T.eq(#r.destroyed, 1); T.eq(#run.deck, 0)
  T.eq(r.mult, 2); T.eq(run.trinkets[1].state.x, 1.75)
end)
H.test("ARENA_CHAMPION_effect", function()
  local run = H.run { trinkets = { "ARENA_CHAMPION" } }
  for _, bossId in ipairs({ "HOGGER", "RIVENDARE" }) do
    local r = H.score(run, single(12), nil, { bossId = bossId })
    T.eq(r.bossTriggered, true); T.eq(r.gold, 8)
  end
end)
H.test("matador_only_when_triggered", function()
  local run = H.run { trinkets = { "ARENA_CHAMPION" } }
  for _, bossId in ipairs({ "HOGGER", "MUTANUS", "HEROD", "ONYXIA", "RAGNAROS" }) do
    local r = H.score(run, single(2), { H.card(12, "H", "STEEL") }, { bossId = bossId })
    T.eq(r.bossTriggered, false); T.eq(r.gold, 0)
  end
  T.eq(H.score(run, single()).gold, 0)
  local r = H.score(run, { H.card(2), H.card(2, "H"), H.card(12) }, nil, { bossId = "HOGGER" })
  T.eq(r.gold, 0)
  run = H.run { trinkets = { "SCHEMATIC", "ARENA_CHAMPION" } }
  T.eq(H.score(run, single(12), nil, { bossId = "HOGGER" }).gold, 16)
  run.blind, run.bosses[1] = 3, "HOGGER"
  ns.Run.disableBoss(run); T.eq(H.score(run, single(12)).gold, 0)
end)
H.test("MAGE_TOWER_effect", function()
  local run = H.run { trinkets = { "MAGE_TOWER" } }
  run.usage.tomeIds = { PAIR = true, FLUSH = true }
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.trinkets, 2)
  T.eq(run.lastPayout.trinketLines[1].gold, 2)
end)
H.test("satellite_unique_tomes", function()
  local run = H.run { trinkets = { "SCHEMATIC", "MAGE_TOWER" } }
  local def = assert(ns.Trinkets.def.MAGE_TOWER)
  T.eq(def.onRoundEnd(run, run.trinkets[2]), 0)
  run.usage.tome, run.usage.scroll = 20, 30
  run.usage.tomeIds = { PAIR = true, FLUSH = true }
  T.eq(def.onRoundEnd(run, run.trinkets[2]), 2)
  ns.Run.winBlind(run); T.eq(run.lastPayout.trinkets, 2)
end)
H.test("MASTER_RIDING_effect", function()
  local run = H.run { trinkets = { "MASTER_RIDING" } }
  for _, n in ipairs({ 15, 16, 17 }) do
    run.deck = {}
    for i = 1, n do run.deck[i] = H.card(2, "S", i % 2 == 0 and "STONE" or "BONUS") end
    run.deck[n + 1] = H.card(3, "H", nil, "FOIL", "RED")
    T.eq(H.score(run, single()).mult, n >= 16 and 3 or 1)
  end
end)
H.test("INSCRIPTIONIST_effect", function()
  for _, room in ipairs({ 0, 1, 2 }) do
    local run = H.run { trinkets = { "SCHEMATIC", "INSCRIPTIONIST" } }
    run.maxConsumables = room
    ns.Run.startBlind(run)
    T.eq(#run.consumables, room)
    for _, item in ipairs(run.consumables) do T.eq(item.kind, "scroll") end
  end
end)
H.test("d_part_b_pool_and_copy_gates", function()
  for id, enh in pairs({ EARTHEN_RING = "STONE", FORTUNE_CAT = "LUCKY", GOLDEN_TICKET = "GOLD", GLASS_CANNON = "GLASS" }) do
    local run = H.run()
    T.ok(ns.Trinkets.def[id], id)
    T.eq(ns.Trinkets.inPool(run, id), false)
    run.deck[1].enh = enh
    T.eq(ns.Trinkets.inPool(run, id), true)
  end
  for _, id in ipairs({ "GLAD_MEDALLION", "MAGE_TOWER" }) do
    local run = H.run { trinkets = { "SCHEMATIC", id } }
    T.eq(ns.TrinketEngine.source(run.trinkets, 1), nil)
  end
end)

H.test("IRONFORGE_ANVIL_same_hand_deck_parity", function()
  local run = H.run { trinkets = { "VAMPIRIC", "IRONFORGE_ANVIL" } }
  local played = H.card(9, "S", "STEEL")
  run.deck = { played, H.card(3, "H", "STEEL"), H.card(4, "D") }
  -- Vampiric Embrace strips the played Steel in `before`, so the Anvil sees one Steel (x1.2), not two (x1.4).
  local r = H.score(run, { played })
  local xs = {}
  for _, e in ipairs(r.events) do
    if e.kind == "trinket" and e.xmult and e.slot == 2 then xs[#xs + 1] = e.xmult end
  end
  T.eq(#xs, 1)
  near(xs[1], 1.2)
  T.eq(played.enh, "STEEL", "run.deck untouched")
  T.eq(run.deck[1], played)
  T.eq(#run.deck, 3)
end)
H.test("deckCards_hook_sees_scratch_copy", function()
  local run = H.run()
  local played, held = H.card(9, "S", "STEEL"), H.card(5, "H", "GOLD")
  run.deck = { played, held, H.card(4, "D") }
  local seen
  H.stub({ id = "S_PEEK",
    before = function(ctx) ctx.cards[1].enh = nil; ctx.held[1].enh = nil end,
    onHand = function(ctx) seen = ctx.deckCards end })
  run.trinkets[1] = ns.Trinkets.create(run, "S_PEEK")
  H.score(run, { played }, { held })
  T.eq(#seen, 3)
  T.eq(seen[1].enh, nil); T.eq(seen[2].enh, nil)
  T.eq(played.enh, "STEEL"); T.eq(held.enh, "GOLD")
end)
