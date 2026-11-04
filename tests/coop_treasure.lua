-- TREASURE HUNT (1.20, src/coop/mg/Treasure.lua): the cells it may pick (the
-- player's part of the map, ledges both ways, no warps / water / people, the
-- map's own data), the same pick on two copies, the hints, and full hunts on
-- two copies of the frame through a fake link (one module instance, its state
-- swapped between "A" and "B", as tests/coop_minigame.lua does).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local CoopManager = require("src.coop.CoopManager")
local MG = require("src.coop.CoopMinigame")
local Treasure = require("src.coop.mg.Treasure")
require("src.coop.CoopLog").enabled = false

T.check(MG.GAMES.treasure == Treasure.def and CoopManager.CAPS["minigame.treasure"],
        "the hunt registers on the frame, with its capability")
T.check(Treasure.def.lowWins and Treasure.def.duration == Treasure.DURATION, "the lower time wins")

-- a map of characters: # wall, . floor, W warp, ~ water, L a Gen 1 ledge
-- (hopped southward from the floor above it)
local ROWS = {
  "############",
  "#....#.....#",
  "#....#.....#",
  "#..W.#.....#",
  "#....#.....#",
  "#LLLL#.....#",
  "#....#.....#",
  "#..~.#.....#",
  "#....#.....#",
  "############",
}
local function fakeMap(rows, id, objects)
  local W, H = #rows[1], #rows
  local m = { id = id or "FAKE_MAP", widthCells = W, heightCells = H, tileset = {}, collisionPatch = {}, blockPatch = {},
              def = { id = id or "FAKE_MAP", tileset = "OVERWORLD", generation = 1, width = W, height = H,
                      objects = objects or { { x = 7, y = 2 } }, signs = { { x = 9, y = 8 } } } }
  local function ch(x, y) return rows[y + 1]:sub(x + 1, x + 1) end
  function m:inBounds(x, y) return x >= 0 and y >= 0 and x < W and y < H end
  function m:cellTile(x, y) return self:inBounds(x, y) and ch(x, y):byte() or 0xFF end
  function m:isWalkableCell(x, y)
    if not self:inBounds(x, y) or self.collisionPatch[y * W + x + 1] then return false end
    local c = ch(x, y)
    return c == "." or c == "W"
  end
  function m:isWaterCell(x, y) return self:inBounds(x, y) and ch(x, y) == "~" end
  function m:warpAtCell(x, y) return self:inBounds(x, y) and ch(x, y) == "W" and {} or nil end
  return m
end
local FIELD = { ledges = { { tileset = "OVERWORLD", facing = "down", input = "down",
                             standingTile = ("."):byte(), ledgeTile = ("L"):byte() } } }
local function has(cells, x, y)
  for _, c in ipairs(cells) do if c[1] == x and c[2] == y then return true end end
  return false
end

-- --------------------------------------------------------- the cells
local map = fakeMap(ROWS)
local left = Treasure.candidates(map, 1, 1, FIELD)
local onlyLeft, sorted = true, true
for i, c in ipairs(left) do
  if c[1] > 4 then onlyLeft = false end
  if i > 1 and (c[2] * 12 + c[1]) <= (left[i - 1][2] * 12 + left[i - 1][1]) then sorted = false end
end
T.check(#left == 26 and onlyLeft, "from the left: its two halves joined by the ledge, 26 cells (" .. #left .. ")")
T.check(sorted, "...in index order")
T.check(not has(left, 3, 3) and not has(left, 3, 7) and not has(left, 1, 5), "no warp, no water, no ledge")
T.check(has(left, 2, 8), "the cells below the ledge count (hopped down, walked round)")
local noLedge = Treasure.candidates(map, 1, 1, {})
T.check(#noLedge == 38 and not has(noLedge, 1, 1), "without the ledge the corner is too small: the biggest part instead")
local right = Treasure.candidates(map, 7, 1, FIELD)
T.check(#right == 38 and not has(right, 7, 2) and not has(right, 9, 8), "the right part, less a person's and a sign's cell")
local doorMat = Treasure.candidates(map, 3, 3, FIELD)
T.check(#doorMat == 26, "standing on the warp: the part around it")
map.collisionPatch[4 * 12 + 8 + 1] = 1
T.check(#Treasure.candidates(map, 7, 1, FIELD) == 38 and has(Treasure.candidates(map, 7, 1, FIELD), 8, 4),
        "a cell this copy's scripts shut still counts: the map's own data decides")
map.collisionPatch = {}

-- the same seed, the same cell, on two copies
local copyB = fakeMap(ROWS)
copyB.collisionPatch[2 * 12 + 9 + 1] = 1  -- B cut / shut something A did not
local allSame, spread = true, {}
for seed = 1, 60 do
  local sa = MG.newSession(Treasure.def, "m" .. seed, seed * 7919, true)
  local sb = MG.newSession(Treasure.def, "m" .. seed, seed * 7919, false)
  local a = Treasure.pick(Treasure.candidates(map, 7, 1, FIELD), sa)
  local b = Treasure.pick(Treasure.candidates(copyB, 9, 6, FIELD), sb)
  if not (a and b and a[1] == b[1] and a[2] == b[2]) then allSame = false end
  if a then spread[a[1] .. "," .. a[2]] = true end
end
local n = 0
for _ in pairs(spread) do n = n + 1 end
T.check(allSame, "60 seeds: both copies pick the same cell every time, from different spots of the same part")
T.check(n >= 20, "...and the seeds spread over the map (" .. n .. " cells)")

-- hints and the score line
T.check(Treasure.hint(0) == "hot" and Treasure.hint(3) == "hot" and Treasure.hint(4) == "warm"
        and Treasure.hint(8) == "warm" and Treasure.hint(9) == "cold" and Treasure.hint(nil) == "away",
        "HOT up to 3 steps, WARM up to 8, COLD beyond, another map apart")
T.check(Treasure.scoreText(0) == "--" and Treasure.scoreText(Treasure.NOT_FOUND) == "--"
        and Treasure.scoreText(12.34) == "12.3s", "the score: -- until found, then the time")
T.check(MG.outcome(Treasure.def, 12.3, Treasure.NOT_FOUND) == "win" and MG.outcome(Treasure.def, Treasure.NOT_FOUND, 40) == "lose"
        and MG.outcome(Treasure.def, Treasure.NOT_FOUND, Treasure.NOT_FOUND) == "draw", "found beats not found; nobody: a draw")

-- --------------------------------------------- two copies, one link
local copies, queue, status = {}, {}, {}
local function stackOf(top)
  local s = { states = { top } }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local pressed = {}
for _, name in ipairs({ "A", "B" }) do
  local ow = { map = name == "A" and map or copyB, player = { cellX = 1, cellY = 1, moving = false } }
  local game = { data = Data, save = { player = { name = name == "A" and "MOCHI" or "TOBY" } }, overworld = ow }
  game.stack = stackOf(ow)
  game.input = { isDown = function() return false end, wasPressed = function(_, b) return pressed[name] == b end }
  copies[name] = { game = game, ow = ow, state = {} }
end
local idle = { A = true, B = true }
local active
local function use(name)
  if active then
    local c = copies[active].state
    c.session, c.pending, c.asked = MG.session, MG.pending, MG.asked
  end
  active = name
  local c = copies[name].state
  MG.session, MG.pending, MG.asked = c.session, c.pending, c.asked
  CoopManager.partner.name = name == "A" and "TOBY" or "MOCHI"
  CoopManager.partner.map = copies[name == "A" and "B" or "A"].ow.map.id
  package.loaded["src.core.Game"] = copies[name].game
  CoopManager.getLocalPlayerName = function() return name == "A" and "MOCHI" or "TOBY" end
end
CoopManager.net = { send = function(_, m) queue[#queue + 1] = { from = active, m = m } return true end, flush = function() end }
CoopManager.isConnected = function() return true end
CoopManager.connected = true
CoopManager.overworldIdle = function() return idle[active] end
CoopManager.showStatus = function(text) status[active] = text end
CoopManager.partner.caps = CoopManager.capSet(CoopManager.localCaps())
local function pump()
  for _ = 1, 50 do
    if #queue == 0 then return end
    local e = table.remove(queue, 1)
    use(e.from == "A" and "B" or "A")
    local h = CoopManager.handlers[e.m.type]
    if h then h(nil, e.m) end
  end
end
local function tick(dt)
  for _, nm in ipairs({ "A", "B" }) do
    use(nm); MG.update(dt, copies[nm].game, copies[nm].ow)
  end
  pump()
  pressed.A, pressed.B = nil, nil
end
local function sess(name) use(name) return MG.session end
local function begin(ax, ay, bx, by)
  copies.A.ow.player.cellX, copies.A.ow.player.cellY = ax, ay
  copies.B.ow.player.cellX, copies.B.ow.player.cellY = bx, by
  use("A")
  local ok = MG.invite(copies.A.game, "treasure", copies.A.ow)
  pump()
  use("B")
  if MG.asked then MG.asked.onAccept() end
  pump()
  for _ = 1, 32 do tick(0.1) end
  return ok
end
local function put(name, x, y) copies[name].ow.player.cellX, copies[name].ow.player.cellY = x, y end

-- the gate
use("A")
CoopManager.partner.map = "SOMEWHERE_ELSE"
local ok, why = Treasure.def.canStart(copies.A.game, copies.A.ow)
T.check(not ok and why == "Partner is far away", "the partner on another map: no hunt (" .. tostring(why) .. ")")
use("A")
copies.A.ow.player.surfing = true
ok, why = Treasure.def.canStart(copies.A.game, copies.A.ow)
copies.A.ow.player.surfing = nil
T.check(not ok and why == "Not while surfing", "not while surfing")
-- two rooms of 30 cells, a wall between
local rooms = { "##############" }
for _ = 1, 5 do rooms[#rooms + 1] = "#......#......#" end
rooms[#rooms + 1] = "##############"
local savedMap = copies.A.ow.map
copies.A.ow.map = fakeMap(rooms, "FAKE_MAP", {})
copies.A.ow.player.cellX, copies.A.ow.player.cellY = 1, 1
CoopManager.partner.map = "FAKE_MAP"
CoopManager.partner.cx, CoopManager.partner.cy = 9, 2
ok, why = Treasure.def.canStart(copies.A.game, copies.A.ow)
T.check(not ok and why == "Join your partner first", "the partner in the other room: join them first (" .. tostring(why) .. ")")
CoopManager.partner.cx, CoopManager.partner.cy = 5, 4
ok = Treasure.def.canStart(copies.A.game, copies.A.ow)
T.check(ok, "...in the same room: the hunt is on")
CoopManager.partner.cx, CoopManager.partner.cy = nil, nil
copies.A.ow.map = savedMap
local tiny = fakeMap({ "#####", "#...#", "#...#", "#####" }, "FAKE_MAP")
local saved = copies.A.ow.map
copies.A.ow.map = tiny
use("A")
ok, why = Treasure.def.canStart(copies.A.game, copies.A.ow)
copies.A.ow.map = saved
T.check(not ok and why == "Too small here", "a room of six cells is too small")

-- a hunt: A finds it
T.check(begin(7, 1, 9, 6), "A asks for a hunt on the map both are on")
local sa, sb = sess("A"), sess("B")
T.check(sa and sb and sa.phase == "play" and sb.phase == "play", "both are hunting after the countdown")
T.check(sa.data.cx == sb.data.cx and sa.data.cy == sb.data.cy and sa.data.map == sb.data.map,
        ("the same cell on both: %s,%s / %s,%s"):format(sa.data.cx, sa.data.cy, sb.data.cx, sb.data.cy))
T.check(sb.data.matched == true, "the guest heard the asker's cell and it is its own")
T.check(sa.score == Treasure.NOT_FOUND and sb.score == Treasure.NOT_FOUND, "nobody has a time yet")
use("A"); local quietA = MG.fieldQuiet()
use("B"); local quietB = MG.fieldQuiet()
T.check(Treasure.def.quietField and quietA and quietB, "no wild Pokemon or trainer sight while hunting")
local cx, cy = sa.data.cx, sa.data.cy
-- B far, A near: the hints
local far = math.abs(cy - 1) > math.abs(cy - 8) and { 1, 1 } or { 1, 8 }
put("B", far[1], far[2])
local nx, ny = cx, cy
for _, c in ipairs(right) do
  if math.abs(c[1] - cx) + math.abs(c[2] - cy) == 2 then nx, ny = c[1], c[2] break end
end
put("A", nx, ny)
tick(0.1)
T.check(sess("A").data.hint == "hot" and sess("B").data.hint == "cold",
        "two steps away: HOT; nine or more: COLD (" .. tostring(sess("A").data.hint) .. "/" .. tostring(sess("B").data.hint) .. ")")
-- B digs in the wrong place
pressed.B = "a"
tick(0.1)
T.check(sess("B").phase == "play" and status.B == "Nothing here!", "A on the wrong cell: nothing there, the hunt goes on")
-- A steps on it while a menu was open: the press is the menu's
put("A", cx, cy)
idle.A = false
tick(0.1)
pressed.A = "a"
tick(0.1)
T.check(sess("A").phase == "play", "A on the cell with a menu up does not count")
idle.A = true
tick(0.1)
pressed.A = "a"
tick(0.1)
pump(); tick(0.1)
local ra, rb = sess("A"), sess("B")
T.check(ra.data.found and ra.final and ra.final < Treasure.NOT_FOUND, "A presses A on the cell: found in " .. tostring(ra.final))
T.check(rb.data.beaten and rb.final == Treasure.NOT_FOUND, "B hears it and stops hunting")
T.check(ra.result == "win" and rb.result == "lose", "A wins on A, B loses on B (" .. tostring(ra.result) .. "/" .. tostring(rb.result) .. ")")
T.check(rb.partnerFinal == ra.final and ra.partnerFinal == rb.final, "both copies settle from the same two numbers")
use("A"); quietA = MG.fieldQuiet()
use("B"); quietB = MG.fieldQuiet()
T.check(not quietA and not quietB, "the game over: the field is back to normal on both")
for _ = 1, 70 do tick(0.1) end
T.check(sess("A") == nil and sess("B") == nil, "the result goes away")

-- the guest's map data differ: it takes the asker's cell
local odd = {}
for i, r in ipairs(ROWS) do odd[i] = r end
odd[2] = "#....#....##"  -- one wall more on B's copy: the list shifts
copies.B.ow.map = fakeMap(odd)
local mismatch, adopted = 0, true
for _ = 1, 12 do
  begin(7, 1, 9, 6)
  sa, sb = sess("A"), sess("B")
  if sb.data.matched == false then
    mismatch = mismatch + 1
    if not (sb.data.cx == sa.data.cx and sb.data.cy == sa.data.cy) then adopted = false end
  end
  if mismatch > 0 then break end
  use("A"); MG.abort(nil, true); pump()
end
T.check(mismatch > 0 and adopted, "a different pick on the guest: it hunts the asker's cell ("
        .. sb.data.cx .. "," .. sb.data.cy .. ", own " .. sb.data.own[1] .. "," .. sb.data.own[2] .. ")")
-- nobody finds it: time up, a draw
for _ = 1, Treasure.DURATION * 10 + 20 do tick(0.1) end
local ta, tb = sess("A"), sess("B")
T.check(ta and tb and ta.result == "draw" and tb.result == "draw", "time up, nobody found it: a draw on both ("
        .. tostring(ta and ta.result) .. "/" .. tostring(tb and tb.result) .. ")")
for _ = 1, 70 do tick(0.1) end
copies.B.ow.map = copyB

-- B finds it, and the draw of the box does not fail
begin(7, 1, 9, 6)
sb = sess("B")
put("B", sb.data.cx, sb.data.cy)
tick(0.1)
use("B")
local drew = pcall(Treasure.def.draw, MG.session)
T.check(drew or not (love and love.graphics), "the hint box draws")
pressed.B = "a"
tick(0.1); pump(); tick(0.1)
T.check(sess("B").result == "win" and sess("A").result == "lose", "the guest can win too")
for _ = 1, 70 do tick(0.1) end

T.finish("co-op treasure hunt")
