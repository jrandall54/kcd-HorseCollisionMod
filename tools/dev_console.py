"""Talks to the running game's remote console over TCP.

CryEngine embeds a console server, and this build has it: with
`log_EnableRemoteConsole = 1` in system.cfg the game listens on port 4600,
accepts console commands, and streams its console output back. Confirmed
against the running game: `MemInfo` executed and echoed, and the mod's own
telemetry arrived live while the game was being played.

Two limits found the same way:

  * Commands marked VF_CHEAT are refused, `lua_reload_script` among them.
    Dev mode is what lifts that, and it comes from the **command line**
    (`-devmode`), not from a config file. The `sys_DevMode = 1` line sitting
    in system.cfg is inert: querying it answers "Unknown command".
  * `wh_con_expr_prefix` is `!`, not `#`.

The wire format, confirmed against the running game:

  * Every packet is one event-type character, then the payload, then a zero
    byte.
  * The event type is written as an **ASCII digit**, `'0' + type`, not as a
    raw byte. The first packet the server sends is `b"1\\x00"`, which is
    `'1'` for type 1, eCET_Req. Reading that first byte as a number gives 49
    and looks like a protocol mismatch when nothing is wrong.
  * The exchange is driven by the server. It sends eCET_Req to ask whether the
    client has anything to say, and **waits**. A client that never answers gets
    one packet and then silence, which is exactly what the first run produced.
    Answer every request, with a queued command if there is one and eCET_Noop
    if there is not, and the log stream follows.

Usage:

    python tools/dev_console.py                          interactive
    python tools/dev_console.py "e_TimeOfDay"            one command
    python tools/dev_console.py --lua "System.LogAlways('hi')"
    python tools/dev_console.py --reload                 reload the mod's Lua
    python tools/dev_console.py --listen                 watch the log stream only
    python tools/dev_console.py --raw                    also dump the bytes

Setup, once, in the game's system.cfg:

    log_EnableRemoteConsole = 1
"""

import argparse
import io
import collections
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

# CryEngine marks up console text with "$" followed by a color digit. Left in,
# a log line reads "$3MemInfo = $60 $5[]$4".
COLOUR_CODES = re.compile(r"\$[0-9]")


def show(text):
    """Prints a line, flushing so a piped or redirected run is not silent.

    Python block-buffers stdout when it is not a terminal, so a long listening
    run that is stopped from outside prints nothing at all and looks like the
    game sent nothing. That cost one wrong conclusion already.
    """
    print(text, flush=True)

HOST = "127.0.0.1"
PORT = 4600

# CryEngine's EConsoleEventType. Sent and received as the character '0' + value.
EV_NOOP = 0
EV_REQ = 1
EV_LOG_MESSAGE = 2
EV_LOG_WARNING = 3
EV_LOG_ERROR = 4
EV_CONSOLE_COMMAND = 5
EV_AUTOCOMPLETE_LIST = 6
EV_AUTOCOMPLETE_DONE = 7

EVENT_NAMES = {
    EV_NOOP: "noop",
    EV_REQ: "req",
    EV_LOG_MESSAGE: "log",
    EV_LOG_WARNING: "warn",
    EV_LOG_ERROR: "error",
    EV_CONSOLE_COMMAND: "command",
    EV_AUTOCOMPLETE_LIST: "autocomplete",
    EV_AUTOCOMPLETE_DONE: "autocomplete-done",
}

LOG_EVENTS = (EV_LOG_MESSAGE, EV_LOG_WARNING, EV_LOG_ERROR)

# Backend chatter the game emits constantly and that says nothing about the
# game itself. Both groups were read off a live session and confirmed to carry
# no gameplay information before being muted here:
#
#   PROS: ...            Warhorse's own online backend (Pros.Global.Api.Auth).
#                        It retries whenever it cannot reach its service, and
#                        reconnects. Nothing in the game waits on it.
#   [Steam] ...          The Steam achievement and stats layer writing user
#                        data. Bookkeeping only.
#
# At verbosity 4 these outnumber real log lines badly enough that a listening
# session is unreadable, which is the whole reason the live log exists. They
# are suppressed by default and counted, never dropped silently: --listen
# reports how many were hidden, and --noisy turns the filter off. --raw is
# unaffected, since raw means raw.
NOISE = [
    re.compile(r"^\s*PROS:"),
    re.compile(r"^\s*\[Steam\]"),
]


def is_noise(text):
    """True when a log line is backend chatter rather than game information."""
    stripped = COLOUR_CODES.sub("", text).strip()
    return any(pattern.search(stripped) for pattern in NOISE)

