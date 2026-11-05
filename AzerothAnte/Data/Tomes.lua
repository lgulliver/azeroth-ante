local _, ns = ...

-- One Tome per hand type. A Tome id is its handId.
local Tomes = { order = {}, def = {} }

for i, handId in ipairs(ns.Hands.order) do
  Tomes.order[i] = handId
  Tomes.def[handId] = {
    id = handId, handId = handId, name = "Tome of " .. ns.Hands.def[handId].name,
  }
end

ns.Tomes = Tomes
