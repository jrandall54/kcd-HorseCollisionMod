"""The testing world: what this branch changes about the installed settings.

The problem this replaces. The test world used to be three PowerShell switches
with their values hard-coded in `dev_deploy.ps1`, applied by regex over the
installed settings file. Every new thing anybody wanted to change for a test
meant editing PowerShell, and the rider said so plainly after watching a
two-minute detour to flip two booleans:

    We built the fucking tool so you can easily switch testing environments
    that persist past save reloads. We built it. it works and I have fucking
    clue why you don't use it.

It also could not reach most of the mod any more. After the per-tier tables
landed, a setting like the gallop's stamina cost lives at
`StaminaDrainByTier.Gallop`, and a regex looking for `^\\tKey = value` cannot
see inside a table.

How it works now. Startup scripts are loaded in name order, so a file named
`HorseCollisionMod_TestWorld.lua` runs after `HorseCollisionMod_Settings.lua`
and can simply assign into the same global the settings file defines. The mod
then applies it through `ApplySettings` like anything else, with the same type
checking and the same rejection of unknown keys.

That means:

  * Nothing in the mod knows this exists, so nothing can ship it. The file is
    written into the development install only, and `build.ps1` packs from
    `src/`, which never contains it.
  * Nested keys work, because it is Lua rather than a regex.
  * The installed settings file is left byte-identical to the repository, so
    the deploy's own verification stays exact instead of having to allow for
    values it patched.
  * The world announces itself in `kcd.log` at load, so what is live is a
    matter of record rather than of memory.

The world is branch state, held in `.hcm_testworld` at the repository root and
untracked: it describes this machine's install, not the project. `flow.ps1
land` clears it, so a merged branch leaves nothing behind.

    python tools/testworld.py --list
    python tools/testworld.py --set CollisionIsCrime=true
    python tools/testworld.py --set StaminaDrainByTier.Gallop=0
    python tools/testworld.py --unset CollisionIsCrime
    python tools/testworld.py --preset stamina
    python tools/testworld.py --clear
    python tools/testworld.py --write "C:\\Games\\Kingdom Come - Deliverance"
"""

import argparse
import io
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(REPO_ROOT, ".hcm_testworld")
PRESETS = os.path.join(REPO_ROOT, "tools", "testworlds.ini")
INSTALLED = os.path.join("Data", "Scripts", "Startup",
		"HorseCollisionMod_TestWorld.lua")

# A key is a settings name, optionally one table member deep: `Key` or
# `Key.Member`. Two levels is all the settings file has and all it needs.
KEY = re.compile(r"^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?$")

# Values that are Lua source as typed. Everything else is quoted as a string,
# so a caller never has to think about shell quoting to set a name.
BARE = re.compile(r"^(?:true|false|nil|-?\d+(?:\.\d+)?|\{.*\}|\".*\"|'.*')$")


def read_presets():
	"""Named groups of overrides, as data rather than as code.

	Adding one is an edit to an ini file, which is the whole point: nobody
	should have to touch a script to describe a testing environment.
	"""
	out, current = {}, None

	if not os.path.exists(PRESETS):
		return out

	for line in io.open(PRESETS, encoding="utf-8"):
		bare = line.split("#")[0].strip()

		if not bare:
			continue

		header = re.match(r"^\[(\w+)\]$", bare)

		if header:
			current = header.group(1)
			out.setdefault(current, [])
			continue

		if current and "=" in bare:
			key, value = bare.split("=", 1)
			out[current].append((key.strip(), value.strip()))

	return out


def read_world():
	"""The overrides this branch is carrying, in the order they were added."""
	out = []

	if not os.path.exists(WORLD):
		return None

	for line in io.open(WORLD, encoding="utf-8"):
		bare = line.split("#")[0].strip()

		if not bare or "=" not in bare:
			continue

		key, value = bare.split("=", 1)
		out.append((key.strip(), value.strip()))

	return out


def write_world(pairs):
	lines = [
		"# The testing world for this branch. Written by tools/testworld.py,",
		"# applied by flow.ps1 test, and cleared by flow.ps1 land.",
		"#",
		"# Every line is one setting the development install overrides. A key",
		"# may name a table member: StaminaDrainByTier.Gallop = 0",
		"",
	]

	for key, value in pairs:
		lines.append("%s = %s" % (key, value))

	io.open(WORLD, "w", encoding="utf-8", newline="\n").write(
			"\n".join(lines) + "\n")


def merge(pairs, additions):
	"""Later wins, and a key keeps the position it was first given."""
	out = list(pairs)

	for key, value in additions:
		for index, (have, _old) in enumerate(out):
			if have == key:
				out[index] = (key, value)
				break
		else:
			out.append((key, value))

	return out


def lua_value(value):
	return value if BARE.match(value) else '"%s"' % value.replace('"', '\\"')


