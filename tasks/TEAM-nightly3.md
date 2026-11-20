# PkMultiplayer 2.0.0-nightly.3 -- team brief (2026-11-20)

PkMultiplayer is Mochi's 2-player online CO-OP mod for Gen2Recomped (LOVE 11.5 / LuaJIT): two players
beat Pokemon Red/Blue/Yellow and Gold/Silver/Crystal together. It is NOT an MMO. Repo
~/Downloads/PkMultiplayer, base branch `v2.0/nightly.3`. The plan with an audit is tasks/todo.md
(section "2.0.0-nightly.3: plan"); read it and src/coop/*.lua relevant to your task first.

## Hard rules
1. Work only in YOUR worktree/branch (table below). Commit there with
   `git -c user.name=Mochx07 -c user.email=256135680+Mochx07@users.noreply.github.com commit ...`.
   Never push, tag or publish. Never touch other worktrees, ~/Downloads/PkMplayer-merge or lib/patches/*.
2. The mod ships no engine code. Engine behaviour changes go through lib/Hooks.lua wrappers (the
   `wrap(t, label, name, make)` helper) or src/coop modules. If you truly need an engine patch, do NOT
   write it: describe it precisely (file, function, what to change, why) in your report; claude does it.
3. Anything that changes what goes over the wire sits behind a capability
   (`CoopManager.registerCap(name)` / `CoopManager.bothHave(name)`). Protocol stays 17.
4. Every on-screen text in English AND Spanish: `CoopI18n.t(...)` with the Spanish in
   src/coop/CoopLangES.lua; `python3 tools/i18n_check.py` must pass. Game Boy style, must fit 160x144.
   No emojis anywhere (code, UI, docs, commit messages). Code/comments in English.
5. Suites: `tools/run_tests.sh` (all) must stay green; add a suite under tests/ for your logic and list
   it in .modkitignore like the others.
6. Real two-copy tests are REQUIRED and ALWAYS hidden (Xvfb, no sound, never a visible window):
   `PKM_BASE=~/.cache/pkmultiplayer/base-85512413 ~/Downloads/pkm-120/pair.sh <your-worktree>
   <driver.lua> <port> <version> <idA> <idB> <out-dir>`. Drivers live in tests/drivers/ and MUST be
   named `<you>_*.lua` (the launcher copies them into a shared folder by file name). Look at
   tests/drivers/gen1_rival.lua and gen1_legend.lua for how a driver drives two real Red games.
   Use only YOUR ports and identities; other agents run at the same time.
7. Look at your screenshots (PNG) before claiming something looks right.
8. When done: tasks/REPORT-<you>.md (what, how tested, exact results, open issues, engine patches you
   need) committed on your branch.

## Who does what
| Agent | Worktree / branch | Ports | Identities (Pokemon Red imported, version "red") | Task |
|---|---|---|---|---|
| claude | main checkout, v2.0/nightly.3 | 7900-7919 | PkMpRedA/B | B1 gyms, B2 League + Hall of Fame, then B6 |
| six | ~/Downloads/pkm-n3/six, n3/six | 7920-7939 | PkN3_six_A/B | B5 Gen 1 story |
| codex | ~/Downloads/pkm-n3/codex, n3/codex | 7940-7959 | PkN3_codex_A/B | E1 touch on the mod's screens + E3 simulated-touch tests |
