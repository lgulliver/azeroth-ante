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

  local function apply(effect, slot, index)
    if effect.chips then chips = chips + effect.chips end
    if effect.mult then mult = mult + effect.mult end
    if effect.xmult then mult = mult * effect.xmult end
    emit({ kind = "trinket", slot = slot, chips = effect.chips, mult = effect.mult,
      xmult = effect.xmult, index = index })
  end

  emit({ kind = "base", handId = handId, chips = chips, mult = mult })

  for _, i in ipairs(scoringIdx) do
    local card = cards[i]
    if boss and boss.debuff and boss.debuff(card) then
      emit({ kind = "debuff", index = i })
    else
      local value = ns.Cards.chipValue(card)
      chips = chips + value
      emit({ kind = "card", index = i, chips = value })
      for slot, trinket in ipairs(ctx.trinkets or {}) do
        local def = lookup(ns.Trinkets, trinket.id)
        local effect = def and def.onCard and def.onCard(ctx, card)
        if effect then apply(effect, slot, i) end
      end
    end
  end

  for slot, trinket in ipairs(ctx.trinkets or {}) do
    local def = lookup(ns.Trinkets, trinket.id)
    local effect = def and def.onHand and def.onHand(ctx)
    if effect then apply(effect, slot) end
  end

  local total = math.floor(chips * mult)
  emit({ kind = "total", total = total })
  return { handId = handId, chips = chips, mult = mult, total = total, events = events }
end

ns.Scoring = Scoring