def lua_for(pairs):
	"""The override file, as Lua that assigns into the settings global.

	Guarded on the global existing. The settings file defines it, and if that
	has not run there is nothing to override and nothing worth failing over.
	"""
	body = [
		"-- The testing world for this branch, written by tools/testworld.py.",
		"--",
		"-- Not part of the mod. This file exists only in a development",
		"-- install; build.ps1 packs from src/, which never contains it.",
		"--",
		"-- Loaded after HorseCollisionMod_Settings.lua because startup",
		"-- scripts run in name order, so it can assign into the same global",
		"-- and be applied by ApplySettings with the same type checking.",
		"",
		'if type(HorseCollisionModSettings) == "table" then',
	]

	# A member key needs its parent table to exist first. The settings file
	# usually defines it, but a world may reach a table a player has deleted.
	parents = []

	for key, _value in pairs:
		if "." in key:
			parent = key.split(".")[0]

			if parent not in parents:
				parents.append(parent)

	for parent in parents:
		body.append('\tHorseCollisionModSettings.%s = '
				'HorseCollisionModSettings.%s or {}' % (parent, parent))

	if parents:
		body.append("")

	for key, value in pairs:
		body.append("\tHorseCollisionModSettings.%s = %s"
				% (key, lua_value(value)))

	shown = ", ".join("%s=%s" % (k, v) for k, v in pairs) or "none"

	body += [
		"",
		"\t-- Announced at load, so what is live is a matter of record rather",
		"\t-- than of memory. A test run against a world nobody could see is",
		"\t-- how a setting left on silently corrupts the next comparison.",
		'\tSystem.LogAlways("[HorseCollisionMod] test world: %s")' % shown,
		"end",
		"",
	]

	return "\n".join(body)


def main():
	ap = argparse.ArgumentParser(description=__doc__,
			formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--list", action="store_true", help="print the world")
	ap.add_argument("--set", action="append", metavar="KEY=VALUE", default=[],
			help="add or replace one override")
	ap.add_argument("--unset", action="append", metavar="KEY", default=[],
			help="remove one override")
	ap.add_argument("--preset", action="append", metavar="NAME", default=[],
			help="add every override in a named preset")
	ap.add_argument("--clear", action="store_true",
			help="carry no overrides, so the install runs shipped values")
	ap.add_argument("--reset", action="store_true",
			help="forget the world entirely, so the default preset returns")
	ap.add_argument("--write", metavar="GAMEROOT",
			help="write the world into a development install")
	ap.add_argument("--default", metavar="NAME", default="dev",
			help="the preset used when no world has been set (default: dev)")
	args = ap.parse_args()

	presets = read_presets()
	world = read_world()

	if args.reset:
		if os.path.exists(WORLD):
			os.remove(WORLD)

		world = None
		args.list = True

	# No world file at all means nobody has chosen one, so the default preset
	# applies. An empty world file is a choice: run the shipped values.
	if world is None and not args.clear:
		world = list(presets.get(args.default, []))

	if args.clear:
		world = []

	for name in args.preset:
		if name not in presets:
			sys.stderr.write("no preset named '%s'. Known: %s\n"
					% (name, ", ".join(sorted(presets)) or "none"))
			return 2

		world = merge(world, presets[name])

	for entry in args.set:
		if "=" not in entry:
			sys.stderr.write("--set wants KEY=VALUE, got '%s'\n" % entry)
			return 2

		key, value = entry.split("=", 1)
		key, value = key.strip(), value.strip()

		if not KEY.match(key):
			sys.stderr.write("'%s' is not a settings key\n" % key)
			return 2

		world = merge(world, [(key, value)])

	for key in args.unset:
		world = [(k, v) for k, v in world if k != key.strip()]

	if args.preset or args.set or args.unset or args.clear:
		write_world(world)

	# Printed after any change, because a switch whose effect you cannot see is
	# how a setting stays on through the next three tests.
	if args.list or not args.write:
		if world:
			for key, value in world:
				sys.stdout.write("  %s = %s\n" % (key, value))
		else:
			sys.stdout.write("  (no overrides, shipped values)\n")

	if args.write:
		target = os.path.join(args.write, INSTALLED)
		folder = os.path.dirname(target)

		if not os.path.isdir(folder):
			sys.stderr.write("no startup folder at %s\n" % folder)
			return 1

		if not world:
			# Removed rather than emptied. A file that assigns nothing still
			# loads, and one left behind from a previous branch is exactly the
			# silent leftover this is meant to prevent.
			if os.path.exists(target):
				os.remove(target)
				sys.stdout.write("  removed the installed test world\n")

			return 0

		io.open(target, "w", encoding="utf-8", newline="\n").write(
				lua_for(world))
		sys.stdout.write("  wrote %d override(s) to the install\n" % len(world))

	return 0


if __name__ == "__main__":
	sys.exit(main())
