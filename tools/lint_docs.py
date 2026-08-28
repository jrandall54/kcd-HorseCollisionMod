"""Enforces docs/STYLE.md on documentation and code comments.

Style rules are worth nothing if they are only written down. This checks them.

Scope: tracked Markdown outside the testing diary, plus comments in the Lua,
Python and PowerShell sources. The diary is exempt because it is a log of what
happened, where narrative and first person are correct.

Run: python tools/lint_docs.py [--warnings]
"""

import io
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A log of events. Narrative, first person and dated findings all belong here.
EXEMPT = {"docs/TESTING_DIARY.md"}

COMMENT_PREFIX = {".lua": "--", ".py": "#", ".ps1": "#"}


def rule(pattern, message, flags=re.I):
    return (re.compile(pattern, flags), message)


# Rejected outright. Each one has been corrected by hand in this repository
# more than once.
ERRORS = [
    rule(r"\b(?:we|us|our|ours)\b",
         "first person plural: describe the system, not its authors"),
    rule(r"(?<![A-Za-z])I(?:'m|'ve|'ll|'d)?(?![A-Za-z])",
         "first person singular: documentation has no narrator"),
    rule(r"\bmy\b", "first person possessive"),
    rule(r"\b(?:this session|earlier today|yesterday|last night)\b",
         "session narrative: documentation is not dated to when it was written"),
    rule(r"\b(?:cost (?:us|me|the most)|the hard way|breakthrough)\b"
         r"|\b(?:\d+|several|many|four|five|six) (?:more )?test cycles\b",
         "narrative about the process of finding something out"),
    rule(r"\bturned out (?:that|to be)\b",
         "narrative discovery: state the fact, not the surprise"),
    rule(r"[—–]", "em or en dash: use a comma, colon or full stop"),
    rule(r"[\U0001F300-\U0001FAFF☀-➿]", "emoji"),
    rule(r"\b(?:seamlessly|effortlessly|robust|powerful|leverage|delve|"
         r"elevate|unlock|game.changer|best.in.class|cutting.edge|"
         r"revolutionary|blazing|supercharge)\b",
         "marketing language"),
    rule(r"(?:^|\. )\s*(?:obviously|clearly)\b"
         r"|\b(?:of course|needless to say|as we (?:all )?know)\b",
         "tells the reader they should already understand this"),
]

# Reported, not fatal. Usually removable without loss.
WARNINGS = [
    # "rather than" is a comparison, not a hedge. The trailing check keeps a
    # wrapped line from being flagged when its "than" sits on the next one.
    rule(r"\b(?:very|really|quite|extremely|incredibly|pretty much)\b"
         r"|\brather\b(?! than)(?!\s*$)",
         "intensifier or hedge, usually deletable"),
    # "actually" is deliberately absent. It is nearly always contrastive here
    # ("where impacts were actually landing", against where they were assumed
    # to), and flagging it produced more false positives than findings. A rule
    # that is usually wrong teaches its reader to skip the whole report.
    rule(r"\b(?:basically|essentially|simply|just simply|at the end of the day)\b",
         "filler"),
    rule(r"\bin order to\b", 'wordy: "to"'),
    rule(r"\bdue to the fact that\b", 'wordy: "because"'),
    rule(r"\bat this (?:point in )?time\b", 'wordy: "now"'),
    rule(r"\bit (?:is|should be) (?:worth )?not(?:ing|ed) that\b",
         "throat-clearing: state the thing"),
    rule(r"\bthere (?:is|are) (?:a |an |)(?:number|variety) of\b",
         "wordy: name them or count them"),
    rule(r"\bplease note\b", "throat-clearing"),
    rule(r"\bin conclusion\b", "summary of a summary"),
]

MAX_SENTENCE_WORDS = 40


def tracked_files():
    """Everything git would keep: tracked files plus untracked, minus ignored.

    `git ls-files` alone lists only tracked files, so a newly written document
    is not checked until its first commit, which is exactly when checking it
    would have been most useful.
    """
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        cwd=REPO_ROOT, capture_output=True, text=True).stdout
    return sorted(set(p for p in out.splitlines() if p))


