-- A CO-OP DOUBLE WITH ONE TEAM FAR BEHIND.  Host: three at level 40.  Guest:
-- three at level 10.  The host meets a trainer on Route 29 (FALKNER's team,
-- PIDGEY 7 / PIDGEOTTO 9) and asks the guest along.  Both copies must build
-- the same foe:
--   * without the catch-up rule the pair's average (25) is far over the
--     foe's 8 and the foe goes up two levels -- against the guest's tens;
--   * with it (both copies have story.catchup) it is levelled against the
--     weaker team: one level.
-- Then both foes are put at 1 HP on both copies and knocked out on turn 1:
-- the guest's Pokemon are paid boosted EXP ("gained a boosted"), the host's
-- the usual, and the two copies never disagree (CoopBattle.desyncs).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7817")
  local ROOT = os.getenv("SHOT_DIR") or "/tmp/pkm"
  local DIR = ROOT .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CM = require("src.coop.CoopManager")
  local BattleState = require("src.battle.BattleState")
  local CoopBattle = require("src.coop.CoopBattle")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local level = role == "host" and 40 or 10
  for _, n in ipairs(role == "host" and { 157, 18, 65 } or { 158, 161, 163 }) do
    local m = Pokemon.new(game.data, ("SPECIES_%03d"):format(n), level)
    m.moves = { { id = "TACKLE", pp = 35 } }
    table.insert(save.party, m)
  end
  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")
  if role == "host" then
    check(CM.host(port), "hosting")
  else
    U.wait(60)
    check(CM.join("127.0.0.1", port), "joined")
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CM.isConnected() and CM.partner.map == "ROUTE29" and CM.partner.caps then linked = true break end
    U.wait(1)
  end
  check(linked, "linked on Route 29")
  U.log(role .. " both have story.catchup: " .. tostring(CM.bothHave("story.catchup")))
  U.wait(90)
  local texts = {}
  if role == "host" then
    local ow = game.overworld
    local battle = BattleState.newTrainer(game, "OPP_LEADER", 1)
    battle.onFinish = function(r) ow:afterBattle(r, battle) end
    ow:pushBattle(battle)
    U.wait(20)
    U.tap(game, "a")       -- BATTLE MODE: CO-OP DOUBLE
    U.wait(30)
    U.tap(game, "start")   -- the first three
    U.wait(20)
  else
    for _ = 1, 60 * 30 do
      if CM.activeInviteModal then break end
      U.wait(1)
    end
    check(CM.activeInviteModal ~= nil, "invited")
    U.wait(70)
    U.tap(game, "a") U.wait(30)
    U.tap(game, "start") U.wait(30)
  end
  local battle
  for _ = 1, 60 * 30 do
    local t = game.stack:top()
    if t and t.coopDouble then battle = t break end
    U.wait(1)
  end
  check(battle ~= nil, "the co-op double is up")
  if not battle then love.event.quit(1) return end
  for _, fn in ipairs({ "say", "sayNext" }) do
    local orig = battle[fn]
    battle[fn] = function(self, t, ...)
      texts[#texts + 1] = tostring(t)
      return orig(self, t, ...)
    end
  end
  local levels = {}
  for i, m in ipairs(battle.enemyParty or {}) do levels[i] = m.level end
  U.log(role .. " foe team: " .. #levels .. " at " .. table.concat(levels, "/") ..
        " plan " .. tostring(battle.coopBalanced and (battle.coopBalanced.foes .. " +" .. battle.coopBalanced.boost)))
  local f = io.open(DIR .. "/foe.txt", "w")
  if f then f:write(table.concat(levels, "/") .. "\n") f:close() end
  check(battle.coopBalanced and battle.coopBalanced.boost == 1,
        "the foe is levelled against the weaker team: +1 (not the pair's +2)")
  check((role == "guest") == (battle.coopCatchUpExp == true), "boosted EXP on the guest's copy only")
  local P = BattleState.POS
  local mineBefore = {}
  for i, m in ipairs(save.party) do mineBefore[i] = m.exp end
  local turned = false
  for _ = 1, 60 * 90 do
    if game.stack:top() ~= battle then break end
    local c = battle.coop
    local turn = c and c.turn or 0
    if (battle.phase == "menu") and not turned then
      -- the same edit on both copies before either chooses turn 1
      for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
        local b = battle:battlerAt(pos)
        if b then b.mon.hp = 1 b.shownHP = 1 end
      end
      for _, m in ipairs(battle.enemyParty) do m.hp = 1 end
      turned = true
      U.shot(game, DIR .. "/1_menu.png")
    end
    if battle.phase ~= "waitPartner" and game.stack:top() == battle then U.tap(game, "a") end
    U.wait(3)
    if turned and turn >= 3 then break end
  end
  U.shot(game, DIR .. "/2_end.png")
  local boosted = false
  for _, t in ipairs(texts) do if t:find("boosted") then boosted = true end end
  U.log(role .. " texts: " .. table.concat(texts, " || "):gsub("\n", " "):sub(1, 600))
  if role == "guest" then
    check(boosted, "the guest's Pokemon gained boosted EXP")
  else
    check(not boosted, "the host's Pokemon gained the usual EXP")
  end
  local gained = false
  for i, m in ipairs(save.party) do if (m.exp or 0) > (mineBefore[i] or 0) then gained = true end end
  check(gained, "EXP was paid on this copy")
  for _, m in ipairs(save.party) do
    check(not m.traded, "no Pokemon left marked as traded")
    break
  end
  check((CoopBattle.desyncs or 0) == 0, "the two copies never disagreed (desyncs " .. tostring(CoopBattle.desyncs) .. ")")
  U.wait(60)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
