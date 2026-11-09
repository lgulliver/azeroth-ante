local _, ns = ...

-- The addon's page in the game's Settings panel. Values live in
-- AzerothAnteDB.options; a missing key means the default.
local Options = {}

Options.DEFAULTS = { openOnFlight = true }

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
    local setting = Settings.RegisterAddOnSetting(category, "AZEROTHANTE_OPEN_ON_FLIGHT", "openOnFlight",
      db.options, Settings.VarType.Boolean, "Open on flight paths", Options.DEFAULTS.openOnFlight)
    Settings.CreateCheckbox(category, setting,
      "Open the window when you take a flight path, and close it again when you land.")
    Settings.RegisterAddOnCategory(category)
    return category
  end)
  if ok then Options.category = category end
end

ns.UI.Options = Options
