# Battlewright

What to press next: a rotation helper for **World of Warcraft: Forever**, and
the sibling of [Gearwright](https://github.com/crazyace/Gearwright) (Gearwright sorts out
your gear; Battlewright your fight).

> Status: **first draft.** Rogue only (Assassination, Combat, Subtlety). In combat,
> Forever hides energy and target health from addons and blocks aura reads
> ([docs/FINDINGS.md](docs/FINDINGS.md)); Battlewright works around it: combo points,
> cooldowns and "not enough energy" are readable, and Slice and Dice / Rupture are
> tracked from your own casts.

## What it shows

- A big icon: the next ability. Greyed out while there isn't enough energy (with a
  countdown out of combat; Forever hides energy in combat).
- A small icon beside it: a cooldown worth using now (Adrenaline Rush, Blade Flurry,
  Cold Blood).
- An energy bar under it (the game draws it even though addons can't read energy in
  combat).
- A line under that saying why ("Slice and Dice is down", "full combo points").

It shows in combat (and, with `/bw target`, when you target an enemy). If the game hides
the combat data it needs, it says so instead of guessing.

## Built from your character

Battlewright's rotation is its own (Forever has no built-in one-button assistant), and
it's built from what you have:

- **Spells and ranks** you know (the spellbook). A spell you haven't learned is never
  suggested.
- **Talents**, read out of combat: the spec comes from where your points are, and
  talents change the rotation (see below). `/bw talents` lists which talents it uses,
  which don't change what you press, and Forever talents it doesn't know yet, with
  their in-game description, so they can be added.
- **Your main-hand weapon:** Ambush and Backstab only with a dagger. The game doesn't
  tell addons whether you're behind the target, so Backstab is suggested only after
  `/bw behind` (e.g. in a group, when the tank holds aggro), or while your Gouge
  holds the target (step behind it and Backstab). Any other hit ends the Gouge.

## Rogue priorities

The theory behind these (talents, builds, abilities by level, weapons) is in
[docs/ROGUE.md](docs/ROGUE.md).

1. In stealth: Premeditation first (as a cooldown) if talented, then Ambush (with a
   dagger, Assassination/Subtlety), Garrote or Cheap Shot (Combat).
2. Slice and Dice when it's down or about to fall off (2 s). In combat its timer is
   estimated from your cast: 6 + 3 s per combo point, +15% per rank of Improved Slice
   and Dice.
3. Venom (if talented) at full combo points when it's down.
4. Rupture at full combo points on a long fight: a target above 50% health, or, in
   combat where health is hidden, an elite or boss (Assassination, Subtlety, or any
   spec with Serrated Blades).
5. Eviscerate at full combo points (4 with Mutilate, else 5), or 3+ on a target under
   25% (when its health is readable).
6. Build: Riposte after a parry; Ambush out of stealth when Cutthroat allows it; Mutilate (Assassination), Ghostly Strike or
   Hemorrhage (Subtlety), Backstab (dagger + `/bw behind`, or after your Gouge), else Sinister Strike.
7. Cooldowns (small icon): Eureka! (Gnome racial) at 3 combo points (2 with Mutilate),
   so its 3 charges cover your finisher, Kick when the target casts (shown big; the game hides it
   for casts that can't be interrupted), Adrenaline Rush and Blade Flurry (Combat), Cold Blood at full combo
   points (Assassination), Preparation once Vanish and Evasion are used.

Out of melee range, the icon turns red and says so. Rupture's timer is kept per target.

## Commands

| Command | Does |
|---|---|
| `/bw unlock`, `/bw lock` | Move the icon (drag it), then lock it |
| `/bw scale 1.2` | Icon size (0.5-2) |
| `/bw spec combat` | Play a spec regardless of talents (`auto` to go back) |
| `/bw target` | Also show out of combat with an enemy targeted |
| `/bw behind` | Assume you're behind the target: suggest Backstab with a dagger |
| `/bw talents` | Your spec and talents, and how the rotation uses them |
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

`/bwp book` (out of combat) saves the text of every talent at every rank, every spell
in your spell book, and, with a trainer window open, every service the trainer lists.
Send it with `/bwp export`; it feeds docs/ROGUE.md.

## Layout

```
Battlewright/
  Core/Init.lua        event bus, settings
  Core/State.lua       reads energy, combo points, auras, cooldowns (secret-aware)
  Core/Tracker.lua     Slice and Dice / Rupture timers from your casts
  Core/Talents.lua     your talents, read out of combat (Forever's Traits tree)
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
