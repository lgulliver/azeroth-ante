local _, ns = ...

-- The addon's page in the game's Settings panel. Values live in
-- AzerothAnteDB.options; a missing key means the default.
local Options = {}

Options.DEFAULTS = { openOnQueue = true, padOnAutoOpen = true, openOnFlight = true }

function Options.Get(key)
  local options = AzerothAnteDB and AzerothAnteDB.options
  local value = options and options[key]
  if value == nil then return Options.DEFAULTS[key] end
  return value
end

-- Fills missing keys, then registers the page. Clients without the modern
-- Settings API keep the defaults and simply get no page.
function Options.Register(db)
  db.options = db.options or {}
  for key, value in pairs(Options.DEFAULTS) do
    if db.options[key] == nil then db.options[key] = value end
  end
  if Options.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local ok, category = pcall(function()
    local category = Settings.RegisterVerticalLayoutCategory("Azeroth Ante")
    local function checkbox(variable, key, name, tooltip)
      local setting = Settings.RegisterAddOnSetting(category, variable, key,
        db.options, Settings.VarType.Boolean, name, Options.DEFAULTS[key])
      Settings.CreateCheckbox(category, setting, tooltip)
    end
    checkbox("AZEROTHANTE_OPEN_ON_QUEUE", "openOnQueue", "Open when you join a queue",
      "Open the window when you join a dungeon, raid or battleground queue.")
    checkbox("AZEROTHANTE_PAD_ON_AUTO_OPEN", "padOnAutoOpen", "Take the controller when the window opens itself",
      "When a queue or flight path opens the window, your gamepad plays the game straight away. Press B to give it back.")
    checkbox("AZEROTHANTE_OPEN_ON_FLIGHT", "openOnFlight", "Open on flight paths",
      "Open the window when you take a flight path, and close it again when you land.")
    Settings.RegisterAddOnCategory(category)
    return category
  end)
  if ok then Options.category = category end
end

ns.UI.Options = Options
