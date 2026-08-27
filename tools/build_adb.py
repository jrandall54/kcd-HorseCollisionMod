"""Generates the modded animation data for the walk-speed stagger.

`actor:StartInteractiveActionByName(name, ...)` resolves `name` against the
FragTags of exactly one fragment, `AnimationControlled`. Vanilla ships 30
options there and every one is an object interaction (cabinet_o, alarmBell,
door_*), which is why calling it with a hit-reaction name acquired the NPC's
body and then aborted within a frame - a valid call with no matching option.

Build 2.1.0-dev6 proved the mechanism holds: NPCs played cabinet_o and
alarmBell in full and returned to normal behavior afterwards. Build dev8
proved a modded database really is loaded from a mod pak, using a canary that
repointed cabinet_o at a stagger clip.

Four files are generated and must all ship together:

1. kcd_male_database.adb - adds our options to `AnimationControlled`, each
   pointing at a standing hit-reaction clip the game already contains. The
   hitreaction_idle_* clips are non-additive full-body reactions, so they read
   as a stagger on their own; the combat_hit_small_*_add clips are additive
   and expect a base pose underneath.

2. kcd_animationControlledTags.xml - the fragment's subTagDef, declared at
   kcd_male_fragmentids.xml line 131. **A FragTags value is inert unless it is
   declared here.** Missing this is why dev8's hcm_* options still aborted
   after one frame while the repointed vanilla cabinet_o played correctly.

3. wh_female_fragmentids.xml - the women have the same hit-reaction clips but
   no `AnimationControlled` fragment at all, so it has to be declared before
   anything can be added to it. It reuses the same subTagDef as the men.

4. wh_female_database.adb - the fragment block itself, added wholesale since
   the female database has no existing one to append to.

Run: python tools/build_adb.py
"""

import io
import os
import re
import struct
import sys
import zipfile
import zlib

# Where the game is installed. Resolved rather than hardcoded, because a clone
# only builds when this matches, and it matches on exactly one machine. The
# generated files are derived from the game's own paks, so with no resolvable
# install there is no animation data and the build silently becomes Lua only.
#
# Resolution order: --game-root on the command line, then KCD_PATH in the
# environment, then the usual install locations, then every Steam library in
# libraryfolders.vdf, since a Steam install can sit on any drive.
DEFAULT_ROOTS = [
    r"C:\Games\Kingdom Come - Deliverance",
    r"C:\Program Files (x86)\Steam\steamapps\common\KingdomComeDeliverance",
    r"C:\Program Files\Steam\steamapps\common\KingdomComeDeliverance",
    r"C:\GOG Games\Kingdom Come Deliverance",
    r"C:\Program Files (x86)\GOG Galaxy\Games\Kingdom Come Deliverance",
]

# Presence of this file is what identifies a directory as the game rather than
# just an existing folder, and it is also the file this script reads.
PAK_RELATIVE = os.path.join("Data", "Animations-part1.pak")


