local _, ns = ...

local Achievements = { order = {}, def = {} }

local function add(id, desc, counter, target, check)
  Achievements.order[#Achievements.order + 1] = id
  Achievements.def[id] = {
    id = id, name = ns.Vouchers.def[id].name, desc = desc, unlocks = id,
    counter = counter, target = target, check = check,
  }
end

function Achievements.bossCount(profile)
  local count = 0
  for _, id in ipairs(ns.Bosses.pool) do
    if profile.bossesSeen[id] then count = count + 1 end
  end
  if profile.bossesSeen[ns.Bosses.FINAL] then count = count + 1 end
  return count
end

add("OVERSTOCK_PLUS", "Spend 2500g in shops across all runs.", "spend", 2500)
add("LIQUIDATION", "Buy 10 vouchers across all runs.", "voucherBought", 10)
add("GLOW_UP", "Have 5 trinkets with an edition at once at blind start.", "editionTrinkets", 5)
add("REROLL_GLUT", "Reroll the shop 100 times across all runs.", "reroll", 100)
add("OMEN_GLOBE", "Use 25 Scrolls from Arcana packs across all runs.", "scrollFromPackUsed", 25)
add("OBSERVATORY", "Use 25 Tomes from Celestial packs across all runs.", "tomeFromPackUsed", 25)
add("NACHO_TONG", "Play 2500 cards across all runs.", "cardsPlayed", 2500)
add("RECYCLOMANCY", "Discard 2500 cards across all runs.", "cardsDiscarded", 2500)
add("TAROT_TYCOON", "Buy 50 Scrolls from the shop across all runs.", "scrollBought", 50)
add("PLANET_TYCOON", "Buy 50 Tomes from the shop across all runs.", "tomeBought", 50)
add("MONEY_TREE", "Earn maximum interest 10 rounds in a row.", "maxInterestStreak", 10)
add("ANTIMATTER", "Buy Empty Gem Socket 10 times across all runs.", "blankBought", 10)
add("ILLUSION", "Buy 20 playing cards from the shop across all runs.", "cardBought", 20)
add("PETROGLYPH", "Win a run with Chronomancer's Hourglass owned.", nil, nil,
  function(profile, event, amount, run)
    return event == "runEnded" and amount == 1 and run and run.vouchers and run.vouchers.HIEROGLYPH
  end)
add("RETCON", "Fight all 9 bosses across all runs, including Ragnaros.", nil, nil,
  function(profile, event)
    return event == "bossFought" and Achievements.bossCount(profile) == #ns.Bosses.pool + 1
  end)
add("PALETTE", "Start a blind with a hand size of 5 or less.", nil, nil,
  function(profile, event, amount)
    return event == "handSize" and amount <= 5
  end)

ns.Achievements = Achievements
