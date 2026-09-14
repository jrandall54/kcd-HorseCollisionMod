"""Writes a console script that fires one unused Henry voice trigger.

    python tools/make_voice_probe.py 1

The audio-trigger path is the one route to Henry's voice that has never failed:
`entity:ExecuteAudioTrigger` is a direct call on the entity's audio proxy rather
than a message to a behaviour tree, so it answers to none of the dialogue
system's gates and plays even on a corpse two seconds dead. The mod already uses
it for the three impact grunts.

These are the rest of the Henry and generic-male vocalisations the game declares
and the dialogue system never offers. Several are cinematic one-offs recorded by
`tmck`, Henry's actor, which the game fires once in a scripted scene and never
again.

Each run validates the name with `Sound.GetAudioTriggerID` before firing, so a
name that does not exist is distinguishable from one that exists and is silent.
That distinction was missing from the dialogue auditions and cost a lot of time.

Fires through vanilla's own `PlayAudioTrigger(entity, name)` helper rather than
calling `ExecuteAudioTrigger` directly. The first version of this probe passed
the entity id where the call wants an audio proxy id, which reported
`fired=true` and made no sound at all -- including for `v_henry_hyje`, which
sits in the same `voices.xml` as the three grunts the mod plays successfully.
That control is what caught it: a trigger from the working file going silent
means the probe is wrong, not the trigger.
"""

import io
import os
import sys

# Ordered by how likely each is to read as a short reaction to hitting someone.
TRIGGERS = [
	("33487_henry_surprised", "Henry startled, from the fall cutscene"),
	("41745_tmck_ambush_voice_1", "Henry in the ambush scene, 1 of 4"),
	("41745_tmck_ambush_voice_2", "Henry in the ambush scene, 2 of 4"),
	("41745_tmck_ambush_voice_3", "Henry in the ambush scene, 3 of 4"),
	("41745_tmck_ambush_breathing_4", "Henry breathing hard, ambush scene"),
	("41745_ambush_voice_soldier_death_1", "a soldier dying, recorded by Henry's actor"),
	("24381_fight_os3", "offscreen fight voice, Henry drinking event path"),
	("v_henry_hyje", "Henry urging the horse on"),
	("v_henry_nostamina_sigh", "Henry out of breath"),
	("special_player_fainting", "the player fainting, on the stamina voice event"),
	("n_ge_snort", "a generic male snort"),
	("n_ge_spit", "a generic male spit"),
	("cin_man_hey", "a man shouting hey"),
	("cin_mam_dice_emotions", "a man reacting to a dice throw"),
	("v_player_drunked", "the player drunk"),
	("v_henry_deer_luring", "Henry luring a deer"),
	("speech_monitor_trigger", "the speech channel itself, declared in dialog.xml"),
]


def main():
	index = int(sys.argv[1])
	name, note = TRIGGERS[index - 1]

	script = '''local e = player
local id = Sound.GetAudioTriggerID("%s")
local fired = false
if id and type(PlayAudioTrigger) == "function" then
	fired = pcall(function() PlayAudioTrigger(e, "%s") end)
end
System.LogAlways("[HorseCollisionMod] VOICE %d %s valid=" .. tostring(id ~= nil)
		.. " helper=" .. type(PlayAudioTrigger) .. " fired=" .. tostring(fired))
''' % (name, name, index, name)

	out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "voice_probe_now.lua")
	io.open(out, "w", encoding="utf-8", newline="\n").write(script)
	print("%d/%d  %s  -- %s" % (index, len(TRIGGERS), name, note))


if __name__ == "__main__":
	main()
