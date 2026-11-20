PkMultiplayer nightly.3: codex E1 + E3

Worktree: `/home/mochix/Downloads/pkm-n3/codex`. Branch: `n3/codex`.
Only codex identities `PkN3_codex_A` / `PkN3_codex_B`, Pokemon Red (`red`), and ports 7940-7959 were used. No engine files, patches, other worktrees, tags, pushes, or releases were changed.

**Implementation**

`src/coop/CoopTouch.lua` supplies touch targets for the co-op menu and every page, diagnostics, host addresses/code, recent hosts, address/port editors, invite-code keyboard, new-game name/role/link/READY steps, team selection, invitations, waiting prompts, emotes, chat (including its battle overlay), VS link/results, keeper choices, the catch timing ring, shared text prompts, Pokedex, Soul Links, and watching. Mod-created generic menus cover the battle-mode, tower and contest choices too. The co-op entries in the engine's title/start menus and the title's continue/new choice receive touch routing. An idle-field CO-OP button opens the menu without a physical START key.

The engine delivers LOVE window coordinates through `Game:touchpressed/moved/released`. The wrappers in `lib/Hooks.lua` give the mod's active screen ownership before the engine pad; release stays with the screen that took the press. Mapping inverts `Renderer.uiPresentation` (`x`, `y`, `scaleX`, `scaleY`), already expressed in LOVE units, without applying DPI twice. Owned screens hold UI anchoring so their draw and hit coordinates share the same centered 160x144 surface. Virtual controls remain available on the field and are hidden over the mod's own targets.

A tap selects and confirms on release. Dragging moves list cursors and scroll windows without confirming; out-of-screen/BACK taps cancel. Changed screens/pages and secondary fingers cannot activate a stale choice. Focus/visibility changes clear canceled gestures. Existing semantic screen actions are reused through a temporary input facade; no keys or held/queued game buttons are manufactured by the drivers.

The in-game keyboard supplies digits, uppercase letters, punctuation, erase, space, confirm/send and back for code/name/chat. On touch-driven phones it replaces the native keyboard, keeping its coordinates deterministic; desktop text entry remains available. The recent-host page has a bounded six-row window. Invitation choices have separate 16-pixel rows; the team retains its compact six-member layout. English/Spanish labels use CoopI18n and the Spanish catalog.

**Decisions**

- Kept the invitation's existing 0.8-second arming protection.
- Kept the lobby's second confirmation before quitting a live link; BACK changes to QUIT after the first tap.
- Canceling a keeper choice chooses the existing fair-coin option, so ownership cannot remain unresolved.
- Kept protocol 17 and all existing capability gates. No messages or fields were added.
- Screen fixtures initialize saves/scenarios, but every navigation, typing, selection and confirmation action in the drivers is a simulated `love.touchpressed/moved/released` event. No `U.tap`, key callbacks, clipboard paste, or direct host/join/chat/emote/invite calls drive the integration flow.
- Drivers flush their final assertions and use `os.exit` for bounded headless teardown after screenshots finish. Some earlier runs completed assertions but lingered during normal application shutdown.

**Verification**

| Claim | Executed check | Result | Status |
| --- | --- | --- | --- |
| Geometry, boundaries, all screen rows/pages, cancellation, drag, multitouch, keyboard actions, title/start entries, invalid code/port, fainted selection, focus recovery | `tools/run_tests.sh coop_touch` | 5102/5102 assertions | PASS |
| Complete regression suite including the staged new module | `tools/run_tests.sh` | 61 suite summaries green; legacy 234 ok / 0 FAIL; release contents 101 files | PASS |
| English/Spanish catalog | `python3 tools/i18n_check.py --strict` | 0 untranslated, 0 placeholder mismatches, 615 entries | PASS |
| Real touch-only host/join/code/chat/emote/READY/VS with the engine pad enabled | `codex_touch_pair.lua`, final command below | Host 0 failures; guest 0 failures; launcher exit 0 | PASS |
| Real two-copy name/lobby/READY, all menu pages, scrolling, VS results, rival invitation and team selection | `codex_touch_screens.lua`, final command below | Host 0 failures; guest 0 failures; launcher exit 0 | PASS |
| Final emote BACK layout and cancellation | `codex_touch_pair.lua` with `CODEX_TOUCH_EMOTE_BACK=1`, port 7949 | Host 0 failures; guest 0 failures; launcher exit 0 | PASS |

