local _, ns = ...

local Scoring = {}

local function lookup(registry, id)
  if not id or not registry then return nil end
  return registry.def[id]
end

function Scoring.score(ctx)
  local cards = ctx.cards
  local handId, scoringIdx = ns.HandEval.evaluate(cards)
  ctx.contains = ns.HandEval.contains(cards)

  local boss = lookup(ns.Bosses, ctx.bossId)
  local chips, mult = ns.Hands.base(handId, (ctx.handLevels and ctx.handLevels[handId]) or 1)
  if boss and boss.halveBase then
    chips = math.floor(chips / 2)
    mult = math.max(1, math.floor(mult / 2))
  end

  local events = {}
  local function emit(event)
    event.runChips, event.runMult = chips, mult
    events[#events + 1] = event
  end

  local goldRef = ctx.goldRef or { gold = ctx.gold or 0 }
  ctx.goldRef = goldRef
  local goldStart = goldRef.gold
  local held = ctx.held or {}
  local trinkets = ctx.trinkets or {}

  local function apply(effect, slot, index)
    if effect.chips then chips = chips + effect.chips end
    if effect.mult then mult = mult + effect.mult end
    if effect.xmult then mult = mult * effect.xmult end
    emit({ kind = "trinket", slot = slot, chips = effect.chips, mult = effect.mult,
      xmult = effect.xmult, index = index })
  end

  -- Foil and Holo before, Poly after. A kind of "edition" event for a card or a trinket slot.
  local function applyEdition(ed, where, phase)
    local e = { kind = "edition", ed = ed, index = where.index, slot = where.slot }
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
      if ns.Prob.roll(ctx.rng, ctx.trinkets or {}, 1, 5) then enhEvent(i, card, { mult = 20 }) end
      if ns.Prob.roll(ctx.rng, ctx.trinkets or {}, 1, 15) then
        goldRef.gold = goldRef.gold + 20
        emit({ kind = "money", index = i, gold = 20 })
      end
    end
    if card.ed then
      applyEdition(card.ed, { index = i }, "pre")
      applyEdition(card.ed, { index = i }, "post")
    end
    if card.seal == "GOLD" then
      goldRef.gold = goldRef.gold + 3
      emit({ kind = "seal", index = i, seal = "GOLD", gold = 3 })
    end
    for slot, trinket in ipairs(trinkets) do
      local def = lookup(ns.Trinkets, trinket.id)
      local effect = def and def.onCard and def.onCard(ctx, card)
      if effect then apply(effect, slot, i) end
    end
  end

  emit({ kind = "base", handId = handId, chips = chips, mult = mult })

  local destroyCandidates = {}
  for _, i in ipairs(scoringIdx) do
    local card = cards[i]
    if boss and boss.debuff and boss.debuff(card) then
      emit({ kind = "debuff", index = i })
    else
      cardStep(i, card)
      if card.seal == "RED" then
        emit({ kind = "retrigger", index = i })
        cardStep(i, card)
      end
      if card.enh == "GLASS" then destroyCandidates[#destroyCandidates + 1] = i end
    end
  end

  for h, card in ipairs(held) do
    if card.enh == "STEEL" then
      if boss and boss.debuff and boss.debuff(card) then
        emit({ kind = "debuff", heldIndex = h })
      else
        for pass = 1, (card.seal == "RED") and 2 or 1 do
          if pass == 2 then emit({ kind = "retrigger", heldIndex = h }) end
          mult = mult * 1.5
          emit({ kind = "held", heldIndex = h, xmult = 1.5 })
        end
      end
    end
  end

  for slot, trinket in ipairs(trinkets) do
    local def = lookup(ns.Trinkets, trinket.id)
    if trinket.ed then applyEdition(trinket.ed, { slot = slot }, "pre") end
    local effect = def and def.onHand and def.onHand(ctx)
    if effect then apply(effect, slot) end
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

  local destroyed = {}
  for _, i in ipairs(destroyCandidates) do
    if ns.Prob.roll(ctx.rng, ctx.trinkets or {}, 1, 4) then
      destroyed[#destroyed + 1] = cards[i].id
      emit({ kind = "destroy", index = i })
    end
  end

  return { handId = handId, chips = chips, mult = mult, total = total, events = events,
    gold = goldRef.gold - goldStart, destroyed = destroyed }
end

ns.Scoring = Scoring
