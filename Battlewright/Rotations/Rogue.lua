-- Battlewright: Rogue priorities. Pure: takes a State.Read() table, returns
--   main = { spell, why, wait (seconds of energy to wait for, 0 = now, nil =
--            unknown), short (true while there isn't enough energy) },
--   cooldown = { spell, why } or nil   (an off-the-GCD cooldown worth using now)
-- A first, simple version (2026-10-04) built on Classic Rogue play; refine as
-- Forever's talents (Venom, Restless Blades, Thousand Cuts...) get tested.
local _, ns = ...

local Rogue = {}
ns.Rotations.ROGUE = Rogue

local SND_REFRESH = 2 -- refresh Slice and Dice when this close to falling off

local function known(s, name) return s.spells[name] ~= nil end

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
  local order = spec == "combat" and { "Cheap Shot", "Garrote", "Ambush", "Sinister Strike" }
    or { "Ambush", "Garrote", "Cheap Shot", "Sinister Strike" }
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
  if spec ~= "combat" and cp >= full and hp > 0.5 and not s.debuffs["Rupture"] and ready(s, "Rupture") then
    return act(s, "Rupture", "long fight: bleed it")
  end
  if (cp >= full or (cp >= 3 and hp < 0.25)) and ready(s, "Eviscerate") then
    return act(s, "Eviscerate", cp >= full and "full combo points" or "target nearly dead")
  end
end

local function builder(s, spec)
  if ready(s, "Riposte") then return act(s, "Riposte", "after a parry") end
  local order
  if spec == "assassination" then
    order = { "Mutilate", "Sinister Strike" }
  elseif spec == "subtlety" then
    order = { "Ghostly Strike", "Hemorrhage", "Sinister Strike" }
  else
    order = { "Sinister Strike" }
  end
  for _, name in ipairs(order) do
    if ready(s, name) then return act(s, name, "build combo points") end
  end
end

local function cooldown(s, spec)
  if not s.inCombat then return nil end
  if spec == "combat" then
    if ready(s, "Adrenaline Rush") then return { spell = "Adrenaline Rush", why = "ready" } end
    if ready(s, "Blade Flurry") then return { spell = "Blade Flurry", why = "ready (best with two targets)" } end
  elseif spec == "assassination" then
    if s.cp >= 4 and ready(s, "Cold Blood") then return { spell = "Cold Blood", why = "before your finisher" } end
  end
end

-- The next ability for `spec`, or nil when there's nothing to attack.
function Rogue.Next(s, spec)
  if not (s.target.exists and s.target.attackable) then return nil end
  local main = (s.stealthed and opener(s, spec)) or finisher(s, spec) or builder(s, spec)
  return main, cooldown(s, spec)
end
