"""Builds the mod page's settings block out of the settings file itself.

`pre_release_check.py` compares the `[code]` block on the Nexus page against the
keys that ship, and a page written by hand falls behind the moment a setting is
added. There were 150 missing at the 5.10.0 audit. So the block is generated
instead: the settings file is the single source, and its own inline comments
become the descriptions.

Only the player-facing half is emitted. Everything after the banner in the
settings file is exposed for completeness -- internals, timings measured against
an animation, switches with one sensible value -- and belongs in the repository
documentation rather than on a page someone reads before downloading. That is
the same boundary `check_nexus_page` applies.

Section headings come from the settings file's own comment blocks, so the page
is ordered the way the file a player edits is ordered.

    python tools/nexus_settings_block.py              # print the block
    python tools/nexus_settings_block.py --check      # compare with the page
"""

import argparse
import io
import os
import re
import sys

SETTINGS = os.path.join("src", "HorseCollisionMod_Settings.lua")
PAGE = "nexus_description.txt"
BANNER = "\t-- ====="


def read(path):
	return io.open(path, encoding="utf-8", errors="replace").read()


def player_facing():
	"""The settings a player is meant to touch, in file order, with comments.

	Yields ("section", text) and ("setting", name, value, description). A
	section is a comment block sitting on its own above a run of settings; a
	description is the trailing comment on the setting's own line, plus any
	continuation lines under it.
	"""
	text = read(SETTINGS)

	# Start at the table itself. The file opens with a comment block explaining
	# how to edit it, which is prose about the file rather than a group of
	# settings inside it, and reading from the top turns it into a heading.
	opening = text.find("HorseCollisionModSettings = {")

	if opening != -1:
		text = text[opening:]

	banner = text.find(BANNER)

	if banner != -1:
		text = text[:banner]

	lines = text.split("\n")
	out = []
	pending = []
	# Lines already folded into a setting's trailing comment. Without this the
	# loop visits them again and emits each one a second time as a heading.
	eaten = set()

	for i, line in enumerate(lines):
		if i in eaten:
			continue

		bare = line.strip()

		# A comment line on its own: either a section heading or prose about the
		# setting underneath. Held until the next setting decides which.
		if bare.startswith("--") and "=" not in line.split("--")[0]:
			pending.append(bare.lstrip("- ").strip())
			continue

		m = re.match(r"^\t([A-Za-z_]\w*)\s*=\s*(.+?)\s*(?:--\s*(.*))?$", line)

		if not m:
			# A blank line ends a comment block, which makes it a section.
			if not bare and pending:
				out.append(("section", " ".join(pending)))
				pending = []

			continue

		name, value, own = m.group(1), m.group(2).rstrip(","), m.group(3) or ""

		# A setting whose value is a table is listed as its members rather
		# than as a bare "{", which is what the page showed before and told a
		# player nothing. Rendered inline so the row stays one row: the page
		# is checked by setting name, and a member per row would need a name
		# with a dot in it that check_nexus_page cannot match.
		if value == "{":
			members = []
			j = i + 1

			while j < len(lines) and not lines[j].strip().startswith("}"):
				body = lines[j].split("--")[0]

				for key, val in re.findall(r"(\w+)\s*=\s*([^,]+)", body):
					members.append("%s %s" % (key, val.strip()))

				eaten.add(j)
				j += 1

			eaten.add(j)
			value = ", ".join(members)

		# Continuation of the trailing comment: a following line whose only
		# content is a comment aligned past the value column.
		j = i + 1

		while j < len(lines):
			cont = re.match(r"^\s{20,}--\s*(.*)$", lines[j])

			if not cont:
				break

			own += " " + cont.group(1).strip()
			eaten.add(j)
			j += 1

		if pending:
			out.append(("section", " ".join(pending)))
			pending = []

		out.append(("setting", name, value, own.strip()))

	return out


def block():
	rows = player_facing()
	width = max(len(r[1]) for r in rows if r[0] == "setting") + 2
	vwidth = min(24, max(len(r[2]) for r in rows if r[0] == "setting") + 2)
	lines = []

	for row in rows:
		if row[0] == "section":
			# A heading sits at the left margin; check_nexus_page reads an
			# unindented word as a heading rather than as a setting.
			text = row[1]

			if len(text) > 78:
				text = text[:75].rstrip() + "..."

			lines.append("")
			lines.append(text)
			continue

		_kind, name, value, desc = row
		desc = desc[:1].upper() + desc[1:] if desc else ""
		lines.append("  %-*s%-*s%s" % (width, name, vwidth, value, desc))

	return "\n".join(lines).strip("\n")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--check", action="store_true",
			help="report which player-facing settings the page is missing")
	args = ap.parse_args()

	if not args.check:
		sys.stdout.write(block() + "\n")
		return

	page = read(PAGE) if os.path.exists(PAGE) else ""
	found = re.search(r"\[code\](.*?)\[/code\]", page, re.S)
	listed = set(re.findall(r"^[ \t]{2,}(\w+)\s{2,}", found.group(1), re.M)) \
			if found else set()
	shipped = set(r[1] for r in player_facing() if r[0] == "setting")

	sys.stdout.write("player-facing settings: %d   on the page: %d\n"
			% (len(shipped), len(shipped & listed)))

	for key in sorted(shipped - listed):
		sys.stdout.write("   missing from the page: %s\n" % key)

	for key in sorted(listed - shipped):
		sys.stdout.write("   on the page but not player-facing: %s\n" % key)


if __name__ == "__main__":
	main()
