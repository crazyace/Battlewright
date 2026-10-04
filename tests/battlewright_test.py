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
  f.IsShown = function(self) return self.shown == true end
  f.SetPoint = function(self, ...) self.point = { ... } end
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
function UnitLevel() return GAME.level or 19 end
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
  { group = 11580, name = "Venom", rank = 1, spellID = 1310703 }, { group = 11580, name = "Shadow Trick", rank = 1, spellID = 999001 }, { group = 11580, name = "Lethality", rank = 12 },
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
C_Spell.GetSpellDescription = function(id) if id == 999001 then return "Something new." end end
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
assert "used|r  Venom 1: finisher kept up" in out, out
assert "not used yet|r  Shadow Trick 1: Something new." in out, out
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
# Talents are matched by node or spell ID (from talentsforever.com's data), so a
# talent the game renames keeps its name and spec: node 108100 is Flawless
# Execution even when the game calls it Restless Blades and its group is unknown.
L.execute("""
NODES[7] = { group = 99999, name = "Restless Blades", rank = 1, nodeID = 108100 }
local getNodes = C_Traits.GetTreeNodes
C_Traits.GetTreeNodes = function(tree) if tree == 1111 then local o = getNodes() o[#o] = 108100 return o end end
local getNode = C_Traits.GetNodeInfo
C_Traits.GetNodeInfo = function(c, id) if id == 108100 then return getNode(c, 7) end return getNode(c, id) end
""")
t = L.eval("""function(ns) local t = ns.Talents.Refresh()
  return t.ranks["Flawless Execution"], t.ranks["Restless Blades"], t.points[2], t.budget.total, t.budget.source end""")(ns)
assert tuple(t) == (1, None, 4, 10, "level"), tuple(t)
# Talent points: the Legacy Talented perk (tree 1188) adds a point per rank
# when the game gives no count: level 19 with Talented 3 is 13 points.
L.execute("""
C_Traits.GetConfigInfo = function(id) return { treeIDs = id == 2 and { 1188 } or { 1111 } } end
C_Traits.GetConfigIDBySystemID = function(sys) return sys == 3 and 2 or nil end
local getNodes2, getNode2, getDef = C_Traits.GetTreeNodes, C_Traits.GetNodeInfo, C_Traits.GetDefinitionInfo
C_Traits.GetTreeNodes = function(tree) if tree == 1188 then return { 500 } end return getNodes2(tree) end
C_Traits.GetNodeInfo = function(c, id) if id == 500 then return { activeRank = 3, entryIDs = { 500 } } end return getNode2(c, id) end
C_Traits.GetDefinitionInfo = function(id) if id == 500 then return { spellID = 1225474 } end return getDef(id) end
""")
b = L.eval("function(ns) local b = ns.Talents.Refresh().budget return b.total, b.bonus, b.source end")(ns)
assert tuple(b) == (13, 3, "level"), tuple(b)
# The game's own count wins: 2 unspent and 22 spent at level 19.
L.execute("C_Traits.GetTreeCurrencyInfo = function(_, tree) if tree == 1111 then return { { quantity = 2, spent = 22 } } end end")
b = L.eval("function(ns) local b = ns.Talents.Refresh().budget return b.total, b.unspent, b.bonus, b.source end")(ns)
assert tuple(b) == (24, 2, 14, "currency"), tuple(b)
L.execute("printed = {}")
L.globals().SlashCmdList.BATTLEWRIGHT("talents")
out = "\n".join(L.globals().printed.values())
assert "talent points: 24 (2 unspent), 14 from the Legacy Talented perk" in out, out
L.execute("C_Traits.GetTreeCurrencyInfo, C_Traits.GetConfigIDBySystemID = nil, nil")
# Every talent the rotation and builds name is on the ID list (or a rename breaks it).
missing = L.eval("""function(ns) local R, have, miss = ns.Rotations.ROGUE, {}, {}
  for _, t in ipairs(R.TALENTS) do have[t.name] = true end
  for name in pairs(R.USED) do if not have[name] then miss[#miss + 1] = name end end
  for _, name in ipairs(R.PASSIVE) do if not have[name] then miss[#miss + 1] = name end end
  for _, b in pairs(R.BUILDS) do for _, name in ipairs(b.order) do if not have[name] then miss[#miss + 1] = name end end end
  return table.concat(miss, ", ") end""")(ns)
