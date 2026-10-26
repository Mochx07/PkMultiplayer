#!/usr/bin/env python3
"""Lists the mod's on-screen English lines that src/coop/CoopLangES.lua does
not translate, and catalog entries whose %s / %d pieces do not match.

    python3 tools/i18n_check.py          # report
    python3 tools/i18n_check.py --strict # exit 1 when anything is missing

Only literals handed to the places that draw text are looked at -- Font.draw,
showStatus, a row's label / info / lines, a modal's cancelLabel -- and a line
put together with `..` is checked as a template ("WAITING " .. name ->
"WAITING %s").  A line that matches a catalog template counts as translated,
the way CoopI18n.t matches it at run time.
"""
import re
import sys
from pathlib import Path

MOD = Path(__file__).resolve().parent.parent
SOURCES = sorted((MOD / "src" / "coop").glob("*.lua")) + [MOD / "src" / "follow" / "FollowMon.lua"]
SKIP = {"CoopLangES.lua", "CoopI18n.lua", "CoopLog.lua", "CoopNet.lua"}

STRING = r'"((?:[^"\\]|\\.)*)"'
# a call or field that puts text on screen, then its first argument / value
SINKS = re.compile(
    r'(?:Font\.draw|showStatus|fit|wrap|header\s*=|label\s*=|cancelLabel\s*=)\s*\(?\s*'
    r'((?:' + STRING + r'|[\w.:\[\]()]+)(?:\s*\.\.\s*(?:' + STRING + r'|[\w.:\[\]()"]+))*)')
LIST_SINKS = re.compile(r'(?:info|lines)\s*=\s*\{([^}]*)\}')


def catalog():
    text = (MOD / "src" / "coop" / "CoopLangES.lua").read_text(encoding="utf-8")
    entries = {}
    for m in re.finditer(r'\[' + STRING + r'\]\s*=\s*\n?\s*' + STRING, text):
        key = m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8")
        val = m.group(2).encode().decode("unicode_escape").encode("latin-1").decode("utf-8")
        entries[key] = val
    return entries


def template(expr):
    """`"WAITING " .. name` -> "WAITING %s"; None when there is no text in it."""
    parts = re.split(r'\s*\.\.\s*', expr.strip())
    out, literal = [], False
    for p in parts:
        m = re.fullmatch(STRING, p)
        if m:
            out.append(m.group(1))
            literal = True
        else:
            out.append("%s")
    if not literal:
        return None
    return "".join(out)


def as_pattern(key):
    pat = re.escape(key)
    pat = re.sub(r'%\\?\d*[sd]', '(.*?)', pat.replace('\\%', '%'))
    return re.compile("^" + pat + "$", re.S)


def pieces(s):
    return len(re.findall(r'%\d*[sd]', s))


def is_text(s):
    # something a player reads: has a letter, is not an id / key / format
    if not re.search(r'[A-Za-z]{2}', s):
        return False
    if re.fullmatch(r'[a-z_][a-z0-9_.]*', s):
        return False
    if s.startswith(("src.", "coop_", "net_", "EVENT_", "OPP_")) or "%0" in s:
        return False
    return True


def main():
    cat = catalog()
    templates = [(as_pattern(k), k) for k in cat if pieces(k) > 0]

    def translated(line):
        if line in cat:
            return True
        probe = line.replace("%s", "X")
        return any(p.match(probe) or p.match(line) for p, _ in templates)

    missing = {}
    for path in SOURCES:
        if path.name in SKIP:
            continue
        for n, src in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if src.lstrip().startswith("--"):
                continue
            found = []
            for m in SINKS.finditer(src):
                t = template(m.group(1))
                if t is not None:
                    found.append(t)
            for m in LIST_SINKS.finditer(src):
                # a help box is translated as one block (CoopI18n.lines)
                block = re.findall(STRING, m.group(1))
                if not translated("\n".join(block)):
                    found.extend(block)
            for line in found:
                if is_text(line) and not translated(line):
                    missing.setdefault(line, f"{path.relative_to(MOD)}:{n}")

    bad = [k for k, v in cat.items() if pieces(k) != pieces(v)]
    for line, where in sorted(missing.items(), key=lambda kv: kv[1]):
        print(f"untranslated  {where}  {line!r}")
    for k in bad:
        print(f"pieces differ  {k!r} -> {cat[k]!r}")
    print(f"{len(missing)} untranslated, {len(bad)} with other pieces, {len(cat)} in the catalog")
    if "--strict" in sys.argv and (missing or bad):
        sys.exit(1)


if __name__ == "__main__":
    main()
