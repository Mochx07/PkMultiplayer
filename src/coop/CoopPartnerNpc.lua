-- src/coop/CoopPartnerNpc.lua (split out of CoopManager.lua for 1.20)
-- install(CoopManager, CMI) runs this code where it used to sit in
-- CoopManager.lua: CoopManager.* names are the manager's own, and CMI
-- carries the manager's file-level locals it reads (and the ones it
-- hands on to the code after it).
--
-- partner entity

local M = {}

function M.install(CoopManager, CMI)
local CoopLog = CMI.CoopLog
local CoopManager = CMI.CoopManager
local NPC = CMI.NPC
local PARTNER_NPC_INDEX = CMI.PARTNER_NPC_INDEX
local getGame = CMI.getGame
local mapsMatch = CMI.mapsMatch
local now = CMI.now
local partnerPalette = CMI.partnerPalette


-- Where the partner's map sits relative to ours, in pixels: 0,0 on the
-- same map, the seam offset when they stand on a connected map we are
-- drawing (route <-> town), nil when they are somewhere we cannot see.
local function partnerFrameOffset(ow)
  local pm = CoopManager.partner.map
  if not (ow and ow.map and pm) then return nil end
  if mapsMatch(pm, ow.map.id) then return 0, 0 end
  for _, nb in ipairs(ow.neighbors or {}) do
    if nb.map and mapsMatch(nb.map.id, pm) then
      return nb.ox or ((nb.cx or 0) * 16), nb.oy or ((nb.cy or 0) * 16)
    end
  end
  return nil
end
CoopManager.partnerFrameOffset = partnerFrameOffset

-- ---------------------------------------------------------------------
-- KRIS OR THE BOY, as the partner sees themselves.  An older partner sends
-- no `walk`; their sprite says it while they walk or ride.
-- ---------------------------------------------------------------------

local function isKris(id)
  return type(id) == "string" and id:find("^SPRITE_KRIS") ~= nil
end

function CoopManager.partnerIsKris()
  local p = CoopManager.partner
  return isKris(p.walk or p.sprite)
end

-- The back pic the partner stands behind you in, in a co-op double, when it
-- is not your own: their form's back (Crystal names both), or on Gold and
-- Silver Kris's, cut from a Crystal ROM (lib/Kris.lua).  Returns the path
-- and whether it is true-colour, or nil to share yours.
function CoopManager.partnerBackPic(data, myWalk)
  if not CoopManager.partner.name then return nil end
  local theirs = CoopManager.partnerIsKris()
  if theirs == isKris(myWalk) then return nil end
  local forms = data and data.field and data.field.playerForms
  local form = type(forms) == "table" and forms[theirs and "girl" or "boy"]
  if type(form) == "table" and type(form.back) == "string" then
    return form.back, form.trueColor and true or false
  end
  local K = package.loaded["pkmultiplayer.kris"]
  if theirs and K and K.backPath then return K.backPath, false end
  return nil
end

local function applyPartnerPalette(npc, game)
  if npc and npc.sprite and npc.sprite.setPalette then
    local colors, key = partnerPalette(game)
    pcall(npc.sprite.setPalette, npc.sprite, colors, key)
  end
end
CoopManager.partnerPalette = partnerPalette
CoopManager.applyPartnerPalette = applyPartnerPalette

local function knownSprite(game, id)
  local sprites = game and game.data and game.data.sprites
  if type(id) ~= "string" then return false end
  if not sprites then return true end
  return sprites[id] ~= nil
end

-- What to draw when the partner names a sheet this cartridge does not have
-- (a different game, a mod sprite): this game's own player walker.  The old
-- fallback was a hard-coded SPRITE_CHRIS -- which Gold does not have at all
-- (its hero is SPRITE_RED), so every Gold partner was drawn as a placeholder.
local function defaultPlayerSprite(ow, game)
  local walk = ow and ow.player and ow.player.walkId
  if knownSprite(game, walk) then return walk end
  local ok, FieldDefaults = pcall(require, "src.world.FieldDefaults")
  if ok and FieldDefaults and FieldDefaults.fieldValue and game and game.data then
    local okV, id = pcall(FieldDefaults.fieldValue, game.data, "playerSprites", "walk")
    if okV and knownSprite(game, id) then return id end
  end
  for _, id in ipairs({ "SPRITE_RED", "SPRITE_CHRIS", "SPRITE_GOLD" }) do
    if knownSprite(game, id) then return id end
  end
  return walk or "SPRITE_RED"
end

local function ensureListed(list, npc)
  for _, n in ipairs(list) do
    if n == npc then return end
  end
  table.insert(list, npc)
end

function CoopManager.removePartnerNpc(ow)
  if ow then
    for _, listName in ipairs({ "npcs", "entities" }) do
      local list = ow[listName]
      if list then
        for i = #list, 1, -1 do
          if list[i] == CoopManager.partnerNpc or (type(list[i]) == "table" and list[i].coopPartner) then
            table.remove(list, i)
          end
        end
      end
    end
  end
  CoopManager.partnerNpc = nil
  local okF, FollowMon = pcall(require, "src.follow.FollowMon")
  if okF then FollowMon.remote = nil end
