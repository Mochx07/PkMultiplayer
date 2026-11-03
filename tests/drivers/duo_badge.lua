-- A BADGE WON TOGETHER, HANDED TO EACH PLAYER (1.20 story.duo), two Gold
-- copies.
--
--   pair.sh <mod> duo_badge.lua <port> gold <host> <guest> <out>
--
-- Both stand in front of FALKNER in VIOLET GYM.  The host (MOCHI) talks to
-- him, picks CO-OP, the guest (TOBY) accepts the invite, and the two win the
-- double.  Then each screen hands the ZEPHYRBADGE to its own player by name:
--   * MOCHI's screen: Falkner's own line, "MOCHI received ZEPHYRBADGE."
--     (not "MOCHI & TOBY"), and later "TOBY got one too!";
--   * TOBY's screen: a box "TOBY received ZEPHYRBADGE." with the badge
--     fanfare, then the TM the scene handed over, "TOBY received TM31!".
-- Every text the engine fills in is logged (substitute), so the prize money
-- line of each battle shows whose name it carries.
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
    local m = Pokemon.new(game.data, "SPECIES_150", 100)
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
  U.shot(game, DIR .. "/0_gym.png")
  local go = os.time() + 2
  while os.time() < go do U.wait(1) end

  local ow = game.overworld
  local battles, lastBattle, shotBadge, gifts, lastGift = 0, nil, false, 0, nil
  local gotLine
  if role == "host" then
    -- face FALKNER and talk, until his scene starts
    for _ = 1, 10 do
      U.tap(game, "up") U.wait(10)
      U.tap(game, "a") U.wait(20)
      local o = game.overworld
      if (o.runner and o.runner:isRunning()) or game.stack:top() ~= o then break end
    end
    U.log("host talking to FALKNER: top=" .. tostring(game.stack:top() ~= game.overworld))
  end
  local t0 = love.timer.getTime()
  local quietSince
  while love.timer.getTime() - t0 < 200 do
    local top = game.stack:top()
    ow = game.overworld
    local running = ow and ow.runner and ow.runner.isRunning and ow.runner:isRunning()
    if top and top.chooseAction and top ~= lastBattle then
      battles = battles + 1
      lastBattle = top
      U.log(role .. " battle #" .. battles .. (top.coopDouble and " (co-op double)" or " (SOLO)"))
      U.wait(30)
      U.shot(game, DIR .. "/1_battle.png")
    end
    if top and top.isTextBox then
      local p = top.pages and top.pages[top.pageIndex or 1]
      local txt = p and table.concat(p, " / ") or ""
      if top.coopGift and top ~= lastGift then
        lastGift = top
        gifts = gifts + 1
        U.wait(70)
        U.log(role .. " gift box " .. gifts .. ": " .. txt)
        U.shot(game, DIR .. ("/3_gift_%d.png"):format(gifts))
      elseif not shotBadge and txt:find("ZEPHYRBADGE", 1, true) then
        shotBadge = true
        U.wait(60)
        U.log(role .. " badge page: " .. txt)
        U.shot(game, DIR .. "/2_badge_page.png")
      end
    end
    local s = CM.statusMessage
    if s and s:find("too!", 1, true) and s ~= gotLine then
      gotLine = s
      U.log(role .. " status: " .. s)
      U.wait(10)
      U.shot(game, DIR .. "/4_partner_got.png")
    end
    -- done: the battle is over, the scene is over, no box waiting
    local CoopStory = require("src.coop.CoopStory")
    if lastBattle and top == ow and not running and #CoopDuo.handovers == 0 and #CoopStory.deferred == 0 then
      quietSince = quietSince or love.timer.getTime()
      -- the guest waits for the host's scene to end (its rewards) as well
      if love.timer.getTime() - quietSince > 8 and (role == "host" or game.rewardsIn) then break end
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
  U.shot(game, DIR .. "/5_end.png")
  local tm
  for id, def in pairs(game.data.items) do if def.name == "TM31" then tm = id end end
  U.log(("%s TM31 (%s) in bag: %s; deferred %d, waiting boxes %d"):format(role, tostring(tm),
        tostring(save.inventory[tm]), #require("src.coop.CoopStory").deferred, #CoopDuo.handovers))
  check(tm and (save.inventory[tm] or 0) >= 1, save.player.name .. " has TM31")
  if role == "guest" then check(gifts >= 2, "the TM was handed to TOBY in a box too (" .. gifts .. " box(es))") end
  check(battles == 1 and lastBattle and lastBattle.coopDouble, "one battle, the co-op double vs FALKNER")
  check(lastBattle and lastBattle.result == "win", "won (" .. tostring(lastBattle and lastBattle.result) .. ")")
  check(Badges.has(save, { id = "ZEPHYRBADGE" }), save.player.name .. " holds the ZEPHYRBADGE")
  if role == "host" then
    check(shotBadge, "FALKNER's badge line came up on MOCHI's screen")
    check(gotLine == "TOBY got one too!" or gotLine == "TOBY got them too!",
          "MOCHI's screen reads that TOBY got it too (" .. tostring(gotLine) .. ")")
  else
    check(gifts >= 1, "the badge was handed to TOBY in a box of their own (" .. gifts .. " box(es))")
  end
  U.wait(60 * 4)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
