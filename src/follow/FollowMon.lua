-- THE LEAD POKEMON WALKS BEHIND YOU, the way HeartGold / SoulSilver's does,
-- in Gold, Silver and Crystal.
--
-- WHO: the first party Pokemon that is neither fainted nor an egg (HGSS's
-- GetFirstAliveMonInParty); nobody when every one has fainted.
--
-- WHAT IT LOOKS LIKE: its party menu icon, the same SPRITE_MON_### sheet the
-- cartridge puts on its overworld Pokemon (the Lake of Rage Gyarados):
-- two frames that bob on their own clock, a little faster while it walks,
-- mirrored when it heads right. The sheets come from the player's own ROM
-- import; the mod draws nothing of its own.
--
-- HOW IT MOVES: Yellow's Pikachu's trail (src/world/PikachuFollower.lua),
-- which the engine already calls on every map load, every frame and every
-- seam crossing -- lib/Hooks.lua wraps those calls, so the engine's own
-- integration (carrying it over a connection, rebasing it) works for this
-- follower too. It is sent to the cell the player is vacating the frame the
-- step is committed, walks at the player's step length (half when it fell
-- two cells behind), never blocks the player, and snaps back when it ends up
-- more than six cells away. Hidden on the bike and while surfing.
--
-- A SHINY ONE SPARKLES every few seconds (the partner sees it too).
--
-- IT FINDS THINGS, the way HGSS's does: a friendly one (happiness 100+)
-- sometimes picks something up as you walk -- a "!" over it says so -- and
-- hands it over when you talk to it.  What it finds grows with your badges.
-- The find waits in the save (save.pkmFollowerFind) until you take it.
--
-- IN CO-OP: coop_pos carries `fol` (sheet + pixel position), and the
-- partner's copy draws it behind the partner's avatar (FollowMon.updateRemote).
--
-- Gen 2 only: Gen 1 has no per-species overworld icons, and Yellow already
-- has its own Pikachu.

local FollowMon = {}

local INDEX = 987            -- synthetic object index (the partner is 988)
local REMOTE_INDEX = 986
local FAR = 6

-- the MODS panel's switch (main.lua defines the row)
FollowMon.enabled = function() return true end

local function isEgg(mon) return mon.isEgg or mon.egg end

function FollowMon.lead(save)
  for i, mon in ipairs((save and save.party) or {}) do
    if not isEgg(mon) and (tonumber(mon.hp) or 0) > 0 then return mon, i end
  end
  return nil
end

-- SPRITE_MON_158 for SPECIES_158, if this cartridge has that sheet
local function spriteFor(game, mon)
  local dex = mon and tonumber(tostring(mon.species):match("^SPECIES_(%d+)$"))
  if not dex then return nil end
  local key = ("SPRITE_MON_%03d"):format(dex)
  local sprites = game and game.data and game.data.sprites
  if sprites and sprites[key] then return key end
  return nil
end
FollowMon.spriteFor = spriteFor

local function shouldShow(game, ow)
  if not FollowMon.enabled() then return nil end
  local save = game and game.save
  if not (save and ow and ow.player and ow.map) then return nil end
  if save.onBike or ow.player.surfing then return nil end
  local mon = FollowMon.lead(save)
  return mon and spriteFor(game, mon), mon
end

local function find(ow)
  for i, npc in ipairs((ow and ow.npcs) or {}) do
    if npc.pkmFollower then return npc, i end
  end
  return nil
end
FollowMon.current = function(ow) return (find(ow)) end

local function unlist(ow, flag)
  for _, name in ipairs({ "npcs", "entities" }) do
    local list = ow and ow[name]
    if list then
      for i = #list, 1, -1 do
        if type(list[i]) == "table" and list[i][flag] then table.remove(list, i) end
      end
    end
  end
end

