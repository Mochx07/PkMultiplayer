-- Interactive Double Battle Animation Visual Inspector for Love2D
-- Usage: love tools/anim_viewer_app
package.path = "./?.lua;./?/init.lua;../../?.lua;../../?/init.lua;" .. package.path

local BattleState = require("src.battle.BattleState")
local Gen2AnimPlayer = require("src.battle.Gen2AnimPlayer")

local MOVE_ARCHETYPES = {
  { name = "Aerochorro (Aeroblast)", id = 177, arch = "aeroblast", routine = "Aeroblast" },
  { name = "Hiperrayo (Hyper Beam)", id = 63, arch = "beam", routine = "MoveWaveToTarget" },
  { name = "Lanzallamas (Flamethrower)", id = 53, arch = "beam", routine = "MoveWaveToTarget" },
  { name = "Rayo Burbuja (BubbleBeam)", id = 61, arch = "wave", routine = "Bubble" },
  { name = "Rayo Hielo (Ice Beam)", id = 58, arch = "beam", routine = "MoveWaveToTarget" },
  { name = "Rayo (Thunderbolt)", id = 85, arch = "beam", routine = "MoveWaveToTarget" },
  { name = "Hoja Afilada (Razor Leaf)", id = 75, arch = "wave", routine = "RazorLeaf" },
  { name = "Ascuas (Ember)", id = 52, arch = "arc", routine = "Ember" },
  { name = "Bomba Lodo (Sludge Bomb)", id = 188, arch = "arc", routine = "Sludge" },
  { name = "Llamarada (Fire Blast)", id = 126, arch = "arc", routine = "FireBlast" },
  { name = "Placaje (Tackle)", id = 33, arch = "toTarget", routine = "MoveFromUserToTarget" },
  { name = "Pistola Agua (Water Gun)", id = 55, arch = "toTarget", routine = "WaterGun" },
  { name = "Mordisco (Bite)", id = 44, arch = "strike", routine = "Bite" },
  { name = "Cuchillada (Slash)", id = 163, arch = "strike", routine = "Kick" },
  { name = "Danza Espada (Swords Dance)", id = 14, arch = "rise", routine = "GrowthSwordsDance" },
  { name = "Rayo Solar (SolarBeam)", id = 76, arch = "beam", routine = "SolarBeam" },
  { name = "Avalancha (Rock Slide)", id = 157, arch = "fall", routine = "Drop" },
  { name = "Terremoto (Earthquake)", id = 89, arch = "shake", routine = "Shake" },
  { name = "Surf", id = 57, arch = "shake", routine = "Surf" },
}

local SLOTS = {
  [0] = { name = "P1 (Lead)", isPlayer = true, x = 44, y = 48, w = 48, h = 48, color = {0.2, 0.7, 1.0} },
  [2] = { name = "P2 (Pareja)", isPlayer = true, x = 10, y = 38, w = 48, h = 48, color = {0.5, 0.5, 1.0} },
  [1] = { name = "E1 (Rival Izq)", isPlayer = false, x = 72, y = -2, w = 56, h = 56, color = {1.0, 0.4, 0.4} },
  [3] = { name = "E2 (Rival Der)", isPlayer = false, x = 114, y = 2, w = 56, h = 56, color = {1.0, 0.6, 0.2} }
}

local app = {
  selectedMove = 1,
  attackerSlot = 0, -- P1
  targetSlot = 1,   -- E1
  frame = 0,
  maxFrames = 45,
  playing = true,
  speed = 1.0,
  scale = 3,
  showHermite = true,
  showBoxes = true,
}

local function mockPic(w, h)
  return {
    getWidth = function() return w end,
    getHeight = function() return h end,
    getDimensions = function() return w, h end
  }
end

function love.load()
  love.window.setTitle("PkMultiplayer - Visor de Animaciones Dobles Gen 2")
  love.window.setMode(800, 600, { resizable = true })
  
  -- Create dummy battle state to compute real animPicBox
  app.battle = setmetatable({
    sides = { { battlers = {} }, { battlers = {} } },
    coopDouble = true,
    isDouble = function() return true end,
    gen3Layout = function() return false end,
    picImage = function(_, img) return img end
  }, { __index = BattleState })

  app.battle.sides[1].battlers[1] = { sprite = mockPic(48, 48), mon = {} } -- P1
  app.battle.sides[1].battlers[2] = { sprite = mockPic(48, 48), mon = {} } -- P2
  app.battle.sides[2].battlers[1] = { sprite = mockPic(56, 56), mon = {} } -- E1
  app.battle.sides[2].battlers[2] = { sprite = mockPic(56, 56), mon = {} } -- E2

  app.animPlayer = setmetatable({}, { __index = Gen2AnimPlayer })
  app.updateOffsets()
end

