-- GEN 2 MOVE ANIMATIONS IN A SINGLE BATTLE, frame by frame (review driver).
--
--   cd <base> && SHOT_DIR=/tmp/x POKEPORT_VERSION=gold POKEPORT_IDENTITY=<id> \
--   SIX_MOVES=HYPER_BEAM,AEROBLAST SIX_VANILLA=0 \
--   POKEPORT_DRIVER=tests/drivers/six_anim_single.lua love .
--
-- The player's LUGIA and a wild SNORLAX both get one move per round; every
-- second frame of each move's animation is captured, from both sides.
-- SIX_VANILLA=1 clears the co-op build's `sideOffsets` every frame, so the
-- same frames show the engine's own (cartridge) placement for comparison.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/six"
  local vanilla = os.getenv("SIX_VANILLA") == "1"
  local moves = {}
  for m in (os.getenv("SIX_MOVES") or "HYPER_BEAM"):gmatch("[^,]+") do moves[#moves + 1] = m end
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  U.wait(5)
  -- the classic 2D battle: DRAMATIC_SHAPE's voxel world redraws the field
  -- (live level only, nothing is written to the save)
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local save = U.freshSave(game)
  save.player.name = "SIX"
  save.options = save.options or {}
  save.options.animations = true
  local mon = Pokemon.new(game.data, os.getenv("SIX_PLAYER") or "SPECIES_249", 60)
  mon.moves = { { id = moves[1], pp = 30 } }
  if os.getenv("SIX_SHINY") == "1" then Pokemon.forceShiny(game.data, mon) end
  save.party = { mon }
  U.teleport(game, "ROUTE29", 10, 8, "down")
  U.wait(20)
  local ow = game.overworld
  local battle = BattleState.newWild(game, os.getenv("SIX_FOE") or "SPECIES_143", 60)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  for _ = 1, 600 do
    if game.stack:top() == battle and battle.phase == "menu" then break end
    U.tap(game, "a"); U.wait(3)
  end
  U.log("battle up, phase " .. tostring(battle.phase))
  for _, b in ipairs({ battle.player, battle.enemy }) do
    b.mon.stats.hp = 999; b.mon.hp = 999; b.shownHP = 999
  end

  local function setMove(b, id)
    local ms = b.mon.moves
    for i = #ms, 1, -1 do ms[i] = nil end
    ms[1] = { id = id, pp = 30 }
  end

  for _, id in ipairs(moves) do
    setMove(battle.player, id)
    setMove(battle.enemy, id)
    local seen, n, lastName = {}, 0, nil
    local quiet = 0
    for _ = 1, 60 * 40 do
      if battle.animPlaying and battle.animName then
        if vanilla and battle.animPlayer then battle.animPlayer.sideOffsets = nil end
        local side = battle.animAttackerIsPlayer and "P" or "E"
        local key = battle.animName .. "_" .. side
        if key ~= lastName then n = 0; lastName = key; seen[key] = (seen[key] or 0) + 1 end
        n = n + 1
        U.shot(game, ("%s/%s%s_%d_%02d.png"):format(DIR, vanilla and "v_" or "", key, seen[key], n))
        quiet = 0
      else
        if battle.phase == "menu" or battle.phase == "moveSelect" then
          if seen[id .. "_P"] and seen[id .. "_E"] and quiet > 30 then break end
          U.tap(game, "a")
        elseif game.stack:top() == battle then
          U.tap(game, "a")
        end
        quiet = quiet + 1
        U.wait(2)
      end
      for _, b in ipairs({ battle.player, battle.enemy }) do
        if b.mon.hp < 500 then b.mon.hp = 999; b.shownHP = 999 end
      end
      if game.stack:top() ~= battle then break end
    end
    U.log(("%s: player x%d, foe x%d"):format(id, seen[id .. "_P"] or 0, seen[id .. "_E"] or 0))
  end
  U.log("done")
  love.event.quit(0)
end