-- SHINY SPARKLE: a four-point star at two corners in turn, for a fifth of a
-- second every SPARKLE_EVERY seconds
FollowMon.SPARKLE_EVERY = 2.5
local SPARKLE_CORNERS = { { 1, 1 }, { 13, 3 }, { 3, 12 }, { 12, 13 } }
local function drawSparkle(x, y, t)
  local phase = t % FollowMon.SPARKLE_EVERY
  if phase > 0.4 then return end
  local c = SPARKLE_CORNERS[(math.floor(t / FollowMon.SPARKLE_EVERY) * 2 + (phase > 0.2 and 1 or 0)) % 4 + 1]
  local sx, sy = x + c[1], y + c[2]
  local g = love.graphics
  g.setColor(1, 1, 0.55, 1)
  g.rectangle("fill", sx, sy - 2, 1, 5)
  g.rectangle("fill", sx - 2, sy, 5, 1)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", sx, sy - 1, 1, 3)
  g.rectangle("fill", sx - 1, sy, 3, 1)
end

-- the icon's two frames, mirrored for a right turn: an icon has no facings
local function drawIcon(self, camX, camY)
  local sprite, px, py = self:pose()
  if not sprite then return end
  local t = love.timer and love.timer.getTime() or 0
  local frame = math.floor(t * (self.moving and 8 or 4)) % 2
  sprite:drawFixedFrame(px, py, camX, camY, frame, self.facing == "right")
  local x = math.floor(px - camX)
  local y = math.floor(py - camY) - 4
  if self.pkmShiny then drawSparkle(x, y, t) end
  if self.pkmFound then
    -- the field's own "!" (CoopEmotes: the cartridge's bubble, or the drawn
    -- one when no ROM was imported), hung where the field hangs a trainer's
    local age = t - (self.pkmFoundSince or t)
    pcall(require("src.coop.CoopEmotes").draw, self.pkmGame, "exclaim", x + 8, y + 16, age)
  end
end

local function makeNpc(game, ow, spriteId, x, y, facing, index, name)
  local NPC = require("src.world.NPC")
  local ok, npc = pcall(NPC.new, game.data, ow.map.id, {
    index = index, name = name, sprite = spriteId,
    movement = "STAY", range = "NONE", x = x, y = y,
  })
  if not ok or not npc then return nil end
  npc.passable = true -- never blocks a step (Collision.occupied)
  npc.facing = facing or "down"
  npc.spriteName = spriteId
  npc.draw = drawIcon
  return npc
end

local function list(ow, npc)
  ow.npcs = ow.npcs or {}
  ow.entities = ow.entities or {}
  table.insert(ow.npcs, npc)
  table.insert(ow.entities, npc)
end

-- behind the player when that cell is walkable, else the player's own cell
-- (it trails out on the next step)
local function spawnCell(ow)
  local p = ow.player
  local dx = p.facing == "left" and 1 or p.facing == "right" and -1 or 0
  local dy = p.facing == "up" and 1 or p.facing == "down" and -1 or 0
  local bx, by = p.cellX + dx, p.cellY + dy
  if ow.map:inBounds(bx, by) and ow.map:isWalkableCell(bx, by) then
    return bx, by
  end
  return p.cellX, p.cellY
end

local function spawn(game, ow, spriteId)
  local x, y = spawnCell(ow)
  local npc = makeNpc(game, ow, spriteId, x, y, ow.player.facing, INDEX, "PKM_FOLLOWER")
  if not npc then return nil end
  npc.pkmFollower = true
  list(ow, npc)
  ow.pkmFollowTrail = { x = ow.player.cellX, y = ow.player.cellY }
  return npc
end

-- after PikachuFollower.onMapEntered: a connection crossing hands the live
-- follower back (opts.keepPikachu, via the wrapped `current`); a warp
-- respawns it behind the player
function FollowMon.onMapEntered(game, ow, opts)
  unlist(ow, "pkmFollower")
  local spriteId = shouldShow(game, ow)
  if not spriteId then return end
  local keep = opts and opts.keepPikachu
  if type(keep) == "table" and keep.pkmFollower then
    list(ow, keep)
    return
  end
  spawn(game, ow, spriteId)
end

