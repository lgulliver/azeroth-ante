local ns, T = ...

ns.Shop = ns.Shop or { open = function() end }

local function copy(value)
  T.ok(type(value) ~= "function", "run contains a function")
  if type(value) ~= "table" then return value end
  T.eq(getmetatable(value), nil)
  local out = {}
  for k, v in pairs(value) do out[copy(k)] = copy(v) end
  return out
end

local function playing(deckId, bossId)
  local run = ns.Run.new(7, deckId or "ADVENTURER")
  if bossId then run.blind, run.bosses[1] = 3, bossId end
  ns.Run.startBlind(run)
  return run
end

T.test("new_run_shape", function()
  local run = ns.Run.new(7, "ADVENTURER")
  T.eq(run.seed, 7)
  T.eq(run.deckId, "ADVENTURER")
  T.eq(run.stage, 1)
  T.eq(run.blind, 1)
  T.eq(run.phase, "blind")
  T.eq(run.gold, 4)
  T.eq(run.handSize, 8)
  T.eq(run.maxTrinkets, 5)
  T.eq(run.trinkets, {})
  T.eq(run.handsPlayedTotal, 0)
  T.eq(run.score, 0)
  T.eq(run.target, 300)
  T.eq(run.handsLeft, 4)
  T.eq(run.discardsLeft, 3)
  T.eq(run.pile, {})
  T.eq(run.hand, {})
  T.eq(run.lastResult, nil)
  T.eq(run.lastPayout, nil)
  for _, id in ipairs(ns.Hands.order) do T.eq(run.handLevels[id], 1) end
  T.eq(#run.bosses, 8)
  T.eq(run.bosses[8], "RAGNAROS")
  local seen, pool = {}, {}
  for _, id in ipairs(ns.Bosses.pool) do pool[id] = true end
  for i, id in ipairs(run.bosses) do
    T.ok(not seen[id], "duplicate boss")
    if i < 8 then T.ok(pool[id], "boss outside pool") end
    seen[id] = true
  end
  T.eq(copy(run), run)
  T.ok(type(run.rng.s) == "number")
end)

T.test("targets", function()
  T.eq(ns.Run.BASE_TARGETS, { 300, 800, 2000, 5000, 11000, 20000, 35000, 50000 })
  T.eq(ns.Run.target(1, 1), 300)
  T.eq(ns.Run.target(1, 2), 450)
  T.eq(ns.Run.target(2, 3, "HOGGER"), 1600)
  T.eq(ns.Run.target(8, 3, "RAGNAROS"), 200000)
end)

T.test("start_blind_deals_8", function()
  local run = playing()
  T.eq(run.phase, "play")
  T.eq(#run.hand, 8)
  T.eq(#run.pile, 44)
  local seen = {}
  for _, list in ipairs({ run.hand, run.pile }) do
    for _, card in ipairs(list) do
      T.ok(not seen[card.id], "duplicate card")
      seen[card.id] = true
    end
  end
  run.score, run.handsLeft, run.discardsLeft = 100, 1, 0
  ns.Run.startBlind(run)
  T.eq(#run.hand, 8)
  T.eq(#run.pile, 44)
  T.eq(run.score, 0)
  T.eq(run.target, 300)
  T.eq(run.handsLeft, 4)
  T.eq(run.discardsLeft, 3)
end)

T.test("deck_values_and_boss_overrides", function()
  T.eq(playing("WARRIOR").handsLeft, 5)
  T.eq(playing("ROGUE").discardsLeft, 4)
  T.eq(ns.Run.new(7, "GOBLIN").gold, 10)
  local run = playing("WARRIOR", "ONYXIA")
  T.eq(run.handsLeft, 1)
  T.eq(run.target, 300)
  T.eq(ns.Run.bossId(run), "ONYXIA")
  run.blind = 2
  T.eq(ns.Run.bossId(run), nil)
end)

T.test("can_play_rejects_bad_selection", function()
  local run = playing()
  for _, idx in ipairs({ {}, { 1, 2, 3, 4, 5, 6 }, { 1, 1 }, { 9 }, { 0 }, { 1.5 }, { "1" } }) do
    local ok, reason = ns.Run.canPlay(run, idx)
    T.eq(ok, false)
    T.ok(type(reason) == "string" and #reason > 0)
    T.eq(ns.Run.canDiscard(run, idx), false)
  end
  T.eq(ns.Run.canPlay(run, { 1, 3, 5, 7, 8 }), true)
  run.phase = "blind"
  T.eq(ns.Run.canPlay(run, { 1 }), false)
  T.eq(ns.Run.canDiscard(run, { 1 }), false)
end)

T.test("herod_requires_five", function()
  local run = playing(nil, "HEROD")
  local ok, reason = ns.Run.canPlay(run, { 1, 2, 3, 4 })
  T.eq(ok, false)
  T.ok(type(reason) == "string" and #reason > 0)
  T.eq(ns.Run.canPlay(run, { 1, 2, 3, 4, 5 }), true)
  T.eq(ns.Run.canDiscard(run, { 1 }), true)
end)

T.test("mutanus_no_discards", function()
  local run = playing("ROGUE", "MUTANUS")
  T.eq(run.discardsLeft, 0)
  T.eq(ns.Run.canDiscard(run, { 1 }), false)
end)

T.test("play_reaches_target_goes_shop", function()
  local run = playing("GOBLIN")
  run.target = 1
  local oldOpen, seen = ns.Shop.open, nil
  ns.Shop.open = function(r) seen = { run = r, phase = r.phase, gold = r.gold } end
  local ok, err = pcall(function() ns.Run.play(run, { 1 }) end)
  ns.Shop.open = oldOpen
  if not ok then error(err, 0) end
  T.eq(run.phase, "shop")
  T.eq(run.gold, 18)
  T.eq(run.lastPayout, { reward = 3, hands = 3, interest = 2, trinkets = 0, total = 8 })
  T.ok(seen and seen.run == run)
  T.eq(seen.phase, "shop")
  T.eq(seen.gold, 18)
end)

T.test("play_scores_selected_positions_and_refills", function()
  local run = playing()
  local before, pile = copy(run.hand), copy(run.pile)
  run.target = 1000000
  local result = ns.Run.play(run, { 5, 2, 7 })
  local expected = ns.Scoring.score({ cards = { before[5], before[2], before[7] },
    handLevels = run.handLevels, trinkets = {}, handsPlayedTotal = 1,
    isLastHand = false, discardsLeft = 3, gold = 4, rng = ns.RNG.new(1) })
  T.eq(result, expected)
  T.eq(run.score, expected.total)
  T.eq(run.lastResult, result)
  T.eq(run.handsPlayedTotal, 1)
  T.eq(run.handsLeft, 3)
  T.eq(run.discardsLeft, 3)
  T.eq(run.hand, { before[1], before[3], before[4], before[6], before[8], pile[44], pile[43], pile[42] })
  T.eq(#run.pile, 41)
  T.eq(run.phase, "play")
  T.eq(copy(run), run)
end)

T.test("scoring_receives_run_context", function()
  local run = playing(nil, "HOGGER")
  run.hand = { { rank = 13, suit = "S", id = 12 } }
  run.handsLeft, run.handsPlayedTotal, run.gold = 1, 4, 10
  run.handLevels.HIGH_CARD = 2
  run.trinkets = { { id = "BLOODLUST" }, { id = "EXECUTE" },
    { id = "COMBO_POINTS" }, { id = "GOBLIN_BANK" } }
  run.target = 1000000
  local result = ns.Run.play(run, { 1 })
  T.eq(result.chips, 75)
  T.eq(result.mult, 20)
  T.eq(result.total, 1500)
  T.eq(result.events[2].kind, "debuff")
  T.eq(run.handsPlayedTotal, 5)
end)

T.test("discard_removes_positions_and_refills", function()
  local run = playing()
  local before, pile = copy(run.hand), copy(run.pile)
  ns.Run.discard(run, { 6, 1, 3 })
  T.eq(run.hand, { before[2], before[4], before[5], before[7], before[8], pile[44], pile[43], pile[42] })
  T.eq(#run.pile, 41)
  T.eq(run.discardsLeft, 2)
  T.eq(run.handsLeft, 4)
  T.eq(run.handsPlayedTotal, 0)
  T.eq(run.score, 0)
  T.eq(run.lastResult, nil)
end)

T.test("invalid_actions_preserve_run", function()
  local run = playing()
  local before = copy(run)
  ns.Run.play(run, { 1, 1 })
  ns.Run.discard(run, { 9 })
  ns.Run.nextBlind(run)
  T.eq(run, before)
end)

T.test("run_out_of_hands_lost", function()
  local run = playing()
  run.target = 1000000
  for _ = 1, 4 do ns.Run.play(run, { 1 }) end
  T.eq(run.handsLeft, 0)
  T.eq(run.phase, "lost")
  T.eq(run.lastPayout, nil)
  local before = copy(run)
  ns.Run.play(run, { 1 })
  ns.Run.discard(run, { 1 })
  T.eq(run, before)
end)

T.test("final_boss_win_is_won", function()
  local run = playing()
  run.stage, run.blind = 8, 3
  ns.Run.startBlind(run)
  T.eq(run.target, 200000)
  run.target, run.handsLeft = 1, 1
  local oldOpen = ns.Shop.open
  ns.Shop.open = function() error("final win must not open shop") end
  local ok, err = pcall(function() ns.Run.play(run, { 1 }) end)
  ns.Shop.open = oldOpen
  if not ok then error(err, 0) end
  T.eq(run.phase, "won")
  T.eq(run.handsLeft, 0)
  T.eq(run.gold, 9)
  T.eq(run.lastPayout.reward, 5)
end)

T.test("payout_rewards_interest_cap_and_trinkets", function()
  local run = playing()
  run.gold, run.blind, run.handsLeft = 29, 2, 2
  run.trinkets = { { id = "HEARTHSTONE" }, { id = "ARCANE_INTELLECT" } }
  ns.Run.winBlind(run)
  T.eq(run.lastPayout, { reward = 4, hands = 2, interest = 5, trinkets = 3, total = 14 })
  T.eq(run.gold, 43)
end)

T.test("round_end_receives_run", function()
  local run = playing()
  run.trinkets = { { id = "TEST_ROUND_END" } }
  ns.Trinkets.def.TEST_ROUND_END = { onRoundEnd = function(r)
    T.ok(r == run)
    return r.discardsLeft
  end }
  local ok, err = pcall(function() ns.Run.winBlind(run) end)
  ns.Trinkets.def.TEST_ROUND_END = nil
  if not ok then error(err, 0) end
  T.eq(run.lastPayout.trinkets, 3)
end)

T.test("next_blind_advances_only_from_shop", function()
  local run = ns.Run.new(7, "ADVENTURER")
  for stage = 1, 8 do
    for blind = 1, 3 do
      T.eq(run.stage, stage)
      T.eq(run.blind, blind)
      T.eq(run.phase, "blind")
      if stage < 8 or blind < 3 then
        run.phase = "shop"
        ns.Run.nextBlind(run)
      end
    end
  end
  run.phase = "won"
  ns.Run.nextBlind(run)
  T.eq(run.stage, 8)
  T.eq(run.blind, 3)
  T.eq(run.phase, "won")
end)

T.test("sort_hand", function()
  local run = playing()
  run.hand = { { rank = 5, suit = "H", id = 17 }, { rank = 14, suit = "D", id = 52 },
    { rank = 3, suit = "S", id = 2 } }
  ns.Run.sortHand(run, "rank")
  T.eq({ run.hand[1].id, run.hand[2].id, run.hand[3].id }, { 52, 17, 2 })
  ns.Run.sortHand(run, "suit")
  T.eq({ run.hand[1].id, run.hand[2].id, run.hand[3].id }, { 2, 17, 52 })
end)

T.test("same_seed_same_run", function()
  local a, b = playing(), playing()
  T.eq(a, b)
  a.trinkets, b.trinkets = { { id = "LUCKY_CHARM" } }, { { id = "LUCKY_CHARM" } }
  a.target, b.target = 1000000, 1000000
  local rngBefore = a.rng.s
  T.eq(ns.Run.play(a, { 1, 2, 3, 4, 5 }), ns.Run.play(b, { 1, 2, 3, 4, 5 }))
  T.ok(a.rng.s ~= rngBefore, "scoring must consume run RNG")
  T.eq(a, b)
end)
