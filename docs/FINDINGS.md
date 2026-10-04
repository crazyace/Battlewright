# What Forever lets addons read in combat

## Round 1 (2026-10-03 21:06, level 19 Rogue, 29 samples over ~15 s)

BattlewrightProbe `/bwp combat`; saved in `data/probe/2026-10-03-combat.json`.

| Call | In combat |
|---|---|
| `UnitPower(player, ComboPoints)`, `GetComboPoints` | readable |
| `C_Spell.GetSpellCooldown` | readable (`isOnGCD`, `startTime`, `duration`...) |
| `C_Spell.GetSpellPowerCost` | readable (Sinister Strike 45 energy) |
| `C_Spell.IsSpellUsable` | readable: `usable, notEnoughPower` |
| `IsStealthed`, `UnitCanAttack(target)`, `GetTime`, `UnitPowerMax(energy)` | readable |
| `UnitPower(player, Energy)` | **secret** |
| `UnitHealth(target)`, `UnitHealthMax(target)` | **secret** |
| `C_UnitAuras.GetAuraDataByIndex` (player buffs, target debuffs) | **blocked**: "Auras cannot be accessed when secret while tainted by 'BattlewrightProbe'" (worked once before combat started) |

What Battlewright does about it:

- **Energy:** uses `IsSpellUsable`'s "not enough power" to grey the icon; no countdown.
- **Target health:** unknown in combat, so no "finish early on a dying target".
- **Auras:** Slice and Dice and Rupture are tracked from your own casts
  (`UNIT_SPELLCAST_SUCCEEDED`), their length estimated from the combo points you had:
  Slice and Dice 6 + 3 x CP s, Rupture 6 + 2 x CP s (Classic). Talents that lengthen
  them aren't counted yet. Real aura data is used whenever the game allows it.

## Round 2 (2026-10-03 21:19, 44 samples)

Saved in `data/probe/2026-10-03-combat-2.json`. No call was blocked (the combat log
check, which caused "blocked from an action only available to the Blizzard UI" in an
earlier try, was removed).

| Call | In combat |
|---|---|
| `C_AssistedCombat.IsAvailable` | `false, "WRONG_WORLD_STATE_EXPRESSION"`: the API exists but Forever has the one-button assistant switched off; `GetNextCastSpell` / `GetRotationSpells` return nothing |
| `UNIT_SPELLCAST_SUCCEEDED` | readable: unit, cast GUID, **spell ID** (e.g. Sinister Strike 1758) |
| `UnitCastingInfo` / `UnitChannelInfo(target)` | readable (the mob didn't cast this time) |
| `C_Spell.IsSpellInRange` | readable |
| `UnitGUID(target)` | readable |
| `C_UnitAuras.GetPlayerAuraBySpellID`, `GetAuraDataBySpellName`, `AuraUtil.FindAuraByName` | no error (unlike by index), but returned nothing: not up, or hidden? Round 3 counts real answers |
| `UNIT_POWER_FREQUENT` | fires, readable (`player`, `ENERGY`), but carries no value |
| `UNIT_AURA` | fires; its update info is secret |
| `UnitHealthPercent`, `UnitPowerPercent`, `GetPowerRegen` | **secret** |

What Battlewright does with it: Kick when the target casts something interruptible
(shown big), "out of range" on the icon, Rupture timers kept per target GUID, and an
aura lookup by spell ID used whenever it answers.

## Round 3 (2026-10-03 21:24, 34 samples)

Saved in `data/probe/2026-10-03-combat-3.json`.

- **Aura lookups by spell ID or name don't work in combat either.**
  `GetPlayerAuraBySpellID`, `GetAuraDataBySpellName` and `AuraUtil.FindAuraByName`
  found nothing in all 34 samples, while `UNIT_AURA` reported an aura being added (its
  details secret). They don't error; they come back empty. Battlewright's cast-based
  tracker stays the source for Slice and Dice and Rupture.
- **The target's cast:** `UnitCastingInfo(target)` was readable-and-empty while the mob
  wasn't casting, and **secret in the 5 samples while it was**. So an addon can tell
  *that* the target is casting, not what or whether it can be interrupted. Battlewright
  now suggests Kick whenever the target casts, unless the game says it can't be
  interrupted.
- Everything else as in round 2.

## Showing what we can't read (2026-10-04)

EllesmereUI (supports Forever; all rights reserved, studied only) shows a Kick-ready
tick on cast bars and a shield on uninterruptible casts without reading either value.
Secret values can't be compared or used in addon code, but the game's widgets accept
them and draw them:

- `StatusBar:SetMinMaxValues` / `SetValue` take secret numbers (energy, a duration);
- `Region:SetAlphaFromBoolean(flag, alphaIfTrue, alphaIfFalse)` takes a secret boolean
  (e.g. `notInterruptible` from `UnitCastingInfo`);
- `C_Spell.GetSpellCooldownDuration` / `UnitCastingDuration` return duration objects,
  and `C_CurveUtil.EvaluateColorValueFromBoolean` turns a secret boolean into a color.

Battlewright now uses the first two: an energy bar under the icon fed straight from
`UnitPower`, and the Kick icon given `notInterruptible` through `SetAlphaFromBoolean`,
so the game hides it for casts that can't be interrupted.

## Round 4 (2026-10-03 21:33, 42 samples): settled

Saved (trimmed) in `data/probe/2026-10-03-combat-4.json`. You cast Slice and Dice x2,
Kick x2, Sinister Strike x4, Eviscerate x1.

- **Aura lookups return nothing in combat even while the aura is up.** Slice and Dice
  was cast twice, yet `GetPlayerAuraBySpellID`, `GetAuraDataBySpellName` and
  `AuraUtil.FindAuraByName` found nothing in all 42 samples. Battlewright's cast-based
  tracker is the only way to know your buffs and debuffs in combat.
- **The target's casts:** `UnitCastingInfo` was secret in 8 samples (the mob casting)
  and you Kicked twice: "secret = casting" holds.
- `IsSpellInRange` and `UnitGUID(target)` answered nothing once each (no target for a
  moment), readable otherwise.

What an addon can and can't use in combat on Forever is now known; see the tables
above. Further probing isn't needed for the Rogue rotation.