-- the seam translation crossConnection gave the player
function FollowMon.rebase(ow, dx, dy)
  local npc = find(ow)
  if npc then
    npc.cellX, npc.cellY = npc.cellX + dx, npc.cellY + dy
    npc.px, npc.py = npc.px + dx * 16, npc.py + dy * 16
    if npc.targetX then npc.targetX = npc.targetX + dx end
    if npc.targetY then npc.targetY = npc.targetY + dy end
    if npc.goalX then npc.goalX = npc.goalX + dx end
    if npc.goalY then npc.goalY = npc.goalY + dy end
  end
  local trail = ow.pkmFollowTrail
  if trail then trail.x, trail.y = trail.x + dx, trail.y + dy end
end

-- once a frame, after the engine's npc loop (PikachuFollower.update)
function FollowMon.update(game, ow)
  if not (ow and ow.player and ow.map) then return end
  local spriteId = shouldShow(game, ow)
  local npc = find(ow)
  if not spriteId then
    if npc then unlist(ow, "pkmFollower") end
    return
  end
  if npc and npc.spriteName ~= spriteId then
    -- the lead changed (a swap in the party menu, a faint): new sheet, same spot
    npc.def.sprite = spriteId
    npc.spriteName = spriteId
    pcall(npc.refreshSprite, npc, game.data)
  end
  if not npc then
    npc = spawn(game, ow, spriteId)
    if not npc then return end
  end
  local lead = FollowMon.lead(game.save)
  npc.pkmShiny = FollowMon.isShiny(lead)
  local found = game.save.pkmFollowerFind ~= nil
  if found and not npc.pkmFound then npc.pkmFoundSince = love.timer and love.timer.getTime() or 0 end
  npc.pkmFound, npc.pkmGame = found, game
  local p = ow.player
  local trail = ow.pkmFollowTrail
  if not trail then
    trail = { x = p.cellX, y = p.cellY }
    ow.pkmFollowTrail = trail
  end
  -- queued the frame the player COMMITS a step, so it walks into the cell
  -- being vacated and rests one cell behind (PikachuFollower, #410)
  local destX = p.targetX or p.cellX
  local destY = p.targetY or p.cellY
  if destX ~= trail.x or destY ~= trail.y then
    npc.goalX, npc.goalY = trail.x, trail.y
    trail.x, trail.y = destX, destY
    FollowMon.onStep(game, lead)
  end
  if npc.moving or not npc.goalX then return end
  local gx, gy = npc.goalX, npc.goalY
  if npc.cellX == gx and npc.cellY == gy then
    npc.goalX, npc.goalY = nil, nil
    return
  end
  local far = math.abs(npc.cellX - gx) + math.abs(npc.cellY - gy)
  if far > FAR then
    -- a warp, a forced slide, a ledge chain: snap rather than walk through walls
    npc.cellX, npc.cellY = gx, gy
    npc.px, npc.py = gx * 16, gy * 16
    npc.goalX, npc.goalY = nil, nil
    return
  end
  local dir
  if npc.cellX < gx then dir = "right"
  elseif npc.cellX > gx then dir = "left"
  elseif npc.cellY < gy then dir = "down"
  else dir = "up" end
  npc.facing = dir
  npc.targetX = npc.cellX + (dir == "right" and 1 or dir == "left" and -1 or 0)
  npc.targetY = npc.cellY + (dir == "down" and 1 or dir == "up" and -1 or 0)
  local stepLen = p.stepFramesCur or p.stepFrames or 16
  if far > 1 then stepLen = math.max(1, math.floor(stepLen / 2)) end
  npc.stepFrames = stepLen
  npc.moving = true
  npc.progress = 0
  -- this frame's npc loop already ran: burn the step's first frame now, or it
  -- trails a pixel further every tile
  npc:update(ow.map, ow.entities)
end

function FollowMon.isShiny(mon)
  if not mon then return false end
  local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
  if not (ok and Pokemon.isShiny) then return mon.shiny == true end
  local okS, shiny = pcall(Pokemon.isShiny, mon)
  return okS and shiny == true
end

-- ------------------------------------------------------------ finding

-- one step in FIND_ONE_IN, for a lead this friendly or more
FollowMon.FIND_ONE_IN = 192
FollowMon.FIND_HAPPINESS = 100
-- { item key, weight, badges needed }
FollowMon.FINDS = {
  { "POTION", 20, 0 }, { "POKE_BALL", 14, 0 }, { "BERRY", 14, 0 },
  { "ANTIDOTE", 7, 0 }, { "PARLYZ_HEAL", 6, 0 }, { "AWAKENING", 6, 0 },
  { "PSNCUREBERRY", 6, 0 }, { "PRZCUREBERRY", 6, 0 }, { "REPEL", 7, 0 },
  { "ESCAPE_ROPE", 4, 0 }, { "TINYMUSHROOM", 4, 0 }, { "NUGGET", 1, 0 },
  { "SUPER_POTION", 14, 3 }, { "GREAT_BALL", 10, 3 }, { "SUPER_REPEL", 5, 3 },
  { "MINT_BERRY", 5, 3 }, { "ICE_BERRY", 3, 3 }, { "BURNT_BERRY", 3, 3 },
  { "BITTER_BERRY", 3, 3 }, { "PEARL", 3, 3 }, { "STARDUST", 3, 3 }, { "ETHER", 3, 3 },
  { "HYPER_POTION", 8, 6 }, { "ULTRA_BALL", 6, 6 }, { "MAX_REPEL", 3, 6 },
  { "REVIVE", 3, 6 }, { "FULL_HEAL", 4, 6 }, { "MIRACLEBERRY", 2, 6 },
  { "GOLD_BERRY", 3, 6 }, { "BIG_PEARL", 1, 6 }, { "STAR_PIECE", 1, 6 },
  { "BIG_MUSHROOM", 1, 6 },
}

-- item key -> this cartridge's item id (ITEM_018 for POTION in Gold)
local function itemByKey(data, key)
  for id, def in pairs((data and data.items) or {}) do
    if type(def) == "table" and def.key == key then return id end
  end
  return nil
end
FollowMon.itemByKey = itemByKey

local function badgeCount(game)
  local ok, n = pcall(function()
    return require("src.inventory.Badges").count(game.data, game.save)
  end)
  return ok and tonumber(n) or 0
end

function FollowMon.rollFind(game, rand)
  rand = rand or math.random
  local badges = badgeCount(game)
  local pool, total = {}, 0
  for _, f in ipairs(FollowMon.FINDS) do
    if badges >= f[3] and itemByKey(game.data, f[1]) then
      pool[#pool + 1] = f
      total = total + f[2]
    end
  end
  if total <= 0 then return nil end
  local r = rand() * total
  for _, f in ipairs(pool) do
    r = r - f[2]
    if r <= 0 then return f[1] end
  end
  return pool[#pool][1]
end

function FollowMon.onStep(game, lead, rand)
  local save = game and game.save
  if not (save and lead) or save.pkmFollowerFind then return end
  if (tonumber(lead.happiness) or 70) < FollowMon.FIND_HAPPINESS then return end
  rand = rand or math.random
  if rand(FollowMon.FIND_ONE_IN) ~= 1 then return end
  local key = FollowMon.rollFind(game, rand)
  if key then save.pkmFollowerFind = { key = key } end
end

-- A on it with a find waiting: it hands it over
local function giveFind(game, name)
  local save = game.save
  local find = save.pkmFollowerFind
  local id = find and itemByKey(game.data, find.key)
  if not id then
    save.pkmFollowerFind = nil
    return nil
  end
  local def = game.data.items[id]
  local itemName = (def and def.name) or find.key
  local Strings = require("src.core.Strings")
  local ok, added = pcall(function()
    return require("src.inventory.Bag").add(save, id, 1, game.data)
  end)
  if ok and added ~= false then
    save.pkmFollowerFind = nil
    pcall(function() require("src.core.Sound").play(game.data, "Item") end)
    return Strings("%s found\n%s!"):format(name, itemName)
  end
  return Strings("%s found\n%s...\fBut the BAG\nis full."):format(name, itemName)
end

-- A on it: it turns to you, cries, and says how it feels (Gen 2 friendship)
function FollowMon.talk(game, ow, npc)
  local mon = FollowMon.lead(game.save)
  if not mon then return false end
  npc:facePlayer(ow.player)
  local def = game.data.pokemon and game.data.pokemon[mon.species]
  local name = mon.nickname or (def and def.name) or "It"
  pcall(function() require("src.core.Sound").playCry(game.data, mon.species) end)
  if game.save.pkmFollowerFind then
    local found = giveFind(game, name)
    if found then
      local TextBox = require("src.coop.CoopI18n").textBox()
      game.stack:push(TextBox.new(game, found))
      return true
    end
  end
  local h = tonumber(mon.happiness) or 70
  local Strings = require("src.core.Strings")
  -- a Gen 2 line is 18 characters and a name up to 10, so the name and at
  -- most seven more share the first line
  local line
  if h >= 200 then line = Strings("%s loves\nbeing with you!")
  elseif h >= 150 then line = Strings("%s is very\nhappy with you!")
  elseif h >= 100 then line = Strings("%s is\nhappily following.")
  elseif h >= 50 then line = Strings("%s is\nfollowing you.")
  else line = Strings("%s keeps\nits distance...") end
  local TextBox = require("src.coop.CoopI18n").textBox()
  game.stack:push(TextBox.new(game, line:format(name)))
  return true
end

-- --------------------------------------------------------------- co-op

-- what coop_pos carries about our follower: nil when there is none to see
function FollowMon.snapshot(ow)
  local npc = find(ow)
  if not npc or npc.hidden then return nil end
  return { s = npc.spriteName, px = npc.px, py = npc.py, f = npc.facing,
           m = npc.moving and true or nil, sh = npc.pkmShiny or nil }
end

FollowMon.remote = nil -- { x, y, mapId } smoothed draw position

function FollowMon.removeRemote(ow)
  unlist(ow, "pkmFollowerRemote")
  FollowMon.remote = nil
end

-- The partner's follower, drawn behind the partner's avatar. `info` is the
-- latest coop_pos `fol`; ox, oy the partner's map offset from ours (nil when
-- they are nowhere we can see). Smoothed toward each snapshot at walking
-- speed, like the avatar (CoopManager.updatePartnerRender).
function FollowMon.updateRemote(game, ow, dt, info, ox, oy)
  local npc
  for _, n in ipairs((ow and ow.npcs) or {}) do
    if n.pkmFollowerRemote then npc = n break end
  end
  if not (ox and type(info) == "table" and type(info.s) == "string"
          and game.data.sprites and game.data.sprites[info.s]) then
    if npc then FollowMon.removeRemote(ow) end
    return
  end
  local tx, ty = (tonumber(info.px) or 0) + ox, (tonumber(info.py) or 0) + oy
  local r = FollowMon.remote
  if not r or r.mapId ~= ow.map.id then r = { x = tx, y = ty } end
  r.mapId = ow.map.id
  local dx, dy = tx - r.x, ty - r.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local moved = 0
  if dist > 48 then
    r.x, r.y = tx, ty
  elseif dist > 0.01 then
    local step = math.min(dist, math.max(60, dist * 9) * (dt or 0.016))
    r.x, r.y = r.x + dx / dist * step, r.y + dy / dist * step
    moved = step
  end
  FollowMon.remote = r
  if npc and npc.mapId ~= ow.map.id then FollowMon.removeRemote(ow); npc = nil end
  if not npc then
    npc = makeNpc(game, ow, info.s, 0, 0, info.f, REMOTE_INDEX, "PKM_FOLLOWER_P2")
    if not npc then return end
    npc.pkmFollowerRemote = true
    npc.coopPartner = true -- CoopManager.removePartnerNpc takes it with the avatar
    npc.mapId = ow.map.id
    -- position is driven only from here
    npc.update = function() end
    list(ow, npc)
    FollowMon.remote = r
  elseif npc.spriteName ~= info.s then
    npc.def.sprite = info.s
    npc.spriteName = info.s
    pcall(npc.refreshSprite, npc, game.data)
  end
  local rx, ry = math.floor(r.x + 0.5), math.floor(r.y + 0.5)
  npc.px, npc.py = rx, ry
  npc.cellX, npc.cellY = math.floor((rx + 8) / 16), math.floor((ry + 8) / 16)
  npc.facing = info.f or "down"
  npc.moving = moved > 0 or info.m == true
  npc.pkmShiny = info.sh == true
end

return FollowMon
