-- Battlewright: a snapshot of what the rotation needs, read from the game.
--   { now, energy, energyMax, regen, cp, stealthed, inCombat,
--     target = { exists, attackable, hp (0-1) },
--     buffs = { [name] = secondsLeft }, debuffs = { [name] = secondsLeft },   (mine on the target)
--     spells = { [name] = { id, cost, cooldown (s left), usable } } }   (known spells only)
-- Returns nil, "secret" when the client hides a value the rotation can't do
-- without (Forever has issecretvalue; some combat data may be secret), and
-- nil, "no-api" when a call it needs is missing.
local _, ns = ...

local State = {}
ns.State = State

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

-- Spells the rotations ask about, per class.
State.SPELLS = {
  ROGUE = { "Sinister Strike", "Eviscerate", "Slice and Dice", "Rupture", "Backstab", "Ambush",
    "Cheap Shot", "Garrote", "Mutilate", "Hemorrhage", "Ghostly Strike", "Riposte", "Kick",
    "Blade Flurry", "Adrenaline Rush", "Cold Blood", "Premeditation", "Preparation", "Expose Armor" },
}

local function auras(unit, filter, now)
  local out = {}
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return out end
  for i = 1, 40 do
    local ok, a = pcall(get, unit, i, filter)
    if not ok or type(a) ~= "table" then break end
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

local function spell(name, now)
  local id = spellIDs[name]
  if id == nil then
    local info = C_Spell and C_Spell.GetSpellInfo and select(2, pcall(C_Spell.GetSpellInfo, name))
    id = type(info) == "table" and not secret(info.spellID) and info.spellID or false
    spellIDs[name] = id
  end
  if not id then return nil end
  local s = { id = id, cost = 0, cooldown = 0, usable = true }
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
    if ok and not secret(usable) then s.usable = usable == true or noPower == true end
  end
  return s
end

-- Forget spell IDs when spells change (a new rank, a respec).
for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED" }) do
  ns:On(event, function() spellIDs = {} end)
end

function State.Read()
  if not (UnitPower and GetTime) then return nil, "no-api" end
  local now = GetTime()
  local energyType = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
  local cpType = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
  local energy, energyMax = UnitPower("player", energyType), UnitPowerMax("player", energyType)
  local cp = UnitPower("player", cpType)
  if (not cp or cp == 0) and GetComboPoints then cp = GetComboPoints("player", "target") end
  if secret(energy) or secret(cp) or secret(energyMax) then return nil, "secret" end
  local s = {
    now = now, energy = energy or 0, energyMax = energyMax or 100, cp = cp or 0, regen = 10,
    stealthed = IsStealthed and IsStealthed() == true or false,
    inCombat = UnitAffectingCombat and UnitAffectingCombat("player") == true or false,
    target = { exists = UnitExists("target") == true },
    spells = {},
  }
  if GetPowerRegen then
    local ok, _, active = pcall(GetPowerRegen)
    if ok and type(active) == "number" and not secret(active) and active > 0 then s.regen = active end
  end
  if s.target.exists then
    s.target.attackable = UnitCanAttack("player", "target") == true
    local hp, max = UnitHealth("target"), UnitHealthMax("target")
    if not secret(hp) and not secret(max) and type(max) == "number" and max > 0 then s.target.hp = hp / max end
  end
  s.buffs = auras("player", "HELPFUL", now)
  s.debuffs = s.target.exists and auras("target", "HARMFUL|PLAYER", now) or {}
  if not s.buffs or not s.debuffs then return nil, "secret" end
  local _, class = UnitClass("player")
  for _, name in ipairs(State.SPELLS[class] or {}) do s.spells[name] = spell(name, now) end
  return s
end
