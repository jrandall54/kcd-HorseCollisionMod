# How it works

A plain-language overview of what this mod does and how it is put together. No
engine knowledge assumed. `TECHNICAL_DETAILS.md` covers the same ground at the
level needed to change it.

## What the mod does

Vanilla horse collisions produce a shout and nothing else. This mod reads the
horse's speed at the moment of contact and picks a reaction to match: a stagger
at a walk, an animated knockdown at a trot, and a physics throw at a gallop.
Two commanded moves, the rear and the charge, are tiers of their own. The
README's table gives all five.

The horse pays for it in stamina, more so during combat and more against an
armored target, and an exhausted horse throws its rider.

Armor is felt in the collision as well as in the stamina. A man in mail is
harder for a horse to move than a villager in cloth. A peasant is thrown clear;
a guard mostly goes down where he stood.

Being ridden down hurts, and enough of it kills. The mod applies that damage
itself, from the tier and the victim's armor. A bump costs nothing and a full
gallop usually kills an unarmored man. With `CollisionIsCrime` on, which is the
default, a collision that wounds is a crime, and guards respond to it.

That only holds if the mod is the one that kills. The game applies trample
damage of its own for a collision, and guards blame whoever lands the killing
blow, so a victim the trample finished would be charged to the player as murder
whatever `CollisionIsCrime` was set to.

So the trample cannot kill at all. Anyone the horse strikes is made briefly
immortal at the moment of contact, and the mod hands back whatever the engine
charged for the collision. The immortality lasts until the victim's body has
stopped moving, and the mod charges them at that same moment. The game bills a
thrown body for as long as it is moving, so waiting for the body to come to rest
is what makes the protection cover the whole collision and the mod's own blow
land last.

Impacts vary a little, so that two identical collisions are not identical. The
outcome is left to that arithmetic: a villager dies at a gallop because the
damage usually exceeds their health, and a knight survives because it usually
does not come close.

Characters the game will not let you attack are charged nothing at all. The mod
damages a victim by writing to their health, which is not the path vanilla
refuses when it declines to let the player swing at Captain Bernard, and which
ignores the game's own immortality flag. They are recognized by the protection
flags the game marks them with rather than by name, so a character protected
only for the span of one quest is covered too. They are still knocked down,
since that is the collision itself, and whatever the game charges them for it
is given straight back.

A badly hurt NPC left in the street would otherwise be taken over by the game's
own behavior for the wounded, which stands them still until they slowly heal.
The mod exempts anyone it knocks down from that, using the same mechanism the
game uses for its own characters, so a victim gets up and carries on.

A victim who hits the ground shows it afterwards. Their clothes pick up dirt,
and a harder blow draws more blood on whichever side of them the horse struck.
Both accumulate, so a man ridden down repeatedly gets steadily filthier. The
marks wear off once the victim's own routine takes them home. Nothing is marked
at walking pace, where nobody goes down.

A collision also makes a noise. There is no single sound in the game for a
horse hitting a person, so each tier builds one from layers. A shove at walking
pace is cloth and a body settling, a trot leads with a blunt impact, and a
gallop stacks several impacts over a dull heavy thud. What the impact sounds
like depends on what the victim is wearing, from the same armor the collision
already weighs.

Henry makes a noise too. The game records him taking a hit at three severities
and each tier uses one, so a shove at walking pace draws a small grunt and a
body taken at a gallop knocks the wind out of him. He stays quiet for a second
and a half afterwards, so riding into a crowd does not produce a grunt per
person. A heavier impact still gets through that silence.

When a collision kills somebody, he says something. "Oh fuck!", "Good God, what
a bloody mess.", "Jesus Christ, he was only a boy.", "He's still breathing but
he probably won't wake up again." Every line is the game's own, recorded by
Henry's voice actor for quests you may never have played. A death gets a line
and never a grunt as well.

An ordinary impact stays wordless. The lines Henry has are sentences, which suit
standing over a body and not a shove at walking pace, and the short exclamations
that would suit a shove are the ones the game will not play on request.

