-- Battlewright: slash commands. Loaded last so every module exists.
local _, ns = ...

local function help()
  ns.print("commands:")
  print("  /bw unlock | lock     move the icon (drag it), then lock it")
  print("  /bw scale <0.5-2>     icon size")
  print("  /bw spec <assassination|combat|subtlety|auto>")
  print("  /bw target            also show it out of combat when you target an enemy")
  print("  /bw behind            assume you're behind the target (suggests Backstab with a dagger)")
  print("  /bw guide [solo|group|talents|rotation]  your rotation and talent build")
  print("  /bw talents           your spec and talents, and which ones the rotation uses")
  print("  /bw on | off          turn Battlewright on or off")
  print("  /bw reset             put the icon back in the middle")
end

-- /bw talents: what Battlewright knows about your build.
local function talents()
  local _, class = UnitClass("player")
  local classData = ns.Rotations[class]
  if not classData then return ns.print("no rotation for your class yet") end
  local t = ns.Talents.Refresh() or ns.Talents.Get()
  local s = ns.State.Read()
  local spec, how = ns.Spec.Detect(class, s and s.spells or {})
  ns.print("spec: %s (%s)", tostring(spec), how)
  local b = t.budget
  if b then
    ns.print("talent points: %d (%d unspent)%s%s", b.total, b.unspent,
      b.bonus > 0 and (", %d from the Legacy Talented perk"):format(b.bonus) or "",
      b.source == "currency" and "" or ", counted from your level")
  end
  local passive = {}
  for _, name in ipairs(classData.PASSIVE or {}) do passive[name] = true end
  local used, other, unknown = {}, {}, {}
  for _, e in ipairs(t.list) do
    if e.rank > 0 then
      if classData.USED and classData.USED[e.name] then
        used[#used + 1] = ("%s %d: %s"):format(e.name, e.rank, classData.USED[e.name])
      elseif passive[e.name] then
        other[#other + 1] = ("%s %d"):format(e.name, e.rank)
      else
        unknown[#unknown + 1] = e
      end
    end
  end
  if #used == 0 and #other == 0 and #unknown == 0 then return ns.print("no talent points spent") end
  for _, line in ipairs(used) do print("  |cff40ff40used|r  " .. line) end
  if #other > 0 then print("  |cffaaaaaano change to the rotation:|r " .. table.concat(other, ", ")) end
  for _, e in ipairs(unknown) do
    local desc = e.spellID and C_Spell and C_Spell.GetSpellDescription and select(2, pcall(C_Spell.GetSpellDescription, e.spellID))
    print(("  |cffff9900not used yet|r  %s %d%s"):format(e.name, e.rank,
      type(desc) == "string" and desc ~= "" and (": " .. desc) or ""))
  end
  if #unknown > 0 then ns.print("send these descriptions over to teach Battlewright what they do") end
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
  elseif cmd == "behind" then
    db.assumeBehind = not db.assumeBehind
    ns.print("assume you're behind the target (Backstab): %s", db.assumeBehind and "on" or "off")
  elseif cmd == "guide" then
    if arg == "rotation" or arg == "talents" then
      ns.db.guidePage = arg
      if not (ns.Guide.frame and ns.Guide.frame:IsShown()) then ns.Guide.Toggle() else ns.Guide.Refresh() end
    elseif arg == "solo" or arg == "group" then
      ns.db.guideMode = arg
      if not (ns.Guide.frame and ns.Guide.frame:IsShown()) then ns.Guide.Toggle() else ns.Guide.Refresh() end
    else
      ns.Guide.Toggle()
    end
  elseif cmd == "talents" then
    talents()
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
