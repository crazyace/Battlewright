-- Battlewright: a snapshot of what the rotation needs, read from the game.
--   { now, energy (nil when hidden), energyMax, regen, cp, stealthed, inCombat,
--     target = { exists, attackable, hp (0-1) },
--     buffs = { [name] = secondsLeft }, debuffs = { [name] = secondsLeft },   (mine on the target)
--     spells = { [name] = { id, cost, cooldown (s left), usable, noPower } } }   (known spells only)
--   estimated = true when buffs/debuffs come from Tracker.lua, not the game.
--   target.casting = { interruptible = bool } while the target casts or channels,
--   inRange = false when out of melee range (nil = unknown),
--   talents = { [name] = rank } (read out of combat), mainHand = weapon subclass
--   (15 = dagger) or nil, behind = true when you've told Battlewright to assume
--   you're behind the target (/bw behind; the game doesn't say).
--
-- What Forever lets addons read in combat (BattlewrightProbe, 2026-10-03,
-- docs/FINDINGS.md): combo points, cooldowns, costs, IsSpellUsable (incl. "not
-- enough power"), stealth, range, the target's GUID and casts, your cast
-- events: yes. Energy, target health (and their percents), energy regen:
-- secret. Auras by index: blocked. So energy and target health may be nil, and
-- buffs/debuffs fall back to Tracker.lua (or a lookup by spell ID, if it answers).
-- Returns nil, "secret" only when combo points are hidden (no rotation without
-- them), and nil, "no-api" when a call it needs is missing.
local _, ns = ...

local State = {}
ns.State = State

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

-- Spells the rotations ask about, per class.
State.SPELLS = {
  ROGUE = { "Sinister Strike", "Eviscerate", "Slice and Dice", "Rupture", "Backstab", "Ambush",
    "Cheap Shot", "Garrote", "Mutilate", "Hemorrhage", "Ghostly Strike", "Riposte", "Kick",
    "Blade Flurry", "Adrenaline Rush", "Cold Blood", "Premeditation", "Preparation", "Expose Armor",
    "Vanish", "Evasion", "Sprint" },
}

local function auras(unit, filter, now)
  local out = {}
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return out end
  for i = 1, 40 do
    local ok, a = pcall(get, unit, i, filter)
    if not ok then return nil end -- blocked (in combat on Forever)
    if type(a) ~= "table" then break end
    if secret(a.name) then return nil end
    local left = math.huge
    if not secret(a.expirationTime) and type(a.expirationTime) == "number" and a.expirationTime > 0 then
      left = a.expirationTime - now
    end
    -- A hidden timer still says the aura is there: treat it as lasting.
    out[a.name] = math.max(out[a.name] or 0, left)
  end
  return out
end

local spellIDs = {}

-- Main-hand weapon subclass (Enum.ItemWeaponSubclass; 15 = dagger), cached.
local mainHand, mainHandRead
local function weapon()
  if mainHandRead then return mainHand end
  mainHandRead = true
  local id = GetInventoryItemID and GetInventoryItemID("player", 16)
  if id and C_Item and C_Item.GetItemInfoInstant then
    local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, id)
    mainHand = ok and classID == 2 and subclassID or nil
  else
    mainHand = nil
  end
  return mainHand
end
ns:On("PLAYER_EQUIPMENT_CHANGED", function() mainHandRead = false end)

local function spell(name, now)
  local id = spellIDs[name]
  if id == nil then
    local info = C_Spell and C_Spell.GetSpellInfo and select(2, pcall(C_Spell.GetSpellInfo, name))
    id = type(info) == "table" and not secret(info.spellID) and info.spellID or false
    spellIDs[name] = id
  end
  if not id then return nil end
  ns.Tracker.names[id] = name
  local s = { id = id, cost = 0, cooldown = 0, usable = true, noPower = false }
  if C_Spell.GetSpellPowerCost then
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, id)
    if ok and type(costs) == "table" and costs[1] and not secret(costs[1].cost) then s.cost = costs[1].cost or 0 end
  end
  if C_Spell.GetSpellCooldown then
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    if ok and type(cd) == "table" and not secret(cd.startTime) and not secret(cd.duration) then
      local start, dur = cd.startTime or 0, cd.duration or 0
      -- The global cooldown (1.5 s or less) isn't a real cooldown.
      if start > 0 and dur > 1.5 then s.cooldown = math.max(0, start + dur - now) end
    end
  end
  if C_Spell.IsSpellUsable then
    local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, id)
    if ok and not secret(usable) then
      s.usable = usable == true or noPower == true
      s.noPower = not secret(noPower) and noPower == true
    end
  end
  return s
