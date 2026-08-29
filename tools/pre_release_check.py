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


def released_versions():
    """Versions that were actually released, from the tags, without the v."""
    out = subprocess.run(["git", "tag", "-l", "v*"],
                         cwd=REPO_ROOT, capture_output=True, text=True).stdout

    return set(m.group(1) for m in
               (re.match(r"^v(\d+\.\d+\.\d+)$", t.strip())
                for t in out.splitlines()) if m)


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
    shipped = released_versions()

    for path in paths:
        if path in VERSION_EXEMPT or os.path.splitext(path)[1] not in (
                ".md", ".lua", ".txt", ".manifest"):
            continue

        for i, line in enumerate(read(path).splitlines(), 1):
            # The trailing boundary excludes a prerelease suffix, so a version
            # file is not reported for containing "3.1.0" as the first part of
            # its own "3.1.0-dev.2".
            for m in re.finditer(r"\b(\d+\.\d+\.\d+)(?![\w.-])", line):
                other = m.group(1)

                # Semantic Versioning itself, and the game's own version, are
                # not this project's version.
                if other in (version, "2.0.0", "1.9.7", "1.1.0", "3.0.3"):
                    continue

                # The version under development, with its prerelease suffix
                # removed, is the release these documents are being written for.
                if other == version.split("-", 1)[0]:
                    continue

                # A version that was actually released is history, and history
                # is correct. "Shipped in 3.0.0" describes what happened and
                # stays true forever; rewriting it to name the current build
                # would make it false. What this looks for is a number naming
                # no release at all, which is the shape a stale claim takes.
                if other in shipped:
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


def check_download_size(paths, version):
    """Documented byte counts against the zip that was actually built.

    A size quoted in prose is a claim a reader can verify by downloading, and
    it drifts every time the script changes.
    """
    zip_path = os.path.join(REPO_ROOT, "releases",
                            "HorseCollisionMod_v%s.zip" % version)

    if not os.path.exists(zip_path):
        return []

    actual = os.path.getsize(zip_path)
    shipped = released_versions()
    found = []

    for path in paths:
        if path in VERSION_EXEMPT or os.path.splitext(path)[1] not in (
                ".md", ".txt"):
            continue

        for i, line in enumerate(read(path).splitlines(), 1):
            # A size attributed to a release that happened is a record of that
            # release, not a claim about this build, on the same reasoning as
            # the version check above.
            if any(v in line for v in shipped):
                continue

            for m in re.finditer(r"\b(\d{1,3}(?:,\d{3})+) bytes\b", line):
                claimed = int(m.group(1).replace(",", ""))

                # The old deployment model's size is quoted as a comparison
                # and is not this build.
                if claimed > actual * 3:
                    continue

                if claimed != actual:
                    found.append((path, i, m.group(1),
                                  "the built zip is %d bytes" % actual))

    return found


def readme_layout():
    """The paths listed in the README's repository layout block.

    The block is indented by directory: a line at the left margin ending in a
    slash opens a directory, indented lines under it are its members, and a
    line at the left margin without a slash is a file in the root.
    """
    text = read("README.md")
    m = re.search(r"^## Repository layout\s*\n+```\n(.*?)^```", text,
                  re.S | re.M)

    if not m:
        return None

    listed = set()
    directory = ""

    for line in m.group(1).splitlines():
        if not line.strip():
            continue

        name = line.split()[0]
        indented = line[:1].isspace()

        # A description may wrap, and its continuation is indented like a
        # member. Only a token that looks like a path is one.
        if "." not in name and not name.endswith("/"):
            continue

        if not indented:
            directory = name if name.endswith("/") else ""

            if not name.endswith("/"):
                listed.add(name)

            continue

        listed.add(directory + name)

    return listed


def check_readme_layout():
    """The README's repository layout against what the repository holds.

    A layout block is the first thing a reader trusts and the first thing to
    rot, because adding a file is not a moment anyone thinks about the README.
    Only src and tools are required to be complete: they are where files are
    added, and a missing entry there means the description is wrong rather
    than merely brief.
    """
    listed = readme_layout()

    if listed is None:
        return [("README.md", 0, "layout", "no repository layout block")]

    found = []

    for name in sorted(listed):
        if name.endswith("/"):
            continue

        if not os.path.exists(os.path.join(REPO_ROOT, name)):
            found.append(("README.md", 0, name,
                          "the layout lists a file that does not exist"))

    tracked = set(tracked_files())

    for path in sorted(tracked):
        if not path.startswith(("src/", "tools/")):
            continue

        if os.path.basename(path).startswith("__"):
            continue

        if path not in listed:
            found.append(("README.md", 0, path,
                          "tracked but missing from the layout"))

    return found


