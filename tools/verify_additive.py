"""Proves the additive animation layout is correct and complete.

Every claim the mod makes about its own deployment is checked here against the
game's own paks and against the packaged release, rather than being asserted in
documentation. Run it before publishing.

The claims, in order:

 1. The release overrides no vanilla filename.
 2. Every file the release ships is one the mod is supposed to ship.
 3. Nothing is lost from the fragment the mod takes authority over: every
    vanilla FragTag and every vanilla option survives.
 4. The mod's own options are present and point at clips the game contains.
 5. The reference chain resolves end to end, every path in it exists, and the
    vanilla database is referenced rather than copied.
 6. Pak entry names use forward slashes, or CryEngine looks them up by a path
    that does not match and the pak silently overrides nothing.
 7. The Lua redirects the classes the engine actually spawns, not the templates
    those classes were built from.

Run: python tools/verify_additive.py [path/to/release.zip]
"""

import io
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_adb

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADB_PREFIX = "Animations/Mannequin/ADB/"

FAILURES = []
CHECKS = [0]


def check(ok, claim, detail=""):
    CHECKS[0] += 1
    print("  [%s] %s%s" % ("PASS" if ok else "FAIL", claim,
                           "" if not detail else "  (%s)" % detail))
    if not ok:
        FAILURES.append(claim)
    return ok


def heading(text):
    print()
    print(text)
    print("-" * len(text))


def read_pak_text(pak, entry):
    return build_adb.read_pak_entry(pak, entry).decode("ascii", "replace")


def newest_release():
    releases = os.path.join(REPO_ROOT, "releases")
    zips = [os.path.join(releases, f) for f in os.listdir(releases)
            if f.endswith(".zip")]
    if not zips:
        raise SystemExit("no release zip in releases/; run build.ps1 first")
    return max(zips, key=os.path.getmtime)


