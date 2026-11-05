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
