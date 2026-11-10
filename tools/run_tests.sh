#!/bin/bash
# Runs every suite of the mod against a clean Gen2Recomped at the base the
# patches are cut from (lib/patches/index.lua `base`), extracted once from the
# co-op worktree's git history.
#
#   tools/run_tests.sh            every suite
#   tools/run_tests.sh session    only the suites whose file name has "session"
#
# test_coop.lua is the legacy ROM-free suite; it runs through run.lua like the
# rest (run bare, without the mod's patches, its foesOf and Bug Contest checks
# fail because the engine underneath is unpatched).
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${PKM_ENGINE_REPO:-$HOME/Downloads/PkMplayer-merge}"
REF="$(grep -o 'base = "[0-9a-f]*"' "$M/lib/patches/index.lua" | head -1 | cut -d'"' -f2)"
BASE="${PKM_BASE:-$HOME/.cache/pkmultiplayer/base-$REF}"
if [ ! -f "$BASE/main.lua" ]; then
  mkdir -p "$BASE" && git -C "$REPO" archive "$REF" | tar -x -C "$BASE" || exit 1
fi
cd "$BASE"
# the exit status says whether anything failed (CI reads it)
bad=0
for t in "$M"/tests/*.lua; do b=$(basename "$t")
  case $b in run.lua|foreign_wrapper_pre.lua|test_coop.lua|foreign_wrapper.lua|reload_patched.lua|patch_cache.lua|patch_cache_pre.lua) continue;; esac
  if [ -n "${1:-}" ] && [[ "$b" != *$1* ]]; then continue; fi
  out=$(timeout 600 luajit "$M/tests/run.lua" "$t" 2>&1) || { bad=1; echo "!! $b failed"; }
  echo "== $b: $(echo "$out" | grep -v '^\[warn\]' | tail -1 | cut -c1-160)"
  echo "$out" | grep -E "^FAIL|rror" | grep -v "^\[warn\]" | head -8
done
if [ -z "${1:-}" ]; then
  extra() { # name, then the command; its last lines are the summary
    local name=$1; shift
    local out
    out=$("$@" 2>&1) || { bad=1; echo "!! $name failed"; }
    echo "== $name: $(echo "$out" | tail -1)"
  }
  PKM_EAGER=1 PKM_PRE="$M/tests/foreign_wrapper_pre.lua" extra foreign_wrapper luajit "$M/tests/run.lua" "$M/tests/foreign_wrapper.lua"
  PKM_EAGER=1 extra reload_patched luajit "$M/tests/run.lua" "$M/tests/reload_patched.lua"
  PKM_EAGER=1 PKM_PRE="$M/tests/patch_cache_pre.lua" extra patch_cache luajit "$M/tests/run.lua" "$M/tests/patch_cache.lua"
  out=$(luajit "$M/tests/run.lua" "$M/tests/test_coop.lua" 2>&1) || { bad=1; echo "!! test_coop failed"; }
  echo "== test_coop: $(echo "$out" | grep -c '^ok') ok, $(echo "$out" | grep -c '^FAIL') FAIL"
  echo "$out" | grep -E "^FAIL|rror" | grep -v "^\[warn\]" | head
fi
exit $bad
