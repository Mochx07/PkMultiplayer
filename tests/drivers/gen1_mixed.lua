-- Red and Yellow linked: what each copy draws of the other.
-- Host runs Red, guest runs Yellow (POKEPORT_VERSION per copy).  Both stand
-- in Pallet Town with a PIKACHU first in the party; each screenshots the
-- field (partner + their walking Pokemon) and a co-op wild double.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7801")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local GV = require("src.core.GameVersion")
  U.log(role .. ": game " .. tostring(GV.get()))
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  for _, sp in ipairs({ "PIKACHU", role == "host" and "CHARMANDER" or "BULBASAUR" }) do
    table.insert(save.party, Pokemon.new(game.data, sp, 12))
  end
  do
    local okP, Pipelines = pcall(require, "src.render.Pipelines")
    if okP then for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end end
  end
  U.teleport(game, "PALLET_TOWN", role == "host" and 5 or 8, 8, "down")
  if role == "host" then
    check(CoopManager.host(port), "hosting")
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling")
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "PALLET_TOWN" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked in Pallet Town")
  U.wait(30)
  for _ = 1, 2 do U.hold(game, role == "host" and "down" or "up", 16) end
  U.wait(120)
  local p = CoopManager.partner
  local npc = CoopManager.partnerNpc
  U.log(("%s: partner game=%s sprite=%s drawn=%s fol=%s"):format(role, tostring(p.game), tostring(p.sprite),
    tostring(npc and npc.spriteName), tostring(p.fol and (p.fol.sprite or p.fol.species or p.fol.id) or p.fol)))
  local okF, FollowMon = pcall(require, "src.follow.FollowMon")
  local remote = okF and FollowMon.remote
  U.log(("%s: remote follower %s"):format(role, tostring(remote and (remote.spriteName or remote.sprite and remote.sprite.id) or remote)))
  U.shot(game, DIR .. "/1_field.png")

  if role == "host" then
    CoopManager.setRule("wildTogether", true)
    U.wait(30)
    local BattleState = require("src.battle.BattleState")
    local ow = game.overworld
    local battle = BattleState.newWild(game, "PIDGEY", 5)
    battle.onFinish = function(r) ow:afterBattle(r, battle) end
    ow.pkmRandomEncounter = true
    ow:pushBattle(battle)
    ow.pkmRandomEncounter = nil
  end
  local battle
  for i = 1, 60 * 25 do
    local t = game.stack:top()
    if t and t.coopDouble then battle = t break end
    if role == "guest" and t and t.isCoopInvite and i % 30 == 0 then U.tap(game, "a") end
    if t and t.isCoopBattleSelect and i % 20 == 0 then U.tap(game, "start") end
    U.wait(1)
  end
  check(battle ~= nil, "co-op wild double up")
  if battle then
    for _ = 1, 200 do
      if battle.phase == "menu" then break end
      U.tap(game, "a") U.wait(4)
    end
    U.shot(game, DIR .. "/2_battle.png")
  end
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
