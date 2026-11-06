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
  T.eq({ t.uid, t.sellBonus, t.state, t.paid }, { 1, 0, {}, 8 })
  T.eq(loaded.nextTrinketUid, 2)
  T.eq(loaded.roundHandPlays, {})
  T.eq(ns.Save.VERSION, 4)
end)
