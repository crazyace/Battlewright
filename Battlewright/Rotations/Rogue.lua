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
-- Full combo points: 4 with Mutilate (it adds 2 at a time, 6 would waste one), else 5.
local function fullCP(s) return known(s, "Mutilate") and 4 or 5 end
-- Eureka! waits until its 3 charges reach the finisher: two builders before it.
local function eurekaCP(s) return fullCP(s) - 2 * (known(s, "Mutilate") and 2 or 1) end

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
  local full = fullCP(s)
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
  -- Eureka! (Gnome racial, 2 min): your next 3 non-periodic damaging abilities
  -- cost 10% less energy and deal 10% more damage. Every direct hit uses a
  -- charge (Kick and Gouge too; Garrote and Rupture don't), so press it when
  -- the next three are your strongest: two builders and the full-combo-point
  -- finisher (with Mutilate, one Mutilate gets you there), not while the
  -- target casts (Kick would spend one).
  local full = fullCP(s)
  if not s.target.casting and s.cp >= eurekaCP(s) and ready(s, "Eureka!") then
    return { spell = "Eureka!", why = "racial: your next 3 attacks, finisher included, cost less and hit harder" }
  end
  if spec == "combat" then
    if ready(s, "Adrenaline Rush") then return { spell = "Adrenaline Rush", why = "ready" } end
    if ready(s, "Blade Flurry") then return { spell = "Blade Flurry", why = "ready (best with two targets)" } end
  elseif spec == "assassination" then
    -- Cold Blood on a full-combo-point Eviscerate (4 with Mutilate, else 5).
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
  if s.cp >= fullCP(s) then return nil end
  if not ((dagger(s) and ready(s, "Backstab")) or ready(s, "Mutilate")) then return nil end
  return builder(s, spec)
end

-- The rotation guide (/bw guide) ---------------------------------------------------
-- The same priorities as Next(), written out for what you have now: known
-- spells, talents and weapons. Rows: { spell = icon name or nil, text }.
local WEAPON_NAMES = { [0] = "an axe", [4] = "a mace", [7] = "a sword", [13] = "a fist weapon", [15] = "a dagger" }
-- Rotation spells still to come, by trainer level (Forever trainer, verified).
-- (Spell IDs for the icons: a spell you don't know yet has no icon by name.)
local COMING = {
  { 20, "Rupture", "a bleed finisher for elites and bosses", 1943 },
  { 22, "Vanish", "back into stealth: escape, or a second opener", 1856 },
  { 26, "Cheap Shot", "a stun opener that works from the front", 1833 },
  { 28, "Instant Poison II", "your first damaging poison: put it on both weapons", 8687 },
  { 30, "Kidney Shot", "a finisher stun", 408 },
  { 30, "Deadly Poison", "poison damage over time", 2835 },
}

function Rogue.Guide(s, spec, level)
  local sections = {}
  local function section(title) local sec = { title = title, rows = {} }; sections[#sections + 1] = sec; return sec end
  local function row(sec, spell, text, id)
    sec.rows[#sec.rows + 1] = { spell = spell, id = id or (spell and s.spells[spell] and s.spells[spell].id), text = text }
  end
  local full = fullCP(s)

  local setup = section("Your setup")
  row(setup, nil, ("Spec: %s"):format(spec:gsub("^%l", string.upper)))
  if dagger(s) then
    row(setup, "Backstab", "Main hand: a dagger. Ambush, Backstab and Gouge -> Backstab all work.")
  elseif s.mainHand then
    row(setup, "Sinister Strike", ("Main hand: %s. Sinister Strike builds; Ambush and Backstab need a dagger in "
      .. "your main hand."):format(WEAPON_NAMES[s.mainHand] or "a weapon"))
  else
    row(setup, nil, "Main hand: empty. Equip a weapon.")
  end
  if s.offHand then
    row(setup, nil, ("Off hand: %s.%s"):format(WEAPON_NAMES[s.offHand] or "a weapon",
      known(s, "Mutilate") and " Mutilate hits with both weapons." or ""))
  elseif (level or 0) >= 10 then
    row(setup, nil, "Off hand: empty. You can Dual Wield: a second weapon is free damage.")
  end

  -- Remorseless Attacks (Forever): after killing a non-trivial enemy, +20% crit
  -- per rank on your next Sinister Strike, Backstab, Ambush, Mutilate or
  -- Ghostly Strike, for 20 s. So: pull the next mob inside those 20 s, and
  -- spend it on your hardest hit (Ambush from stealth).
  local remorse = s.talents and s.talents["Remorseless Attacks"] or 0
  local remorseID = s.talentIDs and s.talentIDs["Remorseless Attacks"]
  local hardest = (dagger(s) and known(s, "Ambush") and "Ambush")
    or (known(s, "Mutilate") and "Mutilate") or (dagger(s) and known(s, "Backstab") and "Backstab") or "Sinister Strike"

  local open = section("From stealth")
  if known(s, "Premeditation") then row(open, "Premeditation", "Premeditation first: 2 combo points.") end
  if dagger(s) and known(s, "Ambush") then
    row(open, "Ambush", "Ambush, from behind: your hardest hit.")
  end
  if known(s, "Garrote") then
    row(open, "Garrote", talent(s, "Dirty Deeds") and "Garrote: a bleed (works from the front with Dirty Deeds)."
      or "Garrote, from behind: a bleed" .. (dagger(s) and " (when you can't Ambush)." or "."))
  end
  if known(s, "Cheap Shot") then row(open, "Cheap Shot", "Cheap Shot: a stun, from any side.") end
  if #open.rows == 0 then row(open, "Sinister Strike", "No opener yet: walk up and Sinister Strike.") end
  if remorse > 0 then
    row(open, "Remorseless Attacks", ("Remorseless Attacks: a kill gives your next Sinister Strike, Backstab, "
      .. "Ambush or Mutilate +%d%% crit for 20 s. Pull the next mob inside those 20 s and open with %s; don't "
      .. "spend it on a stray Sinister Strike between pulls."):format(20 * remorse, hardest), remorseID)
  end

  local prio = section("In combat, top to bottom")
  if known(s, "Kick") then row(prio, "Kick", "Kick the moment the target casts (big icon).") end
  if known(s, "Gouge") and (known(s, "Mutilate") or (dagger(s) and known(s, "Backstab"))) then
    row(prio, "Gouge", ("Gouge, step behind, %s while it holds."):format(known(s, "Mutilate") and "Mutilate" or "Backstab"))
  end
  if known(s, "Slice and Dice") then
    row(prio, "Slice and Dice", "Slice and Dice when it's down (1-2 combo points), or with 2 s left. Why: +20% "
      .. "attack speed on both weapons for 25 energy, and your auto-attacks are a big share of your damage. "
      .. "Over a short pull that's about a 1-2 point Eviscerate's worth; it pays more the longer the fight, on "
      .. "elites, and once poisons (28+) proc off every hit. Skip it on a mob that's about to die.")
  end
  if known(s, "Venom") then row(prio, "Venom", ("Venom at %d combo points when it's down."):format(full)) end
  if known(s, "Rupture") then
    row(prio, "Rupture", talent(s, "Serrated Blades") and ("Rupture at %d, kept up (Serrated Blades)."):format(full)
      or (spec == "combat" and "Rupture: skipped (Eviscerate is better for Combat)."
      or ("Rupture at %d on elites and bosses; normal mobs die first."):format(full)))
  end
  if known(s, "Eviscerate") then
    row(prio, "Eviscerate", ("Eviscerate at %d combo points; earlier if the mob is nearly dead "
      .. "(combo points are lost when it dies)."):format(full))
  end
  if known(s, "Riposte") then row(prio, "Riposte", "Riposte after you parry.") end
  if known(s, "Mutilate") then row(prio, "Mutilate", "Mutilate to build: 2 combo points, from any side.") end
  if spec == "subtlety" then
    if known(s, "Ghostly Strike") then row(prio, "Ghostly Strike", "Ghostly Strike when it's ready.") end
    if known(s, "Hemorrhage") then row(prio, "Hemorrhage", "Hemorrhage to build.") end
  end
  if dagger(s) and known(s, "Backstab") then
    row(prio, "Backstab", "Backstab when you're behind (groups: /bw behind).")
  end
  if known(s, "Sinister Strike") then
    row(prio, "Sinister Strike", (known(s, "Mutilate") and "Sinister Strike if Mutilate isn't usable."
      or "Sinister Strike to build otherwise."))
  end

  local cds = section("Cooldowns (small icon)")
  if known(s, "Eureka!") then
    row(cds, "Eureka!", ("Eureka! at %d combo points: its 3 charges reach your finisher. Not while the "
      .. "mob casts (Kick uses a charge)."):format(eurekaCP(s)))
  end
  if known(s, "Cold Blood") then row(cds, "Cold Blood", ("Cold Blood right before a %d-point Eviscerate."):format(full)) end
  if known(s, "Adrenaline Rush") then row(cds, "Adrenaline Rush", "Adrenaline Rush when it's ready.") end
  if known(s, "Blade Flurry") then row(cds, "Blade Flurry", "Blade Flurry, best with two mobs.") end
  if known(s, "Preparation") then row(cds, "Preparation", "Preparation once Vanish and Evasion are used.") end
  if known(s, "Evasion") then row(cds, "Evasion", "Evasion when a fight goes wrong (your call).") end
  if #cds.rows == 0 then row(cds, nil, "None yet.") end

  local tal = section("Talents that shape this")
  local names = {}
  for name in pairs(Rogue.USED) do if talent(s, name) then names[#names + 1] = name end end
  table.sort(names)
  for _, name in ipairs(names) do row(tal, nil, ("%s %d: %s"):format(name, s.talents[name], Rogue.USED[name])) end
  if talent(s, "Relentless Strikes") then row(tal, nil, "Relentless Strikes: 5-point finishers refund 25 energy.") end
  if talent(s, "Ruthlessness") then row(tal, nil, "Ruthlessness: finishers often leave 1 combo point.") end
  if remorse > 0 then
    row(tal, nil, ("Remorseless Attacks %d: +%d%% crit on the first hit after a kill (20 s): chain pulls.")
      :format(remorse, 20 * remorse), remorseID)
  end
  if #tal.rows == 0 then row(tal, nil, "None that change what you press (/bw talents lists them all).") end

  local soon = section("Coming up")
  for _, c in ipairs(COMING) do
    if not known(s, c[2]) and c[1] >= (level or 0) then row(soon, c[2], ("Level %d: %s, %s."):format(c[1], c[2], c[3]), c[4]) end
  end
  if spec == "assassination" and not known(s, "Mutilate") then
    row(soon, "Mutilate", "20 points in Assassination: Mutilate, 2 combo points a press (the level 30 goal).", 1310707)
  end
  if #soon.rows == 0 then sections[#sections] = nil end
  return sections
end

-- The rotation path: one typical fight as icons, for the top of the guide.
-- Lanes: { label, steps }, step = { spell, id, note (under the icon), count
-- (×n) } or { text } (a word between icons, like "step behind"). The builder
-- count is fixed (a real fight can take one more or fewer), and it's split
-- around Eureka! the way the icon suggests it.
function Rogue.GuidePath(s, spec)
  local lanes = {}
  local function step(spell, note, count)
    return { spell = spell, id = s.spells[spell] and s.spells[spell].id, note = note, count = count }
  end
  local full = fullCP(s)
  local build = known(s, "Mutilate") and "Mutilate"
    or (spec == "subtlety" and known(s, "Hemorrhage") and "Hemorrhage") or "Sinister Strike"
  local per = build == "Mutilate" and 2 or 1
  local builds = math.ceil(full / per) -- presses to reach full combo points

  -- Opener.
  local first
  if dagger(s) and known(s, "Ambush") then first = "Ambush"
  elseif known(s, "Garrote") then first = "Garrote"
  elseif known(s, "Cheap Shot") then first = "Cheap Shot" end
  if first then
    local steps = {}
    if known(s, "Premeditation") then steps[#steps + 1] = step("Premeditation", "+2 pts") end
    steps[#steps + 1] = step(first, first == "Cheap Shot" and "stun" or "behind")
    lanes[#lanes + 1] = { label = "From stealth", steps = steps }
  end
  -- Remorseless Attacks: chain pulls.
  local remorse = s.talents and s.talents["Remorseless Attacks"] or 0
  if remorse > 0 then
    local hit = (dagger(s) and known(s, "Ambush") and "Ambush") or build
    lanes[#lanes + 1] = { label = "After a kill", steps = {
      { spell = "Remorseless Attacks", id = s.talentIDs and s.talentIDs["Remorseless Attacks"], note = "kill" },
      { text = "next pull, 20 s" }, step(hit, ("+%d%% crit"):format(20 * remorse)) } }
  end

  -- One cycle: Slice and Dice, build (Eureka! where its charges reach the
  -- finisher), Cold Blood, finisher.
  local steps = {}
  if known(s, "Slice and Dice") then steps[#steps + 1] = step("Slice and Dice", "1-2 pts") end
  local finish = known(s, "Eviscerate") and "Eviscerate"
  local eurekaAt = known(s, "Eureka!") and finish and math.max(0, math.ceil(eurekaCP(s) / per)) or nil
  local before = eurekaAt and math.min(eurekaAt, builds) or builds
  if before > 0 then steps[#steps + 1] = step(build, nil, before > 1 and before or nil) end
  if eurekaAt then
    steps[#steps + 1] = step("Eureka!", eurekaCP(s) <= 0 and "first" or ("at %d pts"):format(eurekaCP(s)))
    local after = builds - before
    if after > 0 then steps[#steps + 1] = step(build, nil, after > 1 and after or nil) end
  end
  if known(s, "Cold Blood") and finish then steps[#steps + 1] = step("Cold Blood", "crit") end
  if finish then steps[#steps + 1] = step(finish, ("at %d"):format(full)) end
  if known(s, "Slice and Dice") then steps[#steps + 1] = { text = "repeat" } end
  lanes[#lanes + 1] = { label = "Each cycle", steps = steps }

  -- Elites: Rupture before the Eviscerate cycle.
  if known(s, "Rupture") and (spec ~= "combat" or talent(s, "Serrated Blades")) then
    lanes[#lanes + 1] = { label = "Elites", steps = {
      step(build, nil, builds > 1 and builds or nil), step("Rupture", ("at %d"):format(full)),
      step(build, nil, builds > 1 and builds or nil), step("Eviscerate", ("at %d"):format(full)) } }
  end
  if known(s, "Kick") then
    lanes[#lanes + 1] = { label = "Mob casts", steps = { step("Kick", "any time") } }
  end
  local behind = known(s, "Mutilate") and "Mutilate" or (dagger(s) and known(s, "Backstab") and "Backstab")
  if known(s, "Gouge") and behind then
    lanes[#lanes + 1] = { label = "Gouge trick", steps = {
      step("Gouge", "front"), { text = "step behind" }, step(behind, "4 s window") } }
  end
  if dagger(s) and known(s, "Backstab") and build == "Sinister Strike" then
    lanes[#lanes + 1] = { label = "Behind (groups)", steps = {
      step("Backstab", "replaces SS", builds > 1 and builds or nil), step("Eviscerate", ("at %d"):format(full)) } }
  end
  return lanes
end

-- The next ability for `spec`, or nil when there's nothing to attack.
function Rogue.Next(s, spec)
  if not (s.target.exists and s.target.attackable) then return nil end
  local main = (s.stealthed and opener(s, spec)) or gougeWindow(s, spec) or finisher(s, spec) or builder(s, spec)
  if main and s.inRange == false then main.outOfRange = true end
  return main, cooldown(s, spec)
end
