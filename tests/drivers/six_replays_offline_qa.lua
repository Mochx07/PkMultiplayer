-- SIX QA: Complete Replay & Offline Replay Menu QA.
-- Plays a fast 1-turn battle, verifies replay recording, disconnects to test
-- offline menu REPETICIONES, B button navigation back, and replay spectator playback.
--
--   pair.sh <mod> six_replays_offline_qa.lua 7817 gold PkMp15B PkMpBigB <out>
--
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7817")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/six_replays") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopLink = require("src.coop.CoopLink")
  local CoopVS = require("src.coop.CoopVS")
  local CoopReplay = require("src.coop.CoopReplay")
  local CoopMenu = require("src.coop.CoopMenu")
  local I18n = require("src.coop.CoopI18n")

  -- Clean old replays for clean test
  CoopReplay.forget()
  for _, n in ipairs(CoopReplay.list()) do
    pcall(love.filesystem.remove, CoopReplay.DIR .. "/" .. n)
  end
  CoopReplay.forget()
  check(#CoopReplay.list() == 0, "replays directory clean at start")

  -- Test offline menu when 0 replays exist
  local menu0 = CoopMenu.new(game)
  local offRows0 = menu0:offlineRows()
  local hasReplays0 = false
  for _, r in ipairs(offRows0) do
    if r.sub == "replays" or r.label == "REPLAYS" then hasReplays0 = true break end
  end
  check(not hasReplays0, "offline menu does NOT show REPLAYS when 0 replays exist")

  local save = U.freshSave(game)
  save.options = save.options or {}
  save.options.animations = false
  save.player.name = role == "host" and "MOCHI" or "TOBY"

  -- Host: Level 60 Mewtwo with Psychic
  -- Guest: Level 3 Caterpie with Tackle
  if role == "host" then
    local m = Pokemon.new(game.data, "SPECIES_150", 60)
    m.moves = { { id = "PSYCHIC", pp = 10 } }
    table.insert(save.party, m)
  else
    local m = Pokemon.new(game.data, "SPECIES_010", 3)
    m.moves = { { id = "TACKLE", pp = 35 } }
    table.insert(save.party, m)
  end

  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "joining 127.0.0.1:" .. port)
  end

  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked on Route 29")
  U.wait(60)

  -- Invite to FREE BATTLE
  if role == "host" then
    check(CoopLink.invite(game, "battle", CoopVS.FORMATS.free), "sent FREE BATTLE invite")
  else
    local asked
    for _ = 1, 60 * 20 do
      asked = CoopLink.asked
      if asked then break end
      U.wait(1)
    end
    check(asked ~= nil, "guest received FREE BATTLE invite")
    if asked then
      U.wait(70)
      U.tap(game, "a")
    end
  end

  -- Wait for link battle to open (host confirms level rule if classic/free battle)
  local battle
  for _ = 1, 60 * 40 do
    local top = game.stack:top()
    if role == "host" and top and top.stage == "battleOptions" then
      U.tap(game, "a")
    end
    if top and top.kind == "link" and not top.spectating then battle = top break end
    U.wait(1)
  end
  check(battle ~= nil, "link battle opened")

  -- Play out the 1-turn battle by tapping A
  for _ = 1, 60 * 30 do
    local top = game.stack:top()
    if top == game.overworld then break end
    if top == battle and battle.phase == "moveSelect" then
      U.tap(game, "a")
      U.wait(4)
    elseif top == battle or (top and top ~= game.overworld) then
      U.tap(game, "a")
      U.wait(6)
    else
      U.wait(1)
    end
  end
  check(game.stack:top() == game.overworld, "returned to overworld after battle")
  U.wait(60)

  -- Verify replay was written
  local replays = CoopReplay.list()
  check(#replays == 1, "exactly 1 replay was recorded (" .. tostring(replays[1]) .. ")")
  local rep = replays[1] and CoopReplay.load(replays[1])
  check(rep ~= nil and #rep.log > 0, "replay data loaded successfully with log actions")
  if rep then
    U.log(role .. ": replay winner=" .. tostring(rep.winner or "battle ended") .. " turns=" .. #rep.log)
  end

  -- Disconnect to test OFFLINE replay menu
  CoopManager.disconnect()
  U.wait(30)
  check(not CoopManager.isConnected(), "successfully disconnected: now offline")

  -- Test offline menu in Spanish
  I18n.forced = "es"
  local menu = CoopMenu.new(game)
  game.stack:push(menu)
  U.wait(10)

  local offRows = menu:offlineRows()
  local replayRowIndex = nil
  for idx, r in ipairs(offRows) do
    if r.sub == "replays" then replayRowIndex = idx break end
  end
  check(replayRowIndex ~= nil, "REPETICIONES appears in offline menu when a replay exists (row " .. tostring(replayRowIndex) .. ")")
  U.shot(game, DIR .. "/offline_menu_es.png")

  -- Open REPETICIONES
  menu.index = replayRowIndex or 1
  U.tap(game, "a")
  U.wait(10)
  check(menu.page == "replays", "navigated to replays subpage in offline menu")
  local replayRows = menu:replayRows()
  check(#replayRows == 1, "replays list contains 1 item")
  check(replayRows[1].label:match("^VS "), "replay label starts with VS: " .. tostring(replayRows[1].label))
  check(replayRows[1].info[1] == "COMBATE LIBRE" or replayRows[1].info[1] == "FREE BATTLE",
        "replay info shows format COMBATE LIBRE: " .. tostring(replayRows[1].info[1]))
  U.shot(game, DIR .. "/offline_replays_list_es.png")

  -- Test B button navigation back to offline main menu
  U.tap(game, "b")
  U.wait(10)
  check((menu.page or "main") == "main", "B button walked back to offline main menu")
  check(menu.index == replayRowIndex, "cursor restored to REPETICIONES row (index " .. tostring(replayRowIndex) .. ")")

  -- Launch replay playback from menu
  menu.index = replayRowIndex
  U.tap(game, "a")
  U.wait(10)
  -- Select replay item 1
  U.tap(game, "a")
  U.wait(20)

  local specBattle = nil
  for _ = 1, 60 * 30 do
    local top = game.stack:top()
    if top and top.spectating then specBattle = top break end
    U.wait(1)
  end
  check(specBattle ~= nil, "replay spectator battle launched successfully from offline menu")
  if specBattle then
    U.shot(game, DIR .. "/replay_spectator.png")
    U.log(role .. ": spectator replay running")
  end

  -- Wait for replay to play through by tapping A to advance spectator dialogue
  for _ = 1, 60 * 40 do
    local top = game.stack:top()
    if top == game.overworld then break end
    if top ~= game.overworld then
      U.tap(game, "a")
      U.wait(6)
    else
      U.wait(1)
    end
  end
  check(game.stack:top() == game.overworld, "returned to overworld after replay spectator finished")

  U.log(role .. " replays offline QA done: " .. fails .. " failures")
  love.event.quit(fails == 0 and 0 or 1)
end
