-- src/coop/CoopWorld.lua
-- ONE WORLD FOR TWO (1.20, capability "world.share").
--
-- 1. STRENGTH BOULDERS ARE THE SAME ROCK ON BOTH SCREENS.  A boulder one
--    player pushes moves in the partner's copy too, when the partner is on
--    that map: the partner's own engine pushes it (sound, dust, a hole it
--    falls through and that hole's script included), so it ends on the
--    same cell.  A player who walks onto a map where the partner already
--    is asks for the partner's boulders and finds them where the partner
--    left them.  A boulder is never pushed onto the cell the partner stands
--    on (they are in the way, as anyone would be).
--
-- 2. THE PARTNER'S HMs WORK FOR YOU WHEN THEY ARE CLOSE.  With the partner
--    on the same map and at most RANGE (8) steps away, a field move your
--    own party can't use -- no Pokemon knows it, or your badge for it is
--    missing -- is used with theirs, when THEIR game lets them: their
--    Pokemon knows it and they hold the badge in their own save.  Every
--    field-move prompt in the engine asks one function (partyKnows), so CUT
--    trees, ROCK SMASH rocks, STRENGTH boulders, SURF, WHIRLPOOL and
--    WATERFALL all take the partner's Pokemon there.  FLASH is a party-menu
--    move with no prompt to answer, so it is shared the other way round: a
--    cave the partner has lit (their FLASH, their badge) lights for you too
--    when they are within the same 8 steps.
--
-- Nobody's party changes: what the borrower's game holds is a stand-in
-- (name, species, level, the one move) built from what the partner sent.
-- A partner without the capability (1.6.x) gets none of these messages and
-- nothing here acts: each game keeps its own boulders and its own HMs.
--
-- Wire, all as coop_world { k = ... }:
--   hms   { hms = { [MOVE] = { n, s, l } }, lit }   what our own game can use
--   lent  { move }                                  "MOCHI borrows your CUT"
--   push  { map, i, x, y, dir }                     boulder object i, from x,y
--   req   { map }                                   "send me your boulders"
--   rocks { map, list = { { i, x, y } } }           the boulders on that map
--
-- How it sits in the engine (lib/Hooks.lua): OverworldState.partyKnows and
-- OverworldState.checkBoulderPush are wrapped and hand over to partyKnows()
-- and checkBoulderPush() below.

local CoopManager = require("src.coop.CoopManager")

local CoopWorld = {}

CoopWorld.CAP = "world.share"
CoopManager.registerCap(CoopWorld.CAP)

CoopWorld.RANGE = 8
-- the field moves a partner can lend
CoopWorld.MOVES = { "CUT", "FLASH", "ROCK_SMASH", "STRENGTH", "SURF", "WATERFALL", "WHIRLPOOL" }
local LENDABLE = {}
for _, m in ipairs(CoopWorld.MOVES) do LENDABLE[m] = true end
CoopWorld.LENDABLE = LENDABLE

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local PARTNER_FRESH = 3.0
local NOTE_EVERY = 4.0   -- a lend's status line, at most this often per move
local MAX_PENDING = 16

-- session state (reset on a new link)
CoopWorld.partnerHms = nil   -- [MOVE] = { n = name, s = species, l = level }
CoopWorld.partnerLit = false -- the partner's FLASH is lit where they stand
CoopWorld.pending = {}       -- boulder pushes waiting for the overworld
CoopWorld.ownOnly = false    -- partyKnows answers for our own party only
CoopWorld.replaying = false  -- a push that came from the partner is running

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end
CoopWorld.now = now

local function send(msg)
  if CoopManager.connected and CoopManager.net then
    msg.type = "coop_world"
    CoopManager.net:send(msg)
  end
end

-- both copies have it, and the link is up
function CoopWorld.on()
  return CoopManager.connected == true and CoopManager.bothHave(CoopWorld.CAP)
end

local function partnerName()
  return tostring(CoopManager.partner and CoopManager.partner.name or "PARTNER")