### What people say about it

Vanilla's answer to a horse walking into someone is one shout. The mod gives
the moment words, and every one of them is already in the game, spoken by that
character's own voice actor. No new audio ships: a vanilla bark set is named
and the game chooses a line from it.

A shove at walking pace draws a complaint: "Be a bit more careful!", "Hey!
Watch it!", "Jesus! Look where you're going!". Or a set that gets angrier the
more often the same person is shoved, which turns repeatedly barging somebody
into an argument rather than a repeated noise.

A knockdown speaks twice. The victim cries out at the moment of impact,
wordlessly, and then says something while getting back to their feet. What
they say then leans on the only lines the game has that mention a horse: "Learn
how to ride a horse, idiot!", "Watch where you're going, you lout! You nearly
killed me!", "That horse of yours nearly trampled me to death!"

Each moment draws from a pool rather than a single set, so the same collision
does not produce the same sentence twice running, and vanilla's own collision
bark is held off so the two do not talk over each other.

**With `CollisionIsCrime` on, the spoken reactions are mostly a walking-pace
feature.** A trot or gallop impact is a crime, and a victim of a crime is taken
over by the game's own crime and combat reactions: they call for the guards,
and that is what you hear instead. The mod suppresses the collision bark, which
is a different branch of the game's dialogue from the call for help. A stagger
is not a crime, so the walking-pace reactions work in every configuration.
Turning `CollisionIsCrime` off gives the spoken reactions at every speed.

A character whose voice never recorded a set says nothing, with no error, as in
vanilla, so some individuals are quieter than others.

### Losing patience

Barging the same person at walking pace costs nobody anything: no damage, no
stamina, no crime. Ridden into repeatedly, they run out of patience. The first
shove is free, and every one after that rolls against a chance that grows with
the count, until they turn and fight.

They try to drag you out of the saddle first, and the fight starts once you are
on the ground. During it, the mod shows the game's surrender prompt, so you can yield
rather than fight on.

That fight is not a crime. No fine is levied and no guard is summoned for the
provocation itself, because the message the mod sends is one the game's own
data marks as costing no reputation. A charge appears only if **you** swing,
and only if somebody sees it. Guards who witness the brawl wade in.

A guard shoved the same way arrests rather than brawls. That is the game's own
rule for soldiers and it is left alone.

Women do not fight back. The game refuses them the fight branch, so a woman
runs and fetches a guard instead, on the same count and the same roll.

The brawl ends when the victim's own state says it has ended, not on a timer.
Usually the game resolves the encounter itself; a victim who leaves the fight
and keeps running with you well clear is left to run, because that flee ends
by itself unless you follow.

### Rearing on command

A rear is what a rider has at a standstill, and it is on the mod's own keys:
`F` rears on the spot and `R` rears and drives forward. Both are the horse's own
animations and you stay in the saddle throughout.

The rear is its own tier. It hurts more than being knocked down at a trot,
sounds like hooves rather than a body, and plays the same fall as a trot.
Rearing again on someone already down hits them again without restarting their
fall. It brings the hooves down on whoever is directly in front, inside an arc
rather than on everyone nearby, and hits everybody standing in that arc.

The charge is its own tier too. The horse rears on the spot and is then driven
forward physically, so it collides with the world like any moving horse. It is
stopped by walls and fences instead of riding through them, and you can steer
it slightly on the way in. Everyone in a corridor in front of the horse goes
down, with no limit. Its damage, stamina cost, throw and the time it holds a
victim out of the next impact are all its own figures.

Bystanders a rear or a charge misses are frightened, and each decides for
themselves whether to run or turn on you.

Both moves refuse from anything faster than a standstill. The animation owns
the horse's position while it plays, so speed the horse already had fights it
and drags the horse visibly sideways.

The keys are chosen in the settings file from a fixed list, given in the README.
The mod cannot rebind a key while the game is running, so it declares every key
it might be asked for in advance and the settings pick which of them it listens
to. A key outside the list, or both moves put on one key, is reported in the
log rather than quietly doing nothing.

