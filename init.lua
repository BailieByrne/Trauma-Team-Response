local defaults = {
  enabled = true,
  corpoChance = 30,
  mercChance = 12,
  gangChance = 4,
  fringeChance = 1,
  silverWeight = 60,
  goldWeight = 30,
  silverDelay = 60,
  goldDelay = 45,
  platinumDelay = 30,
}

local settings = {}
for key, value in pairs(defaults) do settings[key] = value end

local function loadSettings()
  local file = io.open("config.json", "r")
  if not file then return end
  local ok, saved = pcall(json.decode, file:read("*a"))
  file:close()
  if ok and type(saved) == "table" then
    for key, value in pairs(defaults) do
      if type(saved[key]) == type(value) then settings[key] = saved[key] end
    end
  end
end

local function saveSettings()
  local file = io.open("config.json", "w")
  if file then
    file:write(json.encode(settings))
    file:close()
  end
end

local function applySettings()
  if not Game.GetPlayer() then return end
  for key, value in pairs(settings) do
    Game.TTSetSetting(key, type(value) == "boolean" and (value and 1 or 0) or value)
  end
end

local function changed(key, value)
  settings[key] = value
  saveSettings()
  applySettings()
end

registerForEvent("onInit", function()
  loadSettings()
  local menu = GetMod("nativeSettings")
  if not menu then
    print("[Trauma Team Subscriptions] Native Settings UI is required for the Mods tab")
    return
  end

  menu.addTab("/TTSubscriptions", "Trauma Team Subscriptions")
  menu.addSubcategory("/TTSubscriptions/General", "General")
  menu.addSubcategory("/TTSubscriptions/Chances", "Subscription chances")
  menu.addSubcategory("/TTSubscriptions/Tiers", "Policy tiers")
  menu.addSubcategory("/TTSubscriptions/Dispatch", "Dispatch timing")

  menu.addSwitch("/TTSubscriptions/General", "Enable subscriptions", "Disabling hides policies and prevents new dispatches. Existing assignments remain saved.", settings.enabled, defaults.enabled, function(value) changed("enabled", value) end)

  local function slider(path, label, desc, key, minimum, maximum)
    menu.addRangeInt(path, label, desc, minimum, maximum, 1, settings[key], defaults[key], function(value) changed(key, value) end)
  end
  slider("/TTSubscriptions/Chances", "Corporate and law elites (%)", "Arasaka, Militech, NCPD, Barghest and similar elites.", "corpoChance", 0, 100)
  slider("/TTSubscriptions/Chances", "Mercenary elites (%)", "Mercenaries and unclassified elites.", "mercChance", 0, 100)
  slider("/TTSubscriptions/Chances", "Gang elites (%)", "Major gang elites.", "gangChance", 0, 100)
  slider("/TTSubscriptions/Chances", "Nomad and Wraith elites (%)", "Wraith and Aldecaldo elites.", "fringeChance", 0, 100)
  slider("/TTSubscriptions/Tiers", "Silver weight (%)", "Gold uses its own weight; Platinum gets the remainder.", "silverWeight", 0, 100)
  slider("/TTSubscriptions/Tiers", "Gold weight (%)", "Keep Silver plus Gold at or below 100 for a Platinum chance.", "goldWeight", 0, 100)
  slider("/TTSubscriptions/Dispatch", "Silver delay (seconds)", "Countdown before the response is requested.", "silverDelay", 0, 180)
  slider("/TTSubscriptions/Dispatch", "Gold delay (seconds)", "Countdown before the response is requested.", "goldDelay", 0, 180)
  slider("/TTSubscriptions/Dispatch", "Platinum delay (seconds)", "Countdown before the response is requested.", "platinumDelay", 0, 180)
  applySettings()
  print("[Trauma Team Subscriptions] Added controls to the Mods tab")
end)

local refreshTimer = 0
registerForEvent("onUpdate", function(delta)
  refreshTimer = refreshTimer + delta
  if refreshTimer >= 5 then
    refreshTimer = 0
    applySettings()
  end
end)
