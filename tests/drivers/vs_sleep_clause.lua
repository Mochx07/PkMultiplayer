-- THE SLEEP CLAUSE IN A REAL LEVEL 50 BATTLE, two Gold copies (1.20).
--
--   pair.sh <mod> vs_sleep_clause.lua <port> gold <host> <guest> <out>
--
-- The host's PARASECT uses SPORE on turns 1 and 2 and SLASH after that; the
-- guest's PIDGEY (faster, so it does not tick its sleep on turn 1) attacks on
-- turn 1 and the guest switches to SENTRET on turn 2.  So the second SPORE
-- meets a different foe while PIDGEY sleeps: it must fail with the clause's
-- line on BOTH copies, SENTRET must stay awake, and the battle is played to
-- the end.  Each copy logs every battle line and every turn's HP/status of
-- both teams, then plays its own replay: the replay must stop the same SPORE
-- and end exactly like the battle.  Screenshots of the clause's line in the
-- battle and in the replay go to <out>/<role>/.
--
-- VS_FORMAT=free (exported before pair.sh) plays the same as a FREE BATTLE,
-- where nothing may change: the second SPORE lands and SENTRET sleeps too.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7830")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/vss") .. "/" .. role
  local fmtId = os.getenv("VS_FORMAT") or "lv50"
  local free = fmtId == "free"
  -- VS_GUEST_LANG=es: the guest reads the battle in Spanish (the line is text
  -- only, so the two copies may differ in language and still agree)
  if role == "guest" and os.getenv("VS_GUEST_LANG") then
    require("src.coop.CoopI18n").forced = os.getenv("VS_GUEST_LANG")
  end
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
  local CoopLink = require("src.coop.CoopLink")
  local CoopVS = require("src.coop.CoopVS")
  local CoopReplay = require("src.coop.CoopReplay")
  local CoopSleepClause = require("src.coop.CoopSleepClause")
  local save = U.freshSave(game)
  save.options = save.options or {}
  save.options.animations = false
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local moves = game.data.moves
  check(moves.SPORE and moves.SPORE.effect == "SLEEP_EFFECT" and moves.SLASH ~= nil,
        "SPORE is a sleep move in this game (" .. tostring(moves.SPORE and moves.SPORE.effect) .. ")")
  if role == "host" then
    local p = Pokemon.new(game.data, "SPECIES_047", 40)
    p.moves = { { id = "SPORE", pp = moves.SPORE.pp }, { id = "SLASH", pp = moves.SLASH.pp } }
    table.insert(save.party, p)
  else
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_016", 10))
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_161", 12))
  end
  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")
  local replaysBefore = #CoopReplay.list()

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
  check(CoopManager.bothHave(CoopSleepClause.CAP), "both copies have the sleep clause (" .. CoopSleepClause.CAP .. ")")
  if role == "host" then
    check(CoopLink.invite(game, "battle", CoopVS.FORMATS[fmtId]), fmtId .. " invite sent")
  else
    for _ = 1, 60 * 20 do if CoopLink.asked then break end U.wait(1) end
    U.wait(70)
    U.tap(game, "a")
  end

  -- the host's team, then the guest's, the same order on every copy
  local function sides(b)
    if b.spectating or role == "host" then return b.playerParty, b.enemyParty end
    return b.enemyParty, b.playerParty
  end
  local function team(p)
    local o = {}
    for _, m in ipairs(p or {}) do o[#o + 1] = ("%s %d/%d %s"):format(m.species, m.hp, m.stats.hp, tostring(m.status or "-")) end
    return table.concat(o, ", ")
  end
  local function ending(b)
    local h, g = sides(b)
    return team(h) .. " | " .. team(g)
  end

  local function playOut(label, match, frames, steer)
    local b
    for _ = 1, 60 * 40 do
      local top = game.stack:top()
      if top and match(top) then b = top break end
      -- a FREE BATTLE's asker picks the level rule in the Cable Club's menu
      if top and top.stage == "battleOptions" then U.tap(game, "a") U.wait(10) end
      U.wait(1)
    end
    if not b then return nil end
    local last, lastText, shotN = nil, nil, 0
    -- each turn's HP/status, taken as its end-of-turn step finishes (the
    -- replay rushes through its turns, so sampling the screen misses some)
    local turnStates = {}
    local endOfTurn = b.endOfTurn
    b.endOfTurn = function(s, ...)
      local r1, r2 = endOfTurn(s, ...)
      local turn = s.turnCount or 0
      turnStates[turn] = ending(s)
      U.log(("%s %s after turn %d: %s"):format(role, label, turn, turnStates[turn]))
      return r1, r2
    end
    for _ = 1, frames do
      local top = game.stack:top()
      if top == b then last = ending(b) end
      if top == game.overworld then break end
      -- every line the battle shows, once
      local text = b.current and b.current.text
      if text and text ~= lastText then
        lastText = text
        U.log(("%s %s line: %s"):format(role, label, (text:gsub("\n", " "))))
      end
      -- the clause's line, once it is fully on screen
      if text and (text:find("SLEEP CLAUSE", 1, true) or text:find("CLAUSULA", 1, true)
                   or text:find("CLÁUSULA", 1, true)) and shotN < 1
         and (b.charIndex or 0) >= (b.total or 0) then
        shotN = shotN + 1
        U.wait(10)
        U.shot(game, DIR .. "/" .. label .. "_clause.png")
      end
      if top == b and steer and steer(b) then
        -- steered
      elseif top == b and b.phase == "moveSelect" then U.tap(game, "a") U.wait(4)
      elseif top == b or (top and top ~= game.overworld) then U.tap(game, "a") U.wait(6)
      else U.wait(1) end
    end
    return b, last, turnStates
  end

  -- host: SPORE on turns 1-2, SLASH after; guest: attack, then SENTRET on turn 2
  local switched = false
  local function steer(b)
    local turn = (b.turnCount or 0) + 1
    if role == "guest" and turn == 2 and not switched and b.phase == "menu" then
      U.wait(10)
      switched = true
      b:resolveSwitch(b.playerParty[2])
      U.log(role .. ": switching to " .. tostring(b.playerParty[2].species) .. " on turn 2")
      U.wait(4)
      return true
    end
    if role == "host" and b.phase == "moveSelect" then
      b.moveIndex = turn <= 2 and 1 or 2
      U.tap(game, "a")
      U.wait(4)
      return true
    end
    return false
  end

  local live, liveEnd, liveTurns = playOut("battle", function(t) return t.kind == "link" and not t.spectating end,
                                           60 * 150, steer)
  check(live ~= nil, "the link battle opened")
  if live then
    U.log(role .. ": battle ended '" .. tostring(liveEnd) .. "' result " .. tostring(live.result))
    local t2 = liveTurns[2] or ""
    if free then
      check(live.coopSleepClause == nil, "a FREE BATTLE is not under the sleep clause")
      check(t2:find("SPECIES_161 %d+/%d+ SLP"), "after turn 2 SENTRET sleeps too, as before 1.20: " .. t2)
    else
      check(live.coopSleepClause ~= nil, "the LEVEL 50 battle is under the sleep clause")
      local blocked = live.coopSleepClause and live.coopSleepClause.blocked
      check(blocked == 1, "exactly one sleep was stopped (" .. tostring(blocked) .. ")")
      check(t2:find("SPECIES_016 %d+/%d+ SLP") and t2:find("SPECIES_161 %d+/%d+ %-"),
            "after turn 2 PIDGEY sleeps and SENTRET is awake: " .. t2)
    end
    check(game.stack:top() == game.overworld, "back in the overworld after the battle")
  end
  U.wait(60)
  local names = CoopReplay.list()
  check(#names == replaysBefore + 1, "the battle left a replay")
  local replay = names[1] and CoopReplay.load(names[1])
  if free then
    check(replay and replay.format == nil and replay.sleepClause == nil, "the replay is a free battle, no clause")
  else
    check(replay and replay.format == "lv50" and replay.sleepClause == true,
          "the replay is LEVEL 50 and notes the sleep clause")
  end

  if replay then
    check(CoopReplay.play(game, names[1]), "the replay starts")
    local spec, specEnd, specTurns = playOut("replay", function(t) return t.spectating end, 60 * 150)
    check(spec ~= nil and (spec.coopSleepClause ~= nil) == not free, "the replay's spectator plays the same rules")
    if spec then
      if not free then
        check(spec.coopSleepClause and spec.coopSleepClause.blocked == 1, "the replay stops the same sleep")
      end
      local same = true
      for turn, state in pairs(liveTurns or {}) do
        if specTurns[turn] ~= state then same = false end
      end
      check(same and specTurns[2] ~= nil, "the replay matches the battle after every turn")
    end
    U.log(role .. ": replay ended '" .. tostring(specEnd) .. "'")
    check(specEnd == liveEnd, "the replay ends exactly like the battle did")
    check(game.stack:top() == game.overworld, "back in the overworld after the replay")
  end
  U.log(role .. " done: " .. fails .. " failures")
  U.wait(30)
  love.event.quit(fails == 0 and 0 or 1)
end
