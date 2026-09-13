"""Trace what a bark set can say, in order, and when it runs out.

`bark_lines.py` answers "what words are in this set". This answers the harder
question: **which line plays on the first firing, which on the second, and when
does the speaker fall silent.**

The structure, read out of the shipped tables:

    topictorole   (metarole, role) -> topic      which topic a speaker reaches
    topic2sequence  topic -> sequences           each with an entry_condition
    sequence        priority, timeout, next      ordering, cooldown, chaining

Within a topic the sequences are ordered by `priority`, and each carries a
`timeout` in seconds which is the cooldown `IsSeqAvailable()` tests. A sequence
also carries `next`, which is the **topic** reached after it, and that is where
escalation ladders live: the first shove plays the entry sequence, and repeats
climb the rungs of the next topic as each rung goes on cooldown.

Special timeout values: `0` means no cooldown at all, and `-1` means the
sequence may be used only once ever.

    python tools/bark_chain.py RANENY_NA_ZEMI
    python tools/bark_chain.py ZASAH_ZBRANI_IGNOROVANY --role 1681
"""

import argparse
import sys
from collections import defaultdict

import bark_lines as B


def load():
    tab = B.TABLES

    role_xml = B._read(tab, "Libs/Tables/rpg/role.xml").decode("us-ascii", "replace")
    role_name = {}
    for _mid, rid, rn in B._rows(role_xml, "metarole_id", "role_id", "role_name"):
        if rid:
            role_name[int(rid)] = rn

    t2r = B._read(tab, "Libs/Tables/text/topictorole.xml").decode("us-ascii", "replace")
    topics_by_pair = defaultdict(set)
    for mid, rid, tid in B._rows(t2r, "metarole_id", "role_id", "topic_id"):
        if mid and rid and tid:
            topics_by_pair[(int(mid), int(rid))].add(int(tid))

    t2s = B._read(tab, "Libs/Tables/text/topic2sequence.xml").decode("us-ascii", "replace")
    seqs_by_topic = defaultdict(list)
    for entry, npc, seq, topic in B._rows(
            t2s, "entry_condition", "npc_entry_condition", "sequence_id", "topic_id"):
        if seq and topic:
            seqs_by_topic[int(topic)].append((int(seq), entry.strip(), npc.strip()))

    seq_xml = B._read(tab, "Libs/Tables/text/sequence.xml").decode("us-ascii", "replace")
    seq_info = {}
    for sid, timeout, prio, flags, nxt in B._rows(
            seq_xml, "sequence_id", "timeout", "priority", "flags", "next"):
        if sid:
            seq_info[int(sid)] = {
                "timeout": timeout, "priority": prio, "flags": flags, "next": nxt}

    text_by_seq = {}
    for topic, speaker, txt in B.lines():
        pass
    # Localization keys carry the sequence id in their second field, which is a
    # more direct map from a sequence to its words than going through the topic.
    import re
    xml = B._read(B.LOCALE, "text_ui_dialog.xml").decode("utf-8", "replace")
    row = re.compile(r"<Row><Cell>t(\d+)_s(\d+)_(\d+)_([^<]*?)_[A-Za-z0-9]{4}</Cell>"
                     r"<Cell>[^<]*</Cell><Cell>([^<]*)</Cell></Row>")
    for m in row.finditer(xml):
        text_by_seq.setdefault(int(m.group(2)), []).append(
            (int(m.group(3)), m.group(4), m.group(5)))

    return role_name, topics_by_pair, seqs_by_topic, seq_info, text_by_seq


def describe_timeout(value):
    if value == "0":
        return "no cooldown"
    if value == "-1":
        return "ONCE ONLY"
    try:
        secs = int(value)
    except (TypeError, ValueError):
        return "timeout=%s" % value
    if secs >= 60 and secs % 60 == 0:
        return "%ds (%dm)" % (secs, secs // 60)
    return "%ds" % secs


def walk(topic, depth, seen, tables, out, only_role=None):
    role_name, topics_by_pair, seqs_by_topic, seq_info, text_by_seq = tables
    if topic in seen or depth > 6:
        return
    seen.add(topic)
    pad = "   " * depth
    rows = seqs_by_topic.get(topic, [])
    if not rows:
        out.append("%stopic %-7d (no sequences)" % (pad, topic))
        return
    ordered = sorted(rows, key=lambda r: int(seq_info.get(r[0], {}).get("priority") or 0))
    out.append("%stopic %-7d %d sequence(s)" % (pad, topic, len(ordered)))
    for seq, entry, npc in ordered:
        meta = seq_info.get(seq, {})
        out.append("%s   prio %-3s seq %-7d %-14s flags=%-7s"
                   % (pad, meta.get("priority"), seq,
                      describe_timeout(meta.get("timeout")), meta.get("flags")))
        if entry and entry != "1":
            out.append("%s      entry: %s" % (pad, entry[:110]))
        if npc:
            out.append("%s      npc  : %s" % (pad, npc[:110]))
        texts = sorted(text_by_seq.get(seq, []))
        for _idx, speaker, txt in texts[:3]:
            out.append("%s      [%s] %s" % (pad, speaker, txt[:74]))
        nxt = meta.get("next")
        if nxt and nxt not in ("0", ""):
            out.append("%s      next -> topic %s" % (pad, nxt))
            walk(int(nxt), depth + 1, seen, tables, out, only_role)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("metarole", nargs="+")
    ap.add_argument("--role", type=int, default=None,
                    help="only the path for this role id (see soul:GetRoles)")
    args = ap.parse_args()

    tables = load()
    role_name, topics_by_pair, _s, _i, _t = tables
    names = B.metaroles()

    for want in args.metarole:
        mid = names.get(want)
        if mid is None:
            print("no metarole named %s" % want)
            continue
        print("\n===== %s (metarole %d)" % (want, mid))
        pairs = sorted([p for p in topics_by_pair if p[0] == mid], key=lambda p: p[1])
        for (_m, rid) in pairs:
            if args.role and rid != args.role:
                continue
            print("  role %-5d %s" % (rid, role_name.get(rid, "?")))
            for topic in sorted(topics_by_pair[(_m, rid)]):
                out = []
                walk(topic, 2, set(), tables, out, args.role)
                print("\n".join(out))


if __name__ == "__main__":
    main()
