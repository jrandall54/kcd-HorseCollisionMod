"""Read the English lines of a vanilla bark set, offline.

`dialog:monologRequest` selects a **metarole**, which is a named bark set, and
the dialog system then picks which line of that set plays. So a set is only
usable when every one of its lines is acceptable at the moment it fires, and
the only way to know that without spending a ride is to read them all.

The chain is entirely in the shipped tables:

    metarole.xml       metarole_name -> metarole_id
    topictorole.xml    metarole_id   -> topic_id (many)
    text_ui_dialog.xml key "t<topic_id>_s<sentence>_<n>_<speaker>_<hash>"

The localization key carries the topic id in its first field, so no sequence or
sentence table is needed to go from a set to its text. The speaker slug in the
fourth field is the character who recorded the line, which is what decides
whether a given NPC can speak the set at all: holding the metarole is not the
gate, having the audio is.

Usage:

    python tools/bark_lines.py RANENY_NA_ZEMI
    python tools/bark_lines.py --grep "watch where"
    python tools/bark_lines.py --list PAIN
    python tools/bark_lines.py --speakers JINDRICH_NARAZIL_NA_MRTVOLY
"""

import argparse
import os
import re
import sys
import zipfile

GAME = os.environ.get("KCD_ROOT", r"C:\Games\Kingdom Come - Deliverance")
TABLES = os.path.join(GAME, "Data", "Tables.pak")
LOCALE = os.path.join(GAME, "Localization", "English_xml.pak")


def _read(pak, member):
	"""Read one member out of a .pak.

	The paks store their entries with backslash separators in the local file
	header while the central directory uses forward slashes, which zipfile
	rejects as a mismatch. Rewriting orig_filename before the read satisfies
	the check without touching the archive.
	"""
	zf = zipfile.ZipFile(pak)
	info = zf.getinfo(member)
	for spelling in (info.filename.replace("/", "\\"), info.filename):
		info.orig_filename = spelling
		try:
			with zf.open(info) as handle:
				return handle.read()
		except zipfile.BadZipFile:
			continue
	raise SystemExit("could not read %s from %s" % (member, pak))


def _rows(xml, *fields):
	"""Yield one tuple per <row>, pulling the named attributes."""
	pattern = re.compile(r"<row\s([^>]*)/>")
	attr = re.compile(r'(\w+)="([^"]*)"')
	for match in pattern.finditer(xml):
		values = dict(attr.findall(match.group(1)))
		yield tuple(values.get(f, "") for f in fields)


def metaroles():
	xml = _read(TABLES, "Libs/Tables/rpg/metarole.xml").decode("us-ascii", "replace")
	return {name: int(rid) for rid, name in _rows(xml, "metarole_id", "metarole_name") if rid}


def topics_by_metarole():
	xml = _read(TABLES, "Libs/Tables/text/topictorole.xml").decode("us-ascii", "replace")
	out = {}
	for mid, _role, topic in _rows(xml, "metarole_id", "role_id", "topic_id"):
		if mid and topic:
			out.setdefault(int(mid), set()).add(int(topic))
	return out


def lines():
	"""Every dialogue line, as (topic_id, speaker_slug, text)."""
	xml = _read(LOCALE, "text_ui_dialog.xml").decode("utf-8", "replace")
	row = re.compile(r"<Row><Cell>([^<]*)</Cell><Cell>[^<]*</Cell><Cell>([^<]*)</Cell></Row>")
	key = re.compile(r"^t(\d+)_s\d+_\d+_([^_]*(?:_[^_]*)*)_[A-Za-z0-9]{4}$")
	out = []
	for match in row.finditer(xml):
		name, text = match.group(1), match.group(2)
		m = key.match(name)
		if not m:
			continue
		out.append((int(m.group(1)), m.group(2), text))
	return out


def index():
	names = metaroles()
	by_role = topics_by_metarole()
	all_lines = lines()
	by_topic = {}
	for topic, speaker, text in all_lines:
		by_topic.setdefault(topic, []).append((speaker, text))
	return names, by_role, by_topic


def show(name, names, by_role, by_topic, speakers_only=False, limit=None):
	if name not in names:
		near = [n for n in names if name.upper() in n.upper()]
		print("no metarole named %s%s" % (name, ("; did you mean: " + ", ".join(near[:8])) if near else ""))
		return
	mid = names[name]
	topics = sorted(by_role.get(mid, ()))
	collected = []
	for topic in topics:
		collected.extend(by_topic.get(topic, ()))

	print("== %s  (metarole_id=%d, %d topic%s, %d line%s)"
			% (name, mid, len(topics), "" if len(topics) == 1 else "s",
				len(collected), "" if len(collected) == 1 else "s"))
	if not collected:
		print("   no recorded lines")
		return

	if speakers_only:
		tally = {}
		for speaker, _text in collected:
			tally[speaker] = tally.get(speaker, 0) + 1
		for speaker, count in sorted(tally.items(), key=lambda kv: -kv[1]):
			print("   %-24s %d" % (speaker, count))
		return

	longest = max(len(t) for _s, t in collected)
	print("   longest line: %d characters" % longest)
	seen = set()
	shown = 0
	for speaker, text in collected:
		if text in seen:
			continue
		seen.add(text)
		print("   [%-18s] %s" % (speaker, text))
		shown += 1
		if limit and shown >= limit:
			print("   ... %d more" % (len(set(t for _s, t in collected)) - shown))
			break


def main():
	ap = argparse.ArgumentParser(description=__doc__,
			formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("metarole", nargs="*", help="metarole name(s) to print")
	ap.add_argument("--list", metavar="SUBSTRING", help="list metarole names containing this")
	ap.add_argument("--grep", metavar="TEXT", help="find which metarole speaks a line of text")
	ap.add_argument("--speakers", action="store_true", help="tally who recorded the set instead of printing lines")
	ap.add_argument("--limit", type=int, default=None, help="stop after this many distinct lines")
	args = ap.parse_args()

	names, by_role, by_topic = index()

	if args.list is not None:
		for n in sorted(names):
			if args.list.upper() in n.upper():
				count = sum(len(by_topic.get(t, ())) for t in by_role.get(names[n], ()))
				print("%-46s %4d lines" % (n, count))
		return

	if args.grep:
		needle = args.grep.lower()
		topic_to_role = {}
		for role_name, mid in names.items():
			for topic in by_role.get(mid, ()):
				topic_to_role.setdefault(topic, []).append(role_name)
		hits = 0
		for topic, entries in by_topic.items():
			for speaker, text in entries:
				if needle in text.lower():
					owners = ",".join(topic_to_role.get(topic, ["<no metarole>"]))
					print("%-40s [%-16s] %s" % (owners, speaker, text))
					hits += 1
					if hits > 60:
						print("... more")
						return
		if not hits:
			print("no line matching %r" % args.grep)
		return

	if not args.metarole:
		ap.error("give a metarole name, --list, or --grep")

	for name in args.metarole:
		show(name, names, by_role, by_topic, args.speakers, args.limit)
		print()


if __name__ == "__main__":
	main()
