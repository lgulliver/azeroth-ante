local ns, T = ...

local function playing()
  local run = ns.Run.new(7, "ADVENTURER")
  ns.Run.startBlind(run)
  return run
end

T.test("save_roundtrip_mid_round", function()
  local run = playing()
  ns.Run.play(run, { 1 })
  local db = {}
  ns.Save.store(db, run)
  local loaded = ns.Save.load(db)
  T.ok(loaded ~= nil, "load returned nil")
  T.eq(loaded, run)
  local r1 = ns.Run.play(run, { 1 })
  local r2 = ns.Run.play(loaded, { 1 })
  T.eq(r2, r1)
  T.eq(loaded, run)
  loaded.score = 999999
  loaded.hand[1] = nil
  T.ok(db.run.score ~= 999999, "mutating loaded run touched db.run")
  T.ok(db.run.hand[1] ~= nil, "mutating loaded hand touched db.run")
end)

T.test("load_rejects_bad_version", function()
  local run = playing()
  local db = {}
  ns.Save.store(db, run)
  db.version = 0
  T.eq(ns.Save.load(db), nil)
  T.eq(ns.Save.load(nil), nil)
  T.eq(ns.Save.load({ version = ns.Save.VERSION, run = "x" }), nil)
  T.eq(ns.Save.load({ version = ns.Save.VERSION, run = { seed = 1 } }), nil)
end)

T.test("clear_removes_run", function()
  local db = {}
  ns.Save.store(db, playing())
  ns.Save.clear(db)
  T.eq(ns.Save.load(db), nil)
end)

T.test("relink_after_load_shares_tables", function()
  local run = playing()
  local db = {}
  ns.Save.store(db, run)
  local loaded = ns.Save.load(db)
  loaded.hand[1].enh = "MULT"
  T.eq(ns.Deck.find(loaded, loaded.hand[1].id).enh, "MULT")
  for _, card in ipairs(loaded.pile) do
    T.ok(rawequal(card, ns.Deck.find(loaded, card.id)))
  end
  T.eq(db.run.hand[1].enh, nil)
end)

T.test("load_rejects_v1", function()
  T.eq(ns.Save.load({ version = 1, run = playing() }), nil)
end)

T.test("v3_save_migrates_trinkets", function()
  local run = playing()
  run.nextTrinketUid, run.roundHandPlays = nil, nil
  run.trinkets = { { id = "BLOODLUST", ed = nil, paid = 8 } }
  local db = { version = 3, run = run }
  local loaded = ns.Save.load(db)
  T.ok(loaded ~= nil, "v3 load returned nil")
  local t = loaded.trinkets[1]
  T.eq({ t.uid, t.sellBonus, t.state, t.paid }, { 1, 0, { hands = 0 }, 8 }) -- Spec row 25: fresh purchase counter.
  T.eq(loaded.nextTrinketUid, 2)
  T.eq(loaded.roundHandPlays, {})
  T.eq(ns.Save.VERSION, 7)
end)

T.test("v4_save_migrates_lifecycle_fields", function()
  local run = playing()
  run.discardsUsedRound, run.flags, run.lifecycleEvents = nil, nil, nil
  run.shop = { cards = {}, packs = {} }
  local loaded = ns.Save.load({ version = 4, run = run })
  T.ok(loaded ~= nil, "v4 load returned nil")
  T.eq({ loaded.discardsUsedRound, loaded.flags, loaded.lifecycleEvents, loaded.shop.freeRerolls }, { 0, {}, {}, 0 })
  run.shop = nil
  T.eq(ns.Save.load({ version = 4, run = run }).shop, nil)
end)

T.test("load_does_not_replay_lifecycle_events", function()
  local run = playing()
  run.lifecycleEvents = { { kind = "money", amount = 3 } }
  local db = {}
  ns.Save.store(db, run)
  T.eq(ns.Save.load(db).lifecycleEvents, {})
end)

T.test("save_v6_loads_with_empty_tag_state", function()
  local run = playing()
  ns.Run.play(run, { 1 })
  run.tags, run.blindTags, run.skips, run.playedThisAnte, run.roundFirstHand = nil, nil, nil, nil, nil
  run.skippedBlinds = nil
  local loaded = ns.Save.load({ version = 6, run = run })
  T.ok(loaded ~= nil, "v6 load returned nil")
  T.eq({ loaded.tags, loaded.blindTags, loaded.skips, loaded.playedThisAnte, loaded.skippedBlinds }, { {}, {}, 0, {}, {} })
  T.eq(loaded.roundFirstHand, next(run.roundHandPlays))
  T.eq(ns.Save.VERSION, 7)
end)

T.test("save_v6_relinks_old_forced_card", function()
  local run = playing()
  run.forcedCard = { id = run.hand[3].id, rank = run.hand[3].rank, suit = run.hand[3].suit }
  local loaded = ns.Save.load({ version = 6, run = run })
  T.ok(rawequal(loaded.forcedCard, loaded.hand[3]), "old forcedCard copy relinked to the hand card")
end)

T.test("save_roundtrip_keeps_boss_state", function()
  local run = playing()
  run.hand[1].faceDown = true
  run.forcedCard = run.hand[2]
  local trinket = ns.Trinkets.create(run, "BLOODLUST")
  trinket.disabled, trinket.faceDown = true, true
  run.trinkets = { trinket }
  run.playedThisAnte = { [5] = true }
  run.tags, run.blindTags, run.skips, run.skippedBlinds = { "RARE" }, { "FOIL", "UNCOMMON" }, 1, { [1] = true }
  local db = {}
  ns.Save.store(db, run)
  T.eq(db.run.forcedCard, nil)
  T.eq(db.run.forcedCardId, run.hand[2].id)
  T.ok(rawequal(run.forcedCard, run.hand[2]), "store leaves the live run alone")
  local loaded = ns.Save.load(db)
  T.ok(loaded.hand[1].faceDown, "face-down card")
  T.ok(rawequal(loaded.forcedCard, loaded.hand[2]), "forcedCard relinked")
  T.eq(loaded.forcedCardId, nil)
  T.eq({ loaded.trinkets[1].disabled, loaded.trinkets[1].faceDown }, { true, true })
  T.eq(loaded.playedThisAnte, { [5] = true })
  T.eq({ loaded.tags, loaded.blindTags, loaded.skips, loaded.skippedBlinds },
    { { "RARE" }, { "FOIL", "UNCOMMON" }, 1, { [1] = true } })
  T.eq(loaded, run)
end)

T.test("save_roundtrip_keeps_gift_pack", function()
  local run = ns.Run.new(9, "ADVENTURER")
  run.blindTags[1] = "CHARM"
  ns.Run.skipBlind(run)
  local db = {}
  ns.Save.store(db, run)
  local loaded = ns.Save.load(db)
  T.eq(loaded.giftPack, run.giftPack)
  T.ok(#loaded.giftPack.hand > 0, "pack hand saved")
  for _, card in ipairs(loaded.giftPack.hand) do
    local inDeck = false
    for _, d in ipairs(loaded.deck) do if rawequal(d, card) then inDeck = true end end
    T.ok(inDeck, "pack hand card relinked to the deck")
  end
  T.eq(loaded, run)
end)

T.test("save_v6_defaults_unused_discards", function()
  local run = playing()
  run.discardsUnusedTotal = nil
  T.eq(ns.Save.load({ version = 6, run = run }).discardsUnusedTotal, 0)
end)