assert missing == "", missing
# A plan with 3 bonus points: the build's points come 3 levels sooner (never
# before 10), and all 13 are unspent at level 19.
plan = L.eval("""function(ns) local R = ns.Rotations.ROGUE
  local p = R.TalentPlan({ talents = {}, talentBudget = { total = 13, bonus = 3, source = "level" } }, R.BUILDS.mutilate, 19)
  return p.unspent, p.upcoming[1].name, p.upcoming[1].from, p.upcoming[1].to, p.upcoming[2].from end""")(ns)
assert tuple(plan) == (13, "Malice", 10, 11, 12), tuple(plan)
L.globals().SlashCmdList.BATTLEWRIGHT("spec auto")
L.execute("C_ClassTalents, C_Traits = nil, nil; GAME.mainHand = nil")
L.eval("function(ns) ns.Talents.Clear() end")(ns)
L.globals().fire("PLAYER_EQUIPMENT_CHANGED")

# /bw guide: the rotation written out for what you have. A dagger Assassination
# Rogue at 19 with Eureka! and Gouge, no Mutilate yet.
L.globals().SlashCmdList.BATTLEWRIGHT("spec assassination")
show(known={"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25, "Backstab": 60, "Ambush": 60,
            "Garrote": 50, "Gouge": 45, "Kick": 25, "Eureka!": 0, "Evasion": 0}, cp=0, combat=False)
L.execute("GAME.mainHand = 15"); L.globals().fire("PLAYER_EQUIPMENT_CHANGED")
# Sassy's talents: Remorseless Attacks 2 (chain pulls), Ruthlessness 3.
L.eval("""function(ns) ns._get = ns.Talents.Get
  ns.Talents.Get = function() return { ranks = { ["Remorseless Attacks"] = 2, ["Ruthlessness"] = 3, ["Malice"] = 5 },
    spellIDs = { ["Remorseless Attacks"] = 14144 }, points = { 10 }, list = {} } end end""")(ns)
L.globals().SlashCmdList.BATTLEWRIGHT("guide")
guide = L.eval("""function(ns) local out = {}
  for _, sec in ipairs(ns.Guide.sections) do
    out[#out + 1] = "# " .. sec.title
    for _, r in ipairs(sec.rows) do out[#out + 1] = r.text end
  end
  return table.concat(out, "\\n") end""")(ns)
print(guide)
for want in ["# From stealth", "Ambush, from behind", "Kick the moment the target casts",
             "Gouge, step behind, Backstab while it holds", "Eviscerate at 5 combo points",
             "Eureka! at 3 combo points", "Main hand: a dagger", "Off hand: empty",
             "Level 20: Rupture", "Level 22: Vanish", "20 points in Assassination: Mutilate",
             "Ambush or Mutilate +40% crit for 20 s. Pull the next mob inside those 20 s and open with Ambush",
             "Why: +20% attack speed on both weapons for 25 energy", "Skip it on a mob that's about to die",
             "Remorseless Attacks 2: +40% crit on the first hit after a kill"]:
    assert want in guide, want
# Priority order matches the rotation: Kick, Gouge, Slice and Dice, Eviscerate, builders.
order = [guide.index(x) for x in ["Kick the moment", "Gouge, step behind", "Slice and Dice when", "Eviscerate at", "Backstab when", "Sinister Strike to build"]]
assert order == sorted(order), order
# The rotation path at the top: one typical fight as icons.
path_text = """function(ns) local out = {}
  for _, lane in ipairs(ns.Guide.path) do
    local steps = {}
    for _, st in ipairs(lane.steps) do
      steps[#steps + 1] = st.text or (st.spell .. (st.count and ("x" .. st.count) or "") .. (st.note and ("(" .. st.note .. ")") or ""))
    end
    out[#out + 1] = lane.label .. ": " .. table.concat(steps, " > ")
  end
  return table.concat(out, " | ") end"""
