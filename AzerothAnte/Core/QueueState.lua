local _, ns = ...

local QueueState = {}

function QueueState.new()
  return { queued = false, paused = false }
end

function QueueState.handle(qs, ev)
  if ev == "QUEUE_JOINED" then
    if qs.queued then return nil end
    qs.queued = true
    return "show"
  elseif ev == "QUEUE_LEFT" then
    local wasPaused = qs.paused
    qs.queued, qs.paused = false, false
    return wasPaused and "resume" or nil
  elseif ev == "PROPOSAL" then
    qs.paused = true
    return "pause"
  elseif ev == "PROPOSAL_FAILED" then
    qs.paused = false
    return "resume"
  elseif ev == "ACCEPTED" then
    qs.queued, qs.paused = false, false
    return "hide"
  elseif ev == "COMBAT" then
    return "hide"
  end
  return nil
end

ns.QueueState = QueueState
