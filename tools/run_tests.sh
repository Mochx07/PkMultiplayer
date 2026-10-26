#!/bin/bash
# Runs every suite of the mod against a clean Gen2Recomped at the base the
# patches are cut from (lib/patches/index.lua `base`), extracted once from the
# co-op worktree's git history.
#
#   tools/run_tests.sh            every suite
#   tools/run_tests.sh session    only the suites whose file name has "session"
#
# test_coop.lua is the legacy ROM-free suite: 3 of its checks failed before
# 1.5 already (foesOf order, two Bug Contest checks) and still do.
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${PKM_ENGINE_REPO:-$HOME/Downloads/PkMplayer-merge}"
REF="$(grep -o 'base = "[0-9a-f]*"' "$M/lib/patches/index.lua" | head -1 | cut -d'"' -f2)"
BASE="${PKM_BASE:-$HOME/.cache/pkmultiplayer/base-$REF}"
if [ ! -f "$BASE/main.lua" ]; then
  mkdir -p "$BASE" && git -C "$REPO" archive "$REF" | tar -x -C "$BASE" || exit 1
fi
cd "$BASE"
for t in "$M"/tests/*.lua; do b=$(basename "$t")
  case $b in run.lua|foreign_wrapper_pre.lua|test_coop.lua|foreign_wrapper.lua|reload_patched.lua) continue;; esac
  if [ -n "${1:-}" ] && [[ "$b" != *$1* ]]; then continue; fi
  out=$(timeout 600 luajit "$M/tests/run.lua" "$t" 2>&1)
  echo "== $b: $(echo "$out" | grep -v '^\[warn\]' | tail -1 | cut -c1-160)"
  echo "$out" | grep -E "^FAIL|rror" | grep -v "^\[warn\]" | head -8
done
if [ -z "${1:-}" ]; then
  echo "== foreign_wrapper: $(PKM_EAGER=1 PKM_PRE="$M/tests/foreign_wrapper_pre.lua" luajit "$M/tests/run.lua" "$M/tests/foreign_wrapper.lua" 2>&1 | tail -1)"
  echo "== reload_patched: $(PKM_EAGER=1 luajit "$M/tests/run.lua" "$M/tests/reload_patched.lua" 2>&1 | tail -1)"
  echo "== test_coop: $(LUA_PATH="$M/?.lua;;" luajit "$M/tests/test_coop.lua" 2>&1 | grep -c '^FAIL') FAIL (3 are old)"
  LUA_PATH="$M/?.lua;;" luajit "$M/tests/test_coop.lua" 2>&1 | grep '^FAIL\|rror' | head
fi
