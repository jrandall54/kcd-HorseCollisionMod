"""Enumerate the whole `alias` namespace offline, with lines, speakers and lengths.

`dialog:monologRequest` carries an `alias` field, and the diary proves it works:
sent to Henry with `alias = "dudeSurrender_combat"` he said "Shit, leave me be,
enough". An alias names **one topic**, which is much finer control than a
metarole: a metarole is a whole bark set and the dialog system chooses which of
its lines plays, whereas a topic holding a single short line is effectively a
line the mod chose.

The diary recorded the alias route as a dead end for two reasons, and the second
of them is wrong:

  * "the 861 known labels are almost entirely quest and scene scoped" -- true of
    the 861, and still true of most of what is here.
  * "Nor can more labels be recovered ... the alias namespace is only visible
    where vanilla's XML happens to reference it" -- **not true.** The namespace
    is a shipped column. `Libs/Tables/text/topic.xml` carries `label` next to
    `topic_id`, and it holds **1656 distinct labels** against the 861 that
    vanilla's AI files happen to mention. Around 795 aliases had never been seen
    by this project at all.

So this reads the column rather than the references:

    topic.xml           label -> topic_id           the alias namespace
    text_ui_dialog.xml  key "t<topic_id>_s<n>_<n>_<speaker>_<hash>"

The speaker slug in the fourth field of the key is the character who recorded
the line, and `bark_lines.py` records why that matters more than any holding
table: **having the audio is the gate**, not holding a role. So a line only
reaches Henry if Henry recorded it.

    python tools/bark_alias.py --speaker-tally
    python tools/bark_alias.py --henry --max-words 8
    python tools/bark_alias.py --grep "out of the way"
    python tools/bark_alias.py dudeSurrender_combat
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
	the check without touching the archive. Lifted from `bark_lines.py`, which
	documents the same quirk.
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


def aliases():
	"""label -> topic_id, straight out of the topic table's own column."""
	xml = _read(TABLES, "Libs/Tables/text/topic.xml").decode("us-ascii", "replace")
	out = {}

	for body in re.findall(r"<row\s([^>]*)/>", xml):
		attr = dict(re.findall(r'(\w+)="([^"]*)"', body))
		label = attr.get("label") or ""

		if label:
			out[label] = int(attr["topic_id"])

	return out


def lines_by_topic():
	"""topic_id -> [(speaker_slug, text)], every dialogue line in the game."""
	xml = _read(LOCALE, "text_ui_dialog.xml").decode("utf-8", "replace")
	row = re.compile(r"<Row><Cell>([^<]*)</Cell><Cell>[^<]*</Cell><Cell>([^<]*)</Cell></Row>")
	key = re.compile(r"^t(\d+)_s\d+_\d+_([^_]*(?:_[^_]*)*)_[A-Za-z0-9]{4}$")
	out = {}

	for raw_key, text in row.findall(xml):
		hit = key.match(raw_key)

		if not hit:
			continue

		out.setdefault(int(hit.group(1)), []).append((hit.group(2), text))

	return out


def words(text):
	return len(text.split())


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("label", nargs="?", help="one alias to print in full")
	ap.add_argument("--henry", action="store_true",
			help="only aliases Henry himself recorded")
	ap.add_argument("--speaker", help="only aliases this speaker slug recorded")
	ap.add_argument("--max-words", type=int,
			help="only aliases whose EVERY line is at most this many words")
	ap.add_argument("--grep", help="only aliases with a line matching this text")
	ap.add_argument("--speaker-tally", action="store_true",
			help="who records labelled topics, and how many")
	ap.add_argument("--limit", type=int, default=60)
	args = ap.parse_args()

	alias = aliases()
	by_topic = lines_by_topic()

	sys.stdout.write("%d labelled topics, %d topics carry dialogue lines\n\n"
			% (len(alias), len(by_topic)))

	if args.speaker_tally:
		tally = {}

		for label, topic in alias.items():
			for speaker, _text in by_topic.get(topic, ()):
				tally[speaker] = tally.get(speaker, 0) + 1

		for speaker, count in sorted(tally.items(), key=lambda kv: -kv[1])[:args.limit]:
			sys.stdout.write("%-28s %d\n" % (speaker, count))

		return

	if args.label:
		topic = alias.get(args.label)

		if topic is None:
			raise SystemExit("no such alias: %s" % args.label)

		sys.stdout.write("%s  topic=%d\n" % (args.label, topic))

		for speaker, text in by_topic.get(topic, ()):
			sys.stdout.write("   [%-20s] (%d words) %s\n"
					% (speaker, words(text), text))

		return

	# The filtered survey. A set is only usable if EVERY line in it passes, for
	# the reason `pick-bark-sets-by-line-length-not-just-fit` records: the mod
	# picks the topic and the dialog system still picks which of its lines
	# plays, so one long member spoils the whole alias.
	want = args.speaker or ("henry" if args.henry else None)
	shown = 0

	for label in sorted(alias):
		entries = by_topic.get(alias[label]) or []

		if not entries:
			continue

		if want and not any(want in s.lower() for s, _t in entries):
			continue

		if want:
			entries = [(s, t) for s, t in entries if want in s.lower()]

		if args.max_words and max(words(t) for _s, t in entries) > args.max_words:
			continue

		if args.grep and not any(args.grep.lower() in t.lower() for _s, t in entries):
			continue

		longest = max(words(t) for _s, t in entries)
		sys.stdout.write("%-44s topic=%-6d %d line(s), longest %d words\n"
				% (label, alias[label], len(entries), longest))

		for speaker, text in entries[:6]:
			sys.stdout.write("    [%-18s] %s\n" % (speaker, text))

		sys.stdout.write("\n")
		shown += 1

		if shown >= args.limit:
			sys.stdout.write("... stopping at %d\n" % args.limit)
			break

	if not shown:
		sys.stdout.write("nothing matched\n")


if __name__ == "__main__":
	main()
