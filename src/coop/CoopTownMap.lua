-- src/coop/CoopTownMap.lua
-- THE PARTNER ON THE TOWN MAP (nightly.3, Mochi: "the other player's head on
-- the map").  While linked, the TOWN MAP (Red/Blue/Yellow's item, and the
-- Gen 2 town map the fly and area screens use) shows where the partner is:
-- the top half of their own walking sprite, facing you, in their colours,
-- on their town -- steady, where your own mark blinks.  A partner on the
-- other edition of the same generation (Red with Yellow) is placed by their
-- map's id, which the two editions share.  Not in the Time Capsule (the
-- other world's map is not this one), nor on a nest (AREA) screen.
-- lib/Hooks.lua wraps TownMap:draw and calls CoopTownMap.draw after it.
local CoopManager = require("src.coop.CoopManager")

local CoopTownMap = {}

local renderers = setmetatable({}, { __mode = "k" })
-- the partner's version colours on the head: off -- with them the sprite's
-- transparent colour came out as an opaque grey box on the TOWN MAP
CoopTownMap.PARTNER_COLOURS = false

local function linked()
  return CoopManager.isConnected and CoopManager.isConnected() and not CoopManager.capsule
end

-- the partner's sprite here: theirs if this game has it, else this game's
-- own player walker (as CoopPartnerNpc does)
local function renderer(game)
  local defs = game and game.data and game.data.sprites
  if type(defs) ~= "table" then return nil end
  local p = CoopManager.partner
  local id = p.sprite
  if not defs[id] then
    local ow = game.overworld
    id = ow and ow.player and ow.player.walkId
  end
  local def = id and defs[id]
  if type(def) ~= "table" then return nil end
  local byData = renderers[defs] or {}
  renderers[defs] = byData
  if byData[id] == nil then
    local SR = require("src.render.SpriteRenderer")
    local ok, r = pcall(SR.new, def)
    byData[id] = ok and r or false
    if ok and r and r.setPalette and CoopManager.partnerPalette and CoopTownMap.PARTNER_COLOURS then
      local okP, colors, key = pcall(CoopManager.partnerPalette, game)
      if okP and colors then pcall(r.setPalette, r, colors, key) end
    end
  end
  return byData[id] or nil
end

-- the centre of the partner's place on this map screen, or nil
function CoopTownMap.point(tm)
  local p = CoopManager.partner
  if type(tm) ~= "table" or tm.nestSpecies or not (p and p.map) then return nil end
  local loc = tm.byMap and tm.byMap[p.map]
  if type(loc) ~= "table" then return nil end
  if tm.mode == "gen2" then
    if loc.region ~= tm.region or not (loc.px and loc.py) then return nil end
    return loc.px, loc.py
  end
  if tm.mode == "grid" and loc.x and loc.y then
    -- TownMap's markerXY is the 8x8 cell's top-left; its centre is +4
    return loc.x * 8 + 16 + 4, loc.y * 8 + 8 + 4
  end
  return nil
end

function CoopTownMap.draw(tm)
  if not linked() then return end
  local cx, cy = CoopTownMap.point(tm)
  if not cx then return end
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local r = renderer(tm.game)
  if r then
    -- SpriteRenderer:draw puts the cell 4 px above py; the head is the top
    -- 16x8, centred on the place
    local ok = pcall(r.draw, r, cx - 8, cy, 0, 0, "down", 0, false, true)
    if ok then return end
  end
  -- no sprite to draw: a ringed dot, apart from your own solid one
  g.setColor(0, 0, 0, 1)
  g.circle("line", cx, cy, 4)
  g.setColor(1, 1, 1, 1)
end

return CoopTownMap
