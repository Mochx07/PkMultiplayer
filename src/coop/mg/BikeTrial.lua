-- src/coop/mg/BikeTrial.lua
-- BIKE TRIAL (1.20, M3): a time trial down Cycling Road, gate to gate, on
-- the minigame frame (src/coop/CoopMinigame.lua).
--
--   * where: Gen 2 Kanto.  Both players meet at the start gate (ROUTE 16
--     GATE, the one west of Celadon) with a BICYCLE in the bag.  canStart
--     says what is missing: the game (Gen 1 has no such road here), the
--     bike, the road itself (never been to Celadon or Fuchsia), or the gate.
--   * start: after the frame's countdown each copy lines its own player up at
--     the gate's west door, on the bike (a short hop inside the start area,
--     never a ride from elsewhere: no taxi).  The clock starts when the player
--     stands there.
--   * the course: out the west door onto ROUTE 16, south down ROUTE 17 (the
--     engine's own downhill road) and into the ROUTE 17 / 18 GATE.  Entering
--     that gate straight from ROUTE 17 is the finish; the time is in tenths
--     of a second, so both copies compare the same two whole numbers.
--   * the ghost: the partner's live position, which the world sync already
--     draws as the partner on the road (passable, so it never blocks); the
--     bar on the right shows both riders' progress down the course.
--   * no trainer spots you and no wild Pokemon jumps out while it is on
--     (def.quietField, lib/Hooks.lua asks the frame).
--   * finishing first waits for the partner (def.waitForPartner): their time
--     comes when they cross the line or at their time-up, never cut short.
--   * lowest time wins.  A rider who does not finish in time scores DNF (a
--     big number), so a finisher always beats them and two DNFs draw.
--   * best time: save.coopBikeBest (tenths), kept in the save like the other
--     co-op fields, so it lasts once the player saves.
local MG = require("src.coop.CoopMinigame")

local BikeTrial = {}

BikeTrial.ID = "bike"
BikeTrial.START = "ROUTE16_GATE"
BikeTrial.LANE = { { 1, 4 }, { 1, 5 } }      -- asker / partner, beside the west door
BikeTrial.ROAD = "ROUTE17"
BikeTrial.FINISH = "ROUTE17_ROUTE18_GATE"
BikeTrial.START_AREA = { ROUTE16_GATE = true, ROUTE16 = true }
BikeTrial.DURATION = 120
BikeTrial.DNF = 99999                         -- tenths: "did not finish"
BikeTrial.ROAD_END_Y = 83                     -- the finish gate's door row on ROUTE 17

local function T(s) return require("src.coop.CoopI18n").t(s) end
local function manager()
  local ok, CM = pcall(require, "src.coop.CoopManager")
  return ok and CM or nil
end

-- tenths -> "0:23.4"; DNF (or no time yet) -> "--"
function BikeTrial.timeText(v)
  v = tonumber(v)
  if not v or v <= 0 or v >= BikeTrial.DNF then return "--" end
  v = math.max(0, math.floor(v + 0.5))
  local secs = math.floor(v / 10)
  return string.format("%d:%02d.%d", math.floor(secs / 60), secs % 60, v % 10)
end

-- seconds -> tenths, the same rounding everywhere
function BikeTrial.tenths(seconds)
  return math.max(1, math.floor((tonumber(seconds) or 0) * 10 + 0.5))
end

local function hasBike(save)
  local inv = save and save.inventory
  return inv ~= nil and (tonumber(inv.BICYCLE) or 0) > 0
end

-- the road exists in this game's data (Gen 2 Kanto; not Gen 1, not Prism)
function BikeTrial.hasRoad(data)
  local maps = data and data.maps
  if not (maps and maps[BikeTrial.START] and maps[BikeTrial.ROAD] and maps[BikeTrial.FINISH]) then return false end
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if okV and GameVersion.isGen2 and not GameVersion.isGen2() then return false end
  return true
end

-- each copy asks for itself: ok, or false and what to tell the player
function BikeTrial.canStart(game, ow)
  local save = game and game.save
  if not BikeTrial.hasRoad(game and game.data) then return false, "No CYCLING ROAD here" end
  if not hasBike(save) then return false, "You need a BICYCLE" end
  local here = ow and ow.map and ow.map.id
  if here and BikeTrial.START_AREA[here] then return true end
  local visited = save and save.visited or {}
  if not (visited.CELADON_CITY or visited.FUCHSIA_CITY) then return false, "Reach CYCLING ROAD first" end
  return false, "Go to the ROUTE 16 gate"
end

-- how far down the course a rider is, 0..1 (nil: not on it)
function BikeTrial.progress(map, x, y)
  if map == BikeTrial.START then return 0 end
  if map == "ROUTE16" then return 0.05 end
  if map == BikeTrial.ROAD then
    local f = math.max(0, math.min(1, (tonumber(y) or 0) / BikeTrial.ROAD_END_Y))
    return 0.1 + 0.85 * f
  end
  if map == BikeTrial.FINISH then return 1 end
  return nil
end

function BikeTrial.best(save)
  local b = save and tonumber(save.coopBikeBest)
  return (b and b > 0 and b < BikeTrial.DNF) and b or nil
end

-- a finished time: kept when it beats the save's best; true when it did
function BikeTrial.record(save, tenths)
  tenths = tonumber(tenths)
  if not (save and tenths and tenths > 0 and tenths < BikeTrial.DNF) then return false end
  local b = BikeTrial.best(save)
  if b and b <= tenths then return false end
  save.coopBikeBest = tenths
  return true
end

local function idle(game, ow)
  return ow and ow.map and not ow.transitioning and game and game.stack
         and (not game.stack.top or game.stack:top() == ow)
end

-- the play itself, one copy's player
function BikeTrial.start(s, game, ow)
  s:setScore(BikeTrial.DNF)
  s.data.stage = "lineup"
  s.data.best = BikeTrial.best(game and game.save)
end

function BikeTrial.update(s, dt, game, ow)
  local d = s.data
  ow = (game and game.overworld) or ow
  if not (ow and ow.map) then return end
  local save = game.save
  if d.stage == "lineup" then
    if not idle(game, ow) then return end
    local lane = BikeTrial.LANE[s.asker and 1 or 2]
    -- on the bike before the hop, so the gate opens onto the bike's song
    if save then save.onBike = true end
    if ow.map.id == BikeTrial.START and ow.player and ow.player.cellX == lane[1] and ow.player.cellY == lane[2] then
      d.stage = "ready"
    elseif ow.startWarpTo then
      ow:startWarpTo(BikeTrial.START, lane[1], lane[2], "left")
      d.stage = "hop"
    end
  elseif d.stage == "hop" then
    if not ow.transitioning and ow.map.id == BikeTrial.START then d.stage = "ready" end
  end
  if d.stage == "ready" then
    if not ow.transitioning then
      if save then save.onBike = true end
      d.stage, d.t0, d.last = "ride", s.t, ow.map.id
    end
    return
  end
  if d.stage ~= "ride" then return end
  local here = ow.map.id
  if here == BikeTrial.ROAD then d.onRoad = true end
  -- the finish: into the gate straight off the road (a FLY to Fuchsia and a
  -- walk in from the east is not a ride)
  if here == BikeTrial.FINISH and d.last == BikeTrial.ROAD and d.onRoad then
    local time = BikeTrial.tenths(s.t - d.t0)
    d.stage = "done"
    s:setScore(time)
    local CM = manager()
    if BikeTrial.record(save, time) then
      d.newBest = true
      if CM and CM.showStatus then CM.showStatus(T("New best time!"), 3) end
    end
    require("src.coop.CoopLog").info("MINIGAME", "bike trial finished in " .. BikeTrial.timeText(time))
    s:finish()
    return
  end
  d.last = here
end

-- the rider's own clock and best along the bottom, both riders on the bar
function BikeTrial.draw(s, ow)
  local Font = require("src.render.Font")
  local I18n = require("src.coop.CoopI18n")
  local d = s.data
  local running = d.t0 and (d.stage == "ride") and BikeTrial.tenths(s.t - d.t0) or nil
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 14, 20, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(I18n.fit(T("TIME") .. " " .. BikeTrial.timeText(running or (d.stage == "done" and s.score) or 0), 18), 8, 120)
  Font.draw(I18n.fit(T("BEST") .. " " .. BikeTrial.timeText(d.best), 18), 8, 128)
  -- the course bar: start at the top, the finish gate at the bottom
  local x, y0, y1 = 150, 46, 106
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x, y0, 3, y1 - y0)
  local CM = manager()
  local p = CM and CM.partner
  local theirs = p and BikeTrial.progress(p.map, p.cx, p.cy)
  if theirs then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", x - 3, y0 + (y1 - y0) * theirs - 3, 9, 6)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", x - 3, y0 + (y1 - y0) * theirs - 3, 9, 6)
  end
  local mine = ow and ow.map and ow.player and BikeTrial.progress(ow.map.id, ow.player.cellX, ow.player.cellY)
  if mine then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", x - 3, y0 + (y1 - y0) * mine - 3, 9, 6)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

BikeTrial.def = MG.register({
  id = BikeTrial.ID,
  name = "BIKE TRIAL",
  info = { "RIDE CYCLING ROAD", "GATE TO GATE.", "LOWEST TIME WINS." },
  duration = BikeTrial.DURATION,
  lowWins = true,
  quietField = true,
  waitForPartner = true,
  canStart = BikeTrial.canStart,
  start = BikeTrial.start,
  update = BikeTrial.update,
  draw = BikeTrial.draw,
  scoreText = BikeTrial.timeText,
})

return BikeTrial
