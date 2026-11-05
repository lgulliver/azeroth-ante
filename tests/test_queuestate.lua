local ns, T = ...

local QS = ns.QueueState

T.test("queue_joined_shows_and_queues", function()
  local qs = QS.new()
  T.eq(qs, { queued = false, paused = false })
  T.eq(QS.handle(qs, "QUEUE_JOINED"), "show")
  T.eq(qs.queued, true)
end)

T.test("join_twice_shows_once", function()
  local qs = QS.new()
  T.eq(QS.handle(qs, "QUEUE_JOINED"), "show")
  T.eq(QS.handle(qs, "QUEUE_JOINED"), nil)
  T.eq(qs.queued, true)
end)

T.test("queue_left_resets", function()
  local qs = { queued = true, paused = false }
  T.eq(QS.handle(qs, "QUEUE_LEFT"), nil)
  T.eq(qs, { queued = false, paused = false })
end)

T.test("queue_left_while_paused_resumes", function()
  local qs = { queued = true, paused = true }
  T.eq(QS.handle(qs, "QUEUE_LEFT"), "resume")
  T.eq(qs, { queued = false, paused = false })
end)

T.test("proposal_pauses", function()
  local qs = { queued = true, paused = false }
  T.eq(QS.handle(qs, "PROPOSAL"), "pause")
  T.eq(qs.paused, true)
  T.eq(qs.queued, true)
end)

T.test("proposal_failed_resumes", function()
  local qs = { queued = true, paused = true }
  T.eq(QS.handle(qs, "PROPOSAL_FAILED"), "resume")
  T.eq(qs.paused, false)
  T.eq(qs.queued, true)
end)

T.test("accepted_hides_and_clears", function()
  local qs = { queued = true, paused = true }
  T.eq(QS.handle(qs, "ACCEPTED"), "hide")
  T.eq(qs, { queued = false, paused = false })
end)

T.test("combat_hides_without_state_change", function()
  local qs = { queued = true, paused = false }
  T.eq(QS.handle(qs, "COMBAT"), "hide")
  T.eq(qs, { queued = true, paused = false })
end)
