-- Battlewright: slash commands. Loaded last so every module exists.
local _, ns = ...

local function help()
  ns.print("commands:")
  print("  /bw unlock | lock     move the icon (drag it), then lock it")
  print("  /bw scale <0.5-2>     icon size")
  print("  /bw spec <assassination|combat|subtlety|auto>")
  print("  /bw target            also show it out of combat when you target an enemy")
  print("  /bw on | off          turn Battlewright on or off")
  print("  /bw reset             put the icon back in the middle")
end

SLASH_BATTLEWRIGHT1 = "/bw"
SLASH_BATTLEWRIGHT2 = "/battlewright"
SlashCmdList.BATTLEWRIGHT = function(msg)
  local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  local db = ns.db
  if cmd == "unlock" or cmd == "lock" then
    db.locked = cmd == "lock"
    ns.print(db.locked and "locked" or "unlocked: drag the icon, then /bw lock")
  elseif cmd == "scale" and tonumber(arg) then
    db.scale = math.max(0.5, math.min(2, tonumber(arg)))
    if ns.Display.frame then ns.Display.Place() end
  elseif cmd == "spec" then
    db.specOverride = (arg ~= "" and arg ~= "auto") and arg or false
    ns.print("spec: %s", db.specOverride or "from your talents")
  elseif cmd == "target" then
    db.showOutOfCombat = not db.showOutOfCombat
    ns.print("show out of combat with an enemy targeted: %s", db.showOutOfCombat and "on" or "off")
  elseif cmd == "on" or cmd == "off" then
    db.enabled = cmd == "on"
    ns.print(db.enabled and "on" or "off")
  elseif cmd == "reset" then
    db.point = { "CENTER", "CENTER", 0, -160 }
    if ns.Display.frame then ns.Display.Place() end
  else
    help()
  end
  if ns.Display.frame then ns.Display.Update() end
end
