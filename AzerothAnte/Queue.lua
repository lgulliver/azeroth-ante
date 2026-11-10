local _, ns = ...

local Queue = {}
local state = ns.QueueState.new()
local lastQueued = false
local pendingShow = false
local battlefieldStatuses = {}
local onTaxi = false
local flightShown = false -- the window was opened by the flight, so landing closes it
local TAXI_POLL = 0.5

local function autoEnter()
  if ns.UI.Pad then ns.UI.Pad.AutoEnter() end
end

local function emit(event)
  local action = ns.QueueState.handle(state, event)
  if not state.queued and not state.paused then pendingShow = false end
  local Main, Screens = ns.UI.Main, ns.UI.Screens
  local openOnQueue = ns.UI.Options.Get("openOnQueue")
  if action == "show" then
    pendingShow = openOnQueue and InCombatLockdown()
    if openOnQueue and not pendingShow then
      Main.Show()
      autoEnter()
    end
  elseif action == "pause" then
    -- With opening off, a pop only reaches a window the player already has open.
    local open = openOnQueue or Main.IsShown()
    pendingShow = open and InCombatLockdown()
    if open and not pendingShow then
      Main.Show()
      Screens.ShowPaused()
    end
    if SOUNDKIT and SOUNDKIT.READY_CHECK and PlaySound then PlaySound(SOUNDKIT.READY_CHECK) end
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
      if battlefieldStatuses[i] == "confirm" and status ~= "active" then
        emit("PROPOSAL_FAILED")
      end
      if status == "confirm" then
        emit("PROPOSAL")
      elseif status == "active" then
        emit("ACCEPTED")
      end
    end
  end
  battlefieldStatuses = statuses
end

-- Polled: no event marks takeoff reliably (PLAYER_CONTROL_LOST may not fire,
-- and UnitOnTaxi still reads true as PLAYER_CONTROL_GAINED fires on landing).
local function updateFlight()
  local ok, taxi = pcall(UnitOnTaxi, "player")
  taxi = ok and taxi and true or false
  if taxi == onTaxi then return end
  onTaxi = taxi
  local Main = ns.UI.Main
  if taxi then
    if ns.UI.Options.Get("openOnFlight") and not InCombatLockdown() and not Main.IsShown() then
      flightShown = true
      Main.Show()
      autoEnter()
    end
  else
    if flightShown and not state.queued and not state.paused then Main.Hide() end
    flightShown = false
  end
end

local function pollFlight()
  updateFlight()
  C_Timer.After(TAXI_POLL, pollFlight)
end
if C_Timer then C_Timer.After(TAXI_POLL, pollFlight) end

local events = {
  LFG_PROPOSAL_SHOW = "PROPOSAL",
  LFG_PROPOSAL_FAILED = "PROPOSAL_FAILED",
  LFG_PROPOSAL_SUCCEEDED = "ACCEPTED",
  PLAYER_REGEN_DISABLED = "COMBAT",
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("LFG_UPDATE")
frame:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
for event in pairs(events) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if pendingShow and not InCombatLockdown() then
      pendingShow = false
      if state.queued or state.paused then
        ns.UI.Main.Show()
        if state.paused then ns.UI.Screens.ShowPaused() else autoEnter() end
      end
    end
  elseif events[event] then
    emit(events[event])
  else
    updateQueues()
  end
end)

Queue.frame = frame
ns.Queue = Queue
