#!/usr/bin/env python3
"""Battlewright tests: load the addons against a small mocked WoW API.

    pip install "lupa>=2.0"
    python tests/battlewright_test.py

Checks the Rogue priorities on hand-made states, reading state from the
mocked game (including a secret value), spec detection, the display, and
BattlewrightProbe's combat recorder with tools/probe_summary.py.
"""
from lupa import lua51
from pathlib import Path

R = Path(__file__).resolve().parent.parent
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
unpack = unpack or table.unpack
printed = {}
function print(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, " ") end
local function stub() return setmetatable({}, { __index = function(t) return function() return t end end }) end
local frames = {}
function CreateFrame()
  local f = stub()
  f.RegisterEvent = function(self, e)
    if not rawget(self, "events") then rawset(self, "events", {}); frames[#frames + 1] = self end
    self.events[e] = true
  end
  f.SetScript = function(self, k, fn) self["_" .. k] = fn end
  f.CreateTexture = function() local t = stub(); t.SetTexture = function(s, x) s.tex = x end; t.SetDesaturated = function(s, d) s.gray = d end; return t end
  f.CreateFontString = function() local t = stub(); t.SetText = function(s, x) s.text = x end; return t end
  f.Show = function(self) self.shown = true end
  f.Hide = function(self) self.shown = false end
  f.SetAlpha = function(self, a) self.alpha = a end
  f.GetPoint = function() return "CENTER", nil, "CENTER", 0, -160 end
  f.SetText = function(self, t) self.text = t; EXPORTTEXT = t end
  f.SetAlphaFromBoolean = function(self, v, a, b) self.fromBoolean = { v, a, b } end
  f.SetValue = function(self, v) self.value = v end
  f.SetShown = function(self, v) self.shown = v end
  return f
end
function fire(event, ...)
  for _, f in ipairs(frames) do
    local ev, fn = rawget(f, "events"), rawget(f, "_OnEvent")
    if ev and ev[event] and fn then fn(f, event, ...) end
  end
end
UIParent = stub()
function geterrorhandler() return function(e) error(e) end end
SlashCmdList = {}
Enum = { PowerType = { Energy = 3, ComboPoints = 4 } }
function UnitClass() return "Rogue", "ROGUE" end
-- The mocked game: edit GAME between checks.
GAME = { energy = 100, cp = 0, stealthed = false, combat = true, target = true, hp = 0.8,
  buffs = {}, debuffs = {}, known = { ["Sinister Strike"] = 45, ["Eviscerate"] = 35, ["Slice and Dice"] = 25 }, now = 100 }
function GetTime() return GAME.now end
function UnitPower(_, t) if t == 4 then return GAME.cp end return GAME.energySecret and SECRET or GAME.energy end
function UnitPowerMax() return 100 end
function IsStealthed() return GAME.stealthed end
function UnitAffectingCombat() return GAME.combat end
function UnitExists() return GAME.target end
function UnitCanAttack() return GAME.target end
function UnitHealth() return GAME.hpSecret and SECRET or GAME.hp * 1000 end
function UnitHealthMax() return 1000 end
function UnitClassification() return GAME.elite and "elite" or "normal" end
local ids = {}
C_Spell = {
  GetSpellInfo = function(name) if GAME.known[name] then ids[#ids + 1] = name; return { spellID = #ids } end end,
  GetSpellPowerCost = function(id) return { { cost = GAME.known[ids[id]] } } end,
  GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
  IsSpellUsable = function() if GAME.noPower then return false, true end return true, false end,
  GetSpellTexture = function(name) return "icon:" .. tostring(name) end,
  IsSpellInRange = function() return GAME.inRange ~= false end,
}
function UnitCastingInfo() if GAME.casting then return "Fireball", "", "", 0, 1, false, "id", GAME.casting == "uninterruptible", 133 end end
function UnitGUID() return GAME.guid end
function GetInventoryItemID(_, slot) if slot == 16 and GAME.mainHand then return 1 end end
C_Item = { GetItemInfoInstant = function() return 1, "Weapon", "", "INVTYPE_WEAPON", 0, 2, GAME.mainHand end }
C_UnitAuras = { GetPlayerAuraBySpellID = function() return GAME.sndAura end,
GetAuraDataByIndex = function(unit, i)
  if GAME.blocked then error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted") end
  local list = unit == "player" and GAME.buffs or GAME.debuffs
  local a = list[i]
  if a then return { name = a[1], expirationTime = a[2] } end
end }
''')

ns = L.table()
for line in (R / "Battlewright" / "Battlewright.toc").read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    path = R / "Battlewright" / line.replace("\\", "/")
    L.eval("function(src, name) return assert(loadstring(src, '@' .. name)) end")(path.read_text(), str(path))("Battlewright", ns)
L.globals().fire("ADDON_LOADED", "Battlewright")
L.globals().fire("PLAYER_LOGIN")


def show(**game):
    """Set the mocked game, forget cached spell IDs, and compute what to show."""
    for k, v in game.items():
        L.globals().GAME[k] = L.table_from(v, recursive=True) if isinstance(v, (dict, list)) else v
    L.globals().fire("SPELLS_CHANGED")
    view = L.eval("function(ns) return ns.Display.Compute() end")(ns)
    main = view["main"]
    return (main["spell"], round(main["wait"], 2)) if main else (None, view["message"])


# Combat, no combo points: build with Sinister Strike.
assert show() == ("Sinister Strike", 0), show()
# 2 combo points, no Slice and Dice: put it up.
assert show(cp=2) == ("Slice and Dice", 0), show(cp=2)
# Slice and Dice up for 10 s, 5 points: Eviscerate.
assert show(cp=5, buffs=[["Slice and Dice", 110]]) == ("Eviscerate", 0)
# ...about to fall off (1 s): refresh it first.
assert show(cp=5, buffs=[["Slice and Dice", 101]]) == ("Slice and Dice", 0)
# Not enough energy: still Sinister Strike, waiting 1.5 s at 10 energy/s.
assert show(cp=1, energy=30, buffs=[["Slice and Dice", 110]]) == ("Sinister Strike", 1.5), show()
# Target nearly dead (20%), 3 points: Eviscerate now rather than build to 5.
assert show(cp=3, energy=100, hp=0.2) == ("Eviscerate", 0)
# A hidden aura timer still counts as "Slice and Dice is up".
L.execute("SECRET = {}; function issecretvalue(v) return v == SECRET end")
L.execute("GAME.buffs = { { 'Slice and Dice', SECRET } }")
assert show(cp=5, hp=0.8) == ("Eviscerate", 0)
# Hidden combo points: say so instead of guessing.
L.execute("GAME.cp = SECRET")
assert show() == (None, "the game hides combat data from addons"), show()
L.execute("issecretvalue = nil; GAME.cp = 0; GAME.buffs = {}")
# No target: nothing to suggest.
assert show(target=False) == (None, None)
L.execute("GAME.target = true")

# Assassination (Mutilate known => talents say so): Mutilate builds; finish at 4.
mut = {"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25, "Mutilate": 60, "Rupture": 25, "Ambush": 60,
       "Garrote": 50, "Cheap Shot": 60}
assert L.eval("function(ns) return ns.Spec.Detect('ROGUE', { Mutilate = {} }) end")(ns) == ("assassination", "spells")
assert show(known=mut, cp=0, buffs=[["Slice and Dice", 130]]) == ("Mutilate", 0)
assert show(cp=4, hp=0.4) == ("Eviscerate", 0)  # 4 is full with Mutilate; under 50% hp, no Rupture
assert show(cp=4, hp=0.9) == ("Rupture", 0)     # long fight: Rupture first
# Health hidden in combat: Eviscerate on ordinary mobs, Rupture only on elites.
L.execute("SECRET = {}; function issecretvalue(v) return v == SECRET end")
assert show(cp=4, hpSecret=True) == ("Eviscerate", 0)
assert show(cp=4, hpSecret=True, elite=True) == ("Rupture", 0)
L.execute("issecretvalue = nil; GAME.hpSecret = false; GAME.elite = false")
# From stealth: Ambush needs a main-hand dagger; without one, Garrote.
assert show(stealthed=True, cp=0) == ("Garrote", 0)
L.execute("GAME.mainHand = 15"); L.globals().fire("PLAYER_EQUIPMENT_CHANGED")
assert show(stealthed=True, cp=0) == ("Ambush", 0)
L.execute("GAME.stealthed = false")
# /bw spec combat overrides the talents: Combat opens with Cheap Shot.
L.globals().SlashCmdList.BATTLEWRIGHT("spec combat")
assert show(stealthed=True) == ("Cheap Shot", 0)
L.globals().SlashCmdList.BATTLEWRIGHT("spec auto")
L.execute("GAME.stealthed = false")

# Talents (Forever's single Traits tree; the node's group says the spec):
# 21 points in Assassination with Improved Slice and Dice 3 and Forever's Venom.
L.execute("""
NODES = {
  { group = 11580, name = "Improved Slice and Dice", rank = 3 }, { group = 11580, name = "Malice", rank = 5 },
  { group = 11580, name = "Venom", rank = 1, spellID = 1310703 }, { group = 11580, name = "Lethality", rank = 12 },
  { group = 11573, name = "Precision", rank = 3 },
}
C_ClassTalents = { GetActiveConfigID = function() return 1 end }
C_Traits = {
  GetConfigInfo = function() return { treeIDs = { 1111 } } end,
  GetTreeNodes = function() local o = {} for i in ipairs(NODES) do o[i] = i end return o end,
  GetNodeInfo = function(_, id) local n = NODES[id] return { groupIDs = { n.group }, activeRank = n.rank, entryIDs = { id }, maxRanks = 5 } end,
  GetEntryInfo = function(_, id) return { definitionID = id } end,
  GetDefinitionInfo = function(id) return { overrideName = NODES[id].name, spellID = NODES[id].spellID } end,
}
C_Spell.GetSpellDescription = function(id) if id == 1310703 then return "Your finishing moves poison the target." end end
""")
L.globals().fire("PLAYER_TALENT_UPDATE")
L.globals().SlashCmdList.BATTLEWRIGHT("spec auto")
assert L.eval("function(ns) return ns.Spec.Detect('ROGUE', {}) end")(ns) == ("assassination", "talents")
# Improved Slice and Dice 3: a 2-point Slice and Dice lasts 12 x 1.45 = 17.4 s.
show(known=mut, cp=2, buffs=[], stealthed=False)
snd_id = L.eval("function(ns) return ns.Display.Compute().state.spells['Slice and Dice'].id end")(ns)
L.execute("GAME.blocked = true")
show()
L.globals().fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", snd_id)
assert abs(L.eval("function(ns) return ns.Tracker.expires['Slice and Dice'] end")(ns) - 117.4) < 1e-9
L.execute("GAME.blocked = false"); L.eval("function(ns) ns.Tracker.expires = {} end")(ns)
# /bw talents: what the rotation uses, what doesn't change it, and Forever talents it doesn't know yet.
L.execute("printed = {}")
L.globals().SlashCmdList.BATTLEWRIGHT("talents")
out = "\n".join(L.globals().printed.values())
print(out)
assert "spec: assassination (talents)" in out and "Improved Slice and Dice 3: Slice and Dice lasts 15% longer" in out, out
assert "no change to the rotation:|r Malice 5, Lethality 12" in out or "Malice 5" in out, out
assert "not used yet|r  Venom 1: Your finishing moves poison the target." in out, out
# Backstab: with a dagger and /bw behind, for a Combat Rogue (no Mutilate).
L.globals().SlashCmdList.BATTLEWRIGHT("spec combat")
assert show(known={"Sinister Strike": 45, "Backstab": 60, "Eviscerate": 35, "Slice and Dice": 25}, cp=0,
            buffs=[["Slice and Dice", 130]]) == ("Sinister Strike", 0)
L.globals().SlashCmdList.BATTLEWRIGHT("behind")
assert show() == ("Backstab", 0)
L.globals().SlashCmdList.BATTLEWRIGHT("behind")
# Premeditation in stealth: suggested as a cooldown before the opener.
L.globals().SlashCmdList.BATTLEWRIGHT("spec subtlety")
pre = L.eval("""function(ns) GAME.stealthed = true
  GAME.known = { ["Premeditation"] = 0, ["Ambush"] = 60, ["Sinister Strike"] = 45 }
  fire("SPELLS_CHANGED") local v = ns.Display.Compute() GAME.stealthed = false
  return v.main.spell, v.cooldown and v.cooldown.spell end""")(ns)
assert tuple(pre) == ("Ambush", "Premeditation"), tuple(pre)
L.globals().SlashCmdList.BATTLEWRIGHT("spec auto")
L.execute("C_ClassTalents, C_Traits = nil, nil; GAME.mainHand = nil")
L.eval("function(ns) ns.Talents.Clear() end")(ns)
L.globals().fire("PLAYER_EQUIPMENT_CHANGED")

# The display: shown in combat with the spell's icon and why; hidden (alpha 0)
# out of combat while locked.
L.eval("function(ns) ns.Display.Update() end")(ns)
f = L.eval("function(ns) return ns.Display.frame end")(ns)
assert f.alpha == 1 and f.icon.tex.startswith("icon:") and ":" in f.why.text, (f.alpha, f.icon.tex, f.why.text)
L.execute("GAME.combat = false")
L.eval("function(ns) ns.Display.Update() end")(ns)
assert f.alpha == 0

# Forever in combat (BattlewrightProbe, 2026-10-03): energy and target health
# secret, auras blocked. Slice and Dice is tracked from our own cast instead,
# with its duration from the combo points spent (2 points: 12 s).
L.execute("""SECRET = {}; function issecretvalue(v) return v == SECRET end
GAME.energySecret, GAME.hpSecret, GAME.blocked = true, true, true""")
std = {"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25}
assert show(known=std, cp=2, buffs=[], debuffs=[]) == ("Slice and Dice", 0)
snd = L.eval("function(ns) return ns.Display.Compute().state.spells['Slice and Dice'].id end")(ns)
est = L.eval("function(ns) return ns.Display.Compute().state.estimated end")(ns)
assert est is True
L.globals().fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", snd)
L.execute("GAME.cp = 5")
assert L.eval("function(ns) return ns.Tracker.expires['Slice and Dice'] end")(ns) == 112  # 100 + 12 s
assert show(cp=5) == ("Eviscerate", 0)                  # Slice and Dice has 12 s left
assert show(now=111) == ("Slice and Dice", 0)            # 1 s left: refresh
# Not enough energy: the game says so even though energy is hidden; no countdown.
view = L.eval("function(ns) GAME.noPower = true; GAME.cp = 0; GAME.now = 105 return ns.Display.Compute().main end")(ns)
assert view["spell"] == "Sinister Strike" and view["short"] is True and view["wait"] is None, dict(view.items())
L.execute("""GAME.noPower, GAME.energySecret, GAME.hpSecret, GAME.blocked = false, false, false, false
GAME.now, GAME.cp = 100, 0; issecretvalue = nil""")
L.eval("function(ns) ns.Tracker.expires = {} end")(ns)

# Round 2 (2026-10-03): the target's casts, range and GUID are readable in combat.
L.execute("SECRET = {}; function issecretvalue(v) return v == SECRET end; GAME.blocked = true; GAME.energySecret = true")
kit = {"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25, "Rupture": 25, "Kick": 25}
def full():
    return L.eval("function(ns) local v = ns.Display.Compute() return v.main and v.main.spell, v.cooldown and v.cooldown.spell, v.main and v.main.outOfRange end")(ns)
show(known=kit, cp=0)
# Kick: suggested (big) when the target casts something interruptible; not for an uninterruptible cast.
L.execute("GAME.casting = 'yes'")
assert tuple(full())[:2] == ("Sinister Strike", "Kick"), tuple(full())
L.execute("GAME.casting = 'uninterruptible'")
assert tuple(full())[1] is None
# In combat the cast's details are secret, but a cast is still going on: Kick.
L.execute("function UnitCastingInfo() if GAME.casting then return SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET end end; GAME.casting = 'secret'")
assert tuple(full())[1] == "Kick", tuple(full())
# The Kick icon hands the secret "not interruptible" flag to the widget (alpha 0
# when it can't be interrupted), and the energy bar is fed secret energy as is.
kick = L.eval("""function(ns) GAME.combat = true ns.Display.Update() local f = ns.Display.frame
  local fb = rawget(f.cd, "fromBoolean") or {}
  return fb[1] == SECRET, fb[2], fb[3], rawget(f.energy, "value") == SECRET end""")(ns)
assert tuple(kick) == (True, 0, 1, True), tuple(kick)
L.execute("GAME.casting = nil; GAME.inRange = false")
# Out of melee range: the icon says so.

assert tuple(full()) == ("Sinister Strike", None, True), tuple(full())
L.execute("GAME.inRange = nil")
# Rupture is tracked per target: casting it on mob A doesn't count for mob B.
L.globals().SlashCmdList.BATTLEWRIGHT("spec subtlety")
L.execute("GAME.guid = 'Creature-A'")
show(cp=5)
rup = L.eval("function(ns) return ns.Display.Compute().state.spells['Rupture'].id end")(ns)
L.globals().fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-r", rup)
assert L.eval("function(ns) return ns.Display.Compute().state.debuffs.Rupture ~= nil end")(ns) is True
L.execute("GAME.guid = 'Creature-B'"); L.globals().fire("PLAYER_TARGET_CHANGED")
assert L.eval("function(ns) return ns.Display.Compute().state.debuffs.Rupture end")(ns) is None
L.execute("GAME.guid = 'Creature-A'")
assert L.eval("function(ns) return ns.Display.Compute().state.debuffs.Rupture ~= nil end")(ns) is True
# A lookup by spell ID that answers beats the estimate.
L.execute("GAME.sndAura = { expirationTime = 130 }")
assert L.eval("function(ns) return ns.Display.Compute().state.buffs['Slice and Dice'] end")(ns) == 30
L.globals().SlashCmdList.BATTLEWRIGHT("spec auto")
L.execute("GAME.sndAura = nil; GAME.blocked = false; GAME.energySecret = false; GAME.guid = nil; issecretvalue = nil")
L.eval("function(ns) ns.Tracker.expires = {} end")(ns)

# BattlewrightProbe ------------------------------------------------------------------
# /bwp combat records the next fight: twice a second for up to 30 s, which calls
# come back readable or secret. Here aura timers are secret.
import json, subprocess, sys, tempfile
L.execute("""
C_Timer = { After = function(_, fn) fn() end }
function date() return "2026-10-04 12:00:00" end
UISpecialFrames, ChatFontNormal = {}, {}
tinsert = table.insert
SECRET = {}
function issecretvalue(v) return v == SECRET end
function GetComboPoints() return 3 end
GAME.cp, GAME.energy, GAME.buffs = 3, 80, { { "Slice and Dice", SECRET } }
""")
for line in (R / "BattlewrightProbe" / "BattlewrightProbe.toc").read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#"):
        path = R / "BattlewrightProbe" / line
        L.eval("function(src, name) return assert(loadstring(src, '@' .. name)) end")(path.read_text(), str(path))("BattlewrightProbe", L.table())
L.execute("printed = {}")
L.globals().SlashCmdList.BATTLEWRIGHTPROBE("combat")
L.globals().fire("PLAYER_REGEN_DISABLED"); L.globals().fire("PLAYER_REGEN_ENABLED")
run = L.eval("""function() local r = BattlewrightProbeDB.runs[1]
  return r.samples, r["UnitPower(energy)"].readable, r["aura expirationTime"].secret > 0, r.known["Sinister Strike"] ~= nil end""")()
assert tuple(run) == (60, 60, True, True), tuple(run)
out = "\n".join(L.globals().printed.values())
assert "SECRET: aura expirationTime" in out, out
# The game blocking a call: the probe records which function it was.
L.globals().fire("ADDON_ACTION_FORBIDDEN", "BattlewrightProbe", "SomeProtectedFunction()")
assert L.eval("function() return BattlewrightProbeDB.blocked['SomeProtectedFunction()'].count end")() == 1
L.globals().SlashCmdList.BATTLEWRIGHTPROBE("export")
export = Path(tempfile.mkdtemp()) / "export.json"
export.write_text(L.globals().EXPORTTEXT)
assert json.loads(export.read_text())["runs"][0]["samples"] == 60
r = subprocess.run([sys.executable, str(R / "tools" / "probe_summary.py"), str(export)], capture_output=True, text=True)
assert "BLOCKED by the game: SomeProtectedFunction() x1 (ADDON_ACTION_FORBIDDEN" in r.stdout, r.stdout
assert r.returncode == 0 and "aura expirationTime: SECRET" in r.stdout and "hidden in combat: aura expirationTime" in r.stdout, r.stdout + r.stderr
print(r.stdout)
print("BATTLEWRIGHT TESTS PASSED")
