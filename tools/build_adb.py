"""Generates this mod's animation data.

`actor:StartInteractiveActionByName(name, ...)` resolves `name` against the
FragTags of exactly one fragment, `AnimationControlled`. Vanilla's options
there, 32 on the male set in the patched game, are all object interactions
(cabinet_o, alarmBell, door_*), so calling it with a hit-reaction name
acquires the NPC's body and aborts within a frame: a valid call with no
matching option.

Adding options by shipping a modified copy of the vanilla database under its
own name does not combine: two mods cannot both do it, since the later one in
mod_order.txt wins and the other's changes vanish with no error. So three
files are generated, and the large vanilla databases are referenced rather
than replaced:

  hcm_<set>_database.adb           the parent, one per character set, and the
                                   authoritative definition of
                                   AnimationControlled. Carries vanilla's own
                                   options plus this mod's, and references the
                                   untouched vanilla database as a SubADB for
                                   every other fragment.
  kcd_animationControlledTags.xml  vanilla's FragTags plus this mod's reaction
                                   tags and the horse's two.

The tag file keeps vanilla's name deliberately. Giving it a mod name means
restating the fragment id and controller definitions, 123 KB of vanilla data,
and putting this mod in the resolution path of every human animation rather
than just its own.

HorseCollisionMod.lua then points the human entity classes' AnimDatabase3P
at the parent. ActionController is deliberately left alone.

Three conditions have to hold at once:

1. The parent must be the one defining AnimationControlled. Sub-databases do
   not merge options into a fragment another database already defines.
2. The parent must therefore carry vanilla's options too, or redirected NPCs
   lose every door, cabinet and wardrobe interaction in the game.
3. The classes redirected must be the ones the engine spawns. NPC_x is a
   template; NPC = CreateAI(NPC_x) copies its fields, so redirecting the
   template changes nothing about what spawns.

Run: python tools/build_adb.py
"""

import glob
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

# FragTags used by the hand-authored horse database. Declared here because this
# is the tag file the mod ships and the horse database is not generated.
HORSE_TAGS = ("hcm_rear", "hcm_rear_charge")

# The subTagDef for the AnimationControlled fragment. This mod ships its own
# version of this file, under this same name, with its tags added.
TAGS_ENTRY = "Animations/Mannequin/ADB/kcd_animationControlledTags.xml"

# Output lands in mod_assets/ at the repository root, never in the working
# directory. This script lives in tools/ and is run both directly and by
# build.ps1 from elsewhere, so the destination cannot depend on wherever it
# happened to be invoked from.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "mod_assets", "Animations", "Mannequin", "ADB")

# The vanilla files each character set's parent names. None is copied.
#
#   db    the stock animation database: read for its AnimationControlled
#         options, and referenced from the parent as a SubADB
#   ids   the fragment id definitions, the parent's FragDef
#   tags  the character set's tag definitions, the parent's TagDef
GENDERS = {
    "male": {
        "db": "Animations/Mannequin/ADB/kcd_male_database.adb",
        "ids": "Animations/Mannequin/ADB/kcd_male_fragmentids.xml",
        "tags": "Animations/Mannequin/ADB/kcd_male_tags.xml",
    },
    "female": {
        "db": "Animations/Mannequin/ADB/wh_female_database.adb",
        "ids": "Animations/Mannequin/ADB/wh_female_fragmentids.xml",
        "tags": "Animations/Mannequin/ADB/wh_female_tags.xml",
    },
}


# FragTags name -> clip. The direction suffix matches what the Lua sends,
# which is GetImpactDir's so_* result with "so_" stripped, hence "forward"
# rather than "front" even though the clip names say front.
BOTH = ("male", "female")
MALE_ONLY = ("male",)

