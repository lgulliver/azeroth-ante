local ns, T = ...

-- WoW supplies the event loop and UI; keep QueueState and Save real.
local function harness(file)
  local h = { calls = {}, frames = {}, modes = {}, statuses = {}, combat = false }
  local env = setmetatable({
    LE_LFG_CATEGORY_LFD = 1, LE_LFG_CATEGORY_RF = 2,
    LE_LFG_CATEGORY_SCENARIO = 3, LE_LFG_CATEGORY_LFR = 4,
    LE_LFG_CATEGORY_FLEXRAID = 5, SOUNDKIT = { READY_CHECK = 8960 },
    SlashCmdList = {},
  }, { __index = _G })
  local function record(name) h.calls[#h.calls + 1] = name end
  env.CreateFrame = function(kind, name)
    T.eq(kind, "Frame")
    T.eq(name, nil)
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(script, fn) T.eq(script, "OnEvent"); self.handler = fn end
    h.frames[#h.frames + 1] = frame
    return frame
  end
  env.GetLFGMode = function(category) return h.modes[category] end
  env.GetMaxBattlefieldID = function() return 3 end
  env.GetBattlefieldStatus = function(index) return h.statuses[index] or "none" end
  env.InCombatLockdown = function() return h.combat end
  env.PlaySound = function(id) T.eq(id, 8960); record("sound") end
  local main = {
    Create = function() record("create") end,
    SetRun = function(run) h.run = run; record("setrun") end,
    Show = function() record("show") end,
    Hide = function() record("hide") end,
    Toggle = function() record("toggle") end,
  }
  h.ns = { QueueState = ns.QueueState, Save = ns.Save, UI = {
    Main = main,
    Screens = {
      ShowPaused = function() record("pause") end,
      HidePaused = function() record("resume") end,
    },
    OnRunChanged = function() record("save") end,
  } }
  h.env = env
  local chunk = assert(loadfile("AzerothAnte/" .. file))
  setfenv(chunk, env)("AzerothAnte", h.ns)
  function h:fire(event, ...)
    for _, frame in ipairs(self.frames) do
      if frame.events[event] then frame.handler(frame, event, ...) end
    end
  end
  function h:clear() self.calls = {} end
  return h
end

T.test("bootstrap_filters_load_creates_before_restore_and_unregisters", function()
  local h = harness("AzerothAnte.lua")
  T.eq(#h.frames, 1)
  h.env.AzerothAnteDB = { version = 1, run = { phase = "play", score = 42 } }
  h:fire("ADDON_LOADED", "OtherAddon")
  T.eq(h.calls, {})
  h:fire("ADDON_LOADED", "AzerothAnte")
  T.eq(h.calls, { "create", "setrun" })
  T.eq(h.run, { phase = "play", score = 42 })
  T.ok(h.run ~= h.env.AzerothAnteDB.run)
  h:fire("ADDON_LOADED", "AzerothAnte")
  T.eq(h.calls, { "create", "setrun" })
end)

T.test("bootstrap_empty_db_slash_in_combat_and_logout_hook", function()
  local h = harness("AzerothAnte.lua")
  h:fire("ADDON_LOADED", "AzerothAnte")
  T.eq(h.env.AzerothAnteDB, {})
  T.eq(h.run, nil)
  T.eq(h.env.SLASH_AZEROTHANTE1, "/ante")
  h:clear()
  h.combat = true
  h.env.SlashCmdList.AZEROTHANTE()
  h:fire("PLAYER_LOGOUT")
  T.eq(h.calls, { "toggle", "save" })
  h.ns.UI.OnRunChanged = nil
  h:fire("PLAYER_LOGOUT")
end)

T.test("queue_join_leave_transitions_across_all_lfg_categories_and_modes", function()
  for category = 1, 5 do
    for _, mode in ipairs({ "queued", "proposal", "rolecheck" }) do
      local h = harness("Queue.lua")
      h:fire("LFG_UPDATE")
      T.eq(h.calls, {})
      h.modes[category] = mode
      h:fire("LFG_UPDATE")
      h:fire("LFG_QUEUE_STATUS_UPDATE")
      T.eq(h.calls, { "show" })
      h.modes[category] = nil
      h:fire("LFG_QUEUE_STATUS_UPDATE")
      h.modes[category] = mode
      h:fire("LFG_UPDATE")
      T.eq(h.calls, { "show", "show" })
    end
  end
end)

T.test("queue_combines_sources_and_battlefield_edges_without_repeated_pop", function()
  local h = harness("Queue.lua")
  h.statuses[3] = "queued"
  h:fire("UPDATE_BATTLEFIELD_STATUS", 3)
  T.eq(h.calls, { "show" })
  h.modes[2] = "queued"
  h.statuses[3] = "none"
  h:fire("UPDATE_BATTLEFIELD_STATUS", 3)
  T.eq(h.calls, { "show" })
  h:clear()
  h.statuses[3] = "confirm"
  h:fire("UPDATE_BATTLEFIELD_STATUS", 3)
  h:fire("LFG_UPDATE")
  T.eq(h.calls, { "show", "pause", "sound" })
  h:clear()
  h.statuses[3] = "active"
  h:fire("UPDATE_BATTLEFIELD_STATUS", 3)
  h:fire("UPDATE_BATTLEFIELD_STATUS", 3)
  T.eq(h.calls, { "resume", "hide" })
  h:clear()
  h.statuses[3] = "none"
  h:fire("UPDATE_BATTLEFIELD_STATUS", 3)
  h.statuses[3] = "confirm"
  h:fire("UPDATE_BATTLEFIELD_STATUS", 3)
  T.eq(h.calls, { "show", "pause", "sound" })
end)

T.test("queue_confirm_counts_as_queued_and_active_hides_after_leaving", function()
  local h = harness("Queue.lua")
  h.statuses[1] = "confirm"
  h:fire("UPDATE_BATTLEFIELD_STATUS", 1)
  T.eq(h.calls, { "show", "show", "pause", "sound" })
  h:clear()
  h.statuses[1] = "active"
  h:fire("UPDATE_BATTLEFIELD_STATUS", 1)
  T.eq(h.calls, { "resume", "hide" })
end)

T.test("queue_direct_events_sound_guard_and_combat_hide", function()
  local h = harness("Queue.lua")
  h:fire("LFG_PROPOSAL_SHOW")
  h:fire("LFG_PROPOSAL_FAILED")
  h:fire("LFG_PROPOSAL_SUCCEEDED")
  h:fire("PLAYER_REGEN_DISABLED")
  T.eq(h.calls, { "show", "pause", "sound", "resume", "resume", "hide", "resume", "hide" })
  h:clear()
  h.env.SOUNDKIT = nil
  h:fire("LFG_PROPOSAL_SHOW")
  T.eq(h.calls, { "show", "pause" })
end)

T.test("queue_suppresses_automatic_show_in_combat", function()
  local h = harness("Queue.lua")
  h.combat = true
  h.modes[1] = "queued"
  h:fire("LFG_UPDATE")
  T.eq(h.calls, {})
  h:fire("PLAYER_REGEN_DISABLED")
  T.eq(h.calls, { "resume", "hide" })
end)

T.test("queue_skips_nil_categories_and_tolerates_missing_or_throwing_apis", function()
  local h = harness("Queue.lua")
  h.env.LE_LFG_CATEGORY_RF = nil
  h.env.GetLFGMode = function(category)
    T.ok(category ~= nil)
    if category == 1 then error("unsupported category") end
    if category == 5 then return "queued" end
  end
  h.env.GetBattlefieldStatus = function() error("unsupported battlefield") end
  h:fire("LFG_UPDATE")
  T.eq(h.calls, { "show" })
  h:clear()
  h.env.GetLFGMode = nil
  h.env.GetMaxBattlefieldID = nil
  h:fire("LFG_UPDATE")
  T.eq(h.calls, {})
end)
