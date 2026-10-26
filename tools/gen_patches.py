#!/usr/bin/env python3
"""Regenerate lib/patches/ from a Gen2Recomped checkout.

    tools/gen_patches.py <engine checkout> <base ref> <co-op ref>

<base ref> is the upstream Gen2Recomped commit the mod targets; <co-op ref>
is the same tree with the co-op changes merged in.  For every engine file in
MODULES this writes lib/patches/<Name>.lua: each top-level function the co-op
build changed or added, verbatim, plus the file-level code it added, and
records in lib/patches/index.lua which upstream function each one replaces
(with an FNV-1a hash of it, so the mod can say when upstream changed one
underneath it).

Functions listed in a module's `skip` are not transplanted: lib/Hooks.lua
wraps them by hand instead (the co-op code only runs before or after them).
"""
import difflib, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luaunits import units  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, 'lib', 'patches')

OVERWORLD_SKIP = {
    # the clock reads: the co-op build only renamed os.date("%H") (no-op)
    'effectiveHour', 'objectTodBit', 'clockTimeOfDay',
    'OverworldState.clockTimeOfDayBit',
    # wrapped in lib/Hooks.lua
    'OverworldState:pushBattle', 'OverworldState:checkTrainerSight',
    'OverworldState:afterBattle', 'OverworldState:drawWorld',
    'OverworldState:drawUI',
    # a comment only
    'OverworldState:update',
}

# File-level locals no engine function captures (they are only read while the
# file loads), so the patch environment cannot find them: the patch gets its
# own copy, as the engine file declares it.
EXTRA_PRELUDE = {
    'src/battle/BattleState.lua': ['local WEAK_KEYS = { __mode = "k" }'],
}

MODULES = [
    # file, require name, skip, keep loose additions
    ('src/battle/BattleState.lua', 'src.battle.BattleState', set(), True),
    ('src/battle/Damage.lua', 'src.battle.Damage', {'Damage.compute'}, True),
    ('src/battle/Experience.lua', 'src.battle.Experience', set(), True),
    ('src/battle/Gen2AnimPlayer.lua', 'src.battle.Gen2AnimPlayer', set(), True),
    ('src/battle/MoveEffects.lua', 'src.battle.MoveEffects', set(), True),
    ('src/battle/Targeting.lua', 'src.battle.Targeting', set(), True),
    ('src/battle/TrainerAI.lua', 'src.battle.TrainerAI', {'TrainerAI.switchAction'}, True),
    ('src/inventory/ItemEffects.lua', 'src.inventory.ItemEffects', set(), True),
    ('src/link/LinkBattle.lua', 'src.link.LinkBattle', set(), True),
    ('src/link/Protocol.lua', 'src.link.Protocol', set(), True),
    ('src/render/HudTiles.lua', 'src.render.HudTiles', set(), True),
    ('src/render/TextBox.lua', 'src.render.TextBox', {'TextBox.new'}, True),
    ('src/script/Commands.lua', 'src.script.Commands', set(), True),
    ('src/script/Gen2Daily.lua', 'src.script.Gen2Daily', set(), True),
    ('src/script/ScriptRunner.lua', 'src.script.ScriptRunner', set(), True),
    ('src/ui/BagMenu.lua', 'src.ui.BagMenu', set(), True),
    ('src/ui/HallOfFame.lua', 'src.ui.HallOfFame', set(), True),
    ('src/ui/Menu.lua', 'src.ui.Menu', {'Menu.new'}, True),
    ('src/ui/PartyMenu.lua', 'src.ui.PartyMenu', set(), True),
    ('src/ui/PokegearMenu.lua', 'src.ui.PokegearMenu', set(), True),
    ('src/ui/TitleState.lua', 'src.ui.TitleState', set(), True),
    ('src/world/BugContest.lua', 'src.world.BugContest', set(), True),
    ('src/world/OverworldController.lua', 'src.world.OverworldController', OVERWORLD_SKIP, False),
]


def show(repo, ref, path):
    return subprocess.run(['git', '-C', repo, 'show', f'{ref}:{path}'],
                          check=True, capture_output=True).stdout.decode('latin-1')