# The mod's scripts as the engine's file system names them.
#
# Only the two Startup scripts are named. The rest of the mod lives in
# Scripts/HorseCollisionMod/ and is pulled in by Script.ReloadScript calls at
# the foot of the entry point, so reloading MOD_SCRIPT cascades through every
# part file and nothing here has to know what they are.
MOD_SCRIPT = "Scripts/Startup/HorseCollisionMod.lua"
SETTINGS_SCRIPT = "Scripts/Startup/HorseCollisionMod_Settings.lua"

# Reloading the mod's Lua without restarting. `lua_reload_script` is a native
# console command this build registers, which is a better bet than driving
# Script.ReloadScript through the "#" Lua prefix. Both are listed so a failure
# of the first can be told apart from a failure of the mechanism.
RELOAD_COMMANDS = [
    # The settings file defines the global table the mod reads while applying
    # settings, and it is a separate file, so it is re-executed first.
    # Reloading only the mod script leaves an edited value on disk with the
    # previous one still live, which reads in game as a setting that does
    # nothing.
    "lua_reload_script " + SETTINGS_SCRIPT,
    "lua_reload_script " + MOD_SCRIPT,
    # Re-executing the script is not enough on its own. The mod's detection
    # loop is only started by its UI listener when a loading screen ends,
    # because a Startup script has no "game loaded" hook to hang off. Reloading
    # rebuilds the HorseCollisionMod table with TimerTick unset, so the loop
    # still running from before sees its generation no longer matches and stops
    # -- and nothing starts a new one. The mod goes silent and the game looks
    # completely vanilla until a save is loaded.
    #
    # Calling the entry point directly stands in for that loading screen, which
    # bumps the generation and starts a fresh loop running the new code.
    "#HorseCollisionMod:uiActionListener('sys_loadingimagescreen', 'OnEnd', nil)",
]

# The animation half. Mannequin owns the databases the stagger options live in.
#
# mn_allowEditableDatabasesInPureGame is the reason mn_reload appeared to do
# nothing: a shipping build treats its Mannequin databases as read only, and
# this build ships the CVar at 0. It is sent first, every time, because it is a
# runtime value that resets with the game exactly like log_Verbosity does.
#
# The reload only sees new data if the ADB files are also on disk loose, under
# Data/Animations/Mannequin/ADB, and sys_PakPriority is 0. dev_deploy.ps1
# -Reload puts them there.
ANIM_RELOAD_COMMANDS = [
    "mn_allowEditableDatabasesInPureGame 1",
    "mn_reload",
    "wh_am_ReloadDB",
]

# The console refuses cheat-flagged commands unless the game was launched with
# -devmode. Seeing this text back is the signal that the flag did not take.
CHEAT_REFUSAL = "VF_CHEAT"

# Sent on every connection before anything else. Console verbosity is a runtime
# value that resets with the game, so a session started after a restart is
# silent until it is raised again; a run that relied on a previous session
# having set it looked like the command had vanished. con_restricted is cleared
# in the same breath since it is the other thing that can refuse input.
#
# The level is deliberately not 4. The mod logs through System.LogAlways, which
# does not consult verbosity, so its telemetry arrives either way. What level 4
# adds is every engine message: formatted, written to the console, and then
# forwarded over this socket one packet per frame exchange. With the PROS
# backend failing twice a second and the Steam stats layer chattering
# continuously that is a large amount of main thread work for output nothing
# reads, and it is enough to starve the audio buffer and make the game sound
# like it is underwater.
#
# --verbose asks for 4 when engine-level detail is actually wanted.
SETUP_VERBOSITY = 2
VERBOSE_VERBOSITY = 4


def setup_commands(verbosity):
    """The per-connection preamble at a given console verbosity."""
    return ["log_Verbosity %d" % verbosity, "con_restricted 0"]

# Why no log line ever came back on the first working session. The remote
# console forwards console output, and a shipping build generally has console
# verbosity turned off, so there is nothing to forward even while the game is
# writing plenty to kcd.log. con_restricted is cleared first in case it is what
# refuses commands from a remote client.
DIAGNOSE_COMMANDS = [
    "con_restricted 0",
    "log_Verbosity 4",
    "log_IncludeTime 1",
    "e_TimeOfDay",
    "version",
]


def pack(event, payload=""):
    """One packet: event digit, payload, terminator."""
    head = chr(ord("0") + event)

    return (head + payload).encode("ascii", "replace") + b"\x00"


