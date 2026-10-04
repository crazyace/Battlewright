-- Battlewright: Slice and Dice, Rupture and Gouge timers, from your own casts.
-- On Forever, addons can't read auras in combat ("Auras cannot be accessed
-- when secret while tainted", BattlewrightProbe 2026-10-03), so the rotation
-- can't see these. Combo points are readable, though, so when you cast one,
-- its duration is estimated from the combo points you had (Classic's
-- durations), lengthened by talents the class file knows (Improved Slice and Dice).
local _, ns = ...

local Tracker = {}
ns.Tracker = Tracker

-- Seconds of each finisher by combo points spent.
Tracker.DURATION = {
  ["Slice and Dice"] = function(cp) return 6 + 3 * cp end, -- 9 / 12 / 15 / 18 / 21
  ["Rupture"] = function(cp) return 6 + 2 * cp end,        -- 8 / 10 / 12 / 14 / 16
  ["Gouge"] = function() return 4 end,
}
local ON_TARGET = { ["Rupture"] = true, ["Gouge"] = true } -- debuffs: kept per target (its GUID is readable)
local NO_CP = { ["Gouge"] = true } -- not a finisher: no combo points needed
-- Your casts that don't hit the target, so don't break its Gouge.
local HARMLESS = { ["Slice and Dice"] = true, ["Gouge"] = true, ["Sprint"] = true, ["Evasion"] = true,
  ["Vanish"] = true, ["Cold Blood"] = true, ["Adrenaline Rush"] = true, ["Blade Flurry"] = true,
  ["Premeditation"] = true, ["Preparation"] = true }

Tracker.lastCP = 0      -- combo points at the last state read (before a finisher spends them)
Tracker.expires = {}    -- [name] or [name .. "@" .. target GUID] = GetTime() when it runs out
Tracker.names = {}      -- [spellID] = name, filled by State.lua

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function targetGUID()
  local g = UnitGUID and UnitGUID("target")
  if g == nil or secret(g) then return nil end
  return g
end

local function key(name)
  if not ON_TARGET[name] then return name end
  local g = targetGUID()
  return g and (name .. "@" .. g) or name
end

function Tracker.IsDebuff(name) return ON_TARGET[name] == true end

function Tracker.Cast(spellID, now)
  if secret(spellID) then return end
  local name = Tracker.names[spellID]
  if name and not HARMLESS[name] then Tracker.expires[key("Gouge")] = nil end -- any hit wakes it up
  local duration = name and Tracker.DURATION[name]
  if duration and (Tracker.lastCP > 0 or NO_CP[name]) then
    local _, class = UnitClass("player")
    local classData = ns.Rotations[class]
    local scale = classData and classData.DurationScale and classData.DurationScale(name, ns.Talents.Get().ranks) or 1
    Tracker.expires[key(name)] = now + duration(Tracker.lastCP) * scale
  end
end

-- { [name] = seconds left } for buffs (onTarget false) or target debuffs (true).
function Tracker.Remaining(onTarget, now)
  local out = {}
  for name in pairs(Tracker.DURATION) do
    if (ON_TARGET[name] or false) == onTarget then
      local t = Tracker.expires[key(name)]
      if t and t > now then out[name] = t - now end
    end
  end
  return out
end

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit == "player" then Tracker.Cast(spellID, GetTime()) end
end)
-- Without a readable GUID a debuff can't be told apart per target: forget it.
ns:On("PLAYER_TARGET_CHANGED", function()
  if not targetGUID() then
    for name in pairs(ON_TARGET) do Tracker.expires[name] = nil end
  end
end)
-- Combat over: target debuffs are gone or don't matter.
ns:On("PLAYER_REGEN_ENABLED", function()
  for k in pairs(Tracker.expires) do
    if k:find("@") or ON_TARGET[k] then Tracker.expires[k] = nil end
  end
end)
