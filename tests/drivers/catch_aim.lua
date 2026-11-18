-- THROWING IN TIME between two real copies (Gold), CoopCatch "catch.aim".
-- Wild together (two against one), both choose a POKe BALL the same turn,
-- the ring comes up on both screens, both press A as it closes; the two
-- copies must agree on the misses and on the throw's outcome.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7805")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopCatch = require("src.coop.CoopCatch")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  for _, n in ipairs(role == "host" and { 155 } or { 158 }) do
    table.insert(save.party, Pokemon.new(game.data, ("SPECIES_%03d"):format(n), 13))
  end
  local ballId = require("src.follow.FollowMon").itemByKey(game.data, "POKE_BALL")
  save.inventory = save.inventory or {}
  save.inventory[ballId] = 5
  do
    local okP, Pipelines = pcall(require, "src.render.Pipelines")
    if okP then for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end end
  end
  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")
  if role == "host" then check(CoopManager.host(port), "hosting")
  else U.wait(60) check(CoopManager.join("127.0.0.1", port), "dialling") end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked on Route 29")
  check(CoopManager.bothHave(CoopCatch.AIM_CAP), "both copies can throw in time")
  U.wait(60)
  if role == "host" then
    CoopManager.setRule("wildTogether", true)
    U.wait(30)
    local BattleState = require("src.battle.BattleState")
    local ow = game.overworld
    local battle = BattleState.newWild(game, "SPECIES_016", 4)
    battle.onFinish = function(r) ow:afterBattle(r, battle) end
    ow.pkmRandomEncounter = true
    ow:pushBattle(battle)
    ow.pkmRandomEncounter = nil
  end
  local battle
  for i = 1, 60 * 25 do
    local tp = game.stack:top()
    if tp and tp.coopWild and tp.phase then battle = tp break end
    if role == "guest" and tp and tp.isCoopInvite and i % 30 == 0 then U.tap(game, "a") end
    if tp and tp.isCoopBattleSelect and i % 20 == 0 then U.tap(game, "start") end
    U.wait(1)
  end
  check(battle ~= nil, "two against one is up")
  if not battle then love.event.quit(1) return end
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    U.tap(game, "a") U.wait(4)
  end
  check(battle.phase == "menu", "FIGHT / PKMN / PACK / RUN")
  battle:chooseAction({ special = "playerItem", id = ballId, messages = {}, coopBall = "POKE_BALL" })
  -- the ring
  local ring
  for _ = 1, 60 * 20 do
    local tp = game.stack:top()
    if tp and tp.isCoopAim then ring = tp break end
    U.wait(1)
  end
  check(ring ~= nil, "the ring is up")
  if ring then
    U.shot(game, DIR .. "/1_ring.png")
    while ring.aim.t < CoopCatch.AIM_TIME - 0.02 do U.wait(1) end
    U.tap(game, "a")
    U.wait(2)
    U.log(("%s: my miss %s ms"):format(role, tostring(ring.aim.mine)))
    check(ring.aim.mine ~= nil and ring.aim.mine < 250, "my press landed in time")
  end
  -- the throw
  local caughtAt, outcome
  for _ = 1, 60 * 40 do
    if battle.coopKeep or battle.coopCaught then outcome = "caught" break end
    if battle.coopBalls and battle.coopBalls.done and battle.phase == "menu" then outcome = "missed" break end
    if battle.phase ~= "menu" and battle.phase ~= "waitPartner" and not (game.stack:top() or {}).isCoopAim then U.tap(game, "a") end
    U.wait(3)
  end
  U.shot(game, DIR .. "/2_after.png")
  U.log(("%s: OUTCOME %s"):format(role, tostring(outcome)))
  CoopManager.sendChat("OUT " .. tostring(outcome))
  local agreed
  for _ = 1, 60 * 15 do
    for _, line in ipairs(CoopManager.chatLog or {}) do
      local o = tostring(line.text):match("^OUT (%a+)")
      if o and line.sender ~= save.player.name then agreed = (o == tostring(outcome)) end
    end
    if agreed ~= nil then break end
    U.wait(1)
  end
  check(outcome ~= nil, "the throw happened")
  check(agreed == true, "both copies saw the same outcome")
  U.wait(60)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