REACTIONS = [
    # Stagger: a standing hit reaction.
    ("hcm_stagger_forward", "hitreaction_idle_medium_torso_stab_front", BOTH),
    ("hcm_stagger_back", "hitreaction_idle_medium_torso_stab_back", BOTH),
    ("hcm_stagger_left", "hitreaction_idle_medium_torso_stab_left", BOTH),
    ("hcm_stagger_right", "hitreaction_idle_medium_torso_stab_right", BOTH),

    # Knockdown: an animated fall and get-up. Vanilla plays the falls on its own
    # HitDeath fragment under `so_forward+death` with `Tags="walk"`, for a
    # person collapsing while walking, which is the shape of a knockdown.
    # Both character sets have all four.
    # The get-up is paired to the pose the fall ends in, which the shared
    # direction word does not tell you. Front and back swap; left and right
    # keep their own. Every pair was found by playing one fall against all
    # four get-ups on a staged subject, on both character sets, and keeping
    # the one that did not rotate the root: a get-up authored from the wrong
    # side snaps the body to reach its own start pose, and at ground level
    # that drives it through the road.
    #
    # The back fall is the weak one. It is clean on a woman and keeps about
    # ninety degrees on a man, and no get-up does better for him, so the
    # rotation there is inherent to chaining these two clips rather than a
    # pairing that can be improved.
    ("hcm_knockdown_forward",
     ("relaxed_death_walk_front_01", "getup_ground_back"), BOTH),
    ("hcm_knockdown_back",
     ("relaxed_death_walk_back_01", "getup_ground_front"), BOTH),
    ("hcm_knockdown_left",
     ("relaxed_death_walk_left_01", "getup_ground_left"), BOTH),
    ("hcm_knockdown_right",
     ("relaxed_death_walk_right_01", "getup_ground_right"), BOTH),

    # The same four falls with no get-up chained to them, for the tier that
    # hands recovery back to the game instead of animating it.
    #
    # Measured, the rotation a knockdown leaves behind is a constant per
    # action: +53 forward, +90 back, -176 left and zero right. Right is paired
    # the same way left is and imparts nothing, so the rotation lives in the
    # get-up rather than in the fall or in the chaining. Dropping the get-up
    # drops the rotation with it, and the falls are kept untouched because a
    # comparison of all eighteen shared fall clips found these four to be the
    # best available.
    ("hcm_fall_forward", "relaxed_death_walk_front_01", BOTH),
    ("hcm_fall_back", "relaxed_death_walk_back_01", BOTH),
    ("hcm_fall_left", "relaxed_death_walk_left_01", BOTH),
    ("hcm_fall_right", "relaxed_death_walk_right_01", BOTH),

    # Nothing to play, for taking a victim out of a ragdoll without imposing a
    # pose or a facing on them.
    #
    # An actor has to be animation driven or it holds its bind pose, which is
    # the T-pose seen when a ragdolled victim is returned to the alive profile
    # with no fragment running. Every real option carries a pose of its own;
    # this one carries none.
    #
    # See `render_option` for the shape, which is the terminal clip found for
    # the charge.
    ("hcm_settle", (), BOTH),

    # collision_stand_{front,back,left,right}_heavy are named for exactly this
    # case and are not here. They exist as assets under
    # animations/humans/male/hitdeath, but no fragment in the stock database
    # references them, so they do not appear in its animation list and the
    # check below rejects them. Reaching them means validating against the
    # character's animation set rather than against what vanilla already
    # references. They are male only in any case, so they could never carry a
    # tier on their own.
]


def as_clips(clips):
    """A clip entry as a tuple, whether written as one name or several."""
    if isinstance(clips, str):
        return (clips,)

    return tuple(clips)


def reactions_for(gender):
    """The (tag, clip) pairs a character set has the animation for."""
    return [(tag, clip) for tag, clip, genders in REACTIONS
            if gender in genders]


# Collider mode held for the duration of the reaction.
#
# In the patched male database, vanilla declares `Interactive` on 29 of the 32
# options in the `AnimationControlled` fragment, which is the fragment these
# options live in, and nothing on 83 of the 99 in `HitDeath`, which is where
# the clips themselves come from.
#
# The collider follows the fragment the option sits in, not the clip's origin.
# Without a collider layer an interactive action leaves the actor able to pass
# through geometry, so a victim knocked down beside a wagon ends up inside it.
# Vanilla's hit reactions keep their ordinary collider because they play
# through HitDeath.
COLLIDER_MODE = "Interactive"

# Modeled on the vanilla HitDeath option that plays these same clips
# (FragTags "so_forward+minor_hit"), rather than on an object interaction.
# The camera layer is dropped because it aims the player's camera and the
# victim here is never the player. MovementControlMethod is added so the
# animation drives the body, which an interactive action needs and a natively
# triggered hit reaction does not.
TEMPLATE = """      <Fragment BlendOutDuration="0.2" Tags="" FragTags="{tags}">
        <AnimLayer>
{clips}
        </AnimLayer>{ground}{settle}
{movement}{collider}
      </Fragment>"""

