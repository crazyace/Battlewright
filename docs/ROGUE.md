# Rogue on WoW: Forever (levels 1-30)

This is the working theory behind Battlewright's Rogue rotation and Gearwright's Rogue
advice. It covers the level 30 cap of the beta.

**Sources:**
- **Talent texts:** Forever's own, for every rank. They come from `/bwp book` on Sassy
  (Gnome, level 19, 2026-10-03).
- **Spell texts and costs:** from the same capture.
- **Trainer levels:** from verified trainer captures.
- **Estimates:** anything not in those captures is marked *(estimate)*.

## Points and rows

- **Talent points:** the first comes at level 10, then one per level, so you have
  **21 points at 30**.
- **Rows:** each row needs **5 more points in the same tree**. The game's own conditions
  confirm this: rows 2-7 need 5 / 10 / 15 / 20 / 25 / 30 points.
- **Row 5 at 30:** row 5 (Mutilate, Hack and Slash, Blade Flurry, Hemorrhage,
  Preparation, Vigor, Improved Kidney Shot) needs 20 points in that tree. That's only
  possible at 29-30, and only with almost every point in one tree.
- **Out of reach at 30:** rows 6-7 (Seal Fate, Aggression, Weapon Expertise, Quietus,
  Cutthroat, and the capstones Venom, Adrenaline Rush and Thousand Cuts).

**Prerequisites:**

| Talent | Needs |
|---|---|
| Lethality | Malice |
| Venom | Mutilate |
| Riposte | Deflection |
| Dual Wield Specialization | Precision |
| Weapon Expertise | Blade Flurry |
| Hemorrhage | Serrated Blades |
| Quietus | Dirty Deeds |
| Thousand Cuts | Preparation |

## Your abilities (level 19, Forever texts)

| Ability | Cost | What it does |
|---|---|---|
| Sinister Strike (R3) | 45 | Weapon damage + 10. 1 combo point |
| Backstab (R2) | 60 | **150% weapon damage + 30**. From behind, dagger in main hand. 1 CP |
| Ambush (R1) | 60 | **250% weapon damage + 70**. Stealthed **and behind**, dagger. 1 CP |
| Garrote (R1) | 50 | 144 over 18 s (+AP). Stealthed and behind. 1 CP |
| Gouge (R2) | 45 | 20 damage, incapacitates 4 s, **stops your auto-attack**. Target must face you. 10 s cooldown. 1 CP |
| Eviscerate (R3) | 35 | 101-115 at 5 points (+AP) |
| Slice and Dice (R1) | 25 | +20% attack speed, 9/12/15/18/21 s |
| Expose Armor (R1) | 25 | -450 armor at 5 points, 30 s |
| Kick (R1) | 25 | 15 damage, interrupt, 5 s school lockout. 10 s cooldown |
| Feint (R1) | 20 | Less threat. 10 s cooldown |
| Sap (R1) | 65 | 25 s incapacitate, humanoids out of combat |
| Evasion / Sprint | 0 | +50% dodge / +50% speed for 15 s. 5 min cooldown each |

**Gnome racials:**
- **Eureka!**, new on Forever: your next 3 attacks cost 10% less and hit 10% harder. 2 min
  cooldown.
- **Expansive Mind:** +5% max energy, so **105 energy**.
- **Escape Artist.**

Energy regeneration is **10 per second**.

