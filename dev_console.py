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

    python dev_console.py                          interactive
    python dev_console.py "e_TimeOfDay"            one command
    python dev_console.py --lua "System.LogAlways('hi')"
    python dev_console.py --reload                 reload the mod's Lua
    python dev_console.py --listen                 watch the log stream only
    python dev_console.py --raw                    also dump the bytes

Setup, once, in the game's system.cfg:

    log_EnableRemoteConsole = 1
"""

import argparse
import collections
import re
import socket
import sys
import threading
import time

# CryEngine marks up console text with "$" followed by a colour digit. Left in,
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

# The mod's script as the engine's file system names it.
MOD_SCRIPT = "Scripts/Startup/HorseCollisionMod.lua"

# Reloading the mod's Lua without restarting. `lua_reload_script` is a native
# console command this build registers, which is a better bet than driving
# Script.ReloadScript through the "#" Lua prefix. Both are listed so a failure
# of the first can be told apart from a failure of the mechanism.
RELOAD_COMMANDS = [
    "lua_reload_script " + MOD_SCRIPT,
]

# The animation half. Mannequin owns the databases the stagger options live in,
# so if either of these takes effect the ADB changes hotload too and animation
# edits stop costing a restart. Untested: both are listed so a refusal can be
# told apart from a reload that ran and did nothing.
ANIM_RELOAD_COMMANDS = [
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
SETUP_COMMANDS = [
    "log_Verbosity 4",
    "con_restricted 0",
]

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


class Console(object):
    """A client that answers the server's requests and prints what it says."""

    def __init__(self, raw=False, quiet=False):
        self.raw = raw
        self.quiet = quiet
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

    def connect(self, timeout=5.0):
        self.sock = socket.create_connection((HOST, PORT), timeout=timeout)
        self.sock.settimeout(0.5)
        self.alive = True

    def queue(self, command):
        """Queues a console command, sent on the server's next request."""
        self.outbox.append(command)

    def setup(self):
        """Queues the per-connection preamble that makes output readable."""
        for command in SETUP_COMMANDS:
            self.outbox.append(command)
        self.setup_count = len(SETUP_COMMANDS)

    def lua(self, code):
        # sys_DevMode = 1 makes the console evaluate a leading "#" as Lua.
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

                # The list runs to thousands of entries. Printing it would
                # bury the log, so it is collected and only counted here.
                if self.collecting:
                    if len(self.commands) % 500 == 0:
                        show("... %d console commands so far" % len(self.commands))

                    continue

            if event == EV_AUTOCOMPLETE_DONE:
                self.autocomplete_done = True
                show("[autocomplete] complete, %d entries" % len(self.commands))
                continue

            if event in (EV_REQ, EV_NOOP) and not self.raw:
                continue

            if self.quiet and event not in LOG_EVENTS:
                continue

            if CHEAT_REFUSAL in text:
                self.refusals.append(COLOUR_CODES.sub("", text).strip())

            label = EVENT_NAMES.get(event, "event-%d" % event)
            show("[%s] %s" % (label, COLOUR_CODES.sub("", text).strip()))

    def listen_forever(self):
        while self.alive:
            self.pump()

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
    parser.add_argument("--reload", action="store_true",
                        help="reload the mod's Lua script")
    parser.add_argument("--listen", action="store_true",
                        help="print the log stream and nothing else")
    parser.add_argument("--raw", action="store_true",
                        help="dump every byte received, to check the framing")
    parser.add_argument("--quiet", action="store_true",
                        help="show only log lines")
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

    console = Console(raw=args.raw, quiet=args.quiet)

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
        return 0

    if args.diagnose:
        for command in DIAGNOSE_COMMANDS:
            console.queue(command)
    elif args.reload:
        for command in RELOAD_COMMANDS:
            console.queue(command)
    elif args.anim_reload:
        for command in ANIM_RELOAD_COMMANDS:
            console.queue(command)
    elif args.lua:
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

    console.close()
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
