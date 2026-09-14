"""Writes a small console script that auditions one batch of Henry's lines.

    python tools/make_audition.py 11 1     # line 11 on its own
    python tools/make_audition.py 2          # batch 2, ten lines five seconds apart

With a count of 1 the argument is a line number rather than a batch number, and
nothing is scheduled: the line speaks immediately. That is the pace the rider
asked for -- ten in a row was too many to hold in memory and the five-second
spacing too slow to sit through.

The whole 124-line list in one file comes to 17 KB, which is over the console's
4000-byte limit, so `dev_console.py` falls back to writing it to disk and calling
`Script.ReloadScript`. That path runs the file once per session and silently does
nothing on a second call with the same filename, which cost a batch: the log
recorded batch 1 and nothing at all for batch 2.

So each batch is emitted on its own, carrying only its ten entries, small enough
to go over the console directly where a failure is visible.
"""

import io
import json
import os
import sys

SPACING_MS = 5000
PER_BATCH = 10
ORDER = os.environ.get("AUDITION_ORDER")


def clean(text):
	for bad, good in (("\u2026", "..."), ("\u2019", "'"), ("\u2018", "'"),
			("\u201c", "'"), ("\u201d", "'"), ('"', "'")):
		text = text.replace(bad, good)
	return text


def main():
	batch = int(sys.argv[1])
	count = int(sys.argv[2]) if len(sys.argv) > 2 else PER_BATCH
	rows = json.load(io.open(ORDER, encoding="utf-8"))
	first = (batch - 1) if count == 1 else (batch - 1) * PER_BATCH
	group = rows[first:first + count]

	if not group:
		raise SystemExit("batch %d is past the end of %d lines" % (batch, len(rows)))

	entries = "\n".join('\t{ "%s", "%s" },' % (alias, clean(" / ".join(texts)))
			for alias, texts in group)

	script = '''local L = {
%s
}
local m = HorseCollisionMod
local t = player.id
if player.this and player.this.id then t = player.this.id end
System.LogAlways("[HorseCollisionMod] AUDITION batch %d of " .. tostring(#L) .. " lines")
local function speak(i)
	m.RiderVoiceUntil = 0
	m.RiderVoiceRank = 0
	local ok = pcall(function()
		XGenAIModule.SendMessageToEntityData(t, "dialog:monologRequest",
			Utils.makeTable("dialog:monologRequest", { alias = L[i][1],
				forceOnMuted = true, priority = 50, canBeDelayed = false,
				overrideContextSuppress = true }))
	end)
	System.LogAlways("[HorseCollisionMod] AUDITION " .. (%d + i)
		.. " alias=" .. L[i][1] .. " expect=" .. L[i][2] .. " sent=" .. tostring(ok))
end
for i = 1, #L do
	if i == 1 then speak(1) else Script.SetTimer((i - 1) * %d, function() speak(i) end) end
end
''' % (entries, batch, first, SPACING_MS)

	out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "audition_now.lua")
	io.open(out, "w", encoding="utf-8", newline="\n").write(script)

	for offset, (_alias, texts) in enumerate(group, first + 1):
		print("%3d. %s" % (offset, clean(" / ".join(texts))))

	print("\n%d bytes" % len(script))


if __name__ == "__main__":
	main()
