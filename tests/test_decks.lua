local ns, T = ...
local H = loadfile("tests/trinket_helper.lua")(ns, T)

local function count(deck, fn)
  local n = 0
  for _, card in ipairs(deck) do if fn(card) then n = n + 1 end end
  return n
end

T.test("decks_all_fifteen_defined", function()
  T.eq(#ns.Decks.order, 15)
  for i, id in ipairs(ns.Decks.order) do
    local def = ns.Decks.def[id]
    T.ok(def and def.name and def.desc and def.flavour, id)
    if i > 1 then
      local prev = ns.Decks.def[ns.Decks.order[i - 1]].unlock
      T.ok(def.unlock.fraction > (prev and prev.fraction or 0), id .. " unlocks after the deck before it")
    end
  end
end)

T.test("mage_deck_starts_with_crystal_ball_and_echoes", function()
  local run = ns.Run.new(1, "MAGE")
  T.ok(ns.Vouchers.owns(run, "CRYSTAL_BALL"), "Crystal Ball owned")
  T.eq(ns.Consumables.slots(run), 3)
  T.eq(run.consumables, { { kind = "scroll", id = "ECHOES" }, { kind = "scroll", id = "ECHOES" } })
  for _ = 1, 50 do
    local offer = ns.Shop.rollVoucher(run)
    T.ok(not offer or offer.id ~= "CRYSTAL_BALL", "an owned starting voucher is never offered")
  end
end)

T.test("draenei_deck_orrery_and_one_slot", function()
  local run = ns.Run.new(1, "DRAENEI")
  T.ok(ns.Vouchers.telescope(run), "Titan Orrery owned")
  T.eq(ns.Consumables.slots(run), 1)
end)

T.test("death_knight_deck_relics_in_shop", function()
  local run = ns.Run.new(1, "DEATHKNIGHT")
  T.eq(run.consumables, { { kind = "relic", id = "HEXES" } })
  run.phase, run.gold = "shop", 100
  local relics, plain = 0, ns.Run.new(1, "ROGUE")
  for _ = 1, 300 do
    ns.Shop.open(run)
    for _, item in ipairs(run.shop.cards) do
      if item.type == "relic" then
        relics = relics + 1
        T.eq(item.baseCost, 4)
        T.ok(not ns.Relics.HIDDEN[item.id], "hidden relic in the shop: " .. item.id)
      end
    end
  end
  T.ok(relics > 15, "Relics in the Death Knight shop: " .. relics)
  plain.phase, plain.gold = "shop", 100
  for _ = 1, 300 do
    ns.Shop.open(plain)
    for _, item in ipairs(plain.shop.cards) do T.ok(item.type ~= "relic", "no Relics in a plain shop") end
  end
end)

T.test("forsaken_deck_has_no_face_cards", function()
  local run = ns.Run.new(1, "FORSAKEN")
  T.eq(#run.deck, 40)
  T.eq(count(run.deck, function(c) return c.rank >= 11 and c.rank <= 13 end), 0)
  T.eq(run.startDeckSize, 40)
end)

T.test("alliance_deck_spades_and_hearts", function()
  local run = ns.Run.new(1, "ALLIANCE")
  T.eq(#run.deck, 52)
  T.eq(count(run.deck, function(c) return c.suit == "S" end), 26)
  T.eq(count(run.deck, function(c) return c.suit == "H" end), 26)
  T.eq(count(run.deck, function(c) return c.rank == 14 end), 4)
end)

T.test("trade_prince_deck_three_vouchers", function()
  local run = ns.Run.new(1, "TRADEPRINCE")
  for _, id in ipairs({ "TAROT_MERCHANT", "PLANET_MERCHANT", "OVERSTOCK" }) do
    T.ok(ns.Vouchers.owns(run, id), id)
  end
  T.eq(ns.Vouchers.shopCardSlots(run), 3)
end)

T.test("hunter_deck_hand_size_and_slots", function()
  local run = ns.Run.new(1, "HUNTER")
  T.eq(ns.Deck.handSize(run), 10)
  T.eq(ns.Run.trinketSlots(run), 4)
  T.startBlind(run)
  T.eq(#run.hand, 10)
end)

T.test("evoker_deck_bonus_roll_after_boss", function()
  local run = ns.Run.new(1, "EVOKER")
  T.startBlind(run)
  ns.Run.winBlind(run)
  T.eq(run.tags, {})
  run.phase, run.blind = "blind", 3
  T.startBlind(run)
  ns.Run.winBlind(run)
  T.eq(run.tags, { "DOUBLE" })
end)

T.test("druid_deck_balances_and_doubles_targets", function()
  local run = ns.Run.new(1, "DRUID")
  T.eq(run.target, 600)
  T.eq(ns.Run.target(run, 2, 3, "HOGGER"), 3200)
  run.phase = "play"
  -- A pair of 10s: 30 chips (10 base + 10 + 10) and 2 mult become 16 and 16.
  local result = H.score(run, { H.card(10, "S"), H.card(10, "H") })
  T.eq({ result.chips, result.mult, result.total }, { 16, 16, 256 })
  local kinds = {}
  for _, e in ipairs(result.events) do kinds[e.kind] = true end
  T.ok(kinds.balance, "a balance event for the tally")
end)

T.test("gnome_deck_is_random_and_seeded", function()
  local a, b = ns.Run.new(3, "GNOME"), ns.Run.new(3, "GNOME")
  T.eq(#a.deck, 52)
  local plain = 0
  for i, card in ipairs(a.deck) do
    T.eq({ card.rank, card.suit }, { b.deck[i].rank, b.deck[i].suit }, "same seed, same deck")
    if card.rank == (i - 1) % 13 + 2 then plain = plain + 1 end
  end
  T.ok(plain < 20, "ranks are shuffled, " .. plain .. " still in order")
  local ids = {}
  for _, card in ipairs(a.deck) do
    T.ok(not ids[card.id], "unique card ids")
    ids[card.id] = true
  end
end)