def main():
    release = sys.argv[1] if len(sys.argv) > 1 else newest_release()
    print("Verifying %s" % os.path.basename(release))
    print("against    %s" % build_adb.PAK)

    outer = zipfile.ZipFile(release)
    pak_bytes = outer.read("Data/HorseCollisionMod.pak")
    pak = zipfile.ZipFile(io.BytesIO(pak_bytes))
    shipped = {i.filename: i for i in pak.infolist()}

    # ---- 1. no vanilla filename is claimed --------------------------------
    heading("1. The release overrides no vanilla file")

    with zipfile.ZipFile(build_adb.PAK) as anim:
        vanilla_names = set(n.replace("\\", "/") for n in anim.namelist())

    claimed = [n for n in shipped if n in vanilla_names]
    check(not claimed, "no shipped path exists in the vanilla animation pak",
          "overlap: %s" % claimed if claimed else "%d entries checked" % len(shipped))

    adb_files = [n for n in shipped if n.startswith(ADB_PREFIX)]
    bad = [n for n in adb_files if not n.rsplit("/", 1)[-1].startswith("hcm_")]
    check(not bad, "every animation file is named hcm_*", bad or "%d files" % len(adb_files))

    # ---- 2. the file set is exactly what is intended ----------------------
    heading("2. The release ships exactly the intended file set")

    expected = set()
    for gender in build_adb.GENDERS:
        expected.add("hcm_%s_database.adb" % gender)
        expected.add("hcm_%s_fragmentids.xml" % gender)
        expected.add("hcm_%s_controllerdefs.xml" % gender)
    expected.add(build_adb.SHARED_TAGS_NAME)

    got = set(n.rsplit("/", 1)[-1] for n in adb_files)
    check(got == expected, "animation file set matches the generator's contract",
          "missing=%s extra=%s" % (sorted(expected - got) or "none",
                                   sorted(got - expected) or "none"))
    check("Scripts/Startup/HorseCollisionMod.lua" in shipped,
          "the mod script ships")

    # ---- 3, 4, 5. per character set ---------------------------------------
    for gender, paths in sorted(build_adb.GENDERS.items()):
        heading("%s: nothing lost, everything present, chain resolves" % gender)

        parent_name = "hcm_%s_database.adb" % gender
        parent = pak.read(ADB_PREFIX + parent_name).decode("ascii", "replace")

        vanilla_db = read_pak_text(build_adb.PAK, paths["db"])
        van_block = re.search(
            "\n    <AnimationControlled>(.*?)\n    </AnimationControlled>",
            vanilla_db, re.S)
        our_block = re.search(
            "\n    <AnimationControlled>(.*?)\n    </AnimationControlled>",
            parent, re.S)

        if not check(our_block is not None,
                     "the parent defines AnimationControlled itself"):
            continue

        van_opts = re.findall(r'FragTags="([^"]*)"', van_block.group(1)) if van_block else []
        our_opts = re.findall(r'FragTags="([^"]*)"', our_block.group(1))

        lost = sorted(set(van_opts) - set(our_opts))
        check(not lost, "every vanilla option survives",
              lost or "%d inherited" % len(van_opts))

        wanted = [t for t, _ in build_adb.STAGGERS]
        missing = [t for t in wanted if t not in our_opts]
        check(not missing, "all %d stagger options present" % len(wanted), missing)

        # Every clip the mod points at must exist in that set's own database.
        clips_present = set(re.findall(r'<Animation name="([^"]*)"', vanilla_db))
        absent = [c for _, c in build_adb.STAGGERS if c not in clips_present]
        check(not absent, "every referenced clip exists in the vanilla database", absent)

        # The parent must reference the vanilla database, not carry a copy.
        subs = re.findall(r'<SubADB File="([^"]*)"', parent)
        check(paths["db"] in subs, "references the untouched vanilla database",
              subs)
        check(len(parent) < 200 * 1024,
              "parent is a reference, not a copy of the %d KB database"
              % (len(vanilla_db) // 1024),
              "%d KB" % (len(parent) // 1024))

        # FragDef must be the mod's ids, or options fail load-time validation.
        frag_def = re.search(r'<AnimDB FragDef="([^"]*)"', parent).group(1)
        ids_name = "hcm_%s_fragmentids.xml" % gender
        check(frag_def.endswith(ids_name),
              "parent FragDef points at the mod's fragment ids", frag_def)

        # The ids file must reach the mod's tag file.
        ids = pak.read(ADB_PREFIX + ids_name).decode("ascii", "replace")
        m = re.search(r'<Tag name="AnimationControlled" subTagDef="([^"]*)"', ids)
        check(m is not None and m.group(1).endswith(build_adb.SHARED_TAGS_NAME),
              "fragment ids point AnimationControlled at the mod's tag file",
              m.group(1) if m else "not declared")

        van_ids = read_pak_text(build_adb.PAK, paths["ids"])
        van_id_tags = set(re.findall(r'<Tag name="([^"]+)"', van_ids))
        our_id_tags = set(re.findall(r'<Tag name="([^"]+)"', ids))
        check(not (van_id_tags - our_id_tags), "no vanilla fragment id dropped",
              sorted(van_id_tags - our_id_tags) or "%d ids" % len(van_id_tags))

        # The controller def must reach that ids file.
        ctrl_name = "hcm_%s_controllerdefs.xml" % gender
        ctrl = pak.read(ADB_PREFIX + ctrl_name).decode("ascii", "replace")
        m = re.search(r'<Fragments filename="([^"]*)"', ctrl)
        check(m is not None and m.group(1).endswith(ids_name),
              "controller def points at the mod's fragment ids",
              m.group(1) if m else "no Fragments element")

        # Every path referenced must actually resolve, in the mod pak or vanilla.
        refs = set(re.findall(r'(?:File|filename|subTagDef)="([^"]+)"',
                              parent + ids + ctrl))
        unresolved = [r for r in refs
                      if r not in shipped and r.replace("/", "\\") not in vanilla_names
                      and r not in vanilla_names]
        check(not unresolved, "every referenced path resolves", unresolved)

    # ---- 6. tags -----------------------------------------------------------
    heading("Tag definitions")

    our_tags = pak.read(ADB_PREFIX + build_adb.SHARED_TAGS_NAME).decode("ascii", "replace")
    van_tags = read_pak_text(build_adb.PAK, build_adb.TAGS_ENTRY)
    vt = set(re.findall(r'<Tag name="([^"]+)"', van_tags))
    ot = set(re.findall(r'<Tag name="([^"]+)"', our_tags))
    check(not (vt - ot), "every vanilla FragTag survives", sorted(vt - ot) or "%d tags" % len(vt))
    wanted = set(t for t, _ in build_adb.STAGGERS)
    check(wanted <= ot, "every stagger FragTag is declared", sorted(wanted - ot))

    # ---- 7. pak hygiene ----------------------------------------------------
    heading("Pak packaging")

    backslashed = [n for n in shipped if "\\" in n]
    check(not backslashed,
          "entry names use forward slashes, so CryEngine can find them",
          backslashed)

    # ---- 8. the Lua redirect ----------------------------------------------
    heading("The Lua redirect targets classes the engine spawns")

    lua = pak.read("Scripts/Startup/HorseCollisionMod.lua").decode("ascii", "replace")
    table = re.search(r"HorseCollisionMod\.AnimationDatabases = \{(.*?)\n\}", lua, re.S)
    redirected = set(re.findall(r"(\w+)\s*=", table.group(1))) if table else set()

    scripts = r"C:\Games\Kingdom Come - Deliverance\Data\Scripts.pak"
    exposed = {}
    if os.path.exists(scripts):
        with zipfile.ZipFile(scripts) as z:
            names = [n for n in z.namelist() if n.lower().endswith(".lua")]
        for n in names:
            try:
                t = build_adb.read_pak_entry(scripts, n).decode("ascii", "replace")
            except Exception:
                continue
            for cls, template in re.findall(
                    r"^\s*(\w+)\s*=\s*Create(?:AI|Actor)\s*\(\s*(\w+)", t, re.M):
                if "AnimDatabase3P" in t or template in redirected:
                    exposed[cls] = template

    human = {c: t for c, t in exposed.items() if t in redirected}
    unredirected = sorted(c for c in human if c not in redirected)
    check(not unredirected,
          "every exposed class built from a redirected template is itself redirected",
          unredirected or "%d classes: %s" % (len(human), ", ".join(sorted(human))))

    check("ActionController" in lua and "AnimDatabase3P" in lua,
          "both properties are redirected, not just the database")

    # ---- verdict -----------------------------------------------------------
    print()
    print("=" * 62)
    if FAILURES:
        print("FAILED %d of %d checks:" % (len(FAILURES), CHECKS[0]))
        for f in FAILURES:
            print("  - %s" % f)
        return 1
    print("All %d checks passed." % CHECKS[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
