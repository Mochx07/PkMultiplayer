-- MOVE ANIMATIONS LAND ON THE POKEMON ACTUALLY THERE.
--
-- The Gen 2 scripts aim at a fixed box (the 56x56 front pic box, the 48x48
-- back pic box); a 40x40 Pidgey sits at the bottom of its box, so a hit
-- aimed at the middle landed in the air above it.  animPicBox moves each
-- side's half onto the pic's own pixels, in a single as well as in a double,
-- and Gen2AnimPlayer only squeezes what is inside the box.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local BattleState = require("src.battle.BattleState")
local Gen2AnimPlayer = require("src.battle.Gen2AnimPlayer")

local function near(a, b) return math.abs(a - b) < 0.01 end

-- a pic the headless stub cannot read pixels from: its whole image counts
local function pic(w, h)
  return { getWidth = function() return w end, getHeight = function() return h end,
           getDimensions = function() return w, h end }
end

local function battleWith(enemyPic, playerPic)
  local b = setmetatable({ data = Data, sides = { { battlers = {} }, { battlers = {} } } },
                         { __index = BattleState })
  b.sides[1].battlers[1] = { sprite = playerPic, mon = {} }
  b.sides[2].battlers[1] = { sprite = enemyPic, mon = {} }
  b.picImage = function(_, img) return img end
  return b
end

local function player(so)
  return setmetatable({ sideOffsets = so }, { __index = Gen2AnimPlayer })
end

-- OAM is screen + (8, 16)
local function oamAt(ap, sx, sy)
  local dx, dy = ap:objectOffset(sx + 8, sy + 16)
  return sx + dx, sy + dy
end

do
  local b = battleWith(pic(40, 40), pic(48, 48))
  local E = BattleState.POS.OPPONENT_LEFT
  local P = BattleState.POS.PLAYER_LEFT
  local box = b:animPicBox(E)
  T.check(box ~= nil, "a single's foe gets a box")
  -- the 5x5 pic is drawn at (104, 16): its middle is (124, 36)
  local ap = player({ enemy = box, player = b:animPicBox(P) })
  local x, y = oamAt(ap, 124, 28)
  T.check(near(x, 124) and near(y, 36),
    ("the middle of the foe's box lands on the middle of a 40x40 foe (%.1f, %.1f)"):format(x, y))
  -- the bottom of the box lands on its feet, not under them
  x, y = oamAt(ap, 124, 56)
  T.check(near(y, 56), ("the bottom of the box lands on its feet (%.1f)"):format(y))
  -- a full 56x56 foe: nothing moves (the fixture's back pics draw at 2x,
  -- so a 24x24 one fills the 48x48 box)
  local big = battleWith(pic(56, 56), pic(24, 24))
  ap = player({ enemy = big:animPicBox(E), player = big:animPicBox(P) })
  x, y = oamAt(ap, 124, 28)
  T.check(near(x, 124) and near(y, 28), "a 56x56 foe keeps the cartridge's spot")
  -- the player's 48x48 back pic: nothing moves either
  x, y = oamAt(ap, 32, 72)
  T.check(near(x, 32) and near(y, 72), "a full back pic keeps the cartridge's spot")
end

do
  -- outside the box a point only follows the box's edge: a screen-wide
  -- effect is moved, not squeezed onto the foe
  local b = battleWith(pic(40, 40), pic(48, 48))
  local ap = player({ enemy = b:animPicBox(BattleState.POS.OPPONENT_LEFT) })
  local x1 = oamAt(ap, 153, 4)
  local x2 = oamAt(ap, 159, 4)
  T.check(near(x2 - x1, 6), "beyond the box, spacing is kept")
end

do
  -- no boxes (Gen 3 layout, or nothing standing): nothing moves
  local x, y = oamAt(player(nil), 124, 28)
  T.check(near(x, 124) and near(y, 28), "without boxes the animation is left alone")
end

