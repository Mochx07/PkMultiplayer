-- LANCE, BOTH AT ONCE (review driver, two Gold copies).
--
--   pair.sh <mod> league_lance_both.lua <port> gold <host> <guest> <out>
--
-- Both players stand in KAREN's room with her beaten (its exit open), and at
-- the same second of the shared clock both walk up through the door into
-- LANCE's room: its entry scene plays on each (walked in, door shut behind),
-- and they keep walking up to LANCE -- each copy steps on one of the two
-- tiles in front of him (4,5 / 5,5), so both scripts start nearly at once.  Expected: one CO-OP question answered, exactly one invite, exactly
-- one battle -- a co-op double vs LANCE, played to the end on both -- and
-- both walked into the HALL OF FAME.  LANCE_SKEW=<frames> delays the guest.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7792")
  local skew = tonumber(os.getenv("LANCE_SKEW") or "0") or 0
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  U.wait(5)
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local Pokemon = require("src.pokemon.Pokemon")
  local CM = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local best
  for id, mv in pairs(game.data.moves or {}) do
    if mv.name == "PSYCHIC" then best = id break end
  end
  for _ = 1, 3 do
    local m = Pokemon.new(game.data, "SPECIES_150", 100)
    m.moves = { { id = best, pp = 40 } }
    table.insert(save.party, m)
  end
  -- what a player has after beating KAREN: her room's entrance shut behind
  -- them (783, scene 1), its exit to LANCE open (784), KAREN beaten (1467).
  -- LANCE's room is untouched: its entry scene plays as each walks in.
  local Flags = require("src.script.Flags")
  for _, n in ipairs({ 783, 784, 1467 }) do Flags.set(save, ("EVENT_G2_%04d"):format(n)) end
  save.g2Scenes = save.g2Scenes or {}
  save.g2Scenes.KARENS_ROOM = 1
  U.teleport(game, "KARENS_ROOM", role == "host" and 5 or 4, 5, "up")
  if role == "host" then CM.host(port) else U.wait(60) CM.join("127.0.0.1", port) end
  for _ = 1, 60 * 30 do
    if CM.isConnected() and CM.partner.map == "KARENS_ROOM" then break end
    U.wait(1)
  end
  check(CM.isConnected(), "linked in KAREN's room, by the open door")
  local ow = game.overworld
  local function pos()
    local p = ow and ow.player
    return p and (tostring(p.cellX) .. "," .. tostring(p.cellY)) or "?"
  end
  U.wait(60)
  U.log(role .. " in KARENS_ROOM at " .. pos() .. " LANCES_ROOM scene=" .. tostring(save.g2Scenes.LANCES_ROOM))
  U.shot(game, DIR .. "/0_karens_room_door.png")
  -- the same second on both machines' clock
  local go = os.time() + 3
  go = go + (5 - go % 5) % 5
  while os.time() < go do U.wait(1) end
  if skew > 0 and role == "guest" then U.wait(skew) end
  U.log(role .. " walking up at " .. os.time())

  local invites, menus, battles, coopBattles = 0, 0, 0, 0
  local lastMap, lastTop, lastInvite, lastMenu, lastBattle
  local sawSolo = false
  local endAt
  local t0 = love.timer.getTime()
  local walking = true
  local shotDoor, shotScene
  while love.timer.getTime() - t0 < 240 do
    local top = game.stack:top()
    ow = game.overworld
    local map = ow and ow.map and ow.map.id
    if map ~= lastMap then
      U.log(role .. " map " .. tostring(map) .. " at " .. pos() .. " t=" .. ("%.2f"):format(love.timer.getTime() - t0))
      lastMap = map
    end
    if map == "LANCES_ROOM" and shotScene and not shotDoor and top == ow and not (ow.runner and ow.runner.isRunning and ow.runner:isRunning()) then
      shotDoor = true
      U.log(role .. " LANCES_ROOM entry scene done at " .. pos() .. " scene=" .. tostring(save.g2Scenes.LANCES_ROOM))
      U.shot(game, DIR .. "/0b_lances_room_after_door.png")
    end
    if map == "LANCES_ROOM" and not shotScene and ow.runner and ow.runner.isRunning and ow.runner:isRunning() then
      shotScene = true
      U.shot(game, DIR .. "/0a_lances_room_entering.png")
    end
    if CM.activeInviteModal and CM.activeInviteModal ~= lastInvite then
      invites = invites + 1
      lastInvite = CM.activeInviteModal
      U.log(role .. " invite #" .. invites)
    end
    if top and top.header and type(top.header) == "string" and top.header:find("LANCE") and top ~= lastMenu then
      menus = menus + 1
      lastMenu = top
      U.log(role .. " asked: " .. top.header)
      U.shot(game, DIR .. "/1_ask_" .. menus .. ".png")
    end
    if top and top.chooseAction and top ~= lastBattle then
      battles = battles + 1
      lastBattle = top
      if top.coopDouble then coopBattles = coopBattles + 1 else sawSolo = true end
      U.log(role .. " battle #" .. battles .. (top.coopDouble and " (co-op double)" or " (SOLO)"))
      U.shot(game, DIR .. "/2_battle_" .. battles .. ".png")
    end
    if lastBattle and top ~= lastBattle and not lastBattle.loggedEnd and lastBattle.result then
      lastBattle.loggedEnd = true
      U.log(role .. " battle over: result=" .. tostring(lastBattle.result) .. " turn=" .. tostring(lastBattle.coop and lastBattle.coop.turn)
            .. " desyncs=" .. tostring(require("src.coop.CoopBattle").desyncs))
    end
    local name = top and (top.isCoopBattleSelect and "select" or top.isCoopInvite and "invite" or top.isCoopWaitModal and "wait"
                 or top == ow and "ow" or (top.coopDouble and "battle") or tostring(top.__name or top.name or top.kind or "?")) or "nil"
    if name ~= lastTop then lastTop = name U.log(role .. " top " .. name .. " @" .. tostring(map) .. " " .. pos()) end
    if walking and top == ow and (map == "KARENS_ROOM" or map == "LANCES_ROOM") then
      U.hold(game, "up", 4)
      local p = ow.player
      if map == "LANCES_ROOM" and p and p.cellY and p.cellY <= 5 then walking = false end
    elseif top and top.isCoopBattleSelect then
      U.tap(game, "start") U.wait(20)
    elseif top ~= ow then
      walking = false
      U.tap(game, "a") U.wait(6)
    else
      U.wait(6)
    end
    if map == "HALL_OF_FAME" and not endAt then endAt = love.timer.getTime() + 25 U.shot(game, DIR .. "/3_hof.png") end
    if endAt and love.timer.getTime() > endAt then break end
  end
  U.shot(game, DIR .. "/4_end.png")
  U.log(("%s totals: asked=%d invites=%d battles=%d coop=%d"):format(role, menus, invites, battles, coopBattles))
  check(battles == 1 and coopBattles == 1 and not sawSolo, "exactly one battle, the co-op double vs LANCE")
  check(menus + invites == 1, "one question for the pair: this side was " .. (menus == 1 and "asked CO-OP/SOLO" or invites == 1 and "invited" or "asked " .. menus .. " / invited " .. invites))
  check(lastBattle and lastBattle.result == "win", "the double went to the end (" .. tostring(lastBattle and lastBattle.result) .. ")")
  check(lastMap == "HALL_OF_FAME" or endAt ~= nil, "on to the HALL OF FAME (" .. tostring(lastMap) .. ")")
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
