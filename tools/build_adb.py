"""Generates this mod's animation data.

`actor:StartInteractiveActionByName(name, ...)` resolves `name` against the
FragTags of exactly one fragment, `AnimationControlled`. Vanilla ships 30
options there and every one is an object interaction (cabinet_o, alarmBell,
door_*), so calling it with a hit-reaction name acquires the NPC's body and
aborts within a frame: a valid call with no matching option.

Before 2.1.0, adding an option meant shipping a modified copy of the 5.5 MB
vanilla database under its own name. Two mods cannot both do that: the later
one in mod_order.txt wins and the other's changes vanish with no error.

Four files are generated now, and the two large databases are referenced
rather than replaced:

  hcm_<set>_database.adb           the parent, and the authoritative
                                   definition of AnimationControlled. Carries
                                   vanilla's own options plus this mod's, and
                                   references the untouched vanilla database
                                   as a SubADB for every other fragment.
  kcd_animationControlledTags.xml  vanilla's 16 FragTags plus this mod's 4.
  wh_female_fragmentids.xml        declares AnimationControlled for the
                                   women, who have no such fragment at all.

The last two keep vanilla's names deliberately. Giving them mod names means
restating the fragment id and controller definitions, 123 KB of vanilla data,
and putting this mod in the resolution path of every human animation rather
than just its own, which is what broke unrelated animations in an earlier
layout. Owning 15 KB of declarations is the smaller thing to own.

HorseCollisionMod.lua then points the human entity classes' AnimDatabase3P
at the parent. ActionController is deliberately left alone.

Three conditions have to hold at once. See
TESTING_DIARY.md, builds 2.0.1-dev.15 through 2.1.0.

1. The parent must be the one defining AnimationControlled. Sub-databases do
   not merge options into a fragment another database already defines.
2. The parent must therefore carry vanilla's options too, or redirected NPCs
   lose every door, cabinet and wardrobe interaction in the game.
3. The classes redirected must be the ones the engine spawns. NPC_x is a
   template; NPC = CreateAI(NPC_x) copies its fields, so redirecting the
   template changes nothing about what spawns.

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

# The subTagDef for the AnimationControlled fragment. This mod ships its own
# version of this file, under this same name, with four tags added.
TAGS_ENTRY = "Animations/Mannequin/ADB/kcd_animationControlledTags.xml"

# Output lands in mod_assets/ at the repository root, never in the working
# directory. This script lives in tools/ and is run both directly and by
# build.ps1 from elsewhere, so the destination cannot depend on wherever it
# happened to be invoked from.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "mod_assets", "Animations", "Mannequin", "ADB")

# Every vanilla file this reads, per character set. All three are read only.
#
#   db    the stock animation database, referenced from the mod's parent as a
#         SubADB so it is never copied or replaced
#   ids   the fragment id definitions, copied so AnimationControlled can be
#         pointed at the mod's tag file
#   ctrl  the controller def, copied so the ids copy above is what entities
#         resolve names through at runtime
#   tags  the character set's tag definitions, referenced unchanged
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


def out(name):
    """Path of a generated file in mod_assets."""
    return os.path.join(OUT_DIR, name)


def write_shared_tags(nl):
    """Adds the stagger FragTags to the AnimationControlled tag definition.

    Written under vanilla's own name, deliberately.

    The alternative, shipping it as hcm_animationControlledTags.xml, means
    every entity has to be pointed at a copy of the fragment id file to reach
    it, and that file at a copy of the controller def. Those two copies are
    123 KB of vanilla data restated under mod names, and they sit in the
    resolution path of every fragment a human uses, not just this mod's.
    An earlier layout did that, and unrelated animations stopped playing: the
    beggar's kneeling resolves through BeggarIn and kcd_beggar_tags.xml,
    nothing to do with this mod, but it travels through the same copied
    files.

    Replacing 1 KB of tag names is a far smaller thing to own than restating
    the whole fragment and controller definitions, and it leaves every
    unrelated animation on vanilla's own path.
    """
    raw = read_pak_entry(PAK, TAGS_ENTRY).decode("ascii", "replace")

    group = ['    <Group name="HcmReaction">']
    group += ['      <Tag name="%s" />' % tags for tags, _ in STAGGERS]
    group += ["    </Group>"]

    anchor = nl + "  </Tags>"
    patched = raw.replace(anchor, nl + nl.join(group) + anchor, 1)

    if patched == raw:
        raise SystemExit("shared tag anchor not matched")

    name = TAGS_ENTRY.rsplit("/", 1)[-1]

    with io.open(out(name), "wb") as handle:
        handle.write(patched.encode("ascii"))

    print("  tags   %s (%d B, %d vanilla + %d added)"
          % (name, os.path.getsize(out(name)),
             raw.count("<Tag "), len(STAGGERS)))


def write_female_declaration(paths, nl):
    """Declares AnimationControlled for the women, who have no such fragment.

    Also under vanilla's name. The men already declare it and need no change
    here at all.
    """
    ids = read_pak_entry(PAK, paths["ids"]).decode("ascii", "replace")

    if "AnimationControlled" in ids:
        raise SystemExit("the female fragment ids already declare it; "
                         "this patch is no longer needed")

    declaration = ('    <Tag name="AnimationControlled" subTagDef="%s" />'
                   % TAGS_ENTRY)
    anchor = nl + "  </Tags>"
    patched = ids.replace(anchor, nl + declaration + anchor, 1)

    if patched == ids:
        raise SystemExit("female fragment ids anchor not matched")

    name = paths["ids"].rsplit("/", 1)[-1]

    with io.open(out(name), "wb") as handle:
        handle.write(patched.encode("ascii"))

    print("  female %s (%d B, declares AnimationControlled)"
          % (name, os.path.getsize(out(name))))


def write_parent(gender, paths, nl):
    """Writes the one file that carries this mod's options.

    It is the authoritative definition of AnimationControlled, so it has to
    carry vanilla's own options as well as this mod's: a sub-database does not
    merge into a fragment another database defines, and without them a
    redirected NPC loses every door, cabinet and wardrobe interaction.

    Everything else a human animates with is reached by reference, through a
    SubADB pointing at the untouched vanilla database inside its own pak.
    """
    db = read_pak_entry(PAK, paths["db"]).decode("ascii", "replace")

    present = set(re.findall(r'<Animation name="([^"]*)"', db))
    missing = [clip for _, clip in STAGGERS if clip not in present]

    if missing:
        raise SystemExit("clips absent from the %s database: %s"
                         % (gender, missing))

    options = nl.join(render_option(tags, clip, nl) for tags, clip in STAGGERS)

    existing = re.search(
        "\n    <AnimationControlled>(.*?)\n    </AnimationControlled>", db, re.S)

    inherited = 0

    if existing:
        block = existing.group(1).strip("\r\n")
        inherited = block.count("<Fragment ")
        options = block + nl + options

    name = "hcm_%s_database.adb" % gender
    parent = nl.join([
        '<?xml version="1.0" encoding="us-ascii"?>',
        '<AnimDB FragDef="%s" TagDef="%s">' % (paths["ids"], paths["tags"]),
        "  <FragmentList>",
        "    <AnimationControlled>",
        options,
        "    </AnimationControlled>",
        "  </FragmentList>",
        "  <SubADBs>",
        '    <SubADB File="%s" />' % paths["db"],
        "  </SubADBs>",
        "</AnimDB>",
        "",
    ])

    with io.open(out(name), "wb") as handle:
        handle.write(parent.encode("ascii"))

    print("  %-6s %s (%d B, %d vanilla options + %d added)"
          % (gender, name, os.path.getsize(out(name)), inherited, len(STAGGERS)))

def write_additive():
    """Generates the whole layout."""
    nl = newline_of(read_pak_entry(PAK, TAGS_ENTRY).decode("ascii", "replace"))

    print("Additive layout, %d options per character set:" % len(STAGGERS))

    for gender, paths in sorted(GENDERS.items()):
        write_parent(gender, paths, nl)

    write_shared_tags(nl)
    write_female_declaration(GENDERS["female"], nl)

    for tags, clip in STAGGERS:
        print("  + %-22s -> %s" % (tags, clip))

    # A file from an earlier layout would still be an override and would
    # quietly change which chain entities resolve through.
    keep = set(["hcm_male_database.adb", "hcm_female_database.adb",
                TAGS_ENTRY.rsplit("/", 1)[-1],
                GENDERS["female"]["ids"].rsplit("/", 1)[-1]])

    for stale in sorted(set(os.listdir(OUT_DIR)) - keep):
        os.remove(out(stale))
        print("  removed stale file: %s" % stale)

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write_additive()


if __name__ == "__main__":
    main()
