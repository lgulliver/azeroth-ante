local ns, T = ...

local function run(stake, seed)
  return ns.Run.new(seed or 5, "ROGUE", stake)
end

local function shopRun(stake)
  local r = run(stake)
  r.phase, r.gold = "shop", 100
  return r
end

T.test("stakes_ladder_defined", function()
  T.eq(#ns.Stakes.order, 8)
  T.eq(run().stake, 1)
  T.eq(ns.Stakes.of({}), 1)
  T.ok(ns.Stakes.has(run(4), "BLACK") and not ns.Stakes.has(run(4), "BLUE"), "stakes stack up to their own")
end)

T.test("red_stake_small_blind_pays_nothing", function()
  local r = run(2)
  r.blind = 1
  T.eq(ns.Run.blindReward(r), 0)
  r.blind = 2
  T.eq(ns.Run.blindReward(r), 4)
  local w = run(1)
  w.blind = 1
  T.eq(ns.Run.blindReward(w), 3)
end)

T.test("green_and_purple_targets", function()
  T.eq(ns.Run.target(run(2), 8, 1), 50000)
  T.eq(ns.Run.target(run(3), 2, 1), 900)
  T.eq(ns.Run.target(run(3), 8, 1), 100000)
  T.eq(ns.Run.target(run(6), 3, 2), 4800)
  T.eq(ns.Run.target(run(6), 8, 1), 200000)
  T.eq(run(6).target, 300)
end)

T.test("blue_stake_one_less_discard", function()
  local r4, r5 = run(4), run(5)
  T.eq(ns.Run.blindDiscards(r5), ns.Run.blindDiscards(r4) - 1)
end)

local function rollMany(stake, n)
  local r = shopRun(stake)
  local counts = { eternal = 0, perishable = 0, rental = 0, both = 0 }
  for _ = 1, n do
    local offer = ns.Shop.rollTrinket(r, {})
    if offer.eternal then counts.eternal = counts.eternal + 1 end
    if offer.perishable then counts.perishable = counts.perishable + 1 end
    if offer.rental then counts.rental = counts.rental + 1 end
    if offer.eternal and offer.perishable then counts.both = counts.both + 1 end
    T.ok(not (offer.eternal and ns.Stakes.NO_ETERNAL[offer.id]), "Eternal on " .. offer.id)
    T.ok(not (offer.perishable and ns.Stakes.NO_PERISHABLE[offer.id]), "Perishable on " .. offer.id)
  end
  return counts
end

T.test("sticker_odds_by_stake", function()
  local white = rollMany(3, 2000)
  T.eq({ white.eternal, white.perishable, white.rental }, { 0, 0, 0 })
  local black = rollMany(4, 4000)
  T.ok(black.eternal > 900 and black.eternal < 1300, "Black: about 30% Eternal, got " .. black.eternal)
  T.eq({ black.perishable, black.rental }, { 0, 0 })
  local gold = rollMany(8, 4000)
  T.ok(gold.perishable > 900 and gold.perishable < 1300, "Orange: about 30% Perishable, got " .. gold.perishable)
  T.ok(gold.rental > 1000 and gold.rental < 1400, "Gold: about 30% Rental, got " .. gold.rental)
  T.eq(gold.both, 0)
end)

T.test("bought_trinket_keeps_stickers", function()
  local r = shopRun(8)
  r.shop = { cards = { { type = "trinket", id = "ARCANE_INTELLECT", cost = 4, baseCost = 4,
    eternal = true, rental = true } }, packs = {}, rerollCost = 5 }
  ns.Shop.reprice(r)
  T.eq(r.shop.cards[1].cost, 1, "a Rental costs 1g")
  T.ok(ns.Shop.buy(r, 1))
  T.eq(r.gold, 99)
  local t = r.trinkets[1]
  T.ok(t.eternal and t.rental, "stickers carried over")
end)

T.test("eternal_cannot_be_sold_or_destroyed", function()
  local r = shopRun(4)
  r.trinkets = { ns.Stakes.stick(ns.Trinkets.create(r, "ARCANE_INTELLECT"), { eternal = true }),
    ns.Trinkets.create(r, "FORTITUDE") }
  T.eq({ ns.Run.sellTrinket(r, 1) }, { nil, "eternal" })
  -- Relic of Hexes spares it; Soul Harvest won't take it.
  r.consumables = { { kind = "relic", id = "HEXES" } }
  r.trinkets[1].ed = "FOIL" -- so Hexes picks the other one
  T.ok(ns.Consumables.use(r, 1))
  T.eq(#r.trinkets, 2)
  local p = run(4)
  p.trinkets = { ns.Trinkets.create(p, "SOUL_HARVEST"),
    ns.Stakes.stick(ns.Trinkets.create(p, "ARCANE_INTELLECT"), { eternal = true }) }
  T.startBlind(p)
  T.eq(#p.trinkets, 2)
  T.eq(p.trinkets[1].state.mult, 0)
end)

T.test("perishable_debuffed_after_five_rounds", function()
  local r = run(7)
  r.trinkets = { ns.Stakes.stick(ns.Trinkets.create(r, "ARCANE_INTELLECT"), { perishable = true }) }
  for round = 1, 5 do
    T.startBlind(r)
    T.ok(not r.trinkets[1].disabled, "still working in round " .. round)
    ns.Run.winBlind(r)
  end
  T.ok(r.trinkets[1].perished and r.trinkets[1].disabled, "perished")
  T.startBlind(r)
  T.ok(r.trinkets[1].disabled, "a new blind keeps it debuffed")
end)

T.test("rental_charges_before_interest", function()
  local r = run(8)
  r.trinkets = { ns.Stakes.stick(ns.Trinkets.create(r, "ARCANE_INTELLECT"), { rental = true }) }
  T.startBlind(r)
  r.gold = 27 -- 27 - 3 = 24: four interest, not five
  ns.Run.winBlind(r)
  T.eq(r.lastPayout.rental, -3)
  T.eq(r.lastPayout.interest, 4)
  T.eq(r.lastPayout.total, r.lastPayout.reward + r.lastPayout.hands + 4 - 3)
end)

T.test("stake_ladder_unlocks_per_deck", function()
  local db = {}
  T.eq(ns.Profile.stakeUnlocked(db, "ROGUE"), 1)
  local r = run(1)
  r.phase = "won"
  ns.Profile.recordRun(db, r)
  T.eq(ns.Profile.stakeUnlocked(db, "ROGUE"), 2)
  T.eq(ns.Profile.stakeUnlocked(db, "MONK"), 1)
  r.phase = "lost"
  r.stake = 2
  ns.Profile.recordRun(db, r)
  T.eq(ns.Profile.stakeUnlocked(db, "ROGUE"), 2, "a loss unlocks nothing")
  r.phase, r.stake = "won", 8
  ns.Profile.recordRun(db, r)
  T.eq(ns.Profile.stakeUnlocked(db, "ROGUE"), 8)
end)

T.test("stake_and_stickers_survive_save", function()
  local r = run(8)
  r.trinkets = { ns.Stakes.stick(ns.Trinkets.create(r, "ARCANE_INTELLECT"), { perishable = true, rental = true }) }
  local db = {}
  ns.Save.store(db, r)
  local loaded = ns.Save.load(db)
  T.eq(loaded.stake, 8)
  T.eq({ loaded.trinkets[1].perishTally, loaded.trinkets[1].rental }, { 5, true })
end)
