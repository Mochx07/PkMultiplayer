-- HYPER BEAM'S RECHARGE IN A REAL CO-OP DOUBLE, two Gold copies (review driver).
--
--   pair.sh <mod> hyper_beam_double.lua <port> gold <host> <guest> <out>
--
-- Wild Together on Route 29: the host's LUGIA and the guest's SNORLAX know
-- only HYPER BEAM, the two wild PIDGEY only HARDEN and have 5000 HP.  At the
-- start of every co-op turn each copy logs, in the same order on both (host's
-- Pokemon, guest's, foe 1, foe 2), every HP and who is locked into a
-- recharge; the two logs must match line for line.  Turns 1-6: beam,
-- recharge, beam...  Turn 7: the left foe is at 1 HP, so the beam knocks it
-- out -- in Gen 2 the turn after is still a recharge.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7790")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/hb") .. "/" .. role
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
  local m = Pokemon.new(game.data, role == "host" and "SPECIES_249" or "SPECIES_143", 60)
  m.moves = { { id = "HYPER_BEAM", pp = 30 } }
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
    local battle = BattleState.newWild(game, "SPECIES_016", 40)
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
  if os.getenv("HB_TRACE") == "1" then
    for _, fn in ipairs({ "say", "sayNext" }) do
      local orig = battle[fn]
      battle[fn] = function(self, t, ...) U.log(role .. " " .. fn .. ": " .. tostring(t):gsub("\n", " ")) return orig(self, t, ...) end
    end
    local mt = getmetatable(battle)
    setmetatable(battle, { __index = mt and mt.__index or mt, __newindex = function(t, k, v)
      if k == "result" then U.log(role .. " result=" .. tostring(v) .. " " .. debug.traceback()) end
      rawset(t, k, v)
    end })
  end
  -- host's Pokemon, guest's, foe 1, foe 2 -- the same order on both copies
  local order = role == "host" and { P.PLAYER_LEFT, P.PLAYER_RIGHT, P.OPPONENT_LEFT, P.OPPONENT_RIGHT }
                or { P.PLAYER_RIGHT, P.PLAYER_LEFT, P.OPPONENT_LEFT, P.OPPONENT_RIGHT }
  for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
    local b = battle:battlerAt(pos)
    if b then
      b.mon.stats.hp = 5000; b.mon.hp = 5000; b.shownHP = 5000
      -- (a WHIRLWIND would blow one of ours away and end the wild battle)
      b.mon.moves = { { id = "HARDEN", pp = 30 } }
      b.curMoves = { { id = "HARDEN", pp = 30 } }
    end
  end

  local seen, rows = {}, {}
  local lastTurn = 0
  local koSet = false
  local lastPh
  for _ = 1, 60 * 150 do
    if game.stack:top() ~= battle and not battle.coopDouble then break end
    local c = battle.coop
    local turn = c and c.turn or 0
    local ph = tostring(battle.phase) .. "/" .. tostring(battle.result) .. "/" .. tostring(game.stack:top() == battle)
    if ph ~= lastPh then U.log(role .. " phase " .. ph .. " turn " .. turn) lastPh = ph end
    local idle = (battle.phase == "menu" or battle.phase == "waitPartner")
    if idle and turn ~= lastTurn and not seen[turn] then
      seen[turn] = true
      lastTurn = turn
      if turn == 7 and not koSet then
        -- the same edit on both copies, before either chooses turn 7
        local foe = battle:battlerAt(P.OPPONENT_LEFT)
        if foe then foe.mon.hp = 1; foe.shownHP = 1 end
        koSet = true
      end
      local hp, rc = {}, {}
      for i, pos in ipairs(order) do
        local b = battle:battlerAt(pos)
        hp[i] = b and b.mon and b.mon.hp or -1
        rc[i] = (b and b.mustRecharge) and "R" or "-"
      end
      local row = ("turn %d HP %s recharge %s"):format(turn, table.concat(hp, " "), table.concat(rc))
      rows[turn] = { hp = hp, rc = rc }
      U.log(role .. ": " .. row)
      U.shot(game, ("%s/turn_%02d.png"):format(DIR, turn))
      if turn >= 9 then break end
    end
    if battle.phase ~= "waitPartner" and game.stack:top() == battle then U.tap(game, "a") end
    U.wait(3)
  end
  -- what the cartridge asks for, on this copy
  -- (a copy whose own Pokemon recharges while the partner's does too never
  -- stops at the menu that turn, so it has no row for it: the other copy does)
  local function rcOf(t, i) return rows[t] and rows[t].rc[i] == "R" end
  local function hit(t) return rows[t] and rows[t].rc[1] == "-" and rows[t].rc[2] == "-" end
  check(hit(1) and hit(3), "turns 1 and 3: both free to beam")
  check(rows[2] == nil or (rcOf(2, 1) and rcOf(2, 2)), "turn 2: both beam users must recharge")
  check(rows[3] and rows[1].hp[3] > rows[3].hp[3], "turn 2's recharge did no damage, turn 1's beams did")
  -- turn 7's beams knock foe 1 out; in Gen 2 whoever landed one recharges on
  -- turn 8 (no row at all: both recharge, neither copy stops at the menu)
  check(rows[7] and rows[9] and (rows[8] == nil or rcOf(8, 1) or rcOf(8, 2)),
        "turn 8: the beam that knocked out foe 1 still asks for a recharge (Gen 2)")
  check(rows[9] and rows[9].hp[3] <= 0, "turn 9: foe 1 is down")
  local f = io.open(DIR .. "/rows.txt", "w")
  if f then
    for t = 1, 9 do
      if rows[t] then f:write(("turn %d HP %s recharge %s\n"):format(t, table.concat(rows[t].hp, " "), table.concat(rows[t].rc))) end
    end
    f:close()
  end
  U.log(role .. " done: " .. fails .. " failures")
  if role == "host" then battle:tryRun() end
  for _ = 1, 60 * 10 do
    if game.stack:top() == game.overworld then break end
    if game.stack:top() == battle then U.tap(game, "a") end
    U.wait(3)
  end
  love.event.quit(fails == 0 and 0 or 1)
end