def fnv(text):
    h = 0x811C9DC5
    for b in text.encode('latin-1'):
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return '%08x' % h


def file_scope(text):
    names = []
    for line in text.split('\n'):
        m = re.match(r'^local\s+function\s+([A-Za-z_]\w*)', line)
        if m:
            names.append(m.group(1))
            continue
        m = re.match(r'^local\s+([A-Za-z_][\w\s,]*?)\s*(?:=|--|$)', line)
        if m:
            names += [n.strip() for n in m.group(1).split(',') if n.strip()]
    seen, out = set(), []
    for n in names:
        if n not in seen:
            seen.add(n)
            out.append(n)
    return out


def live_names(text, scope):
    live = []
    for n in scope:
        if re.search(r'^[ \t]+' + re.escape(n) + r'\s*=[^=]', text, re.M):
            live.append(n)
    return live


def module_local(text):
    for line in reversed(text.rstrip().split('\n')):
        m = re.match(r'^return\s+([A-Za-z_]\w*)\s*$', line)
        if m:
            return m.group(1)
    raise SystemExit('no `return X` at the end of the file')


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


WS = ' \t\r\n\f\v'


def lhash(line):
    """A line's hash, indentation and trailing blanks left out."""
    return fnv(line.strip(WS))


REF_MIN = 6  # shorter lines (`end`, `else`) travel as text


def encode_put(new_lines, src_lines):
    """The new lines; any that the source function already has go as refs."""
    where = {}
    for k, l in enumerate(src_lines):
        t = l.strip(WS)
        if len(t) >= REF_MIN and t not in where:
            where[t] = k
    put = []
    for l in new_lines:
        t = l.strip(WS)
        k = where.get(t)
        if k is not None:
            indent = l[:len(l) - len(l.lstrip(' \t'))]
            put.append('{ r = %d, h = %s, i = %s }' % (k + 1, lua_str(lhash(l)), lua_str(indent)))
        else:
            put.append(lua_str(l))
    return put


