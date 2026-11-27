local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

-- A boss blind in play against `bossId`.
local function bossRun(bossId, deckId)
  local run = ns.Run.new(5, deckId or "ROGUE")
  run.stage, run.blind = 2, 3
  run.bosses[2] = bossId
  return run
end

H.test("ragnaros_disabled_trinket_skips_round_end", function()
  H.stub { id = "PAYER", onRoundEnd = function() return 7 end }
  local run = bossRun("RAGNAROS")
  run.stage, run.bosses[8] = 8, "RAGNAROS"
  run.trinkets = { ns.Trinkets.create(run, "PAYER") }
  T.startBlind(run)
  T.ok(run.trinkets[1].disabled, "Ragnaros disabled the only trinket")
  run.stage = 7 -- not the last blind, so the round pays out and the shop opens
  run.bosses[7] = "RAGNAROS"
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.trinkets, 0, "no payout from the disabled trinket")
  T.ok(not run.trinkets[1].disabled, "back on for the shop")
end)

H.test("ragnaros_disabled_trinket_still_counts_for_interest", function()
  H.stub { id = "VAULT", interestBonus = 1 }
  local run = bossRun("RAGNAROS")
  run.bosses[2] = "RAGNAROS"
  run.trinkets = { ns.Trinkets.create(run, "VAULT") }
  T.startBlind(run)
  T.ok(run.trinkets[1].disabled)
  run.gold = 10
  ns.Run.winBlind(run)
  T.eq(run.lastPayout.interest, 4, "two units, doubled")
end)

T.test("orbital_hand_picked_when_rolled", function()
  for seed = 1, 400 do
    local run = ns.Run.new(seed, "ROGUE")
    run.stage = 2
    ns.Tags.rollBlindTags(run)
    for i = 1, 2 do
      if run.blindTags[i] == "ORBITAL" then
        local want = run.orbitalHands[i]
        T.ok(ns.Hands.def[want], "a hand is picked")
        local before = run.handLevels[want]
        run.blind = i
        run.phase = "blind"
        if i == 2 then run.skippedBlinds[1] = true end
        ns.Run.skipBlind(run)
        T.eq(run.handLevels[want], before + 3, "the rolled hand is levelled")
        return
      end
    end
  end
  error("no Orbital tag rolled in 400 seeds")
end)

T.test("two_vendor_restocks_give_two_extra_vouchers", function()
  local run = ns.Run.new(3, "ROGUE")
  run.phase, run.gold = "shop", 200
  run.tags = { "VOUCHER", "VOUCHER" }
  ns.Shop.open(run)
  T.eq(run.tags, {}, "both tags spent")
  local first = run.shop.extraVoucher
  T.ok(first, "an extra voucher")
  T.ok(ns.Shop.buyVoucher(run, "extra"))
  local second = run.shop.extraVoucher
  T.ok(second and second.id ~= first.id, "a second extra voucher after the first is bought")
  T.ok(ns.Shop.buyVoucher(run, "extra"))
  T.eq(run.shop.extraVoucher, false)
end)

H.test("not_allowed_hand_still_runs_after_hooks", function()
  H.stub { id = "MELTER", after = function(_, self)
    self.state.n = (self.state.n or 0) + 1
    return { msg = "-1" }
  end }
  local run = bossRun("GLUTH")
  run.trinkets = { ns.Trinkets.create(run, "MELTER") }
  T.startBlind(run)
  run.roundFirstHand = "FLUSH" -- only a Flush is allowed now
  local result = H.score(run, { H.card(5, "S"), H.card(5, "H") })
  T.ok(result.notAllowed, "the Pair is not allowed")
  T.eq(result.total, 0)
  T.eq(result.trinketsAfter[1].state.n, 1, "the after hook ran")
end)

T.test("ragnaros_never_picks_or_revives_a_perished_trinket", function()
  local run = bossRun("RAGNAROS")
  run.bosses[2] = "RAGNAROS"
  local dead = ns.Trinkets.create(run, "ARCANE_INTELLECT")
  dead.perished, dead.disabled = true, true
  local live = ns.Trinkets.create(run, "FORTITUDE")
  run.trinkets = { dead, live }
  for _ = 1, 20 do
    T.startBlind(run)
    T.ok(live.disabled, "the live trinket is the only pick")
    T.ok(dead.disabled, "the perished one stays disabled")
    run.phase = "blind"
  end
end)

T.test("ashbringer_arriving_mid_boss", function()
  local run = bossRun("THREDD")
  T.startBlind(run)
  T.ok(not run.bossDisabled)
  -- Arrives without its blind-select hook having run: any action through withMods catches it.
  run.trinkets = { ns.Trinkets.create(run, "ASHBRINGER") }
  ns.Run.withMods(run, function() end)
  T.ok(run.bossDisabled, "disabled as soon as it is owned")
end)