path = L.eval(path_text)(ns)
print(path)
assert "From stealth: Ambush(behind)" in path, path
# Eureka! at 3 combo points: 3 Sinister Strikes, Eureka!, 2 more, Eviscerate at 5.
assert "Each cycle: Slice and Dice(1-2 pts) > Sinister Strikex3 > Eureka!(at 3 pts) > Sinister Strikex2 > Eviscerate(at 5) > repeat" in path, path
assert "After a kill: Remorseless Attacks(kill) > next pull, 20 s > Ambush(+40% crit)" in path, path
assert "Mob casts: Kick(any time)" in path and "Gouge trick: Gouge(front) > step behind > Backstab(4 s window)" in path, path
assert "Behind (groups): Backstab(replaces SS)x5" in path or "Behind (groups): Backstabx5(replaces SS)" in path, path
cells = L.eval("function(ns) local n = 0 for _, c in ipairs(ns.Guide.frame.cells) do if c.icon.tex then n = n + 1 end end return n end")(ns)
assert cells == 13, cells  # Ambush; Remorseless, Ambush; SnD, SS, Eureka!, SS, Eviscerate; Kick; Gouge, Backstab; Backstab, Eviscerate
# The window drew a line per row, with the spell's icon.
lines = L.eval("function(ns) local n = 0 for _, l in ipairs(ns.Guide.frame.lines) do if l.text.text then n = n + 1 end end return n end")(ns)
assert lines >= 15, lines
# Talent builds: every order is legal on Forever's tree (rows need 5 points per
# row in that tree; prerequisites need the full source talent; max ranks; 21
# points at 30). Tree from /bwp book, 2026-10-03.
TREE = {  # name: (tree, row, max ranks, prerequisite)
  "Improved Gouge": ("A", 1, 3, None), "Remorseless Attacks": ("A", 1, 2, None), "Malice": ("A", 1, 5, None),
  "Ruthlessness": ("A", 2, 3, None), "Murder": ("A", 2, 2, None), "Improved Slice and Dice": ("A", 2, 3, None),
  "Relentless Strikes": ("A", 3, 1, None), "Improved Expose Armor": ("A", 3, 2, None), "Lethality": ("A", 3, 5, "Malice"),
  "Vile Poisons": ("A", 4, 5, None), "Cold Blood": ("A", 4, 1, None), "Improved Poisons": ("A", 4, 5, None),
  "Vigor": ("A", 5, 2, None), "Mutilate": ("A", 5, 1, None), "Improved Kidney Shot": ("A", 5, 2, None),
  "Improved Eviscerate": ("C", 1, 3, None), "Improved Sinister Strike": ("C", 1, 2, None), "Lightning Reflexes": ("C", 1, 5, None),
  "Puncturing Wounds": ("C", 2, 3, None), "Deflection": ("C", 2, 3, None), "Precision": ("C", 2, 3, None),
  "Endurance": ("C", 3, 2, None), "Riposte": ("C", 3, 1, "Deflection"), "Improved Sprint": ("C", 3, 2, None),
  "Improved Kick": ("C", 4, 2, None), "Flawless Execution": ("C", 4, 1, None), "Dual Wield Specialization": ("C", 4, 5, "Precision"),
  "Blade Flurry": ("C", 5, 1, None), "Hack and Slash": ("C", 5, 5, None),
}
builds = L.eval("function(ns) return ns.Rotations.ROGUE.BUILDS end")(ns)
for key in ["mutilate", "backstab", "combat"]:
    order = list(builds[key].order.values())
    assert len(order) == 21, (key, len(order))
    ranks, spent = {}, {"A": 0, "C": 0, "S": 0}
    for i, name in enumerate(order):
        tree, row, mx, pre = TREE[name]
        assert spent[tree] >= 5 * (row - 1), (key, i, name, "row gate")
        assert pre is None or ranks.get(pre, 0) == TREE[pre][2], (key, name, "needs", pre)
        ranks[name] = ranks.get(name, 0) + 1
        assert ranks[name] <= mx, (key, name, "max rank")
        spent[tree] += 1

# A plan with points off the build and some unspent: Improved Gouge 2 and
# Malice 3 at level 19 (10 points, 5 spent).
plan = L.eval("""function(ns) local R = ns.Rotations.ROGUE
  local p = R.TalentPlan({ talents = { ["Improved Gouge"] = 2, ["Malice"] = 3 } }, R.BUILDS.mutilate, 19)
  return p.next.name, p.next.now, p.points, p.spent, p.offPlan[1] end""")(ns)
assert tuple(plan) == ("Malice", True, 10, 5, "Improved Gouge 2"), tuple(plan)

# The Talents page: Sassy (level 19, Malice 5, Remorseless Attacks 2, Ruthlessness 3,
# a dagger, solo) gets the Mutilate build, on track, Lethality next. The build
# text isn't on the Rotation page any more.
assert "Lethality crits and Mutilate at 30" not in guide
talents_text = """function(ns) local out = {} for _, r in ipairs(ns.Guide.talents.rows) do out[#out + 1] = r.text end
  return table.concat(out, "\\n") end"""
