-- Battlewright: Rogue priorities. Pure: takes a State.Read() table, returns
--   main = { spell, why, wait (seconds of energy to wait for, 0 = now, nil =
--            unknown), short (true while there isn't enough energy) },
--   cooldown = { spell, why } or nil   (an off-the-GCD cooldown worth using now)
-- Built from what you have: known spells and ranks (state.spells), talents
-- (state.talents, read out of combat), and your main-hand weapon. Classic
-- Rogue play to start; Forever's new talents are listed by /bw talents with
-- their descriptions until their effect on the rotation is known.
local _, ns = ...

local Rogue = {}
ns.Rotations.ROGUE = Rogue

-- Forever puts all three specs in one Traits tree; a node's group ID says
-- which (from Gearwright's 2026-10-03 beta capture).
Rogue.tabGroups = { [11580] = 1, [11573] = 2, [11572] = 3 }
Rogue.tabToSpec = { [1] = "assassination", [2] = "combat", [3] = "subtlety" }

local DAGGER = 15
local SND_REFRESH = 2 -- refresh Slice and Dice when this close to falling off

-- How each talent changes the rotation. Talents not listed here and not in
-- PASSIVE are reported by /bw talents as "not used yet".
Rogue.USED = {
  ["Improved Slice and Dice"] = "Slice and Dice lasts 15% longer per rank (timer estimate)",
  ["Mutilate"] = "Mutilate is the builder; finish at 4 combo points",
  ["Cold Blood"] = "suggested before a finisher",
  ["Hemorrhage"] = "Subtlety builder",
  ["Ghostly Strike"] = "Subtlety builder when ready",
  ["Premeditation"] = "suggested in stealth before your opener",
  ["Preparation"] = "suggested when Vanish/Evasion/Sprint are all on cooldown",
  ["Serrated Blades"] = "Rupture is kept up at full combo points",
  ["Improved Ambush"] = "Ambush is the opener (with a dagger)",
  ["Riposte"] = "used after a parry",
  ["Blade Flurry"] = "suggested as a cooldown",
  ["Adrenaline Rush"] = "suggested as a cooldown",
  ["Improved Kick"] = "Kick is suggested when the target casts something interruptible",
}
-- Classic talents that only add damage, crit, energy or avoidance: nothing to press differently.
Rogue.PASSIVE = {
  "Malice", "Remorseless Attacks", "Ruthlessness", "Murder", "Relentless Strikes", "Improved Expose Armor",
  "Lethality", "Vile Poisons", "Improved Poisons", "Vigor", "Improved Kidney Shot", "Seal Fate",
  "Improved Gouge", "Improved Eviscerate", "Improved Sinister Strike", "Lightning Reflexes", "Deflection",
  "Precision", "Endurance", "Improved Sprint", "Dual Wield Specialization", "Weapon Expertise",
  "Aggression", "Hack and Slash", "Camouflage", "Master of Deception", "Opportunity", "Setup", "Elusiveness",
  "Initiative", "Improved Distract", "Heightened Senses", "Dirty Deeds",
}

function Rogue.DurationScale(name, talents)
  if name == "Slice and Dice" then return 1 + 0.15 * (talents["Improved Slice and Dice"] or 0) end
  return 1
end

local function known(s, name) return s.spells[name] ~= nil end
local function talent(s, name) return (s.talents and s.talents[name] or 0) > 0 end
local function dagger(s) return s.mainHand == DAGGER end

-- Usable soon: known, off cooldown, and the game doesn't say it's unusable
-- (wrong weapon, not behind...). Energy is handled by `wait`.
local function ready(s, name)
  local sp = s.spells[name]
  return sp and sp.cooldown <= 0 and sp.usable ~= false
end

-- wait: seconds of energy to wait for, 0 = now. When energy is hidden (in
-- combat on Forever) the game still says "not enough energy" (noPower): then
-- wait is unknown (nil) and short is true.
local function act(s, name, why)
  local sp = s.spells[name]
  if s.energy == nil then
    return { spell = name, why = why, wait = not sp.noPower and 0 or nil, short = sp.noPower or nil }
  end
  local short = math.max(0, (sp.cost or 0) - s.energy)
  return { spell = name, why = why, wait = short > 0 and short / (s.regen > 0 and s.regen or 10) or 0,
    short = short > 0 or nil }
end

local function opener(s, spec)
  local order
  if dagger(s) and spec ~= "combat" then
    order = { "Ambush", "Garrote", "Cheap Shot", "Sinister Strike" }
  elseif spec == "combat" then
    order = { "Cheap Shot", "Garrote", "Sinister Strike" }
  else
    order = { "Garrote", "Cheap Shot", "Sinister Strike" } -- Ambush needs a dagger
  end
  for _, name in ipairs(order) do
    if ready(s, name) then return act(s, name, "opener from stealth") end
  end
end

local function finisher(s, spec)
  local cp, hp = s.cp, s.target.hp or 1 -- target health is hidden in combat: assume healthy
  local snd = s.buffs["Slice and Dice"]
  local dying = hp < 0.15
  -- Slice and Dice first: it speeds up every attack.
  if cp >= 1 and not dying and ready(s, "Slice and Dice") and (not snd or snd < SND_REFRESH) and (cp >= 2 or not snd) then
    return act(s, "Slice and Dice", snd and "Slice and Dice is about to fall off" or "Slice and Dice is down")
  end
  local full = (spec == "assassination" and known(s, "Mutilate")) and 4 or 5 -- Mutilate adds 2 at a time
  local rupture = spec ~= "combat" or talent(s, "Serrated Blades")
  if rupture and cp >= full and hp > 0.5 and not s.debuffs["Rupture"] and ready(s, "Rupture") then
    return act(s, "Rupture", talent(s, "Serrated Blades") and "keep Rupture up (Serrated Blades)" or "long fight: bleed it")
  end
  if (cp >= full or (cp >= 3 and hp < 0.25)) and ready(s, "Eviscerate") then
    return act(s, "Eviscerate", cp >= full and "full combo points" or "target nearly dead")
  end
end

local function builder(s, spec)
  if ready(s, "Riposte") then return act(s, "Riposte", "after a parry") end
  local order = {}
  if spec == "assassination" then order[#order + 1] = "Mutilate" end
  if spec == "subtlety" then
    order[#order + 1] = "Ghostly Strike"
    order[#order + 1] = "Hemorrhage"
  end
  -- Backstab needs a main-hand dagger and being behind the target, which the
  -- game doesn't tell addons: only when you've said so (/bw behind).
  if dagger(s) and s.behind then order[#order + 1] = "Backstab" end
  order[#order + 1] = "Sinister Strike"
  for _, name in ipairs(order) do
    if ready(s, name) then
      local why = name == "Backstab" and "build combo points (you're behind it)" or "build combo points"
      return act(s, name, why)
    end
  end
end

local function cooldown(s, spec)
  -- Kick unless the game says the cast can't be interrupted (in combat it
  -- usually can't say: the cast's details are secret).
  local cast = s.target.casting
  if cast and cast.interruptible ~= false and ready(s, "Kick") then
    return { spell = "Kick", why = cast.interruptible and "interrupt the cast" or "the target is casting", urgent = true }
  end
  if s.stealthed and s.cp == 0 and ready(s, "Premeditation") then
    return { spell = "Premeditation", why = "before your opener" }
  end
  if not s.inCombat then return nil end
  if spec == "combat" then
    if ready(s, "Adrenaline Rush") then return { spell = "Adrenaline Rush", why = "ready" } end
    if ready(s, "Blade Flurry") then return { spell = "Blade Flurry", why = "ready (best with two targets)" } end
  elseif spec == "assassination" then
    if s.cp >= 4 and ready(s, "Cold Blood") then return { spell = "Cold Blood", why = "before your finisher" } end
  end
  if ready(s, "Preparation") and known(s, "Vanish") and not ready(s, "Vanish") and not ready(s, "Evasion") then
    return { spell = "Preparation", why = "resets Vanish, Evasion and Sprint" }
  end
end

-- The next ability for `spec`, or nil when there's nothing to attack.
function Rogue.Next(s, spec)
  if not (s.target.exists and s.target.attackable) then return nil end
  local main = (s.stealthed and opener(s, spec)) or finisher(s, spec) or builder(s, spec)
  if main and s.inRange == false then main.outOfRange = true end
  return main, cooldown(s, spec)
end
