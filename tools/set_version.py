"""Sets the version everywhere it is written, in one command.

The number lives in two places: `src/mod.manifest` and the
`HorseCollisionMod.Version` assignment. `build.ps1` refuses a release if
either disagrees with the version being built.

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

    m = re.search(r'HorseCollisionMod\.Version\s*=\s*"([^"]+)"', read(ENTRY))
    out["HorseCollisionMod.Version"] = (ENTRY, m.group(1) if m else None)

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

    text = read(ENTRY)
    new = re.sub(r'(HorseCollisionMod\.Version\s*=\s*)"[^"]+"',
                 r'\g<1>"%s"' % version, text, count=1)

    if new != text:
        write(ENTRY, new)
        touched.append(os.path.relpath(ENTRY, REPO_ROOT))

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
    # The captured body carries its own leading newlines, so a rebuilt text
    # would not match the file, and the changelog would be left unmoved while
    # the version files were rewritten.
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
