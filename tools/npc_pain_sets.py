"""Every NPC bark set that a horse could actually make a victim speak.

The question this answers: which metarole is the right register for being
knocked about by a horse at a middling speed? The set in use, `RANENY_NA_ZEMI`,
is vanilla's *dying* bark and reads far too strong. The obvious replacements,
`ZASAH_ZBRANI_SLABY` and `ZASAH_ZBRANI_SILNY`, cannot be driven at all: their
only sequences are gated on `var('hitStrength')`, a variable written by the
engine's own hit resolution and by nothing a mod can send.

So the filter that matters is not theme, it is reachability. A set is only
usable when **every** sequence behind **every** one of its topics carries the
always-true entry condition `'1'`. One gated sequence means the dialog system
can answer a request with a refusal, silently.

Reported per set:

    topics      how many topics the set holds
    lines       recorded lines across them
    wordless    lines that are the marker `<...>`, a grunt with no subtitle
    longest     words in the longest line, since the system picks the member
    gate        unconditional, or the condition that spoils it

    python tools/npc_pain_sets.py
    python tools/npc_pain_sets.py --max-words 4
    python tools/npc_pain_sets.py --grep ZASAH
"""

import argparse
import re
import sys

import bark_lines as B

WORDLESS = re.compile(r"^\s*(&lt;|<)\.\.\.(&gt;|>)\s*$")


def conditions():
	"""topic_id -> the set of entry conditions behind it, and its timeouts."""
	t2s = B._read(B.TABLES, "Libs/Tables/text/topic2sequence.xml")
	seq = B._read(B.TABLES, "Libs/Tables/text/sequence.xml")
	t2s = t2s.decode("utf-8", "replace")
	seq = seq.decode("utf-8", "replace")
	timeout_of = {}

	for sid, timeout in B._rows(seq, "sequence_id", "timeout"):
		timeout_of[sid] = timeout

	out = {}

	for topic, sid, cond in B._rows(t2s, "topic_id", "sequence_id",
			"entry_condition"):
		if not topic:
			continue

		entry = out.setdefault(int(topic), {"conds": set(), "timeouts": set()})
		entry["conds"].add(cond or "")
		entry["timeouts"].add(timeout_of.get(sid))

	return out


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--max-words", type=int, default=6,
			help="report only sets whose longest line is this short")
	ap.add_argument("--grep", help="only sets whose name contains this")
	ap.add_argument("--all", action="store_true",
			help="include sets with a gated sequence")
	args = ap.parse_args()

	names, by_role, by_topic = B.index()
	gates = conditions()
	rows = []

	for name, mid in names.items():
		if args.grep and args.grep.upper() not in name.upper():
			continue

		topics = sorted(by_role.get(mid, ()))
		lines, wordless, longest = [], 0, 0
		bad = set()

		for topic in topics:
			gate = gates.get(topic)

			if gate:
				for cond in gate["conds"]:
					if cond not in ("1", ""):
						bad.add(cond)

				if -1 in gate["timeouts"]:
					bad.add("timeout -1, once per playthrough")

			for _speaker, text in by_topic.get(topic, ()):
				lines.append(text)

				if WORDLESS.match(text):
					wordless += 1
				else:
					longest = max(longest, len(text.split()))

		if not lines:
			continue

		if longest > args.max_words:
			continue

		if bad and not args.all:
			continue

		rows.append((name, len(topics), len(lines), wordless, longest,
				sorted(bad), lines))

	rows.sort(key=lambda r: (r[4], -r[3]))
	sys.stdout.write("%d set(s), longest line <= %d words%s\n\n"
			% (len(rows), args.max_words,
				"" if args.all else ", every sequence unconditional"))

	for name, ntopics, nlines, wordless, longest, bad, lines in rows:
		sys.stdout.write("%-38s topics=%d lines=%d wordless=%d longest=%dw\n"
				% (name, ntopics, nlines, wordless, longest))

		for cond in bad:
			sys.stdout.write("    GATED  %s\n" % cond)

		seen = set()

		for text in lines:
			if text in seen:
				continue

			seen.add(text)
			sys.stdout.write("      %s\n" % text)

		sys.stdout.write("\n")


if __name__ == "__main__":
	main()