def prose_lines(path):
    """Yields (line number, text) for every line the rules apply to.

    Markdown contributes everything outside fenced code blocks. Source files
    contribute comment text only, since the rules are about prose.
    """
    ext = os.path.splitext(path)[1]
    text = io.open(os.path.join(REPO_ROOT, path), encoding="utf-8",
                   errors="replace").read()

    if ext == ".md":
        fenced = False
        for i, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("```"):
                fenced = not fenced
                continue
            if fenced:
                continue
            # Inline code and links to files are identifiers, not prose.
            yield i, re.sub(r"`[^`]*`", "", line)
        return

    prefix = COMMENT_PREFIX.get(ext)

    if not prefix:
        return

    for i, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()

        # Only whole-line comments. A trailing comment after code is usually a
        # short label and rarely prose.
        if not stripped.startswith(prefix):
            continue

        body = stripped[len(prefix):]

        # Doc-comment markers, and directives that are not prose.
        if re.match(r"^\s*@\w+", body) or body.strip().startswith("-"):
            continue

        yield i, body


def broken_markdown(path):
    """Yields structure that will not render.

    A table or a heading needs a blank line before it. Without one the parser
    treats the row as ordinary text in the preceding paragraph, and the table
    silently renders as a line of pipe characters. Scripted edits that splice
    blocks into a file drop that separator easily, and the result looks correct
    in the source.
    """
    if not path.endswith(".md"):
        return

    text = io.open(os.path.join(REPO_ROOT, path), encoding="utf-8",
                   errors="replace").read()
    lines = text.splitlines()
    fenced = False

    for i, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue

        if fenced or i == 0 or not lines[i - 1].strip():
            continue

        previous = lines[i - 1].strip()

        if line.startswith("|") and not previous.startswith("|"):
            yield i + 1, "table needs a blank line before it"
        elif line.startswith("#"):
            yield i + 1, "heading needs a blank line before it"


def long_sentences(path):
    if not path.endswith(".md"):
        return

    text = io.open(os.path.join(REPO_ROOT, path), encoding="utf-8",
                   errors="replace").read()
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    text = re.sub(r"^\s*[|#\-*].*$", "", text, flags=re.M)

    for sentence in re.split(r"(?<=[.!?])\s+", text):
        words = sentence.split()

        if len(words) > MAX_SENTENCE_WORDS:
            line = text.count("\n", 0, text.index(sentence)) + 1
            yield line, len(words), " ".join(words[:9])


def main():
    show_warnings = "--warnings" in sys.argv or "-w" in sys.argv
    errors = []
    warnings = []

    for path in tracked_files():
        if path in EXEMPT:
            continue

        if os.path.splitext(path)[1] not in (".md", ".lua", ".py", ".ps1"):
            continue

        for line_no, text in prose_lines(path):
            for pattern, message in ERRORS:
                m = pattern.search(text)
                if m:
                    errors.append((path, line_no, m.group(0).strip(), message))

            for pattern, message in WARNINGS:
                m = pattern.search(text)
                if m:
                    warnings.append((path, line_no, m.group(0).strip(), message))

        for line_no, count, opening in long_sentences(path):
            warnings.append((path, line_no, "%d words" % count,
                             "sentence over %d words: %s..."
                             % (MAX_SENTENCE_WORDS, opening)))

        # An error, not a warning: this one is visible to every reader of the
        # rendered page, unlike a filler word.
        for line_no, message in broken_markdown(path):
            errors.append((path, line_no, "markdown", message))

    for path, line, found, message in errors:
        print("[STYLE] %s:%d  %r  %s" % (path, line, found, message))

    if show_warnings:
        for path, line, found, message in warnings:
            print("[style] %s:%d  %r  %s" % (path, line, found, message))

    print()
    print("%d error(s), %d warning(s)%s"
          % (len(errors), len(warnings),
             "" if show_warnings else " (--warnings to list)"))

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