def check_readme_settings():
    """Defaults quoted in the README against the file that ships.

    The README documents a subset of the settings deliberately, so a missing
    row is not a fault. A row quoting a value the mod does not use is, and it
    is the kind that reaches a player: they set a number from the table,
    nothing changes the way it says, and the mod looks broken.
    """
    settings = read(os.path.join("src", "HorseCollisionMod_Settings.lua"))
    shipped = dict(re.findall(r"^\t(\w+)\s*=\s*([^,]+),", settings, re.M))
    found = []

    for key, quoted in re.findall(r"^\|\s*`(\w+)`\s*\|\s*([^|]+?)\s*\|",
                                  read("README.md"), re.M):
        if key not in shipped:
            found.append(("README.md", 0, key,
                          "the table documents a setting that does not ship"))
            continue

        actual = shipped[key].strip()

        if quoted != actual:
            found.append(("README.md", 0, "%s = %s" % (key, quoted),
                          "the mod ships %s" % actual))

    return found


def check_generated_docs():
    """The generated API reference against the source it documents.

    docs/api is LDoc output committed to the repository, so it goes stale
    silently: the source grows new functions and fields and the published
    reference keeps describing the old surface. Comparing commit times catches
    that, where comparing file times would fire on every checkout.
    """
    source = os.path.join("src", "HorseCollisionMod.lua")
    generated = os.path.join("docs", "api", "index.html")

    if not os.path.exists(os.path.join(REPO_ROOT, generated)):
        return []

    def committed_at(path):
        out = subprocess.run(["git", "log", "-1", "--format=%ct", "--", path],
                             cwd=REPO_ROOT, capture_output=True,
                             text=True).stdout.strip()

        return int(out) if out.isdigit() else None

    source_at = committed_at(source)
    generated_at = committed_at(generated)

    if source_at is None or generated_at is None:
        return []

    if source_at > generated_at:
        return [(generated.replace(os.sep, "/"), 0, "stale",
                 "the source has changed since this was generated; run ldoc .")]

    return []


def check_file_description(version):
    """The Files tab entry against the 255 characters the mod page keeps.

    The description is sent in the request that creates the version, and the
    API has no endpoint to add one afterwards, so a missing file publishes a
    blank entry that can only be fixed in the browser.

    Gated on the release zip existing, for the same reason as the size check:
    a clone with nothing built is not mid-release.
    """
    zip_path = os.path.join(REPO_ROOT, "releases",
                            "HorseCollisionMod_v%s.zip" % version)

    if not os.path.exists(zip_path):
        return []

    path = "releases/file-description-%s.txt" % version

    if not os.path.exists(os.path.join(REPO_ROOT, path)):
        return [(path, 0, "missing",
                 "the Files tab entry would publish with no description")]

    text = read(path).strip()

    if not text:
        return [(path, 0, "empty",
                 "the Files tab entry would publish with no description")]

    if len(text) > 255:
        return [(path, 0, "%d characters" % len(text),
                 "the mod page keeps 255")]

    return []


def main():
    paths = tracked_files()
    version = current_version()

    # Two audiences, and conflating them makes the check useless on a branch.
    # Everything except the mod page asks whether the repository describes
    # itself accurately, which is true of any merge. The mod page and the
    # Files tab entry are publishing artifacts, written once per release, and
    # reporting them as problems on every push trains a reader to skip the
    # whole report.
    merge_only = "--merge" in sys.argv

    if not version:
        print("[STALE] could not read the version from src/mod.manifest")
        return 1

    problems = (check_versions(paths, version)
                + check_claims(paths)
                + check_links(paths)
                + check_config_docs()
                + check_readme_layout()
                + check_readme_settings()
                + check_generated_docs()
                + check_download_size(paths, version))

    if not merge_only:
        problems += (check_nexus_page(version)
                     + check_file_description(version))

    for path, line, found, message in problems:
        where = "%s:%d" % (path, line) if line else path
        print("[STALE] %s  %r  %s" % (where, found, message))

    print()
    scope = "repository" if merge_only else "repository and mod page"
    print("%d stale reference(s) against version %s (%s)"
          % (len(problems), version, scope))

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