L.globals().SlashCmdList.BATTLEWRIGHT("guide talents")
assert L.eval("function(ns) return ns.Guide.page end")(ns) == "talents"
ttext = L.eval(talents_text)(ns)
for want in ["Assassination: Mutilate: Ambush openers, Lethality crits and Mutilate at 30.",
             "Your points match this build. Next: Lethality at level 20.", "Levels 20-24: Lethality 5",
             "Level 25: Relentless Strikes 1", "Level 26: Cold Blood 1", "Levels 27-29: Improved Slice and Dice 3",
             "Level 30: Mutilate 1", "Also good: Combat: sturdy, if you'd rather not die (equip an off-hand weapon"]:
    assert want in ttext, want
assert "Not in this build" not in ttext
# Solo shows only the solo builds: no group Backstab build button.
shown = L.eval("""function(ns) local out = {} for _, b in ipairs(ns.Guide.frame.builds) do
  if b.shown then out[#out + 1] = b.name.text end end return table.concat(out, ", ") end""")(ns)
assert shown == "Assassination: Mutilate, Combat: sturdy", shown
# A group build chosen while on Solo isn't shown.
L.eval("function(ns) ns.Guide.SetBuild('backstab') end")(ns)
assert L.eval("function(ns) return ns.Guide.talents.key end")(ns) == "mutilate"
# Pick another build: the plan follows it and names the best fit.
L.eval("function(ns) ns.Guide.SetBuild('combat') end")(ns)
ttext = L.eval(talents_text)(ns)
assert ttext.startswith("Combat: sturdy: if you'd rather not die") and "Best fit for you: Assassination: Mutilate" in ttext, ttext
assert "Not in this build: Malice 5, Remorseless Attacks 2, Ruthlessness 3" in ttext, ttext
# The tree: drawn from the nodes' positions, as if the build's points were spent.
L.eval("""function(ns) local get = ns.Talents.Get
  ns._sassy = get
  ns.Talents.Get = function() local r = get()
    r.ranks = { ["Malice"] = 5, ["Improved Gouge"] = 2 }
    r.list = {
      { name = "Malice", rank = 5, max = 5, tab = 1, spellID = 14138, posX = 2220, posY = 2130 },
      { name = "Improved Gouge", rank = 2, max = 3, tab = 1, spellID = 13741, posX = 1020, posY = 2130 },
      { name = "Lethality", rank = 0, max = 5, tab = 1, spellID = 14128, posX = 2220, posY = 3330 },
      { name = "Mutilate", rank = 0, max = 1, tab = 1, spellID = 1310707, posX = 1620, posY = 4530 },
      { name = "Puncturing Wounds", rank = 0, max = 3, tab = 2, spellID = 1224716, posX = 5020, posY = 2730 },
      { name = "Camouflage", rank = 0, max = 5, tab = 3, spellID = 13975, posX = 9080, posY = 2130 },
    }
    return r end
  ns.Guide.SetBuild(nil) end""")(ns)
nodes = L.eval("""function(ns) local out = {}
  for _, n in ipairs(ns.Guide.frame.nodes) do
    if n.shown ~= false then out[n.name] = n.status .. " " .. (n.rank.text or "") .. (n.icon.gray and " grey" or "") end
  end
  return out end""")(ns)
nodes = dict(nodes.items())
# The build's talents are lit with the build's ranks, whatever you have (no Lethality
# yet, still 5/5); talents not in it are greyed at 0, even your Improved Gouge 2.
assert nodes["Malice"] == "build 5/5" and nodes["Improved Gouge"] == "none 0/3 grey", nodes
assert nodes["Lethality"] == "build 5/5" and nodes["Mutilate"] == "build 1/1", nodes
assert nodes["Puncturing Wounds"] == "none 0/3 grey" and nodes["Camouflage"] == "none 0/5 grey", nodes
heads = L.eval("function(ns) local o = {} for i, h in ipairs(ns.Guide.frame.trees) do o[i] = h.text end return o end")(ns)
# Each tree's heading: the build's points in it (of the talents drawn: Malice 5, Lethality 5, Mutilate 1).
assert list(heads.values()) == ["Assassination  11", "Combat  0", "Subtlety  0"], list(heads.values())
# Another build: your Malice isn't in it, so it's greyed at 0, nothing red.
L.eval("function(ns) ns.Guide.SetBuild('combat') end")(ns)
other = dict(L.eval("""function(ns) local out = {} for _, n in ipairs(ns.Guide.frame.nodes) do
  if n.shown ~= false then out[n.name] = n.status .. (n.icon.gray and " grey" or "") end end return out end""")(ns).items())
