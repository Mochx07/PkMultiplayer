-- Gen 1 co-op double, alone (the partner's slot played by the stand-in AI):
-- where the two backs (P1, P2) land, and a screenshot.  PKM_SPECIES picks
-- the two (default PIKACHU,PIKACHU).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/backs"
  local Pokemon = require("src.pokemon.Pokemon")
  local save = U.freshSave(game)
  save.player.name = "MOCHI"
  local a, b = (os.getenv("PKM_SPECIES") or "PIKACHU,PIKACHU"):match("([^,]+),([^,]+)")
  table.insert(save.party, Pokemon.new(game.data, a, 14))
  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  local BattleState = require("src.battle.BattleState")
  local CoopBattle = require("src.coop.CoopBattle")
  local battle = BattleState.newWild(game, "PIDGEY", 5)
  CoopBattle.initBattle(battle, { save.party[1] }, { Pokemon.new(game.data, b, 14) }, { name = "TOBY" }, 4242, nil)
  battle.coop.partnerLost = true
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)
  for _ = 1, 150 do
    if battle.phase == "menu" then break end
    U.tap(game, "a") U.wait(5)
  end
  U.wait(20)
  local P = BattleState.POS
  for _, pos in ipairs({ P.PLAYER_LEFT, P.PLAYER_RIGHT }) do
    local bt = battle:battlerAt(pos)
    local img = bt and bt.sprite and battle:picImage(bt.sprite)
    local s = img and BattleState.resolveBattleScale(battle.data, "back", nil, bt.mon.species) or 0
    local x, y = img and BattleState.doubleBackBase(pos, img, s)
    U.log(("pos %d %s img %sx%s scale %s base %s,%s"):format(pos, tostring(bt and bt.mon.species),
      tostring(img and img:getWidth()), tostring(img and img:getHeight()), tostring(s), tostring(x), tostring(y)))
  end
  U.log("HUD_X " .. tostring(BattleState.DOUBLE_HUD_X))
  U.shot(game, DIR .. "/menu.png")
  love.event.quit(0)
end
