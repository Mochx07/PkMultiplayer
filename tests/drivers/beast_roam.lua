-- THE ROAMING BEASTS IN CO-OP between two real game instances, linked over
-- 127.0.0.1 (src/coop/CoopBoss.lua, capability "story.bosses").
--
--   pair.sh <mod> tests/drivers/beast_roam.lua <port> gold <idA> <idB> <out>
--
-- Both have the beasts loose (the Burned Tower's InitRoamMons), each in its
-- own save: the host's RAIKOU on Route 29, the guest's ENTEI on Route 30.
--   1. SIGHTING: each opens the POKEGEAR's MAP card and sees the partner's
--      beasts beside its own (CoopBoss.partnerBeasts; screenshots).
--   2. ENCOUNTER: the host's RAIKOU steps out on Route 29 with the guest on
--      the map and TEAM UP WILD on; the guest is asked in.  RAIKOU stands
--      alone, does not run at the end of the turn, no BALL; after two turns
--      the host runs.  The HP it was left with is in the host's save, still
--      roaming; the guest's own beasts are as they were.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7831")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopBoss = require("src.coop.CoopBoss")
  local BattleState = require("src.battle.BattleState")
  local P = BattleState.POS
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local team = role == "host" and { 155, 16, 19 } or { 158, 161, 21 }
  for _, n in ipairs(team) do
    local m = Pokemon.new(game.data, ("SPECIES_%03d"):format(n), 30)
    m.moves = { { id = "TACKLE", pp = 35 } }
    table.insert(save.party, m)
  end
  save.flags = save.flags or {}
  save.flags.EVENT_GOT_MAP_CARD = true
  -- the Burned Tower's release, then each moves its own beast
  require("src.script.Gen2Commands").g2_init_roam_mons({ save = save, game = game })
  local mine = role == "host" and "RAIKOU" or "ENTEI"
  local where = role == "host" and "ROUTE29" or "ROUTE30"
  local lm = game.data.maps[where] and tonumber(game.data.maps[where].landmark)
  save.g2Roam[mine].mapId, save.g2Roam[mine].landmark = where, lm
  U.log(("%s: my %s on %s (landmark %s); beasts %s"):format(role, mine, where, tostring(lm),
        table.concat((function() local t = {} for k in pairs(save.g2Roam) do t[#t + 1] = k end table.sort(t) return t end)(), ",")))
  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29"
       and CoopManager.bothHave("story.bosses") then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both on Route 29, both with story.bosses")

  -- 1. the sighting
  local got = false
  for _ = 1, 60 * 10 do
    if #CoopBoss.partnerBeasts > 0 then got = true break end
    U.wait(1)
  end
  local theirs = role == "host" and "ENTEI" or "RAIKOU"
  local seen
  for _, e in ipairs(CoopBoss.partnerBeasts) do if e.n == theirs then seen = e end end
  local theirLm = game.data.maps[role == "host" and "ROUTE30" or "ROUTE29"].landmark
  check(got and seen and tonumber(seen.l) == tonumber(theirLm),
        ("the partner's %s is known here, at landmark %s"):format(theirs, tostring(seen and seen.l)))
  U.log(role .. ": partner's beasts " .. #CoopBoss.partnerBeasts)
  local Gear = require("src.ui.PokegearMenu")
  local gear = Gear.new(game, { onCancel = function() end })
  for i, c in ipairs(gear.cards) do if c.id == "MAP" then gear.index = i end end
  check(gear:current() and gear:current().id == "MAP", "the POKEGEAR is on its MAP card")
  game.stack:push(gear)
  -- the partner's frame blinks: two shots a third of a second apart
  U.wait(40)
  U.shot(game, DIR .. "/1_gear_a.png")
  U.wait(20)
  U.shot(game, DIR .. "/1_gear_b.png")
  for i = #game.stack.states, 1, -1 do
    if game.stack.states[i] == gear then table.remove(game.stack.states, i) end
  end
  U.wait(60)

  -- 2. the encounter
  local other = {}
  if role == "guest" then
    for k, v in pairs(save.g2Roam) do other[k] = { mapId = v.mapId, hp = v.hp } end
  end
  local battle
  if role == "host" then
    CoopManager.setRule("wildTogether", true)
    U.wait(30)
    local ow = game.overworld
    local function fresh() return love.timer.getTime() - (CoopManager.partner.lastSeen or 0) < 1.0 end
    for _ = 1, 60 * 60 do
      if fresh() and CoopManager.partnerAvailable(ow) then break end
      U.wait(1)
    end
    local info = save.g2Roam.RAIKOU
    -- as OverworldController's encounter builds it (RoamMons.encounterFor)
    battle = BattleState.newWild(game, info.speciesId, 40, { battleType = "roaming", roamer = "RAIKOU",
                                                            roamerHP = info.hp })
    battle.onFinish = function(r) ow:afterBattle(r, battle) end
    ow.pkmRandomEncounter = true
    ow:pushBattle(battle)
    ow.pkmRandomEncounter = nil
    check(battle.coopBeast == "RAIKOU" and CoopManager.pendingBattleInvite ~= nil, "the partner is asked in against RAIKOU")
  else
    local asked = false
    for _ = 1, 60 * 30 do
      if CoopManager.activeInviteModal then asked = true break end
      U.wait(1)
    end
    check(asked, "the invite arrives")
    U.wait(70)
    U.shot(game, DIR .. "/2_invite.png")
    U.tap(game, "a"); U.wait(30)
    U.tap(game, "start"); U.wait(30)
  end
  for _ = 1, 60 * 20 do
    local top = game.stack:top()
    if top and top.coopDouble then battle = top break end
    U.wait(1)
  end
  check(battle and battle.coopDouble and battle.coopBeast == "RAIKOU", "a co-op double against RAIKOU is up")
  if not (battle and battle.coopDouble) then love.event.quit(1) return end
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    U.tap(game, "a"); U.wait(4)
  end
  check(battle.phase == "menu", "reached FIGHT / PKMN / PACK / RUN")
  check(battle:battlerAt(P.OPPONENT_LEFT) and battle:battlerAt(P.OPPONENT_RIGHT) == nil, "RAIKOU stands alone")
  U.shot(game, DIR .. "/3_menu.png")
  for turn = 1, 2 do
    local want = battle.coop.turn + 1
    for _ = 1, 60 * 40 do
      if battle.coop.turn >= want and (battle.phase == "menu" or battle.result) then break end
      if battle.phase ~= "waitPartner" then U.tap(game, "a") end
      U.wait(3)
    end
    local b = battle:battlerAt(P.OPPONENT_LEFT)
    U.log(("%s: FOE_HP turn %d raikou %d result %s"):format(role, turn, b and b.mon.hp or -1, tostring(battle.result)))
  end
  check(battle.result == nil and not battle.roamerEscaped, "two turns on, RAIKOU has not run")
  U.shot(game, DIR .. "/4_after_turns.png")
  local ItemEffects = require("src.inventory.ItemEffects")
  local ballId = require("src.follow.FollowMon").itemByKey(game.data, "POKE_BALL")
  save.inventory[ballId] = 5
  check(ItemEffects.use(game.data, save, ballId, nil, battle) == "failed", "a BALL can't be thrown together")
  local left = battle:battlerAt(P.OPPONENT_LEFT) and battle:battlerAt(P.OPPONENT_LEFT).mon.hp
  if role == "host" then
    for _ = 1, 60 * 20 do
      if battle.phase == "menu" then break end
      if battle.phase == "moveSelect" then U.tap(game, "b")
      elseif battle.phase ~= "waitPartner" then U.tap(game, "a") end
      U.wait(3)
    end
    battle:tryRun()
  end
  local back = false
  for _ = 1, 60 * 20 do
    if game.stack:top() == game.overworld then back = true break end
    if game.stack:top() == battle then U.tap(game, "a") end
    U.wait(3)
  end
  check(back, "both got away, back on Route 29")
  U.wait(60)
  if role == "host" then
    local info = save.g2Roam.RAIKOU
    check(info and info.active ~= false and tonumber(info.hp) == tonumber(left),
          ("RAIKOU still roams in our save with the %s HP it was left with (saved %s)"):format(tostring(left),
          tostring(info and info.hp)))
  else
    local same = true
    for k, v in pairs(other) do
      local now = save.g2Roam[k]
      same = same and now and now.mapId == v.mapId and now.hp == v.hp
    end
    check(same, "our own beasts are as they were")
  end
  U.shot(game, DIR .. "/5_back.png")
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