# Hands the body to a stiff ragdoll once the fall has played, which is how
# vanilla settles a fallen actor onto ground that is not flat. Without it the
# clip holds its authored pose whatever the slope underneath, and the body
# clips into the terrain.
#
# ExitTime is when the layer takes over, in seconds from the start of the
# fragment. Stiffness 100 is vanilla's own value and barely deforms the pose;
# the layer is there to find the ground, not to throw the body.
SETTLE_LAYER = """
        <ProcLayer>
          <Blend ExitTime="%s" StartTime="0" Duration="0.2" />
          <Procedural type="Ragdoll">
            <ProceduralParams>
              <Sleep value="%s" />
              <Stiffness value="%s" />
            </ProceduralParams>
          </Procedural>
        </ProcLayer>"""

# Rotates the actor to match the ground it is on, copied from the vanilla
# fragments that place a pose at ground level. Duration 0 at ExitTime 0 means it
# applies for the whole fragment rather than blending in.
GROUND_ROTATION_LAYER = """
        <ProcLayer>
          <Blend ExitTime="0" StartTime="0" Duration="0" />
          <Procedural type="GroundRotation">
            <ProceduralParams />
          </Procedural>
        </ProcLayer>"""

# Whether a knockdown carries it.
GROUND_ROTATION = True

# Whether the reaction declares a movement control layer at all. Vanilla's own
# hit reactions mostly do not: 77 of the 99 options in the patched male
# HitDeath declare none, which leaves the actor on default entity-driven
# movement and therefore collision-aware. The 29 of 32 in AnimationControlled
# that do declare one are object interactions, where the actor is meant to be
# driven onto a door or a bed and geometry is not in the way.
MCM_DECLARE = True

# How much of the actor's movement the animation drives, as vanilla's own hit
# reactions set it.
MCM_HORIZONTAL = 2
MCM_ROTATE = 0
MCM_VERTICAL = 0
MCM_XYMOVE = 0
MCM_ZMOVE = 0

# Seconds into the fall before the body is settled, and how rigid it is while
# settling. None disables the layer for the knockdown options, which is the
# behavior these shipped with.
SETTLE_AT = None
SETTLE_STIFFNESS = 100
SETTLE_SLEEP = 0

# The settle layer for the fall tier, whose whole purpose is to hand the body
# to physics partway through the clip.
#
# These are vanilla's own values, read from the `HitDeath` fragment option that
# performs this exact handover for a rider knocked off a horse:
#
#   <Blend ExitTime="1.1" StartTime="0" Duration="0.2" />
#   <Procedural type="Ragdoll">
#     <Sleep value="1" /> <Stiffness value="500" />
#
# Sleep has to be 1. At 0 the body stays live rather than settling, and the
# ragdoll is measured arriving two seconds after the victim has already stood
# up, which is not a handover at all. Stiffness 100 is too soft to hold a body
# through it; 500 is what vanilla uses for the same purpose.
FALL_SETTLE_STIFFNESS = 500
FALL_SETTLE_SLEEP = 1

# When each fall option hands over, in seconds, by character set and direction.
#
# A clip does not end when the victim reaches the ground; it goes on to settle
# them into a final pose. Measured clip lengths, in milliseconds:
#
#   male    back 1710  forward 2425  left 4120  right 3060
#   female  back 1890  forward 3340  left 2016  right 2335
#
# Expressing them here rather than in Lua lets Mannequin own the timing, so the
# mod runs no timer against a clip whose length it would have to know.
#
# Each figure is the clip's length times a fixed share, 0.68 for the male set
# and 0.50 for the female, so the clip has finished settling the pose before
# physics takes the body. Handing over when the head stops descending is
# earlier, and gives physics a half-posed body.
#
# The long lie-down that follows is vanilla's get-up, which reads none of this.
FALL_SETTLE_AT = {
    "male": {"forward": 1.65, "back": 1.16, "left": 2.80, "right": 2.08},
    "female": {"forward": 1.67, "back": 0.95, "left": 1.01, "right": 1.17}
}

