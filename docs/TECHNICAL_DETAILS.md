# Technical Details

Notes on how this mod works and what the engine does or does not allow. Everything here
was verified by testing in game, not inferred. The build-by-build record is in
`docs/TESTING_DIARY.md`.

## Making an NPC play an animation

This is the hard part, and most of the obvious approaches do not work.

An NPC's body is driven by the animation system, which is in turn driven by the AI. Lua
cannot simply tell a skeleton what to do. The following were all tried and all failed:

| Approach | Result |
| --- | --- |
| `human:PlayAnim(fragment, tag)` | Call is accepted, nothing ever renders |
| `entity:AddImpulse` on a standing NPC | Ignored; actors are animation-driven, not physics-driven |
| `soul:DealDamage` with the player as attacker | Changes stat numbers only, no reaction |
| `hitReaction` brain message | Delivered, but handled by a tree that cannot drive the body |
| `combat:hit` brain message | Same |
| A `PlayAnimation` node added to `sb_switch_hitreactions.xml` | Node runs, animation fails |

The last one is worth explaining, because it looks like it should work. Behavior trees
named `sb_switch_*` are passive observers running alongside whatever the NPC is actually
doing. They react to events, send messages and set variables, but they do not own the
body. Across all 31 switch trees in the game there is not a single `PlayAnimation` node.
Warhorse never does this, which is why there was no working example to copy.

### What does work

`actor:StartInteractiveActionByName(name, objectId, updateVisibility, animSpeed)`

This is the call vanilla uses to make someone mime opening a door. It takes over the body,
plays a whole animation, and hands control back cleanly.

The catch is `name`. It is matched against the FragTags of exactly one Mannequin fragment,
`AnimationControlled`, and vanilla only ships object interactions there: `cabinet_o`,
`alarmBell`, `door_l_f_o` and so on. Passing a name that is not in that set is accepted
silently and aborts after a single frame, which looks like a one-frame twitch in game.

So the mod adds its own entries. Three kinds of file are involved, and every one is
required. Miss any of them and the call still succeeds while nothing plays.

1. **Fragment IDs** declare which fragments exist and point each at its tag definition file.
   `kcd_male_fragmentids.xml` already declares `AnimationControlled`, so it is left alone.
   `wh_female_fragmentids.xml` does not, so it is patched to add it.
2. **The tag definition** (`kcd_animationControlledTags.xml`) declares the valid FragTags.
   **A FragTags value that is not declared here does nothing**, even when the database entry
   exists. Both sexes share this file.
3. **The databases** hold the options. Ours point at
   `hitreaction_idle_medium_torso_stab_{front,back,left,right}`, standing hit reactions the
   game already contains. `kcd_male_database.adb` has an existing `AnimationControlled`
   block to append to; `wh_female_database.adb` has none, so the whole block is added.

`build_adb.py` generates all four modified files from the game's own paks. It checks that
every clip it references actually exists first, because a missing clip resolves to nothing
without any error.

## Pak packaging

Mod paks are zip files, and the entry names inside them must use forward slashes:

```
Libs/AI/final/x.xml     works
Libs\AI\final\x.xml     silently does nothing
```

CryEngine looks entries up by exact path. PowerShell's `Compress-Archive` writes Windows
separators, so a pak built with it fails to override anything.

This is easy to miss because `Scripts/Startup/*.lua` still works either way. That folder is
enumerated rather than looked up by path, so the Lua half of a mod loads normally while
every asset override silently fails. The log shows the pak opening successfully and there
is no error anywhere.

`build.ps1` builds the pak entry by entry through `System.IO.Compression` to avoid this,
and prints each entry name so the separators are visible.

Note also that the game's own paks store forward slashes in the central directory but
backslashes in the local file headers. Python's `zipfile` treats that as corruption and
refuses to read them, so `build_adb.py` inflates entries from the local header directly.

## Engine and Lua limits

- The `io` library is restricted. Scripts cannot write files.
- `os.clock()` returns nil. Use `System.GetCurrTime()`, which returns seconds as a float.
- Reading properties on C++ userdata entities outside `pcall` can throw fatal errors.
  Entities stream in and out constantly, so every engine call in this mod is wrapped.
- `soul:DealDamage(stamina, health, attacker, flag)` takes stamina first. Vanilla's own
  debug helper `Quick.lua` names the parameters health-first, which is wrong. Earlier
  builds of this mod dealt 25 health damage to the horse on every impact because of it.
  Use `soul:SetState` when adjusting a specific stat.
- Brain messages sent with `XGenAIModule.SendMessageToEntity` are not guaranteed to
  arrive. Handlers declared `Atomic="true"` drop messages while busy; measured delivery was
  about 3 in 19 under load. There is no return value to check.
- The behavior tree node `LogToConsole` does not write to `kcd.log`. Use an `ExecuteLua`
  node calling `System.LogAlways` instead.

A recurring theme: **most of these failures are silent**. A call returns without error, a
log line never appears, an animation simply does not play. Three separate times this
project drew a wrong conclusion from an unverified signal. Before concluding anything from
a signal, confirm the signal itself works.

## Timers and save reloads

KCD clears Lua timers when a save is loaded, but not always completely. A script that
starts a new timer loop on every load screen can end up with several running at once, which
costs performance and can disrupt audio.

The mod increments a counter on each load screen and passes that value into the timer
closure. Any loop whose value no longer matches the current one stops on its next
iteration, so at most one loop is ever live.

Detection runs at 100 ms. Each tick checks whether the player is mounted and moving at
least at walking pace before doing anything else, so the cost while on foot is negligible.

## Collision detection

`System.GetEntitiesInSphere` around the horse, filtered to living humans. The sphere is a
crude approximation of a horse's shape, which is why NPCs can react from slightly further
away than looks right. Replacing it with an oriented box is a known improvement.

A per-victim cooldown is required. The sphere is tested ten times a second, so without it
the same NPC's reaction restarts every tick and they never finish staggering.

## Speed tiers

KCD horses have three speed plateaus, not four. Telemetry across roughly 90 logged impacts
clustered at 2.05 to 3.74, 6.38 to 7.03, and 9.18 to 10.81 m/s. The thresholds sit in the
empty gaps between those clusters rather than at invented round numbers.
