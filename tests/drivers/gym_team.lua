-- A GYM LEADER WITH A TEAM FOR TWO (1.20 story.gyms), two copies.
--
--   pair.sh <mod> gym_team.lua <port> gold <host> <guest> <out>
--
-- Both stand in front of FALKNER in VIOLET GYM.  The host (MOCHI, three
-- MEWTWO at 60) talks to him, picks CO-OP, the guest (TOBY, three at 20)
-- accepts.  FALKNER (cartridge: PIDGEY 7, PIDGEOTTO 9) must come out with
-- four: two more of his type (HOOTHOOT, SPEAROW) before his ace, the whole
-- team a level above TOBY's 20 -- PIDGEY 21, HOOTHOOT 21, SPEAROW 21,
-- PIDGEOTTO 23 -- the same on both copies (the "team:" lines of the two
-- logs must match), and the double is won with no copy drifting.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7791")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  U.wait(5)
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local CM = require("src.coop.CoopManager")
  local CoopDuo = require("src.coop.CoopDuo")
  local Badges = require("src.inventory.Badges")
  local Pokemon = require("src.pokemon.Pokemon")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local best
  for id, mv in pairs(game.data.moves or {}) do
    if mv.name == "PSYCHIC" then best = id break end
  end
  for _ = 1, 3 do
    local m = Pokemon.new(game.data, "SPECIES_150", role == "host" and 60 or 20)
    m.moves = { { id = best, pp = 40 } }
    table.insert(save.party, m)
  end
  -- every line the engine fills in, so the handover / prize lines are on record
  local TextBox = require("src.render.TextBox")
  local sub = TextBox.substitute
  TextBox.substitute = function(g, text, ...)
    local out = sub(g, text, ...)
    if type(out) == "string" and (out:find("received", 1, true) or out:find(" got", 1, true)) then
      U.log(role .. " text: " .. out:gsub("\n", " / "):gsub("\f", " // "))
    end
    return out
  end
  -- what reaches this copy from the partner's scene, and whether it counts as lived here
  local CoopStory = require("src.coop.CoopStory")
  local onRewards = CoopStory.onPartnerRewards
  CoopStory.onPartnerRewards = function(g, msg)
    local kinds = {}
    for _, r in ipairs(msg.rewards or {}) do kinds[#kinds + 1] = r.kind .. ":" .. tostring(r.id or r.map or r.amount or "") end
    U.log(role .. " rewards in: " .. table.concat(kinds, ", ") .. " lived=" .. tostring(CoopStory.alreadyLived(g.save, msg.rewards or {}))
          .. " deferred=" .. tostring(msg.deferredAt ~= nil))
    local a, b = onRewards(g, msg)
    game.rewardsIn = true
    return a, b
  end
  U.teleport(game, "VIOLET_GYM", role == "host" and 5 or 4, 2, "up")
  if role == "host" then CM.host(port) else U.wait(60) CM.join("127.0.0.1", port) end
  for _ = 1, 60 * 30 do
    if CM.isConnected() and CM.partner.map == "VIOLET_GYM" then break end
    U.wait(1)
  end
  check(CM.isConnected(), "linked in VIOLET GYM")
  U.wait(90)
  check(CoopDuo.on(), "story.duo on for both")
  check(require("src.coop.CoopGyms").on(), "story.gyms on for both")
  U.shot(game, DIR .. "/0_gym.png")
  local go = os.time() + 2
  while os.time() < go do U.wait(1) end

  local ow = game.overworld
  local CoopBattle = require("src.coop.CoopBattle")
  local battle, lastTop, shotNew, shotIntro = nil, nil, false, false
  local seen = {}
  if role == "host" then
    for _ = 1, 10 do
      U.tap(game, "up") U.wait(10)
      U.tap(game, "a") U.wait(20)
      local o = game.overworld
      if (o.runner and o.runner:isRunning()) or game.stack:top() ~= o then break end
    end
  end
  local function nm(m) local d = game.data.pokemon[m.species] return (d and d.name or m.species) .. (m.level or "?") end
  local t0 = love.timer.getTime()
  local quietSince
  while love.timer.getTime() - t0 < 200 do
    local top = game.stack:top()
    ow = game.overworld
    local running = ow and ow.runner and ow.runner.isRunning and ow.runner:isRunning()
    if top and top.chooseAction and top ~= battle then
      battle = top
      local t = {}
      for _, m in ipairs(top.enemyParty or {}) do t[#t + 1] = nm(m) end
      U.log("team: " .. table.concat(t, " "))
      U.log(role .. " battle: coopDouble=" .. tostring(top.coopDouble) .. " gym=" .. tostring(top.coopGymTeam ~= nil))
      U.wait(20)
      U.shot(game, DIR .. "/1_intro.png")
    end
    if battle and top == battle then
      for _, pos in ipairs({ 1, 3 }) do
        local b = battle.battlerAt and battle:battlerAt(pos)
        if b and b.mon and not seen[b.mon] then
          seen[b.mon] = true
          local n = nm(b.mon)
          U.log(role .. " on the field: " .. n)
          if n:find("HOOTHOOT") or n:find("SPEAROW") then shotNew = shotNew or "due" end
        end
      end
    end
    if shotNew == "due" and top == battle and battle.phase == "menu" then
      shotNew = true
      U.wait(10)
      U.shot(game, DIR .. "/2_new_foe.png")
    end
    if battle and top == ow and not running and #CoopDuo.handovers == 0 then
      quietSince = quietSince or love.timer.getTime()
      if love.timer.getTime() - quietSince > 6 then break end
    else
      quietSince = nil
    end
    if top and top.isCoopBattleSelect then
      U.tap(game, "start") U.wait(20)
    elseif top ~= ow then
      U.tap(game, "a") U.wait(8)
    else
      U.wait(6)
    end
  end
  U.shot(game, DIR .. "/3_end.png")
  check(battle and battle.coopDouble, "the co-op double vs FALKNER")
  local t = {}
  for _, m in ipairs(battle and battle.enemyParty or {}) do t[#t + 1] = nm(m) end
  check(table.concat(t, " ") == "PIDGEY21 HOOTHOOT21 SPEAROW21 PIDGEOTTO23",
        "FALKNER brings four for two, a level above TOBY (" .. table.concat(t, " ") .. ")")
  check(shotNew == true, "a new one of his type came out (on screen: 2_new_foe.png)")
  check(battle and battle.result == "win", "won (" .. tostring(battle and battle.result) .. ")")
  check((CoopBattle.desyncs or 0) == 0, "the copies never drifted (" .. tostring(CoopBattle.desyncs) .. ")")
  check(Badges.has(save, { id = "ZEPHYRBADGE" }), save.player.name .. " holds the ZEPHYRBADGE")
  U.wait(60 * 3)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
