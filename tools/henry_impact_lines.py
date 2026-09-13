"""Every spoken line Henry can be made to say on demand, with its full text.

This answers one question and answers it completely: **if the mod sends
`dialog:monologRequest` with this alias, what words come out?**

Three things have to be true for a line to be usable, and an earlier pass got
the third one wrong:

1. The topic's label is in `topic.xml`, which is the alias namespace.
2. One of its sequences has `entry_condition = '1'`. Anything else --
   `IsQuestStarted(...)`, `IsObjectiveCompleted(...)` -- refuses silently, so the
   request is accepted and nothing is spoken.
3. That sequence's `timeout` is not `-1`, which means usable once per
   playthrough and then never again.
4. Its shipped audio exists and carries exactly one actor, Henry's. A sequence
   with two actors is a conversation, and asking for one as a bark was refused
   every time it was tried.
5. **Every** line in the topic is short and usable, not just the first one.

The third point is the reason this tool exists. A topic holds a whole set of
recorded lines and the dialog system picks which member plays, so a shortlist
built from one member per topic is a shortlist of guesses. Lines were chosen
from labels like "Oh, shit!" that turned out to be the opening of "Oh shit,
where's that damn ring?", and the rider had to discover that by hearing it:

> "I choose it because it was labeled as saying 'oh shit' but it actually has
> many more words attached to the line."

So every member is printed, and `--max-words` rejects a topic on its **longest**
member rather than its first.

    python tools/henry_impact_lines.py --max-words 6
    python tools/henry_impact_lines.py --alias revelation_murderer_ohfuck
"""

import argparse
import collections
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bark_lines as B

HENRY = ("henry_0", "henry_1", "henry_2", "henry_3", "henry_4", "p_henry_he")

# Tom McKay, who voices Henry. The shipped dialogue audio is named
# `<actor>_t<topic>_s<sequence>_<n>_<slug>_<hash>.ogg`, so the actor prefix on a
# sequence's files is the definitive record of who speaks in it.
ACTOR = "tmck"

_OGG = re.compile(r"Dialog/\d+/(.+?)_t(\d+)_s(\d+)_", re.I)


def speakers_by_sequence():
	"""Which actors recorded each sequence, read out of the localization paks.

	This is the filter nothing in the tables can replace. A sequence with no
	audio can never be heard however reachable it looks, and a sequence recorded
	by two actors is a conversation rather than a monolog: asking for one as a
	bark was refused every single time in testing, while every line that did play
	had exactly one actor on it, and that actor was Henry's.
	"""
	root = os.path.join(B.GAME, "Localization")
	out = collections.defaultdict(set)

	for name in os.listdir(root):
		if not (name.startswith("English") and name.endswith(".pak")):
			continue

		for member in zipfile.ZipFile(os.path.join(root, name)).namelist():
			match = _OGG.match(member)

			if match:
				out[match.group(3)].add(match.group(1).lower())

	return out


def load():
	topic_xml = B._read(B.TABLES, "Libs/Tables/text/topic.xml").decode("utf-8", "replace")
	t2s_xml = B._read(B.TABLES, "Libs/Tables/text/topic2sequence.xml").decode("utf-8", "replace")

	labels = {}
	for tid, label in B._rows(topic_xml, "topic_id", "label"):
		if label and tid:
			labels[int(tid)] = label

	seq_xml = B._read(B.TABLES, "Libs/Tables/text/sequence.xml").decode("utf-8", "replace")

	# `-1` means the sequence may be used once in a playthrough and never again.
	# Three of the rider's picks were silent for this reason alone: the quest
	# they belong to had long since spent them.
	once_only = set()
	for sid, timeout in B._rows(seq_xml, "sequence_id", "timeout"):
		if (timeout or "").strip() == "-1":
			once_only.add(sid)

	voices = speakers_by_sequence()

	# A topic survives only if it has at least one sequence that is always-true,
	# repeatable, and recorded by Henry's actor alone.
	ungated = set()
	for tid, sid, ec in B._rows(t2s_xml, "topic_id", "sequence_id", "entry_condition"):
		if not tid or ec.strip() != "1" or sid in once_only:
			continue

		if voices.get(sid) == {ACTOR}:
			ungated.add(int(tid))

	by_topic = {}
	for topic, speaker, text in B.lines():
		if speaker in HENRY and text.strip():
			by_topic.setdefault(topic, []).append(text)

	return labels, ungated, by_topic


def words(text):
	return len(text.split())


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--max-words", type=int, default=6,
			help="reject a topic whose longest line exceeds this")
	ap.add_argument("--alias", help="print one alias regardless of length")
	ap.add_argument("--grep", help="only aliases whose text matches, case-insensitive")
	args = ap.parse_args()

	labels, ungated, by_topic = load()
	by_label = {v: k for k, v in labels.items()}

	if args.alias:
		tid = by_label.get(args.alias)
		if tid is None:
			raise SystemExit("no such alias: " + args.alias)
		print("%s  topic=%d  ungated=%s" % (args.alias, tid, tid in ungated))
		for text in by_topic.get(tid, []):
			print("   (%d) %s" % (words(text), text))
		return

	rows = []
	for tid in sorted(ungated):
		label = labels.get(tid)
		texts = by_topic.get(tid)
		if not label or not texts:
			continue
		longest = max(words(t) for t in texts)
		if longest > args.max_words:
			continue
		if args.grep and not any(args.grep.lower() in t.lower() for t in texts):
			continue
		rows.append((longest, len(texts), label, texts))

	rows.sort()
	for longest, count, label, texts in rows:
		print("%-50s lines=%d longest=%d" % (label, count, longest))
		for text in texts:
			print("     %s" % text)
	print("\n%d aliases, every line at most %d words" % (len(rows), args.max_words))


if __name__ == "__main__":
	main()
