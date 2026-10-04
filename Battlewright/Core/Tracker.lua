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
  ["Venom"] = function(cp) return 6 + 3 * cp end,          -- 9 / 12 / 15 / 18 / 21
}
local ON_TARGET = { ["Rupture"] = true, ["Gouge"] = true } -- debuffs: kept per target (its GUID is readable)
local NO_CP = { ["Gouge"] = true } -- not a finisher: no combo points needed
-- Your casts that don't hit the target, so don't break its Gouge.
local HARMLESS = { ["Slice and Dice"] = true, ["Venom"] = true, ["Eureka!"] = true, ["Gouge"] = true, ["Sprint"] = true, ["Evasion"] = true,
  ["Vanish"] = true, ["Cold Blood"] = true, ["Adrenaline Rush"] = true, ["Blade Flurry"] = true,
  ["Premeditation"] = true, ["Preparation"] = true }

Tracker.lastCP = 0      -- combo points at the last state read
-- The combo points a finisher spent. The last state read isn't enough: the
-- game often spends them before it reports the cast, and a read in between
-- (10 a second) then sees 0, or 1 from Ruthlessness (beta, 2026-10-04:
-- Slice and Dice untracked, so it was asked for again and again and
-- Eviscerate never came up). So they're taken when you press the button
-- (UNIT_SPELLCAST_SENT), and as a fallback when the game's count drops.
Tracker.sent = {}       -- [castGUID] = combo points when the cast was sent
Tracker.spent = nil     -- { cp = before, at = GetTime() } when the count last dropped
local SPENT_WINDOW = 1.5
Tracker.expires = {}    -- [name] or [name .. "@" .. target GUID] = GetTime() when it runs out
Tracker.names = {}      -- [spellID] = name, filled by State.lua

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function targetGUID()
  local g = UnitGUID and UnitGUID("target")
  if secret(g) or g == nil then return nil end -- secret first: comparing one is an error
  return g
end

local function key(name)
  if not ON_TARGET[name] then return name end
  local g = targetGUID()
  return g and (name .. "@" .. g) or name
end

function Tracker.IsDebuff(name) return ON_TARGET[name] == true end

local function comboPoints()
  if not UnitPower then return nil end
  local cpType = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
  local cp = UnitPower("player", cpType)
  if secret(cp) or type(cp) ~= "number" then return nil end
  if cp == 0 and GetComboPoints then
    local c = GetComboPoints("player", "target")
    if not secret(c) and type(c) == "number" then cp = c end
  end
  return cp
end

-- Combo points the finisher behind `castGUID` spent.
local function spentBy(castGUID, now)
  local cp = castGUID and not secret(castGUID) and Tracker.sent[castGUID]
  if castGUID and not secret(castGUID) then Tracker.sent[castGUID] = nil end
  if cp and cp > 0 then return cp end
  if Tracker.spent and now - Tracker.spent.at <= SPENT_WINDOW then return Tracker.spent.cp end
  return Tracker.lastCP
end

function Tracker.Cast(spellID, now, castGUID)
  if secret(spellID) then return end
  local name = Tracker.names[spellID]
  if name and not HARMLESS[name] then Tracker.expires[key("Gouge")] = nil end -- any hit wakes it up
  local duration = name and Tracker.DURATION[name]
  local cp = duration and not NO_CP[name] and spentBy(castGUID, now) or 0
  if duration and (cp > 0 or NO_CP[name]) then
    local _, class = UnitClass("player")
    local classData = ns.Rotations[class]
    local scale = classData and classData.DurationScale and classData.DurationScale(name, ns.Talents.Get().ranks) or 1
    Tracker.expires[key(name)] = now + duration(cp) * scale
    Tracker.spent = nil
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

-- (Another unit's cast can arrive with hidden details: 1 of 9 events on the
-- beta, 2026-10-03 21:59. Skip those rather than compare a secret value.)
ns:On("UNIT_SPELLCAST_SENT", function(unit, _, castGUID)
  if secret(unit) or unit ~= "player" or secret(castGUID) or castGUID == nil then return end
  Tracker.sent[castGUID] = comboPoints()
end)
local lastCount
ns:On("UNIT_POWER_FREQUENT", function(unit, powerType)
  if secret(unit) or unit ~= "player" or secret(powerType) or powerType ~= "COMBO_POINTS" then return end
  local cp = comboPoints()
  if cp and lastCount and cp < lastCount then Tracker.spent = { cp = lastCount, at = GetTime() } end
  lastCount = cp
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
  if secret(unit) then return end
  if unit == "player" then
    Tracker.Cast(spellID, GetTime(), castGUID)
    if not secret(castGUID) and castGUID ~= nil then Tracker.sent[castGUID] = nil end
  end
end)
-- Without a readable GUID a debuff can't be told apart per target: forget it.
ns:On("PLAYER_TARGET_CHANGED", function()
  if not targetGUID() then
    for name in pairs(ON_TARGET) do Tracker.expires[name] = nil end
  end
end)
-- Combat over: target debuffs are gone or don't matter.
ns:On("PLAYER_REGEN_ENABLED", function()
  Tracker.sent = {} -- casts that never went through
  for k in pairs(Tracker.expires) do
    if k:find("@") or ON_TARGET[k] then Tracker.expires[k] = nil end
  end
end)
