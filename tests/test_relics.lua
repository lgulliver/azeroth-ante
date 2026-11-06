local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function newRun(phase)
  local run = ns.Run.new(7, "ADVENTURER")
  if phase == "play" then ns.Run.startBlind(run) else run.phase = phase or "shop" end
  return run
end

local function relic(id) return { kind = "relic", id = id } end

-- Checks a relic is usable on cards, then applies it.
local function apply(run, id, cards)
  local item = relic(id)
  local ok, reason = ns.Consumables.canApply(run, item, cards)
  T.ok(ok, id .. ": " .. tostring(reason))
  return ns.Consumables.apply(run, item, cards)
end

local function trinket(id, ed) return { id = id, ed = ed } end

local function isEnhanced(card)
  return card.enh ~= nil and card.enh ~= "STONE" and ns.CardTypes.enh[card.enh] ~= nil
end

T.test("relic_catalog", function()
  T.eq(#ns.Relics.order, 18)
  local seen = {}
  for _, id in ipairs(ns.Relics.order) do
    local d = ns.Relics.def[id]
    T.eq(d.id, id)
    T.ok(not seen[id], "unique " .. id)
    seen[id] = true
    T.ok(type(d.name) == "string" and type(d.desc) == "string" and type(d.icon) == "string", id)
    T.ok(type(d.use) == "function", id)
    T.eq(type(d.untargeted), "boolean", id)
    T.ok((d.select ~= nil) ~= d.untargeted, id .. ": targeted xor untargeted")
    T.eq(d.creates, false, id)
  end
  T.eq(ns.Consumables.COST.relic, 4)
  T.eq(ns.Consumables.def(relic("COSMOS")).name, "Relic of the Cosmos")
end)

T.test("relic_overfills_hand", function()
  local run = newRun("play")
  T.eq(#run.hand, 8)
  apply(run, "COURT")
  T.eq(#run.hand, 10)
  T.eq(#run.deck, 54, "one destroyed, three added")
  for i = 8, 10 do
    T.ok(run.hand[i].rank >= 11 and run.hand[i].rank <= 13, "face rank")
    T.ok(isEnhanced(run.hand[i]), "enhanced, not Stone")
    T.ok(run.hand[i].suit ~= nil, "suit")
  end
  local six = { 1, 2, 3, 4, 5, 6 }
  T.ok(not ns.Run.canPlay(run, six), "six cards never playable")
  ns.Run.play(run, { 1, 2 })
  T.eq(#run.hand, 8, "refill does not draw while hand >= handSize")
end)

T.test("relic_court_needs_hand", function()
  local run = newRun("shop")
  local ok, reason = ns.Consumables.canApply(run, relic("COURT"), {})
  T.ok(not ok)
  T.eq(reason, "Needs 1 card in hand")
end)

T.test("court_in_open_pack_uses_pack_hand", function()
  local run = newRun("shop")
  local hand = { run.deck[1], run.deck[2], run.deck[3] }
  run.shop = { openPack = { hand = hand } }
  local outcome = apply(run, "COURT")
  T.eq(#hand, 5, "2 left plus 3 added")
  T.eq(#outcome.added, 3)
  T.eq(#outcome.destroyed, 1)
end)

T.test("aces_add_enhanced_aces", function()
  for seed = 1, 20 do
    local run = ns.Run.new(seed, "ADVENTURER")
    ns.Run.startBlind(run)
    apply(run, "ACES")
    T.eq(#run.hand, 8 - 1 + 2)
    for i = 8, 9 do
      T.eq(run.hand[i].rank, 14, "seed " .. seed)
      T.ok(isEnhanced(run.hand[i]), "seed " .. seed .. ": never Stone")
    end
  end
end)

T.test("numbers_add_enhanced_numbers", function()
  for seed = 1, 20 do
    local run = ns.Run.new(seed, "ADVENTURER")
    ns.Run.startBlind(run)
    apply(run, "NUMBERS")
    T.eq(#run.hand, 8 - 1 + 4)
    for i = 8, 11 do
      T.ok(run.hand[i].rank >= 2 and run.hand[i].rank <= 10, "seed " .. seed)
      T.ok(isEnhanced(run.hand[i]), "seed " .. seed .. ": never Stone")
    end
  end
end)

T.test("gold_seal_on_selected", function()
  local run = newRun("play")
  apply(run, "GOLD", { run.hand[2] })
  T.eq(run.hand[2].seal, "GOLD")
  T.eq(run.hand[1].seal, nil)
end)

T.test("radiance_adds_edition", function()
  local seen = {}
  for seed = 1, 40 do
    local run = ns.Run.new(seed, "ADVENTURER")
    ns.Run.startBlind(run)
    local card = run.hand[1]
    apply(run, "RADIANCE", { card })
    T.ok(card.ed == "FOIL" or card.ed == "HOLO" or card.ed == "POLY", "edition " .. tostring(card.ed))
    seen[card.ed] = true
  end
  T.ok(seen.FOIL and seen.HOLO and seen.POLY, "all three rolled")
end)

H.test("lich_gold_zero", function()
  -- Spec remaps remove legacy rares; keep rare relic coverage with a scoped fixture.
  H.stub { id = "RELIC_RARE", name = "Rare", rarity = "rare", cost = 8 }
  local run = newRun("shop")
  run.gold = 25
  apply(run, "LICH")
  T.eq(run.gold, 0)
  T.eq(#run.trinkets, 1)
  T.eq(ns.Trinkets.def[run.trinkets[1].id].rarity, "rare")
end)

T.test("lich_needs_eligible_rare", function()
  local run = newRun("shop")
  for _, id in ipairs(ns.Trinkets.order) do
    if ns.Trinkets.def[id].rarity == "rare" then run.trinkets[#run.trinkets + 1] = trinket(id) end
  end
  run.maxTrinkets = #run.trinkets + 1 -- Keep room while exhausting the now-populated rare pool.
  local ok, reason = ns.Consumables.canApply(run, relic("LICH"), {})
  T.ok(not ok)
  T.eq(reason, "No eligible rare trinket")
end)

T.test("sigil_one_suit_for_hand", function()
  local run = newRun("play")
  local outcome = apply(run, "UNITY")
  T.eq(#outcome.changed, 8)
  for _, card in ipairs(run.hand) do T.eq(card.suit, run.hand[1].suit) end
end)

T.test("ouija_one_rank_and_hand_size", function()
  local run = newRun("play")
  apply(run, "WHISPERS")
  T.eq(run.handSizeMod, -1)
  T.eq(ns.Deck.handSize(run), 7)
  local rank = run.hand[1].rank
  T.ok(rank >= 2 and rank <= 14)
  for _, card in ipairs(run.hand) do T.eq(card.rank, rank) end
end)

T.test("ectoplasm_void_negative_and_hand_size", function()
  local run = newRun("shop")
  run.trinkets = { trinket("FORTITUDE"), trinket("WHETSTONE") }
  apply(run, "VOID")
  T.eq(run.handSizeMod, -1)
  local negatives = 0
  for _, t in ipairs(run.trinkets) do
    if t.ed == "NEGATIVE" then negatives = negatives + 1 end
  end
  T.eq(negatives, 1)
end)

T.test("flame_destroys_five_gains_20", function()
  local run = newRun("play")
  local gold = run.gold
  local outcome = apply(run, "FLAME")
  T.eq(#run.hand, 3)
  T.eq(#outcome.destroyed, 5)
  T.eq(run.gold, gold + 20)
  T.eq(outcome.gold, 20)
  T.eq(#run.deck, 47)
end)

T.test("flame_with_fewer_than_five_destroys_all_it_has", function()
  local run = newRun("play")
  while #run.hand > 3 do table.remove(run.hand) end
  local gold = run.gold
  local outcome = apply(run, "FLAME")
  T.eq(#outcome.destroyed, 3)
  T.eq(run.gold, gold + 20)
  T.ok(#run.hand >= 1, "checkHand refilled the emptied hand")
end)

T.test("flame_needs_a_card_in_hand", function()
  local run = newRun("play")
  run.hand = {}
  local ok, reason = ns.Consumables.canApply(run, relic("FLAME"), {})
  T.ok(not ok)
  T.eq(reason, "Needs 1 card in hand")
end)

T.test("rebirth_copies_and_drops_negative", function()
  local run = newRun("shop")
  run.trinkets = { trinket("FORTITUDE", "FOIL"), trinket("WHETSTONE", "NEGATIVE"), trinket("HEALTHSTONE") }
  apply(run, "REBIRTH")
  T.eq(#run.trinkets, 2)
  T.eq(run.trinkets[1].id, run.trinkets[2].id)
  T.ok(run.trinkets[2].ed ~= "NEGATIVE", "copy drops Negative")
end)

T.test("recurrence_red_seal", function()
  local run = newRun("play")
  apply(run, "RECURRENCE", { run.hand[1] })
  T.eq(run.hand[1].seal, "RED")
end)

T.test("hexes_destroys_others", function()
  local run = newRun("shop")
  run.trinkets = { trinket("FORTITUDE"), trinket("ARCANE_INTELLECT", "FOIL"), trinket("WHETSTONE") }
  apply(run, "HEXES")
  T.eq(#run.trinkets, 1)
  T.eq(run.trinkets[1].ed, "POLY")
  T.ok(run.trinkets[1].id == "FORTITUDE" or run.trinkets[1].id == "WHETSTONE")
end)

T.test("void_needs_editionless", function()
  local run = newRun("shop")
  run.trinkets = { trinket("FORTITUDE", "HOLO") }
  local ok, reason = ns.Consumables.canApply(run, relic("VOID"), {})
  T.ok(not ok)
  T.eq(reason, "No eligible trinket")
  ok, reason = ns.Consumables.canApply(run, relic("HEXES"), {})
  T.ok(not ok)
  T.eq(reason, "No eligible trinket")
  T.eq(run.handSizeMod, 0)
end)

T.test("insight_blue_seal", function()
  local run = newRun("play")
  apply(run, "INSIGHT", { run.hand[3] })
  T.eq(run.hand[3].seal, "BLUE")
end)

T.test("spirits_purple_seal", function()
  local run = newRun("play")
  apply(run, "SPIRITS", { run.hand[4] })
  T.eq(run.hand[4].seal, "PURPLE")
end)

T.test("mirrors_two_copies", function()
  local run = newRun("play")
  local card = run.hand[1]
  card.enh, card.ed, card.seal = "GLASS", "FOIL", "RED"
  local before = #run.deck
  local outcome = apply(run, "MIRRORS", { card })
  T.eq(#run.deck, before + 2)
  T.eq(#outcome.added, 2)
  for i = 1, 2 do
    local copy = run.deck[before + i]
    T.eq(copy.rank, card.rank)
    T.eq(copy.suit, card.suit)
    T.eq(copy.enh, "GLASS")
    T.eq(copy.ed, "FOIL")
    T.eq(copy.seal, "RED")
    T.ok(copy.id ~= card.id)
  end
end)

H.test("legends_rarest_available", function()
  -- Spec remaps remove legacy rares; keep rare relic coverage with a scoped fixture.
  H.stub { id = "RELIC_RARE", name = "Rare", rarity = "rare", cost = 8 }
  local run = newRun("shop")
  apply(run, "LEGENDS")
  T.eq(ns.Trinkets.def[run.trinkets[1].id].rarity, "rare")

  run = newRun("shop")
  for _, id in ipairs(ns.Trinkets.order) do
    if ns.Trinkets.def[id].rarity == "rare" then run.trinkets[#run.trinkets + 1] = trinket(id) end
  end
  run.maxTrinkets = #run.trinkets + 1 -- Test rarity fallback rather than the slot limit.
  apply(run, "LEGENDS")
  T.eq(ns.Trinkets.def[run.trinkets[#run.trinkets].id].rarity, "uncommon")
end)

T.test("cosmos_levels_every_hand_including_secret", function()
  local run = newRun("shop")
  run.seenHands.FIVE_KIND = true
  local outcome = apply(run, "COSMOS")
  for _, id in ipairs(ns.Hands.order) do
    T.eq(run.handLevels[id], 2, id)
    T.eq(outcome.levelled[id], 2, id)
  end
  T.ok(not run.seenHands.FLUSH_FIVE, "secret hands stay hidden")
  T.eq(#ns.Hands.visible(run), 10)
end)

T.test("void_penalty_escalates", function()
  local run = newRun("shop")
  run.trinkets = { trinket("FORTITUDE"), trinket("WHETSTONE"), trinket("HEALTHSTONE") }
  T.eq(run.voidPenalty, 1)
  local outcome = apply(run, "VOID")
  T.eq(run.handSizeMod, -1)
  T.eq(outcome.handSize, -1)
  T.eq(run.voidPenalty, 2)
  outcome = apply(run, "VOID")
  T.eq(run.handSizeMod, -3)
  T.eq(outcome.handSize, -2)
  T.eq(run.voidPenalty, 3)
  local desc = ns.Consumables.describe(run, relic("VOID"))
  T.ok(desc:find("-3 hand size", 1, true), desc)
  T.ok(ns.Consumables.affects(run, relic("VOID")):find("-3 hand size", 1, true))
end)

T.test("radiance_refuses_card_with_edition", function()
  local run = newRun("play")
  run.hand[1].ed = "FOIL"
  local ok, reason = ns.Consumables.canApply(run, relic("RADIANCE"), { run.hand[1] })
  T.ok(not ok)
  T.eq(reason, "Card already has an edition")
  T.ok(ns.Consumables.canApply(run, relic("RADIANCE"), { run.hand[2] }))
end)

H.test("trinket_outcomes_report_slots", function()
  -- Spec remaps remove legacy rares; keep rare relic coverage with a scoped fixture.
  H.stub { id = "RELIC_RARE", name = "Rare", rarity = "rare", cost = 8 }
  local run = newRun("shop")
  run.trinkets = { trinket("FORTITUDE"), trinket("WHETSTONE"), trinket("HEALTHSTONE") }
  local outcome = apply(run, "VOID")
  T.eq(#outcome.trinkets, 1)
  T.eq(run.trinkets[outcome.trinkets[1]].ed, "NEGATIVE")
  outcome = apply(run, "HEXES")
  T.eq(outcome.trinkets, { 1 })
  T.eq(#run.trinkets, 1)
  run = newRun("shop")
  run.trinkets = { trinket("FORTITUDE", "FOIL"), trinket("WHETSTONE") }
  outcome = apply(run, "REBIRTH")
  T.eq(outcome.trinkets, { 2 })
  run = newRun("shop")
  outcome = apply(run, "LICH")
  T.eq(outcome.trinkets, { 1 })
  run = newRun("shop")
  outcome = apply(run, "LEGENDS")
  T.eq(outcome.trinkets, { 1 })
end)

T.test("whispers_reports_hand_size", function()
  local run = newRun("play")
  local outcome = apply(run, "WHISPERS")
  T.eq(outcome.handSize, -1)
end)
