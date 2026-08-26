"""Talks to the running game's remote console over TCP.

CryEngine embeds a small console server. The engine binary carries the strings
"RemoteConsoleServer", "RemoteConsoleClient" and the CVar
"log_EnableRemoteConsole", so the feature is compiled into this build; whether
it can be switched on from a config file is what this script is meant to find
out. Nothing here has been confirmed against a running game yet.

If it works, it replaces the slowest part of the test loop. Console commands go
in, log output comes back, and with sys_DevMode already enabled in system.cfg a
line beginning with "#" is evaluated as Lua. That means the mod's script can be
reloaded, its Config retuned, and a save loaded, without leaving the game.

Setup, once:

    Add to the game's system.cfg, next to the existing sys_DevMode line:

        log_EnableRemoteConsole = 1

Usage:

    python dev_console.py                          interactive
    python dev_console.py "map help"               one command
    python dev_console.py --lua "System.LogAlways('hi')"
    python dev_console.py --reload                 reload the mod's Lua
    python dev_console.py --listen                 watch the log stream only

The wire format is the one CryEngine's RemoteConsole.cpp uses: every packet is
a single byte naming the event, then the payload text, then a zero byte. The
event numbering below is that file's enum. If the handshake turns out to differ
in this build, run with --raw to see exactly what the server sends.
"""

import argparse
import socket
import sys
import threading
import time

HOST = "127.0.0.1"
PORT = 4600

# From CryEngine's EConsoleEventType. Only a few of these matter to us.
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

# The mod's script, as the engine's file system sees it. Script.ReloadScript is
# what vanilla itself uses to pull a script back in at runtime; see the calls at
# the top of Scripts/common.lua and most files under Scripts/Entities.
MOD_SCRIPT = "Scripts/Startup/HorseCollisionMod.lua"


def pack(event, payload=""):
    """One packet: event byte, payload, terminator."""
    return bytes([event]) + payload.encode("ascii", "replace") + b"\x00"


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

        messages.append((packet[0], packet[1:].decode("ascii", "replace")))

    return messages, buffer


class Console(object):
    def __init__(self, raw=False, quiet=False):
        self.raw = raw
        self.quiet = quiet
        self.sock = None
        self.alive = False
        self.buffer = b""

    def connect(self, timeout=5.0):
        self.sock = socket.create_connection((HOST, PORT), timeout=timeout)
        self.sock.settimeout(0.5)
        self.alive = True

    def send(self, command):
        self.sock.sendall(pack(EV_CONSOLE_COMMAND, command))

    def lua(self, code):
        # sys_DevMode = 1 makes the console evaluate a leading "#" as Lua.
        self.send("#" + code)

    def pump(self):
        """Reads and prints whatever the server has sent."""
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

        if self.raw:
            print("<< %r" % chunk)

        self.buffer = self.buffer + chunk
        messages, self.buffer = unpack(self.buffer)

        for event, text in messages:
            # The server sends a noop as a keepalive. Echoing it would bury
            # everything else.
            if event == EV_NOOP and not self.raw:
                continue

            if self.quiet and event not in (EV_LOG_MESSAGE, EV_LOG_WARNING,
                                            EV_LOG_ERROR):
                continue

            label = EVENT_NAMES.get(event, "event-%d" % event)
            print("[%s] %s" % (label, text))

    def listen_forever(self):
        while self.alive:
            self.pump()

    def close(self):
        self.alive = False

        if self.sock:
            self.sock.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
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
    parser.add_argument("--wait", type=float, default=2.0,
                        help="seconds to keep reading after sending")
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

    print("connected to %s:%d" % (HOST, PORT))

    if args.listen:
        try:
            console.listen_forever()
        except KeyboardInterrupt:
            pass

        console.close()
        return 0

    if args.reload:
        console.lua('Script.ReloadScript("%s")' % MOD_SCRIPT)
    elif args.lua:
        console.lua(args.lua)
    elif args.command:
        console.send(args.command)
    else:
        return interactive(console)

    deadline = time.time() + args.wait

    while time.time() < deadline and console.alive:
        console.pump()

    console.close()
    return 0


def interactive(console):
    """Reads commands from the terminal, printing log output as it arrives."""
    reader = threading.Thread(target=console.listen_forever)
    reader.daemon = True
    reader.start()

    print("commands go to the game. '#' prefix evaluates Lua. Ctrl-C to quit.")
    print("  :reload   reload the mod script")

    try:
        while console.alive:
            line = input("> ").strip()

            if not line:
                continue

            if line == ":reload":
                console.lua('Script.ReloadScript("%s")' % MOD_SCRIPT)
                continue

            console.send(line)
    except (KeyboardInterrupt, EOFError):
        pass

    console.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