def steam_library_roots():
    """Yields a candidate game folder for every Steam library on the machine."""
    try:
        import winreg
    except ImportError:
        return

    steam = None
    keys = [
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam"),
        (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Valve\Steam"),
    ]

    for hive, path in keys:
        try:
            with winreg.OpenKey(hive, path) as key:
                steam = winreg.QueryValueEx(key, "InstallPath")[0]
                break
        except OSError:
            continue

    if not steam:
        return

    vdf = os.path.join(steam, "steamapps", "libraryfolders.vdf")

    if not os.path.exists(vdf):
        return

    with io.open(vdf, "r", encoding="utf-8", errors="replace") as handle:
        body = handle.read()

    # libraryfolders.vdf is Valve's key/value text format. Only the "path"
    # entries matter here, and they carry doubled backslashes.
    for raw in re.findall(r'"path"\s+"([^"]+)"', body):
        library = raw.replace("\\\\", "\\")
        yield os.path.join(library, "steamapps", "common",
                           "KingdomComeDeliverance")


def explicit_root():
    """Returns an (label, path) pair when one was given, else None.

    An explicitly given path is authoritative. Falling through to a different
    install when it is wrong would generate animation data from somewhere the
    caller did not mean, which is a far worse failure than stopping.
    """
    if "--game-root" in sys.argv:
        index = sys.argv.index("--game-root")

        if index + 1 < len(sys.argv):
            return ("--game-root", sys.argv[index + 1])

    if os.environ.get("KCD_PATH"):
        return ("KCD_PATH", os.environ["KCD_PATH"])

    return None


def find_game_root():
    """Returns the game folder, or exits naming every place that was tried."""
    given = explicit_root()

    if given:
        label, root = given

        if os.path.exists(os.path.join(root, PAK_RELATIVE)):
            return root

        raise SystemExit("%s points at %s\nbut %s is not there."
                         % (label, root, PAK_RELATIVE))

    candidates = list(DEFAULT_ROOTS)
    candidates.extend(steam_library_roots())

    for root in candidates:
        if root and os.path.exists(os.path.join(root, PAK_RELATIVE)):
            return root

    tried = "\n  ".join(c for c in candidates if c)

    raise SystemExit(
        "No Kingdom Come: Deliverance install found.\n\n"
        "Looked for %s under:\n  %s\n\n"
        "Point at it with either of:\n"
        '  python tools/build_adb.py --game-root "D:\\path\\to\\game"\n'
        "  set KCD_PATH=D:\\path\\to\\game" % (PAK_RELATIVE, tried))


GAME_ROOT = find_game_root()
PAK = os.path.join(GAME_ROOT, PAK_RELATIVE)
ADB_ENTRY = "Animations/Mannequin/ADB/kcd_male_database.adb"
TAGS_ENTRY = "Animations/Mannequin/ADB/kcd_animationControlledTags.xml"

# Female NPCs need more work than the men. Their database has the same
# hitreaction clips, but wh_female_fragmentids.xml never declares an
# AnimationControlled fragment at all, so there is nothing for
# StartInteractiveActionByName to resolve against. Without this the call is
# accepted and aborts after one frame, which reads in game as a brief twitch.
# Both files therefore have to be patched: the fragment declared, and the
# fragment block added to the database.
FEM_ADB_ENTRY = "Animations/Mannequin/ADB/wh_female_database.adb"
FEM_IDS_ENTRY = "Animations/Mannequin/ADB/wh_female_fragmentids.xml"

# Output lands in mod_assets/ at the repository root, never in the working
# directory. This script lives in tools/ and is run both directly and by
# build.ps1 from elsewhere, so the destination cannot depend on wherever it
# happened to be invoked from.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "mod_assets", "Animations", "Mannequin", "ADB")
ADB_OUT = os.path.join(OUT_DIR, "kcd_male_database.adb")
TAGS_OUT = os.path.join(OUT_DIR, "kcd_animationControlledTags.xml")

# Additive deployment.
#
# The shipped 2.0.0 layout splices the stagger options into copies of the
# vanilla databases and ships those copies, which means any other mod touching
# human animations either loses its changes to this one or takes this one's
# away, depending only on mod_order.txt. Mannequin databases cannot be merged.
#
# Additive mode claims no vanilla filename at all. Each gender gets:
#
#   hcm_<g>_database.adb        a ~340 byte parent, two SubADB references
#     -> the vanilla database, untouched, read from its own pak
#     -> hcm_<g>_stagger.adb, the mod's fragments
#
# and the declarations the fragments need travel under mod names too. Entities
# are pointed at the parent by HorseCollisionMod.lua at startup.
#
# Confirmed in game across four probes; see TESTING_DIARY.md builds
# 2.0.1-dev.15 through dev.19. Opt out with --replace to build the 2.0.0 layout.
ADDITIVE = "--replace" not in sys.argv

# Diagnostic. Adds one option to the mod's sub-database carrying the vanilla
# FragTag cabinet_o, pointing at a stagger clip rather than the cabinet
# animation. That tag is declared in vanilla's tag file and in ours, so tag
# declaration is not a variable: if an NPC asked for cabinet_o staggers, this
# sub-database's options are reaching the merged fragment and winning over
# vanilla's. If they play the cabinet animation, they are not.
#
# The same technique settled a comparable question in build 2.0.0-dev8.
CANARY = "--canary" in sys.argv
CANARY_TAG = "cabinet_o"

# Per gender: vanilla database, vanilla fragment ids, vanilla tag definition.
GENDERS = {
    "male": {
        "db": "Animations/Mannequin/ADB/kcd_male_database.adb",
        "ids": "Animations/Mannequin/ADB/kcd_male_fragmentids.xml",
        "tags": "Animations/Mannequin/ADB/kcd_male_tags.xml",
        "ctrl": "Animations/Mannequin/ADB/kcd_male_controllerdefs.xml",
    },
    "female": {
        "db": "Animations/Mannequin/ADB/wh_female_database.adb",
        "ids": "Animations/Mannequin/ADB/wh_female_fragmentids.xml",
        "tags": "Animations/Mannequin/ADB/wh_female_tags.xml",
        "ctrl": "Animations/Mannequin/ADB/wh_female_controllerdefs.xml",
    },
}

# The one tag file both genders share, holding the four hcm_stagger_* FragTags.
# A copy of vanilla plus our group rather than a reference: unlike a database,
# a tag definition has no include mechanism. It never collides, because the
# name is ours, but it also cannot pick up another mod's additions to the same
# group. Acceptable here because nothing else is likely to extend
# AnimationControlled; it would not be for a mod that had to share a group.
SHARED_TAGS_NAME = "hcm_animationControlledTags.xml"

# Taken from the vanilla male header so the sub-database resolves fragment ids
# and tags against exactly the same definitions.
FRAG_DEF = "Animations/Mannequin/ADB/kcd_male_fragmentids.xml"
TAG_DEF = "Animations/Mannequin/ADB/kcd_male_tags.xml"

SUBADB_ENTRY = "Animations/Mannequin/ADB/hcm_male_stagger.adb"
SUBADB_OUT = os.path.join(OUT_DIR, "hcm_male_stagger.adb")

FEM_ADB_OUT = os.path.join(OUT_DIR, "wh_female_database.adb")
FEM_IDS_OUT = os.path.join(OUT_DIR, "wh_female_fragmentids.xml")

# FragTags name -> clip. The direction suffix matches what the Lua sends,
# which is GetImpactDir's so_* result with "so_" stripped, hence "forward"
# rather than "front" even though the clip names say front.
#
# Heavier hcm_shove_* entries pointing at hitreaction_idle_heavy_* existed
# briefly, but nothing referenced them, so they were removed rather than left
# as dead data. Add them back here when the trot tier moves off the physics
# ragdoll.
STAGGERS = [
    ("hcm_stagger_forward", "hitreaction_idle_medium_torso_stab_front"),
    ("hcm_stagger_back", "hitreaction_idle_medium_torso_stab_back"),
    ("hcm_stagger_left", "hitreaction_idle_medium_torso_stab_left"),
    ("hcm_stagger_right", "hitreaction_idle_medium_torso_stab_right"),
]

# Collider mode held for the duration of the stagger, or None to declare no
# ColliderMode layer at all.
#
# Build 2.0.0 shipped "Disabled" on the theory that it would stop the horse
# snagging on a victim who is mid-stagger and cannot step aside. It did not,
# and it is a departure from vanilla: the clips these options play live on the
# HitDeath fragment in the stock database, and neither of the two options
# there declares a ColliderMode layer. Disabling an actor's colliders while a
# physicalized item is attached to their hand is the leading explanation for
# NPCs dropping baskets and buckets when they stagger.
#
# None therefore matches vanilla. Set to "Disabled" or "Interactive" only with
# an in-game result to justify it.
COLLIDER_MODE = None

# Modeled on the vanilla HitDeath option that plays these same clips
# (FragTags "so_forward+minor_hit"), rather than on an object interaction.
# The camera layer is dropped because it aims the player's camera and the
# victim here is never the player. MovementControlMethod is added so the
# animation drives the body, which an interactive action needs and a natively
# triggered hit reaction does not.
TEMPLATE = """      <Fragment BlendOutDuration="0.2" Tags="" FragTags="{tags}">
        <AnimLayer>
          <Blend ExitTime="0" StartTime="0" Duration="0.2" />
          <Animation name="{clip}" />
        </AnimLayer>
        <ProcLayer>
          <Blend ExitTime="0" StartTime="0" Duration="0.2" />
          <Procedural type="MovementControlMethod">
            <ProceduralParams>
              <Horizontal value="2" />
              <Vertical value="0" />
              <XyMove value="0" />
              <ZMove value="0" />
              <Rotate value="0" />
              <Velocity value="0" />
              <Inertia value="0" />
            </ProceduralParams>
          </Procedural>
        </ProcLayer>{collider}
      </Fragment>"""

COLLIDER_LAYER = """
        <ProcLayer>
          <Blend ExitTime="0" StartTime="0" Duration="0.2" />
          <Procedural type="ColliderMode">
            <ProceduralParams>
              <ColliderMode value="%s" />
            </ProceduralParams>
          </Procedural>
        </ProcLayer>"""


def read_pak_entry(pak, entry):
    """Reads one entry from a KCD pak.

    KCD paks store forward slashes in the central directory but backslashes
    in the local file headers. Python's zipfile treats that mismatch as
    corruption and refuses to read, so the entry is located through the
    central directory and inflated straight from its local header.
    """
    with zipfile.ZipFile(pak) as archive:
        info = archive.getinfo(entry)

    with io.open(pak, "rb") as handle:
        handle.seek(info.header_offset)
        header = handle.read(30)

        if header[:4] != b"PK\x03\x04":
            raise SystemExit("bad local header for %s" % entry)

        name_len, extra_len = struct.unpack("<HH", header[26:30])
        handle.seek(info.header_offset + 30 + name_len + extra_len)
        blob = handle.read(info.compress_size)

    if info.compress_type == zipfile.ZIP_STORED:
        return blob

    return zlib.decompress(blob, -15)


def newline_of(text):
    if "\r\n" in text:
        return "\r\n"

    return "\n"


def render_option(tags, clip, nl):
    """Renders one Fragment option with the file's own line endings."""
    collider = ""

    if COLLIDER_MODE:
        collider = COLLIDER_LAYER % COLLIDER_MODE

    option = TEMPLATE.format(tags=tags, clip=clip, collider=collider)

    return option.replace("\n", nl)


def write_subadb_database(raw, nl, added):
    """Writes the stagger options into their own database, referenced as a SubADB.

    CryEngine's Mannequin loader can assemble one database from several files.
    No vanilla KCD .adb uses it, all 28 of them splice everything into one
    document, but the loader is present in WHGame.dll:

        SubADBs
        Loading subADB %s
        [CAnimationDatabaseManager::LoadDatabase] Unknown tags %s for subADB %s

    If this works, the mod's fragments live in a file nothing else touches and
    the edit to the vanilla database shrinks to a three-line reference, which
    is the difference between a conflict another animation mod cannot resolve
    and one they can merge by hand.

    Emitted without a Tags filter deliberately. The error string above shows
    Tags is validated against the tag definition, so an unfiltered SubADB is
    the case least likely to fail for a reason unrelated to the question being
    asked.
    """
    sub = [
        '<?xml version="1.0" encoding="us-ascii"?>',
        '<AnimDB FragDef="%s" TagDef="%s">' % (FRAG_DEF, TAG_DEF),
        "  <FragmentList>",
        "    <AnimationControlled>",
        added,
        "    </AnimationControlled>",
        "  </FragmentList>",
        "</AnimDB>",
        "",
    ]

    with io.open(SUBADB_OUT, "wb") as handle:
        handle.write(nl.join(sub).encode("ascii"))

    reference = nl.join([
        "  <SubADBs>",
        '    <SubADB File="%s" />' % SUBADB_ENTRY,
        "  </SubADBs>",
    ])

    anchor = nl + "</AnimDB>"
    patched = raw.replace(anchor, nl + reference + anchor, 1)

    if patched == raw:
        raise SystemExit("SubADBs insertion anchor not matched")

    with io.open(ADB_OUT, "wb") as handle:
        handle.write(patched.encode("ascii"))

    print("SubADB mode: %d options in their own database" % len(STAGGERS))
    print("wrote %s (%d bytes)" % (SUBADB_OUT, os.path.getsize(SUBADB_OUT)))
    print("wrote %s (%d bytes, vanilla + %d)"
          % (ADB_OUT, os.path.getsize(ADB_OUT), len(patched) - len(raw)))


def write_database():
    raw = read_pak_entry(PAK, ADB_ENTRY).decode("ascii", "replace")
    nl = newline_of(raw)

    # Every referenced clip must already exist, otherwise the option resolves
    # to nothing silently - the exact failure mode this project spent a dozen
    # builds chasing.
    present = set(re.findall(r'<Animation name="([^"]*)"', raw))
    missing = [clip for _, clip in STAGGERS if clip not in present]

    if missing:
        raise SystemExit("clips absent from the database: %s" % missing)

    block = re.search(
        r"\n    <AnimationControlled>(.*?)\n    </AnimationControlled>", raw, re.S)

    if not block:
        raise SystemExit("AnimationControlled fragment not found")

    added = nl.join(
        render_option(tags, clip, nl) for tags, clip in STAGGERS)

    if USE_SUBADB:
        write_subadb_database(raw, nl, added)
        return

    anchor = nl + "    </AnimationControlled>"
    patched = raw.replace(anchor, nl + added + anchor, 1)

    if patched == raw:
        raise SystemExit("database insertion anchor not matched")

    with io.open(ADB_OUT, "wb") as handle:
        handle.write(patched.encode("ascii"))

    before = len(re.findall(r"<Fragment", block.group(1)))
    print("AnimationControlled options: %d -> %d" % (before, before + len(STAGGERS)))

    for tags, clip in STAGGERS:
        print("  + %-22s -> %s" % (tags, clip))

    print("wrote %s (%d bytes)" % (ADB_OUT, os.path.getsize(ADB_OUT)))


def write_tags():
    raw = read_pak_entry(PAK, TAGS_ENTRY).decode("ascii", "replace")
    nl = newline_of(raw)

    group = ['    <Group name="HcmReaction">']
    group = group + ['      <Tag name="%s" />' % tags for tags, _ in STAGGERS]
    group = group + ["    </Group>"]

    anchor = nl + "  </Tags>"
    patched = raw.replace(anchor, nl + nl.join(group) + anchor, 1)

    if patched == raw:
        raise SystemExit("tag insertion anchor not matched")

    with io.open(TAGS_OUT, "wb") as handle:
        handle.write(patched.encode("ascii"))

    print("wrote %s (%d tags declared)" % (TAGS_OUT, len(STAGGERS)))


def write_female():
    """Adds an AnimationControlled fragment to the female character set."""
    ids = read_pak_entry(PAK, FEM_IDS_ENTRY).decode("ascii", "replace")
    nl = newline_of(ids)

    if "AnimationControlled" not in ids:
        declaration = ('    <Tag name="AnimationControlled" subTagDef="%s" />'
                       % TAGS_ENTRY)
        anchor = nl + "  </Tags>"
        ids = ids.replace(anchor, nl + declaration + anchor, 1)

        if anchor not in ids:
            raise SystemExit("female fragmentids anchor not matched")

    with io.open(FEM_IDS_OUT, "wb") as handle:
        handle.write(ids.encode("ascii"))

    raw = read_pak_entry(PAK, FEM_ADB_ENTRY).decode("ascii", "replace")
    nl = newline_of(raw)

    present = set(re.findall(r'<Animation name="([^"]*)"', raw))
    missing = [clip for _, clip in STAGGERS if clip not in present]

    if missing:
        raise SystemExit("clips absent from the female database: %s" % missing)

    options = nl.join(
        render_option(tags, clip, nl) for tags, clip in STAGGERS)
    block = (nl + "    <AnimationControlled>"
             + nl + options
             + nl + "    </AnimationControlled>")

    anchor = nl + "  </FragmentList>"

    if anchor not in raw:
        raise SystemExit("female FragmentList anchor not matched")

    patched = raw.replace(anchor, block + anchor, 1)

    with io.open(FEM_ADB_OUT, "wb") as handle:
        handle.write(patched.encode("ascii"))

    print("female: declared AnimationControlled and added %d options"
          % len(STAGGERS))
    print("wrote %s (%d bytes)" % (FEM_ADB_OUT, os.path.getsize(FEM_ADB_OUT)))


def out(name):
    """Path of a generated file in mod_assets."""
    return os.path.join(OUT_DIR, name)


def write_shared_tags(nl):
    """The FragTags the stagger options carry, under a name nothing else uses.

    A copy of the vanilla AnimationControlled tag definition plus one group.
    Tag definitions have no include mechanism, so unlike a database this cannot
    be a reference to the vanilla file. It never collides, because the filename
    is ours, but it also cannot see another mod's additions to the same group.
    """
    raw = read_pak_entry(PAK, TAGS_ENTRY).decode("ascii", "replace")

    group = ['    <Group name="HcmReaction">']
    group += ['      <Tag name="%s" />' % tags for tags, _ in STAGGERS]
    group += ["    </Group>"]

    anchor = nl + "  </Tags>"
    patched = raw.replace(anchor, nl + nl.join(group) + anchor, 1)

    if patched == raw:
        raise SystemExit("shared tag anchor not matched")

    with io.open(out(SHARED_TAGS_NAME), "wb") as handle:
        handle.write(patched.encode("ascii"))

    return "Animations/Mannequin/ADB/" + SHARED_TAGS_NAME


def write_additive_gender(gender, paths, shared_tags, nl):
    """Writes the three files one gender needs, claiming no vanilla name."""
    ids_name = "hcm_%s_fragmentids.xml" % gender
    stagger_name = "hcm_%s_stagger.adb" % gender
    parent_name = "hcm_%s_database.adb" % gender

    ids = read_pak_entry(PAK, paths["ids"]).decode("ascii", "replace")

    # The women have the same hit-reaction clips but no AnimationControlled
    # fragment at all, so it has to be declared before anything can be added to
    # it. The men already have one, and only its subTagDef needs repointing.
    if "AnimationControlled" not in ids:
        declaration = ('    <Tag name="AnimationControlled" subTagDef="%s" />'
                       % shared_tags)
        anchor = nl + "  </Tags>"
        ids = ids.replace(anchor, nl + declaration + anchor, 1)

        if declaration not in ids:
            raise SystemExit("%s fragmentids anchor not matched" % gender)
    else:
        ids = ids.replace(TAGS_ENTRY, shared_tags)

        if shared_tags not in ids:
            raise SystemExit("%s subTagDef reference not found" % gender)

    with io.open(out(ids_name), "wb") as handle:
        handle.write(ids.encode("ascii"))

    # The controller def is what an entity actually resolves fragments and
    # tags through at runtime, by way of its ActionController property. A
    # database's own FragDef governs load-time validation only. Without this
    # the stagger options load and validate cleanly, and then every call
    # against them resolves to nothing, because the entity is still looking
    # them up in vanilla's tag file where hcm_stagger_* is not declared.
    ctrl_name = "hcm_%s_controllerdefs.xml" % gender
    ctrl = read_pak_entry(PAK, paths["ctrl"]).decode("ascii", "replace")
    ctrl = ctrl.replace(paths["ids"], "Animations/Mannequin/ADB/" + ids_name)

    if ids_name not in ctrl:
        raise SystemExit("%s controller def Fragments element not matched" % gender)

    with io.open(out(ctrl_name), "wb") as handle:
        handle.write(ctrl.encode("ascii"))

    # Every referenced clip must already exist in that gender's database, or
    # the option resolves to nothing silently.
    db = read_pak_entry(PAK, paths["db"]).decode("ascii", "replace")
    present = set(re.findall(r'<Animation name="([^"]*)"', db))
    missing = [clip for _, clip in STAGGERS if clip not in present]

    if missing:
        raise SystemExit("clips absent from the %s database: %s"
                         % (gender, missing))

    entries = list(STAGGERS)

    if CANARY:
        entries.append((CANARY_TAG, STAGGERS[0][1]))

    options = nl.join(render_option(tags, clip, nl) for tags, clip in entries)

    # Sub-databases do not merge options into a fragment another one already
    # defines: the later sub replaces that fragment outright. Proven with a
    # canary carrying the vanilla cabinet_o tag, which played vanilla's
    # cabinet animation rather than this mod's clip while vanilla's
    # sub-database was listed second.
    #
    # So this file has to carry vanilla's own options too, or redirected
    # entities lose every door, cabinet and wardrobe interaction. It is still
    # only the one fragment: 69 KB against the 5.5 MB whole database.
    existing = re.search(
        "\n    <AnimationControlled>(.*?)\n    </AnimationControlled>", db, re.S)

    if existing:
        inherited = existing.group(1).strip("\r\n")
        options = inherited + nl + options
        print("  %-6s inherits %d vanilla options"
              % (gender, inherited.count("<Fragment")))

    stagger = nl.join([
        '<?xml version="1.0" encoding="us-ascii"?>',
        '<AnimDB FragDef="Animations/Mannequin/ADB/%s" TagDef="%s">'
        % (ids_name, paths["tags"]),
        "  <FragmentList>",
        "    <AnimationControlled>",
        options,
        "    </AnimationControlled>",
        "  </FragmentList>",
        "</AnimDB>",
        "",
    ])

    with io.open(out(stagger_name), "wb") as handle:
        handle.write(stagger.encode("ascii"))

    # The parent holds no fragments of its own. The vanilla database is read
    # from its own pak and is never overridden, which is the whole point.
    #
    # FragDef must be OUR fragment ids, not vanilla's. The parent's FragDef is
    # what the loader resolves FragTags against; a sub-database's own FragDef
    # does not govern that, despite being honoured for other purposes. With
    # vanilla's here the chain reaches vanilla's tag file, which declares no
    # hcm_stagger_* tag, and every option is rejected with:
    #
    #   [CAnimationDatabaseManager::LoadDatabase] Unknown tags for fragmentID
    #       AnimationControlled tag  fragTags hcm_stagger_forward
    #
    # which reads in game as the one-frame snap back, the signature of a valid
    # call with no matching option.
    parent = nl.join([
        '<?xml version="1.0" encoding="us-ascii"?>',
        '<AnimDB FragDef="Animations/Mannequin/ADB/%s" TagDef="%s">'
        % (ids_name, paths["tags"]),
        "  <SubADBs>",
        # Order matters: both sub-databases define the AnimationControlled
        # fragment, vanilla with 30 options and this mod with 4. If a
        # fragment, and the later one replaces the earlier outright rather
        # than merging. This mod's file therefore goes last, and carries
        # vanilla's options as well as its own.
        '    <SubADB File="%s" />' % paths["db"],
        '    <SubADB File="Animations/Mannequin/ADB/%s" />' % stagger_name,
        "  </SubADBs>",
        "</AnimDB>",
        "",
    ])

    with io.open(out(parent_name), "wb") as handle:
        handle.write(parent.encode("ascii"))

    print("  %-6s %s (%d B), %s (%d B), %s (%d B), %s (%d B)"
          % (gender, parent_name, os.path.getsize(out(parent_name)),
             stagger_name, os.path.getsize(out(stagger_name)),
             ids_name, os.path.getsize(out(ids_name)),
             ctrl_name, os.path.getsize(out(ctrl_name))))


def write_additive():
    """Generates the whole additive layout, overriding no vanilla file."""
    nl = newline_of(read_pak_entry(PAK, TAGS_ENTRY).decode("ascii", "replace"))
    shared_tags = write_shared_tags(nl)

    print("Additive layout, %d options per gender:" % len(STAGGERS))

    for gender, paths in sorted(GENDERS.items()):
        write_additive_gender(gender, paths, shared_tags, nl)

    print("  shared %s (%d B)"
          % (SHARED_TAGS_NAME, os.path.getsize(out(SHARED_TAGS_NAME))))

    for tags, clip in STAGGERS:
        print("  + %-22s -> %s" % (tags, clip))

    # A file left over from a previous --replace build would still be an
    # override, and would quietly undo everything this mode is for.
    for stale in ["kcd_male_database.adb", "kcd_animationControlledTags.xml",
                  "wh_female_database.adb", "wh_female_fragmentids.xml"]:
        path = out(stale)

        if os.path.exists(path):
            os.remove(path)
            print("  removed stale override: %s" % stale)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    if ADDITIVE:
        write_additive()
        return

    write_database()
    write_tags()
    write_female()


if __name__ == "__main__":
    main()