end

local function makePartnerNpc(ow, game, spriteId)
  local objDef = {
    index = PARTNER_NPC_INDEX,
    name = "COOP_PARTNER",
    sprite = spriteId,
    x = 0, y = 0,
    movement = "STAY",
    range = "NONE",
  }
  local ok, npc = pcall(NPC.new, game.data, ow.map.id, objDef)
  if not ok or not npc then
    CoopLog.error("MANAGER", "Could not build partner sprite " .. tostring(spriteId) .. ": " .. tostring(npc))
    return nil
  end
  npc.coopPartner = true
  npc.passable = true
  npc.hidden = false
  npc.mapId = ow.map.id
  npc.progress = 0
  npc.spriteName = spriteId
  -- position is driven only by CoopManager.updatePartnerRender
  npc.update = function() end
  applyPartnerPalette(npc)
  return npc
end

-- Smooth the partner toward the latest snapshot.  Snapshots arrive ~15 a
-- second; drawing them raw made the sprite stutter and pop, and drawing
-- `moving` as a wall-clock flip-flop made it moonwalk.  Here the sprite
-- chases its target at walking speed (faster when it falls behind), and the
-- walk frame comes from the distance actually travelled, exactly the way a
-- local NPC's walk cycle does.
function CoopManager.updatePartnerRender(ow, dt)
  local partner = CoopManager.partner
  local game = getGame(ow)
  local ox, oy = partnerFrameOffset(ow)
  local fresh = (now() - (partner.lastSeen or 0)) < 30
  if not ox or not fresh then
    CoopManager.removePartnerNpc(ow)
    CoopManager.render = nil
    return
  end

  local targetX = (partner.px or 0) + ox
  local targetY = (partner.py or 0) + oy
  local r = CoopManager.render
  local activeMap = ow.map.id

  if r and r.mapId ~= activeMap then
    -- WE crossed a seam: re-express the drawn position in the new map's
    -- frame using the old map's offset, so the partner does not jump
    local shifted = false
    for _, nb in ipairs(ow.neighbors or {}) do
      if nb.map and mapsMatch(nb.map.id, r.mapId) then
        r.x = r.x + (nb.ox or 0)
        r.y = r.y + (nb.oy or 0)
        shifted = true
        break
      end
    end
    if not shifted then r = nil end
  end

  if not r then
    r = { x = targetX, y = targetY, progress = 0 }
  end
  r.mapId = activeMap

  local dx, dy = targetX - r.x, targetY - r.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local moved = 0
  if dist > 48 then
    -- warp, fly, fall or a long lag spike: snap rather than slide through walls
    r.x, r.y = targetX, targetY
  elseif dist > 0.01 then
    local speed = math.max(60, dist * 9)
    local step = math.min(dist, speed * (dt or 0.016))
    r.x = r.x + dx / dist * step
    r.y = r.y + dy / dist * step
    moved = step
  end

  if moved > 0 or partner.moving then
    r.progress = (r.progress or 0) + moved
  elseif dist <= 0.01 then
    r.progress = 0
  end
  CoopManager.render = r

  -- the entity itself
  local npc = CoopManager.partnerNpc
  local spriteId = partner.sprite
  if not knownSprite(game, spriteId) then spriteId = defaultPlayerSprite(ow, game) end
  if npc and npc.mapId ~= activeMap then
    CoopManager.removePartnerNpc(ow)
    npc = nil
  end
  if not npc then
    npc = makePartnerNpc(ow, game, spriteId)
    if not npc then return end
    CoopManager.partnerNpc = npc
  elseif npc.spriteName ~= spriteId then
    npc.def.sprite = spriteId
    npc.spriteName = spriteId
    pcall(npc.refreshSprite, npc, game.data)
    applyPartnerPalette(npc)
  end

  ow.npcs = ow.npcs or {}
  ow.entities = ow.entities or {}
  ensureListed(ow.npcs, npc)
  ensureListed(ow.entities, npc)

  local rx, ry = math.floor(r.x + 0.5), math.floor(r.y + 0.5)
  npc.hidden = false
  npc.px = rx
  npc.py = ry + (partner.hopY or 0)
  npc.cellX = math.floor((rx + 8) / 16)
  npc.cellY = math.floor((ry + 8) / 16)
  npc.facing = partner.facing or "down"
  local walking = (moved > 0) or (partner.moving and dist > 0.01)
  npc.moving = walking
  npc.progress = math.floor(r.progress or 0)
  npc.stepFlip = math.floor((r.progress or 0) / 16) % 2 == 1

  -- ...and their walking Pokemon behind them
  local okF, FollowMon = pcall(require, "src.follow.FollowMon")
  if okF then
    local info = (not partner.surfing) and partner.follow or nil
    pcall(FollowMon.updateRemote, game, ow, dt, info, ox, oy)
  end
end

-- kept for callers/tests that still ask for it by the old name
local function ensurePartnerNpc(ow)
  CoopManager.updatePartnerRender(ow, 0)
end
CoopManager.ensurePartnerNpc = ensurePartnerNpc

CMI.partnerFrameOffset = partnerFrameOffset
end

return M