MOVEMENT_LAYER = """
        <ProcLayer>
          <Blend ExitTime="0" StartTime="0" Duration="0.2" />
          <Procedural type="MovementControlMethod">
            <ProceduralParams>
              <Horizontal value="{horizontal}" />
              <Vertical value="{vertical}" />
              <XyMove value="{xymove}" />
              <ZMove value="{zmove}" />
              <Rotate value="{rotate}" />
              <Velocity value="0" />
              <Inertia value="0" />
            </ProceduralParams>
          </Procedural>
        </ProcLayer>"""

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


# Every pak the game reads vanilla data out of, lowest priority first.
#
# The base paks in `Data/` are the game as it launched; the patches in
# `Data/patch/` replace whole files. Reading the base pak alone derives the
# mod's files from data the running game does not use.
#
# The order is the engine's own, read off its log rather than guessed: the base
# paks in `Data/` are opened first, then `Data/patch/` in ascending name order,
# and a later pak wins. So the last pak in this list that holds an entry is the
# one the game actually serves.
PATCH_RELATIVE = os.path.join("Data", "patch")


def vanilla_paks():
    """Returns every candidate pak, lowest priority first."""
    base = sorted(glob.glob(os.path.join(GAME_ROOT, "Data", "*.pak")))
    patches = sorted(glob.glob(os.path.join(GAME_ROOT, PATCH_RELATIVE, "*.pak")))

    return base + patches


_PAK_ENTRIES = {}


def pak_key(name):
    """Normalizes a pak entry name so the same file matches across paks.

    Paks are not consistent about how they spell an entry. The launch paks and
    the patches up to 1.7 use `Animations/Mannequin/ADB/...`; 1.8 onward store
    the whole path lowercased. Some store backslashes. A literal match therefore
    finds an entry in the old paks and misses it in every modern one, and a
    resolver that misses the highest patch silently falls back to a lower one.
    """
    return name.replace("\\", "/").lower()


def pak_entries(pak):
    """Cached {normalized name: name as stored} for one pak.

    A pak that cannot be opened raises rather than resolving to nothing: an
    empty table would drop that pak out of the priority order in silence, which
    is the failure this whole mechanism exists to prevent.
    """
    if pak not in _PAK_ENTRIES:
        table = {}

        with zipfile.ZipFile(pak) as archive:
            for name in archive.namelist():
                table[pak_key(name)] = name

        _PAK_ENTRIES[pak] = table

    return _PAK_ENTRIES[pak]


def read_vanilla(entry):
    """Reads a vanilla entry from the pak the running game would serve it from.

    Returns (bytes, label), where the label names the winning pak so the build
    output says which version of the game each generated file was derived from.
    Silent version skew is the whole failure this guards against, so it is
    printed rather than merely resolved.
    """
    key = pak_key(entry)
    holders = [p for p in vanilla_paks() if key in pak_entries(p)]

    if not holders:
        raise SystemExit("no pak under %s holds %s" % (GAME_ROOT, entry))

    winner = holders[-1]
    stored = pak_entries(winner)[key]

    return (read_pak_entry(winner, stored),
            os.path.relpath(winner, GAME_ROOT))


def newline_of(text):
    if "\r\n" in text:
        return "\r\n"

    return "\n"


# One clip and the blend that introduces it. A layer holding several plays
# them in order, which is how vanilla sequences a jump into its fall, in 568
# of its own options.
#
# ExitTime is 0 on the first clip, meaning start at once, and -1 on every clip
# after it, meaning begin the transition when the one before has finished. The
# sequence is therefore timed by the animations themselves.
#
# Chaining the same two clips from Lua on a fixed delay does not work. The fall
# clips differ in length, so one delay is early for some directions and late
# for others, and a late one arrives after the victim has regained control and
# drags them back to the ground from wherever they walked to.
CLIP = ('          <Blend ExitTime="%s" StartTime="0" Duration="0.2" />\n'
        '          <Animation name="%s" />')