do
  -- Double battle: beam trajectories (e.g. Hyper Beam) across all slots
  local b = setmetatable({ data = Data, sides = { { battlers = {} }, { battlers = {} } } },
                         { __index = BattleState })
  b.coopDouble = true
  b.isDouble = function() return true end
  b.gen3Layout = function() return false end
  b.picImage = function(_, img) return img end

  b.sides[1].battlers[1] = { sprite = pic(48, 48), mon = {} } -- P1 (0)
  b.sides[1].battlers[2] = { sprite = pic(48, 48), mon = {} } -- P2 (2)
  b.sides[2].battlers[1] = { sprite = pic(56, 56), mon = {} } -- E1 (1)
  b.sides[2].battlers[2] = { sprite = pic(56, 56), mon = {} } -- E2 (3)

  -- Hyper Beam authored coordinates from player side:
  local hbCoords = { {64, 92}, {80, 84}, {96, 76}, {112, 68}, {126, 62} }

  -- 1) P1 -> E1, P2 -> E1, P1 -> E2, P2 -> E2 (all monotonic progression toward enemy)
  for _, pair in ipairs({
    { 0, 1, "P1 to E1" },
    { 2, 1, "P2 to E1" },
    { 0, 3, "P1 to E2" },
    { 2, 3, "P2 to E2" },
  }) do
    local aSlot, tSlot, label = pair[1], pair[2], pair[3]
    local so = {
      player = b:animPicBox(aSlot, false),
      enemy = b:animPicBox(tSlot, true),
    }
    local ap = player(so)
    local prevY = 999
    local monotonic = true
    for _, pt in ipairs(hbCoords) do
      local _, curY = oamAt(ap, pt[1] - 8, pt[2] - 16)
      if curY >= prevY then monotonic = false end
      prevY = curY
    end
    T.check(monotonic, label .. " hyper beam travels smoothly toward target without snapping")
  end

  -- 2) Ally targeting (side to side): P1 attacking P2, and P2 attacking P1
  local p1ToP2 = player({
    player = b:animPicBox(0, false),
    enemy = b:animPicBox(2, true),
  })
  local xStart, yStart = oamAt(p1ToP2, hbCoords[1][1] - 8, hbCoords[1][2] - 16)
  local xEnd, yEnd = oamAt(p1ToP2, hbCoords[5][1] - 8, hbCoords[5][2] - 16)
  T.check(xEnd < xStart and math.abs(yEnd - yStart) < 10, "P1 targeting P2 travels leftward across player side")

  local p2ToP1 = player({
    player = b:animPicBox(2, false),
    enemy = b:animPicBox(0, true),
  })
  xStart, yStart = oamAt(p2ToP1, hbCoords[1][1] - 8, hbCoords[1][2] - 16)
  xEnd, yEnd = oamAt(p2ToP1, hbCoords[5][1] - 8, hbCoords[5][2] - 16)
  T.check(math.abs(yEnd - yStart) < 30 and yEnd > 70, "P2 targeting P1 stays on player row and reaches partner")

  -- 3) animFxBattler targets correct ally on friendly fire
  b.animAttackerPos = 0
  b.animTargetPos = 2
  b.animAttackerIsPlayer = true
  b.animFxSide = "target"
  local targetBattler = b:animFxBattler(false)
  T.check(targetBattler == b:battlerAt(2), "animFxBattler resolves partner P2 on friendly fire")
end

