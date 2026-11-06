local _, ns = ...

local Profile = {}

function Profile.get(db)
  if type(db.profile) ~= "table" then db.profile = {} end
  local profile = db.profile
  profile.version = 1
  for _, key in ipairs({ "discovered", "stats", "seenUnlocks" }) do
    if type(profile[key]) ~= "table" then profile[key] = {} end
  end
  for _, stats in pairs(profile.stats) do
    stats.wins = stats.wins or 0
    stats.bestStage = stats.bestStage or 0
    stats.runs = stats.runs or 0
  end
  return profile
end

function Profile.discover(db, kind, id)
  local data = ({ trinket = ns.Trinkets, tome = ns.Tomes, scroll = ns.Scrolls, relic = ns.Relics })[kind]
  if not data or not data.def[id] then return false end
  local discovered = Profile.get(db).discovered
  local key = kind .. ":" .. id
  if discovered[key] then return false end
  discovered[key] = true
  return true
end

function Profile.discoveredCount(db)
  local count = 0
  for _, discovered in pairs(Profile.get(db).discovered) do
    if discovered == true then count = count + 1 end
  end
  return count
end

function Profile.totalDiscoverable()
  return #ns.Trinkets.order + #ns.Tomes.order + #ns.Scrolls.order + #ns.Relics.order
end

function Profile.isUnlocked(db, deckId)
  local deck = ns.Decks.def[deckId]
  local have = Profile.discoveredCount(db)
  if not deck then return false, have, 0 end
  local need = deck.unlock and deck.unlock.discovered or 0
  return have >= need, have, need
end

function Profile.newlyUnlocked(db)
  local profile, unlocked = Profile.get(db), {}
  for _, id in ipairs(ns.Decks.order) do
    if Profile.isUnlocked(db, id) and not profile.seenUnlocks[id] then
      unlocked[#unlocked + 1] = id
    end
  end
  return unlocked
end

function Profile.markSeen(db, deckId)
  Profile.get(db).seenUnlocks[deckId] = true
end

-- The caller records each finished run once; no profile state lives in a run.
function Profile.recordRun(db, run)
  if run.phase ~= "won" and run.phase ~= "lost" then return end
  local stats = Profile.get(db).stats
  if not stats[run.deckId] then stats[run.deckId] = { wins = 0, bestStage = 0, runs = 0 } end
  local deck = stats[run.deckId]
  deck.runs = deck.runs + 1
  if run.phase == "won" then deck.wins = deck.wins + 1 end
  deck.bestStage = math.max(deck.bestStage, run.stage)
end

ns.Profile = Profile