def unpack(buffer):
    """Splits a receive buffer into whole packets, returning the remainder."""
    messages = []

    while True:
        end = buffer.find(b"\x00")

        if end < 0:
            break

        packet, buffer = buffer[:end], buffer[end + 1:]

        if not packet:
            continue

        event = packet[0] - ord("0")
        messages.append((event, packet[1:].decode("ascii", "replace")))

    return messages, buffer


def check_lua_syntax(code):
    """Refuses code the game would drop without saying anything.

    The remote console does not report a compile error. A chunk with an
    unbalanced `end` produces no output and no complaint, which is
    indistinguishable from a chunk that ran and found nothing, and that
    ambiguity has cost several rounds of guessing at results that were never
    produced.

    Returns an error string, or None when the chunk compiles or when no Lua
    is available to ask.
    """
    for candidate in ("luac", "luac5.1", "luajit", "lua"):
        exe = shutil.which(candidate)

        if exe:
            break
    else:
        return None

    handle, path = tempfile.mkstemp(suffix=".lua")

    try:
        with os.fdopen(handle, "w", encoding="utf-8") as f:
            f.write(code)

        args = [exe, "-bl", path, os.devnull] if "luajit" in exe \
            else [exe, "-p", path]
        done = subprocess.run(args, capture_output=True, text=True)

        if done.returncode == 0:
            return None

        message = (done.stderr or done.stdout).strip()

        return message.replace(path, "<lua>")
    finally:
        os.unlink(path)


class Console(object):
    """A client that answers the server's requests and prints what it says."""

    def __init__(self, raw=False, quiet=False, noisy=False,
                 verbosity=SETUP_VERBOSITY):
        self.raw = raw
        self.quiet = quiet
        self.noisy = noisy
        self.verbosity = verbosity
        self.muted = 0
        self.sock = None
        self.alive = False
        self.buffer = b""
        self.outbox = collections.deque()
        self.sent = 0
        self.commands = []
        self.autocomplete_done = False
        self.collecting = False
        self.refusals = []
        self.setup_count = 0

        # Whether the game has said anything of its own since the setup
        # commands. A Lua chunk that draws nothing is the signature of a game
        # launched without -devmode, and telling those apart needs a record of
        # whether anything came back at all.
        self.saw_output = False

    def connect(self, timeout=5.0):
        self.sock = socket.create_connection((HOST, PORT), timeout=timeout)
        self.sock.settimeout(0.5)
        self.alive = True

    def queue(self, command):
        """Queues a console command, sent on the server's next request."""
        self.outbox.append(command)

    def setup(self):
        """Queues the per-connection preamble that makes output readable."""
        commands = setup_commands(self.verbosity)

        for command in commands:
            self.outbox.append(command)

        self.setup_count = len(commands)

    def lua(self, code):
        # The remote console evaluates a leading "#" as Lua. This is separate
        # from wh_con_expr_prefix, which reads "!" and governs the in-game
        # console; "#" works here regardless. An earlier comment credited
        # sys_DevMode, which is not a CVar in this build at all.
        self.queue("#" + code)


    def reload_mod(self):
        self.lua('Script.ReloadScript("%s")' % MOD_SCRIPT)

    def drained(self):
        return not self.outbox

    def _answer(self):
        """Reply with queued work if there is any, a noop if there is not.

        Called once for every packet received, not only for eCET_Req. The
        server sends one packet and then waits: replying only to requests got
        a single autocomplete entry and then silence, with the same result
        whether the reply was a noop or a command, which rules out the reply's
        content and leaves strict alternation as the explanation.
        """
        if self.outbox:
            command = self.outbox.popleft()
            self.sock.sendall(pack(EV_CONSOLE_COMMAND, command))
            self.sent = self.sent + 1

            if not self.quiet:
                show(">> %s" % command)
        else:
            self.sock.sendall(pack(EV_NOOP))

    def pump(self):
        """Reads whatever has arrived, answers requests, prints the rest."""
        try:
            chunk = self.sock.recv(65536)
        except socket.timeout:
            return
        except OSError:
            self.alive = False
            return

        if not chunk:
            self.alive = False
            return

        self.buffer = self.buffer + chunk
        messages, self.buffer = unpack(self.buffer)

        # The server pings every frame, so a raw dump of the keepalives buries
        # everything worth reading. Only dump a chunk that carries something
        # other than requests and noops.
        if self.raw and any(e not in (EV_REQ, EV_NOOP) for e, _ in messages):
            show("<< %r" % chunk)

        for event, text in messages:
            self._answer()

            if event == EV_AUTOCOMPLETE_LIST:
                self.commands.append(text)

                # The server sends its whole autocomplete list, every command
                # and CVar in the build, on connect. That is 4545 entries here,
                # so printing them buries whatever was actually asked for: a
                # one-command query scrolls its own answer off the screen.
                # They are collected either way, because --commands wants them,
                # but only --commands prints progress and only --raw shows the
                # entries themselves.
                if self.collecting and len(self.commands) % 500 == 0:
                    show("... %d console commands so far" % len(self.commands))

                continue

            if event == EV_AUTOCOMPLETE_DONE:
                self.autocomplete_done = True
                if self.collecting or self.raw:
                    show("[autocomplete] complete, %d entries"
                         % len(self.commands))
                continue

            # Keepalives are never printed as lines, not even under --raw. The
            # server pings every frame, so a listening session shows hundreds of
            # "[req]" a second and the log underneath is unreadable. --raw still
            # dumps the bytes of any chunk that carries something real, which is
            # what it is actually for.
            if event in (EV_REQ, EV_NOOP):
                continue

            if self.quiet and event not in LOG_EVENTS:
                continue

            # Counted rather than dropped, so the tally at the end can say
            # how much was hidden and the filter never silently eats
            # something that mattered.
            if not self.noisy and event in LOG_EVENTS and is_noise(text):
                self.muted = self.muted + 1
                continue

            if CHEAT_REFUSAL in text:
                self.refusals.append(COLOUR_CODES.sub("", text).strip())

            label = EVENT_NAMES.get(event, "event-%d" % event)
            clean = COLOUR_CODES.sub("", text).strip()

            # The setup commands echo their own assignments back, and those
            # arrive whether or not anything the caller asked for ran. Counting
            # them would defeat the whole point of the flag.
            if not clean.startswith(("log_Verbosity", "con_restricted",
                                     "log_SpamDelay")):
                self.saw_output = True

            show("[%s] %s" % (label, clean))

    def listen_forever(self):
        while self.alive:
            self.pump()

    def report_muted(self):
        """Says how much backend chatter was hidden, if any."""
        if not self.muted:
            return

        show("[filtered] %d backend log lines hidden (PROS, Steam)."
             " Use --noisy to see them." % self.muted)

    def close(self):
        self.alive = False

        if self.sock:
            self.sock.close()