def settle_for(tag, gender):
    """The ragdoll layer an option carries, as (exitTime, sleep, stiffness).

    Returns None when the option carries none.

    The fall tier is the case this exists for. Its whole purpose is to hand the
    body to physics partway through the clip.
    """
    if tag.startswith("hcm_fall_"):
        side = tag[len("hcm_fall_"):]
        at = FALL_SETTLE_AT.get(gender, {}).get(side)

        if at is None:
            return None

        return (at, FALL_SETTLE_SLEEP, FALL_SETTLE_STIFFNESS)

    if tag.startswith("hcm_knockdown_") and SETTLE_AT is not None:
        return (SETTLE_AT, SETTLE_SLEEP, SETTLE_STIFFNESS)

    # The empty fragment carries one too, and it is the whole point of it.
    #
    # A victim hit while already down has to be ragdolled again, and doing that
    # from Lua by setting the physicalization profile means something has to set
    # it back. That flip is what shoots the actor upright: an alive actor is an
    # upright capsule, so returning to it from a body lying on the ground stands
    # them in a frame with nothing in between.
    #
    # Letting the fragment own the ragdoll is how the fall tier already works,
    # and the game recovers those actors its own way when the fragment ends. At
    # ExitTime 0 the layer takes the body immediately, which is correct here
    # because there is no clip to play first.
    if tag == "hcm_settle":
        return (0, FALL_SETTLE_SLEEP, FALL_SETTLE_STIFFNESS)

    return None


def render_option(tags, clips, nl, settle=None, ground=False):
    """Renders one Fragment option with the file's own line endings.

    `clips` is one clip name, or several to play in order. `settle` is the
    ragdoll layer's (exitTime, sleep, stiffness), or None for no layer.
    """
    collider = ""

    if COLLIDER_MODE:
        collider = COLLIDER_LAYER % COLLIDER_MODE

    settle_layer = ""

    if settle is not None:
        settle_layer = SETTLE_LAYER % settle

    movement = ""

    if MCM_DECLARE:
        movement = MOVEMENT_LAYER.format(
            horizontal=MCM_HORIZONTAL, vertical=MCM_VERTICAL,
            xymove=MCM_XYMOVE, zmove=MCM_ZMOVE, rotate=MCM_ROTATE)

    ground_layer = ""

    if ground and GROUND_ROTATION:
        ground_layer = GROUND_ROTATION_LAYER

    # An option named with no clips is the empty fragment.
    #
    # The shape is the terminal clip found for the charge: a blend marked
    # terminal paired with an animation of no name. The pair is required
    # rather than decorative, because a fragment sizes its clip array at half
    # its child count and a lone trailing blend writes one clip past the end.
    if not as_clips(clips):
        body = ('          <Blend ExitTime="0" StartTime="0" Duration="0.1"'
                ' terminal="1" />' + chr(10) +
                '          <Animation name="" />')
    else:
        body = chr(10).join(CLIP % ("0" if i == 0 else "-1", clip)
                            for i, clip in enumerate(as_clips(clips)))
    option = TEMPLATE.format(tags=tags, clips=body, collider=collider,
                             ground=ground_layer, settle=settle_layer,
                             movement=movement)

    return option.replace("\n", nl)


def out(name):
    """Path of a generated file in mod_assets."""
    return os.path.join(OUT_DIR, name)


def write_shared_tags(nl):
    """Adds the reaction and horse FragTags to the AnimationControlled tag file.

    Written under vanilla's own name, deliberately.

    The alternative, shipping it as hcm_animationControlledTags.xml, means
    every entity has to be pointed at a copy of the fragment id file to reach
    it, and that file at a copy of the controller def. Those two copies are
    123 KB of vanilla data restated under mod names, and they would sit in the
    resolution path of every fragment a human uses, not just this mod's.

    Replacing 1 KB of tag names is a far smaller thing to own than restating
    the whole fragment and controller definitions, and it leaves every
    unrelated animation on vanilla's own path.
    """
    blob, source = read_vanilla(TAGS_ENTRY)
    raw = blob.decode("ascii", "replace")

    group = ['    <Group name="HcmReaction">']
    group += ['      <Tag name="%s" />' % tag for tag, _, _ in REACTIONS]
    group += ["    </Group>"]

    # The horse's own tags, which nothing else declares.
    #
    # `hcm_rear` and `hcm_rear_charge` are the FragTags of the two options in
    # `hcm_horse_database.adb`, and that file is hand authored and not produced
    # here. This file is, and it is the only place those tags are declared, so
    # regenerating without them deletes them. The rears would then request a
    # fragment that cannot resolve, which is not an error: the call returns
    # true and the horse stays in `MotionIdle`.
    group += ['    <Group name="HcmHorse">']
    group += ['      <Tag name="%s" />' % tag for tag in HORSE_TAGS]
    group += ["    </Group>"]

    anchor = nl + "  </Tags>"
    patched = raw.replace(anchor, nl + nl.join(group) + anchor, 1)

    if patched == raw:
        raise SystemExit("shared tag anchor not matched")

    name = TAGS_ENTRY.rsplit("/", 1)[-1]

    with io.open(out(name), "wb") as handle:
        handle.write(patched.encode("ascii"))

    print("  tags   %s (%d B, %d vanilla + %d added) from %s"
          % (name, os.path.getsize(out(name)),
             raw.count("<Tag "), len(REACTIONS) + len(HORSE_TAGS), source))