assert other["Malice"] == "none grey" and other["Lethality"] == "none grey", other
assert other["Puncturing Wounds"] == "none grey", other
L.eval("function(ns) ns.Guide.SetBuild(nil) end")(ns)
# The subtitle is short enough to clear the tabs.
assert L.eval("function(ns) return ns.Guide.frame.subtitle.text end")(ns) == "Assassination  -  level 19"
# The tooltip line says what the build takes.
line = L.eval("function(ns) for _, n in ipairs(ns.Guide.frame.nodes) do if n.name == 'Lethality' then return n.line end end end")(ns)
assert line == "In this build: 5 of 5 ranks", line
# Layout: the build buttons, the tree and the cards under it don't overlap
# (in game the cards were drawn over the tree).
lay = L.eval("""function(ns) local f = ns.Guide.frame
  local lowestNode, buttonBottom, legendTop = 0, 0, nil
  for _, n in ipairs(f.nodes) do if n.shown then lowestNode = math.min(lowestNode, n.point[5] - 38) end end
  buttonBottom = f.builds[1].point[5] - 48
  local topNode
  for _, n in ipairs(f.nodes) do if n.shown then topNode = math.max(topNode or -math.huge, n.point[5]) end end
  for _, c in ipairs(f.lines) do
    if c.text.text and c.text.text:find("^The tree as this build fills it") then legendTop = c.card.point[5] end
  end
  return lowestNode, buttonBottom, legendTop, topNode end""")(ns)
lowest, buttons, legend, top_node = lay
assert legend is not None and legend <= lowest - 2, lay
assert top_node < buttons, lay
L.eval("function(ns) ns.Talents.Get = ns._sassy end")(ns)
L.eval("function(ns) ns.Guide.SetBuild(nil) ns.Guide.SetPage('rotation') end")(ns)

# Group mode (/bw guide group): Backstab is the builder, Rupture on bosses,
# Feint for threat, the tank pulls first; no Gouge trick or chain pulling.
assert L.eval("function(ns) return ns.Guide.mode end")(ns) == "solo"
show(known={"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25, "Backstab": 60, "Ambush": 60,
            "Garrote": 50, "Gouge": 45, "Kick": 25, "Eureka!": 0, "Evasion": 0, "Rupture": 25, "Feint": 20,
            "Expose Armor": 25, "Vanish": 0}, cp=0, combat=False)
L.globals().SlashCmdList.BATTLEWRIGHT("guide group")
assert L.eval("function(ns) return ns.Guide.mode, ns.db.guideMode end")(ns) == ("group", "group")
gpath = L.eval(path_text)(ns)
print(gpath)
assert "From stealth: tank pulls > Ambush(behind)" in gpath, gpath
assert "Each cycle: Slice and Dice(1-2 pts) > Backstabx3 > Eureka!(at 3 pts) > Backstabx2 > Eviscerate(at 5) > repeat" in gpath, gpath
assert "Bosses: Backstabx5 > Rupture(at 5) > Backstabx5 > Eviscerate(at 5)" in gpath, gpath
assert "Threat: Feint(when ready)" in gpath, gpath
assert "Gouge trick" not in gpath and "After a kill" not in gpath and "Behind (groups)" not in gpath, gpath
gtext = L.eval("""function(ns) local out = {} for _, sec in ipairs(ns.Guide.sections) do
  for _, r in ipairs(sec.rows) do out[#out + 1] = r.text end end return table.concat(out, "\\n") end""")(ns)
for want in ["Let the tank pull and hold the mob first", "Backstab is your builder: stand behind the mob",
             "Sinister Strike only when you can't get behind", "Rupture at 5 on bosses and long fights",
             "Expose Armor on bosses only when no warrior is using Sunder Armor", "Feint whenever it's ready",
             "Evasion if the mob turns on you", "Vanish to drop all threat", "it matters less in groups"]:
    assert want in gtext, want
assert "Gouge, step behind" not in gtext and "Pull the next mob inside" not in gtext, gtext
# Group with a dagger: the Backstab build. Sassy's points are all in it (a different
# order), so nothing is off-plan; its early Combat points are due now.
L.eval("function(ns) ns.Guide.SetPage('talents') end")(ns)
gt = L.eval(talents_text)(ns)
L.eval("function(ns) ns.Guide.SetPage('rotation') end")(ns)
for want in ["Backstab (dagger, groups): you have a dagger in your main hand", "Due now: Improved Eviscerate 3",
             "Due now: Puncturing Wounds 3", "Your next point (level 20): Improved Eviscerate.",
             "Also good: Assassination: Mutilate, if you also play solo"]:
    assert want in gt, want