def main():
    parser = argparse.ArgumentParser(
        description="Send console commands to the running game.")
    parser.add_argument("command", nargs="?", help="console command to send")
    parser.add_argument("--lua", metavar="CODE",
                        help="evaluate CODE as Lua in the running game")
    parser.add_argument("--file", metavar="PATH",
                        help="evaluate the Lua in PATH as one chunk. The remote "
                             "console takes a whole file as readily as a line, "
                             "and a probe worth running twice belongs in a file "
                             "rather than in shell quoting")
    parser.add_argument("--reload", action="store_true",
                        help="reload the mod's Lua script")
    parser.add_argument("--listen", action="store_true",
                        help="print the log stream and nothing else")
    parser.add_argument("--raw", action="store_true",
                        help="dump every byte received, to check the framing")
    parser.add_argument("--quiet", action="store_true",
                        help="show only log lines")
    parser.add_argument("--noisy", action="store_true",
                        help="do not hide the PROS and Steam backend chatter")
    parser.add_argument("--verbose", action="store_true",
                        help="raise console verbosity to 4 (costs frame time)")
    parser.add_argument("--wait", type=float, default=3.0,
                        help="seconds to keep reading after the command is sent")
    parser.add_argument("--commands", metavar="FILE", nargs="?",
                        const="console_commands.txt",
                        help="save the game's console command and CVar list")
    parser.add_argument("--diagnose", action="store_true",
                        help="try to turn on console output, then read it back")
    parser.add_argument("--anim-reload", action="store_true",
                        help="ask Mannequin to reload the animation databases")
    args = parser.parse_args()

    console = Console(raw=args.raw, quiet=args.quiet, noisy=args.noisy,
                      verbosity=(VERBOSE_VERBOSITY if args.verbose
                                 else SETUP_VERBOSITY))

    try:
        console.connect()
    except OSError as err:
        print("could not reach the console on %s:%d (%s)" % (HOST, PORT, err))
        print()
        print("Check, in order:")
        print("  1. the game is running")
        print("  2. system.cfg contains  log_EnableRemoteConsole = 1")
        print("  3. the game was restarted after that line was added")
        return 1

    show("connected to %s:%d" % (HOST, PORT))

    if args.commands:
        return collect_commands(console, args.commands)

    console.setup()

    if args.listen:
        try:
            console.listen_forever()
        except KeyboardInterrupt:
            pass

        console.close()
        console.report_muted()
        return 0

    if args.diagnose:
        for command in DIAGNOSE_COMMANDS:
            console.queue(command)
    elif args.reload or args.anim_reload:
        # The two halves compose rather than exclude each other, so a change
        # touching both is reloaded over one connection. Mannequin goes first:
        # the Lua half ends by restarting the detection loop, which should run
        # against databases that are already current.
        if args.anim_reload:
            for command in ANIM_RELOAD_COMMANDS:
                console.queue(command)

        if args.reload:
            for command in RELOAD_COMMANDS:
                console.queue(command)
    elif args.file:
        try:
            with io.open(args.file, "r", encoding="utf-8") as handle:
                body = handle.read()
        except OSError as err:
            print("cannot read %s: %s" % (args.file, err))

            return 2

        problem = check_lua_syntax(body)

        if problem:
            print("%s does not compile, so the game would drop it without a "
                  "word:" % args.file)
            print("  " + problem)

            return 2

        print("sending %s, %d lines" % (args.file, body.count(chr(10)) + 1))
        console.lua(body)
    elif args.lua:
        problem = check_lua_syntax(args.lua)

        if problem:
            print("the chunk does not compile, so the game would drop it "
                  "without a word:")
            print("  " + problem)

            return 2

        console.lua(args.lua)
    elif args.command:
        console.queue(args.command)
    else:
        return interactive(console)

    # The wait is measured from when the queue actually drains, not from
    # connect. The server sends its whole autocomplete list first, one entry
    # per exchange, so a fixed deadline from connect can expire before the
    # command has even gone out.
    while console.alive and not console.drained():
        console.pump()

    deadline = time.time() + args.wait

    while time.time() < deadline and console.alive:
        console.pump()

    if console.sent == 0:
        print("warning: the server never asked for input, nothing was sent.")
        print("         re-run with --raw to see what it did send.")

    # A Lua chunk that produced no output at all almost always means the game
    # was launched without -devmode. The console accepts the expression, the
    # server acknowledges it, and the evaluation is dropped in silence: there
    # is no refusal message the way there is for a VF_CHEAT variable.
    #
    # That silence reads exactly like a chunk that ran and logged nothing, and
    # a session was spent probing an unresponsive game before the cause was
    # found. Saying so costs one line and removes the whole class of confusion.
    if (args.lua or args.file) and console.sent > 0 and not console.saw_output:
        print()
        print("The chunk produced no output at all.")
        print("The usual cause is that the game was not launched with "
              "-devmode,")
        print("which the Lua console needs; without it an expression is "
              "accepted")
        print("and dropped without a word. Relaunch with:")
        print("    .\tools\dev_deploy.ps1 -NoBuild -Launch")

    console.close()
    console.report_muted()
    return 0


