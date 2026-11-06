local _, ns = ...

local Profile = {}

local oldThresholds = { WARRIOR = 5, GOBLIN = 12, MONK = 18, WARLOCK = 24 }
-- The fixed thresholds of 0.3.0; decks reached under them stay unlocked when thresholds scale.
local v3Thresholds = { WARRIOR = 7, GOBLIN = 17, MONK = 26, WARLOCK = 35 }
local UNLOCK_MIGRATION = 2

local function discoveredCount(profile)
  local count = 0
  for _, discovered in pairs(profile.discovered) do
    if discovered == true then count = count + 1 end
  end
  return count
end

function Profile.get(db)
  local existing = type(db.profile) == "table"
  if not existing then db.profile = {} end
  local profile = db.profile
  local migrateUnlocks = existing and type(profile.unlockedDecks) ~= "table"
  profile.version = 1
  for _, key in ipairs({ "discovered", "stats", "seenUnlocks", "counters", "achievements",
    "bossesSeen", "unlockedDecks", "seenAchievements" }) do
    if type(profile[key]) ~= "table" then profile[key] = {} end
  end
  if migrateUnlocks then
    local have = discoveredCount(profile)
    for id, need in pairs(oldThresholds) do
      if have >= need then profile.unlockedDecks[id] = true end
    end
  end
  if profile.unlockMigration ~= UNLOCK_MIGRATION then
    if existing then
      local have = discoveredCount(profile)
      for id, need in pairs(v3Thresholds) do
        if have >= need then profile.unlockedDecks[id] = true end
      end
    end
    profile.unlockMigration = UNLOCK_MIGRATION
  end
  for _, stats in pairs(profile.stats) do
    stats.wins = stats.wins or 0
    stats.bestStage = stats.bestStage or 0
    stats.runs = stats.runs or 0
  end
  return profile
end

function Profile.discover(db, kind, id)
  local data = ({ trinket = ns.Trinkets, tome = ns.Tomes, scroll = ns.Scrolls, relic = ns.Relics, voucher = ns.Vouchers })[kind]
  if not data or not data.def[id] then return false end
  local discovered = Profile.get(db).discovered
  local key = kind .. ":" .. id
  if discovered[key] then return false end
  discovered[key] = true
  return true
end

function Profile.discoveredCount(db)
  return discoveredCount(Profile.get(db))
end

function Profile.totalDiscoverable()
  return #ns.Trinkets.order + #ns.Tomes.order + #ns.Scrolls.order + #ns.Relics.order + #ns.Vouchers.order
end

-- Items to discover before a deck unlocks: a fraction of the whole collection, so it scales as content grows.
function Profile.unlockThreshold(deckId)
  local deck = ns.Decks.def[deckId]
  local fraction = deck and deck.unlock and deck.unlock.fraction
  return fraction and math.floor(fraction * Profile.totalDiscoverable()) or 0
end

function Profile.isUnlocked(db, deckId)
  local deck = ns.Decks.def[deckId]
  local have = Profile.discoveredCount(db)
  if not deck then return false, have, 0 end
  local need = Profile.unlockThreshold(deckId)
  local profile = Profile.get(db)
  if have >= need then profile.unlockedDecks[deckId] = true end
  return profile.unlockedDecks[deckId] == true, have, need
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

function Profile.event(db, name, amount, run)
  local profile, unlocked = Profile.get(db), {}
  if name == "bossFought" and ns.Bosses.def[amount] then
    profile.bossesSeen[amount] = true
  end
  for _, id in ipairs(ns.Achievements.order) do
    local def = ns.Achievements.def[id]
    if def.counter == name then
      local have = profile.counters[name] or 0
      -- Core emits current streak/held counts, not increments.
      if name == "maxInterestStreak" or name == "editionTrinkets" then
        profile.counters[name] = math.max(have, amount)
      else
        profile.counters[name] = have + amount
      end
    end
    if not profile.achievements[id] then
      local reached = def.counter and (profile.counters[def.counter] or 0) >= def.target
      if reached or (def.check and def.check(profile, name, amount, run)) then
        profile.achievements[id] = true
        unlocked[#unlocked + 1] = id
      end
    end
  end
  return unlocked
end

function Profile.hasAchievement(a, b)
  -- Shop passes only the id; the bootstrap sets Profile.db to the saved database.
  local db, id = a, b
  if type(a) ~= "table" then db, id = Profile.db, a end
  if type(db) ~= "table" then return false end
  return Profile.get(db).achievements[id] == true
end

function Profile.achievementProgress(db, id)
  local profile = Profile.get(db)
  local def = ns.Achievements.def[id]
  if not def then return 0, 0 end
  if def.counter then return profile.counters[def.counter] or 0, def.target end
  if id == "RETCON" then return ns.Achievements.bossCount(profile), #ns.Bosses.pool + 1 end
  return profile.achievements[id] and 1 or 0, 1
end

function Profile.newAchievements(db)
  local profile, unlocked = Profile.get(db), {}
  for _, id in ipairs(ns.Achievements.order) do
    if profile.achievements[id] and not profile.seenAchievements[id] then
      unlocked[#unlocked + 1] = id
    end
  end
  return unlocked
end

function Profile.markAchievementSeen(db, id)
  Profile.get(db).seenAchievements[id] = true
end

ns.Profile = Profile
