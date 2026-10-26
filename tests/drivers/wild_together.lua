-- WILD TOGETHER between two real game instances, linked over 127.0.0.1.
--
--   PKM_ROLE=host|guest PKM_PORT=7791 SHOT_DIR=/tmp/pkm \
--   POKEPORT_VERSION=gold POKEPORT_IDENTITY=<copy> \
--   POKEPORT_DRIVER=<mod>/tests/drivers/wild_together.lua love .
--
-- Both stand a few steps apart on Route 29.  The host meets a wild Pokemon
-- (a random encounter, as a step makes one) with the rule on; the guest is
-- asked, joins with the first three of its party, and both fight the same
-- wild pair in a co-op double.  After a turn the two copies must agree on the
-- foes' HP; then the host runs and both are back on the overworld.
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

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local team = role == "host" and { 155, 16 } or { 158, 161 }
  for _, n in ipairs(team) do
    local m = Pokemon.new(game.data, ("SPECIES_%03d"):format(n), 13)
    m.moves = { { id = "TACKLE", pp = 35 } }
    table.insert(save.party, m)
  end
  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both on Route 29")
  U.wait(60)
  local Music = require("src.core.Music")
  -- a teleport does not start the map's music; the overworld's own call does
  Music.playMap(game.data, "ROUTE29")
  U.wait(30)
  local mapSong = Music.current()
  U.log(role .. ": music on the map: " .. tostring(mapSong))

  local function topBattle()
    local top = game.stack:top()
    return top and top.coopDouble and top or nil
  end

  if role == "host" then
    CoopManager.setRule("wildTogether", true)
    U.wait(30)
    local BattleState = require("src.battle.BattleState")
    local ow = game.overworld
    local battle = BattleState.newWild(game, "SPECIES_016", 9)
    battle.onFinish = function(r) ow:afterBattle(r, battle) end
    ow.pkmRandomEncounter = true
    ow:pushBattle(battle)
    ow.pkmRandomEncounter = nil
    check(CoopManager.pendingBattleInvite ~= nil, "the partner is asked")
  else
    local asked = false
    for _ = 1, 60 * 20 do
      if CoopManager.activeInviteModal then asked = true break end
      U.wait(1)
    end
    check(asked, "the invite arrives")
    -- A counts once the invite has been up 0.8 s (CoopBattleInviteModal.ARM_TIME)
    U.wait(70)
    U.shot(game, DIR .. "/1_invite.png")
    local function topName()
      local t = game.stack:top()
      return t and (t.isCoopInvite and "invite" or t.isCoopBattleSelect and "select"
                    or t == game.overworld and "overworld" or tostring(t.phase or t)) or "nil"
    end
    U.tap(game, "a"); U.wait(30)
    U.log("guest: after A on the invite: " .. topName())
    U.shot(game, DIR .. "/1b_select.png")
    U.tap(game, "start"); U.wait(30)
    U.log("guest: after START on the team: " .. topName())
  end

  local battle
  for _ = 1, 60 * 20 do
    battle = topBattle()
    if battle then break end
    U.wait(1)
  end
  check(battle and battle.coopWild, "a co-op wild double is up")
  if not battle then love.event.quit(1) return end

  -- through the intro to the action menu, then one TACKLE each
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    U.tap(game, "a"); U.wait(4)
  end
  check(battle.phase == "menu", "reached FIGHT / PKMN / PACK / RUN")
  U.shot(game, DIR .. "/2_menu.png")
  local P = BattleState and BattleState.POS or require("src.battle.BattleState").POS
  local foes = { battle:battlerAt(P.OPPONENT_LEFT), battle:battlerAt(P.OPPONENT_RIGHT) }
  check(foes[1] and foes[2] and foes[1].mon.species == "SPECIES_016", "two wild PIDGEY on the field")
  for _ = 1, 6 do U.tap(game, "a"); U.wait(12) end
  local turnSeen = false
  for _ = 1, 60 * 30 do
    if battle.coop and battle.coop.turn and battle.coop.turn >= 2 then
      turnSeen = true break
    end
    if battle.phase ~= "menu" and battle.phase ~= "waitPartner" then U.tap(game, "a") end
    U.wait(3)
  end
  check(turnSeen, "a turn went by")
  U.shot(game, DIR .. "/3_after_turn.png")
  local hp = {}
  for i, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
    local b = battle:battlerAt(pos)
    hp[i] = b and b.mon.hp or -1
  end
  U.log(role .. ": FOE_HP " .. hp[1] .. " " .. hp[2])

  -- the bag: no BALL together
  local ItemEffects = require("src.inventory.ItemEffects")
  local ballId = require("src.follow.FollowMon").itemByKey(game.data, "POKE_BALL")
  save.inventory[ballId] = 5
  local r = ItemEffects.use(game.data, save, ballId, nil, battle)
  check(r == "failed", "a BALL can't be thrown together")

  if role == "host" then
    -- RUN from the action menu, as a player picks it
    local last
    for _ = 1, 60 * 20 do
      if battle.phase == "menu" then break end
      if battle.phase ~= last then U.log("host: phase " .. tostring(battle.phase)) last = battle.phase end
      if battle.phase == "moveSelect" then U.tap(game, "b")
      elseif battle.phase ~= "waitPartner" then U.tap(game, "a") end
      U.wait(3)
    end
    U.log("host: running from phase " .. tostring(battle.phase))
    battle:tryRun()
  end
  local back = false
  for _ = 1, 60 * 20 do
    if game.stack:top() == game.overworld then back = true break end
    if game.stack:top() == battle then U.tap(game, "a") end
    U.wait(3)
  end
  check(back, "both got away, back on Route 29")
  local t0 = love.timer.getTime()
  while love.timer.getTime() - t0 < 4 do U.wait(1) end
  U.log(role .. ": music after the battle: " .. tostring(Music.current()))
  check(Music.current() == mapSong, "the map's music came back")
  U.shot(game, DIR .. "/4_back.png")
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
