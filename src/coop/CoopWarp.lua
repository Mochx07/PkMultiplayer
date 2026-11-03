-- src/coop/CoopWarp.lua (split out of CoopManager.lua for 1.20)
-- install(CoopManager, CMI) runs this code where it used to sit in
-- CoopManager.lua: CoopManager.* names are the manager's own, and CMI
-- carries the manager's file-level locals it reads (and the ones it
-- hands on to the code after it).
--
-- warp to partner
--
-- It used to be free, instant and unlimited: from anywhere straight onto the
-- partner, which made walking, FLY and every gate in the game optional.  Now
-- it is FLY with a partner at the other end, not a taxi:
--   * only to a town or city YOU have already been to, the same places FLY
--     would take you (field.flyOrder + save.visited, FlyMenu's rule);
--   * the partner is asked, and has to say YES;
--   * once every WARP_COOLDOWN seconds (ten minutes);
--   * only to a partner standing idle in the overworld (not in a battle, a
--     conversation, a menu or a map transition);
--   * never into a gym or the Elite Four -- those you walk into together
--     (checkStoryWarp);
--   * never while either of you is surfing, or while you are battling or
--     talking.

local M = {}

function M.install(CoopManager, CMI)
local CoopLog = CMI.CoopLog
local CoopManager = CMI.CoopManager
local LEAGUE_MAPS = CMI.LEAGUE_MAPS
local PARTNER_FRESH = CMI.PARTNER_FRESH
local STORY_GATE_MAPS = CMI.STORY_GATE_MAPS
local getGame = CMI.getGame
local mapsMatch = CMI.mapsMatch
local normMap = CMI.normMap
local now = CMI.now
local playSound = CMI.playSound
local stackTop = CMI.stackTop


CoopManager.WARP_COOLDOWN = 600
CoopManager.WARP_ASK_TIMEOUT = 30
CoopManager.lastWarpAt = nil
CoopManager.warpAsk = nil      -- { id, at }: the request we are waiting on
local warpAskSeq = 0

function CoopManager.warpCooldownLeft()
  if not CoopManager.lastWarpAt then return 0 end
  return math.max(0, CoopManager.WARP_COOLDOWN - (now() - CoopManager.lastWarpAt))
end

function CoopManager.warpAsking()
  local ask = CoopManager.warpAsk
  return ask ~= nil and (now() - ask.at) <= CoopManager.WARP_ASK_TIMEOUT
end

-- A FLY destination this player has been to.
function CoopManager.flyVisited(game, mapId)
  local data, save = game and game.data, game and game.save
  if not (data and save and mapId) then return false end
  local want = normMap(mapId)
  for _, id in ipairs((data.field or {}).flyOrder or {}) do
    if normMap(id) == want then
      local def = data.maps and data.maps[id]
      if not (def and (save.visited or {})[id]) then return false end
      local okMap, Map = pcall(require, "src.world.Map")
      return (okMap and Map.isOutdoor and Map.isOutdoor(def)) or def.tileset == "PLATEAU"
    end
  end
  return false
end

-- ok, reason.  `answered`: the partner has just said yes, so their own
-- yes/no box may still be closing -- that is not "busy".
function CoopManager.canWarpToPartner(ow, answered)
  local p = CoopManager.partner
  if not CoopManager.isConnected() or not p.map then return false, "No partner available" end
  if not (ow and ow.startWarpTo) or ow.transitioning then return false, "Can't warp right now" end
  if CoopManager.isLocalInBattle(ow) then return false, "Can't warp in battle!" end
  local left = CoopManager.warpCooldownLeft()
  if left > 0 then
    local secs = math.ceil(left)
    return false, string.format("Warp ready in %d:%02d", math.floor(secs / 60), secs % 60)
  end
  if mapsMatch(p.map, ow.map and ow.map.id) then return false, "Partner is right here!" end
  if (now() - (p.lastSeen or 0)) > PARTNER_FRESH then return false, "Partner not responding" end
  if p.inBattle or ((p.busy or p.inDialogue) and not answered) then return false, "Partner is busy" end
  if p.surfing then return false, "Partner is on the water" end
  local dest = normMap(p.map) or ""
  if STORY_GATE_MAPS[dest] or LEAGUE_MAPS[dest] then return false, "Can't warp in there!" end
  if not CoopManager.flyVisited(getGame(ow), p.map) then
    return false, "Only to towns you know"
  end
  if CoopManager.isLocalInDialogue(ow) or (ow.player and ow.player.surfing) then
    return false, "Can't warp now!"
  end
  return true
end

-- A asks; B answers YES or NO; A warps on a YES (onWarpReply).
function CoopManager.warpToPartner(ow)
  local ok, why = CoopManager.canWarpToPartner(ow)
  if ok and CoopManager.warpAsking() then ok, why = false, "Waiting for an answer" end
  if not ok then
    CoopManager.showStatus(why, 2.5)
    playSound(getGame(ow), "Collision")
    return false
  end
  warpAskSeq = warpAskSeq + 1
  CoopManager.warpAsk = { id = warpAskSeq, at = now() }
  CoopManager.net:send({ type = "coop_warp_req", id = warpAskSeq })
  CoopManager.showStatus("Asked " .. (CoopManager.partner.name or "partner") .. " to warp", 3)
  return true
end

-- B: a request.  Only a player idle in the overworld is asked at all.
function CoopManager.onWarpRequest(ow, msg)
  local game = getGame(ow)
  local function reply(yes, why)
    CoopManager.net:send({ type = "coop_warp_reply", id = msg.id, ok = yes, why = why })
  end
  local idle = game and game.stack and stackTop(game) == ow and ow and not ow.transitioning
               and not CoopManager.isLocalInBattle(ow) and not CoopManager.isLocalInDialogue(ow)
  if not idle then return reply(false, "busy") end
  local TextBox = require("src.coop.CoopI18n").textBox()
  local name = CoopManager.partner.name or "Your partner"
  game.stack:push(TextBox.new(game, name .. " wants to\nwarp to you. OK?", nil, {
    defaultNo = true,
    choice = function(yes) reply(yes == true) end,
  }))
end

-- A: the answer.  Checked again, because the world moved while B decided.
function CoopManager.onWarpReply(ow, msg)
  local ask = CoopManager.warpAsk
  if not (ask and ask.id == msg.id) then return end
  CoopManager.warpAsk = nil
  local name = CoopManager.partner.name or "Partner"
  if (now() - ask.at) > CoopManager.WARP_ASK_TIMEOUT then return end
  if not msg.ok then
    CoopManager.showStatus(msg.why == "busy" and (name .. " is busy") or (name .. " said no"), 3)
    return
  end
  local ok, why = CoopManager.canWarpToPartner(ow, true)
  if not ok then
    CoopManager.showStatus(why, 2.5)
    playSound(getGame(ow), "Collision")
    return
  end
  local p = CoopManager.partner
  CoopManager.lastWarpAt = now()
  ow:startWarpTo(p.map, p.cx, p.cy, p.facing or "down")
  playSound(getGame(ow), "Teleport_Exit1")
  CoopManager.net:send({ type = "coop_warp" })
  CoopManager.showStatus("Warped to " .. name .. "!", 2.5)
end

-- A: nobody answered
function CoopManager.tickWarpAsk()
  local ask = CoopManager.warpAsk
  if ask and (now() - ask.at) > CoopManager.WARP_ASK_TIMEOUT then
    CoopManager.warpAsk = nil
    CoopManager.showStatus("No answer from " .. (CoopManager.partner.name or "partner"), 3)
  end
end

-- Story gate check: a gym or the League waits until the partner is with you.
function CoopManager.checkStoryWarp(ow, destMapId)
  if not CoopManager.storySync or not CoopManager.isConnected() then
    return true
  end
  local dest = normMap(destMapId) or ""
  if not STORY_GATE_MAPS[dest] then return true end

  local partnerMap = normMap(CoopManager.partner.map)
  local current = normMap(ow and ow.map and ow.map.id)
  if not partnerMap then return true end

  local together = false
  if partnerMap == dest or partnerMap == current then
    together = true
  elseif LEAGUE_MAPS[dest] and LEAGUE_MAPS[partnerMap] then
    together = true
  else
    -- both somewhere in the same town (the gym's prefix: VIOLET_GYM -> VIOLET)
    local town = dest:match("^(.-)_GYM$")
    if town and partnerMap:find("^" .. town .. "_") and current and current:find("^" .. town .. "_") then
      together = true
    end
  end

  if not together then
    CoopManager.showStatus(string.format("Wait for %s! (%s)",
      CoopManager.partner.name or "partner", CoopManager.mapLabel(CoopManager.partner.map)), 3.5)
    playSound(getGame(ow), "Collision")
    CoopLog.sync("STORY_GATE_BLOCKED", "Blocked from " .. tostring(destMapId) .. "; partner at " .. tostring(CoopManager.partner.map))
    return false
  end
  return true
end

end

return M
