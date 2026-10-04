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
  ["Improved Gouge"] = "the Backstab window after Gouge lasts 0.5 s longer per rank",
  ["Venom"] = "finisher kept up (after Slice and Dice) at full combo points",
  ["Cutthroat"] = "Ambush suggested out of stealth when Cutthroat allows it",
  ["Improved Kick"] = "Kick is suggested when the target casts something interruptible",
}
-- Classic talents that only add damage, crit, energy or avoidance: nothing to press differently.
Rogue.PASSIVE = {
  "Malice", "Remorseless Attacks", "Ruthlessness", "Murder", "Relentless Strikes", "Improved Expose Armor",
  "Lethality", "Vile Poisons", "Improved Poisons", "Vigor", "Improved Kidney Shot", "Seal Fate",
  "Improved Eviscerate", "Improved Sinister Strike", "Lightning Reflexes", "Deflection",
  "Precision", "Endurance", "Improved Sprint", "Dual Wield Specialization", "Weapon Expertise",
  "Aggression", "Hack and Slash", "Camouflage", "Master of Deception", "Opportunity", "Setup", "Elusiveness",
  "Initiative", "Improved Distract", "Heightened Senses", "Dirty Deeds",
  -- Forever's new talents (texts from /bwp book, 2026-10-03):
  "Puncturing Wounds", "Flawless Execution", "Dirty Tricks", "Quietus", "Thousand Cuts",
}

function Rogue.DurationScale(name, talents)
  if name == "Slice and Dice" then return 1 + 0.15 * (talents["Improved Slice and Dice"] or 0) end
  if name == "Gouge" then return 1 + 0.125 * (talents["Improved Gouge"] or 0) end -- +0.5 s a rank
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
  -- Venom (Assassination capstone): poisons +30% damage while it lasts.
  if cp >= full and not dying and not s.buffs["Venom"] and ready(s, "Venom") then
    return act(s, "Venom", "Venom is down: poisons hit 30% harder")
  end
  local rupture = spec ~= "combat" or talent(s, "Serrated Blades")
  -- A long fight is worth bleeding. Health is hidden in combat, so then only
  -- elites and bosses count (or anything, with Serrated Blades): ordinary mobs
  -- die before Rupture pays off.
  local long
  if s.target.hp then long = s.target.hp > 0.5 else long = s.target.elite or talent(s, "Serrated Blades") end
  if rupture and cp >= full and long and not s.debuffs["Rupture"] and ready(s, "Rupture") then
    local why = talent(s, "Serrated Blades") and "keep Rupture up (Serrated Blades)"
      or (s.target.elite and "elite: bleed it" or "long fight: bleed it")
    return act(s, "Rupture", why)
  end
  if (cp >= full or (cp >= 3 and hp < 0.25)) and ready(s, "Eviscerate") then
    return act(s, "Eviscerate", cp >= full and "full combo points" or "target nearly dead")
  end
end

local function builder(s, spec)
  if ready(s, "Riposte") then return act(s, "Riposte", "after a parry") end
  -- Cutthroat: a Backstab can let your next Ambush skip Stealth (the game
  -- then says Ambush is usable out of stealth).
  if not s.stealthed and dagger(s) and talent(s, "Cutthroat") and ready(s, "Ambush") then
    return act(s, "Ambush", "Cutthroat: Ambush without Stealth")
  end
  local order = {}
  if spec == "assassination" then order[#order + 1] = "Mutilate" end
  if spec == "subtlety" then
    order[#order + 1] = "Ghostly Strike"
    order[#order + 1] = "Hemorrhage"
  end
  -- Backstab needs a main-hand dagger and being behind the target, which the
  -- game doesn't tell addons: only when you've said so (/bw behind), or while
  -- your Gouge holds it (step behind it and Backstab).
  -- (Gouge stops your auto-attack, so only your next ability breaks it.)
  -- Mutilate stays first: 2 combo points, and it works from the front.
  local gouged = s.debuffs["Gouge"] ~= nil
  if dagger(s) and (s.behind or gouged) then table.insert(order, order[1] == "Mutilate" and 2 or 1, "Backstab") end
  order[#order + 1] = "Sinister Strike"
  for _, name in ipairs(order) do
    if ready(s, name) then
      local why = name == "Backstab" and (gouged and "Gouged: step behind it" or "build combo points (you're behind it)")
        or "build combo points"
      return act(s, name, why)
    end
  end
end

local function cooldown(s, spec)
  -- Kick unless the game says the cast can't be interrupted (in combat it
  -- usually can't say: the cast's details are secret).
  local cast = s.target.casting
  if cast and cast.interruptible ~= false and ready(s, "Kick") then
    local kick = { spell = "Kick", why = cast.interruptible and "interrupt the cast" or "the target is casting",
      urgent = true }
    -- Only a secret flag is handed on (for the display to draw); a readable
    -- one already said "interruptible" above. (No `x and y or z` on it: testing
    -- a secret value is an error.)
    if cast.rawSecret then kick.notInterruptible = cast.raw end
    return kick
  end
  if s.stealthed and s.cp == 0 and ready(s, "Premeditation") then
    return { spell = "Premeditation", why = "before your opener" }
  end
  if not s.inCombat then return nil end
  -- Gnome racial: the next 3 attacks cost 10% less and hit 10% harder (2 min).
  if ready(s, "Eureka!") then return { spell = "Eureka!", why = "racial: 3 cheaper, harder attacks" } end
  if spec == "combat" then
    if ready(s, "Adrenaline Rush") then return { spell = "Adrenaline Rush", why = "ready" } end
    if ready(s, "Blade Flurry") then return { spell = "Blade Flurry", why = "ready (best with two targets)" } end
  elseif spec == "assassination" then
    -- Cold Blood on a full-combo-point Eviscerate (4 with Mutilate, else 5).
    local full = known(s, "Mutilate") and 4 or 5
    if s.cp >= full and ready(s, "Cold Blood") then return { spell = "Cold Blood", why = "before your finisher" } end
  end
  if ready(s, "Preparation") and known(s, "Vanish") and not ready(s, "Vanish") and not ready(s, "Evasion") then
    return { spell = "Preparation", why = "resets Vanish, Evasion and Sprint" }
  end
end

-- While your Gouge holds the target: the attack it set up (Backstab with a
-- dagger, or Mutilate) comes before Slice and Dice, which can wait the few
-- seconds; the Gouge can't. A full-combo-point finisher still comes first.
local function gougeWindow(s, spec)
  if not s.debuffs["Gouge"] then return nil end
  local full = (spec == "assassination" and known(s, "Mutilate")) and 4 or 5
  if s.cp >= full then return nil end
  if not ((dagger(s) and ready(s, "Backstab")) or ready(s, "Mutilate")) then return nil end
  return builder(s, spec)
end

-- The next ability for `spec`, or nil when there's nothing to attack.
function Rogue.Next(s, spec)
  if not (s.target.exists and s.target.attackable) then return nil end
  local main = (s.stealthed and opener(s, spec)) or gougeWindow(s, spec) or finisher(s, spec) or builder(s, spec)
  if main and s.inRange == false then main.outOfRange = true end
  return main, cooldown(s, spec)
end
