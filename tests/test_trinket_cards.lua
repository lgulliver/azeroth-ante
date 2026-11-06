local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function blindRun(opts)
  local run = H.run(opts)
  ns.Run.startBlind(run)
  return run
end

local function inList(list, card)
  for _, c in ipairs(list) do
    if c == card then return true end
  end
  return false
end

H.test("chipvalue_bonus", function()
  T.eq(ns.Cards.chipValue({ rank = 14, suit = "S", bonusChips = 10 }), 21)
  T.eq(ns.Cards.chipValue({ rank = 5, suit = "S" }), 5)
  T.eq(ns.Cards.chipValue({ rank = 14, suit = "S", enh = "STONE", bonusChips = 10 }), 10)
  local run = ns.Run.new(1, "ROGUE")
  T.eq(ns.Cards.nominal({ rank = 14, suit = "S", bonusChips = 10 }), 11)
  local copy = ns.Deck.copy(run, { rank = 4, suit = "H", bonusChips = 15 })
  T.eq(copy.bonusChips, 15)
end)

H.test("scratch_cards_pure", function()
  H.stub({ id = "C_STRIP", before = function(ctx)
    for _, card in ipairs(ctx.cards) do card.enh = nil end
  end })
  H.stub({ id = "C_BONUS", onCard = function(_, _, card)
    card.bonusChips = (card.bonusChips or 0) + 5
  end })
  local run = H.run({ trinkets = { "C_STRIP", "C_BONUS" } })
  local card = H.card(9, "H", "MULT")
  local a = H.score(run, { card }, {})
  local b = H.score(run, { card }, {})
  T.eq(a.total, b.total)
  T.eq(card.enh, "MULT")
  T.eq(card.bonusChips, nil)
  T.eq(a.cardsAfter[card.id], { bonusChips = 5 })
  T.eq(a.cardsAfter[card.id].enh, nil)
end)