Final integration commands (Xvfb is the launcher's default; no visible window or sound):

```sh
ALSOFT_DRIVERS=null LP_NUM_THREADS=1 CODEX_TOUCH_PAD=1 CODEX_TOUCH_LANG=es \
PKM_BASE=~/.cache/pkmultiplayer/base-85512413 PKM_TIMEOUT=300 \
~/Downloads/pkm-120/pair.sh ~/Downloads/pkm-n3/codex \
  tests/drivers/codex_touch_pair.lua 7947 red \
  PkN3_codex_A PkN3_codex_B /tmp/codex-touch-pair-clean

ALSOFT_DRIVERS=null LP_NUM_THREADS=1 \
PKM_BASE=~/.cache/pkmultiplayer/base-85512413 PKM_TIMEOUT=300 \
~/Downloads/pkm-120/pair.sh ~/Downloads/pkm-n3/codex \
  tests/drivers/codex_touch_screens.lua 7948 red \
  PkN3_codex_A PkN3_codex_B /tmp/codex-touch-screens-clean

ALSOFT_DRIVERS=null LP_NUM_THREADS=1 CODEX_TOUCH_PAD=1 CODEX_TOUCH_LANG=es \
CODEX_TOUCH_EMOTE_BACK=1 PKM_BASE=~/.cache/pkmultiplayer/base-85512413 PKM_TIMEOUT=300 \
~/Downloads/pkm-120/pair.sh ~/Downloads/pkm-n3/codex \
  tests/drivers/codex_touch_pair.lua 7949 red \
  PkN3_codex_A PkN3_codex_B /tmp/codex-touch-emote-clean
```

The pair uses 960x540 / 540x690 windows; the gallery uses 1000x610 / 510x730. Geometry tests also exercise fractional, non-square DPI and sub-unit scales plus letterbox rejection. The pair sends `TOUCH HOST` / `TOUCH GUEST` by tapping individual keyboard cells and checks receipt on the other game. Both games toggle READY, pick an emote, and enter a real VS battle after a touch invitation response. The gallery starts both live lobbies by touching READY, drags a 14-row production Menu until the visible window moves, confirms row 7, and then starts the real Gen 1 rival co-op battle with changed three-member teams.

Literal outputs are committed in [suites.log](evidence/codex/suites.log), [i18n.log](evidence/codex/i18n.log), [pair.log](evidence/codex/pair.log), and [screens.log](evidence/codex/screens.log), and [emote.log](evidence/codex/emote.log). Development suites, drivers, report and evidence are excluded in `.modkitignore`.

**Visual evidence**

86 screenshots from the verified runs are represented in four contact sheets: [pair host](evidence/codex/pair-host.png), [pair guest](evidence/codex/pair-guest.png), [screen gallery host](evidence/codex/screens-host.png), [screen gallery guest](evidence/codex/screens-guest.png). The emote frames are refreshed from the final focused BACK regression. The full-resolution originals and engine logs remain in the output directories above. I opened and inspected the sheets and individual code, chat, port, invitation, team and Pokedex captures. The emote BACK button sits below all seven bubble numbers. The final layouts keep targets on the rendered rows; the host-address outline no longer crosses its code, and touch footers no longer leave old labels behind in the editors/Pokedex.

**Limits and engine requests**

Physical Android/iOS hardware and vendor IMEs are NOT CHECKED: these were real Linux LOVE games in Xvfb. Tower/contest invitations and waits use the production modal classes as explicit fixtures inside the assigned Red games; Crystal's actual tower/contest gameplay is NOT CHECKED. The keeper fixture exercises the real ownership menu and choice, without granting a Pokemon. The VS result fixture exercises the real scoreboard and dismissal with an isolated transport; actual VS invitation/start and rival co-op invitation/team/start use the live two-copy connection. Full battle completion and capture mechanics are outside E1/E3.

Engine patches requested: none. No remaining E1/E3 implementation issue was observed in the executed checks.
