local _, ns = ...

-- Balatro's stakes: each adds its rule to every stake below it. Unlocked per deck (Profile.stakeUnlocked).
local Stakes = {}

Stakes.order = { "WHITE", "RED", "GREEN", "BLACK", "BLUE", "PURPLE", "ORANGE", "GOLD" }
Stakes.def = {
  WHITE = { name = "White Stake", color = { 0.95, 0.95, 0.95 }, desc = "Base difficulty" },
  RED = { name = "Red Stake", color = { 0.9, 0.25, 0.2 }, desc = "Small blind gives no reward money" },
  GREEN = { name = "Green Stake", color = { 0.3, 0.75, 0.35 }, desc = "Required scores scale faster each ante" },
  BLACK = { name = "Black Stake", color = { 0.35, 0.35, 0.4 }, desc = "Shop trinkets can be Eternal (can't be sold or destroyed)" },
  BLUE = { name = "Blue Stake", color = { 0.3, 0.5, 0.95 }, desc = "-1 discard" },
  PURPLE = { name = "Purple Stake", color = { 0.65, 0.35, 0.85 }, desc = "Required scores scale even faster" },
  ORANGE = { name = "Orange Stake", color = { 0.95, 0.55, 0.15 }, desc = "Shop trinkets can be Perishable (debuffed after 5 rounds)" },
  GOLD = { name = "Gold Stake", color = { 1, 0.82, 0 }, desc = "Shop trinkets can be Rental (1g to buy, -3g per round)" },
}
for i, id in ipairs(Stakes.order) do
  Stakes.def[id].id, Stakes.def[id].index = id, i
end

-- Ante base scores by Balatro's scaling: 1 below Green, 2 from Green, 3 from Purple.
Stakes.TARGETS = {
  { 300, 800, 2000, 5000, 11000, 20000, 35000, 50000 },
  { 300, 900, 2600, 8000, 20000, 36000, 60000, 100000 },
  { 300, 1000, 3200, 9000, 25000, 60000, 110000, 200000 },
}

Stakes.PERISH_ROUNDS = 5
Stakes.RENTAL_COST = 1
Stakes.RENTAL_RATE = 3

-- Balatro jokers with eternal_compat = false (they sell or destroy themselves) and
-- perishable_compat = false (they grow over the run).
Stakes.NO_ETERNAL = {
  RIPE_BANANA = true, TIGULES = true, GOLDEN_BANANA = true, FERTILE_SEED = true, POPCORN = true,
  NOODLES = true, MORNING_DEW = true, SOULSTONE = true, GLAD_MEDALLION = true, INVIS_POTION = true,
  DARKMOON_FIZZ = true,
}
Stakes.NO_PERISHABLE = {
  SOUL_HARVEST = true, FLIGHT_PATH = true, SPRINT = true, STARLIGHT_CODEX = true, FEL_INFUSION = true,
  PACK_RAT = true, OLD_GODS = true, FOUR_WINDS = true, VAMPIRIC = true, PHANTASM = true,
  GOBLIN_ROCKET = true, OBELISK = true, FORTUNE_CAT = true, FLASH_HEAL = true, SPARE_TABARD = true,
  STORMWIND_KEEP = true, TINY_GNOME = true, COOKING_FIRE = true, GLASS_CANNON = true, MOUNT_UP = true,
  TIMEWALKING_BADGE = true, FROSTMOURNE = true, SHADOWMOURNE = true,
}

-- The run's stake number (saves from before stakes are White).
function Stakes.of(run) return run.stake or 1 end

-- Whether the run's stake includes the rule of stake `id`.
function Stakes.has(run, id) return Stakes.of(run) >= Stakes.def[id].index end

-- The ante's base score: the stake's scaling, times the deck's targetMult (Balance Druid x2).
function Stakes.baseTarget(run, stage)
  local scaling = Stakes.has(run, "PURPLE") and 3 or (Stakes.has(run, "GREEN") and 2 or 1)
  -- Scaling 1 reads Run.BASE_TARGETS so the simulator's override still applies.
  local list = scaling == 1 and ns.Run.BASE_TARGETS or Stakes.TARGETS[scaling]
  local deck = run.deckId and ns.Decks.def[run.deckId]
  return list[stage] * (deck and deck.targetMult or 1)
end

-- Rolls the stake's stickers onto a trinket offer (shop or Trinket Lockbox), as Balatro's create_card.
function Stakes.rollStickers(run, offer)
  if not Stakes.has(run, "BLACK") then return end
  local r = ns.RNG.next(run.rng)
  if r > 0.7 then
    if not Stakes.NO_ETERNAL[offer.id] then offer.eternal = true end
  elseif r > 0.4 and Stakes.has(run, "ORANGE") and not Stakes.NO_PERISHABLE[offer.id] then
    offer.perishable = true
  end
  if Stakes.has(run, "GOLD") and ns.RNG.next(run.rng) > 0.7 then offer.rental = true end
end

-- Copies an offer's stickers onto the trinket made from it.
function Stakes.stick(instance, offer)
  instance.eternal = offer.eternal or nil
  instance.perishTally = offer.perishable and Stakes.PERISH_ROUNDS or nil
  instance.rental = offer.rental or nil
  return instance
end

-- End of round: Perishable trinkets count down and perish (debuffed for good); Rental ones cost
-- 3g each. Returns the gold the rentals took.
function Stakes.endRound(run)
  local rent = 0
  for _, t in ipairs(run.trinkets) do
    if t.perishTally and not t.perished then
      t.perishTally = t.perishTally - 1
      if t.perishTally <= 0 then t.perished, t.disabled = true, true end
    end
    if t.rental then rent = rent + Stakes.RENTAL_RATE end
  end
  return rent
end

-- Tooltip lines for a trinket's or an offer's stickers.
function Stakes.lines(t)
  local lines = {}
  if t.eternal then lines[#lines + 1] = "Eternal: can't be sold or destroyed" end
  if t.perished then
    lines[#lines + 1] = "Perished: debuffed"
  elseif t.perishTally or t.perishable then
    lines[#lines + 1] = "Perishable: debuffed after " .. (t.perishTally or Stakes.PERISH_ROUNDS) .. " rounds"
  end
  if t.rental then lines[#lines + 1] = "Rental: -" .. Stakes.RENTAL_RATE .. "g each round" end
  return lines
end

ns.Stakes = Stakes
