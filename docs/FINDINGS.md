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

## Round 2 (to run)

`/bwp combat` now also tries, in combat: `C_UnitAuras.GetPlayerAuraBySpellID`,
`GetAuraDataBySpellName`, `AuraUtil.FindAuraByName`, `UnitHealthPercent`,
`UnitPowerPercent`, `GetPowerRegen`, `UnitGUID(target)`, `UnitCastingInfo` /
`UnitChannelInfo(target)` (for Kick), `C_Spell.IsSpellInRange`, Blizzard's own
rotation suggestion `C_AssistedCombat` (`IsAvailable`, `GetNextCastSpell`,
`GetRotationSpells`), and whether `UNIT_SPELLCAST_SUCCEEDED`, `UNIT_POWER_FREQUENT`,
`UNIT_AURA` and the combat log's arguments are readable.