def edits_between(src_lines, new_lines):
    out = []
    sm = difflib.SequenceMatcher(None, src_lines, new_lines, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            continue
        before = [lhash(l) for l in src_lines[max(0, i1 - 2):i1]]
        old = [lhash(l) for l in src_lines[i1:i2]]
        after = [lhash(l) for l in src_lines[i2:i2 + 2]]
        put = encode_put(new_lines[j1:j2], src_lines)
        out.append('        { at = %d, cut = %d,\n'
                   '          ctx = { before = { %s }, old = { %s }, after = { %s } },\n'
                   '          put = {%s} },' % (
                       i1 + 1, i2 - i1,
                       ', '.join(map(lua_str, before)), ', '.join(map(lua_str, old)),
                       ', '.join(map(lua_str, after)),
                       ''.join('\n            %s,' % x for x in put) + ('\n          ' if put else '')))
    return out


def best_source(u, base_units):
    """The engine function a brand-new co-op function was built from, if any:
    the one sharing the most (non-trivial) lines with it."""
    mine = {l.strip(WS) for l in u['text'].split('\n') if len(l.strip(WS)) >= REF_MIN}
    best, score = None, 0
    for b in base_units:
        theirs = {l.strip(WS) for l in b['text'].split('\n') if len(l.strip(WS)) >= REF_MIN}
        n = len(mine & theirs)
        if n > score:
            best, score = b, n
    return best if score >= 4 else None


def emit_unit(u, b, base_units):
    head = '    { name = %s, kind = %s,' % (lua_str(u['name']), lua_str(u['kind']))
    new_lines = u['text'].split('\n')
    src = b or best_source(u, base_units)
    if not src:
        return [head + ' text = {'] + ['      %s,' % lua_str(l) for l in new_lines] + ['    } },']
    out = [head]
    if not b:
        out.append('      from = %s, fromKind = %s,' % (lua_str(src['name']), lua_str(src['kind'])))
    out.append('      base = %s, edits = {' % lua_str(fnv(src['text'])))
    out += edits_between(src['text'].split('\n'), new_lines)
    out.append('      } },')
    return out


def main():
    repo, base_ref, coop_ref = sys.argv[1:4]
    base_rev = subprocess.run(['git', '-C', repo, 'rev-parse', '--short', base_ref],
                              check=True, capture_output=True, text=True).stdout.strip()
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith('.lua'):
            os.remove(os.path.join(OUT, old))
    index = []
    for path, req, skip, keep_loose in MODULES:
        base = show(repo, base_ref, path)
        new = show(repo, coop_ref, path)
        bu, bl = units(base)
        nu, nl = units(new)
        # keyed by (name, nth definition): a file may define one twice
        def keyed(us):
            seen, out = {}, []
            for u in us:
                n = seen.get(u['name'], 0)
                seen[u['name']] = n + 1
                out.append(((u['name'], n), u))
            return out
        bmap = dict(keyed(bu))
        modname = module_local(base)
        scope = file_scope(base)
        live = live_names(base, scope)

        picked = []
        for key, u in keyed(nu):
            if u['name'] in skip:
                continue
            b = bmap.get(key)
            if b and b['text'] == u['text']:
                continue
            picked.append((u, b))

        prelude = list(EXTRA_PRELUDE.get(path, []))
        if keep_loose:
            for line in difflib.unified_diff([l for _, l in bl], [l for _, l in nl],
                                             n=0, lineterm=''):
                if line.startswith('+') and not line.startswith('+++'):
                    prelude.append(line[1:])
        prelude_locals = []
        for line in prelude:
            m = re.match(r'^local\s+([A-Za-z_][\w\s,]*?)\s*(?:=|--|$)', line)
            if m:
                prelude_locals += [n.strip() for n in m.group(1).split(',') if n.strip()]
        if not picked and not any(l.strip() and not l.strip().startswith('--') for l in prelude):
            print(f'{path}: nothing to transplant')
            continue
        fwd = [u['name'] for u, _ in picked if u['kind'] == 'local']

        stem = os.path.splitext(os.path.basename(path))[0]
        base_texts = [b['text'] for b in bu]
        out = [
            f'-- PkMultiplayer: how the co-op build changes {path}.',
            f'-- GENERATED by tools/gen_patches.py against Gen2Recomped {base_rev};',
            '-- edit the co-op tree and regenerate rather than editing this file.',
            '--',
            '-- This file carries no engine code.  Each unit is a list of edits to the',
            '-- engine function as it reads in the player\'s own copy of the game:',
            '-- where (`at`, and the hashes of the lines around it, `ctx`), how many of',
            '-- its lines go (`cut`), and what goes in their place (`put`: the co-op',
            '-- build\'s own lines, or {r = n, h = hash, i = indent} for "line n of the',
            '-- engine function, re-indented").  lib/Transplant.lua applies them.',
            'return {',
            '  prelude = {',
        ]
        out += [f'    {lua_str(l)},' for l in prelude]
        out.append('  },')
        out.append('  units = {')
        for u, b in picked:
            out += emit_unit(u, b, bu)
        out.append('  },')
        out.append('}')
        with open(os.path.join(OUT, stem + '.lua'), 'w', encoding='latin-1', newline='\n') as f:
            f.write('\n'.join(out) + '\n')

        index.append(f'  {{ module = {lua_str(req)}, file = {lua_str(path)}, '
                     f'name = {lua_str(modname)}, patch = {lua_str("lib/patches/" + stem + ".lua")},\n'
                     '    scope = { ' + ', '.join(lua_str(n) for n in scope) + ' },\n'
                     '    live = { ' + ', '.join(lua_str(n) for n in live) + ' } },')
        print(f'{path}: {len(picked)} functions, {len(prelude)} loose lines')

    with open(os.path.join(OUT, 'index.lua'), 'w', newline='\n') as f:
        f.write('-- GENERATED by tools/gen_patches.py: the engine files the co-op build\n'
                f'-- changes (lib/patches/), as they read in Gen2Recomped {base_rev}, and\n'
                '-- the names of their file-level locals.\n'
                f'return {{\n  base = {lua_str(base_rev)},\n  modules = {{\n'
                + '\n'.join(index) + '\n  },\n}\n')


if __name__ == '__main__':
    main()
