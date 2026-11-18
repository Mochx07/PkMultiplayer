-- Red/Blue: THE RIVAL 2v2 (nightly.3).  The host chose SQUIRTLE, the guest
-- BULBASAUR; the host's script runs Route 22's rival (rival_battle
-- OPP_RIVAL1 4); the guest joins and both copies face two rivals: the host's
-- (party 5) and the guest's own (party 6).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7806")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local MAP = "PALLET_TOWN"
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.flags = save.flags or {}
  save.flags[role == "host" and "EVENT_CHOSE_SQUIRTLE" or "EVENT_CHOSE_BULBASAUR"] = true
  save.player.rival = role == "host" and "GARY" or "BLUE"
  for _, sp in ipairs(role == "host" and { "SQUIRTLE", "PIDGEY" } or { "BULBASAUR", "RATTATA" }) do
    table.insert(save.party, Pokemon.new(game.data, sp, 12))
  end
  U.teleport(game, MAP, role == "host" and 5 or 8, 8, "down")
  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == MAP then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both in Pallet Town")
  U.wait(60)

  local function topName()
    local t = game.stack:top()
    if not t then return "nil" end
    if t == game.overworld then return "overworld" end
    if t.isCoopInvite then return "invite" end
    if t.isCoopBattleSelect then return "select" end
    if t.phase then return "battle:" .. tostring(t.phase) .. (t.coopDouble and ":coop" or "") end
    return tostring(t)
  end
  local ow = game.overworld
  if role == "host" then
    ow.runner:run({ { "rival_battle", "OPP_RIVAL1", 4 } }, { mapId = MAP })
  end
  local battle, last
  for i = 1, 60 * 40 do
    local name = topName()
    if name ~= last then U.log(role .. ": top " .. name) last = name end
    local t = game.stack:top()
    if t and t.phase and t.coopDouble then battle = t break end
    if role == "guest" and t and t.isCoopInvite and i % 30 == 0 then U.tap(game, "a") end
    if t and t.isCoopBattleSelect and i % 20 == 0 then U.tap(game, "start") end
    if role == "host" and t and t.phase and not t.coopDouble and i > 60 * 25 then break end
    -- the host's BATTLE MODE: CO-OP DOUBLE (the first row)
    if role == "host" and t and t ~= game.overworld and not t.phase and not t.isCoopBattleSelect and i % 30 == 0 then U.tap(game, "a") end
    U.wait(1)
  end
  check(battle ~= nil, "a co-op battle against the rival is up")
  if battle then
    U.wait(30)
    U.shot(game, DIR .. "/1_battle.png")
    local P = require("src.battle.BattleState").POS
    local foe = battle:battlerAt(P.OPPONENT_LEFT)
    local foe2 = battle:battlerAt(P.OPPONENT_RIGHT)
    local partyA, partyB = {}, {}
    for _, m in ipairs(battle.enemyParty or {}) do partyA[#partyA + 1] = tostring(m.species) end
    for _, m in ipairs(battle.enemyPartyB or {}) do partyB[#partyB + 1] = tostring(m.species) end
    local key = table.concat(partyA, ",") .. "|" .. table.concat(partyB, ",")
    U.log(("%s: rivals %s & %s | %s"):format(role, tostring(battle.trainer and battle.trainer.name),
      tostring(battle.trainerB and battle.trainerB.name), key))
    check(battle.coopRivals == true, "two rivals on the far side")
    check(foe2 ~= nil, "the second rival's Pokemon stands on the right")
    CoopManager.sendChat("RIV " .. key)
    local agreed
    for _ = 1, 60 * 15 do
      for _, line in ipairs(CoopManager.chatLog or {}) do
        local t = tostring(line.text):match("^RIV (.*)$")
        if t and line.sender ~= save.player.name then agreed = (t == key) end
      end
      if agreed ~= nil then break end
      U.wait(1)
    end
    check(agreed == true, "both copies built the same two teams")
  else
    U.shot(game, DIR .. "/1_no_coop.png")
  end
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
