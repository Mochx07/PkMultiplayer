# B5 Report: Gen 1 Story in Co-op (Red / Blue / Yellow)

- **Agent**: `six`
- **Branch**: `n3/six`
- **Worktree**: `/home/mochix/Downloads/pkm-n3/six`
- **Assigned Ports / Identities**: `7920-7939`, `PkN3_six_A` / `PkN3_six_B` (`red`)
- **Engine Patch Regeneration Needed**: **No**. All engine integrations were implemented via `lib/Hooks.lua` wrappers and `src/coop/*` modules (`lib/patches/*` untouched).

---

## 1. What Was Changed

### A. Unified Story State Diffing & Sub-Runner Ownership (`src/coop/CoopStory.lua`)
1. **Unified `snapshot(save)` and `stateChanges(save, before)`**:
   - Previously, `save.objectToggles`, `save.itemsTaken`, and `save.hiddenTaken` were only diffed inside `luaSnapshot` / `luaChanges` (used by Lua talk handlers), so command-row scripts executed by `ScriptRunner:run` (`CoopStory.begin` / `CoopStory.finish`) did not share their `show_object` / `hide_object` toggles with the partner.
   - `snapshot` and `stateChanges` now track `objectToggles` (`kind = "toggle"`), `itemsTaken` (`kind = "taken"`), `hiddenTaken` (`kind = "hidden_taken"`), and `defeatedTrainers` (`kind = "trainer"`), covering both `ScriptRunner` row scripts and Lua handlers without duplication.
   - When `EVENT_RESCUED_MR_FUJI` transitions to `true`, `POKEMON_TOWER_7F`'s `POKEMONTOWER7F_MR_FUJI` is also recorded hidden in `save.objectToggles` (and on the receiving copy) so 7F clears properly for both players.
   - When `EVENT_BEAT_SILPH_CO_GIOVANNI` transitions to `true`, Yellow's `SILPHCO11F_ROCKET` toggle is recorded hidden alongside Red/Blue's `SILPHCO11F_ROCKET1` and `SILPHCO11F_ROCKET2` so Red/Blue <-> Yellow pairs clear 11F cleanly.
2. **Outer Lua Handler + Helper `ScriptRunner` Coexistence**:
   - When a Lua talk or victory handler (`beginLua`) launches a non-big-battle helper `ScriptRunner` (such as `MT_MOON_B2F` fossil pickup or `POKEMON_TOWER_7F.onVictory` Rocket exit walk), `CoopStory.begin` attaches the outer Lua story context (`outer.handedToRunner = true`) instead of clobbering `CoopStory.current`, and closes it once both the outer callback and the runner finish.
   - When a 1-line Lua talk wrapper launches a big-battle `ScriptRunner` (such as `TEXT_POKEMONTOWER2F_RIVAL`), `CoopStory.begin` absorbs the outer snapshot into the runner's big-battle context so `waitForPartner`, `claim`, and `offerBigBattle` run once without sending duplicate events.