end

local function moveName(game, move)
  local def = game and game.data and game.data.moves and game.data.moves[move]
  return (def and def.name) or (move:gsub("_", " "))
end

local function getGame(ow)
  return (ow and ow.game) or CoopManager.getGame(ow)
end

local function isPushable(npc)
  if type(npc) ~= "table" or not npc.def then return false end
  local ok, Map = pcall(require, "src.world.Map")
  return ok and Map.isPushable and Map.isPushable(npc.def) == true or false
end
CoopWorld.isPushable = isPushable

-- ---------------------------------------------------------------------
-- where the partner is
-- ---------------------------------------------------------------------

-- steps between the partner and us, when they are on this map and their
-- position is fresh; nil otherwise
function CoopWorld.partnerSteps(ow)
  local partner = CoopManager.partner
  if not (partner and ow and ow.map and ow.player) then return nil end
  if not CoopManager.mapsMatch(partner.map, ow.map.id) then return nil end
  if (now() - (partner.lastSeen or 0)) > PARTNER_FRESH then return nil end
  local p = ow.player
  local dx = math.abs((tonumber(partner.cx) or 0) - (p.cellX or 0))
  local dy = math.abs((tonumber(partner.cy) or 0) - (p.cellY or 0))
  return dx + dy
end

function CoopWorld.near(ow)
  local steps = CoopWorld.partnerSteps(ow)
  return steps ~= nil and steps <= CoopWorld.RANGE
end

-- ---------------------------------------------------------------------
-- 2. the partner's HMs
-- ---------------------------------------------------------------------

-- what our own game can use, for the partner: the engine's own answer
-- (party, badge), never what the partner lent us
function CoopWorld.ownHms(ow)
  local out = {}
  if not (ow and ow.partyKnows) then return out end
  local game = getGame(ow)
  CoopWorld.ownOnly = true
  for _, move in ipairs(CoopWorld.MOVES) do
    local ok, mon = pcall(ow.partyKnows, ow, move)
    if ok and type(mon) == "table" then
      local def = game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
      out[move] = {
        n = tostring(mon.nickname or (def and def.name) or mon.species or "POKéMON"),
        s = type(mon.species) == "string" and mon.species or nil,
        l = tonumber(mon.level) or nil,
      }
    end
  end
  CoopWorld.ownOnly = false
  return out
end