end

-- Forget spell IDs when spells change (a new rank, a respec).
for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED" }) do
  ns:On(event, function() spellIDs = {} end)
end

-- One of your auras by spell ID: seconds left, or nil when the game doesn't
-- say (not up, or hidden).
function State.AuraBySpellID(id, now)
  local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
  if not get then return nil end
  local ok, a = pcall(get, id)
  if not ok or type(a) ~= "table" or secret(a.expirationTime) then return nil end
  if type(a.expirationTime) == "number" and a.expirationTime > 0 then return a.expirationTime - now end
  return math.huge
end

-- The target's cast or channel: { interruptible = true / false / nil (unknown) },
-- or nil when it isn't casting. In combat on Forever the cast's details come
-- back secret (BattlewrightProbe round 3), but a secret answer still means a
-- cast is going on; only "nothing" (nil) means it isn't.
function State.Casting()
  for _, fn in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
    if fn then
      local r = { pcall(fn, "target") }
      if r[1] and r[2] ~= nil then
        local notInterruptible = fn == UnitCastingInfo and r[9] or r[8]
        if secret(notInterruptible) then return { interruptible = nil } end
        return { interruptible = notInterruptible ~= true }
      end
    end
  end
end

-- In melee range of the target (by Sinister Strike's range), or nil if unknown.
function State.InRange(spells)
  local probe = spells["Sinister Strike"]
  if not (probe and C_Spell and C_Spell.IsSpellInRange) then return nil end
  local ok, inRange = pcall(C_Spell.IsSpellInRange, probe.id, "target")
  if not ok or secret(inRange) or inRange == nil then return nil end
  return inRange == true
end

function State.Read()
  if not (UnitPower and GetTime) then return nil, "no-api" end
  local now = GetTime()
  local energyType = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
  local cpType = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
  local energy, energyMax = UnitPower("player", energyType), UnitPowerMax("player", energyType)
  local cp = UnitPower("player", cpType)
  if (not cp or cp == 0) and GetComboPoints then cp = GetComboPoints("player", "target") end
  if secret(cp) then return nil, "secret" end
  if secret(energy) then energy = nil end -- hidden in combat on Forever
  if secret(energyMax) then energyMax = nil end
  ns.Tracker.lastCP = cp or 0
  local s = {
    now = now, energy = energy, energyMax = energyMax or 100, cp = cp or 0, regen = 10,
    stealthed = IsStealthed and IsStealthed() == true or false,
    inCombat = UnitAffectingCombat and UnitAffectingCombat("player") == true or false,
    target = { exists = UnitExists("target") == true },
    spells = {},
    talents = ns.Talents.Get().ranks,
    mainHand = weapon(),
    behind = ns.db and ns.db.assumeBehind or false,
  }
  if GetPowerRegen then
    local ok, _, active = pcall(GetPowerRegen)
    if ok and type(active) == "number" and not secret(active) and active > 0 then s.regen = active end
  end
  if s.target.exists then
    s.target.attackable = UnitCanAttack("player", "target") == true
    s.target.casting = State.Casting()
    local hp, max = UnitHealth("target"), UnitHealthMax("target")
    if not secret(hp) and not secret(max) and type(max) == "number" and max > 0 then s.target.hp = hp / max end
  end
  local _, class = UnitClass("player")
  for _, name in ipairs(State.SPELLS[class] or {}) do s.spells[name] = spell(name, now) end
  s.inRange = State.InRange(s.spells)
  s.buffs = auras("player", "HELPFUL", now)
  -- (Not `exists and auras(...) or {}`: a blocked read returns nil, which that
  -- would turn into "no debuffs" instead of falling back to the tracker.)
  s.debuffs = {}
  if s.target.exists then s.debuffs = auras("target", "HARMFUL|PLAYER", now) end
  -- Auras blocked: use what our own casts say instead, unless a lookup by
  -- spell ID gives the real thing.
  if not s.buffs then
    s.buffs, s.estimated = ns.Tracker.Remaining(false, now), true
    for name in pairs(ns.Tracker.DURATION) do
      local id = s.spells[name] and s.spells[name].id
      local left = id and State.AuraBySpellID(id, now)
      if left then s.buffs[name] = left end
    end
  end
  if not s.debuffs then s.debuffs, s.estimated = ns.Tracker.Remaining(true, now), true end
  return s
end
