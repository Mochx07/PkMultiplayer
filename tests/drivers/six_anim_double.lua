-- GEN 2 MOVE ANIMATIONS IN A CO-OP DOUBLE, frame by frame (review driver).
--
--   SIX_MOVES=HYPER_BEAM,AEROBLAST pair.sh <mod> six_anim_double.lua <port> gold <host> <guest> <out>
--
-- Wild Together on Route 29 (as wild_together.lua): the host's lead is a
-- LUGIA, the guest's a SNORLAX (SIX_HOST / SIX_GUEST override), the wild pair
-- two PIDGEY.  Every battler gets the same single move each round, and every
-- second frame of every animation is captured on both screens, named by the
-- attacker's and target's slots (0 = host/left player, 2 = right player,
-- 1 / 3 = the foes).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7810")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/six") .. "/" .. role
  local moves = {}
  for m in (os.getenv("SIX_MOVES") or "HYPER_BEAM"):gmatch("[^,]+") do moves[#moves + 1] = m end
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
  local BattleState = require("src.battle.BattleState")
  local save = U.freshSave(game)
  save.options = save.options or {}
  save.options.animations = true
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local lead = role == "host" and (os.getenv("SIX_HOST") or "SPECIES_249")
               or (os.getenv("SIX_GUEST") or "SPECIES_143")
  local m = Pokemon.new(game.data, lead, 60)
  m.moves = { { id = moves[1], pp = 30 } }
  if os.getenv("SIX_SHINY_" .. role:upper()) == "1" then Pokemon.forceShiny(game.data, m) end
  table.insert(save.party, m)
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

  local function topBattle()
    local top = game.stack:top()
    return top and top.coopDouble and top or nil
  end
  if role == "host" then
    CoopManager.setRule("wildTogether", true)
    U.wait(30)
    local ow = game.overworld
    local battle = BattleState.newWild(game, os.getenv("SIX_FOE") or "SPECIES_016", 40)
    battle.onFinish = function(r) ow:afterBattle(r, battle) end
    ow.pkmRandomEncounter = true
    ow:pushBattle(battle)
    ow.pkmRandomEncounter = nil
  else
    for _ = 1, 60 * 20 do
      if CoopManager.activeInviteModal then break end
      U.wait(1)
    end
    U.wait(70)
    U.tap(game, "a"); U.wait(30)
    U.tap(game, "start"); U.wait(30)
  end
  local battle
  for _ = 1, 60 * 20 do
    battle = topBattle()
    if battle then break end
    U.wait(1)
  end
  check(battle ~= nil, "a co-op wild double is up")
  if not battle then love.event.quit(1) return end
  local P = BattleState.POS
  local slots = { P.PLAYER_LEFT, P.OPPONENT_LEFT, P.PLAYER_RIGHT, P.OPPONENT_RIGHT }
  -- the same numbers on both copies, before the first turn is simulated
  for _, pos in ipairs(slots) do
    local b = battle:battlerAt(pos)
    if b then b.mon.stats.hp = 5000; b.mon.hp = 5000; b.shownHP = 5000 end
  end
  local function setMoves(id)
    for _, pos in ipairs(slots) do
      local b = battle:battlerAt(pos)
      if b then
        local ms = b.mon.moves
        for i = #ms, 1, -1 do ms[i] = nil end
        ms[1] = { id = id, pp = 30 }
      end
    end
  end

  for _, id in ipairs(moves) do
    setMoves(id)
    local count, n, last = 0, 0, nil
    local quiet = 0
    for _ = 1, 60 * 60 do
      if battle.animPlaying and battle.animName then
        local key = ("%s_a%s_t%s"):format(battle.animName, tostring(battle.animAttackerPos),
                                          tostring(battle.animTargetPos))
        if key ~= last then
          last = key; n = 0
          if battle.animName == id then count = count + 1 end
          local so = battle.animPlayer and battle.animPlayer.sideOffsets
          local function box(s) return s and ("to=(%.1f,%.1f) k=%.2f"):format(s.to[1], s.to[2], s.k or 1) or "nil" end
          U.log(("%s: anim %s #%d  player %s  enemy %s"):format(role, key, count,
                box(so and so.player), box(so and so.enemy)))
        end
        n = n + 1
        if n <= 40 then
          U.shot(game, ("%s/%s_%d_%02d.png"):format(DIR, key, count, n))
        else
          U.wait(1)
        end
        quiet = 0
      else
        if battle.phase ~= "waitPartner" and game.stack:top() == battle then U.tap(game, "a") end
        quiet = quiet + 1
        U.wait(3)
        if count >= 4 and quiet > 40 and (battle.phase == "menu") then break end
      end
      if game.stack:top() ~= battle then break end
    end
    check(count >= 1, ("%s played %d times"):format(id, count))
  end
  local hp = {}
  for i, pos in ipairs(slots) do local b = battle:battlerAt(pos); hp[i] = b and b.mon.hp or -1 end
  U.log(role .. ": HP " .. table.concat(hp, " "))
  if role == "host" then battle:tryRun() end
  for _ = 1, 60 * 10 do
    if game.stack:top() == game.overworld then break end
    if game.stack:top() == battle then U.tap(game, "a") end
    U.wait(3)
  end
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
