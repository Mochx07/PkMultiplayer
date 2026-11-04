-- THE RIVAL IN 2v2 (1.20 story.gyms), two Gold/Crystal copies.
--
--   pair.sh <mod> rival_2v2.lua <port> gold <host> <guest> <out>
--
-- Both stand in AZALEA TOWN by the Slowpoke Well, where the rival waits.
-- The host (MOCHI, took TOTODILE, rival SILVER) steps onto the rival's tile;
-- the guest (TOBY, took CHIKORITA, rival KAMON) is on the map and accepts
-- the CO-OP invite.  The battle must be two trainers on both screens:
-- SILVER on the left with the team of the CHIKORITA he took from MOCHI's
-- story (OPP_RIVAL1 #4), KAMON on the right with TOBY's own rival team
-- (#5, QUILAVA).  The "teamA:" / "teamB:" lines of the two logs must match,
-- both named in the intro, and the double is won with no copy drifting.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7792")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  U.wait(5)
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local CM = require("src.coop.CoopManager")
  local CoopGyms = require("src.coop.CoopGyms")
  local CoopBattle = require("src.coop.CoopBattle")
  local Pokemon = require("src.pokemon.Pokemon")
  local Gen2Flags = require("src.script.Gen2Flags")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.player.rival = role == "host" and "SILVER" or "KAMON"
  -- six foes in three turns: no move animations, fast text (pair.sh stops at 300 s)
  save.options = save.options or {}
  save.options.animations = false
  save.options.textSpeed = 1
  save.flags = save.flags or {}
  save.flags[Gen2Flags.eventFlag(26)] = true                         -- got a Pokemon from ELM
  save.flags[Gen2Flags.eventFlag(role == "host" and 28 or 29)] = true -- TOTODILE / CHIKORITA
  -- the rival waits by the well on the host's map only
  save.g2Scenes = save.g2Scenes or {}
  if role == "host" then save.g2Scenes.AZALEA_TOWN = 1 end
  local best
  for id, mv in pairs(game.data.moves or {}) do
    if mv.name == "PSYCHIC" then best = id break end
  end
  for _ = 1, 3 do
    local m = Pokemon.new(game.data, "SPECIES_150", 45)
    m.moves = { { id = best, pp = 40 } }
    table.insert(save.party, m)
  end
  U.teleport(game, "AZALEA_TOWN", role == "host" and 6 or 8, role == "host" and 10 or 12, "left")
  if role == "host" then CM.host(port) else U.wait(60) CM.join("127.0.0.1", port) end
  for _ = 1, 60 * 30 do
    if CM.isConnected() and CM.partner.map == "AZALEA_TOWN" then break end
    U.wait(1)
  end
  check(CM.isConnected(), "linked in AZALEA TOWN")
  U.wait(90)
  check(CoopGyms.on(), "story.gyms on for both")
  U.shot(game, DIR .. "/0_town.png")
  local go = os.time() + 2
  while os.time() < go do U.wait(1) end

  local ow = game.overworld
  if role == "host" then
    for _ = 1, 6 do
      U.hold(game, "left", 18) U.wait(20)
      local o = game.overworld
      if (o.runner and o.runner:isRunning()) or game.stack:top() ~= o then break end
    end
    U.log("host on the rival's tile: scene=" .. tostring(game.stack:top() ~= game.overworld
          or (game.overworld.runner and game.overworld.runner:isRunning())))
  end
  local function nm(m) local d = game.data.pokemon[m.species] return (d and d.name or m.species) .. (m.level or "?") end
  local function list(p) local t = {} for _, m in ipairs(p or {}) do t[#t + 1] = nm(m) end return table.concat(t, " ") end
  local battle, shots, shotField = nil, 0, false
  local battleAt
  local t0 = love.timer.getTime()
  local quietSince
  while love.timer.getTime() - t0 < 255 do
    local top = game.stack:top()
    ow = game.overworld
    local running = ow and ow.runner and ow.runner.isRunning and ow.runner:isRunning()
    if top and top.chooseAction and top ~= battle then
      battle = top
      battleAt = U.frame()
      U.log("teamA: " .. tostring(top.trainer and top.trainer.name) .. " " .. list(top.enemyParty))
      U.log("teamB: " .. tostring(top.trainerB and top.trainerB.name) .. " " .. list(top.enemyPartyB))
      U.log(role .. " battle: coopDouble=" .. tostring(top.coopDouble) .. " rivals=" .. tostring(top.coopRivals)
            .. " intro=" .. tostring(top.introText):gsub("\n", " / "))
    end
    -- the intro (both trainers named), then the field
    if battle and top == battle and shots < 4 and U.frame() - battleAt >= 30 + shots * 45 then
      shots = shots + 1
      U.shot(game, DIR .. ("/1_intro_%d.png"):format(shots))
    end
    if battle and top == battle and not shotField and battle.phase == "menu" then
      shotField = true
      U.wait(10)
      U.shot(game, DIR .. "/2_field.png")
    end
    if battle and top == ow and not running then
      quietSince = quietSince or love.timer.getTime()
      if love.timer.getTime() - quietSince > 6 then break end
    else
      quietSince = nil
    end
    if top and top.isCoopBattleSelect then
      U.tap(game, "start") U.wait(20)
    elseif top ~= ow then
      -- hold off pressing A through the intro so it can be read on the shots
      if not (battle and top == battle and shots < 4) then U.tap(game, "a") end
      U.wait(8)
    else
      U.wait(6)
    end
  end
  U.shot(game, DIR .. "/3_end.png")
  check(battle and battle.coopDouble and battle.coopRivals, "the co-op double is the two rivals")
  check(battle and battle.trainer and battle.trainer.name == "SILVER" and battle.trainerB
        and battle.trainerB.name == "KAMON", "SILVER on the left, KAMON on the right, on both screens")
  local a, b = battle and battle.enemyParty or {}, battle and battle.enemyPartyB or {}
  check(#a == 3 and #b == 3 and nm(a[3]) == "BAYLEEF16" and nm(b[3]) == "QUILAVA16",
        "each with his own team: " .. list(a) .. " | " .. list(b))
  check(battle and tostring(battle.introText):find("SILVER & KAMON", 1, true) ~= nil, "both named in the intro")
  check(shotField, "the field came up (2_field.png)")
  check(battle and battle.result == "win", "won (" .. tostring(battle and battle.result) .. ")")
  check((CoopBattle.desyncs or 0) == 0, "the copies never drifted (" .. tostring(CoopBattle.desyncs) .. ")")
  U.wait(60 * 3)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
