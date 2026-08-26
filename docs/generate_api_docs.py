"""Renders the mod's LDoc comments to a single self-contained HTML page.

The doc comments in HorseCollisionMod.lua are written in standard LDoc
syntax, so `ldoc HorseCollisionMod.lua` produces the same content if a Lua
toolchain is installed. This script exists so the API page can be regenerated
without one, since the project otherwise needs no Lua on the build machine.

Run: python docs/generate_api_docs.py
Output: docs/api/index.html
"""

import html
import io
import os
import re

SOURCE = "HorseCollisionMod.lua"
OUT_DIR = os.path.join("docs", "api")
OUT = os.path.join(OUT_DIR, "index.html")


def strip_marker(line):
    """Removes the leading `---` or `--` from a doc-comment line."""
    return re.sub(r"^\s*--(-)?\s?", "", line)


def parse_blocks(text):
    """Splits the source into (doc_lines, definition_line) pairs."""
    blocks = []
    doc = None

    for line in text.split("\n"):
        stripped = line.strip()

        if stripped.startswith("---"):
            doc = [strip_marker(line)]
            continue

        if doc is not None and stripped.startswith("--"):
            doc.append(strip_marker(line))
            continue

        if doc is not None:
            blocks.append((doc, line.strip()))
            doc = None

    return blocks


def split_tags(doc):
    """Separates prose from @tags, preserving tag order."""
    prose, tags = [], []

    for line in doc:
        match = re.match(r"@(\w+)\s*(.*)", line.strip())

        if match:
            tags.append((match.group(1), match.group(2)))
        elif tags:
            # Continuation of the previous tag's text.
            tags[-1] = (tags[-1][0], tags[-1][1] + " " + line.strip())
        else:
            prose.append(line)

    return prose, tags


def render_prose(lines):
    """Renders the limited markdown subset the doc comments actually use."""
    out, in_list = [], False

    for line in lines:
        text = html.escape(line.rstrip())
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)

        heading = re.match(r"##\s+(.*)", text)
        if heading:
            if in_list:
                out.append("</ul>")
                in_list = False
            out.append("<h3>%s</h3>" % heading.group(1))
            continue

        item = re.match(r"[*\d]\.?\s+(.*)", text)
        if item and (line.lstrip().startswith("*") or re.match(r"\d\.", line.lstrip())):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append("<li>%s</li>" % item.group(1))
            continue

        if not text:
            if in_list:
                out.append("</ul>")
                in_list = False
            out.append("")
            continue

        out.append(text)

    if in_list:
        out.append("</ul>")

    # Consecutive non-tag lines form one paragraph.
    paragraphs, buffer = [], []

    for line in out:
        if line.startswith(("<h3>", "<ul>", "<li>", "</ul>")):
            if buffer:
                paragraphs.append("<p>%s</p>" % " ".join(buffer))
                buffer = []
            paragraphs.append(line)
        elif line:
            buffer.append(line)
        elif buffer:
            paragraphs.append("<p>%s</p>" % " ".join(buffer))
            buffer = []

    if buffer:
        paragraphs.append("<p>%s</p>" % " ".join(buffer))

    return "\n".join(paragraphs)


def entry_name(definition):
    """Derives a display name and kind from the line following a doc block."""
    fn = re.match(r"function\s+HorseCollisionMod[:.](\w+)\s*\((.*?)\)?$", definition)
    if fn:
        return "function", fn.group(1), fn.group(2).rstrip(")")

    local_fn = re.match(r"local\s+function\s+(\w+)\s*\((.*?)\)", definition)
    if local_fn:
        return "local", local_fn.group(1), local_fn.group(2)

    tbl = re.match(r"HorseCollisionMod\.(\w+)\s*=", definition)
    if tbl:
        return "table", tbl.group(1), ""

    return None, None, None


