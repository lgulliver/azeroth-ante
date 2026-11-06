local _, ns = ...

local Scoring = {}

local function lookup(registry, id)
  if not id or not registry then return nil end
  return registry.def[id]
end

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[deepCopy(k)] = deepCopy(v) end
  return out
end

local CARD_FIELDS = { "enh", "bonusChips", "seal", "ed" }

-- Pure: works on scratch copies of ctx.trinkets, ctx.cards and ctx.held (set back on ctx for the
-- hooks) and returns the trinkets as trinketsAfter plus the card changes as cardsAfter, and any
-- created or destroyed cards and consumables as sideEffects. The caller commits them; nothing it
-- was given is mutated.
function Scoring.score(ctx)
  local origCards, origHeld = ctx.cards, ctx.held or {}
  local cards, held = deepCopy(origCards), deepCopy(origHeld)
  ctx.cards, ctx.held = cards, held
  local trinkets = deepCopy(ctx.trinkets or {})
  ctx.trinkets = trinkets
  local rules = ns.TrinketRules.set(trinkets)
  ctx.rules = rules
  local handId, scoringIdx = ns.HandEval.evaluate(cards, rules)
  ctx.handId, ctx.scoringIdx = handId, scoringIdx
  ctx.contains = ns.HandEval.contains(cards, rules)

  local boss = lookup(ns.Bosses, ctx.bossId)
  local goldRef = ctx.goldRef or { gold = ctx.gold or 0 }
  ctx.goldRef = goldRef
  local goldStart = goldRef.gold
  local engine = ns.TrinketEngine

  local events, levelUps, destroyedUids = {}, {}, {}
  local sideEffects, luckyTriggers, bossTriggered = {}, 0, false
  local chips, mult = 0, 0
  local function emit(event)
    event.runChips, event.runMult = chips, mult
    events[#events + 1] = event
  end

  -- where: { index = } for a scoring card, { heldIndex = } for a held one, nil otherwise.
  -- counted: levelHand was already tallied (the before phase needs it ahead of the base).
  local function apply(effect, slot, where, counted)
    where = where or {}
    local uid = trinkets[slot].uid
    if effect.chips then chips = chips + effect.chips end
    if effect.mult then mult = mult + effect.mult end
    if effect.xmult then mult = mult * effect.xmult end
    if effect.gold then goldRef.gold = goldRef.gold + effect.gold end
    if effect.chips or effect.mult or effect.xmult or effect.gold then
      emit({ kind = "trinket", slot = slot, uid = uid, chips = effect.chips, mult = effect.mult,
        xmult = effect.xmult, gold = effect.gold, index = where.index, heldIndex = where.heldIndex })
    end
    if effect.msg then emit({ kind = "trinketMsg", slot = slot, uid = uid, msg = effect.msg }) end
    if effect.levelHand then
      if not counted then levelUps[handId] = (levelUps[handId] or 0) + 1 end
      emit({ kind = "levelUp", handId = handId, slot = slot, uid = uid })
    end
    if effect.changeCard then
      -- { id, enh?, bonusChips?, seal?, ed? }; false clears enh, seal or ed. Hits the scratch card.
      local change = effect.changeCard
      for _, list in ipairs({ cards, held }) do
        for _, card in ipairs(list) do
          if card.id == change.id then
            for _, field in ipairs(CARD_FIELDS) do
              local v = change[field]
              if v == false then card[field] = nil elseif v ~= nil then card[field] = v end
            end
          end
        end
      end
    end
    if effect.createCard then
      local c = effect.createCard.card
      sideEffects[#sideEffects + 1] = { kind = "createCard", toHand = effect.createCard.toHand and true or false,
        card = { rank = c.rank, suit = c.suit, enh = c.enh, ed = c.ed, seal = c.seal, bonusChips = c.bonusChips } }
    end
    if effect.createConsumable then
      sideEffects[#sideEffects + 1] = { kind = "createConsumable",
        consumableKind = effect.createConsumable.kind, id = effect.createConsumable.id }
    end
    if effect.destroyCard then sideEffects[#sideEffects + 1] = { kind = "destroyCard", id = effect.destroyCard } end
  end

  -- Called at most once per Lucky card trigger, whichever of the mult and money rolls hit.
  local function lucky(card)
    luckyTriggers = luckyTriggers + 1
    engine.each(trinkets, function(slot, inst, def, isCopy)
      local effect = def.onLucky and def.onLucky(ctx, inst, card, isCopy)
      if effect then apply(effect, slot) end
    end)
  end

  -- Foil and Holo before, Poly after. A kind of "edition" event for a card or a trinket slot.
  local function applyEdition(ed, where, phase)
    local e = { kind = "edition", ed = ed, index = where.index, slot = where.slot }
    if where.slot then e.uid = trinkets[where.slot].uid end
    if ed == "FOIL" and phase == "pre" then
      chips = chips + 50
      e.chips = 50
    elseif ed == "HOLO" and phase == "pre" then
      mult = mult + 10
      e.mult = 10
    elseif ed == "POLY" and phase == "post" then
      mult = mult * 1.5
      e.xmult = 1.5
    else
      return
    end
    emit(e)
  end

  local function enhEvent(i, card, fields)
    if fields.chips then chips = chips + fields.chips end
    if fields.mult then mult = mult + fields.mult end
    if fields.xmult then mult = mult * fields.xmult end
    fields.kind, fields.index, fields.enh = "enh", i, card.enh
    emit(fields)
  end

  local function cardStep(i, card)
    local value = ns.Cards.chipValue(card)
    chips = chips + value
    emit({ kind = "card", index = i, chips = value })
    local enh = card.enh
    if enh == "BONUS" then
      enhEvent(i, card, { chips = 30 })
    elseif enh == "MULT" then
      enhEvent(i, card, { mult = 4 })
    elseif enh == "STONE" then
      enhEvent(i, card, { chips = 50 })
    elseif enh == "GLASS" then
      enhEvent(i, card, { xmult = 2 })
    elseif enh == "LUCKY" then
      local hit = false
      if ns.Prob.roll(ctx.rng, trinkets, 1, 5) then
        enhEvent(i, card, { mult = 20 })
        hit = true
      end
      if ns.Prob.roll(ctx.rng, trinkets, 1, 15) then
        goldRef.gold = goldRef.gold + 20
        emit({ kind = "money", index = i, gold = 20 })
        hit = true
      end
      if hit then lucky(card) end
    end
    if card.ed then
      applyEdition(card.ed, { index = i }, "pre")
      applyEdition(card.ed, { index = i }, "post")
    end
    if card.seal == "GOLD" then
      goldRef.gold = goldRef.gold + 3
      emit({ kind = "seal", index = i, seal = "GOLD", gold = 3 })
    end
    engine.each(trinkets, function(slot, inst, def, isCopy)
      local effect = def.onCard and def.onCard(ctx, inst, card, i, isCopy)
      if effect then apply(effect, slot, { index = i }) end
    end)
  end

  -- One entry per extra trigger, in firing order: a Red seal first, then each trinket's.
  local function retriggers(card, hook, index)
    local list = {}
    if card.seal == "RED" then list[1] = {} end
    engine.each(trinkets, function(slot, inst, def, isCopy)
      local n = def[hook] and def[hook](ctx, inst, card, index, isCopy)
      for _ = 1, n or 0 do list[#list + 1] = { slot = slot, uid = trinkets[slot].uid } end
    end)
    return list
  end

  local function sourceFields(extra, entry)
    extra.slot, extra.uid = entry.slot, entry.uid
    return extra
  end

  -- Before hooks run left to right once the hand is known; levelHand counts toward this base.
  local pending = {}
  engine.each(trinkets, function(slot, inst, def, isCopy)
    local effect = def.before and def.before(ctx, inst, isCopy)
    if not effect then return end
    if effect.levelHand then levelUps[handId] = (levelUps[handId] or 0) + 1 end
    pending[#pending + 1] = { effect = effect, slot = slot }
  end)

  chips, mult = ns.Hands.base(handId, ((ctx.handLevels and ctx.handLevels[handId]) or 1)
    + (levelUps[handId] or 0))
  if boss and boss.halveBase then
    bossTriggered = true
    chips = math.floor(chips / 2)
    mult = math.max(1, math.floor(mult / 2))
  end
  emit({ kind = "base", handId = handId, chips = chips, mult = mult })
  for _, p in ipairs(pending) do apply(p.effect, p.slot, nil, true) end

  local destroyCandidates = {}
  for _, i in ipairs(scoringIdx) do
    local card = cards[i]
    if boss and boss.debuff and boss.debuff(card, ctx.rules) then
      emit({ kind = "debuff", index = i })
      bossTriggered = true
    else
      local extra = retriggers(card, "retrigger", i)
      cardStep(i, card)
      for _, entry in ipairs(extra) do
        emit(sourceFields({ kind = "retrigger", index = i }, entry))
        cardStep(i, card)
      end
      if card.enh == "GLASS" then destroyCandidates[#destroyCandidates + 1] = i end
    end
  end

  for h, card in ipairs(held) do
    if boss and boss.debuff and boss.debuff(card, ctx.rules) then
      if card.enh == "STEEL" then emit({ kind = "debuff", heldIndex = h }) end
    else
      -- A held card only repeats when its first evaluation did something.
      local function evaluate()
        local fired = false
        if card.enh == "STEEL" then
          mult = mult * 1.5
          emit({ kind = "held", heldIndex = h, xmult = 1.5 })
          fired = true
        end
        engine.each(trinkets, function(slot, inst, def, isCopy)
          local effect = def.onHeld and def.onHeld(ctx, inst, card, h, isCopy)
          if effect then
            apply(effect, slot, { heldIndex = h })
            fired = true
          end
        end)
        return fired
      end
      if evaluate() then
        for _, entry in ipairs(retriggers(card, "heldRetrigger", h)) do
          emit(sourceFields({ kind = "retrigger", heldIndex = h }, entry))
          evaluate()
        end
      end
    end
  end

  for slot, trinket in ipairs(trinkets) do
    if trinket.ed then applyEdition(trinket.ed, { slot = slot }, "pre") end
    local inst, def = engine.source(trinkets, slot)
    if inst then
      local effect = def.onHand and def.onHand(ctx, inst, inst ~= trinket)
      if effect then apply(effect, slot) end
    end
    local ownDef = ns.Trinkets.def[trinket.id]
    engine.each(trinkets, function(other, otherInst, otherDef, otherIsCopy)
      if other == slot or not ownDef or not otherDef.otherTrinket then return end
      local effect = otherDef.otherTrinket(ctx, otherInst, ownDef, otherIsCopy)
      if effect then apply(effect, other) end
    end)
    if trinket.ed then applyEdition(trinket.ed, { slot = slot }, "post") end
  end

  for _, item in ipairs(ctx.consumables or {}) do
    if item.kind == "tome" and item.id == handId then
      mult = mult * 1.5
      emit({ kind = "voucher", id = "OBSERVATORY", xmult = 1.5 })
    end
  end

  local total = math.floor(chips * mult)
  emit({ kind = "total", total = total })

  -- After hooks decay or destroy; only the trinket itself (not a copy) can be destroyed.
  ctx.bossTriggered = bossTriggered
  engine.each(trinkets, function(slot, inst, def, isCopy)
    local effect = def.after and def.after(ctx, inst, isCopy)
    if not effect then return end
    apply({ gold = effect.gold, msg = effect.msg, levelHand = effect.levelHand, changeCard = effect.changeCard,
      createCard = effect.createCard, createConsumable = effect.createConsumable,
      destroyCard = effect.destroyCard }, slot)
    if effect.destroySelf and not isCopy then destroyedUids[inst] = true end
  end)
  local destroyedTrinkets, trinketsAfter = {}, {}
  for _, trinket in ipairs(trinkets) do
    if destroyedUids[trinket] then
      destroyedTrinkets[#destroyedTrinkets + 1] = trinket.uid
      emit({ kind = "trinketDestroyed", uid = trinket.uid })
    else
      trinketsAfter[#trinketsAfter + 1] = trinket
    end
  end

  local destroyed = {}
  for _, i in ipairs(destroyCandidates) do
    if ns.Prob.roll(ctx.rng, trinkets, 1, 4) then
      destroyed[#destroyed + 1] = cards[i].id
      emit({ kind = "destroy", index = i })
    end
  end

  -- Whole-field snapshots of the scratch cards that differ from the real ones (a nil stays nil).
  local cardsAfter = {}
  local function diff(scratch, orig)
    for i, card in ipairs(scratch) do
      for _, field in ipairs(CARD_FIELDS) do
        if card[field] ~= orig[i][field] and card.id then
          cardsAfter[card.id] = { enh = card.enh, bonusChips = card.bonusChips, seal = card.seal, ed = card.ed }
          break
        end
      end
    end
  end
  diff(cards, origCards)
  diff(held, origHeld)

  return { handId = handId, chips = chips, mult = mult, total = total, events = events,
    gold = goldRef.gold - goldStart, destroyed = destroyed, trinketsAfter = trinketsAfter,
    levelUps = levelUps, destroyedTrinkets = destroyedTrinkets, cardsAfter = cardsAfter,
    sideEffects = sideEffects, bossTriggered = bossTriggered, luckyTriggers = luckyTriggers }
end

ns.Scoring = Scoring
