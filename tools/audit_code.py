"""Mechanical audit of the mod's Lua: settings, functions and tables nobody uses.

Everything here is a fact about the source rather than a judgement about it.
Three questions, each of which has produced real clutter before:

  * **Settings.** A key in `Config` that no file ever reads is dead weight in the
    player's settings file. A key in the settings file that `Config` does not
    declare is rejected by `ApplySettings` at load and does nothing.
  * **Functions.** A `HorseCollisionMod:Name()` that nothing calls is dead, with
    the caveat that the entry point and the console tools call some by name.
  * **Module tables.** A `HorseCollisionMod.Name = {...}` nothing indexes is the
    same problem one level up, and bark pools have been left behind this way.

Read as a starting list, not a verdict: a name may be reached from a tool, from
a console script or from a string. Every hit is reported with its line so it can
be checked.

    python tools/audit_code.py
    python tools/audit_code.py --settings
"""

import argparse
import io
import os
import re
import sys

SRC = "src"
ENTRY = os.path.join(SRC, "HorseCollisionMod.lua")
SETTINGS = os.path.join(SRC, "HorseCollisionMod_Settings.lua")


def lua_files():
	out = [ENTRY, SETTINGS]

	for name in sorted(os.listdir(os.path.join(SRC, "HorseCollisionMod"))):
		if name.endswith(".lua"):
			out.append(os.path.join(SRC, "HorseCollisionMod", name))

	return out


def read(path):
	return io.open(path, encoding="utf-8", errors="replace").read()


def strip_comments(text):
	"""Comments hold plenty of names; counting them as uses hides dead code."""
	return re.sub(r"^\s*--.*$", "", text, flags=re.MULTILINE)


def config_keys(text):
	"""The top-level keys of the Config table, with the line each sits on.

	Only depth one counts. A nested table such as `ImpactDamageByTier` holds
	keys named `Walk` and `Gallop`, and counting those as settings reports them
	as unread every time, because nothing reads them under that name.
	"""
	anchor = ("HorseCollisionMod.Config" if "HorseCollisionMod.Config" in text
			else "HorseCollisionModSettings")
	start = text.index(anchor)
	body = text[start:]
	before = text[:start].count("\n")
	depth, out = 0, {}

	for line_no, line in enumerate(body.split("\n"), 1):
		m = re.match(r"^\t([A-Za-z_]\w*)\s*=", line)

		if m and depth == 1:
			out.setdefault(m.group(1), line_no + before)

		depth += line.count("{") - line.count("}")

		if depth <= 0 and out:
			break

	return out


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--settings", action="store_true", help="settings only")
	args = ap.parse_args()

	files = lua_files()
	bodies = {p: read(p) for p in files}
	code = {p: strip_comments(t) for p, t in bodies.items()}
	everything = "\n".join(code.values())

	cfg = config_keys(bodies[ENTRY])
	in_settings = set(config_keys(bodies[SETTINGS]))

	# A setting is used when something reads it off a table, which in this code
	# is always `cfg.Name`, `self.Config.Name` or `Config.Name`.
	dead_cfg = []

	for key, line in sorted(cfg.items()):
		uses = len(re.findall(r"(?:cfg|Config|settings)\s*[.\[]\s*[\"']?%s\b" % key,
				everything))

		if uses == 0:
			dead_cfg.append((key, line))

	print("Config keys: %d    declared in the settings file: %d"
			% (len(cfg), len(in_settings & set(cfg))))
	print("\n== Config keys nothing reads (%d) ==" % len(dead_cfg))

	for key, line in dead_cfg:
		print("   %-34s HorseCollisionMod.lua:%d" % (key, line))

	orphan = sorted(in_settings - set(cfg) - {"HorseCollisionModSettings"})
	print("\n== Settings-file keys Config does not declare (%d) ==" % len(orphan))

	for key in orphan:
		print("   %s" % key)

	missing = sorted(set(cfg) - in_settings)
	print("\n== Config keys absent from the settings file (%d) ==" % len(missing))

	for key in missing:
		print("   %s" % key)

	if args.settings:
		return

	# Functions and module tables.
	defined = {}

	for path, text in bodies.items():
		for m in re.finditer(r"^function HorseCollisionMod[:.](\w+)", text,
				re.MULTILINE):
			defined[m.group(1)] = "%s:%d" % (os.path.basename(path),
					text[:m.start()].count("\n") + 1)

	tools = ""

	for root, _dirs, names in os.walk("tools"):
		for name in names:
			if name.endswith((".lua", ".py", ".ps1")):
				tools += read(os.path.join(root, name))

	dead_fn = []

	for name, where in sorted(defined.items()):
		calls = len(re.findall(r"[:.]%s\s*\(" % name, everything))
		# One hit is the definition itself.
		if calls <= 1 and ('"%s"' % name) not in everything \
				and name not in tools:
			dead_fn.append((name, where))

	print("\n== Functions nothing calls (%d of %d) ==" % (len(dead_fn),
			len(defined)))

	for name, where in dead_fn:
		print("   %-32s %s" % (name, where))

	tables = {}

	for path, text in bodies.items():
		for m in re.finditer(r"^HorseCollisionMod\.(\w+)\s*=\s*\{", text,
				re.MULTILINE):
			tables[m.group(1)] = "%s:%d" % (os.path.basename(path),
					text[:m.start()].count("\n") + 1)

	dead_tbl = []

	for name, where in sorted(tables.items()):
		if name == "Config":
			continue

		uses = len(re.findall(r"(?:self|HorseCollisionMod)\.%s\b" % name,
				everything))

		if uses <= 1 and name not in tools:
			dead_tbl.append((name, where))

	print("\n== Module tables nothing indexes (%d of %d) ==" % (len(dead_tbl),
			len(tables)))

	for name, where in dead_tbl:
		print("   %-32s %s" % (name, where))


if __name__ == "__main__":
	main()