do
  -- HYPER BEAM'S SEGMENTS STAY EVENLY SPACED IN A DOUBLE (player report:
  -- "the Hyper Beam animation looks weird").  The boxes are the ones a real
  -- co-op double on Route 29 hands the player (LUGIA / SNORLAX against two
  -- PIDGEY, logged by tests/drivers/six_anim_double.lua).  In 1.6.16 the
  -- first segments bunched over the user (11 px apart) and the beam then
  -- jumped 24 px into the target's box; on the cartridge they are 18 apart.
  local function side(from, size, to, k)
    return { from = from, size = size, to = to, k = k }
  end
  local P1 = side({ 8, 48 }, 48, { 47.0, 55.5 }, 0.85)
  local P2 = side({ 8, 48 }, 48, { 14.0, 51.5 }, 0.83)
  local E1 = side({ 96, 0 }, 56, { 77.0, 5.0 }, 0.55)
  local E2 = side({ 96, 0 }, 56, { 119.0, 9.0 }, 0.55)
  -- the four BATTLE_ANIM_OBJ_HYPER_BEAM rows (OAM), before the end burst
  local seg = { { 64, 92 }, { 80, 84 }, { 96, 76 }, { 112, 68 } }
  for _, c in ipairs({
    { "P1 -> left foe", P1, E1 }, { "P2 -> left foe", P2, E1 },
    { "P1 -> right foe", P1, E2 }, { "P2 -> right foe", P2, E2 },
    { "left foe -> P1", P1, E1, true }, { "right foe -> P2", P2, E2, true },
    { "right foe -> P1", P1, E2, true }, { "left foe -> P2", P2, E1, true },
  }) do
    local ap = player({ player = c[2], enemy = c[3] })
    local pts = {}
    for i, p in ipairs(seg) do
      local x, y = p[1], p[2]
      -- InitBattleAnimBuffer's mirror for the foe's turn (fixY = $98)
      if c[4] then x, y = 180 - x, 152 - y end
      local dx, dy = ap:objectOffset(x, y)
      pts[i] = { x + dx, y + dy }
    end
    local lo, hi = math.huge, 0
    for i = 2, #pts do
      local g = math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
      lo, hi = math.min(lo, g), math.max(hi, g)
    end
    T.check(hi <= lo * 1.6,
      ("%s: the beam's segments are evenly spaced (%.1f to %.1f px apart)"):format(c[1], lo, hi))
  end
  -- and a single (both pics full size) is still the cartridge, untouched
  local ap = player({ player = side({ 8, 48 }, 48, { 8, 48 }, 1),
                      enemy = side({ 96, 0 }, 56, { 96, 0 }, 1) })
  local ok = true
  for _, p in ipairs(seg) do
    local dx, dy = ap:objectOffset(p[1], p[2])
    if not (near(dx, 0) and near(dy, 0)) then ok = false end
  end
  T.check(ok, "a single's beam stays exactly where the cartridge draws it")
end

do
  -- (from codex 78c8266)
  -- attacker's pic to the target's moves a little at every step: the map
  -- from one box to the other is continuous.  (4763e13 mapped a point by its
  -- box while inside it and by a separate blend outside, so a Hyper Beam
  -- crossing the target box's edge jumped 6-18 px in a double and 10 px in a
  -- single against a 40x40 foe.)
  local px, py, ex, ey = 40, 88, 132, 44   -- PLAYER_PIC_OAM, ENEMY_PIC_OAM
  local N = 400
  local function worstJump(so)
    local ap = player(so)
    local lx, ly, w = nil, nil, 0
    for i = 0, N do
      local x, y = px + (ex - px) * i / N, py + (ey - py) * i / N
      local dx, dy = ap:objectOffset(x, y)
      local sx, sy = x + dx, y + dy
      if lx then w = math.max(w, math.sqrt((sx - lx) ^ 2 + (sy - ly) ^ 2)) end
      lx, ly = sx, sy
    end
    return w
  end
  local function field(enemyW, playerW, double)
    local b = setmetatable({ data = Data, sides = { { battlers = {} }, { battlers = {} } } },
                           { __index = BattleState })
    if double then b.coopDouble = true b.isDouble = function() return true end end
    b.picImage = function(_, img) return img end
    b.sides[1].battlers[1] = { sprite = pic(playerW, playerW), mon = {} }
    b.sides[1].battlers[2] = { sprite = pic(playerW, playerW), mon = {} }
    b.sides[2].battlers[1] = { sprite = pic(enemyW, enemyW), mon = {} }
    b.sides[2].battlers[2] = { sprite = pic(enemyW, enemyW), mon = {} }
    return b
  end
  for _, c in ipairs({
    { "single, 40x40 foe", 40, 48, false, 0, 1 },
    { "double P1 -> E1", 56, 48, true, 0, 1 },
    { "double P2 -> E1", 56, 48, true, 2, 1 },
    { "double P1 -> E2", 56, 48, true, 0, 3 },
    { "double P2 -> E2", 56, 48, true, 2, 3 },
  }) do
    local b = field(c[2], c[3], c[4])
    local w = worstJump({ player = b:animPicBox(c[5], false), enemy = b:animPicBox(c[6], true) })
    T.check(w < 4, ("%s: a projectile moves without jumping (worst step %.1f px)"):format(c[1], w))
  end
end


T.finish("move animations fit the Pokemon")
