local _, ns = ...

local Queue = {}
local state = ns.QueueState.new()
local lastQueued = false
local battlefieldStatuses = {}

local function emit(event)
  local action = ns.QueueState.handle(state, event)
  local Main, Screens = ns.UI.Main, ns.UI.Screens
  if action == "show" then
    if not InCombatLockdown() then Main.Show() end
  elseif action == "pause" then
    Main.Show()
    Screens.ShowPaused()
    if SOUNDKIT then PlaySound(SOUNDKIT.READY_CHECK) end
  elseif action == "resume" then
    Screens.HidePaused()
  elseif action == "hide" then
    Screens.HidePaused()
    Main.Hide()
  end
end

local function updateQueues()
  local queued = false
  local categories = {
    LE_LFG_CATEGORY_LFD, LE_LFG_CATEGORY_RF, LE_LFG_CATEGORY_SCENARIO,
    LE_LFG_CATEGORY_LFR, LE_LFG_CATEGORY_FLEXRAID,
  }
  -- pairs visits defined categories even when an earlier global is nil.
  for _, category in pairs(categories) do
    local ok, mode = pcall(GetLFGMode, category)
    if ok and (mode == "queued" or mode == "proposal" or mode == "rolecheck") then
      queued = true
    end
  end

  local statuses = {}
  local ok, count = pcall(GetMaxBattlefieldID)
  if ok and count then
    for i = 1, count do
      local statusOK, status = pcall(GetBattlefieldStatus, i)
      if statusOK then
        statuses[i] = status
        if status == "queued" or status == "confirm" then queued = true end
      end
    end
  end

  if queued ~= lastQueued then
    lastQueued = queued
    emit(queued and "QUEUE_JOINED" or "QUEUE_LEFT")
  end
  for i, status in pairs(statuses) do
    if status ~= battlefieldStatuses[i] then
      if status == "confirm" then
        emit("PROPOSAL")
      elseif status == "active" then
        emit("ACCEPTED")
      end
    end
  end
  battlefieldStatuses = statuses
end

local events = {
  LFG_PROPOSAL_SHOW = "PROPOSAL",
  LFG_PROPOSAL_FAILED = "PROPOSAL_FAILED",
  LFG_PROPOSAL_SUCCEEDED = "ACCEPTED",
  PLAYER_REGEN_DISABLED = "COMBAT",
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("LFG_UPDATE")
frame:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
for event in pairs(events) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event)
  if events[event] then emit(events[event]) else updateQueues() end
end)

Queue.frame = frame
ns.Queue = Queue
