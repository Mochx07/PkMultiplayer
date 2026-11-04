-- src/coop/mg/Treasure.lua
-- TREASURE HUNT (1.20, M3), a minigame on the frame (src/coop/CoopMinigame.lua).
--
-- Both players stand on the same map.  The shared seed picks one walkable
-- cell of it, the same on both copies; nothing marks it.  Each player hunts on
-- their own copy with a hint at the bottom of the screen (COLD / WARM / HOT, by
-- steps to the cell) and presses A standing on it.  The score is the time it
-- took (lowWins); the first to find it wins, and the other copy stops hunting
-- as soon as it hears the find.  Nobody finding it in time is a draw.
--
-- THE SAME CELL ON BOTH COPIES.  Each copy works the list out by itself, from
-- what both copies have alike:
--   * the map's own data, not the live map: the cells are read through a view
--     with the runtime patches (cut trees, script-shut doors, block swaps) left
--     out, so one player having cut a tree the other has not does not shift the
--     list by a cell;
--   * the cells joined to the player's by steps either way (a ledge hop counts
--     both ways), so both players, standing in the same part of the map,
--     get the same part -- and a cell behind a fence neither can reach is
--     never picked;
--   * no warps, water or the cells the map's people and signs start on;
--   * in index order (y, then x), and session:random picks one.
-- As a guard, the asker also sends its cell (coop_mg_treasure); a guest whose
-- own pick differs takes the asker's (and logs it), so the two can never be
-- hunting different cells for longer than one message.
--
-- No wild Pokemon during the hunt: the overworld the game runs on gets an
-- encounter roll that finds nothing, put back when the game ends.
local Treasure = {}

Treasure.ID = "treasure"
Treasure.DURATION = 120
Treasure.NOT_FOUND = 999       -- the score of a player who did not find it
Treasure.HOT = 3               -- steps: HOT up to here
Treasure.WARM = 8              -- ...WARM up to here, COLD past it
Treasure.MIN_CELLS = 24        -- a smaller area is no hunt
Treasure.heard = {}            -- the asker's cell, by session id