def collect_commands(console, path):
    """Drains the autocomplete list the server sends on connect, and saves it.

    That list is every console command and CVar the build registers. Having it
    on disk answers questions this project keeps hitting from the other side,
    such as which command loads a save or reloads animation data, without
    guessing at names or reading them out of a strings dump.
    """
    console.collecting = True
    idle = 0.0
    last = 0

    # There is no total to count down from, so the list is considered finished
    # either when the server says so or when it stops sending for long enough.
    while console.alive and not console.autocomplete_done and idle < 5.0:
        before = len(console.commands)
        console.pump()

        if len(console.commands) > before:
            idle = 0.0
            last = len(console.commands)
        else:
            idle = idle + 0.5

    console.close()

    if not console.commands:
        print("nothing collected. The server sent no autocomplete entries.")
        return 1

    entries = sorted(set(console.commands))

    with open(path, "w", encoding="ascii", errors="replace") as handle:
        handle.write("\n".join(entries) + "\n")

    print("saved %d entries (%d unique) to %s" % (last, len(entries), path))

    if not console.autocomplete_done:
        print("note: the server never sent its end-of-list marker, so this")
        print("      may be partial. Re-run to check the count is stable.")

    return 0


def interactive(console):
    """Reads commands from the terminal, printing log output as it arrives."""
    reader = threading.Thread(target=console.listen_forever)
    reader.daemon = True
    reader.start()

    print("commands go to the game. '#' prefix evaluates Lua. Ctrl-C to quit.")
    print("  :reload   reload the mod's Lua script")

    try:
        while console.alive:
            line = input("> ").strip()

            if not line:
                continue

            if line == ":reload":
                console.reload_mod()
                continue

            console.queue(line)
    except (KeyboardInterrupt, EOFError):
        pass

    console.close()
    console.report_muted()
    return 0


if __name__ == "__main__":
    sys.exit(main())
