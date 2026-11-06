local _, ns = ...

local Save = {}

Save.VERSION = 3

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[deepCopy(k)] = deepCopy(v) end
  return out
end

function Save.store(db, run)
  db.run = deepCopy(run)
  db.version = Save.VERSION
end

function Save.load(db)
  if not db or (db.version ~= 2 and db.version ~= Save.VERSION) then return nil end
  local run = db.run
  if type(run) ~= "table" or type(run.phase) ~= "string" then return nil end
  if type(run.deck) ~= "table" or type(run.hand) ~= "table"
    or type(run.pile) ~= "table" then return nil end
  run = deepCopy(run)
  if db.version == 2 then
    run.vouchers = run.vouchers or {}
    run.handPlays = run.handPlays or {}
    run.bossRerollsUsed = run.bossRerollsUsed or 0
    run.bossesFought = run.bossesFought or {}
    run.streak = run.streak or { maxInterest = 0 }
    if run.phase == "shop" and run.shopVoucher == nil then run.shopVoucher = ns.Shop.rollVoucher(run) end
  end
  ns.Deck.relink(run)
  return run
end

function Save.clear(db)
  db.run = nil
  db.version = nil
end

ns.Save = Save
