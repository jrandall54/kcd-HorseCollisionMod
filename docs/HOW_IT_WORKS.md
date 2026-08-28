# How it works

A plain-language overview of what this mod does and how it is put together. No
engine knowledge assumed. `TECHNICAL_DETAILS.md` covers the same ground at the
level needed to change it.

## What the mod does

Vanilla horse collisions produce a shout and nothing else. This mod reads the
horse's speed at the moment of contact and picks a reaction to match:

| Speed | Reaction |
| --- | --- |
| Walking | The NPC staggers, stays upright, takes no damage |
| Trot | The NPC is knocked down |
| Gallop | The NPC is knocked down harder |

The horse pays for it in stamina, more so during combat, and an exhausted horse
throws its rider.

## The approach

The first version was a physics hack: every impact applied a raw impulse and
threw a ragdoll, at any speed. This version tries to make collisions behave
like part of the game.

- Reactions are the game's own animations. The stagger, the knockdown and the
  rear-and-throw all exist in vanilla already.
- Speed thresholds come from measured in-game gaits, not round numbers. KCD
  horses have three speed plateaus, so the tiers sit in the gaps between them.
- The detection area is shaped like a horse, and was narrowed after logging
  where impacts were landing.
- Stamina limits how much is possible in one run, and costs more in combat, so
  charging into a fight is a decision rather than a default.
- Nothing is hardcoded. Every threshold, force and cost is a value at the top of
  one file.

## The three parts

**A timer loop, in Lua.** Roughly twenty times a second the mod asks the game
for everything near the player's horse, works out which of those are actually
underneath or in front of it, and decides what should happen to them.

**A reaction, per speed tier.** Knockdowns are physics: the NPC is given an
impulse and the game's ragdoll takes over. The walking-pace stagger is not
physics at all; it plays one of the game's own standing hit-reaction
animations, so the NPC keeps their feet and their dignity.

**Animation data.** The stagger is the part that needs new data, and it is the
reason this mod ships anything besides a script.

## Why the stagger needs new data

The game will play a chosen animation on an NPC on request, but only through a
narrow door. One Mannequin fragment, `AnimationControlled`, holds a list of
named options, and a request has to match one of those names. Vanilla's list is
30 object interactions: opening doors, cabinets, wardrobes, ringing an alarm
bell. Nothing that looks like being knocked into by a horse.

So the mod adds four options to that list, one per direction, each pointing at
a standing hit-reaction animation the game already contains. No new animation is
authored; the clips are the game's own.

## Why that is harder than it sounds

That list lives inside `kcd_male_database.adb`, a single 5.5 MB file. Mannequin
databases cannot be merged and no tool in the KCD ecosystem merges them.

The obvious approach is to ship a modified copy of the whole file. Before 2.1.0
this mod did exactly that, and it has a serious consequence: **two mods cannot
both do it.** Whichever loads later in `mod_order.txt` wins, the other's changes
vanish, and nothing is logged. Neither author finds out, and neither does the
player.

## What 2.1.0 does instead

Mannequin can assemble one database out of several. A database may say "also
load this other one", which means the vanilla file can be *pointed at* where it
already sits rather than copied.

So the mod ships its own small database. That file holds the option list, both
vanilla's 30 and the mod's 4, and refers to the untouched vanilla database for
everything else a person animates with. At startup the mod tells the human
character types to use it.

```
hcm_male_database.adb          the mod's file: 30 vanilla options + 4 new
  refers to kcd_male_database.adb    vanilla, untouched, inside its own pak
```

The 5.5 MB database is never copied and never replaced. The mod's own file is
72 KB, and the whole download is about 22 KB compressed against 195 KB before.

## What the mod does still replace

Two small declaration files:

| File | Size | Why |
| --- | --- | --- |
| `kcd_animationControlledTags.xml` | 1 KB | Lists the names an option may use, and the four new names have to be declared where the game looks. |
| `wh_female_fragmentids.xml` | 14 KB | Female characters have the same animations but no `AnimationControlled` list, so one has to be declared. |

If another mod replaces one of these, whichever loads later wins, as with any
file conflict in KCD. The loss is 15 KB of declarations rather than a whole
animation set, and it can be reconciled by hand.

## Verifying it

`python tools/verify_additive.py` checks every claim on this page against the
game's own data files and the packaged release.
