-- A CO-OP BOSS between two real game instances, linked over 127.0.0.1
-- (src/coop/CoopBoss.lua, capability "story.bosses").
--
--   pair.sh <mod> tests/drivers/boss_double.lua <port> gold <idA> <idB> <out>
--
-- Both stand on Route 29.  The host meets SUDOWOODO the way its script
-- starts it (a wild battle that is not a step in the grass), picks CO-OP
-- BOSS and its team; the guest accepts.  On both screens: SUDOWOODO alone on
-- its side with twice its HP, moving twice each turn, the two copies agreeing
-- on every HP turn after turn (FOE_HP lines).  Then the host runs and both
-- are back on the overworld.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7830")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  -- the flat world: the voxel one is slow on a virtual screen
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local BattleState = require("src.battle.BattleState")
  local P = BattleState.POS
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local team = role == "host" and { 159, 160, 158 } or { 158, 159, 160 }
  for _, n in ipairs(team) do
    local m = Pokemon.new(game.data, ("SPECIES_%03d"):format(n), 40)
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
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29"
       and CoopManager.bothHave("story.bosses") then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both on Route 29, both with story.bosses")
  U.wait(60)

  local function topName()
    local t = game.stack:top()
    return t and (t.isCoopInvite and "invite" or t.isCoopBattleSelect and "select"
                  or t == game.overworld and "overworld" or tostring(t.header or t.phase or t)) or "nil"
  end

  if role == "host" then
    local ow = game.overworld
    -- Commands.start_battle's wild battle: SUDOWOODO, level 20, no step
    local battle = BattleState.newWild(game, "SPECIES_185", 20)
    battle.onFinish = function(r) ow:afterBattle(r, battle) end
    local CoopBoss = require("src.coop.CoopBoss")
    local def = game.data.pokemon.SPECIES_185
    U.log(("host: SUDOWOODO dex %s (def.dex %s), kind %s"):format(tostring(CoopBoss.dexOf(game.data, "SPECIES_185")),
          tostring(def and def.dex), tostring(CoopBoss.kindOf(battle, ow))))
    -- the partner's position fresh (a copy busy building its 3D map can go
    -- quiet for seconds; the boss is then fought alone, as it should)
    local function fresh() return love.timer.getTime() - (CoopManager.partner.lastSeen or 0) < 1.0 end
    for _ = 1, 60 * 60 do
      if fresh() and CoopManager.partnerAvailable(ow, false, true) then break end
      U.wait(1)
    end
    U.log("host: partner available: " .. tostring(select(2, CoopManager.partnerAvailable(ow, false, true)) or "yes"))
    ow:pushBattle(battle)
    U.wait(30)
    check(battle.coopBoss == "sudowoodo", "SUDOWOODO is a boss (" .. tostring(battle.coopBoss) .. ")")
    U.shot(game, DIR .. "/1_battle_mode.png")
    U.log("host: top is " .. topName())
    U.tap(game, "a"); U.wait(30)            -- CO-OP BOSS
    U.log("host: after CO-OP BOSS: " .. topName())
    U.tap(game, "start"); U.wait(30)        -- the team as it stands
    check(CoopManager.pendingBattleInvite ~= nil, "the partner is asked")
  else
    local asked = false
    for _ = 1, 60 * 30 do
      if CoopManager.activeInviteModal then asked = true break end
      U.wait(1)
    end
    check(asked, "the invite arrives")
    U.wait(70)
    U.shot(game, DIR .. "/1_invite.png")
    U.tap(game, "a"); U.wait(30)
    U.tap(game, "start"); U.wait(30)
  end

  local battle
  for i = 1, 60 * 30 do
    local top = game.stack:top()
    if top and top.coopDouble then battle = top break end
    if i % 120 == 0 then
      U.log(("%s: waiting for the battle, top %s (frame %d)"):format(role, topName(), U.frame()))
      if i == 240 then U.shot(game, DIR .. "/1c_waiting.png") end
    end
    U.wait(1)
  end
  check(battle and battle.coopBoss == "sudowoodo", "a co-op boss battle is up")
  if not battle then love.event.quit(1) return end
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    U.tap(game, "a"); U.wait(4)
  end
  check(battle.phase == "menu", "reached FIGHT / PKMN / PACK / RUN")
  local boss = battle:battlerAt(P.OPPONENT_LEFT)
  check(boss and battle:battlerAt(P.OPPONENT_RIGHT) == nil, "SUDOWOODO stands alone on its side")
  local max = boss and boss.mon.stats.hp or -1
  local plain = Pokemon.new(game.data, "SPECIES_185", 20)
  U.log(("%s: BOSS_MAX %d (a plain one about %d)"):format(role, max, plain.stats.hp))
  -- (its own DVs differ from this fresh one's: only roughly twice)
  check(max >= plain.stats.hp * 1.7, "about twice the HP of a plain one")
  U.shot(game, DIR .. "/2_menu.png")

  local shotAgain = false
  local okTurns, seen = 0, 0
  for turn = 1, 2 do
    local want = (battle.coop.turn or 1) + 1
    local moves0 = battle.coopBossMoves or 0
    for _ = 1, 60 * 40 do
      if battle.coop.turn >= want and (battle.phase == "menu" or battle.result) then break end
      if not shotAgain and (battle.coopBossMoves or 0) > moves0 then
        U.wait(50)
        U.shot(game, DIR .. "/3_moves_again.png")
        shotAgain = true
      end
      if game.stack:top() ~= battle and game.stack:top() ~= game.overworld then
        U.tap(game, "down"); U.wait(6); U.tap(game, "a")
      elseif battle.phase ~= "waitPartner" then U.tap(game, "a") end
      U.wait(3)
    end
    local b = battle:battlerAt(P.OPPONENT_LEFT)
    local mine = battle:battlerAt(P.PLAYER_LEFT)
    local ally = battle:battlerAt(P.PLAYER_RIGHT)
    U.log(("%s: FOE_HP turn %d boss %d mine %d ally %d second-moves %d"):format(role, turn,
      b and b.mon.hp or -1, mine and mine.mon.hp or -1, ally and ally.mon.hp or -1, battle.coopBossMoves or 0))
    if battle.result then break end   -- the host ran first (it is the faster copy)
    seen = seen + 1
    if (battle.coopBossMoves or 0) == moves0 + 1 then okTurns = okTurns + 1 end
  end
  check(seen >= 1 and okTurns == seen, ("SUDOWOODO moved a second time in %d of %d turns"):format(okTurns, seen))
  U.shot(game, DIR .. "/4_after_turns.png")

  -- no BALL against a boss together
  local ItemEffects = require("src.inventory.ItemEffects")
  local ballId = require("src.follow.FollowMon").itemByKey(game.data, "POKE_BALL")
  save.inventory[ballId] = 5
  check(ItemEffects.use(game.data, save, ballId, nil, battle) == "failed", "a BALL can't be thrown together")

  if role == "host" and not battle.result then
    for _ = 1, 60 * 20 do
      if battle.phase == "menu" then break end
      if game.stack:top() ~= battle then U.tap(game, "down"); U.wait(6); U.tap(game, "a")
      elseif battle.phase == "moveSelect" then U.tap(game, "b")
      elseif battle.phase ~= "waitPartner" then U.tap(game, "a") end
      U.wait(3)
    end
    battle:tryRun()
  end
  local back = false
  for _ = 1, 60 * 60 do
    if game.stack:top() == game.overworld then back = true break end
    if game.stack:top() == battle then U.tap(game, "a")
    elseif game.stack:top() ~= game.overworld then
      -- "Bring out which POKeMON?": the next one down that can fight
      U.tap(game, "down"); U.wait(6); U.tap(game, "a")
    end
    U.wait(3)
  end
  check(back, "both back on Route 29")
  U.shot(game, DIR .. "/5_back.png")
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