**Damage per energy** (W = your main hand's average hit):
- **Sinister Strike:** (W + 10) / 45.
- **Backstab:** (1.5 W + 30) / 60.

With a level-20-ish dagger (W ≈ 20), that's **0.67 for Sinister Strike against 1.0 for
Backstab**. Backstab does about 50% more damage per energy whenever you can get behind.

**Abilities still to come:**

| Level | New |
|---|---|
| 20 | **Rupture**, Crippling Poison, Backstab 3 |
| 22 | **Vanish**, Sinister Strike 4, Garrote 2 |
| 24 | Eviscerate 4, Mind-numbing Poison |
| 26 | **Cheap Shot**, Ambush 2, Kick 2 |
| 28 | **Instant Poison II** (no rank 1 at the trainer), Backstab 4, Rupture 2, Feint 2 |
| 30 | **Kidney Shot**, **Deadly Poison**, Sinister Strike 5, Garrote 3 |

The first damaging poison comes at 28, so poison talents do nothing before then.

## Talents (Forever values)

**Assassination**

| Talent | Max rank | Verdict for 10-30 |
|---|---|---|
| Malice | +5% crit with attacks **and poisons** | Core |
| Remorseless Attacks | +40% crit on the next SS, Backstab, Ambush or Mutilate after a kill, 20 s | Great for chain pulls |
| Improved Gouge | Gouge +1.5 s | Optional: a longer Gouge → Backstab window |
| Ruthlessness | 60% chance a finisher leaves 1 combo point | Core |
| Murder | +4% damage, **Humanoids and Giants only** | Weaker than Classic, which also covered beasts |
| Improved Slice and Dice | +45% duration | Good. It's also the cleanest way to reach 20 points |
| Lethality | **+20%** crit damage on SS, Gouge, Backstab, Mutilate, Ghostly, Hemo | Core (Classic was +30%) |
| Relentless Strikes | 20% per combo point to get **25 energy** back (certain at 5) | Must-have |
| Improved Expose Armor | -10 energy, and refunds 2 combo points at 5 | Group tool |
| Cold Blood | Next SS, Backstab, Ambush, **Eviscerate** or Mutilate is +100% crit | Strong: a 5-point Eviscerate crit |
| Vile Poisons | Poisons +20% damage | 28+ only |
| Improved Poisons | +10% chance to apply poison, 50% chance an application doesn't use a charge | 28+ only |
| Vigor | +10 max energy | Filler for row 5 |
| Improved Kidney Shot | +10% damage taken while Kidney Shot stuns | Kidney Shot is level 30 |
| **Mutilate** | **Hits with both weapons for 75% damage + 13 each, +20% vs poisoned, 2 combo points** | **The level 30 goal** (see below) |
| Seal Fate | Builder crits: 100% chance of an extra combo point | Row 6: not at 30 |
| Venom | Finisher: poisons +30% damage, +10% chance to apply, 9-21 s | Row 7: not at 30 |

**Combat**

| Talent | Max rank | Verdict |
|---|---|---|
| Improved Eviscerate | **+20%** Eviscerate | Cheap row 1 points for any spec |
| Improved Sinister Strike | -5 energy on SS | Good while SS is your builder |
| Lightning Reflexes | +5% dodge | Survival |
| **Puncturing Wounds** (new) | **Backstab +30% crit, 45% chance of an extra combo point**; Mutilate +15% crit | Very strong for Backstab play (row 2) |
| Precision | +3% hit | Dual wield needs it |
| Deflection | +6% parry | Survival; leads to Riposte |
| Endurance | -60% Sprint and Evasion cooldown | Survival |
| Riposte | After a parry: 150% weapon damage, disarm 6 s | Situational |
| Improved Sprint | Sprint removes snares | PvP |
| Improved Kick | Kick silences for 2 s | PvP and casters |
| Flawless Execution (new) | Eviscerate -10 energy | Good (row 4) |
| Dual Wield Specialization | **+25%** off-hand damage | Good with a real off hand |
| Hack and Slash | Axe/Sword 5% extra attack, Dagger/Fist +5% crit, Mace ignores 15% armor | Row 5 |
| Blade Flurry | +20% attack speed and cleave, 15 s | Row 5 |

**Subtlety (short version)**

| Talent | Max rank | Verdict |
|---|---|---|
| Opportunity | +10% Backstab, Garrote, Ambush, Mutilate | 2 cheap points for dagger play (row 1) |
| Improved Ambush | +45% Ambush crit | Openers |
| Initiative | 100% chance of an extra combo point on Ambush, Garrote, Cheap Shot | Openers |
| Ghostly Strike | 125% weapon damage (**180% with a dagger**), +15% dodge, 1 CP | Openers and survival |
| Premeditation | 2 combo points from stealth | Openers |
| Serrated Blades | 9% armor ignore, Rupture +30% | Leads to Hemorrhage |
| Dirty Deeds | Cheap Shot and Garrote -20 energy; Garrote from the front | Openers |
| Hemorrhage | 100% weapon damage (**145% with a dagger**), Rupture +15% taken, 1 CP | Row 5 |
| Cutthroat, Quietus, Thousand Cuts | Backstab can enable Ambush; SS/Hemo +10% under 35% health; Rupture makes Backstab cheaper | Rows 6-7: not at 30 |

The rest of Subtlety is stealth and PvP utility.

## Mutilate: why it's the level 30 goal

Forever's Mutilate text names **no weapon type and no facing**. Backstab's and Ambush's
texts both spell out "must be behind" and "requires a dagger", so the absence looks
deliberate.

What that would mean:
- **Front-facing:** it works while the mob faces you, which is solo play.
- **Twice the combo points:** 2 per press.
- **Damage:** about 0.75 × (main hand + off hand) + 26, before the 20% poison bonus.
- **Cost:** not in the talent text. *(Estimate: 60, as in TBC.)*

At 60 energy that's 2 combo points per 60 energy, against Sinister Strike's 1 per 45. It
reaches a 4-point Eviscerate in **two presses instead of four**.

*To verify at 30:* does it need daggers in both hands, and what does it cost? If the game
refuses it with another weapon, Battlewright falls back to Sinister Strike by itself,
because it checks whether each spell is usable.

## Recommended build to 30

You have Malice 5, Remorseless Attacks 2 and Ruthlessness 3 (10 points at 19).

| Level | Point | Assassination total | Why |
|---|---|---|---|
| 20-24 | **Lethality 5** | 15 | +20% crit damage on everything you build with |
| 25 | **Relentless Strikes** | 16 | 25 energy back on every 5-point finisher |
| 26 | **Cold Blood** | 17 | A guaranteed 5-point Eviscerate crit every 3 min |
| 27-29 | **Improved Slice and Dice 3** | 20 | Fewer refreshes, and it unlocks row 5 |
| 30 | **Mutilate** | 21 | 2 combo points per press, from the front |

**If Mutilate turns out to need two daggers and you don't want that:** use the same
first 17 points, then **Improved Eviscerate 3 + Improved Sinister Strike 1** (Combat
row 1). You'd have Eviscerate +20% and cheaper Sinister Strikes for the level 30
Sinister Strike/Eviscerate grind.

## The three builds in the guide

`/bw guide` picks one of these for its Solo or Group tab and your weapons. It shows the
next point to spend, what's still to come by level, any points you've spent that the
build doesn't use, and the other builds as alternatives. Every order follows the tree's
rules; the tests check that.

| Build | Levels 10-30 (in order) | Picked for |
|---|---|---|
| **Assassination: Mutilate** | Malice 5, Ruthlessness 3, Remorseless Attacks 2, Lethality 5, Relentless Strikes, Cold Blood, Improved Slice and Dice 3, Mutilate | Solo with any weapon; groups without a main-hand dagger |
| **Backstab (dagger, groups)** | Improved Eviscerate 3, Improved Sinister Strike 2, **Puncturing Wounds 3**, Malice 5, Ruthlessness 3, Remorseless Attacks 2, Relentless Strikes, Lethality 2 | Groups with a main-hand dagger |
| **Combat: sturdy** | Improved Sinister Strike 2, Improved Eviscerate 3, Precision 3, Deflection 3, Riposte, Lightning Reflexes 3, Flawless Execution, Dual Wield Specialization 4, Blade Flurry | The alternative for anyone who'd rather not die; best with an off-hand weapon |

**Backstab build:** Puncturing Wounds needs 5 points in Combat before it. So the build
opens with Combat's cheap row 1 (Improved Eviscerate, Improved Sinister Strike), and
Backstab is critting 30% more by level 17. It gives up Cold Blood and Mutilate, so it's
weaker solo: you rarely get behind a mob that's facing you.

**Combat build:** it trades burst for staying alive (+6% parry, Riposte, +3% dodge), keeps
Sinister Strike cheap and Eviscerate strong, and takes Blade Flurry at 30. It doesn't
depend on your weapon type.

## How to play it (Battlewright follows this)

**Solo, the mob facing you:**

1. **Slice and Dice** on 1-2 combo points when it's down. Ruthlessness often hands you
   the point.
2. **Mutilate** at 30; before that, **Sinister Strike**.
3. **Eviscerate** at 5 combo points (4 with Mutilate, so a 2-point Mutilate isn't
   wasted). **Cold Blood** goes just before it.
4. **Rupture** only on elites and bosses.
5. **Eureka!** (2 min) at 3 combo points (2 with Mutilate). Its 3 charges then cover
   two builders and your full-combo-point Eviscerate. Every direct hit uses a charge,
   Kick and Gouge included; Garrote and Rupture (periodic) don't. So don't press it
   while the mob is casting.

**Stealth:** walk behind the mob, then **Ambush** with a dagger, else **Garrote**.
Remorseless Attacks makes the opener after a kill likely to crit, and it lasts 20 s, so
chain pulls.

**Gouge → step behind → Backstab:** Gouge stops your auto-attack, so nothing breaks it
until your next ability. Battlewright suggests Backstab during the Gouge (Mutilate first,
once you have it).

**Groups:** stand behind and use `/bw behind`. Backstab, at about 50% more damage per
energy, becomes your builder.

## Weapons

- **Dagger main hand:** needed for Ambush, Backstab and Gouge → Backstab. Every one of
  them scales with weapon damage (150-250%), so **a slow, high-damage dagger** is best.
- **Off hand:**
  - **Mutilate** uses 75% of it.
  - **Dual Wield Specialization** (Combat) adds up to 25% of it.
  - **Poisons from 28** proc from it.
- **Sword, mace or axe main hand:** only Sinister Strike and Eviscerate. That's fine for
  pure Sinister Strike play, and Hack and Slash rewards it from row 5. But it gives up
  Ambush and Backstab.
