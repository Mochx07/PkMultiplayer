-- One Yellow copy, no partner: a plain single battle as the baseline for the
-- Gen 1 move animations seen in a co-op double (yellow_double.lua).
-- Turn 1 WATER GUN, turn 2 HYPER BEAM; frames every 2nd tick while they play.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/single"
  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local save = U.freshSave(game)
  local m = Pokemon.new(game.data, "PIKACHU", 40)
  m.moves = { { id = "WATER_GUN", pp = 20 }, { id = "HYPER_BEAM", pp = 5 } }
  table.insert(save.party, m)
  U.teleport(game, "PALLET_TOWN", 5, 8, "down")
  local BattleState = require("src.battle.BattleState")
  local ow = game.overworld
  local battle = BattleState.newWild(game, "SLOWPOKE", 30)
  battle.onFinish = function(r) ow:afterBattle(r, battle) end
  ow:pushBattle(battle)
  for _ = 1, 600 do if game.stack:top() == battle then break end U.wait(1) end
  U.log("battle up: " .. tostring(game.stack:top() == battle) .. " " .. tostring(battle.phase))
  local function toMenu()
    for _ = 1, 400 do
      if battle.phase == "menu" then return true end
      if game.stack:top() ~= battle then return false end
      U.tap(game, "a"); U.wait(4)
    end
  end
  for turn = 1, 2 do
    if not toMenu() then break end
    U.tap(game, "a"); U.wait(12)
    if turn == 2 then U.tap(game, "down"); U.wait(8) end
    U.tap(game, "a"); U.wait(2)
    local per = {}
    for _ = 1, 60 * 20 do
      if game.stack:top() ~= battle or battle.phase == "menu" then break end
      local a, ap = battle.animName, battle.animPlayer
      if a and ap and not ap:isDone() then
        per[a] = (per[a] or 0) + 1
        if per[a] <= 30 then U.shot(game, DIR .. ("/t%d_%s_%02d.png"):format(turn, a, per[a])) end
        U.wait(2)
      else
        U.tap(game, "a"); U.wait(2)
      end
    end
  end
  U.log("single done")
  love.event.quit(0)
end
