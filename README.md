# Battlewright

What to press next: a rotation helper for **World of Warcraft: Forever**, and
the sibling of [Gearwright](https://github.com/crazyace/Gearwright) (Gearwright sorts out
your gear; Battlewright your fight).

> Status: **first draft, untested in game.** Rogue only (Assassination, Combat,
> Subtlety). Whether it can work on Forever at all depends on what the game lets
> addons read in combat: run `/bwp combat` with BattlewrightProbe first (below).

## What it shows

- A big icon: the next ability. Greyed out with a countdown while you wait for energy.
- A small icon beside it: a cooldown worth using now (Adrenaline Rush, Blade Flurry,
  Cold Blood).
- A line under it saying why ("Slice and Dice is down", "full combo points").

It shows in combat (and, with `/bw target`, when you target an enemy). If the game hides
the combat data it needs, it says so instead of guessing.

## Rogue priorities (first version)

1. From stealth: Ambush, Garrote or Cheap Shot (Combat opens with Cheap Shot).
2. Slice and Dice when it's down or about to fall off (2 s).
3. Rupture at full combo points on a target above 50% health (Assassination, Subtlety).
4. Eviscerate at full combo points (4 with Mutilate, else 5), or 3+ on a target under 25%.
5. Build: Riposte after a parry; Mutilate (Assassination), Ghostly Strike or Hemorrhage
   (Subtlety), else Sinister Strike.

The spec comes from your talents' spells (Mutilate, Hemorrhage, Blade Flurry...), or
`/bw spec`.

## Commands

| Command | Does |
|---|---|
| `/bw unlock`, `/bw lock` | Move the icon (drag it), then lock it |
| `/bw scale 1.2` | Icon size (0.5-2) |
| `/bw spec combat` | Play a spec regardless of talents (`auto` to go back) |
| `/bw target` | Also show out of combat with an enemy targeted |
| `/bw on`, `/bw off` | Turn it on or off |
| `/bw reset` | Put the icon back in the middle |

## Install

Copy the `Battlewright` folder into `Interface/AddOns/`.

## BattlewrightProbe (dev only)

A second addon in this repo that answers whether Battlewright can work on Forever: can an
addon read energy, combo points, buffs and debuffs (and their timers), cooldowns and spell
usability **during a fight**, or does the game hide them (`issecretvalue`)?

1. Copy `BattlewrightProbe` into `Interface/AddOns/` too.
2. `/bwp combat`, then fight something (a target dummy or a mob) for 10-30 seconds.
3. When combat ends it says what was readable and what was hidden. `/reload`, then send
   `/bwp export` or `WTF/Account/<ACCOUNT>/SavedVariables/BattlewrightProbe.lua`.
4. `python tools/probe_summary.py BattlewrightProbe.lua` prints the verdict.

The last 5 recordings are kept; `/bwp clear` empties them.

## Layout

```
Battlewright/
  Core/Init.lua        event bus, settings
  Core/State.lua       reads energy, combo points, auras, cooldowns (secret-aware)
  Core/Spec.lua        which spec to play
  Rotations/Rogue.lua  the priorities: pure functions of a state table
  UI/Display.lua       the icon
  Core/Commands.lua    /bw
BattlewrightProbe/            dev-only: what can an addon read in combat? (/bwp)
tools/probe_summary.py       summarises its recordings
tests/battlewright_test.py   runs both addons against a mocked WoW API
```

Tests: `pip install "lupa>=2.0"`, then `python tests/battlewright_test.py`.
Lint: `luacheck .`

## License

MIT, see [LICENSE](LICENSE).
