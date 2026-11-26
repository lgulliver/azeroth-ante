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
  T.eq(ns.Run.target(8, 3, "CTHUN"), 300000)
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
  ns.Run.startBlind(run)
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
  ns.Run.startBlind(fresh)
  T.eq(#fresh.hand, 8)
end)

T.test("patchwerk_target_4x", function()
  T.eq(ns.Run.target(2, 3, "PATCHWERK"), 3200)
  T.eq(ns.Bosses.def.PATCHWERK.minStage, 2)
end)

T.test("archaedas_debuffs_cards_played_this_ante", function()
  local run = ns.Run.new(5, "ADVENTURER")
  run.bosses[run.stage] = "ARCHAEDAS"
  ns.Run.startBlind(run)
  run.target = 1e9
  local card = run.hand[1]
  ns.Run.play(run, { 1 })
  T.ok(run.playedThisAnte[card.id])
  -- The card is met again in the boss blind.
  run.blind = 3
  ns.Run.startBlind(run)
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
