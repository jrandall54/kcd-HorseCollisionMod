"""Talks to the running game's remote console over TCP.

CryEngine embeds a console server, and this build has it: with
`log_EnableRemoteConsole = 1` alongside the `sys_DevMode = 1` already in
system.cfg, the game listens on port 4600 and accepts console commands from
outside the process. Because dev mode is on, a command beginning with "#" is
evaluated as Lua, which is what makes this useful rather than merely tidy.

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
import socket
import sys
import threading
import time

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

# The mod's script as the engine's file system names it. Script.ReloadScript is
# what vanilla uses to pull a script back in at runtime; see the calls at the
# top of Scripts/common.lua.
MOD_SCRIPT = "Scripts/Startup/HorseCollisionMod.lua"


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

    def connect(self, timeout=5.0):
        self.sock = socket.create_connection((HOST, PORT), timeout=timeout)
        self.sock.settimeout(0.5)
        self.alive = True

    def queue(self, command):
        """Queues a console command, sent on the server's next request."""
        self.outbox.append(command)

    def lua(self, code):
        # sys_DevMode = 1 makes the console evaluate a leading "#" as Lua.
        self.queue("#" + code)

    def reload_mod(self):
        self.lua('Script.ReloadScript("%s")' % MOD_SCRIPT)

    def drained(self):
        return not self.outbox

    def _answer_request(self):
        """The server asked. Reply with work if there is any, a noop if not."""
        if self.outbox:
            command = self.outbox.popleft()
            self.sock.sendall(pack(EV_CONSOLE_COMMAND, command))
            self.sent = self.sent + 1

            if not self.quiet:
                print(">> %s" % command)
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

        if self.raw:
            print("<< %r" % chunk)

        self.buffer = self.buffer + chunk
        messages, self.buffer = unpack(self.buffer)

        for event, text in messages:
            if event == EV_REQ:
                self._answer_request()

                if not self.raw:
                    continue

            if event == EV_NOOP and not self.raw:
                continue

            if self.quiet and event not in LOG_EVENTS:
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
        console.reload_mod()
    elif args.lua:
        console.lua(args.lua)
    elif args.command:
        console.queue(args.command)
    else:
        return interactive(console)

    # The command goes out on the server's next request, so the wait covers
    # both the handshake and whatever the command prints afterwards.
    deadline = time.time() + args.wait

    while time.time() < deadline and console.alive:
        console.pump()

    if console.sent == 0:
        print("warning: the server never asked for input, nothing was sent.")
        print("         re-run with --raw to see what it did send.")

    console.close()
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