## The approach

- Reactions are the game's own animations. The stagger, the knockdown and the
  rear all exist in vanilla already.
- Speed thresholds come from measured in-game gaits, not round numbers. KCD
  horses have three speed plateaus, so the tiers sit in the gaps between them.
- The detection area is shaped like a horse.
- Stamina limits how much is possible in one run, and costs more in combat, so
  charging into a fight is a decision rather than a default.
- Every threshold, force and cost is a named setting, and players edit a
  separate file rather than the mod source.

## The parts

**A timer loop, in Lua.** Every `TickSeconds`, about thirty times a second, the
mod asks the game for everything near the player's horse, works out which of
those are actually underneath or in front of it, and decides what should happen
to them.

**A reaction, per tier.** The walking-pace stagger plays one of the game's own
standing hit-reaction animations, so the NPC keeps their feet. A trot plays an
animated fall and then hands the body to the game's physics partway through,
so the victim lands as the animation intended and is picked up afterwards the
way the game picks up anyone who has fallen. A gallop is physics from the
moment of impact: the victim is ragdolled and the engine's own collision throws
the body, with the mod's impulse as a small trim on top.

**Animation data.** The reactions need named animation options the game does
not declare, and they are the reason this mod ships anything besides a script.

**Handing the victim back.** Playing an animation on someone takes their body
away from them, and the game does not tell them so. Left alone they stand where
they fell, thinking they are somewhere else, until something makes the game
rebuild them. The mod watches for the animation finishing and rebuilds them
itself, so they get up and carry on.

## Why the reactions need new data

The game will play a chosen animation on an NPC on request, but only through a
narrow door. One Mannequin fragment, `AnimationControlled`, holds a list of
named options, and a request has to match one of those names. Vanilla's list is
object interactions: opening doors, cabinets, wardrobes, ringing an alarm bell.
Nothing that looks like being knocked into by a horse.

So the mod adds its own options to that list: a stagger, a knockdown and a fall
for each of four directions, and a settle. Each points at an animation the game
already contains. No new animation is authored. The horse gets its own options
the same way, for the rear and the charge.

## Why that is harder than it sounds

That list lives inside `kcd_male_database.adb`, a single large file. Mannequin
databases cannot be merged and no tool in the KCD ecosystem merges them.

Shipping a modified copy of the whole file has a serious consequence: **two
mods cannot both do it.** Whichever loads later in `mod_order.txt` wins, the
other's changes vanish, and nothing is logged.

## How the mod adds to it

Mannequin can assemble one database out of several. A database may say "also
load this other one", which means the vanilla file can be *pointed at* where it
already sits rather than copied.

So the mod ships its own small database. That file holds the option list,
vanilla's and the mod's, and refers to the untouched vanilla database for
everything else a person animates with. At startup the mod tells the human
character types to use it.

```
hcm_male_database.adb          the mod's file: vanilla's options and the mod's
  refers to kcd_male_database.adb    vanilla, untouched, inside its own pak
```

The same holds for the female database. The vanilla databases are never copied
and never replaced.

## What the mod does replace

Three small declaration files:

| File | Why |
| --- | --- |
| `kcd_animationControlledTags.xml` | Lists the names an option may use, and the new names have to be declared where the game looks. |
| `kcd_horse_fragmentids.xml` | Declares `AnimationControlled` for the horse, which vanilla declares only for people. |
| `kcd_horse_controllerdefs.xml` | Gives that fragment a scope, without which it can never play. |

If another mod replaces one of them, whichever loads later wins, as with any
file conflict in KCD. Each is a short list of declarations that can be
reconciled by hand. A file is safe to own only if it is a list of names that no
game patch rewrites; a copy of the game's own data overrides every later patch
to it.

## Verifying it

`python tools/verify_additive.py` checks the release's animation layout and
packaged file set against the game's own data files.
