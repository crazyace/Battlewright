-- Battlewright: bootstrap, event bus, saved settings.
-- A rotation helper: shows the next ability to press. The rotation code is
-- pure (Rotations/*.lua take a state table, State.lua builds it from the game)
-- so it can be tested without a client.
local ADDON, ns = ...

ns.name = ADDON
ns.Rotations = ns.Rotations or {}

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (getMeta and getMeta(ADDON, "Version")) or "dev"

local frame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    if not pcall(frame.RegisterEvent, frame, event) then return end
  end
  table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
  end
end)

local DEFAULTS = {
  enabled = true,
  locked = true,
  scale = 1,
  point = { "CENTER", "CENTER", 0, -160 },
  specOverride = false, -- false = from your talents
  showOutOfCombat = false, -- also show with an attackable target out of combat
  assumeBehind = false, -- suggest Backstab (the game doesn't say where you stand)
  guideMode = false, -- the guide's Solo/Group choice; false = Group while in a party, else Solo
}

ns:On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  BattlewrightDB = BattlewrightDB or {}
  for k, v in pairs(DEFAULTS) do
    if BattlewrightDB[k] == nil then BattlewrightDB[k] = v end
  end
  ns.db = BattlewrightDB
end)

function ns.print(fmt, ...)
  print("|cffd9a441Battlewright|r: " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end
