local ns, T = ...

T.test("stage_8_draws_a_finisher", function()
  local seen = {}
  for seed = 1, 200 do
    local run = ns.Run.new(seed, "ADVENTURER")
    T.ok(ns.Bosses.isFinal(run.bosses[8]), "seed " .. seed .. " stage 8 is a finisher")
    seen[run.bosses[8]] = true
  end
  for _, id in ipairs(ns.Bosses.FINALS) do T.ok(seen[id], id .. " never drawn") end
end)

T.test("finishers_never_before_stage_8", function()
  for seed = 1, 200 do
    local run = ns.Run.new(seed, "ADVENTURER")
    for stage = 1, 7 do
      T.ok(not ns.Bosses.isFinal(run.bosses[stage]), "seed " .. seed .. " stage " .. stage)
    end
  end
end)

T.test("finisher_reroll_stays_final", function()
  local run = ns.Run.new(3, "ADVENTURER")
  run.stage, run.blind, run.phase, run.gold = 8, 3, "blind", 100
  run.vouchers.DIRECTORS_CUT = true
  local old = run.bosses[8]
  local ok, id = ns.Run.rerollBoss(run)
  T.ok(ok, "reroll succeeds")
  T.ok(ns.Bosses.isFinal(id), "still a finisher")
  T.ok(id ~= old, "a different finisher")
  T.eq(run.bosses[8], id)
end)

T.test("finisher_pays_8", function()
  local run = ns.Run.new(3, "ADVENTURER")
  run.stage, run.blind, run.phase = 8, 3, "play"
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.reward, 8)
end)

T.test("regular_blinds_pay_3_4_5", function()
  for blind, want in ipairs({ 3, 4, 5 }) do
    local run = ns.Run.new(3, "ADVENTURER")
    run.stage, run.blind = 2, blind
    T.eq(ns.Run.blindReward(run), want)
  end
end)

T.test("cthun_target_is_6x", function()
  T.eq(ns.Run.target({}, 8, 3, "CTHUN"), 300000)
end)

T.test("finisher_defs", function()
  T.eq(ns.Bosses.FINALS[1], "RAGNAROS")
  for _, id in ipairs(ns.Bosses.FINALS) do
    local def = ns.Bosses.def[id]
    T.ok(def and def.name and def.desc, id)
    T.ok(not ns.Bosses.isFinal(ns.Bosses.pool[1]))
  end
end)

-- Face-down bosses ---------------------------------------------------------

local function bossRun(seed, bossId)
  local run = ns.Run.new(seed, "ADVENTURER")
  run.blind, run.bosses[run.stage] = 3, bossId
  T.startBlind(run)
  return run
end

local function faceDownCount(cards)
  local n = 0
  for _, c in ipairs(cards) do if c.faceDown then n = n + 1 end end
  return n
end

