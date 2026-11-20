-- Gen 1 POKEMON LEAGUE FOR TWO (nightly.3, B2).  PKM_ROOM picks the room:
-- LORELEIS_ROOM, BRUNOS_ROOM, AGATHAS_ROOM (talk to them), LANCES_ROOM
-- (his coordinate trigger) or CHAMPIONS_ROOM (the rival walks in, then Oak
-- and the HALL OF FAME).  Both players are in the room; the host starts it,
-- picks CO-OP, the guest accepts, a 2v2; won quickly (the same HP change on
-- both copies before any turn), and both must come out with the room beaten
-- -- and, for the champion, both inducted into the Hall of Fame.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7910")
  local ROOM = os.getenv("PKM_ROOM") or "LORELEIS_ROOM"
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.player.rival = role == "host" and "GARY" or "BLUE"
  save.flags = save.flags or {}
  local f = save.flags
  f.EVENT_GOT_STARTER = true
  f[role == "host" and "EVENT_CHOSE_SQUIRTLE" or "EVENT_CHOSE_BULBASAUR"] = true
  for _, e in ipairs({ "LORELEIS_ROOM", "BRUNOS_ROOM", "AGATHAS_ROOM" }) do
    f["EVENT_AUTOWALKED_INTO_" .. e] = true
  end
  local order = { "LORELEIS_ROOM", "BRUNOS_ROOM", "AGATHAS_ROOM", "LANCES_ROOM", "CHAMPIONS_ROOM" }
  local BEAT = { LORELEIS_ROOM = "EVENT_BEAT_LORELEIS_ROOM_TRAINER_0", BRUNOS_ROOM = "EVENT_BEAT_BRUNOS_ROOM_TRAINER_0",
                 AGATHAS_ROOM = "EVENT_BEAT_AGATHAS_ROOM_TRAINER_0", LANCES_ROOM = "EVENT_BEAT_LANCE" }
  -- the rooms before this one are beaten (the doors behind are shut)
  for _, r in ipairs(order) do
    if r == ROOM then break end
    if BEAT[r] then f[BEAT[r]] = true end
  end
  if ROOM == "CHAMPIONS_ROOM" then f.EVENT_LANCES_ROOM_LOCK_DOOR = true end
  local team = role == "host" and { { "BLASTOISE", 58 }, { "PIDGEOT", 55 }, { "RAICHU", 54 } }
    or { { "VENUSAUR", 57 }, { "FEAROW", 54 } }
  for _, t in ipairs(team) do table.insert(save.party, Pokemon.new(game.data, t[1], t[2])) end
  local hofBefore = #(save.hallOfFame or {})

  local ow
  local function findNpc(test)
    for _, npc in ipairs(game.overworld.npcs or {}) do if test(npc.def or {}, npc) then return npc end end
  end
  -- where each one stands before the host sets it off
  if ROOM == "CHAMPIONS_ROOM" then
    -- first stand in Lance's room; the host walks in through the stairs
    U.teleport(game, "LANCES_ROOM", role == "host" and 5 or 6, 2, "up")
  elseif ROOM == "LANCES_ROOM" then
    U.teleport(game, ROOM, role == "host" and 5 or 6, role == "host" and 2 or 3, "up")
  else
    U.teleport(game, ROOM, 4, 6, "up")
    U.wait(20)
    local boss = findNpc(function(d) return d.trainerClass ~= nil end)
    check(boss ~= nil, "found " .. tostring(boss and boss.def.trainerClass) .. " in " .. ROOM)
    if boss then
      if role == "host" then U.teleport(game, ROOM, boss.cellX, boss.cellY + 1, "up")
      else U.teleport(game, ROOM, boss.cellX + 1, boss.cellY + 1, "up") end
    end
  end
  U.wait(30)
  if role == "host" then
    CoopManager.balancedFoes = true
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local startMap = ROOM == "CHAMPIONS_ROOM" and "LANCES_ROOM" or ROOM
  local linked = false
  for _ = 1, 60 * 40 do
    if CoopManager.isConnected() and CoopManager.partner.map == startMap then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both in " .. startMap)
  U.wait(90)

  -- set it off
  if role == "host" then
    if ROOM == "LANCES_ROOM" then U.hold(game, "up", 20)
    elseif ROOM == "CHAMPIONS_ROOM" then
      U.teleport(game, "CHAMPIONS_ROOM", 4, 7, "up")
    else U.tap(game, "a") end
  elseif ROOM == "CHAMPIONS_ROOM" then
    -- the guest follows into the champion's room a moment later
    U.wait(30)
    U.teleport(game, "CHAMPIONS_ROOM", 5, 7, "up")
  end

  local function topName()
    local t = game.stack:top()
    if not t then return "nil" end
    if t == game.overworld then return "overworld" end
    if t.isCoopInvite then return "invite" end
    if t.isCoopBattleSelect then return "select" end
    if t.phase then return "battle:" .. tostring(t.phase) .. (t.coopDouble and ":coop" or "") end
    return tostring(t.header or t.title or t)
  end
  local battle, last
  for i = 1, 60 * 90 do
    local name = topName()
    if name ~= last then U.log(role .. ": top " .. name) last = name end
    local t = game.stack:top()
    if t and t.phase and t.coopDouble then battle = t break end
    if role == "guest" and t and t.isCoopInvite and i % 30 == 0 then U.tap(game, "a") end
    if t and t.isCoopBattleSelect and i % 20 == 0 then U.tap(game, "start") end
    if t and t ~= game.overworld and not t.phase and not t.isCoopBattleSelect and not t.isCoopInvite and i % 30 == 0 then U.tap(game, "a") end
    if t and t.phase and not t.coopDouble and i > 60 * 60 then break end
    U.wait(1)
  end
  check(battle ~= nil, "a co-op 2v2 is up in " .. ROOM)
  if not battle then
    U.shot(game, DIR .. "/no_coop.png")
  else
    U.wait(40)
    U.shot(game, DIR .. "/1_battle.png")
    local names = {}
    for _, m in ipairs(battle.enemyParty or {}) do
      local def = game.data.pokemon[m.species]
      names[#names + 1] = tostring(def and def.name or m.species) .. ":" .. tostring(m.level)
    end
    U.log(("%s: %s / %s brings %s%s"):format(role, tostring(battle.oppClass), tostring(battle.trainerB and battle.trainerB.name),
      table.concat(names, " "), battle.enemyPartyB and (" + " .. #battle.enemyPartyB) or ""))
    for _, list in ipairs({ battle.enemyParty or {}, battle.enemyPartyB or {} }) do
      for _, m in ipairs(list) do m.hp = 1 end
    end
    local P = require("src.battle.BattleState").POS
    for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local b = battle:battlerAt(pos)
      if b and b.mon then b.mon.hp = 1 end
    end
    -- through the battle and whatever follows (Oak, the Hall of Fame, the
    -- credits) until the overworld is back
    local back = false
    for i = 1, 60 * 600 do
      local t = game.stack:top()
      if t == game.overworld and i > 60 * 5 and not (game.overworld.runner and game.overworld.runner:isRunning()) then
        back = true
        break
      end
      if i % 12 == 0 then U.tap(game, "a") end
      U.wait(1)
    end
    check(back, "back in the overworld after it")
    U.wait(60)
    U.shot(game, DIR .. "/2_after.png")
    local here = game.overworld and game.overworld.map and game.overworld.map.id
    U.log(role .. ": now in " .. tostring(here))
    if BEAT[ROOM] then
      check(f[BEAT[ROOM]] == true, "this player has " .. BEAT[ROOM])
    else
      check(#(save.hallOfFame or {}) > hofBefore, "this player is in the Hall of Fame ("
            .. hofBefore .. " -> " .. #(save.hallOfFame or {}) .. ")")
    end
  end
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