H.test("before_change_affects_this_hand", function()
  H.stub({ id = "C_STRIP", before = function(ctx)
    for _, card in ipairs(ctx.cards) do card.enh = nil end
  end })
  local plain = H.score(H.run(), { H.card(14, "S") }, {})
  local run = H.run({ trinkets = { "C_STRIP" } })
  local glass = H.card(14, "S", "GLASS")
  local result = H.score(run, { glass }, {})
  T.eq(result.total, plain.total)
  T.eq(#result.destroyed, 0)
  T.eq(glass.enh, "GLASS")
end)

H.test("oncard_bonus_seen_by_retrigger", function()
  H.stub({ id = "C_BONUS", onCard = function(_, _, card)
    card.bonusChips = (card.bonusChips or 0) + 5
  end })
  local run = H.run({ trinkets = { "C_BONUS" } })
  local result = H.score(run, { H.card(5, "S", nil, nil, "RED") }, {})
  local values = {}
  for _, e in ipairs(result.events) do
    if e.kind == "card" then values[#values + 1] = e.chips end
  end
  T.eq(values, { 5, 10 })
end)

H.test("play_commits_card_changes", function()
  H.stub({ id = "C_CHANGE",
    before = function(ctx) for _, c in ipairs(ctx.cards) do c.enh = "BONUS" end end,
    onCard = function(_, _, card) card.bonusChips = (card.bonusChips or 0) + 5 end })
  local run = blindRun({ trinkets = { "C_CHANGE" } })
  local id = run.hand[1].id
  ns.Run.play(run, { 1 })
  local card = ns.Deck.find(run, id)
  T.eq(card.enh, "BONUS")
  T.eq(card.bonusChips, 5)
end)

H.test("create_card_to_hand_keeps_selection", function()
  local made = false
  H.stub({ id = "C_MAKE", before = function()
    if made then return nil end
    made = true
    return { createCard = { card = { rank = 9, suit = "H", bonusChips = 3 }, toHand = true } }
  end })
  local run = blindRun({ trinkets = { "C_MAKE" } })
  local size = ns.Deck.handSize(run)
  local played = run.hand[1]
  local others = {}
  for i = 2, #run.hand do others[#others + 1] = run.hand[i] end
  local deckBefore = #run.deck
  ns.Run.play(run, { 1 })
  T.ok(not inList(run.hand, played), "played card still in hand")
  T.eq(#run.deck, deckBefore + 1)
  local created = run.deck[#run.deck]
  T.eq(created.rank, 9)
  T.eq(created.bonusChips, 3)
  T.ok(created.id ~= nil, "created card has no id")
  T.ok(inList(run.hand, created), "created card not in hand")
  T.ok(#run.hand <= size, "hand overflowed")
  for _, card in ipairs(others) do T.ok(inList(run.hand, card), "a held card was lost") end
end)

H.test("create_card_not_to_hand_goes_to_deck_only", function()
  local made = false
  H.stub({ id = "C_MAKE", before = function()
    if made then return nil end
    made = true
    return { createCard = { card = { rank = 9, suit = "H" }, toHand = false } }
  end })
  local run = blindRun({ trinkets = { "C_MAKE" } })
  local deckBefore = #run.deck
  ns.Run.play(run, { 1 })
  local created = run.deck[#run.deck]
  T.eq(#run.deck, deckBefore + 1)
  T.ok(not inList(run.hand, created), "card should not enter the hand")
end)

H.test("create_consumable_room", function()
  H.stub({ id = "C_ONE", before = function() return { createConsumable = { kind = "scroll" } } end })
  H.stub({ id = "C_TWO", before = function() return { createConsumable = { kind = "scroll" } } end })
  local run = blindRun({ trinkets = { "C_ONE", "C_TWO" } })
  run.consumables[1] = { kind = "scroll", id = ns.Scrolls.order[1] }
  local result = ns.Run.play(run, { 1 })
  T.eq(#run.consumables, 2)
  T.eq(#result.sideEffects, 2)
  T.eq(result.sideEffects[1].kind, "createConsumable")
  T.eq(result.sideEffects[1].consumableKind, "scroll")
end)

H.test("create_consumable_relic_and_explicit_id", function()
  H.stub({ id = "C_REL", before = function() return { createConsumable = { kind = "relic" } } end })
  H.stub({ id = "C_ID", before = function()
    return { createConsumable = { kind = "scroll", id = ns.Scrolls.order[2] } }
  end })
  local run = blindRun({ trinkets = { "C_REL", "C_ID" } })
  ns.Run.play(run, { 1 })
  T.eq(run.consumables[1].kind, "relic")
  T.ok(ns.Relics.def[run.consumables[1].id] ~= nil, "unknown relic")
  T.eq(run.consumables[2], { kind = "scroll", id = ns.Scrolls.order[2] })
end)

H.test("destroy_card_effect", function()
  H.stub({ id = "C_KILL", before = function(ctx)
    return { destroyCard = ctx.held[1].id }
  end })
  local run = blindRun({ trinkets = { "C_KILL" } })
  local victim = run.hand[2]
  ns.Run.play(run, { 1 })
  T.eq(ns.Deck.find(run, victim.id), nil)
  T.ok(not inList(run.hand, victim), "destroyed card still in hand")
  T.ok(not inList(run.pile, victim), "destroyed card still in pile")
end)

H.test("change_card_effect", function()
  H.stub({ id = "C_CH", before = function(ctx)
    return { changeCard = { id = ctx.cards[1].id, enh = "MULT", seal = "GOLD", bonusChips = 7 } }
  end })
  local run = H.run({ trinkets = { "C_CH" } })
  local card = H.card(9, "H", "GLASS")
  local result = H.score(run, { card }, {})
  T.eq(result.cardsAfter[card.id], { enh = "MULT", seal = "GOLD", bonusChips = 7 })
  T.eq(card.enh, "GLASS")
end)

H.test("lucky_hook_counts", function()
  local calls = 0
  H.stub({ id = "C_LUCK", onLucky = function(_, _, card, isCopy)
    calls = calls + 1
    T.eq(card.enh, "LUCKY")
    T.eq(isCopy, false)
  end })
  local run = H.run({ trinkets = { "C_LUCK" } })
  local realNext = ns.RNG.next
  ns.RNG.next = function() return 0 end
  local ok, result = pcall(H.score, run, { H.card(9, "H", "LUCKY") }, {})
  ns.RNG.next = realNext
  assert(ok, result)
  T.eq(calls, 1)
  T.eq(result.luckyTriggers, 1)
end)

H.test("boss_triggered_flag", function()
  local run = H.run()
  T.eq(H.score(run, { H.card(14, "S") }, {}, { bossId = "VANCLEEF" }).bossTriggered, true)
  T.eq(H.score(run, { H.card(14, "H") }, {}, { bossId = "VANCLEEF" }).bossTriggered, false)
  T.eq(H.score(run, { H.card(14, "H") }, {}).bossTriggered, false)
  T.eq(H.score(run, { H.card(14, "H") }, {}, { bossId = "RIVENDARE" }).bossTriggered, true)
  T.eq(H.score(run, { H.card(14, "H") }, {}, { bossId = "HEROD" }).bossTriggered, false)
  -- A debuffed kicker does not score, so it does not trigger.
  local pair = { H.card(9, "H"), H.card(9, "H"), H.card(3, "S") }
  T.eq(H.score(run, { pair[3], pair[1], pair[2] }, {}, { bossId = "VANCLEEF" }).bossTriggered, false)
  T.eq(H.score(run, { H.card(9, "S"), H.card(9, "S"), H.card(3, "H") }, {}, { bossId = "VANCLEEF" }).bossTriggered, true)
end)

H.test("play_supplies_ctx_fields", function()
  local seen = {}
  H.stub({ id = "C_CTX", before = function(ctx)
    seen[#seen + 1] = { first = ctx.firstHandOfRound, room = ctx.consumableRoom, gold = ctx.gold,
      deck = #ctx.deckCards, start = ctx.startDeckSize }
  end })
  local run = blindRun({ trinkets = { "C_CTX" }, gold = 9 })
  T.eq(run.handsPlayedRound, 0)
  ns.Run.play(run, { 1 })
  ns.Run.play(run, { 1 })
  T.eq(seen[1], { first = true, room = 2, gold = 9, deck = 52, start = 52 })
  T.eq(seen[2].first, false)
  T.eq(run.handsPlayedRound, 2)
  ns.Run.startBlind(run)
  T.eq(run.handsPlayedRound, 0)
end)

H.test("save_migration_defaults_hands_played_round", function()
  local run = H.run()
  run.handsPlayedRound = nil
  local db = {}
  ns.Save.store(db, run)
  T.eq(ns.Save.load(db).handsPlayedRound, 0)
end)

H.test("raised_fist_ignores_bonus_chips", function()
  local run = H.run({ trinkets = { "FIST_JUSTICE" } })
  local low = H.card(2, "S")
  low.bonusChips = 10
  local result = H.score(run, { H.card(9, "H") }, { low, H.card(8, "C") })
  local mult = 0
  for _, e in ipairs(result.events) do
    if e.kind == "trinket" and e.heldIndex == 1 then mult = mult + (e.mult or 0) end
  end
  T.eq(mult, 4)
end)

H.test("save_migration_hands_played_round_from_round_plays", function()
  local run = H.run()
  run.handsPlayedRound = nil
  run.roundHandPlays = { PAIR = 2, HIGH_CARD = 1 }
  local db = {}
  ns.Save.store(db, run)
  T.eq(ns.Save.load(db).handsPlayedRound, 3)
end)
