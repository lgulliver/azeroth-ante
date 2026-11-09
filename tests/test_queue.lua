local ns, T = ...

-- WoW supplies the event loop and UI; keep QueueState and Save real.
local function harness(file)
  local h = { calls = {}, frames = {}, modes = {}, statuses = {}, combat = false, taxi = false, timers = {} }
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
  env.UnitOnTaxi = function(unit) T.eq(unit, "player"); return h.taxi end
  env.C_Timer = { After = function(_, fn) h.timers[#h.timers + 1] = fn end }
  env.PlaySound = function(id) T.eq(id, 8960); record("sound") end
  local main
  main = {
    Create = function() record("create") end,
    SetRun = function(run) h.run = run; main.run = run; record("setrun") end,
    Show = function() h.shown = true; record("show") end,
    Hide = function() h.shown = false; record("hide") end,
    IsShown = function() return h.shown == true end,
    Toggle = function() record("toggle") end,
  }
  h.ns = { QueueState = ns.QueueState, Save = ns.Save, UI = {
    Main = main,
    Screens = {
      ShowPaused = function() record("pause") end,
      HidePaused = function() record("resume") end,
    },
    OnRunChanged = function()
      record("save")
      if env.AzerothAnteDB and main.run then ns.Save.store(env.AzerothAnteDB, main.run) end
    end,
  } }
  h.env = env
  function h:load(name)
    local before = {}
    for key in pairs(env) do before[key] = true end
    local chunk = assert(loadfile("AzerothAnte/" .. name))
    setfenv(chunk, env)("AzerothAnte", self.ns)
    for key in pairs(env) do
      T.ok(before[key] or key == "AzerothAnteDB" or key == "SLASH_AZEROTHANTE1"
        or key == "SlashCmdList", "unexpected global: " .. tostring(key))
    end
  end
  h:load("UI/Options.lua")
  h:load(file)
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
  local run = ns.Run.new(7, "ADVENTURER")
  ns.Run.startBlind(run)
  run.score = 42
  h.env.AzerothAnteDB = { version = ns.Save.VERSION, run = run }
  h:fire("ADDON_LOADED", "OtherAddon")
  T.eq(h.calls, {})
  h:fire("ADDON_LOADED", "AzerothAnte")
  T.eq(h.calls, { "create", "setrun" })
  T.eq(h.run, run)
  T.ok(h.run ~= h.env.AzerothAnteDB.run)
  h:fire("ADDON_LOADED", "AzerothAnte")
  T.eq(h.calls, { "create", "setrun" })
end)

T.test("bootstrap_empty_db_slash_in_combat_and_logout_hook", function()
  local h = harness("AzerothAnte.lua")
  h:fire("ADDON_LOADED", "AzerothAnte")
  T.eq(h.env.AzerothAnteDB, { options = { openOnFlight = true } })
  T.eq(h.run, nil)
  T.eq(h.env.SLASH_AZEROTHANTE1, "/ante")
  h:clear()
  h.combat = true
  h.env.SlashCmdList.AZEROTHANTE()
  T.eq(h.calls, { "toggle" })
  -- Match Screens.lua's OnRunChanged: store Main.run through the real Save module.
  local run = ns.Run.new(7, "ADVENTURER")
  ns.Run.startBlind(run)
  run.score = 42
  h.ns.UI.Main.SetRun(run)
  h:clear()
  h:fire("PLAYER_LOGOUT")
  T.eq(h.calls, { "save" })
  T.eq(h.env.AzerothAnteDB.run, h.run)
  T.ok(h.env.AzerothAnteDB.run ~= h.run)
  local loaded = ns.Save.load(h.env.AzerothAnteDB)
  T.eq(loaded, h.run)
  T.ok(loaded ~= h.env.AzerothAnteDB.run)
  T.ok(loaded.hand ~= h.env.AzerothAnteDB.run.hand)
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
  -- First show joins the queue; second show brings the proposal window forward.
  T.eq(h.calls, { "show", "show", "pause", "sound" })
  h:clear()
  h.statuses[1] = "active"
  h:fire("UPDATE_BATTLEFIELD_STATUS", 1)
  -- Leaving the queue while paused and the failed proposal each resume (idempotent).
  T.eq(h.calls, { "resume", "resume", "hide" })
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

T.test("queue_and_bootstrap_define_only_allowed_globals", function()
  local h = harness("Queue.lua")
  h:load("AzerothAnte.lua")
  h:fire("ADDON_LOADED", "AzerothAnte")
  T.eq(h.env.AzerothAnteDB, { options = { openOnFlight = true } })
  T.eq(h.env.SLASH_AZEROTHANTE1, "/ante")
  for key in pairs(h.env.SlashCmdList) do T.eq(key, "AZEROTHANTE") end
end)

T.test("queue_proposal_in_combat_plays_only_sound", function()
  local h = harness("Queue.lua")
  h.combat = true
  h:fire("LFG_PROPOSAL_SHOW")
  T.eq(h.calls, { "sound" })
  h:clear()
  h.env.SOUNDKIT = nil
  h:fire("LFG_PROPOSAL_SHOW")
  T.eq(h.calls, {})
end)

T.test("queue_battlefield_decline_or_expiry_clears_paused", function()
  -- Dropping out of the queue entirely also resumes via QUEUE_LEFT while paused.
  local expected = { none = { "resume", "resume" }, queued = { "resume" }, error = { "resume", "resume" } }
  for _, status in ipairs({ "none", "queued", "error" }) do
    local h = harness("Queue.lua")
    h.statuses[1] = "confirm"
    h:fire("UPDATE_BATTLEFIELD_STATUS", 1)
    h:clear()
    h.statuses[1] = status
    h:fire("UPDATE_BATTLEFIELD_STATUS", 1)
    h:fire("UPDATE_BATTLEFIELD_STATUS", 1)
    T.eq(h.calls, expected[status])
  end
end)

T.test("queue_retries_combat_suppressed_show_once", function()
  for _, proposal in ipairs({ false, true }) do
    local h = harness("Queue.lua")
    h.combat = true
    h.modes[1] = "queued"
    h:fire("LFG_UPDATE")
    if proposal then h:fire("LFG_PROPOSAL_SHOW") end
    h:fire("PLAYER_REGEN_DISABLED")
    h:clear()
    h:fire("PLAYER_REGEN_ENABLED")
    T.eq(h.calls, {})
    h.combat = false
    h:fire("PLAYER_REGEN_ENABLED")
    h:fire("PLAYER_REGEN_ENABLED")
    T.eq(h.calls, proposal and { "show", "pause" } or { "show" })
  end
end)

T.test("queue_retries_pending_proposal_without_queue_scan", function()
  local h = harness("Queue.lua")
  h.combat = true
  h:fire("LFG_PROPOSAL_SHOW")
  h:clear()
  h.combat = false
  h:fire("PLAYER_REGEN_ENABLED")
  T.eq(h.calls, { "show", "pause" })
end)

T.test("queue_does_not_retry_departed_queue_or_resolved_proposal", function()
  for _, event in ipairs({ "LFG_UPDATE", "LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_SUCCEEDED" }) do
    local h = harness("Queue.lua")
    h.combat = true
    if event == "LFG_UPDATE" then
      h.modes[1] = "queued"
      h:fire("LFG_UPDATE")
      h.modes[1] = nil
    else
      h:fire("LFG_PROPOSAL_SHOW")
    end
    h:fire(event)
    h:clear()
    h.combat = false
    h:fire("PLAYER_REGEN_ENABLED")
    T.eq(h.calls, {})
  end
end)

-- Runs the flight poll once, as the next C_Timer tick would.
local function tick(h)
  local fn = table.remove(h.timers, 1)
  fn()
  T.eq(#h.timers, 1, "the poll reschedules itself")
end

T.test("flight_polls_and_opens_on_takeoff_closes_on_landing", function()
  local h = harness("Queue.lua")
  T.eq(#h.timers, 1)
  tick(h)
  T.eq(h.calls, {})
  h.taxi = true
  tick(h)
  tick(h)
  T.eq(h.calls, { "show" })
  h.taxi = false
  tick(h)
  tick(h)
  T.eq(h.calls, { "show", "hide" })
end)

T.test("flight_ignores_control_events", function()
  local h = harness("Queue.lua")
  h.taxi = true
  h:fire("PLAYER_CONTROL_LOST")
  h:fire("PLAYER_CONTROL_GAINED")
  T.eq(h.calls, {})
end)

T.test("flight_respects_disabled_option_and_combat", function()
  local h = harness("Queue.lua")
  h.env.AzerothAnteDB = { options = { openOnFlight = false } }
  h.taxi = true
  tick(h)
  h.taxi = false
  tick(h)
  T.eq(h.calls, {})
  h.env.AzerothAnteDB = nil
  h.combat = true
  h.taxi = true
  tick(h)
  T.eq(h.calls, {})
end)

T.test("flight_landing_leaves_window_opened_elsewhere_or_queued", function()
  local h = harness("Queue.lua")
  h.ns.UI.Main.Show()
  h:clear()
  h.taxi = true
  tick(h)
  h.taxi = false
  tick(h)
  T.eq(h.calls, {})
  h.ns.UI.Main.Hide()
  h:clear()
  h.taxi = true
  tick(h)
  h.modes[1] = "queued"
  h:fire("LFG_UPDATE")
  h.taxi = false
  tick(h)
  T.eq(h.calls, { "show", "show" })
end)

T.test("options_fill_defaults_keep_choices_and_register_once", function()
  local h = harness("Queue.lua")
  local Options = h.ns.UI.Options
  T.eq(Options.Get("openOnFlight"), true)
  local registered = {}
  h.env.Settings = {
    VarType = { Boolean = "boolean" },
    RegisterVerticalLayoutCategory = function(name) return { name = name } end,
    RegisterAddOnSetting = function(category, variable, key, tbl, kind, name, default)
      registered.setting = { variable = variable, key = key, tbl = tbl, kind = kind, default = default }
      return registered.setting
    end,
    CreateCheckbox = function(_, setting) registered.checkbox = setting end,
    RegisterAddOnCategory = function(category) registered.category = category end,
  }
  local db = { options = { openOnFlight = false } }
  h.env.AzerothAnteDB = db
  Options.Register(db)
  T.eq(db.options.openOnFlight, false)
  T.eq(Options.Get("openOnFlight"), false)
  T.eq(registered.category, { name = "Azeroth Ante" })
  T.ok(registered.setting.tbl == db.options)
  T.eq(registered.setting.default, true)
  T.ok(registered.checkbox == registered.setting)
  registered.category = nil
  Options.Register(db)
  T.eq(registered.category, nil)
end)