function app.updateOffsets()
  local aSlot = app.attackerSlot
  local tSlot = app.targetSlot
  local isPlayerAtk = (aSlot % 2 == 0)

  if isPlayerAtk then
    app.animPlayer.sideOffsets = {
      player = app.battle:animPicBox(aSlot, false),
      enemy = app.battle:animPicBox(tSlot, true)
    }
  else
    app.animPlayer.sideOffsets = {
      player = app.battle:animPicBox(tSlot, false),
      enemy = app.battle:animPicBox(aSlot, true)
    }
  end
end

function love.update(dt)
  if app.playing then
    app.frame = app.frame + (dt * 60 * app.speed)
    if app.frame > app.maxFrames then
      app.frame = 0
    end
  end
end

function love.draw()
  local g = love.graphics
  g.clear(0.06, 0.09, 0.14)

  local s = app.scale
  local ox, oy = 40, 40

  -- 160x144 Game Boy screen
  g.setColor(0.04, 0.08, 0.12)
  g.rectangle("fill", ox, oy, 160 * s, 144 * s)
  g.setColor(0.2, 0.3, 0.4)
  g.rectangle("line", ox, oy, 160 * s, 144 * s)

  -- Platforms
  g.setColor(0.12, 0.16, 0.22)
  g.ellipse("fill", ox + 112 * s, oy + 48 * s, 42 * s, 14 * s)
  g.ellipse("fill", ox + 48 * s, oy + 118 * s, 54 * s, 18 * s)

  -- Battlers
  for _, id in ipairs({ 1, 3, 2, 0 }) do
    local slot = SLOTS[id]
    local shrink = 0.85
    local bx = ox + slot.x * s
    local by = oy + slot.y * s
    local bw = (slot.w * shrink) * s
    local bh = (slot.h * shrink) * s

    g.setColor(slot.color[1], slot.color[2], slot.color[3], 0.25)
    g.rectangle("fill", bx, by, bw, bh)
    g.setColor(slot.color)
    g.rectangle("line", bx, by, bw, bh)

    g.print(slot.name, bx + 4, by + 4)
  end

  -- Trajectory and Projectile
  local aSlot = SLOTS[app.attackerSlot]
  local tSlot = SLOTS[app.targetSlot]
  local shrink = 0.85
  local acx = aSlot.x + (aSlot.w * shrink) / 2
  local acy = aSlot.y + (aSlot.h * shrink) / 2
  local tcx = tSlot.x + (tSlot.w * shrink) / 2
  local tcy = tSlot.y + (tSlot.h * shrink) / 2

  if app.showHermite then
    g.setColor(0.2, 0.8, 0.4, 0.4)
    g.line(ox + acx * s, oy + acy * s, ox + tcx * s, oy + tcy * s)
  end

  local isPlayerAtk = (app.attackerSlot % 2 == 0)
  local pCartX = isPlayerAtk and 40 or 132
  local pCartY = isPlayerAtk and 88 or 44
  local tCartX = isPlayerAtk and 132 or 40
  local tCartY = isPlayerAtk and 44 or 88

  local move = MOVE_ARCHETYPES[app.selectedMove]
  local progress = math.min(1.0, math.max(0.0, app.frame / app.maxFrames))

  -- Draw projectile
  if move.arch == "aeroblast" or move.id == 177 then
    if progress <= 0.35 then
      local chargeT = progress / 0.35
      local vX = isPlayerAtk and 72 or 108
      local vY = isPlayerAtk and 88 or 64
      local dx, dy = app.animPlayer:objectOffset(vX, vY)
      local vx, vy = ox + (vX + dx) * s, oy + (vY + dy) * s
      for r = 0, 3 do
        local rad = (18 - (chargeT * 8) + r * 5) * s
        g.setColor(0.2, 0.8, 1.0, 0.85)
        g.ellipse("line", vx, vy, rad, rad * 0.45)
      end
      g.setColor(1, 1, 1, 1)
      g.circle("fill", vx, vy, (4 + math.sin(app.frame * 0.8) * 2) * s)
    elseif progress <= 0.85 then
      local streamP = (progress - 0.35) / 0.50
      for i = 0, 3 do
        local segT = math.max(0, math.min(1, streamP * 1.35 - i * 0.15))
        if segT > 0 then
          local cX = pCartX + (tCartX - pCartX) * segT
          local cY = pCartY + (tCartY - pCartY) * segT
          local dx, dy = app.animPlayer:objectOffset(cX, cY)
          local bx = ox + (cX + dx) * s
          local by = oy + (cY + dy) * s
          g.setColor(0.2, 0.8, 1.0, 1 - i * 0.22)
          g.circle("line", bx, by, (9 + i * 2) * s)
          g.setColor(1, 1, 1, 0.9)
          g.circle("fill", bx, by, (5 - i) * s)
        end
      end
    else
      local impP = (progress - 0.85) / 0.15
      local dx, dy = app.animPlayer:objectOffset(tCartX, tCartY)
      local ix = ox + (tCartX + dx) * s
      local iy = oy + (tCartY + dy) * s
      g.setColor(0.2, 0.8, 1.0, 1 - impP)
      g.circle("line", ix, iy, impP * 28 * s)
      g.setColor(1, 1, 1, 1 - impP * 0.8)
      g.circle("fill", ix, iy, (12 - impP * 8) * s)
    end
  elseif move.arch == "beam" then
    for i = 0, 4 do
      local segP = math.max(0, math.min(1, progress * 1.5 - i * 0.12))
      if segP > 0 then
        local cX = pCartX + (tCartX - pCartX) * segP
        local cY = pCartY + (tCartY - pCartY) * segP
        local dx, dy = app.animPlayer:objectOffset(cX, cY)
        g.setColor(1.0, 0.8, 0.2, 0.8 - i * 0.15)
        g.circle("fill", ox + (cX + dx) * s, oy + (cY + dy) * s, (7 - i) * s * 0.8)
        g.setColor(1, 1, 1, 0.9)
        g.circle("fill", ox + (cX + dx) * s, oy + (cY + dy) * s, (3 - i * 0.4) * s)
      end
    end
  else
    local cX = pCartX + (tCartX - pCartX) * progress
    local cY = pCartY + (tCartY - pCartY) * progress
    local dx, dy = app.animPlayer:objectOffset(cX, cY)
    g.setColor(0.2, 0.9, 0.4)
    g.circle("fill", ox + (cX + dx) * s, oy + (cY + dy) * s, 5 * s)
  end

  -- Sidebar Controls UI
  local rx = ox + 160 * s + 24
  g.setColor(1, 1, 1)
  g.print("MOVIMIENTO: " .. move.name, rx, 40)
  g.print("Rutina: " .. move.routine .. " (" .. move.arch .. ")", rx, 60)
  g.print("Frame: " .. math.floor(app.frame) .. " / " .. app.maxFrames, rx, 85)
  g.print("Atacante: " .. aSlot.name .. " -> Objetivo: " .. tSlot.name, rx, 105)
  g.print("Velocidad: " .. app.speed .. "x", rx, 125)

  g.setColor(0.6, 0.8, 1)
  g.print("[ESPACIO] Pausar / Reanudar", rx, 160)
  g.print("[ARRIBA / ABAJO] Cambiar Movimiento", rx, 180)
  g.print("[1] P1->E1  [2] P1->E2  [3] P2->E1  [4] P2->E2", rx, 205)
  g.print("[5] P1->P2 (Amigo)      [6] P2->P1 (Amigo)", rx, 225)
  g.print("[7] E1->P1 (Rival)      [8] E2->P2 (Rival)", rx, 245)
  g.print("[IZQ / DER] Paso Frame-by-Frame", rx, 270)
  g.print("[H] Alternar Trayectoria Hermite", rx, 290)