3. **Post-Warp Final Coordinates (`CoopStory.finish`)**:
   - When a script warps and then walks the player on the destination map (such as `VERMILION_DOCK`'s S.S. Anne departure script warping to `VERMILION_CITY (18, 31)` and walking 2 tiles north past the ticket guard to `(18, 29)`), `st.warp` updates to the player's final post-script cell `(18, 29, "up")` so the partner lands beside them past the guard.
4. **Synchronous Field Actions (`CoopStory.recordAction`)**:
   - Added `CoopStory.recordAction(game, ow, fn)` to diff and share synchronous Gen 1 field mutations that bypass `ScriptRunner` and `talkScript`:
     - Map item balls (`OverworldState:talkTo` when `npc.def.item` is picked up: `LIFT_KEY`, `SILPH_SCOPE`, `CARD_KEY`, `GOLD_TEETH`, TMs, and field items).
     - Hidden items (`OverworldState:tryHiddenObject`, while keeping hidden Game Corner coins personal).
     - Silph Co. Card Key doors (`OverworldState:tryCardKeyDoor`, sharing `EVENT_SILPH_CO_*_UNLOCKED_DOOR*`).
5. **Live Map Door/Block Refresh (`CoopStory.onPartnerRewards`)**:
   - When partner rewards arrive, `onPartnerRewards` invokes `ow:stampClosedDoors()` (opening unlocked Silph Co. Card Key doors and Rocket Hideout elevator gates live on the partner's screen) and re-runs safe block/toggle-refresh `onEnter` hooks (`GAME_CORNER` poster stairs, `SILPH_CO_2F..11F`, `SAFFRON_CITY`, `POKEMON_TOWER_7F`, `MR_FUJIS_HOUSE`, `ROUTE_12`, `ROUTE_16`, `VICTORY_ROAD_1F..3F`, `POKEMON_MANSION_*`, `CINNABAR_GYM`, `LORELEIS_ROOM`, `BRUNOS_ROOM`, `AGATHAS_ROOM`).
   - `take_item` rewards now use `Bag.remove` so `save.bagOrder` stays consistent when shared key items (`GOLD_TEETH`) are handed in.
6. **Chapter Map Hook Wrapping (`CoopStory.wrapMapHooks`)**:
   - **`POKEMON_TOWER_6F.onStep` (Ghost Marowak at `(10, 16)`)**: Runs inside a `CoopStory` context (`battled = true`, `noCatch = true` kept non-personal in `CoopStory.onBattle`), sends `coop_story_hold` (`class = "GHOST_MAROWAK"`) so a partner stepping on `(10, 16)` while Marowak is active steps back instead of starting a duplicate battle, streams both `"Be gone... Intruders..."` and `"The mother's soul was calmed..."` to the partner's `story.duo` feed, and shares `EVENT_BEAT_GHOST_MAROWAK` via `CoopStory.onAfterBattle()` without taking any consumed `POKE_DOLL` from the partner's bag.
   - **`SILPH_CO_11F.onStep` (Giovanni at `(6, 13)` / `(7, 12)`)**: Guards against `checkCoordEventHere()` re-firing while Giovanni's 3-tile walk (`ow.scriptMoves`) or `stepHold` is active, and sends `coop_story_hold` (`class = "OPP_GIOVANNI"`) so both players walking in together do not double-trigger Giovanni.
   - **`VERMILION_DOCK.onEnter` (S.S. Anne departure)**: Captures `preBefore` snapshot before `onEnter` sets `EVENT_SS_ANNE_LEFT` and queues the departure script, ensuring `EVENT_SS_ANNE_LEFT` is included in `CoopStory.finish`'s diff along with the warp to `VERMILION_CITY (18, 29)`.
   - **`ROUTE_25.onEnter` (post-Bill toggle)**: Wraps the first exit onto Route 25 after helping Bill with `CoopStory.recordAction` so `EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING` and the `BILLSHOUSE_BILL1` / `BILLSHOUSE_BILL2` toggles are shared.
7. **Personal Chapters Kept Personal**:
   - **Silph Co. 7F Lapras (`TEXT_SILPHCO7F_SILPH_WORKER_M1`)**: Detected as `personal = true` by `luaChanges` (`monCount` increase), so `EVENT_GOT_LAPRAS` is never copied to the partner and each player claims their own Lapras.
   - **Safari Zone (`SAFARI_ZONE_GATE`)**: Added `PERSONAL_MAPS = { SAFARI_ZONE_GATE = true }`, `set_field "safari"` observation, and `save.safari` / `save.safariNags` diff checks in `luaSnapshot` / `luaChanges` (including Yellow's free 1-ball entry when broke). Paying, entering, leaving early, or declining `"Leaving early?"` (`warp` back to `SAFARI_ZONE_CENTER`) stays 100% personal and never warps the partner into `SAFARI_ZONE_CENTER`. Meanwhile, `SAFARI_ZONE_SECRET_HOUSE` (`HM_SURF`, `EVENT_GOT_HM03`), `SAFARI_ZONE_WEST` (`GOLD_TEETH` item ball), and `WARDENS_HOUSE` (`take_item GOLD_TEETH`, `HM_STRENGTH`, `EVENT_GAVE_GOLD_TEETH`, `EVENT_GOT_HM04`) share their outcomes with the partner.

### B. Big Battles & Trainer Engagement (`src/coop/CoopReady.lua`, `src/coop/CoopInvites.lua`, `lib/Hooks.lua`)
1. **`CoopManager.askBigBattle` (`src/coop/CoopReady.lua`)**:
   - When both players trigger a Gen 1 big battle together (e.g. `SILPH_CO_11F` Giovanni), the guest yields to the host when `CoopStory.heldHere(ow, class)` is active.
   - When the partner is linked and healthy on another map, `askBigBattle` now offers `VS <NAME>: WAIT <PARTNER> / SOLO` using `CoopStory.WaitHere` before starting a Gen 1 big battle.
2. **Guest Post-Battle Silph Co. Exodus (`src/coop/CoopInvites.lua`)**:
   - In `CoopManager.startGuestBattle`, winning a co-op battle that sets `EVENT_BEAT_SILPH_CO_GIOVANNI` immediately runs the floor's `onEnter` hook (`silphRocketsLeave`) so Giovanni and the Silph Co. Rockets vanish on the guest's screen at once.
3. **`lib/Hooks.lua` Wrappers**:
   - **`MapScripts.talkScript` & `MapScripts.get`**: Wraps `MapScripts.get` with `CoopStory.wrapMapHooks`, and ensures Yellow's `TEXT_ROCKETHIDEOUTB4F_ROCKET` drops `ROCKETHIDEOUTB4F_LIFT_KEY` (`EVENT_ROCKET_DROPPED_LIFT_KEY`) even if the grunt was defeated by trainer sight before being talked to.
   - **`OverworldState:talkTo`**:
     - In Gen 1, undefeated trainers whose `talkScript` is a hand-ported Lua function (`TEXT_ROCKETHIDEOUTB4F_GIOVANNI`, `TEXT_GAMECORNER_ROCKET`, `TEXT_CERULEANCITY_ROCKET`, `TEXT_ROCKETHIDEOUTB4F_ROCKET3`, `TEXT_ROCKETHIDEOUTB4F_ROCKET`, and the 8 Gym Leaders) now route through `self:showMapText` (and `CoopStory.wrapTalk`) instead of being bypassed by `pendingTrainer`.
     - Item-ball pickups (`d.item`) run inside `CoopStory.recordAction`.
   - **`OverworldState:tryHiddenObject` & `OverworldState:tryCardKeyDoor`**: Wrapped with `CoopStory.recordAction`.
   - **`OverworldState:billsHouseBillExits`**: Shares `EVENT_USED_CELL_SEPARATOR_ON_BILL`, `EVENT_MET_BILL`, `EVENT_MET_BILL_2`, and `BILLSHOUSE_BILL1` visibility when Bill exits the Cell Separator.
   - **`OverworldState:engageTrainer`**: Wrapped with `CoopStory.beginLua` / `CoopStory.finishLua` in Gen 1 so trainer battles engaged via coordinate triggers (`SILPH_CO_11F.onStep`), sight (`checkTrainerSight`), or talk share their victory flags (`victories.lua`), `onVictory` scripts (`POKEMON_TOWER_7F.onVictory`), and `onDone` callbacks (`silphRocketsLeave`, Yellow's `ROCKETHIDEOUTB4F_ROCKET` Lift Key drop) with the partner.
   - **`Font.split` / `Font.drawCode` / `Font.advanceOf`**: Added an 8x8 pixel fallback glyph for `"&"` when the active charmap has no `"&"` code (Gen 1's font charmap lacks `"&"`, which previously rendered `"MOCHI & TOBY"` as `"MOCHI   TOBY"` with a missing glyph warning).

---

## 2. How It Was Tested & Exact Results

### A. Unit Test Suites (`./tools/run_tests.sh` & `python3 tools/i18n_check.py`)
- Expanded `tests/coop_gen1_story.lua` from 66 checks to **132 checks**, testing:
  - **S.S. Anne**: Bill's `S_S_TICKET` and Cerulean guard toggles from row script, `ROUTE_25.onEnter` post-Bill flag, Captain's `HM_CUT` + `EVENT_GOT_HM01`, and `VERMILION_DOCK.onEnter` capturing `EVENT_SS_ANNE_LEFT` before `queueScript` and warping the partner to `VERMILION_CITY (18, 29)`.
  - **Pokemon Tower**: 6F Ghost Marowak step trigger, `coop_story_hold` preventing partner double-trigger, calming Marowak sharing `EVENT_BEAT_GHOST_MAROWAK` while preserving the partner's `POKE_DOLL`, 7F Mr. Fuji rescue hiding `POKEMONTOWER7F_MR_FUJI`, showing `MRFUJISHOUSE_MR_FUJI`, swapping Saffron guards, warping the partner to `MR_FUJIS_HOUSE (3, 7)`, and Mr. Fuji's `POKE_FLUTE` + `EVENT_GOT_POKE_FLUTE`.
  - **Rocket Hideout**: Red/Blue `TEXT_ROCKETHIDEOUTB4F_ROCKET3` and Yellow `TEXT_ROCKETHIDEOUTB4F_ROCKET` dropping `ROCKETHIDEOUTB4F_LIFT_KEY`, item-ball pickup sharing `LIFT_KEY` and `itemsTaken` + despawning the ball on the partner's screen, and `TEXT_ROCKETHIDEOUTB4F_GIOVANNI` sharing `EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI`, hiding Giovanni, and revealing `ROCKETHIDEOUTB4F_SILPH_SCOPE`.
  - **Silph Co.**: `CARD_KEY` door unlock sharing `EVENT_SILPH_CO_5_UNLOCKED_DOOR1` and refreshing `stampClosedDoors` live, 7F Lapras (`TEXT_SILPHCO7F_SILPH_WORKER_M1`) staying personal so the partner's `EVENT_GOT_LAPRAS` remains unset and the partner claims their own Lapras, 11F Giovanni (`SILPH_CO_11F.onStep`) sharing `EVENT_BEAT_SILPH_CO_GIOVANNI` and hiding all Silph Co. Rockets (both Red/Blue and Yellow object names), and the Silph President's `MASTER_BALL`.
  - **Safari Zone**: `SAFARI_ZONE_GATE` admission (including Yellow's free 1-ball admission when broke) and `onEnter` warp back to `SAFARI_ZONE_CENTER` staying personal, `SAFARI_ZONE_SECRET_HOUSE` sharing `HM_SURF` + `EVENT_GOT_HM03`, `SAFARI_ZONE_WEST` sharing `GOLD_TEETH` pickup, and `WARDENS_HOUSE` taking `GOLD_TEETH` from both bags and sharing `HM_STRENGTH` + `EVENT_GAVE_GOLD_TEETH` + `EVENT_GOT_HM04`.
  - **Poke Flute & Snorlax**: `ItemEffects.use` with `POKE_FLUTE` adjacent to `ROUTE12_SNORLAX` and `ROUTE16_SNORLAX` returning `"flute_wake"`, `CoopBoss.kindOf` recognizing both as the `"snorlax"` co-op boss, and `snorlaxWake.script` sharing `EVENT_BEAT_ROUTE12_SNORLAX` / `EVENT_BEAT_ROUTE16_SNORLAX` and hiding `ROUTE12_SNORLAX` / `ROUTE16_SNORLAX`.
- All 37 test suites in `./tools/run_tests.sh` pass (`coop_gen1_story.lua: 132/132 checks passed`).
- `python3 tools/i18n_check.py` passes (`0 untranslated, 0 with other pieces, 604 in the catalog`).

### B. Real Hidden Two-Copy Runs (`pair.sh` under Xvfb)
1. **`tests/drivers/six_tower_fuji.lua`** (port `7920`, `red`, `PkN3_six_A` / `PkN3_six_B`):
   - Command:
     `PKM_BASE=~/.cache/pkmultiplayer/base-85512413 ~/Downloads/pkm-120/pair.sh /home/mochix/Downloads/pkm-n3/six /home/mochix/Downloads/pkm-n3/six/tests/drivers/six_tower_fuji.lua 7920 red PkN3_six_A PkN3_six_B /tmp/pkm_six_tower`
   - Result: **`host done: 0 failures` (14/14 checks)**, **`guest done: 0 failures` (12/12 checks)**.
   - Verified screenshots in `/tmp/pkm_six_tower/{host,guest}/`:
     - `1_marowak_begone.png` / `1_marowak_feed.png`: Host triggers Ghost Marowak at `POKEMON_TOWER_6F (10, 16)`; Guest reads `"Be gone... Intruders..."` in the `story.duo` feed and receives `EVENT_BEAT_GHOST_MAROWAK`.
     - `2_tower7f_fuji.png`: Both stand before Mr. Fuji on `POKEMON_TOWER_7F`, talk to him, set `EVENT_RESCUED_MR_FUJI`, hide `POKEMONTOWER7F_MR_FUJI`, and warp together to `MR_FUJIS_HOUSE`.
     - `3_duo_scene_host.png` / `3_duo_scene_guest.png`: Duo scene in `MR_FUJIS_HOUSE` renders `"MR.FUJI: MOCHI & TOBY."` on Host and `"MR.FUJI: TOBY & MOCHI."` on Guest (with the new Gen 1 `"&"` glyph and `SELECT: REACT` tab).
     - `4_duo_handover_host.png` / `4_duo_handover_guest.png`: Host reads `"MOCHI received a POKe FLUTE!"`, Guest turns their pages with A and gets their own `"TOBY received POKe FLUTE!"` box, and Host reads `"TOBY got one too!"`.
     - `5_snorlax_boss_menu.png`: Using `POKE_FLUTE` next to Route 12 Snorlax wakes it into `BATTLE MODE: CO-OP BOSS / SOLO BATTLE`.
2. **`tests/drivers/six_silph_personal.lua`** (port `7922`, `red`, `PkN3_six_A` / `PkN3_six_B`):
   - Command:
     `PKM_BASE=~/.cache/pkmultiplayer/base-85512413 ~/Downloads/pkm-120/pair.sh /home/mochix/Downloads/pkm-n3/six /home/mochix/Downloads/pkm-n3/six/tests/drivers/six_silph_personal.lua 7922 red PkN3_six_A PkN3_six_B /tmp/pkm_six_silph`
   - Result: **`host done: 0 failures` (8/8 checks)**, **`guest done: 0 failures` (8/8 checks)**.
   - Verified screenshots in `/tmp/pkm_six_silph/{host,guest}/`:
     - `1_host_got_lapras.png` / `1_guest_own_lapras.png`: Host receives Lapras on `SILPH_CO_7F` while Guest's `EVENT_GOT_LAPRAS` remains unset, and Guest then talks to the worker to claim their own personal Lapras.
     - `2_vs_giovanni_menu.png`: Host unlocks the `SILPH_CO_11F` Card Key door at `(6, 13)` (opening the door live on Guest's screen too) and steps onto `(6, 13)`, walking Giovanni down and opening `VS GIOVANNI: CO-OP / SOLO`.
     - `3_host_giovanni_cleared.png` / `3_guest_giovanni_cleared.png`: Host defeats Giovanni, sharing `EVENT_BEAT_SILPH_CO_GIOVANNI` and the Silph Co. Rocket exodus so `SILPHCO11F_GIOVANNI` and the Rockets vanish on both screens.

---

## 3. Open Issues
- None. All 6 Gen 1 story chapters, unit tests, i18n checks, and two-copy drivers pass with 0 failures.
