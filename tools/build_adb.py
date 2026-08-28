"""Generates this mod's animation data, without replacing any vanilla file.

`actor:StartInteractiveActionByName(name, ...)` resolves `name` against the
FragTags of exactly one fragment, `AnimationControlled`. Vanilla ships 30
options there and every one is an object interaction (cabinet_o, alarmBell,
door_*), so calling it with a hit-reaction name acquires the NPC's body and
aborts within a frame: a valid call with no matching option.

Adding an option to that fragment used to mean shipping a modified copy of
the 5.5 MB vanilla database under its own name, which meant any other mod
touching human animations either lost its changes to this one or took this
one's away, silently, decided only by mod_order.txt.

This generates an additive layout instead. Seven files, all named hcm_*, so
none of them collides with anything:

  hcm_<set>_database.adb        the parent, and the authoritative definition
                                of AnimationControlled. Carries vanilla's own
                                30 options plus this mod's 4, and references
                                the untouched vanilla database as a SubADB
                                for every other fragment.
  hcm_<set>_fragmentids.xml     vanilla's fragment ids, with
                                AnimationControlled's subTagDef pointed at
                                the tag file below. For the female set it
                                also declares that fragment, which vanilla
                                does not have at all.
  hcm_<set>_controllerdefs.xml  vanilla's controller def, with its Fragments
                                element pointed at the ids file above.
  hcm_animationControlledTags.xml   vanilla's 16 FragTags plus this mod's 4.

HorseCollisionMod.lua then points the human entity classes at the parent
through their AnimDatabase3P and ActionController properties.

Four things have to hold at once, and each was found the hard way. See
TESTING_DIARY.md, builds 2.0.1-dev.15 through 2.1.0.

1. The parent must be the one defining AnimationControlled. Sub-databases do
   not merge options into a fragment another database already defines.
2. The parent must therefore carry vanilla's options too, or redirected NPCs
   lose every door, cabinet and wardrobe interaction in the game.
3. The parent's FragDef must be the mod's fragment ids, or the options fail
   load-time validation with 'Unknown tags for fragmentID AnimationControlled'.
4. ActionController must be redirected as well as AnimDatabase3P. The
   controller def owns what an entity resolves names through at runtime; a
   database's FragDef governs load-time validation only.

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

# The vanilla subTagDef for the AnimationControlled fragment. Read to build
# the mod's own copy of it, never overwritten.
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

# The one tag file both character sets share, holding the four hcm_stagger_*
# FragTags. A copy of vanilla plus the mod's group rather than a reference:
# unlike a database, a tag definition has no include mechanism. It never
# collides, because the name is the mod's, but it also cannot pick up another
# mod's additions to the same group.
SHARED_TAGS_NAME = "hcm_animationControlledTags.xml"

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

    options = nl.join(render_option(tags, clip, nl) for tags, clip in STAGGERS)

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

    # The mod's fragment goes in the PARENT's own FragmentList, not in a
    # sub-database.
    #
    # Sub-databases were tried both first and last, and vanilla's copy of the
    # AnimationControlled fragment won either way, so ordering is not what
    # decides it. A parent is the primary database and its sub-databases
    # supplement what it does not itself define, which makes the parent the
    # only place a definition can be authoritative.
    #
    # It carries vanilla's own options as well as the mod's, or a redirected
    # NPC loses every door, cabinet and wardrobe interaction.
    parent = nl.join([
        '<?xml version="1.0" encoding="us-ascii"?>',
        '<AnimDB FragDef="Animations/Mannequin/ADB/%s" TagDef="%s">'
        % (ids_name, paths["tags"]),
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

    with io.open(out(parent_name), "wb") as handle:
        handle.write(parent.encode("ascii"))

    # No separate stagger file in this layout; remove a stale one so it cannot
    # be mistaken for part of the build.
    stale_stagger = out(stagger_name)

    if os.path.exists(stale_stagger):
        os.remove(stale_stagger)
    print("  %-6s %s (%d B), %s (%d B), %s (%d B)"
          % (gender, parent_name, os.path.getsize(out(parent_name)),
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
    write_additive()


if __name__ == "__main__":
    main()