local DIRS = { { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }
local HINTS = { hot = "HOT!", warm = "WARM", cold = "COLD", away = "WRONG MAP" }

local function manager()
  local ok, CM = pcall(require, "src.coop.CoopManager")
  return ok and CM or nil
end
local function log(level, msg)
  pcall(function() require("src.coop.CoopLog")[level]("MINIGAME", msg) end)
end

-- ---------------------------------------------------------------------
-- the map, as both copies have it
-- ---------------------------------------------------------------------

-- the map without what this copy's scripts and field moves did to it
function Treasure.pristine(map)
  return setmetatable({ blockPatch = {}, collisionPatch = {}, elevationPatch = {}, shutCells = false },
                      { __index = map })
end

local function standable(map, x, y)
  if not map:inBounds(x, y) then return false end
  if not map:isWalkableCell(x, y) then return false end
  if map.isWaterCell and map:isWaterCell(x, y) then return false end
  if map.warpAtCell and map:warpAtCell(x, y) ~= nil then return false end
  return true
end

local function stepOk(Collision, map, x, y, dir, tx, ty)
  local mover = { cellX = x, cellY = y, surfing = false, facing = dir }
  local ok = Collision.mayEnter(map, {}, mover, tx, ty, dir)
  return ok == true
end

-- ledge hops off cell (x, y): the cells two ahead, Gen 1's pair rows
-- (field.ledges) and Gen 2's standing classes (field.ledgeHops)
local function hopsFrom(map, field, x, y)
  local out = {}
  if not field or not map.cellTile then return out end
  local standing = map:cellTile(x, y)
  local tileset = map.def and map.def.tileset
  for _, d in ipairs(DIRS) do
    local dir, dx, dy = d[1], d[2], d[3]
    local hop = false
    local allowed = field.ledgeHops and field.ledgeHops[standing]
    if allowed then
      for _, a in ipairs(allowed) do if a == dir then hop = true end end
    end
    if not hop and field.ledges and map:inBounds(x + dx, y + dy) then
      local front = map:cellTile(x + dx, y + dy)
      for _, l in ipairs(field.ledges) do
        if (l.tileset or "OVERWORLD") == tileset and l.facing == dir and l.input == dir
           and l.standingTile == standing and l.ledgeTile == front then
          hop = true
          break
        end
      end
    end
    if hop then out[#out + 1] = { x + 2 * dx, y + 2 * dy } end
  end
  return out
end

-- the walkable parts of a map: comp[index] = part number, parts[n] = sorted
-- list of indices.  index = y * width + x.
function Treasure.parts(map, field)
  local Collision = require("src.world.Collision")
  local W, H = map.widthCells, map.heightCells
  local ok = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if standable(map, x, y) then ok[y * W + x] = true end
    end
  end
  -- the hops, both ways
  local hop = {}
  local function link(a, b)
    hop[a] = hop[a] or {}
    hop[a][#hop[a] + 1] = b
  end
  for i in pairs(ok) do
    local x, y = i % W, math.floor(i / W)
    for _, h in ipairs(hopsFrom(map, field, x, y)) do
      local j = h[2] * W + h[1]
      if h[1] >= 0 and h[1] < W and ok[j] then link(i, j) link(j, i) end
    end
  end
  local comp, parts = {}, {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local start = y * W + x
      if ok[start] and not comp[start] then
        local n = #parts + 1
        local list, queue, head = {}, { start }, 1
        comp[start] = n
        while queue[head] do
          local i = queue[head]
          head = head + 1
          list[#list + 1] = i
          local cx, cy = i % W, math.floor(i / W)
          for _, d in ipairs(DIRS) do
            local tx, ty = cx + d[2], cy + d[3]
            local j = ty * W + tx
            if tx >= 0 and tx < W and ok[j] and not comp[j] then
              local back = ({ up = "down", down = "up", left = "right", right = "left" })[d[1]]
              if stepOk(Collision, map, cx, cy, d[1], tx, ty) or stepOk(Collision, map, tx, ty, back, cx, cy) then
                comp[j] = n
                queue[#queue + 1] = j
              end
            end
          end
          for _, j in ipairs(hop[i] or {}) do
            if not comp[j] then comp[j] = n queue[#queue + 1] = j end
          end
        end
        table.sort(list)
        parts[n] = list
      end
    end
  end
  return comp, parts
end

-- the cells the hunt may pick, in order, for a player standing at (sx, sy):
-- the part of the map joined to them, without the cells the map's people and
-- signs start on.  Falls back to the map's biggest part when theirs is tiny
-- (a player on a door mat or a ledge between parts).
function Treasure.candidates(liveMap, sx, sy, field)
  local map = Treasure.pristine(liveMap)
  local W = map.widthCells
  local comp, parts = Treasure.parts(map, field)
  local mine = comp[sy * W + sx]
  if not mine then
    for _, d in ipairs(DIRS) do
      local tx, ty = sx + d[2], sy + d[3]
      if tx >= 0 and tx < W and comp[ty * W + tx] then mine = comp[ty * W + tx] break end
    end
  end
  local list = mine and parts[mine]
  if not list or #list < Treasure.MIN_CELLS then
    local best
    for n, p in ipairs(parts) do
      if not best or #p > #parts[best] then best = n end
    end
    list = best and parts[best] or {}
  end
  local taken = {}
  local def = liveMap.def or {}
  for _, group in ipairs({ def.objects or {}, def.signs or {} }) do
    for _, o in ipairs(group) do
      if tonumber(o.x) and tonumber(o.y) then taken[o.y * W + o.x] = true end
    end
  end
  local out = {}
  for _, i in ipairs(list) do
    if not taken[i] then out[#out + 1] = { i % W, math.floor(i / W) } end
  end
  return out
end

function Treasure.pick(cells, session)
  if #cells == 0 then return nil end
  return cells[session:random(#cells)]
end

function Treasure.hint(dist)
  if dist == nil then return "away" end
  if dist <= Treasure.HOT then return "hot" end
  if dist <= Treasure.WARM then return "warm" end
  return "cold"
end

function Treasure.scoreText(v)
  v = tonumber(v)
  if not v or v <= 0 or v >= Treasure.NOT_FOUND then return "--" end
  return string.format("%.1fs", v)
end

-- ---------------------------------------------------------------------
-- no wild Pokemon while hunting
-- ---------------------------------------------------------------------

local function noEncounter() return nil end

local function calm(s, ow)
  if s.data.calmOw == ow then return end
  if s.data.calmOw and rawget(s.data.calmOw, "rollEncounter") == noEncounter then
    s.data.calmOw.rollEncounter = nil
  end
  s.data.calmOw = nil
  if type(ow) == "table" and rawget(ow, "rollEncounter") == nil then
    ow.rollEncounter = noEncounter
    s.data.calmOw = ow
  end
end

-- ---------------------------------------------------------------------
-- the game
-- ---------------------------------------------------------------------

local function field(game)
  return game and game.data and game.data.field
end

local function canStart(game, ow)
  local CM = manager()
  if not (ow and ow.map and ow.player) then return false, "Not here" end
  if CM and CM.partner and not (CM.mapsMatch and CM.mapsMatch(CM.partner.map, ow.map.id)) then
    return false, "Partner is far away"
  end
  if ow.player.surfing then return false, "Not while surfing" end
  local cells = Treasure.candidates(ow.map, ow.player.cellX, ow.player.cellY, field(game))
  if #cells < Treasure.MIN_CELLS then return false, "Too small here" end
  return true
end

local function start(s, game, ow)
  if not (ow and ow.map and ow.player) then error("no overworld") end
  local cells = Treasure.candidates(ow.map, ow.player.cellX, ow.player.cellY, field(game))
  local cell = Treasure.pick(cells, s)
  if not cell then error("no cell to hide the treasure in") end
  s.data.map, s.data.cx, s.data.cy, s.data.cells = ow.map.id, cell[1], cell[2], #cells
  s.data.own = { cell[1], cell[2] }
  s.score = Treasure.NOT_FOUND
  log("info", string.format("treasure: %s %d,%d of %d cells (%s)", tostring(s.data.map), cell[1], cell[2],
                            #cells, s.asker and "asker" or "guest"))
  local CM = manager()
  if s.asker and CM and CM.net then
    CM.net:send({ type = "coop_mg_treasure", mid = s.mid, map = s.data.map, cx = cell[1], cy = cell[2] })
  end
  calm(s, ow)
end

-- the guest checks its pick against the asker's
local function agree(s)
  if s.asker or s.data.matched ~= nil then return end
  local h = Treasure.heard[s.mid]
  if not h then return end
  Treasure.heard[s.mid] = nil
  local same = h.map == s.data.map and tonumber(h.cx) == s.data.cx and tonumber(h.cy) == s.data.cy
  s.data.matched = same
  if not same then
    log("warn", string.format("treasure: our cell %s %d,%d is not the asker's %s %s,%s; taking theirs",
                              tostring(s.data.map), s.data.cx, s.data.cy, tostring(h.map), tostring(h.cx), tostring(h.cy)))
    s.data.map, s.data.cx, s.data.cy = h.map, tonumber(h.cx) or s.data.cx, tonumber(h.cy) or s.data.cy
  end
end

local function update(s, dt, game, ow)
  agree(s)
  local CM = manager()
  if ow then calm(s, ow) end
  -- the partner found it: the hunt is over for us too
  if s.partnerFinal and s.partnerFinal < Treasure.NOT_FOUND then
    s.data.beaten = true
    if CM and CM.showStatus then
      local who = tostring(CM.partner and CM.partner.name or "PARTNER")
      CM.showStatus(who .. " found it!", 3)
    end
    s:finish()
    return
  end
  local p = ow and ow.player
  local here = p and ow.map and ow.map.id == s.data.map
  s.data.dist = here and (math.abs(p.cellX - s.data.cx) + math.abs(p.cellY - s.data.cy)) or nil
  s.data.hint = Treasure.hint(s.data.dist)
  local input = game and game.input
  if s.data.wasIdle and here and not p.moving and input and input.wasPressed and input:wasPressed("a") then
    if s.data.dist == 0 then
      s.data.found = true
      s:setScore(math.floor(s.t * 10 + 0.5) / 10)
      if CM and CM.showStatus then CM.showStatus("You found the treasure!", 3) end
      s:finish()
      return
    elseif CM and CM.showStatus then
      CM.showStatus("Nothing here!", 1.5)
    end
  end
  s.data.wasIdle = (CM and CM.overworldIdle and CM.overworldIdle(game, ow)) and true or false
end

local function draw(s)
  local Font = require("src.render.Font")
  local I18n = require("src.coop.CoopI18n")
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 14, 20, 4)
  love.graphics.setColor(0, 0, 0, 1)
  local hint = I18n.fit(HINTS[s.data.hint or "cold"] or "COLD", 18)
  local how = I18n.fit("A: SEARCH HERE", 18)
  Font.draw(hint, 8, 120)
  Font.draw(how, 8, 128)
  love.graphics.setColor(1, 1, 1, 1)
end

local function finish(s)
  calm(s, nil)
  Treasure.heard = {}
end

Treasure.def = {
  id = Treasure.ID,
  name = "TREASURE HUNT",
  info = { "A SPOT ON THIS MAP", "HIDES A TREASURE.", "FIRST TO FIND IT!" },
  duration = Treasure.DURATION,
  lowWins = true,
  canStart = canStart,
  start = start,
  update = update,
  draw = draw,
  scoreText = Treasure.scoreText,
  finish = finish,
}

require("src.coop.CoopMinigame").register(Treasure.def)

local CM = manager()
if CM and CM.handlers then
  CM.handlers.coop_mg_treasure = function(_, msg)
    if type(msg) == "table" and msg.mid then Treasure.heard[msg.mid] = msg end
  end
end

return Treasure
