-- THE MAGIKARP CONTEST between two real game instances (1.20 M3,
-- src/coop/mg/MagikarpContest.lua), linked over 127.0.0.1.
--
--   ~/Downloads/pkm-120/pair.sh <mod> tests/drivers/karp_contest.lua 7791 gold \
--     PkMultiplayerTest PkMultiplayerTest2 <out>
--
-- Both stand on the shore of the LAKE OF RAGE with an OLD ROD, a few steps
-- apart.  The host asks the guest to the contest from the frame; the guest
-- accepts with A.  For the two minutes each copy fishes with the engine's own
-- rod (OverworldState:goFishing, the cast the BAG makes) and taps A through
-- the engine's boxes and the contest's own.  No battle may open; nothing may
-- join the party.  At the end each copy sends the winner it worked out to the
-- other, and both must name the same one.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7791")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function quit()
    U.wait(120)
    U.log(("%s done: %d failures"):format(role, fails))
    love.event.quit(fails == 0 and 0 or 1)
  end

  U.wait(5)
  -- the flat world: the voxel one is slow on a virtual screen
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.player.id = role == "host" and 12345 or 4660
  local m = Pokemon.new(game.data, "SPECIES_155", 20)
  m.moves = { { id = "TACKLE", pp = 35 } }
  table.insert(save.party, m)
  local function itemByKey(key)
    for id, def in pairs(game.data.items or {}) do
      if type(def) == "table" and def.key == key then return id end
    end
  end
  local rod = itemByKey("OLD_ROD")
  save.inventory[rod] = 1
  local ballsBefore = save.inventory[itemByKey("GREAT_BALL")] or 0

  -- a shore cell: walkable, water in front of it
  U.teleport(game, "LAKE_OF_RAGE", 5, 5, "down")
  local map = game.overworld.map
  local spots = {}
  local dirs = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  for cy = 2, map.heightCells - 3 do
    for cx = 2, map.widthCells - 3 do
      if map:isWalkableCell(cx, cy) and not map:isWaterCell(cx, cy) then
        for _, f in ipairs({ "up", "left", "right", "down" }) do
          local d = dirs[f]
          if map:isWaterCell(cx + d[1], cy + d[2]) then spots[#spots + 1] = { cx, cy, f } break end
        end
      end
    end
  end
  check(#spots >= 2, "the lake has shore cells: " .. #spots)
  local spot = spots[1]
  -- the guest's spot a few steps from the host's; a spot the teleport does
  -- not land on facing water is skipped
  local ow, fx, fy
  local order = {}
  for i = (role == "guest" and #spots or 1), (role == "guest" and 1 or #spots), (role == "guest" and -1 or 1) do
    order[#order + 1] = spots[i]
  end
  for _, sp in ipairs(order) do
    U.teleport(game, "LAKE_OF_RAGE", sp[1], sp[2], sp[3])
    ow = game.overworld
    ow.player.facing = sp[3]
    fx, fy = ow.player:facingCell()
    if ow.map:isWaterCell(fx, fy) then spot = sp break end
    U.log(("%s: spot %d,%d %s -> at %s,%s facing %s, not water"):format(role, sp[1], sp[2], sp[3],
          tostring(ow.player.cellX), tostring(ow.player.cellY), tostring(ow.player.facing)))
  end
  check(ow.map.id == "LAKE_OF_RAGE" and ow.map:isWaterCell(fx, fy),
        ("on the shore at %d,%d facing %s, water ahead"):format(ow.player.cellX, ow.player.cellY, spot[3]))

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "LAKE_OF_RAGE" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both at the LAKE OF RAGE")
  if not linked then return quit() end
  U.wait(90)

  -- each copy's winner, to the other
  local theirWinner
  CoopManager.handlers.drv_karp_winner = function(_, msg) theirWinner = msg.winner end

  local MG = require("src.coop.CoopMinigame")
  local Karp = require("src.coop.mg.MagikarpContest")
  check(MG.GAMES.karp ~= nil and CoopManager.bothHave("minigame.karp"), "both copies have the contest")
  if role == "host" then
    check(MG.invite(game, "karp", ow), "asked the partner to the MAGIKARP CONTEST")
    U.wait(20)
    U.shot(game, DIR .. "/1_asking.png")
  else
    local asked = false
    for _ = 1, 60 * 20 do
      if MG.asked then asked = true break end
      U.wait(1)
    end
    check(asked, "the invite arrives")
    U.wait(70)
    U.shot(game, DIR .. "/1_invite.png")
    U.tap(game, "a")
  end
  local started = false
  for _ = 1, 60 * 20 do
    if MG.session and MG.session.phase == "play" then started = true break end
    U.wait(1)
  end
  check(started, "the contest is on after the countdown")
  if not started then return quit() end

  -- fish: cast whenever the field is free, A through every box
  local casts, battles, shots = 0, 0, 0
  local s = MG.session
  local partySize = #save.party
  while MG.session == s and s.phase == "play" do
    local top = game.stack:top()
    if top == ow and not ow.fishing and not ow.transitioning then
      ow.player.facing = spot[3]
      ow:goFishing(rod)
      casts = casts + 1
      U.wait(2)
    elseif top and top.enemy ~= nil and top.kind ~= nil then
      battles = battles + 1
      U.wait(2)
    else
      U.tap(game, "a")
      U.wait(6)
    end
    if s.data.catches and s.data.catches >= 1 and shots == 0 then
      U.wait(30)
      U.shot(game, DIR .. "/2_first_catch.png")
      shots = 1
    end
    if s.t > 60 and shots == 1 then U.shot(game, DIR .. "/3_half_time.png") shots = 2 end
  end
  U.log(("%s: %d casts, %d MAGIKARP, best %s"):format(role, casts, s.data.catches or 0, Karp.lengthText(s.score)))
  check(casts > 3, "fished with the engine's rod: " .. casts .. " casts")
  check(battles == 0, "no battle opened during the contest")
  check(#save.party == partySize, "nothing joined the party")

  -- the result on both
  -- a copy whose frames come slower is still fishing: wait for it
  for _ = 1, 60 * 240 do
    if s.phase == "result" then break end
    if game.stack:top() ~= ow then U.tap(game, "a") U.wait(6) else U.wait(1) end
  end
  check(s.phase == "result", "the contest has a result: " .. tostring(s.result))
  U.wait(10)
  U.shot(game, DIR .. "/4_result.png")
  local me, them = save.player.name, tostring(CoopManager.partner.name)
  local winner = ({ win = me, lose = them, draw = "DRAW", none = "NONE" })[s.result] or "?"
  U.log(("%s: RESULT %s mine=%s theirs=%s winner=%s"):format(role, tostring(s.result), tostring(s.final),
        tostring(s.partnerFinal), winner))
  check(s.partnerFinal ~= nil, "the partner's final length arrived before the result: " .. tostring(s.partnerFinal))
  CoopManager.net:send({ type = "drv_karp_winner", winner = winner })
  for _ = 1, 60 * 240 do
    if theirWinner then break end
    U.wait(1)
  end
  check(theirWinner ~= nil and theirWinner == winner, "both copies name the same winner: " .. tostring(winner)
        .. " / " .. tostring(theirWinner))
  local ballsAfter = save.inventory[itemByKey("GREAT_BALL")] or 0
  if s.result == "win" and (s.final or 0) > 0 then
    check(ballsAfter == ballsBefore + 1, "the winner got one GREAT BALL")
  else
    check(ballsAfter == ballsBefore, "no prize for " .. tostring(s.result))
  end
  for _ = 1, 60 * 10 do
    if MG.session == nil then break end
    U.wait(1)
  end
  check(MG.session == nil, "the result goes away, back to the lake")
  U.shot(game, DIR .. "/5_after.png")
  quit()
end
