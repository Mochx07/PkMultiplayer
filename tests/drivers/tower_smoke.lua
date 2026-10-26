-- THE BATTLE TOWER IN MULTI (Crystal), two real instances.
--
--   PKM_ROLE=host|guest PKM_PORT=7802 SHOT_DIR=/tmp/pkm \
--   POKEPORT_VERSION=crystal POKEPORT_IDENTITY=<copy> \
--   POKEPORT_DRIVER=<mod>/tests/drivers/tower_smoke.lua love .
--
-- The host stands in the battle room (any map does here) with a rolled L20
-- opponent and picks CO-OP DOUBLE; the guest, on ANOTHER map, is asked, may
-- only bring Pokemon at or under L20, fights the same opponent, and gets its
-- team back as it went in.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7802")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function waitReal(sec, cond)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < sec do
      if cond and cond() then return true end
      U.wait(1)
    end
    return cond and cond() or false
  end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local team = role == "host" and { { 157, 20 }, { 160, 20 } } or { { 249, 50 }, { 154, 20 }, { 181, 18 } }
  for _, t in ipairs(team) do
    table.insert(save.party, Pokemon.new(game.data, ("SPECIES_%03d"):format(t[1]), t[2]))
  end
  U.teleport(game, role == "host" and "ROUTE29" or "NEW_BARK_TOWN", role == "host" and 10 or 6, 8, "down")

  if role == "host" then
    check(CoopManager.host(port), "hosting")
  else
    waitReal(1.5)
    check(CoopManager.join("127.0.0.1", port), "joining")
  end
  check(waitReal(20, function() return CoopManager.isConnected() and CoopManager.partner.map ~= nil end), "linked")
  waitReal(2)

  local function coopBattle()
    local top = game.stack:top()
    return top and top.coopDouble and top or nil
  end

  local before
  if role == "host" then
    local BattleTower = require("src.world.BattleTower")
    local BattleState = require("src.battle.BattleState")
    local s = BattleTower.state(save)
    s.group = 2
    local opp = BattleTower.rollOpponent(game)
    check(opp and #opp.party >= 1, "an opponent was rolled: " .. tostring(opp and opp.name))
    local battle = BattleState.newBattleTowerTrainer(game, opp)
    battle.canLose = true
    battle.onFinish = function(r) U.log("host: tower battle result " .. tostring(r)) end
    game.overworld:pushBattle(battle)
    waitReal(1)
    U.shot(game, DIR .. "/1_offer.png")
    U.tap(game, "a"); waitReal(0.5)   -- CO-OP DOUBLE
    U.tap(game, "start"); waitReal(0.5) -- the team
  else
    check(waitReal(20, function() return CoopManager.activeInviteModal ~= nil end), "asked on another map")
    -- A counts once the invite has been up 0.8 s (CoopBattleInviteModal.ARM_TIME)
    waitReal(1.0)
    U.tap(game, "a"); waitReal(0.6)
    local sel = game.stack:top()
    local over = false
    for _, m in ipairs(sel and sel.party or {}) do if (m.level or 0) > 20 then over = true end end
    check(sel and sel.isCoopBattleSelect and not over and #sel.party == 2, "only Pokemon at or under L20 may enter")
    U.shot(game, DIR .. "/1_select.png")
    before = {}
    for i, m in ipairs(save.party) do before[i] = m.hp end
    U.tap(game, "start")
  end

  local battle
  check(waitReal(20, function() battle = coopBattle() return battle ~= nil end), "a co-op tower double is up")
  if battle then
    check(battle.battleTower == true, "against the tower trainer: " .. tostring(battle.enemy and battle.enemy.name))
    waitReal(2)
    U.shot(game, DIR .. "/2_battle.png")
    local P = require("src.battle.BattleState").POS
    local e1 = battle:battlerAt(P.OPPONENT_LEFT)
    U.log(role .. ": FOE " .. tostring(e1 and e1.mon.species) .. " L" .. tostring(e1 and e1.mon.level))
    -- fight it out
    local function onStack()
      for _, st in ipairs(game.stack.states) do if st == battle then return true end end
      return false
    end
    local lastLog = love.timer.getTime()
    waitReal(120, function()
      if not onStack() then return true end
      -- two turns are enough to compare; the host then calls it a win, which
      -- reaches the guest as the battle's end
      if role == "host" and battle.coop and (battle.coop.turn or 0) >= 2 and not battle.coop.finished then
        require("src.coop.CoopBattle").forceFinishBattle(battle, "win")
      end
      if love.timer.getTime() - lastLog > 8 then
        lastLog = love.timer.getTime()
        local top = game.stack:top()
        U.log(("%s: phase %s top %s turn %s"):format(role, tostring(battle.phase),
          top == battle and "battle" or tostring(top and (top.isCoopBattleSelect and "select" or top.phase or top.text or top)),
          tostring(battle.coop and battle.coop.turn)))
      end
      local top = game.stack:top()
      if top == battle and battle.phase ~= "waitPartner" then U.tap(game, "a") end
      if top ~= battle and top and top.isCoopBattleSelect == nil then U.tap(game, "a") end
      return false
    end)
    U.shot(game, DIR .. "/3_end.png")
    check(not onStack(), "the battle ended")
  end
  if role == "guest" and before then
    waitReal(2)
    local same = true
    for i, m in ipairs(save.party) do
      U.log(("guest: mon %d %s hp %s -> %s"):format(i, m.species, tostring(before[i]), tostring(m.hp)))
      if m.hp ~= before[i] then same = false end
    end
    check(same, "the guest's team came back as it went in")
  end
  waitReal(3)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