# `wh_female_fragmentids.xml` is not generated: patch 1.9 declares
# `AnimationControlled` for the women itself, and a copy under vanilla's name
# would override the patched file and drop its fragment ids.


def write_parent(gender, paths, nl):
    """Writes the one file that carries this mod's options.

    It is the authoritative definition of AnimationControlled, so it has to
    carry vanilla's own options as well as this mod's: a sub-database does not
    merge into a fragment another database defines, and without them a
    redirected NPC loses every door, cabinet and wardrobe interaction.

    Everything else a human animates with is reached by reference, through a
    SubADB pointing at the untouched vanilla database inside its own pak.
    """
    blob, source = read_vanilla(paths["db"])
    db = blob.decode("ascii", "replace")

    present = set(re.findall(r'<Animation name="([^"]*)"', db))
    wanted = reactions_for(gender)
    missing = [clip for _, clips in wanted for clip in as_clips(clips)
               if clip not in present]

    if missing:
        raise SystemExit("clips absent from the %s database: %s"
                         % (gender, missing))

    options = nl.join(
        render_option(tag, clip, nl,
                      settle=settle_for(tag, gender),
                      ground=tag.startswith(("hcm_knockdown_", "hcm_fall_")))
        for tag, clip in wanted)

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

    print("  %-6s %s (%d B, %d vanilla options + %d added) from %s"
          % (gender, name, os.path.getsize(out(name)), inherited, len(wanted),
             source))


def write_additive():
    """Generates the whole layout."""
    nl = newline_of(read_vanilla(TAGS_ENTRY)[0].decode("ascii", "replace"))

    print("Additive layout, %d options where the character set has the clip:"
          % len(REACTIONS))

    for gender, paths in sorted(GENDERS.items()):
        write_parent(gender, paths, nl)

    write_shared_tags(nl)

    for tag, clips, genders in REACTIONS:
        print("  + %-24s -> %-46s %s"
              % (tag, " then ".join(as_clips(clips)), "+".join(genders)))

    # A stale file here is still an override, and would quietly change which
    # chain entities resolve through.
    #
    # `wh_female_fragmentids.xml` is deliberately absent: it is not
    # generated, so leaving it in this set would keep an already-installed copy
    # alive forever. It stays in `generated` below, which is what licenses the
    # sweep to delete it.
    keep = set(["hcm_male_database.adb", "hcm_female_database.adb",
                TAGS_ENTRY.rsplit("/", 1)[-1]])

    # Only files this generator has produced before may be removed. The set is
    # named rather than pattern matched, so a file this generator does not know
    # about is left alone rather than deleted; `mod_assets` is not in git, so a
    # deletion here cannot be recovered. Hand-authored animation data lives in
    # `src/Animations` and is never in this directory.
    generated = set(["hcm_male_database.adb", "hcm_female_database.adb",
                     "kcd_male_database.adb", "wh_female_database.adb",
                     TAGS_ENTRY.rsplit("/", 1)[-1],
                     GENDERS["female"]["ids"].rsplit("/", 1)[-1]])

    for stale in sorted((set(os.listdir(OUT_DIR)) & generated) - keep):
        os.remove(out(stale))
        print("  removed stale file: %s" % stale)

    for foreign in sorted(set(os.listdir(OUT_DIR)) - keep - generated):
        print("  left alone, not generated here: %s" % foreign)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write_additive()


if __name__ == "__main__":
    main()
