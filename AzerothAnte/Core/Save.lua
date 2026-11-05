local _, ns = ...

local Save = {}

Save.VERSION = 1

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
  if not db or db.version ~= Save.VERSION then return nil end
  local run = db.run
  if type(run) ~= "table" or type(run.phase) ~= "string" then return nil end
  return deepCopy(run)
end

function Save.clear(db)
  db.run = nil
  db.version = nil
end

ns.Save = Save
