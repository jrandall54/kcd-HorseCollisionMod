"""Checks that the version and the changelog reflect the work that has landed.

Two failure modes this catches. A release built at a number that does not match
what changed, and a development branch that accumulates user-facing work while
the changelog stays empty, which is what makes the release number a guess.

Run with no arguments for an advisory report. Run with --release X.Y.Z to
enforce the rules a release has to satisfy; that form exits non-zero on any
violation and is what build.ps1 calls.
"""

import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(REPO_ROOT, "CHANGELOG.md")
MANIFEST = os.path.join(REPO_ROOT, "src", "mod.manifest")

# Changes under these paths are visible to a player and must be described in
# the changelog. Everything else is development tooling, which is why a hundred
# commits can correctly leave the version alone.
USER_FACING = ("src/",)

BREAKING = "**BREAKING**"


def git(*args):
    return subprocess.run(["git"] + list(args), cwd=REPO_ROOT,
                          capture_output=True, text=True).stdout.strip()


def released_versions():
    """Version tags, newest first, as (text, tuple) pairs."""
    out = git("tag", "-l", "v*")
    found = []

    for tag in out.splitlines():
        m = re.match(r"^v(\d+)\.(\d+)\.(\d+)$", tag.strip())

        if m:
            found.append((tag.strip(), tuple(int(g) for g in m.groups())))

    return sorted(found, key=lambda p: p[1], reverse=True)


def sections(body):
    """The `### Heading` blocks of one changelog release, as {heading: text}."""
    out = {}

    for m in re.finditer(r"^### +(.+?)\s*$(.*?)(?=^### |\Z)", body,
                         re.M | re.S):
        out[m.group(1).strip()] = m.group(2).strip()

    return out


def changelog_releases():
    """Every `## [version]` block in the changelog, in file order."""
    text = open(CHANGELOG, encoding="utf-8").read()
    blocks = []

    for m in re.finditer(r"^## +\[([^\]]+)\][^\n]*$(.*?)(?=^## |\Z)", text,
                         re.M | re.S):
        blocks.append((m.group(1).strip(), m.group(2)))

    return blocks


def implied_bump(body):
    """Which part of the version the entries in one block call for.

    Removing something, or an entry marked BREAKING, forces a major. A new
    capability is a minor. Anything else is a patch.
    """
    parts = sections(body)

    if BREAKING in body or "Removed" in parts:
        return "major"

    if "Added" in parts:
        return "minor"

    if parts:
        return "patch"

    return None


def next_version(previous, bump):
    major, minor, patch = previous

    if bump == "major":
        return (major + 1, 0, 0)

    if bump == "minor":
        return (major, minor + 1, 0)

    return (major, minor, patch + 1)


def manifest_version():
    text = open(MANIFEST, encoding="utf-8").read()
    m = re.search(r"<version>([^<]+)</version>", text)

    return m.group(1).strip() if m else None


def unreleased_work(since_tag):
    """User-facing commits since a tag, as (sha, subject) pairs.

    Filtered two ways. By path, because tooling under `tools/` never reaches a
    player. And by Conventional Commit type, because a comment reworded inside
    `src/` is not a change anyone can observe in game.
    """
    span = ("%s..HEAD" % since_tag) if since_tag else "HEAD"
    out = git("log", "--oneline", span, "--", *USER_FACING)
    found = []

    for line in out.splitlines():
        sha, _, subject = line.partition(" ")

        if re.match(r"^(feat|fix)(\([^)]*\))?!?:", subject):
            found.append((sha, subject))

    return found


def documented_since(blocks, last_version):
    """Changelog blocks describing work not yet tagged.

    Both `[Unreleased]` and a block already numbered for the next release
    count. Deciding the number early is fine; leaving the work undescribed is
    not.
    """
    described = []

    for name, body in blocks.items():
        if name == "Unreleased":
            described.append((name, body))
            continue

        m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", name)

        if m and tuple(int(g) for g in m.groups()) > last_version:
            described.append((name, body))

    return [(n, b) for n, b in described if sections(b)]


def main():
    release = None

    if "--release" in sys.argv:
        release = sys.argv[sys.argv.index("--release") + 1]

    if not os.path.exists(CHANGELOG):
        print("[VERSION] CHANGELOG.md is missing")
        return 1

    tags = released_versions()
    last_tag, last_version = tags[0] if tags else (None, (0, 0, 0))
    blocks = dict(changelog_releases())
    errors = []

    if release:
        if release not in blocks:
            errors.append("CHANGELOG.md has no section for %s" % release)
        elif not sections(blocks[release]):
            errors.append("the %s section of CHANGELOG.md is empty" % release)

        if manifest_version() != release:
            errors.append("mod.manifest says %s, releasing %s"
                          % (manifest_version(), release))

        leftover = blocks.get("Unreleased", "")

        if sections(leftover):
            errors.append("CHANGELOG.md still has entries under Unreleased; "
                          "move them under %s" % release)

        if release in blocks:
            bump = implied_bump(blocks[release])
            expected = next_version(last_version, bump)
            actual = tuple(int(p) for p in release.split("."))

            if bump and actual != expected:
                errors.append(
                    "the %s entries describe a %s change, so %s follows %s, "
                    "not %s. Mark a breaking entry with %s if it is one."
                    % (release, bump, ".".join(str(p) for p in expected),
                       last_tag or "0.0.0", release, BREAKING))

        for line in errors:
            print("[VERSION] %s" % line)

        if not errors:
            print("Version Check Passed (%s follows %s)."
                  % (release, last_tag or "no tag"))

        return 1 if errors else 0

    # Advisory. Reports drift rather than blocking, because a branch is
    # allowed to be mid-change.
    pending = unreleased_work(last_tag)
    described = documented_since(blocks, last_version)

    print("Last release:      %s" % (last_tag or "none"))
    print("Manifest version:  %s" % manifest_version())
    print("Player-visible commits since it: %d" % len(pending))

    if described:
        for name, body in described:
            bump = implied_bump(body)
            print("Documented as:     [%s] %s -> %s"
                  % (name, ", ".join(sorted(sections(body))),
                     ".".join(str(p) for p in next_version(last_version, bump))))
    elif pending:
        print("Unreleased notes:  NONE")
        print()
        print("%d player-visible commits are not described in CHANGELOG.md."
              % len(pending))
        print("Add them under ## [Unreleased] as they land, so the next")
        print("version is derived rather than guessed:")
        print()

        for sha, subject in pending[:10]:
            print("  %s %s" % (sha, subject))

        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
