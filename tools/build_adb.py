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


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write_database()
    write_tags()
    write_female()


if __name__ == "__main__":
    main()