T.test("moroes_first_hand_face_down", function()
  local run = bossRun(5, "MOROES")
  T.eq(faceDownCount(run.hand), #run.hand)
  T.ok(#run.hand > 0)
  run.target = 1e9
  local opening = {}
  for _, c in ipairs(run.hand) do opening[c] = true end
  local size = #run.hand
  ns.Run.play(run, { 1 })
  T.eq(run.handsPlayedRound, 1)
  T.eq(#run.hand, size)
  local survivors = 0
  for _, c in ipairs(run.hand) do
    if opening[c] then
      survivors = survivors + 1
      T.ok(c.faceDown, "a surviving opening card stays face down")
    else
      T.eq(c.faceDown, nil, "a newly drawn card is face up")
    end
  end
  T.eq(survivors, size - 1)
  local before = {}
  for _, c in ipairs(run.hand) do before[c] = true end
  ns.Run.discard(run, { 1 })
  for _, c in ipairs(run.hand) do
    if not before[c] then T.eq(c.faceDown, nil, "a discard refill is face up") end
  end
end)

T.test("thermaplugg_one_in_seven", function()
  local drawn, down = 0, 0
  for seed = 1, 400 do
    local run = bossRun(seed, "THERMAPLUGG")
    drawn, down = drawn + #run.hand, down + faceDownCount(run.hand)
  end
  T.ok(drawn >= 3000)
  local share = down / drawn
  T.ok(share > 0.10 and share < 0.19, "share " .. share)
end)

T.test("thermaplugg_odds_double_with_loaded_dice", function()
  local function share(trinkets)
    local drawn, down = 0, 0
    for seed = 1, 400 do
      local run = ns.Run.new(seed, "ADVENTURER")
      run.blind, run.bosses[run.stage] = 3, "THERMAPLUGG"
      run.trinkets = trinkets(run)
      T.startBlind(run)
      drawn, down = drawn + #run.hand, down + faceDownCount(run.hand)
    end
    return down / drawn
  end
  local doubled = share(function(run) return { ns.Trinkets.create(run, "LOADED_DICE") } end)
  T.ok(doubled > 0.23 and doubled < 0.34, "2 in 7: share " .. doubled)
  T.eq(ns.Bosses.describe(nil, "THERMAPLUGG"), "1 in 7 cards is drawn face down.")
  local run = ns.Run.new(5, "ADVENTURER")
  run.trinkets = { ns.Trinkets.create(run, "LOADED_DICE") }
  T.eq(ns.Bosses.describe(run, "THERMAPLUGG"), "2 in 7 cards is drawn face down.")
  T.eq(ns.Bosses.describe(run, "HOGGER"), ns.Bosses.def.HOGGER.desc)
end)

T.test("morogrim_face_down_after_play_only", function()
  local run = bossRun(7, "MOROGRIM")
  run.target = 1e9
  T.eq(faceDownCount(run.hand), 0)
  ns.Run.discard(run, { 1, 2 })
  T.eq(faceDownCount(run.hand), 0, "refill after a discard is face up")
  ns.Run.play(run, { 1, 2 })
  T.eq(faceDownCount(run.hand), 2, "refill after a play is face down")
end)

T.test("skeram_face_cards_only", function()
  local faces, rules = 0, ns.TrinketRules.set({})
  for seed = 1, 20 do
    local run = bossRun(seed, "SKERAM")
    for _, c in ipairs(run.hand) do
      local face = ns.Cards.isFace(c, rules)
      T.eq(c.faceDown == true, face and true or false, "card " .. c.rank .. c.suit)
      if face then faces = faces + 1 end
    end
  end
  T.ok(faces > 0)
end)

T.test("played_cards_turn_up", function()
  local run = bossRun(5, "MOROES")
  run.target = 1e9
  local played = run.hand[1]
  T.ok(played.faceDown)
  ns.Run.play(run, { 1 })
  T.eq(played.faceDown, nil)
  T.eq(ns.Deck.find(run, played.id).faceDown, nil)
end)

T.test("blind_end_turns_hand_up", function()
  local run = bossRun(5, "MOROES")
  T.ok(faceDownCount(run.deck) > 0)
  ns.Run.winBlind(run)
  T.eq(faceDownCount(run.deck), 0)
  T.eq(faceDownCount(run.hand), 0)
end)

T.test("disabling_boss_turns_cards_up", function()
  local run = bossRun(5, "SKERAM")
  run.hand[1].faceDown = true
  T.ok(ns.Run.disableBoss(run))
  T.eq(faceDownCount(run.hand), 0)
end)

-- Rule bosses --------------------------------------------------------------

local function debuffEvents(result)
  local n = 0
  for _, e in ipairs(result.events) do if e.kind == "debuff" then n = n + 1 end end
  return n
end

T.test("thredd_debuffs_clubs", function()
  local def = ns.Bosses.def.THREDD
  T.eq(def.name, "Bazil Thredd")
  T.eq(def.minStage, 1)
  T.eq(def.debuff({ rank = 9, suit = "C" }), true)
  T.eq(def.debuff({ rank = 9, suit = "H" }), false)
end)

T.test("targorr_hand_size_minus_one", function()
  local run = bossRun(5, "TARGORR")
  T.eq(ns.Bosses.def.TARGORR.minStage, 1)
  T.eq(#run.hand, 7)
  run.target = 1e9
  local fresh = ns.Run.new(5, "ADVENTURER")
  T.eq(ns.Deck.handSize(fresh), 8)
  fresh.blind = 1
  T.startBlind(fresh)
  T.eq(#fresh.hand, 8)
end)

T.test("patchwerk_target_4x", function()
  T.eq(ns.Run.target({}, 2, 3, "PATCHWERK"), 3200)
  T.eq(ns.Bosses.def.PATCHWERK.minStage, 2)
end)

T.test("archaedas_debuffs_cards_played_this_ante", function()
  local run = ns.Run.new(5, "ADVENTURER")
  run.bosses[run.stage] = "ARCHAEDAS"
  T.startBlind(run)
  run.target = 1e9
  local card = run.hand[1]
  ns.Run.play(run, { 1 })
  T.ok(run.playedThisAnte[card.id])
  -- The card is met again in the boss blind.
  run.blind = 3
  T.startBlind(run)
  run.target = 1e9
  run.hand[1] = card
  local result = ns.Run.play(run, { 1 })
  T.eq(debuffEvents(result), 1)
  -- Next ante it scores.
  run.stage = run.stage + 1
  run.playedThisAnte = {}
  T.eq(ns.Bosses.def.ARCHAEDAS.debuff(card, nil, { playedThisAnte = run.playedThisAnte }), false)
end)

T.test("archaedas_clears_when_stage_advances", function()
  local run = ns.Run.new(5, "ADVENTURER")
  run.playedThisAnte = { [7] = true }
  run.phase, run.blind = "shop", 3
  run.shop = nil
  ns.Run.nextBlind(run)
  T.eq(next(run.playedThisAnte), nil)
end)

T.test("disabling_targorr_refills_hand", function()
  local run = bossRun(5, "TARGORR")
  T.eq(#run.hand, 7)
  T.ok(ns.Run.disableBoss(run))
  T.eq(#run.hand, 8)
end)

T.test("archaedas_discard_trinkets_skip_played_cards", function()
  local run = bossRun(5, "ARCHAEDAS")
  run.trinkets = { { uid = 1, id = "FACELESS_ONE" } }
  run.gold = 0
  local faces = {}
  for _, c in ipairs(run.deck) do
    if c.rank >= 11 and c.rank <= 13 and #faces < 3 then faces[#faces + 1] = c end
  end
  for i = 1, 3 do run.hand[i] = faces[i] end
  run.playedThisAnte = { [faces[1].id] = true }
  ns.Run.discard(run, { 1, 2, 3 })
  T.eq(run.gold, 0)
end)

T.test("targorr_hand_size_back_in_shop", function()
  local run = bossRun(5, "TARGORR")
  T.eq(ns.Deck.handSize(run), 7)
  ns.Run.winBlind(run)
  T.eq(run.phase, "shop")
  T.eq(ns.Deck.handSize(run), 8)
end)

-- Play-time bosses ---------------------------------------------------------

-- The deck card of rank and suit (S, H, D, C), so ids stay real.
local function deckCard(run, rank, suit)
  for _, c in ipairs(run.deck) do
    if c.rank == rank and c.suit == suit then return c end
  end
end

-- Replaces the hand with deck cards given as { rank, suit } pairs.
local function setHand(run, specs)
  run.hand = {}
  for i, s in ipairs(specs) do run.hand[i] = deckCard(run, s[1], s[2]) end
end

local function baseEvent(result)
  for _, e in ipairs(result.events) do if e.kind == "base" then return e end end
end

T.test("hook_discards_two_held", function()
  local run = bossRun(5, "GREENSKIN")
  T.eq(ns.Bosses.def.GREENSKIN.name, "Captain Greenskin")
  T.eq(ns.Bosses.def.GREENSKIN.minStage, 1)
  run.target = 1e9
  run.consumables = {}
  local held = {}
  for i = 2, #run.hand do held[run.hand[i]] = true end
  for _, c in ipairs(run.hand) do c.seal = "PURPLE" end
  local pile, discards = #run.pile, run.discardsLeft
  ns.Run.play(run, { 1 })
  T.eq(run.discardsLeft, discards, "no discard spent")
  T.eq(#run.consumables, 0, "Purple seals do not fire")
  -- 1 played + 2 thrown away, all three replaced by the refill.
  T.eq(#run.hand, 8)
  T.eq(#run.pile, pile - 3)
  local kept = 0
  for _, c in ipairs(run.hand) do if held[c] then kept = kept + 1 end end
  T.eq(kept, 5, "two of the seven held cards are gone")
end)

T.test("hook_discards_before_scoring", function()
  local run = bossRun(5, "GREENSKIN")
  run.target = 1e9
  for _, c in ipairs(run.hand) do c.enh = "STEEL" end
  local played = run.hand[1]
  local result = ns.Run.play(run, { 1 })
  local heldEvents = 0
  for _, e in ipairs(result.events) do if e.kind == "held" then heldEvents = heldEvents + 1 end end
  T.eq(heldEvents, 5, "the two thrown-away cards are not held while the hand scores")
  for _, c in ipairs(run.hand) do T.ok(c ~= played) end
end)

T.test("arm_lowers_level_before_scoring", function()
  local run = bossRun(5, "FROSTWHISPER")
  T.eq(ns.Bosses.def.FROSTWHISPER.name, "Ras Frostwhisper")
  T.eq(ns.Bosses.def.FROSTWHISPER.minStage, 2)
  run.target = 1e9
  run.handLevels.PAIR = 3
  setHand(run, { { 9, "S" }, { 9, "H" }, { 2, "C" }, { 4, "D" } })
  local result = ns.Run.play(run, { 1, 2 })
  T.eq(result.handId, "PAIR")
  T.eq(run.handLevels.PAIR, 2)
  local chips, mult = ns.Hands.base("PAIR", 2)
  T.eq(baseEvent(result).chips, chips)
  T.eq(baseEvent(result).mult, mult)
  setHand(run, { { 9, "S" }, { 2, "C" }, { 4, "D" } })
  ns.Run.play(run, { 1 })
  T.eq(run.handLevels.HIGH_CARD, 1, "never below level 1")
end)

T.test("tooth_charges_per_card", function()
  local run = bossRun(5, "REVILGAZ")
  T.eq(ns.Bosses.def.REVILGAZ.name, "Baron Revilgaz")
  T.eq(ns.Bosses.def.REVILGAZ.minStage, 3)
  run.target = 1e9
  run.gold = 10
  ns.Run.play(run, { 1, 2, 3 })
  T.eq(run.gold, 7)
end)

T.test("tooth_charges_before_scoring", function()
  local run = bossRun(5, "REVILGAZ")
  run.target = 1e9
  run.trinkets = { ns.Trinkets.create(run, "TAUREN_CHARGE") }
  run.gold = 10
  local result = ns.Run.play(run, { 1, 2, 3 })
  local chips
  for _, e in ipairs(result.events) do if e.kind == "trinket" then chips = e.chips end end
  T.eq(chips, 14, "Tauren Charge reads the 7g left after the charge")
end)

T.test("tooth_can_go_below_zero", function()
  local run = bossRun(5, "REVILGAZ")
  run.target = 1e9
  run.gold = 2
  ns.Run.play(run, { 1, 2, 3, 4, 5 })
  T.eq(run.gold, -3, "Balatro's ease_dollars has no floor")
  run.gold = -18
  ns.Run.play(run, { 1, 2, 3, 4, 5 })
  T.eq(run.gold, -23)
end)

T.test("ox_zeroes_gold_on_most_played", function()
  local run = bossRun(5, "GRUUL")
  T.eq(ns.Bosses.def.GRUUL.name, "Gruul the Dragonkiller")
  T.eq(ns.Bosses.def.GRUUL.minStage, 6)
  run.target = 1e9
  run.handPlays = { PAIR = 3, FLUSH = 3, HIGH_CARD = 1 }
  run.gold = 20
  setHand(run, { { 9, "S" }, { 2, "C" }, { 4, "D" } })
  ns.Run.play(run, { 1 })
  T.eq(run.gold, 20, "High Card is not the most played")
  setHand(run, { { 9, "S" }, { 9, "H" }, { 4, "D" } })
  ns.Run.play(run, { 1, 2 })
  T.eq(run.gold, 0, "Pair ties for most played")
  run.gold = -5
  run.trinkets = { { uid = 1, id = "VENTURE_LOAN" } }
  setHand(run, { { 9, "S" }, { 9, "H" }, { 4, "D" } })
  ns.Run.play(run, { 1, 2 })
  T.eq(run.gold, 0, "debt is set to 0 too")
end)

T.test("ox_zeroes_gold_before_scoring", function()
  local run = bossRun(5, "GRUUL")
  run.target = 1e9
  run.handPlays = { PAIR = 2 }
  run.trinkets = { ns.Trinkets.create(run, "TAUREN_CHARGE") }
  run.gold = 20
  setHand(run, { { 9, "S" }, { 9, "H" }, { 4, "D" } })
  local result = ns.Run.play(run, { 1, 2 })
  local chips
  for _, e in ipairs(result.events) do if e.kind == "trinket" then chips = e.chips end end
  T.eq(chips, 0, "Tauren Charge sees 0g")
  T.eq(run.gold, 0)
end)

T.test("ox_no_history_means_high_card", function()
  local run = bossRun(5, "GRUUL")
  run.target = 1e9
  run.handPlays = {}
  run.gold = 20
  setHand(run, { { 9, "S" }, { 9, "H" }, { 4, "D" } })
  ns.Run.play(run, { 1, 2 })
  T.eq(run.gold, 20, "a Pair is not the most played with no history")
  run.handPlays = {}
  setHand(run, { { 9, "S" }, { 2, "C" }, { 4, "D" } })
  ns.Run.play(run, { 1 })
  T.eq(run.gold, 0, "High Card is")
end)

T.test("mouth_debuffs_other_hand_types", function()
  local run = bossRun(5, "GLUTH")
  T.eq(ns.Bosses.def.GLUTH.name, "Gluth")
  T.eq(ns.Bosses.def.GLUTH.minStage, 2)
  run.target = 1e9
  local cards = { { 9, "S" }, { 9, "H" }, { 2, "C" }, { 4, "D" }, { 4, "S" }, { 7, "H" } }
  setHand(run, cards)
  T.ok(ns.Run.canPlay(run, { 1 }), "anything goes before the first hand")
  local first = ns.Run.play(run, { 1, 2 })
  T.ok(first.total > 0, "the first hand type scores")
  setHand(run, cards)
  local hands = run.handsLeft
  T.ok(ns.Run.canPlay(run, { 3 }), "another hand type can still be played")
  local result = ns.Run.play(run, { 3 })
  T.eq(result.total, 0, "but scores nothing")
  T.eq(result.events[1].kind, "notAllowed")
  T.eq(run.handsLeft, hands - 1, "and spends a hand")
  setHand(run, cards)
  T.ok(ns.Run.play(run, { 4, 5 }).total > 0, "the locked type still scores")
end)

T.test("eye_debuffs_repeat", function()
  local run = bossRun(5, "ARAN")
  T.eq(ns.Bosses.def.ARAN.name, "Shade of Aran")
  T.eq(ns.Bosses.def.ARAN.minStage, 3)
  run.target = 1e9
  local cards = { { 9, "S" }, { 9, "H" }, { 2, "C" }, { 4, "D" }, { 4, "S" }, { 7, "H" } }
  setHand(run, cards)
  T.ok(ns.Run.play(run, { 1, 2 }).total > 0)
  setHand(run, cards)
  local score, hands = run.score, run.handsLeft
  local result = ns.Run.play(run, { 4, 5 })
  T.eq(result.total, 0, "a repeated Pair scores nothing")
  T.eq(result.events[1].kind, "notAllowed")
  T.eq(run.score, score)
  T.eq(run.handsLeft, hands - 1, "and uses a hand")
  setHand(run, cards)
  T.ok(ns.Run.play(run, { 3 }).total > 0, "a new hand type scores")
end)

T.test("disallowed_hand_has_no_trinket_effects", function()
  local run = bossRun(5, "ARAN")
  run.target = 1e9
  run.trinkets = { { uid = 1, id = "ARCANE_INTELLECT" } }
  run.roundHandPlays = { HIGH_CARD = 1 }
  setHand(run, { { 9, "S" }, { 2, "C" } })
  T.eq(ns.Run.play(run, { 1 }).total, 0, "no trinket mult on a debuffed hand")
end)

T.test("serpent_draws_three", function()
  local run = bossRun(5, "HAKKAR")
  T.eq(ns.Bosses.def.HAKKAR.name, "Hakkar the Soulflayer")
  T.eq(ns.Bosses.def.HAKKAR.minStage, 5)
  T.eq(#run.hand, 8, "the start of the blind draws normally")
  run.target = 1e9
  ns.Run.play(run, { 1, 2, 3, 4, 5 })
  T.eq(#run.hand, 6, "3 held + 3 drawn")
  ns.Run.discard(run, { 1 })
  T.eq(#run.hand, 8, "5 held + 3 drawn")
  ns.Run.play(run, { 1 })
  T.eq(#run.hand, 10, "over the hand size")
end)

T.test("disabling_play_bosses", function()
  for _, id in ipairs({ "GREENSKIN", "FROSTWHISPER", "REVILGAZ", "GRUUL", "GLUTH", "ARAN", "HAKKAR" }) do
    local run = bossRun(5, id)
    T.ok(ns.Run.disableBoss(run), id)
  end
  local run = bossRun(5, "ARAN")
  run.roundHandPlays = { HIGH_CARD = 1 }
  ns.Run.disableBoss(run)
  T.ok(ns.Run.play(run, { 1 }).total > 0, "a disabled Aran allows repeats")
end)

-- Finishers -----------------------------------------------------------------

-- A final-ante boss blind with `trinkets` owned before it starts.
local function finisherRun(seed, bossId, trinkets)
  local run = ns.Run.new(seed, "ADVENTURER")
  run.stage, run.blind = 8, 3
  run.bosses[8] = bossId
  run.trinkets = trinkets or {}
  T.startBlind(run)
  return run
end

local function disabledUids(run)
  local out = {}
  for _, t in ipairs(run.trinkets) do if t.disabled then out[#out + 1] = t.uid end end
  return out
end

T.test("ragnaros_disables_one_trinket_each_hand", function()
  T.eq(ns.Bosses.def.RAGNAROS.desc, "One random trinket is disabled each hand.")
  local run = finisherRun(5, "RAGNAROS", {
    { uid = 1, id = "ARCANE_INTELLECT", ed = "HOLO" }, { uid = 2, id = "ARCANE_INTELLECT" },
  })
  run.target = 1e9
  for _ = 1, 3 do
    local off = disabledUids(run)
    T.eq(#off, 1, "exactly one trinket is disabled")
    setHand(run, { { 9, "S" }, { 2, "C" } })
    local result = ns.Run.play(run, { 1 })
    local fired = {}
    for _, e in ipairs(result.events) do
      if e.uid then fired[e.uid] = true end
    end
    T.ok(not fired[off[1]], "the disabled trinket does nothing, edition included")
    T.ok(fired[off[1] == 1 and 2 or 1], "the other one still scores")
  end
  T.eq(#disabledUids(run), 1, "a new pick after each hand")
  local empty = finisherRun(5, "RAGNAROS", {})
  T.eq(#disabledUids(empty), 0)
end)

T.test("ragnaros_disabled_target_is_not_copied", function()
  local run = finisherRun(5, "RAGNAROS", { { uid = 1, id = "SCHEMATIC" }, { uid = 2, id = "ARCANE_INTELLECT" } })
  for _, t in ipairs(run.trinkets) do t.disabled = (t.uid == 2) or nil end
  T.eq(ns.TrinketEngine.source(run.trinkets, 1), nil, "a copier copies nothing from a disabled trinket")
  local n = 0
  ns.TrinketEngine.each(run.trinkets, function() n = n + 1 end)
  T.eq(n, 0)
end)

T.test("yogg_flips_and_shuffles", function()
  local owned = {}
  for i = 1, 5 do owned[i] = { uid = i, id = "ARCANE_INTELLECT" } end
  local moved = false
  for seed = 1, 10 do
    local trinkets = {}
    for i, t in ipairs(owned) do trinkets[i] = { uid = t.uid, id = t.id } end
    local run = finisherRun(seed, "YOGG", trinkets)
    for _, t in ipairs(run.trinkets) do T.ok(t.faceDown, "every trinket is face down") end
    T.eq(#run.trinkets, 5)
    for i, t in ipairs(run.trinkets) do if t.uid ~= i then moved = true end end
    run.target = 1e9
    setHand(run, { { 9, "S" }, { 2, "C" } })
    local base = ns.Run.play(run, { 1 })
    T.ok(base.total > 0)
    if seed == 1 then
      local mult
      for _, e in ipairs(base.events) do if e.kind == "total" then mult = e.runMult end end
      T.eq(mult, 1 + 20, "face-down trinkets still work")
      run.target = 1
      setHand(run, { { 9, "S" }, { 2, "C" } })
      ns.Run.play(run, { 1 })
      for _, t in ipairs(run.trinkets) do T.ok(not t.faceDown, "turned up when the blind is won") end
    end
  end
  T.ok(moved, "the order was shuffled")
end)

T.test("xavius_debuffs_until_sale", function()
  local run = finisherRun(5, "XAVIUS", { { uid = 1, id = "ARCANE_INTELLECT" }, { uid = 2, id = "ARCANE_INTELLECT" } })
  run.target = 1e9
  local def = ns.Bosses.def.XAVIUS
  T.eq(def.debuff(run.hand[1], {}, run), true)
  setHand(run, { { 9, "S" }, { 2, "C" } })
  local before = ns.Run.play(run, { 1 })
  T.ok(debuffEvents(before) > 0, "all cards are debuffed")
  T.ok(ns.Run.sellTrinket(run, 1))
  T.eq(run.flags.soldThisBlind, true)
  T.eq(def.debuff(run.hand[1], {}, run), false)
  setHand(run, { { 9, "S" }, { 2, "C" } })
  T.eq(debuffEvents(ns.Run.play(run, { 1 })), 0, "a sale lifts it")
  run.blind = 1
  T.startBlind(run)
  T.ok(not run.flags.soldThisBlind, "resets at the next blind")
end)

T.test("kelthuzad_forces_a_card", function()
  local run = finisherRun(5, "KELTHUZAD")
  run.target = 1e9
  local forced = run.forcedCard
  T.ok(forced, "a card is forced")
  local fi
  for i, c in ipairs(run.hand) do if c == forced then fi = i end end
  T.ok(fi, "the forced card is in the hand")
  local other = fi == 1 and 2 or 1
  local ok, why = ns.Run.canPlay(run, { other })
  T.eq(ok, false)
  local rankName = ({ [11] = "Jack", [12] = "Queen", [13] = "King", [14] = "Ace" })[forced.rank] or tostring(forced.rank)
  T.eq(why, rankName .. " of " .. ns.Cards.SUIT_NAMES[forced.suit] .. " must be selected.")
  T.eq((ns.Run.canDiscard(run, { other })), false)
  T.eq((ns.Run.play(run, { other })), nil, "refused")
  T.ok(ns.Run.canPlay(run, { fi, other }))
  ns.Run.discard(run, { other, fi })
  T.ok(run.forcedCard and run.forcedCard ~= forced, "a new card is forced after it leaves")
  forced = run.forcedCard
  for i, c in ipairs(run.hand) do if c == forced then fi = i end end
  ns.Run.play(run, { fi })
  T.ok(run.forcedCard and run.forcedCard ~= forced, "replaced after it is played")
  local inHand = false
  for _, c in ipairs(run.hand) do
    if c == run.forcedCard then inHand = true end
    T.ok(c ~= forced, "the played card left the hand")
  end
  T.ok(inHand, "the new forced card is in the hand")
  local still = run.forcedCard
  for i, c in ipairs(run.hand) do if c ~= still then fi = i break end end
  for i, c in ipairs(run.hand) do if c == still then other = i end end
  ns.Run.play(run, { fi, other })
  T.ok(run.forcedCard ~= nil)
end)

T.test("disabling_finisher_restores_everything", function()
  local function owned()
    return { { uid = 1, id = "ARCANE_INTELLECT" }, { uid = 2, id = "ARCANE_INTELLECT" } }
  end
  local rag = finisherRun(5, "RAGNAROS", owned())
  T.ok(ns.Run.disableBoss(rag))
  T.eq(#disabledUids(rag), 0, "Ragnaros: trinkets back on")
  local yogg = finisherRun(5, "YOGG", owned())
  T.ok(ns.Run.disableBoss(yogg))
  for _, t in ipairs(yogg.trinkets) do T.ok(not t.faceDown, "Yogg-Saron: trinkets face up") end
  local xav = finisherRun(5, "XAVIUS", owned())
  T.ok(ns.Run.disableBoss(xav))
  T.eq(debuffEvents(ns.Run.play(xav, { 1 })), 0, "Xavius: cards score")
  local kt = finisherRun(5, "KELTHUZAD", owned())
  T.ok(ns.Run.disableBoss(kt))
  T.eq(kt.forcedCard, nil, "Kel'Thuzad: nothing forced")
  T.ok(ns.Run.canPlay(kt, { 1 }))
  local cthun = finisherRun(5, "CTHUN", owned())
  T.ok(ns.Run.disableBoss(cthun), "C'Thun's rule is its target")
  T.eq(cthun.target, ns.Run.BASE_TARGETS[8] * 2)
  -- Losing clears them too.
  local lost = finisherRun(5, "RAGNAROS", owned())
  lost.target, lost.handsLeft = 1e9, 1
  ns.Run.play(lost, { 1 })
  T.eq(lost.phase, "lost")
  T.eq(#disabledUids(lost), 0)
  local kl = finisherRun(5, "KELTHUZAD", owned())
  kl.target, kl.handsLeft = 1e9, 1
  local ki
  for i, c in ipairs(kl.hand) do if c == kl.forcedCard then ki = i end end
  ns.Run.play(kl, { ki })
  T.eq(kl.forcedCard, nil)
end)

T.test("ragnaros_repick_skips_the_disabled_trinket", function()
  for seed = 1, 30 do
    local run = finisherRun(seed, "RAGNAROS", {
      { uid = 1, id = "ARCANE_INTELLECT" }, { uid = 2, id = "ARCANE_INTELLECT" },
    })
    run.target, run.handsLeft = 1e9, 9
    for _ = 1, 4 do
      local before = disabledUids(run)[1]
      ns.Run.play(run, { 1 })
      local after = disabledUids(run)
      T.eq(#after, 1)
      T.ok(after[1] ~= before, "seed " .. seed .. ": a different trinket each hand")
    end
  end
  local solo = finisherRun(5, "RAGNAROS", { { uid = 1, id = "ARCANE_INTELLECT" } })
  solo.target = 1e9
  ns.Run.play(solo, { 1 })
  T.eq(disabledUids(solo), { 1 }, "the only trinket is picked again")
end)

T.test("medallion_brings_wall_and_vessel_to_2x", function()
  for _, case in ipairs({ { "PATCHWERK", 3 }, { "CTHUN", 8 } }) do
    local id, stage = case[1], case[2]
    local function start()
      local run = ns.Run.new(5, "ADVENTURER")
      run.stage, run.blind, run.bosses[stage] = stage, 3, id
      T.startBlind(run)
      run.trinkets = { ns.Trinkets.create(run, "GLAD_MEDALLION") }
      return run
    end
    local run = start()
    T.eq(run.target, ns.Run.target(run, stage, 3, id))
    T.ok(ns.Run.sellTrinket(run, 1))
    T.eq(run.bossDisabled, true, id)
    T.eq(run.target, ns.Run.BASE_TARGETS[stage] * 2, id .. " target is base x2")
    T.eq(run.phase, "play")
    local won = start()
    won.score = ns.Run.BASE_TARGETS[stage] * 2
    local gold, value = won.gold, ns.Shop.sellValue(won.trinkets[1])
    T.ok(ns.Run.sellTrinket(won, 1))
    T.eq(won.phase, stage == 8 and "won" or "shop", id .. " wins at once")
    T.eq(#won.trinkets, 0, "the Medallion is gone before the payout")
    T.eq(won.gold, gold + value + won.lastPayout.total, "sale and payout both paid")
  end
end)

T.test("ragnaros_disabled_trinket_sells_without_its_effect", function()
  local run = finisherRun(5, "RAGNAROS", {})
  run.trinkets = { ns.Trinkets.create(run, "GLAD_MEDALLION") }
  run.trinkets[1].disabled = true
  T.ok(ns.Run.sellTrinket(run, 1))
  T.eq(run.bossDisabled, false, "a disabled Gladiator's Medallion does not disable the boss")
end)

T.test("ragnaros_disabled_trinket_loses_its_passive", function()
  local run = finisherRun(5, "RAGNAROS", {})
  run.target = 1e9
  run.trinkets = { ns.Trinkets.create(run, "REAGENT_BAG") }
  local on = ns.Deck.handSize(run)
  run.trinkets[1].disabled = true
  T.eq(ns.Deck.handSize(run), on - 1, "a disabled hand-size trinket gives no hand size")
  T.eq(ns.Trinkets.mods(run).handSize, 0)
  run.trinkets[1].disabled = nil
  T.eq(ns.Deck.handSize(run), on, "restored when re-enabled")
  -- The re-pick settles through withMods: a shrink never discards, a growth draws up.
  local fresh = finisherRun(5, "RAGNAROS", { ns.Trinkets.create(ns.Run.new(5, "ADVENTURER"), "REAGENT_BAG") })
  fresh.target = 1e9
  T.ok(fresh.trinkets[1].disabled)
  T.eq(ns.Deck.handSize(fresh), 8, "the only trinket is disabled for the first hand")
  T.eq(#fresh.hand, 9, "drawn before the pick, and a shrink never discards")
  ns.Run.play(fresh, { 1, 2 })
  T.ok(fresh.trinkets[1].disabled)
  T.eq(#fresh.hand, 8, "refilled to the smaller size")
  ns.Run.disableBoss(fresh)
  T.eq(#fresh.hand, 9, "re-enabled, the hand draws up")
  -- Interest counts a trinket that was disabled when the blind ends.
  ns.Trinkets.def.TEST_INTEREST = { id = "TEST_INTEREST", interestBonus = 1 }
  local paid, disabled, bonus
  local ok, err = pcall(function()
    paid = finisherRun(5, "RAGNAROS", { { uid = 50, id = "TEST_INTEREST" } })
    disabled, bonus = paid.trinkets[1].disabled, ns.Trinkets.interestBonus(paid)
    paid.gold = 25
    ns.Run.winBlind(paid)
  end)
  ns.Trinkets.def.TEST_INTEREST = nil -- removed before any assert can fail
  T.ok(ok, err)
  T.ok(disabled)
  T.eq(bonus, 0, "a disabled interest trinket adds nothing")
  T.eq(paid.lastPayout.interest, 10, "cleared before the payout: 5 units x 2")
end)

T.test("ragnaros_disabled_saver_does_not_save", function()
  local run = finisherRun(5, "RAGNAROS", {})
  run.trinkets = { ns.Trinkets.create(run, "SOULSTONE") }
  run.trinkets[1].disabled = true
  run.target, run.score, run.handsLeft = 1e9, 5e8, 1
  ns.Run.play(run, { 1 })
  T.eq(run.phase, "lost", "a disabled Soulstone does not save the run")
  T.eq(#run.trinkets, 1, "and is not used up")
  T.ok(not run.trinkets[1].disabled, "cleared once the run is lost")
  local saved = finisherRun(5, "RAGNAROS", {})
  saved.trinkets = { ns.Trinkets.create(saved, "SOULSTONE") }
  saved.target, saved.score, saved.handsLeft = 1e9, 5e8, 1
  ns.Run.play(saved, { 1 })
  T.ok(saved.phase ~= "lost", "an enabled Soulstone still saves")
end)