assert "Not in this build" not in gt
# Back to Solo with the tab.
L.eval("function(ns) ns.Guide.SetMode('solo') end")(ns)
assert L.eval("function(ns) return ns.Guide.mode end")(ns) == "solo"
assert "Gouge trick" in L.eval(path_text)(ns)
L.eval("function(ns) ns.db.guideMode = false end")(ns)

# A build picked on the Talents page drives the Rotation page: Sassy's 10 points
# as Combat play as Combat, with a line saying it's a preview.
rot_text = """function(ns) local out = {} for _, sec in ipairs(ns.Guide.sections) do
  for _, r in ipairs(sec.rows) do out[#out + 1] = r.text end end return table.concat(out, "\\n") end"""
L.eval("function(ns) ns.Guide.SetBuild('combat') end")(ns)
ptext = L.eval(rot_text)(ns)
assert L.eval("function(ns) return ns.Guide.frame.subtitle.text end")(ns) == "Combat  -  level 19"
assert ptext.startswith("Previewing Combat: sturdy with your 10 talent points"), ptext
assert "Your own talents play as Assassination" in ptext and "Spec: Combat" in ptext, ptext
# The build you follow (Malice 5, Ruthlessness 3, Remorseless Attacks 2 = Mutilate's
# first 10 points): your own talents, no preview. Nothing picked: the same.
for key in ["'mutilate'", "nil"]:
    L.eval(f"function(ns) ns.Guide.SetBuild({key}) end")(ns)
    assert "Previewing" not in L.eval(rot_text)(ns), key
    assert L.eval("function(ns) return ns.Guide.frame.subtitle.text end")(ns) == "Assassination  -  level 19"
# The preview teaches the build's spells and drops the ones it doesn't take; the
# in-combat state is untouched.
pv = L.eval("""function(ns) local R = ns.Rotations.ROGUE
  local s = { spells = { Mutilate = { id = 1 }, ["Sinister Strike"] = { id = 2 } }, talents = { Mutilate = 1 } }
  local p, spec = R.Preview(s, R.BUILDS.combat, 21)
  return spec, p.spells["Blade Flurry"] ~= nil, p.spells.Mutilate == nil, p.spells["Sinister Strike"] ~= nil,
    s.spells.Mutilate ~= nil, s.talents.Mutilate, p.talents["Blade Flurry"] end""")(ns)
assert tuple(pv) == ("combat", True, True, True, True, 1, 1), tuple(pv)

# With a sword and Mutilate: no Ambush/Backstab, finish at 4, Eureka! at 0+... (4 - 2x2 = 0).
L.execute("GAME.mainHand = 7"); L.globals().fire("PLAYER_EQUIPMENT_CHANGED")
show(known={"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25, "Mutilate": 60, "Gouge": 45, "Cold Blood": 0,
            "Eureka!": 0})
L.eval("function(ns) ns.Guide.Refresh() end")(ns)
guide2 = L.eval("""function(ns) local out = {} for _, sec in ipairs(ns.Guide.sections) do
  for _, r in ipairs(sec.rows) do out[#out + 1] = r.text end end return table.concat(out, "\\n") end""")(ns)
assert "Main hand: a sword" in guide2 and "Ambush, from behind" not in guide2, guide2
assert "Eviscerate at 4 combo points" in guide2 and "Gouge, step behind, Mutilate" in guide2, guide2
assert "Cold Blood right before a 4-point Eviscerate" in guide2, guide2
# With Mutilate: Eureka! first (its charges: Mutilate, Mutilate, Eviscerate), Cold Blood before the finisher.
path2 = L.eval(path_text)(ns)
assert "Each cycle: Slice and Dice(1-2 pts) > Eureka!(first) > Mutilatex2 > Cold Blood(crit) > Eviscerate(at 4) > repeat" in path2, path2
assert "From stealth" not in path2 and "Gouge trick: Gouge(front) > step behind > Mutilate(4 s window)" in path2, path2
L.globals().SlashCmdList.BATTLEWRIGHT("guide")  # closes it
L.eval("function(ns) ns.Talents.Get = ns._get end")(ns)
assert L.eval("function(ns) return ns.Guide.frame.shown end")(ns) is False
L.globals().SlashCmdList.BATTLEWRIGHT("spec auto")
L.execute("GAME.mainHand = nil; GAME.combat = true"); L.globals().fire("PLAYER_EQUIPMENT_CHANGED")

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
# Kick's icon comes by spell ID when a lookup by name finds nothing (beta: a "?").
L.execute("GAME.casting = 'yes'; _tex = C_Spell.GetSpellTexture; C_Spell.GetSpellTexture = function(k) if type(k) == 'number' then return 'icon:id' .. k end end")
icon = L.eval("function(ns) ns.Display.Update() return rawget(ns.Display.frame.cd.icon, 'tex') end")(ns)
assert icon and icon.startswith("icon:id"), icon
L.execute("C_Spell.GetSpellTexture = _tex")
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

