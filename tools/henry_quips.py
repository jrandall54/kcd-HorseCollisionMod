"""Every short line Henry recorded that the mod can actually address, exhaustively.

The question this answers is the rider's: what can Henry be made to *say* on an
impact, as opposed to grunt. Guessing phrases and grepping for them proved
useless -- ten guesses, ten misses -- so this enumerates instead.

Three facts set the shape of it, all established in the diary:

  * **Having the audio is the gate.** The speaker slug in the fourth field of a
    `text_ui_dialog` key is who recorded the line, and a line only reaches Henry
    if Henry recorded it. Holding a role is not the gate.
  * **A line must be addressable.** Two schemes work from Lua and no others:
    `metarole` on a `dialog:monologRequest`, which names a whole bark set and
    lets the dialog system pick the line, and `alias`, which names one topic by
    the `label` column of `Libs/Tables/text/topic.xml`. `topicId` and
    `StartMonolog` are both proven dead.
  * **Every line in the set has to be acceptable**, because the mod chooses the
    set and the system still chooses the line. So a topic is reported with its
    longest member, and a metarole with the longest line in any of its topics.

Output is grouped by how the line would be requested, because that decides
whether it is usable at all:

    alias      one topic, so the wording is nearly pinned
    metarole   a set, so every member has to pass

    python tools/henry_quips.py --max-words 5
    python tools/henry_quips.py --max-words 6 --alias-only
    python tools/henry_quips.py --metarole-only --max-words 4
"""

import argparse
import re
import sys

import bark_lines as B

# Henry's recorded slugs, from a tally of who records labeled topics:
# henry_0 through henry_4 and p_henry_he. Matched as a prefix rather than a
# fixed list so a slug this project has not seen is not silently dropped.
HENRY = re.compile(r"^(p_)?henry")


def aliases():
	"""label -> topic_id, the alias namespace, straight out of topic.xml.

	1656 labels ship here against the 861 that vanilla's AI files happen to
	reference, so this is the authority rather than a scrape of the brain files.
	"""
	xml = B._read(B.TABLES, "Libs/Tables/text/topic.xml").decode("us-ascii", "replace")
	out = {}

	for topic, label in B._rows(xml, "topic_id", "label"):
		if topic and label:
			out[int(topic)] = label

	return out


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--max-words", type=int, default=5,
			help="a topic qualifies only if EVERY Henry line in it is this short")
	ap.add_argument("--alias-only", action="store_true")
	ap.add_argument("--metarole-only", action="store_true")
	args = ap.parse_args()

	names, by_role, by_topic = B.index()
	label_of = aliases()

	# metarole_id -> name, inverted once so a topic can name its set.
	name_of = {}

	for name, mid in names.items():
		name_of[mid] = name

	# topic -> the metaroles that reach it.
	sets_of = {}

	for mid, topics in by_role.items():
		for topic in topics:
			sets_of.setdefault(topic, set()).add(mid)

	# Henry's lines per topic, and the longest member of the whole topic --
	# including lines he did not record, because the dialog system may pick one.
	henry_topics = {}

	for topic, entries in by_topic.items():
		mine = [t for s, t in entries if HENRY.match(s)]

		if not mine:
			continue

		if max(len(t.split()) for t in mine) > args.max_words:
			continue

		henry_topics[topic] = {
			"lines": sorted(set(mine)),
			"longest_any": max(len(t.split()) for _s, t in entries),
			"others": len(entries) - len(mine),
		}

	by_alias = {t: d for t, d in henry_topics.items() if t in label_of}
	by_set = {t: d for t, d in henry_topics.items() if t in sets_of}

	sys.stdout.write("Henry topics whose every Henry line is <= %d words: %d\n"
			% (args.max_words, len(henry_topics)))
	sys.stdout.write("  addressable by alias:    %d\n" % len(by_alias))
	sys.stdout.write("  addressable by metarole: %d\n" % len(by_set))
	sys.stdout.write("  addressable by neither:  %d  (unreachable from Lua)\n\n"
			% len([t for t in henry_topics if t not in label_of and t not in sets_of]))

	if not args.metarole_only:
		sys.stdout.write("=" * 72 + "\n")
		sys.stdout.write("BY ALIAS -- names one topic, so the wording is nearly pinned\n")
		sys.stdout.write("=" * 72 + "\n\n")

		for topic in sorted(by_alias, key=lambda t: label_of[t]):
			d = by_alias[topic]
			sys.stdout.write("%-46s topic=%d\n" % (label_of[topic], topic))

			for text in d["lines"]:
				sys.stdout.write("    %s\n" % text)

			if d["others"]:
				sys.stdout.write("    (+%d line(s) by other speakers, longest in topic %d words)\n"
						% (d["others"], d["longest_any"]))

			sys.stdout.write("\n")

	if not args.alias_only:
		sys.stdout.write("=" * 72 + "\n")
		sys.stdout.write("BY METAROLE -- a whole set, so every member must pass\n")
		sys.stdout.write("=" * 72 + "\n\n")

		# Grouped by set rather than by topic: the set is what gets requested.
		grouped = {}

		for topic in by_set:
			for mid in sets_of[topic]:
				grouped.setdefault(mid, []).append(topic)

		for mid in sorted(grouped, key=lambda m: name_of.get(m, str(m))):
			topics = grouped[mid]

			# The whole set's worst member, not just the short topics that got
			# it listed. A set with one long topic is unusable however short the
			# rest of it is.
			every = by_role.get(mid, set())
			worst = 0
			total = 0

			for t in every:
				for _s, text in by_topic.get(t, ()):
					worst = max(worst, len(text.split()))
					total += 1

			flag = "USABLE" if worst <= args.max_words else "set has a %d-word member" % worst
			sys.stdout.write("%-40s %d topic(s), %d line(s) in the whole set -- %s\n"
					% (name_of.get(mid, "metarole_%d" % mid), len(every), total, flag))

			for topic in sorted(topics):
				for text in by_set[topic]["lines"]:
					sys.stdout.write("    %s\n" % text)

			sys.stdout.write("\n")


if __name__ == "__main__":
	main()