local function signature(hms, lit)
  local parts = { lit and "lit" or "dark" }
  for _, move in ipairs(CoopWorld.MOVES) do
    local h = hms[move]
    if h then parts[#parts + 1] = move .. "=" .. h.n .. "/" .. tostring(h.s) .. "/" .. tostring(h.l) end
  end
  return table.concat(parts, ";")
end
CoopWorld.signature = signature

-- our FLASH is up where we stand (a dark map we have lit)
local function ownLit(game, ow)
  return game and game.save and game.save.flashLit == true and ow and ow.dark ~= true or false
end

-- the partner's list, as received; anything malformed is dropped
function CoopWorld.onHms(msg)
  local list = {}
  if type(msg.hms) == "table" then
    for move, h in pairs(msg.hms) do
      if LENDABLE[move] and type(h) == "table" and type(h.n) == "string" and #h.n <= 24 then
        list[move] = { n = h.n, s = type(h.s) == "string" and #h.s <= 40 and h.s or nil,
                       l = tonumber(h.l) }
      end
    end
  end
  CoopWorld.partnerHms = list
  CoopWorld.partnerLit = msg.lit == true
end

-- the partner's Pokemon, as our game sees it for one field move
function CoopWorld.standIn(game, move, h)
  local species = h.s
  local known = species and game and game.data and game.data.pokemon and game.data.pokemon[species]
  return {
    species = known and species or nil,
    nickname = h.n,
    level = h.l or 1,
    hp = 1, maxHp = 1,
    moves = { { id = move, pp = 1 } },
    pkmLentBy = partnerName(),
  }
end

local noted = {}
-- a field move our own party can't use, from the partner's, or nil
function CoopWorld.lend(ow, move)
  if CoopWorld.ownOnly or not LENDABLE[move] or not CoopWorld.on() then return nil end
  local h = CoopWorld.partnerHms and CoopWorld.partnerHms[move]
  if not h or not CoopWorld.near(ow) then return nil end
  local game = getGame(ow)
  -- the borrower is told, and so is the partner (not again for every
  -- question the same prompt asks, nor for a surfer crossing into a map)
  local t = now()
  local surfing = move == "SURF" and ow.player and ow.player.surfing
  if not surfing and (t - (noted[move] or -NOTE_EVERY)) >= NOTE_EVERY then
    noted[move] = t
    CoopManager.showStatus(("%s lends you %s"):format(partnerName(), moveName(game, move)), 3)
    send({ k = "lent", move = move })
  end
  return CoopWorld.standIn(game, move, h)
end

-- OverworldState.partyKnows, wrapped: our own party first, always
function CoopWorld.partyKnows(original, ow, move, ...)
  local mon = original(ow, move, ...)
  if mon ~= nil or CoopWorld.ownOnly then return mon end
  local ok, lent = pcall(CoopWorld.lend, ow, move)
  if ok and lent then return lent end
  return mon
end

function CoopWorld.onLent(ow, msg)
  if not LENDABLE[msg.move] then return end
  CoopManager.showStatus(("%s borrows your %s"):format(partnerName(), moveName(getGame(ow), msg.move)), 3)
end

-- the partner's FLASH, for a dark map of ours they are near
function CoopWorld.tickFlash(game, ow)
  if not (CoopWorld.partnerLit and ow and ow.dark == true and game and game.save) then return false end
  if not CoopWorld.ready(game, ow) or not CoopWorld.near(ow) then return false end
  game.save.flashLit = true
  if ow.setDark then ow:setDark(false) else ow.dark = false end
  pcall(function()
    game.stack:push(require("src.render.Transition").whiteFlash(game))
  end)
  CoopManager.showStatus(("%s lights the area with %s"):format(partnerName(), moveName(game, "FLASH")), 3)
  return true
end

-- ---------------------------------------------------------------------
-- 1. Strength boulders
-- ---------------------------------------------------------------------

-- free to move a boulder on: the overworld is the screen
function CoopWorld.ready(game, ow)
  if not (game and ow and ow.map and ow.player) then return false end
  local stack = game.stack
  local top = stack and stack.top and stack:top()
  if top ~= ow then return false end
  if ow.transitioning or ow.inBattle then return false end
  return true
end

local function blocksCell(e, x, y)
  return type(e) == "table" and ((e.cellX == x and e.cellY == y) or (e.targetX == x and e.targetY == y))
end

-- the partner stands (or is stepping) on x, y in our copy of this map
function CoopWorld.partnerOn(ow, x, y)
  local partner = CoopManager.partner
  if not (partner and ow and ow.map and CoopManager.mapsMatch(partner.map, ow.map.id)) then return false end
  if (now() - (partner.lastSeen or 0)) > PARTNER_FRESH then return false end
  return (partner.cx == x and partner.cy == y) or (partner.tx == x and partner.ty == y)
end

-- OverworldState.checkBoulderPush, wrapped
function CoopWorld.checkBoulderPush(original, ow, dir, ...)
  if CoopWorld.replaying or not CoopWorld.on() then return original(ow, dir, ...) end
  local d = DIRS[dir]
  local p = ow and ow.player
  local npc, fx, fy
  if d and p and ow.npcAtCell then
    fx, fy = p.cellX + d[1], p.cellY + d[2]
    local okN, found = pcall(ow.npcAtCell, ow, fx, fy)
    if okN and isPushable(found) and not found.moving then npc = found end
  end
  -- the partner is in the way: the boulder does not go over them
  if npc and CoopWorld.partnerOn(ow, fx + d[1], fy + d[2]) then
    ow.boulderTried = nil
    return false
  end
  local pushed = original(ow, dir, ...)
  if pushed and npc and npc.def and ow.map then
    send({ k = "push", map = ow.map.id, i = npc.def.index, x = fx, y = fy, dir = dir })
  end
  return pushed
end

-- put a boulder on x, y with no animation (the way a script's moveobject does)
local function place(npc, x, y)
  npc.cellX, npc.cellY = x, y
  npc.px, npc.py = x * 16, y * 16
  npc.moving = false
  npc.targetX, npc.targetY = nil, nil
end
CoopWorld.place = place

-- nothing of ours on x, y: not us, not another object
local function cellFree(ow, x, y, npc)
  if blocksCell(ow.player, x, y) then return false end
  for _, e in ipairs(ow.entities or ow.npcs or {}) do
    if e ~= npc and e ~= ow.player and not e.passable and not (e.hidden and not e.buried)
       and not (e.def and e.def.passable) and blocksCell(e, x, y) then
      return false
    end
  end
  return true
end

-- the partner's push, in our copy: "pushed" (our engine did it), "placed"
-- (put straight on its cell), "already" (it is there) or "skip"
function CoopWorld.applyPush(ow, msg)
  local d = DIRS[msg.dir]
  if not (d and ow and ow.map and ow.npcByIndex) then return "skip" end
  if not CoopManager.mapsMatch(ow.map.id, msg.map) then return "skip" end
  local npc = ow:npcByIndex(msg.i)
  if not (isPushable(npc) and not (npc.hidden and not npc.buried)) then return "skip" end
  local tx, ty = msg.x + d[1], msg.y + d[2]
  if npc.cellX == tx and npc.cellY == ty and not npc.moving then return "already" end
  if blocksCell(ow.player, tx, ty) then return "skip" end
  if npc.moving or npc.cellX ~= msg.x or npc.cellY ~= msg.y then
    if not npc.moving and cellFree(ow, tx, ty, npc) then place(npc, tx, ty) return "placed" end
    return "skip"
  end
  -- OUR ENGINE PUSHES IT, from where the partner stood, armed as theirs
  -- was: the sound, the dust, a pit and its script are this game's own
  local p = ow.player
  local px, py, armed = p.cellX, p.cellY, ow.strengthActive
  p.cellX, p.cellY = msg.x - d[1], msg.y - d[2]
  ow.strengthActive = true
  ow.boulderTried = npc -- Red / Blue / Yellow push on the second bump
  CoopWorld.replaying = true
  local ok, pushed = pcall(ow.checkBoulderPush, ow, msg.dir)
  CoopWorld.replaying = false
  p.cellX, p.cellY = px, py
  ow.strengthActive = armed
  if ok and pushed then return "pushed" end
  ow.boulderTried = nil
  if cellFree(ow, tx, ty, npc) then place(npc, tx, ty) return "placed" end
  return "skip"
end

function CoopWorld.onPush(ow, msg)
  if type(msg.map) ~= "string" or not DIRS[msg.dir] then return end
  if type(msg.i) ~= "number" or type(msg.x) ~= "number" or type(msg.y) ~= "number" then return end
  local q = CoopWorld.pending
  if #q >= MAX_PENDING then table.remove(q, 1) end
  q[#q + 1] = { map = msg.map, i = msg.i, x = msg.x, y = msg.y, dir = msg.dir }
  CoopWorld.flushPending(getGame(ow), ow)
end

-- the pushes that came in, applied once the overworld is the screen; one
-- for another map is dropped (the map is not ours any more)
function CoopWorld.flushPending(game, ow)
  local q = CoopWorld.pending
  if #q == 0 or not (ow and ow.map) then return end
  if not CoopWorld.ready(game, ow) then return end
  while #q > 0 do
    local msg = table.remove(q, 1)
    if CoopManager.mapsMatch(msg.map, ow.map.id) then
      local ok, err = pcall(CoopWorld.applyPush, ow, msg)
      if not ok then require("src.coop.CoopLog").error("WORLD", "boulder push failed: " .. tostring(err)) end
    end
  end
end

-- the boulders on our map, for a partner who just walked in
function CoopWorld.rocks(ow)
  local list = {}
  for _, npc in ipairs((ow and ow.npcs) or {}) do
    if isPushable(npc) and not (npc.hidden and not npc.buried) and npc.def.index then
      local x, y = npc.cellX, npc.cellY
      if npc.moving and npc.targetX then x, y = npc.targetX, npc.targetY end
      list[#list + 1] = { i = npc.def.index, x = x, y = y }
    end
  end
  table.sort(list, function(a, b) return a.i < b.i end)
  return list
end

function CoopWorld.onReq(ow, msg)
  if not (ow and ow.map and CoopManager.mapsMatch(ow.map.id, msg.map)) then return end
  send({ k = "rocks", map = ow.map.id, list = CoopWorld.rocks(ow) })
end

-- the partner's boulders, on the map we just walked onto
function CoopWorld.applyRocks(ow, msg)
  if not (ow and ow.map and ow.npcByIndex and CoopManager.mapsMatch(ow.map.id, msg.map)) then return 0 end
  if type(msg.list) ~= "table" then return 0 end
  local moved = 0
  for i = 1, math.min(#msg.list, 64) do
    local r = msg.list[i]
    if type(r) == "table" and type(r.i) == "number" and type(r.x) == "number" and type(r.y) == "number" then
      local npc = ow:npcByIndex(r.i)
      if isPushable(npc) and not npc.moving and (npc.cellX ~= r.x or npc.cellY ~= r.y)
         and cellFree(ow, r.x, r.y, npc) then
        place(npc, r.x, r.y)
        moved = moved + 1
      end
    end
  end
  return moved
end

-- ---------------------------------------------------------------------
-- the link
-- ---------------------------------------------------------------------

CoopManager.handlers.coop_world = function(ow, msg)
  if not CoopWorld.on() then return end
  local k = msg.k
  if k == "hms" then CoopWorld.onHms(msg)
  elseif k == "lent" then CoopWorld.onLent(ow, msg)
  elseif k == "push" then CoopWorld.onPush(ow, msg)
  elseif k == "req" then CoopWorld.onReq(ow, msg)
  elseif k == "rocks" then CoopWorld.applyRocks(ow, msg)
  end
end

CoopWorld.state = { serial = nil, sent = nil, timer = 0, map = nil, npcs = nil }

CoopManager.onTick("world", function(dt, game, ow)
  ow = ow or (game and game.overworld)
  local st = CoopWorld.state
  if st.serial ~= CoopManager.linkSerial then
    -- a new link: nothing of the last partner's is kept
    st.serial = CoopManager.linkSerial
    st.sent, st.timer, st.map, st.npcs = nil, 0, nil, nil
    CoopWorld.partnerHms, CoopWorld.partnerLit = nil, false
    CoopWorld.pending = {}
  end
  if not (CoopWorld.on() and ow and ow.map) then return end
  -- walked onto a map -- or the same one loaded again, which puts every
  -- object back where the map has it: the partner, if there, says where
  -- its boulders are
  if st.map ~= ow.map or st.npcs ~= ow.npcs then
    st.map, st.npcs = ow.map, ow.npcs
    CoopWorld.pending = {}
    send({ k = "req", map = ow.map.id })
  end
  CoopWorld.flushPending(game, ow)
  -- what we can lend, whenever it changes (party, badges, FLASH)
  st.timer = st.timer - dt
  if st.timer <= 0 then
    st.timer = 1
    local hms = CoopWorld.ownHms(ow)
    local lit = ownLit(game, ow)
    local sig = signature(hms, lit)
    if sig ~= st.sent then
      st.sent = sig
      send({ k = "hms", hms = hms, lit = lit })
    end
  end
  CoopWorld.tickFlash(game, ow)
end)

return CoopWorld
