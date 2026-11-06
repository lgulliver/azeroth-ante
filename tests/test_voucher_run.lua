local ns, T = ...

ns.Shop = ns.Shop or { open = function() end }

local function fresh(deckId)
  local run = ns.Run.new(11, deckId or "ADVENTURER")
  return run
end

local function withEvents(fn)
  local saved, events = ns.Profile, {}
  ns.Profile = { onEvent = function(name, amount) events[#events + 1] = { name, amount } end }
  local ok, err = pcall(fn, events)
  ns.Profile = saved
  if not ok then error(err, 0) end
  return events
end

local function names(events)
  local out = {}
  for _, e in ipairs(events) do out[#out + 1] = e[1] end
  return out
end

local function has(events, name, amount)
  for _, e in ipairs(events) do
    if e[1] == name and (amount == nil or e[2] == amount) then return true end
  end
  return false
end

T.test("grabber_wasteful_paintbrush", function()
  local base = fresh()
  ns.Run.startBlind(base)
  local run = fresh()
  run.vouchers.GRABBER, run.vouchers.WASTEFUL, run.vouchers.PAINT_BRUSH = true, true, true
  ns.Run.startBlind(run)
  T.eq(run.handsLeft, base.handsLeft + 1)
  T.eq(run.discardsLeft, base.discardsLeft + 1)
  T.eq(#run.hand, 9)
  T.eq(ns.Deck.handSize(run), ns.Deck.handSize(base) + 1)
end)

T.test("crystal_ball_slot", function()
  local run = fresh()
  run.vouchers.CRYSTAL_BALL = true
  T.eq(ns.Consumables.slots(run), 3)
  for i = 1, 3 do T.ok(ns.Consumables.add(run, { kind = "tome", id = "PAIR" }), "slot " .. i) end
  T.ok(not ns.Consumables.add(run, { kind = "tome", id = "PAIR" }), "fourth refused")
end)

T.test("antimatter_slot", function()
  local run = fresh()
  local before = ns.Run.trinketSlots(run)
  run.vouchers.ANTIMATTER = true
  T.eq(ns.Run.trinketSlots(run), before + 1)
end)

T.test("seed_money_cap", function()
  local function payout(vouchers, gold)
    local run = fresh()
    run.gold, run.hand = gold, {}
    for id in pairs(vouchers) do run.vouchers[id] = true end
    ns.Run.startBlind(run)
    run.hand = {}
    ns.Run.winBlind(run)
    return run.lastPayout.interest
  end
  T.eq(payout({}, 100), 5)
  T.eq(payout({ SEED_MONEY = true }, 100), 10)
  T.eq(payout({ SEED_MONEY = true }, 32), 6)
  T.eq(payout({ SEED_MONEY = true, MONEY_TREE = true }, 200), 20)
end)

T.test("max_interest_streak", function()
  local events = withEvents(function()
    local run = fresh()
    run.gold = 100
    ns.Run.startBlind(run)
    run.hand = {}
    ns.Run.winBlind(run)
    T.eq(run.streak.maxInterest, 1)
    run.phase, run.gold = "play", 100
    ns.Run.winBlind(run)
    T.eq(run.streak.maxInterest, 2)
    run.phase, run.gold = "play", 0
    ns.Run.winBlind(run)
    T.eq(run.streak.maxInterest, 0)
  end)
  local streaks = {}
  for _, e in ipairs(events) do
    if e[1] == "maxInterestStreak" then streaks[#streaks + 1] = e[2] end
  end
  T.eq(streaks, { 1, 2, 0 })
end)

T.test("hieroglyph_floor", function()
  local run = fresh()
  run.phase, run.gold, run.stage = "shop", 20, 1
  run.shop = { cards = {}, packs = {}, rerollCost = 5 }
  run.shopVoucher = { id = "HIEROGLYPH" }
  T.ok(ns.Shop.buyVoucher(run))
  T.eq(run.gold, 10)
  T.eq(run.stage, 1)
  local base = fresh()
  ns.Run.startBlind(base)
  ns.Run.startBlind(run)
  T.eq(run.handsLeft, base.handsLeft - 1)
end)

T.test("hieroglyph_mid", function()
  local run = fresh()
  run.phase, run.gold, run.stage = "shop", 20, 3
  run.shop = { cards = {}, packs = {}, rerollCost = 5 }
  run.shopVoucher = { id = "HIEROGLYPH" }
  T.ok(ns.Shop.buyVoucher(run))
  T.eq(run.stage, 2)
end)

local function atBoss(stage)
  local run = fresh()
  run.stage, run.blind, run.phase, run.gold = stage or 1, 3, "blind", 50
  return run
end

T.test("boss_reroll_once", function()
  local run = atBoss()
  run.vouchers.DIRECTORS_CUT = true
  local old = run.bosses[1]
  local ok, id = ns.Run.rerollBoss(run)
  T.ok(ok)
  T.ok(id ~= old, "different boss")
  T.eq(run.bosses[1], id)
  T.eq(run.gold, 40)
  T.eq(run.bossRerollsUsed, 1)
  local ok2 = ns.Run.canRerollBoss(run)
  T.ok(not ok2, "only once")
  -- a new stage resets the counter
  run.phase = "shop"
  ns.Run.nextBlind(run)
  T.eq(run.bossRerollsUsed, 0)
end)

T.test("boss_reroll_needs_voucher_and_gold", function()
  local run = atBoss()
  T.ok(not ns.Run.canRerollBoss(run), "no voucher")
  run.vouchers.DIRECTORS_CUT, run.gold = true, 9
  T.ok(not ns.Run.canRerollBoss(run), "no gold")
  run.gold, run.phase = 10, "play"
  T.ok(not ns.Run.canRerollBoss(run), "wrong phase")
end)

T.test("boss_reroll_any_blind", function()
  local run = atBoss()
  run.vouchers.DIRECTORS_CUT, run.blind = true, 1
  T.ok(ns.Run.canRerollBoss(run), "blind 1")
  local old = run.bosses[1]
  local ok, id = ns.Run.rerollBoss(run)
  T.ok(ok and id ~= old)
  T.eq(run.bosses[1], id)
end)

T.test("consumable_sell_value", function()
  T.eq(ns.Consumables.sellValue({ kind = "tome", id = "PAIR", paid = 7 }), 3)
  T.eq(ns.Consumables.sellValue({ kind = "relic", id = "X" }), 2)
  T.eq(ns.Vouchers.owns({}, "GRABBER"), false)
end)

T.test("retcon_unlimited", function()
  local run = atBoss()
  run.vouchers.DIRECTORS_CUT, run.vouchers.RETCON = true, true
  run.gold = 100
  for _ = 1, 5 do T.ok(ns.Run.rerollBoss(run)) end
  T.eq(run.gold, 50)
  T.eq(run.bossRerollsUsed, 5)
end)

T.test("boss_reroll_never_final", function()
  local run = atBoss(8)
  run.vouchers.DIRECTORS_CUT, run.vouchers.RETCON = true, true
  local ok = ns.Run.canRerollBoss(run)
  T.ok(not ok)
  T.ok(not ns.Run.rerollBoss(run))
  T.eq(run.bosses[8], ns.Bosses.FINAL)
  T.eq(run.gold, 50)
end)

T.test("boss_reroll_exhausted_pool", function()
  local run = atBoss()
  run.vouchers.DIRECTORS_CUT, run.vouchers.RETCON = true, true
  for _, id in ipairs(ns.Bosses.pool) do run.bossesFought[id] = true end
  run.gold = 1000
  for _ = 1, 20 do
    local old = run.bosses[1]
    local ok, id = ns.Run.rerollBoss(run)
    T.ok(ok)
    T.ok(id ~= old, "differs from current")
    T.ok(id ~= "RAGNAROS", "never the final boss")
  end
end)

T.test("boss_reroll_skips_fought", function()
  local run = atBoss()
  run.vouchers.DIRECTORS_CUT, run.vouchers.RETCON = true, true
  run.gold = 1000
  local keep = ns.Bosses.pool[1]
  for _, id in ipairs(ns.Bosses.pool) do
    if id ~= keep then run.bossesFought[id] = true end
  end
  run.bosses[1] = ns.Bosses.pool[2]
  local _, id = ns.Run.rerollBoss(run)
  T.eq(id, keep)
end)

T.test("observatory_xmult", function()
  local function score(consumables)
    local cards = {
      { rank = 9, suit = "S", id = 1 }, { rank = 9, suit = "H", id = 2 },
      { rank = 3, suit = "C", id = 3 },
    }
    return ns.Scoring.score({ cards = cards, held = {}, handLevels = {}, trinkets = {},
      rng = ns.RNG.new(1), consumables = consumables })
  end
  local base = score(nil)
  T.eq(base.handId, "PAIR")
  local boosted = score({ { kind = "tome", id = "PAIR" }, { kind = "tome", id = "FLUSH" } })
  T.eq(boosted.mult, base.mult * 1.5)
  local last = boosted.events[#boosted.events - 1]
  T.eq(last.kind, "voucher")
  T.eq(last.id, "OBSERVATORY")
  T.eq(last.xmult, 1.5)
  local two = score({ { kind = "tome", id = "PAIR" }, { kind = "tome", id = "PAIR" } })
  T.eq(two.mult, base.mult * 2.25)
  -- Run.play only passes consumables when the voucher is owned.
  local run = fresh()
  run.consumables = { { kind = "tome", id = "HIGH_CARD" }, { kind = "tome", id = "PAIR" }, { kind = "tome", id = "TRIPLE" } }
  ns.Run.startBlind(run)
  run.hand = { { rank = 9, suit = "S", id = 1 }, { rank = 9, suit = "H", id = 2 }, { rank = 3, suit = "C", id = 3 } }
  local plain = ns.Run.play(run, { 1, 2 })
  local hasVoucher = false
  for _, e in ipairs(plain.events) do if e.kind == "voucher" then hasVoucher = true end end
  T.ok(not hasVoucher, "no voucher no bonus")
  run.vouchers.OBSERVATORY = true
  run.phase = "play"
  run.hand = { { rank = 9, suit = "S", id = 1 }, { rank = 9, suit = "H", id = 2 }, { rank = 3, suit = "C", id = 3 } }
  local boosted2 = ns.Run.play(run, { 1, 2 })
  local n = 0
  for _, e in ipairs(boosted2.events) do if e.kind == "voucher" then n = n + 1 end end
  T.eq(n, 1)
end)

T.test("events_from_run", function()
  local events = withEvents(function()
    local run = fresh()
    run.bosses[1] = ns.Bosses.pool[1]
    run.blind = 3
    run.trinkets = { { id = "X", ed = "FOIL" }, { id = "Y" } }
    ns.Run.startBlind(run)
    ns.Run.discard(run, { 1, 2 })
    ns.Run.play(run, { 1, 2, 3 })
    T.eq(run.bossesFought[ns.Bosses.pool[1]], true)
    local plays = 0
    for _, n in pairs(run.handPlays) do plays = plays + n end
    T.eq(plays, 1)
  end)
  T.ok(has(events, "bossFought", ns.Bosses.pool[1]), "bossFought")
  T.ok(has(events, "handSize", 8), "handSize")
  T.ok(has(events, "editionTrinkets", 1), "editionTrinkets")
  T.ok(has(events, "cardsDiscarded", 2), "cardsDiscarded")
  T.ok(has(events, "cardsPlayed", 3), "cardsPlayed")
end)

T.test("events_run_ended", function()
  local events = withEvents(function()
    local run = fresh()
    run.stage, run.blind = 8, 3
    ns.Run.startBlind(run)
    run.hand = {}
    run.score = run.target
    ns.Run.winBlind(run)
    T.eq(run.phase, "won")
    local lost = fresh()
    ns.Run.startBlind(lost)
    lost.handsLeft = 1
    lost.target = 10 ^ 9
    ns.Run.play(lost, { 1 })
    T.eq(lost.phase, "lost")
  end)
  T.ok(has(events, "runEnded", 1), "won")
  T.ok(has(events, "runEnded", 0), "lost")
end)

T.test("consumable_sell_uses_paid", function()
  local run = fresh()
  run.consumables = { { kind = "tome", id = "PAIR", paid = 7 }, { kind = "tome", id = "PAIR" } }
  run.gold = 0
  T.eq(ns.Consumables.sell(run, 1), 3)
  T.eq(run.gold, 3)
  T.eq(ns.Consumables.sell(run, 1), 1)
end)

T.test("blind_hands_discards_helpers", function()
  local run = fresh()
  local deck = ns.Decks.def[run.deckId]
  T.eq(ns.Run.blindHands(run), deck.hands)
  T.eq(ns.Run.blindDiscards(run), deck.discards)
  run.vouchers.GRABBER, run.vouchers.WASTEFUL = true, true
  T.eq(ns.Run.blindHands(run), deck.hands + 1)
  T.eq(ns.Run.blindDiscards(run), deck.discards + 1)
  ns.Run.startBlind(run)
  T.eq(run.handsLeft, ns.Run.blindHands(run), "startBlind uses the helper")
  T.eq(run.discardsLeft, ns.Run.blindDiscards(run))
end)

T.test("blind_hands_discards_hieroglyph_and_boss", function()
  local run = fresh()
  run.vouchers.HIEROGLYPH, run.vouchers.PETROGLYPH = true, true
  T.eq(ns.Run.blindHands(run), ns.Decks.def[run.deckId].hands - 1)
  T.eq(ns.Run.blindDiscards(run), ns.Decks.def[run.deckId].discards - 1)
  run.blind, run.bosses[run.stage] = 3, "ONYXIA" -- one hand only: still at least 1
  T.eq(ns.Run.blindHands(run), 1)
  run.bosses[run.stage] = "MUTANUS" -- no discards: still at least 0
  T.eq(ns.Run.blindDiscards(run), 0)
  run.vouchers = { WASTEFUL = true }
  T.eq(ns.Run.blindDiscards(run), 1)
end)

T.test("hieroglyph_replay_rerolls_fought_boss", function()
  for _, id in ipairs({ "HIEROGLYPH", "PETROGLYPH" }) do
    local run = fresh()
    run.phase, run.gold, run.stage, run.blind = "shop", 20, 3, 3
    local old = run.bosses[3]
    run.bossesFought[old] = true
    run.shop = { cards = {}, packs = {}, rerollCost = 5 }
    run.shopVoucher = { id = id }
    T.ok(ns.Shop.buyVoucher(run))
    T.eq(run.stage, 2)
    ns.Run.nextBlind(run)
    T.eq(run.stage, 3)
    T.eq(run.blind, 1)
    local new = run.bosses[3]
    T.ok(new ~= old, "replayed stage got a new boss")
    T.ok(new ~= "RAGNAROS" and not run.bossesFought[new], "a fresh, non-final boss")
    T.ok(ns.Bosses.def[new] ~= nil)
  end
end)

T.test("hieroglyph_replay_keeps_final_and_unfought_bosses", function()
  local run = fresh()
  run.phase, run.gold, run.stage, run.blind = "shop", 20, 1, 3
  run.bossesFought[run.bosses[1]] = true
  local before = run.bosses[1]
  ns.Vouchers.onBuy(run, "HIEROGLYPH")
  T.eq(run.stage, 1)
  T.eq(run.bosses[1], before, "no stage to go back to: nothing replays")
  run.stage, run.blind = 8, 1
  ns.Vouchers.onBuy(run, "HIEROGLYPH")
  T.eq(run.bosses[7] ~= nil, true)
  T.eq(run.bosses[8], "RAGNAROS")
end)
