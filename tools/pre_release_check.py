"""Checks that the repository describes the build it is about to release.

Documentation goes stale quietly. A version reference names a release that
never shipped, a comment describes a design the code has moved past, a document
points at a file that was deleted. None of it breaks a build, and all of it is
what a reader meets first.

Run before tagging. Exits non-zero on anything found.
"""

import io
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The diary is a log of what happened, so old version numbers are correct
# there. The changelog is a history of releases for the same reason.
VERSION_EXEMPT = {"docs/TESTING_DIARY.md", "CHANGELOG.md"}

# Prose that claims something the reader can check, and that goes stale when
# the design moves. Each of these has been wrong in this repository.
STALE_CLAIMS = [
    (r"\bships? (?:a )?full replacements?\b|\breplaces the (?:vanilla )?"
     r"animation databases\b",
     "the mod no longer replaces vanilla animation databases"),
    (r"\bReplacing it with an oriented box is a known improvement\b",
     "the oriented box is implemented"),
    (r"\bTuning rationale\b", "that section was renamed to Reaction defaults"),
]


def tracked_files():
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        cwd=REPO_ROOT, capture_output=True, text=True).stdout

    return sorted(p for p in out.splitlines() if p)


def read(path):
    return io.open(os.path.join(REPO_ROOT, path), encoding="utf-8",
                   errors="replace").read()


def current_version():
    m = re.search(r"<version>([^<]+)</version>",
                  read(os.path.join("src", "mod.manifest")))

    return m.group(1).strip() if m else None


def check_versions(paths, version):
    """Version numbers naming a release that is not this one.

    A reference to an older release is only correct where the document is a
    history. Everywhere else it dates the document.
    """
    found = []

    for path in paths:
        if path in VERSION_EXEMPT or os.path.splitext(path)[1] not in (
                ".md", ".lua", ".txt", ".manifest"):
            continue

        for i, line in enumerate(read(path).splitlines(), 1):
            for m in re.finditer(r"\b(\d+\.\d+\.\d+)\b", line):
                other = m.group(1)

                # Semantic Versioning itself, and the game's own version, are
                # not this project's version.
                if other in (version, "2.0.0", "1.9.7", "1.1.0", "3.0.3"):
                    continue

                found.append((path, i, other,
                              "names a release that is not %s" % version))

    return found


def check_claims(paths):
    found = []

    for path in paths:
        if path in VERSION_EXEMPT or os.path.splitext(path)[1] not in (
                ".md", ".lua", ".txt"):
            continue

        for i, line in enumerate(read(path).splitlines(), 1):
            # A claim stated as something the mod does not do is the current
            # design being described, not a stale assertion of the old one.
            if re.search(r"\b(?:no longer|does not|doesn't|never|without|"
                         r"instead of|rather than)\b", line, re.I):
                continue

            for pattern, message in STALE_CLAIMS:
                if re.search(pattern, line, re.I):
                    found.append((path, i, line.strip()[:40], message))

    return found


def check_links(paths):
    """Documents pointing at files that are not there."""
    present = set(paths)
    found = []

    for path in paths:
        # The diary records what was true when each entry was written, so a
        # tool it once used and later removed is correct history.
        if path in VERSION_EXEMPT:
            continue

        if os.path.splitext(path)[1] not in (".md", ".lua", ".ps1", ".py"):
            continue

        for i, line in enumerate(read(path).splitlines(), 1):
            for m in re.finditer(r"`((?:docs|tools|src)/[\w./-]+\.\w+)`", line):
                target = m.group(1)

                if target not in present:
                    found.append((path, i, target, "referenced file is missing"))

    return found


def check_config_docs():
    """Config keys the LDoc header does not document, and the reverse."""
    text = read(os.path.join("src", "HorseCollisionMod.lua"))
    documented = set(re.findall(r"^-- @field (\w+)", text, re.M))

    block = re.search(r"HorseCollisionMod\.Config = \{(.*?)^\}", text,
                      re.S | re.M)

    if not block:
        return [("src/HorseCollisionMod.lua", 0, "Config",
                 "could not locate the Config table")]

    declared = set(re.findall(r"^\t(\w+)\s*=", block.group(1), re.M))
    found = []

    for key in sorted(declared - documented):
        found.append(("src/HorseCollisionMod.lua", 0, key,
                      "config key has no @field line"))

    for key in sorted(documented - declared):
        found.append(("src/HorseCollisionMod.lua", 0, key,
                      "@field documents a key that no longer exists"))

    return found


def check_nexus_page(version):
    """The public mod page against the build it describes.

    The page is what a player reads before downloading, and it is the easiest
    thing in the project to forget. Two things have to hold: it names this
    release, and its settings block lists exactly the keys that ship.
    """
    page_path = "nexus_description.txt"
    found = []

    # The page copy is a local working file rather than part of the
    # repository, so a fresh clone has nothing to check and that is correct.
    if not os.path.exists(os.path.join(REPO_ROOT, page_path)):
        return []

    page = read(page_path)

    if version not in page:
        found.append((page_path, 0, version,
                      "the page does not mention this release"))

    block = re.search(r"\[code\](.*?)\[/code\]", page, re.S)

    if not block:
        found.append((page_path, 0, "settings",
                      "no settings block on the page"))

        return found

    listed = set(re.findall(r"^(\w+)\s", block.group(1), re.M))
    shipped = set(re.findall(
        r"^	(\w+)\s*=",
        read(os.path.join("src", "HorseCollisionMod_Settings.lua")), re.M))

    for key in sorted(listed - shipped):
        found.append((page_path, 0, key, "page documents a setting that does "
                                         "not ship"))

    for key in sorted(shipped - listed):
        found.append((page_path, 0, key, "shipped setting is missing from the "
                                         "page"))

    return found


def main():
    paths = tracked_files()
    version = current_version()

    if not version:
        print("[STALE] could not read the version from src/mod.manifest")
        return 1

    problems = (check_versions(paths, version)
                + check_claims(paths)
                + check_links(paths)
                + check_config_docs()
                + check_nexus_page(version))

    for path, line, found, message in problems:
        where = "%s:%d" % (path, line) if line else path
        print("[STALE] %s  %r  %s" % (where, found, message))

    print()
    print("%d stale reference(s) against version %s" % (len(problems), version))

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
