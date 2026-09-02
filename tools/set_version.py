"""Sets the version everywhere it is written, in one command.

The number lives in fourteen places: `src/mod.manifest`, the
`HorseCollisionMod.Version` assignment, and an `@release` tag in the entry
point and each of the eleven part files. `build.ps1` checks every one of them
and refuses a release if any disagrees.

Bumping them by hand is the chore this removes. Done that way it becomes a
build, fix, build cycle repeated once per file, because the build reported
only the first mismatch it found; that half is fixed in `build.ps1`, and this
is the other half.

    python tools/set_version.py            derive the next version and apply it
    python tools/set_version.py 4.7.0      apply a version explicitly
    python tools/set_version.py --check    report without writing anything

Deriving is the usual case and is the same rule `version_check.py` enforces:
the newest tag, bumped by what the changelog's undescribed entries call for.
Applying it also moves those entries out of `## [Unreleased]` and under a
heading for the new version, dated today, which is the step the workflow
requires when a branch merges.

Nothing here touches git. Committing and tagging stay deliberate.
"""

import datetime
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import version_check as vc

REPO_ROOT = vc.REPO_ROOT
MANIFEST = vc.MANIFEST
CHANGELOG = vc.CHANGELOG
ENTRY = vc.SCRIPT
PARTS_DIR = os.path.join(REPO_ROOT, "src", "HorseCollisionMod")


def lua_files():
    """The entry point first, then every part file, in load order."""
    out = [ENTRY]

    if os.path.isdir(PARTS_DIR):
        for name in sorted(os.listdir(PARTS_DIR)):
            if name.endswith(".lua"):
                out.append(os.path.join(PARTS_DIR, name))

    return out


def read(path):
    return io.open(path, encoding="utf-8").read()


def write(path, text):
    io.open(path, "w", encoding="utf-8", newline="\n").write(text)


def derive():
    """The version the changelog's undescribed entries call for."""
    tags = vc.released_versions()
    last_tag, last_version = tags[0] if tags else (None, (0, 0, 0))
    blocks = dict(vc.changelog_releases())
    described = vc.documented_since(blocks, last_version)

    if not described:
        return None, "nothing is described in CHANGELOG.md since %s" % (
            last_tag or "the beginning")

    # An already-numbered heading is the author's decision and is honored.
    for name, _ in described:
        if re.match(r"^\d+\.\d+\.\d+$", name):
            return name, None

    dropped = vc.dropped_settings(last_tag)
    bump = vc.implied_bump(described[0][1], dropped)

    return ".".join(str(p) for p in vc.next_version(last_version, bump)), None


def current():
    """What each place says the version is, as {label: (path, version)}."""
    out = {}

    m = re.search(r"<version>([^<]+)</version>", read(MANIFEST))
    out["mod.manifest"] = (MANIFEST, m.group(1).strip() if m else None)

    entry = read(ENTRY)
    m = re.search(r'HorseCollisionMod\.Version\s*=\s*"([^"]+)"', entry)
    out["HorseCollisionMod.Version"] = (ENTRY, m.group(1) if m else None)

    for path in lua_files():
        m = re.search(r"^-- @release\s+(\S+)\s*$", read(path), re.M)

        if m:
            out["@release " + os.path.basename(path)] = (path, m.group(1))

    return out


def apply(version):
    """Writes the version into every place that carries it."""
    touched = []

    text = read(MANIFEST)
    new = re.sub(r"<version>[^<]+</version>", "<version>%s</version>" % version,
                 text, count=1)

    if new != text:
        write(MANIFEST, new)
        touched.append("mod.manifest")

    for path in lua_files():
        text = read(path)
        new = text

        if path == ENTRY:
            new = re.sub(r'(HorseCollisionMod\.Version\s*=\s*)"[^"]+"',
                         r'\g<1>"%s"' % version, new, count=1)

        # Horizontal whitespace only, never `\s`, which matches newlines.
        #
        # With `\s*$` under re.M the match ran past the end of the line and
        # swallowed the blank line separating the module header from the doc
        # block below it. LDoc then reads the two as one block and fails with
        # "'class' cannot have multiple values". That was misdiagnosed as a
        # problem with the tables in the file it named, and "fixed" by moving
        # them, which was never the cause.
        new = re.sub(r"^(-- @release[ \t]+)\S+[ \t]*$",
                     r"\g<1>%s" % version, new, flags=re.M)

        if new != text:
            write(path, new)
            touched.append(os.path.relpath(path, REPO_ROOT))

    return touched


def promote_changelog(version):
    """Moves `## [Unreleased]` entries under a dated heading for the version."""
    text = read(CHANGELOG)
    blocks = dict(vc.changelog_releases())

    if version in blocks:
        return None

    unreleased = blocks.get("Unreleased", "")

    if not vc.sections(unreleased):
        return None

    today = datetime.date.today().isoformat()
    heading = "## [%s] - %s" % (version, today)

    # Located with the same pattern the blocks were parsed with, rather than by
    # rebuilding the original text out of the heading and the captured body.
    # The captured body carries its own leading newlines, so joining them does
    # not reproduce what is in the file and the replace matched nothing.
    #
    # That failure was silent and therefore the worst kind: the version files
    # were rewritten, the changelog was not, and the tool reported success.
    pattern = re.compile(r"^(## +\[Unreleased\][^\n]*\n)(.*?)(?=^## |\Z)",
                         re.M | re.S)
    m = pattern.search(text)

    if not m:
        return None

    body = m.group(2).lstrip("\n")
    new = (text[:m.start()]
           + m.group(1) + "\n" + heading + "\n\n" + body
           + text[m.end():])

    if new == text:
        return None

    write(CHANGELOG, new)

    return heading


def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    check_only = "--check" in sys.argv
    version = args[0] if args else None
    derived = False

    if not version:
        version, why = derive()
        derived = True

        if not version:
            print("[VERSION] cannot derive a version: %s" % why)
            print("          pass one explicitly, or add entries under "
                  "## [Unreleased].")
            return 1

    if not re.match(r"^\d+\.\d+\.\d+(?:[-+].*)?$", version):
        print("[VERSION] %s is not a version" % version)
        return 1

    state = current()
    stale = {k: v for k, (_, v) in state.items() if v != version}

    if check_only:
        print("Target version: %s%s"
              % (version, " (derived)" if derived else ""))

        if not stale:
            print("All %d places already say %s." % (len(state), version))

            return 0

        print("%d of %d places disagree:" % (len(stale), len(state)))

        for label in sorted(stale):
            print("  %-40s %s" % (label, stale[label]))

        return 1

    touched = apply(version)
    heading = promote_changelog(version)

    print("Set version to %s%s in %d file(s)."
          % (version, " (derived)" if derived else "", len(set(touched))))

    for name in sorted(set(touched)):
        print("  %s" % name)

    if heading:
        print("Promoted CHANGELOG entries under %s" % heading)

    print()
    print("Next:  .\\build.ps1 -Version %s" % version)

    return 0


if __name__ == "__main__":
    sys.exit(main())