end

function love.keypressed(key)
  if key == "space" then
    app.playing = not app.playing
  elseif key == "up" then
    app.selectedMove = app.selectedMove > 1 and (app.selectedMove - 1) or #MOVE_ARCHETYPES
    app.frame = 0
  elseif key == "down" then
    app.selectedMove = app.selectedMove < #MOVE_ARCHETYPES and (app.selectedMove + 1) or 1
    app.frame = 0
  elseif key == "left" then
    app.playing = false
    app.frame = math.max(0, app.frame - 1)
  elseif key == "right" then
    app.playing = false
    app.frame = math.min(app.maxFrames, app.frame + 1)
  elseif key == "1" then
    app.attackerSlot = 0; app.targetSlot = 1; app.updateOffsets(); app.frame = 0
  elseif key == "2" then
    app.attackerSlot = 0; app.targetSlot = 3; app.updateOffsets(); app.frame = 0
  elseif key == "3" then
    app.attackerSlot = 2; app.targetSlot = 1; app.updateOffsets(); app.frame = 0
  elseif key == "4" then
    app.attackerSlot = 2; app.targetSlot = 3; app.updateOffsets(); app.frame = 0
  elseif key == "5" then
    app.attackerSlot = 0; app.targetSlot = 2; app.updateOffsets(); app.frame = 0
  elseif key == "6" then
    app.attackerSlot = 2; app.targetSlot = 0; app.updateOffsets(); app.frame = 0
  elseif key == "7" then
    app.attackerSlot = 1; app.targetSlot = 0; app.updateOffsets(); app.frame = 0
  elseif key == "8" then
    app.attackerSlot = 3; app.targetSlot = 2; app.updateOffsets(); app.frame = 0
  elseif key == "h" then
    app.showHermite = not app.showHermite
  end
end