CSS = """
:root{--bg:#fbfaf7;--fg:#23201c;--mut:#6b6459;--line:#e3ddd2;--acc:#7a5c2e;
--code:#f2ede3;--card:#fff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
.wrap{display:flex;max-width:1180px;margin:0 auto;gap:2.5rem;padding:0 1.5rem}
nav{width:230px;flex:0 0 230px;position:sticky;top:0;align-self:flex-start;
height:100vh;overflow-y:auto;padding:2rem 0;border-right:1px solid var(--line)}
nav h2{font-size:.72rem;letter-spacing:.09em;text-transform:uppercase;
color:var(--mut);margin:1.6rem 0 .5rem}
nav a{display:block;padding:.2rem 0;color:var(--fg);text-decoration:none;
font-size:.9rem}
nav a:hover{color:var(--acc);text-decoration:underline}
main{flex:1;min-width:0;padding:2rem 0 5rem}
h1{font-size:1.9rem;margin:0 0 .3rem}
.sub{color:var(--mut);margin:0 0 2rem;font-size:.92rem}
h2{font-size:1.3rem;margin:2.8rem 0 .8rem;padding-bottom:.35rem;
border-bottom:1px solid var(--line)}
h3{font-size:1.02rem;margin:1.6rem 0 .5rem}
p{margin:.7rem 0}
code{background:var(--code);padding:.1em .35em;border-radius:3px;
font:.88em ui-monospace,SFMono-Regular,Consolas,monospace}
.item{background:var(--card);border:1px solid var(--line);border-radius:7px;
padding:1.1rem 1.3rem;margin:1.1rem 0}
.sig{font:.95rem ui-monospace,SFMono-Regular,Consolas,monospace;
color:var(--acc);font-weight:600;margin:0 0 .5rem;word-break:break-word}
table{border-collapse:collapse;width:100%;margin:.8rem 0;font-size:.9rem}
th,td{text-align:left;padding:.4rem .6rem;border-bottom:1px solid var(--line);
vertical-align:top}
th{color:var(--mut);font-weight:600;font-size:.78rem;text-transform:uppercase;
letter-spacing:.05em}
td:first-child{font-family:ui-monospace,Consolas,monospace;white-space:nowrap}
.ret{color:var(--mut);font-size:.9rem;margin:.5rem 0 0}
ul{margin:.6rem 0;padding-left:1.2rem}
li{margin:.25rem 0}
@media(max-width:860px){.wrap{flex-direction:column;gap:0}
nav{width:auto;flex:auto;position:static;height:auto;border-right:0;
border-bottom:1px solid var(--line)}}
"""


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    text = io.open(SOURCE, encoding="ascii").read()
    blocks = parse_blocks(text)

    module_prose, module_tags = None, []
    tables, functions = [], []

    for doc, definition in blocks:
        prose, tags = split_tags(doc)
        tag_names = [t for t, _ in tags]

        if "module" in tag_names:
            module_prose, module_tags = prose, tags
            continue

        kind, name, params = entry_name(definition)

        if not name:
            continue

        record = (name, params, prose, tags)

        if kind == "table":
            tables.append(record)
        else:
            functions.append(record)

    def meta(tags, key):
        for tag, value in tags:
            if tag == key:
                return value
        return ""

    parts = []
    parts.append("<!doctype html><html lang='en'><head><meta charset='utf-8'>")
    parts.append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
    parts.append("<title>HorseCollisionMod API</title>")
    parts.append("<style>%s</style></head><body><div class='wrap'>" % CSS)

    parts.append("<nav><h2>Tables</h2>")
    for name, _, _, _ in tables:
        parts.append("<a href='#t-%s'>%s</a>" % (name, name))
    parts.append("<h2>Functions</h2>")
    for name, _, _, _ in functions:
        parts.append("<a href='#f-%s'>%s</a>" % (name, name))
    parts.append("</nav><main>")

    parts.append("<h1>HorseCollisionMod</h1>")
    parts.append("<p class='sub'>version %s &middot; %s</p>" % (
        html.escape(meta(module_tags, "release")),
        html.escape(meta(module_tags, "author"))))

    if module_prose:
        parts.append(render_prose(module_prose))

    parts.append("<h2>Tables</h2>")
    for name, _, prose, tags in tables:
        parts.append("<div class='item' id='t-%s'>" % name)
        parts.append("<p class='sig'>HorseCollisionMod.%s</p>" % name)
        parts.append(render_prose(prose))

        fields = [(t, v) for t, v in tags if t == "field"]
        if fields:
            parts.append("<table><tr><th>Field</th><th>Meaning</th></tr>")
            for _, value in fields:
                key, _, rest = value.partition(" ")
                parts.append("<tr><td>%s</td><td>%s</td></tr>" % (
                    html.escape(key), html.escape(rest)))
            parts.append("</table>")
        parts.append("</div>")

    parts.append("<h2>Functions</h2>")
    for name, params, prose, tags in functions:
        parts.append("<div class='item' id='f-%s'>" % name)
        parts.append("<p class='sig'>%s(%s)</p>" % (name, html.escape(params)))
        parts.append(render_prose(prose))

        args = [(t, v) for t, v in tags if t.startswith("tparam")]
        if args:
            parts.append("<table><tr><th>Parameter</th><th>Type</th>"
                         "<th>Description</th></tr>")
            for _, value in args:
                bits = value.split(" ", 2)
                typ = bits[0] if bits else ""
                arg = bits[1] if len(bits) > 1 else ""
                desc = bits[2] if len(bits) > 2 else ""
                parts.append("<tr><td>%s</td><td><code>%s</code></td><td>%s</td></tr>"
                             % (html.escape(arg), html.escape(typ), html.escape(desc)))
            parts.append("</table>")

        for tag, value in tags:
            if tag.startswith("treturn"):
                bits = value.split(" ", 1)
                parts.append("<p class='ret'><strong>Returns</strong> "
                             "<code>%s</code> %s</p>" % (
                                 html.escape(bits[0]),
                                 html.escape(bits[1] if len(bits) > 1 else "")))
        parts.append("</div>")

    parts.append("</main></div></body></html>")

    with io.open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(parts))

    print("documented %d tables and %d functions" % (len(tables), len(functions)))
    print("wrote %s (%d bytes)" % (OUT, os.path.getsize(OUT)))


if __name__ == "__main__":
    main()
