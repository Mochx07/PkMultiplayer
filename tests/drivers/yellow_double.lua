-- YELLOW (Gen 1) between two real game instances, linked over 127.0.0.1.
--
--   pair.sh <mod> tests/drivers/yellow_double.lua 7820 yellow PkMp15A PkMpBigA <out>
--
-- Both stand in Pallet Town, link up and see each other; each screenshots the
-- co-op menu in English and in Spanish.  The host meets a wild Pokemon with
-- WILD TOGETHER on, the guest joins, and the two fight a co-op double with
-- Gen 1 moves (THUNDERSHOCK / WATER GUN on turn 1, HYPER BEAM / PSYBEAM on
-- turn 2); frames are captured every few ticks while the moves fly.  The guest
-- plays the battle with the mod in Spanish (text cuts).  After each turn both
-- copies log the foes' HP, which must agree.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7820")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local I18n = require("src.coop.CoopI18n")
  local data = game.data
  U.log(role .. ": gen2 anims? " .. tostring(data.battle_anims and data.battle_anims.gen2))
  local maps = data.maps or {}
  local MAP = maps.PALLET_TOWN and "PALLET_TOWN" or nil
  check(MAP ~= nil, "PALLET_TOWN exists in game.data.maps")
  if not MAP then
    local ks = {} for k in pairs(maps) do ks[#ks + 1] = k if #ks > 8 then break end end
    U.log("maps: " .. table.concat(ks, " "))
    love.event.quit(1) return
  end
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local function mon(id, lvl, moves)
    check(data.pokemon[id] ~= nil, "species " .. id)
    local m = Pokemon.new(data, id, lvl)
    m.moves = {}
    for _, mv in ipairs(moves) do
      check(data.moves[mv] ~= nil, "move " .. mv)
      m.moves[#m.moves + 1] = { id = mv, pp = 20 }
    end
    return m
  end
  if role == "host" then
    table.insert(save.party, mon("PIKACHU", 40, { "THUNDERSHOCK", "HYPER_BEAM" }))
    table.insert(save.party, mon("CHARMANDER", 20, { "EMBER" }))
  else
    table.insert(save.party, mon("SQUIRTLE", 40, { "WATER_GUN", "PSYBEAM" }))
    table.insert(save.party, mon("BULBASAUR", 20, { "VINE_WHIP" }))
  end
  U.teleport(game, MAP, role == "host" and 5 or 7, 8, "down")
  check(game.overworld ~= nil, "in the overworld")

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner and CoopManager.partner.map == MAP then
      linked = true break
    end
    U.wait(1)
  end
  check(linked, "linked, both in " .. MAP)
  local seen = false
  for _ = 1, 60 * 10 do
    for _, npc in ipairs(game.overworld.npcs or {}) do
      if npc.coopPartner then seen = true end
    end
    if seen then break end
    U.wait(1)
  end
  check(seen, "the partner stands in " .. MAP)
  U.wait(30)
  U.shot(game, DIR .. "/1_overworld.png")

  -- the co-op menu, English then Spanish
  local CoopMenu = require("src.coop.CoopMenu")
  I18n.forced = "en"
  game.stack:push(CoopMenu.new(game)); U.wait(10)
  U.shot(game, DIR .. "/2_coop_menu_en.png")
  U.tap(game, "b"); U.wait(10)
  I18n.forced = "es"
  game.stack:push(CoopMenu.new(game)); U.wait(10)
  U.shot(game, DIR .. "/3_coop_menu_es.png")
  U.tap(game, "b"); U.wait(10)
  while game.stack:top() ~= game.overworld and game.stack:top() do game.stack:pop() end
  I18n.forced = role == "guest" and "es" or "en"
  U.wait(60)

  local function topBattle()
    local top = game.stack:top()
    return top and top.coopDouble and top or nil
  end
  local BattleState = require("src.battle.BattleState")
  if role == "host" then
    CoopManager.setRule("wildTogether", true)
    U.wait(30)
    local ow = game.overworld
    local battle = BattleState.newWild(game, "SLOWPOKE", 22)
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
    U.wait(70)
    U.shot(game, DIR .. "/4_invite_es.png")
    U.tap(game, "a"); U.wait(30)
    U.shot(game, DIR .. "/4b_select_es.png")
    U.tap(game, "start"); U.wait(30)
  end

  local battle
  for _ = 1, 60 * 20 do
    battle = topBattle()
    if battle then break end
    U.wait(1)
  end
  check(battle and battle.coopWild, "a co-op wild double is up")
  if not battle then love.event.quit(1) return end
  local P = BattleState.POS

  local function toMenu(tag)
    for _ = 1, 400 do
      if battle.phase == "menu" then return true end
      if game.stack:top() ~= battle then return false end
      if battle.phase ~= "waitPartner" then U.tap(game, "a") end
      U.wait(4)
    end
    return battle.phase == "menu"
  end
  local function foeHp()
    local hp = {}
    for i, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local b = battle:battlerAt(pos)
      hp[i] = b and b.mon.hp or -1
    end
    return hp[1] .. " " .. hp[2]
  end

  check(toMenu(), "reached FIGHT / PKMN / PACK / RUN")
  U.shot(game, DIR .. "/5_menu.png")
  for turn = 1, 2 do
    local startTurn = battle.coop and battle.coop.turn or 0
    U.tap(game, "a"); U.wait(12)                 -- FIGHT
    if turn == 2 then U.tap(game, "down"); U.wait(8) end
    U.shot(game, DIR .. ("/6_t%d_moves.png"):format(turn))
    for _ = 1, 4 do U.tap(game, "a"); U.wait(10) end -- move, target, confirm
    -- capture the move animations mid-flight: every 3rd frame while the
    -- animation player is running, up to 30 frames per animation
    local per, lastAnim, total = {}, nil, 0
    for _ = 1, 60 * 40 do
      if game.stack:top() ~= battle then break end
      if battle.phase == "menu" and battle.coop and battle.coop.turn and battle.coop.turn > startTurn then break end
      local a, ap = battle.animName, battle.animPlayer
      local running = a and ap and ap.isDone and not ap:isDone()
      if running then
        if a ~= lastAnim then
          U.log(("%s: t%d anim %s attacker=%s target=%s"):format(role, turn, tostring(a),
            tostring(battle.animAttackerPos), tostring(battle.animTargetPos)))
          lastAnim = a
        end
        per[a] = (per[a] or 0) + 1
        if per[a] <= 30 and total < 90 then
          total = total + 1
          U.shot(game, DIR .. ("/7_t%d_%s_%02d.png"):format(turn, tostring(a), per[a]))
        end
        U.wait(2)
      else
        if a == nil or not running then lastAnim = running and lastAnim or nil end
        if battle.phase ~= "menu" and battle.phase ~= "waitPartner" then U.tap(game, "a") end
        U.wait(2)
      end
    end
    U.log(("%s: after turn %d FOE_HP %s phase=%s"):format(role, turn, foeHp(), tostring(battle.phase)))
    U.shot(game, DIR .. ("/8_t%d_after.png"):format(turn))
    if game.stack:top() ~= battle then break end
    if not toMenu() then break end
  end

  if role == "host" and game.stack:top() == battle then battle:tryRun() end
  local back = false
  for _ = 1, 60 * 20 do
    if game.stack:top() == game.overworld then back = true break end
    if game.stack:top() == battle then U.tap(game, "a") end
    U.wait(3)
  end
  check(back, "both back in " .. MAP)
  U.wait(60)
  U.shot(game, DIR .. "/9_back.png")
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