# Eureka! (Gnome racial): 3 charges, so it waits until the next three attacks
# are two builders and the 5-point finisher: 3+ combo points.
eureka = lambda: L.eval("function(ns) local v = ns.Display.Compute() return v.cooldown and v.cooldown.spell end")(ns)
show(known={"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25, "Eureka!": 0}, cp=1, buffs=[["Slice and Dice", 130]])
assert eureka() is None
show(cp=3)
assert eureka() == "Eureka!"
# ...but not while the target casts: Kick comes first and would use a charge.
L.execute("GAME.casting = 'yes'")
assert eureka() is None
L.execute("GAME.casting = nil")
# Cold Blood waits for full combo points: 5 without Mutilate.
L.globals().SlashCmdList.BATTLEWRIGHT("spec assassination")
cb = lambda: L.eval("function(ns) local v = ns.Display.Compute() return v.cooldown and v.cooldown.spell end")(ns)
show(known={"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25, "Cold Blood": 0}, cp=4, buffs=[["Slice and Dice", 130]])
assert cb() is None
show(cp=5)
assert cb() == "Cold Blood", cb()
L.globals().SlashCmdList.BATTLEWRIGHT("spec auto")
L.execute("GAME.cp = 0; GAME.buffs = {}")

# The game often spends the combo points before it reports the finisher, and a
# state read in between sees 0 (beta, 2026-10-04: Slice and Dice untracked, so
# Eviscerate never came up). The points are taken when the cast is sent.
L.execute("GAME.blocked = true")
kit3 = {"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25}
show(known=kit3, cp=4, buffs=[])
snd = L.eval("function(ns) return ns.Display.Compute().state.spells['Slice and Dice'].id end")(ns)
L.globals().fire("UNIT_SPELLCAST_SENT", "player", "target", "cast-snd", snd)
L.execute("GAME.cp = 0"); L.eval("function(ns) ns.Display.Compute() end")(ns)  # a read after the points are gone
L.globals().fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-snd", snd)
assert abs(L.eval("function(ns) return ns.Tracker.expires['Slice and Dice'] end")(ns) - (GAME_NOW := L.eval("GAME.now")) - 18) < 1e-9
# Fallback without the sent event: the drop in combo points (5 -> 1, Ruthlessness).
L.eval("function(ns) ns.Tracker.expires = {} end")(ns)
L.execute("GAME.cp = 5"); L.globals().fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
L.execute("GAME.cp = 1"); L.globals().fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
L.eval("function(ns) ns.Display.Compute() end")(ns)
L.globals().fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-snd2", snd)
assert abs(L.eval("function(ns) return ns.Tracker.expires['Slice and Dice'] end")(ns) - GAME_NOW - 21) < 1e-9
# And with Slice and Dice tracked, 5 combo points mean Eviscerate.
L.execute("GAME.cp = 5")
assert show() == ("Eviscerate", 0), show()
L.execute("GAME.blocked = false; GAME.cp = 0")
L.eval("function(ns) ns.Tracker.expires = {} ns.Tracker.spent = nil end")(ns)

# Gouge sets up Backstab (dagger): step behind it. Any hit ends the Gouge.
L.execute("GAME.blocked = true; GAME.mainHand = 15; GAME.guid = 'Creature-G'"); L.globals().fire("PLAYER_EQUIPMENT_CHANGED")
gk = {"Sinister Strike": 45, "Eviscerate": 35, "Slice and Dice": 25, "Backstab": 60, "Gouge": 45}
assert show(known=gk, cp=1) == ("Slice and Dice", 0)
def cast(name):
    sid = L.eval("function(ns, n) return ns.Display.Compute().state.spells[n].id end")(ns, name)
    L.globals().fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", sid)
def why():
    return L.eval("function(ns) local m = ns.Display.Compute().main return m.spell, m.why end")(ns)
L.execute("GAME.cp = 1")
L.eval("function(ns) ns.Tracker.expires['Slice and Dice'] = GAME.now + 20 end")(ns)
assert tuple(why()) == ("Sinister Strike", "build combo points"), tuple(why())
cast("Gouge")
assert tuple(why()) == ("Backstab", "Gouged: step behind it"), tuple(why())
cast("Backstab")
assert tuple(why())[0] == "Sinister Strike"
# Slice and Dice down: the Gouge's 1 combo point would ask for Slice and Dice,
# but the Gouge window comes first (beta, 2026-10-04: no Backstab was shown).
L.eval("function(ns) ns.Tracker.expires['Slice and Dice'] = nil end")(ns)
L.execute("GAME.cp = 0")
assert tuple(why())[0] == "Sinister Strike", tuple(why())
cast("Gouge"); L.execute("GAME.cp = 1")
assert tuple(why()) == ("Backstab", "Gouged: step behind it"), tuple(why())
cast("Backstab"); L.execute("GAME.cp = 2")
assert tuple(why())[0] == "Slice and Dice", tuple(why())
L.eval("function(ns) ns.Tracker.expires['Slice and Dice'] = GAME.now + 20 end")(ns)
# Gouge wears off after 4 s (no Improved Gouge).
cast("Gouge"); L.execute("GAME.now = GAME.now + 4.5")
assert tuple(why())[0] == "Sinister Strike"
# With Mutilate (2 combo points, works from the front), it stays first even after Gouge.
L.globals().SlashCmdList.BATTLEWRIGHT("spec assassination")
show(known=dict(gk, Mutilate=60), cp=1)
L.eval("function(ns) ns.Tracker.expires['Slice and Dice'] = GAME.now + 20 end")(ns)
cast("Gouge")
assert tuple(why())[0] == "Mutilate", tuple(why())
# Venom: kept up at full combo points, after Slice and Dice; then Eviscerate.
show(known=dict(gk, Mutilate=60, Venom=25), cp=4)
L.eval("function(ns) ns.Tracker.expires['Slice and Dice'] = GAME.now + 20 end")(ns)
assert tuple(why())[0] == "Venom", tuple(why())
cast("Venom")
assert tuple(why())[0] == "Eviscerate", tuple(why())
L.globals().SlashCmdList.BATTLEWRIGHT("spec auto")
L.execute("GAME.blocked = false; GAME.mainHand = nil; GAME.guid = nil; GAME.now = 100; GAME.cp = 0")
L.globals().fire("PLAYER_EQUIPMENT_CHANGED")
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
# /bwp book: every talent's text at every rank, and the spell book.
L.execute("""
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
C_Traits = {
  GetConfigInfo = function() return { treeIDs = { 1111 } } end,
  GetTreeNodes = function() return { 105712 } end,
  GetNodeInfo = function() return { maxRanks = 2, activeRank = 1, posY = 6330, entryIDs = { 50 }, conditionIDs = { 43439 },
    visibleEdges = {}, groupIDs = { 11574 } } end,
  GetEntryInfo = function() return { definitionID = 9 } end,
  GetDefinitionInfo = function() return { spellID = 1310703 } end,
  GetTraitDescription = function(_, rank) return "Venom rank " .. rank end,
  GetConditionInfo = function() return { spentAmountRequired = 30 } end,
}
C_Spell.GetSpellName = function() return "Venom" end
C_Spell.GetSpellDescription = function() return "" end
C_Spell.GetSpellSubtext = function() return "Rank 4" end
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo() return "Assassination", nil, 0, 1 end
function GetSpellBookItemInfo() return "SPELL", 1752 end
function GetNumTrainerServices() return 0 end
""")
L.globals().SlashCmdList.BATTLEWRIGHTPROBE("book")
book = L.eval("""function() local b = BattlewrightProbeDB.book local n = b.nodes[1]
  return n.entries[1].name, n.entries[1].ranks[2], b.conditions[43439].spentAmountRequired, b.spells[1].id, b.spells[1].rank end""")()
assert tuple(book) == ("Venom", "Venom rank 2", 30, 1752, "Rank 4"), tuple(book)
L.globals().SlashCmdList.BATTLEWRIGHTPROBE("export")
export = Path(tempfile.mkdtemp()) / "export.json"
export.write_text(L.globals().EXPORTTEXT)
assert json.loads(export.read_text())["runs"][0]["samples"] == 60
r = subprocess.run([sys.executable, str(R / "tools" / "probe_summary.py"), str(export)], capture_output=True, text=True)
assert "BLOCKED by the game: SomeProtectedFunction() x1 (ADDON_ACTION_FORBIDDEN" in r.stdout, r.stdout
assert r.returncode == 0 and "aura expirationTime: SECRET" in r.stdout and "hidden in combat: aura expirationTime" in r.stdout, r.stdout + r.stderr
print(r.stdout)
print("BATTLEWRIGHT TESTS PASSED")
