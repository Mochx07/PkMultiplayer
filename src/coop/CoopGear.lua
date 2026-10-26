-- src/coop/CoopGear.lua
-- THE PARTNER IN YOUR POKéGEAR.  While linked:
--   * PHONE: the partner heads the phone book.  CALL rings their POKéGEAR
--     (a status line and the call tone on their side) and opens the chat,
--     over the phone card, the way a call reads over it on the cartridge.
--   * MAP: the partner's mark blinks on the town map where they are, beside
--     yours when you are both in the same place.
-- lib/Hooks.lua wraps PokegearMenu's contacts / startPhoneCall / drawMap and
-- hands them here.

local CoopManager = require("src.coop.CoopManager")

local CoopGear = {}

local function linked()
  return CoopManager.isConnected and CoopManager.isConnected()
end

local function partnerName()
  return tostring(CoopManager.partner.name or "PARTNER"):upper()
end

-- the phone book, with the partner on top
function CoopGear.contacts(list)
  if not linked() then return list end
  local out = { { id = "coop", name = partnerName(), coopPartner = true } }
  for _, e in ipairs(type(list) == "table" and list or {}) do out[#out + 1] = e end
  return out
end

-- CALL on the partner: true when handled here
function CoopGear.call(menu, entry)
  if not (type(entry) == "table" and entry.coopPartner) then return false end
  local game = menu.game
  pcall(function() require("src.core.Sound").play(game.data, "Call") end)
  if CoopManager.net then
    CoopManager.net:send({ type = "coop_call", name = CoopManager.getLocalPlayerName(game) })
  end
  local TextBox = require("src.coop.CoopI18n").textBox()
  game.stack:push(TextBox.new(game, "Calling " .. partnerName() .. "...", function()
    CoopManager.openChat(game, game.overworld)
  end))
  return true
end

CoopManager.handlers.coop_call = function(ow, msg)
  local game = CoopManager.getGame(ow)
  pcall(function() require("src.core.Sound").play(game.data, "Call") end)
  CoopManager.showStatus((msg.name or "Partner") .. " is calling! (T: chat)", 5)
end

-- the town-map point of a map, as PokegearMenu:drawMap finds yours
local function landmarkPoint(game, mapId)
  local maps = game.data and game.data.maps
  local def = maps and mapId and maps[mapId]
  local landmark = def and def.landmark
  local town = (game.data.field or {}).townMap or {}
  local entry = landmark and town.landmarks
    and (town.landmarks[landmark] or town.landmarks[tostring(landmark)])
  if not entry then return nil end
  return tonumber(entry.x) or 0, tonumber(entry.y) or 0, landmark
end
CoopGear.landmarkPoint = landmarkPoint

-- after the map card is drawn: the partner's mark, blinking (on two thirds
-- of each second) so it reads apart from yours
function CoopGear.drawMap(menu)
  if not linked() then return end
  local game = menu.game
  local p = CoopManager.partner
  local x, y, landmark = landmarkPoint(game, p.map)
  if not x then return end
  local t = love.timer and love.timer.getTime() or 0
  if t % 1 > 0.66 then return end
  local mine = game.overworld and game.overworld.map and game.overworld.map.def
  local same = mine and mine.landmark == landmark
  local px, py = x - 8 + (same and 6 or 0), y - 16 + (same and 2 or 0)
  -- a P2 mark: a dark ring with a light core, 8x8, where the player icon's
  -- feet would be
  local g = love.graphics
  g.setColor(0.1, 0.1, 0.35, 1)
  g.rectangle("fill", px + 4, py + 8, 8, 8)
  g.setColor(0.55, 0.8, 1, 1)
  g.rectangle("fill", px + 6, py + 10, 4, 4)
  g.setColor(1, 1, 1, 1)
end

return CoopGear
