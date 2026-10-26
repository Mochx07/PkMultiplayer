-- src/coop/CoopCompat.lua
-- GETTING ALONG WITH THE OTHER MODS.
--
-- DramaticShapes (bundled with the official Gen2Recomped) stages battles on
-- the map in 3D, and stages singles only: its notes say so, and its HUD
-- panels and bands are cut for the two single-battle boxes.  A co-op double
-- has four boxes in other places, and staged it drew every name and HP bar
-- twice ("PIDGEYPIDGEY").  So a co-op double is not staged: it is fought on
-- the classic battle screen, as with 3D-BTL off.  Singles are untouched.
--
-- ...AND ON THE CLASSIC SCREEN OUR POKEMON SHOW THEIR BACKS.  In its 3D
-- battles both sides face the camera, so DramaticShapes hands the player's
-- side its FRONT pic (OverworldBattle.wantsFront, asked by the pokemon.sprite
-- hook for every battler built).  It went on doing that for a co-op double
-- it does not stage: on the flat screen both players' Pokemon stood facing
-- away from the foes.  While a co-op double (or a wild battle together) is
-- up, it is told the battle is not staged, and the back pics come back.

local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")

local CoopCompat = {}

-- a co-op double or wild battle is being built or fought right now
function CoopCompat.classicScreen()
  local CB = package.loaded["src.coop.CoopBattle"]
  local b = CB and CB.currentBattle
  if type(b) ~= "table" or not (b.coopDouble or b.coopWild) then return false end
  return not (b.coop and b.coop.finished)
end

function CoopCompat.wrapDramaticShapes()
  local V = rawget(_G, "__DRAMATIC_SHAPE_V")
  if type(V) ~= "table" or type(V.require) ~= "function" then return false end
  local ok, OB = pcall(V.require, "OverworldBattle")
  if not (ok and type(OB) == "table" and type(OB.begin) == "function") then return false end
  if OB.__pkmCoopWrapped then return true end
  local begin = OB.begin
  OB.begin = function(state, battle, ...)
    if type(battle) == "table" and (battle.coopDouble or battle.coopWild) then
      if OB.finish then pcall(OB.finish) end
      return false
    end
    return begin(state, battle, ...)
  end
  if type(OB.wantsFront) == "function" then
    local wantsFront = OB.wantsFront
    OB.wantsFront = function(...)
      if CoopCompat.classicScreen() then return false end
      return wantsFront(...)
    end
  end
  OB.__pkmCoopWrapped = true
  CoopLog.info("COMPAT", "DramaticShapes: co-op doubles stay on the classic screen, with back pics")
  return true
end

-- DramaticShapes may load before or after this mod, and may come back after
-- the launcher reloads the mods: checked until it is wrapped, then cheaply
CoopManager.onIdleTick("compat", function()
  if CoopCompat.done == rawget(_G, "__DRAMATIC_SHAPE_V") and CoopCompat.done ~= nil then return end
  if CoopCompat.wrapDramaticShapes() then CoopCompat.done = rawget(_G, "__DRAMATIC_SHAPE_V") end
end)

return CoopCompat
