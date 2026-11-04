-- src/coop/CoopHud.lua (split out of CoopManager.lua for 1.20)
-- install(CoopManager, CMI) runs this code where it used to sit in
-- CoopManager.lua: CoopManager.* names are the manager's own, and CMI
-- carries the manager's file-level locals it reads (and the ones it
-- hands on to the code after it).
--
-- drawing

local M = {}

function M.install(CoopManager, CMI)
local CoopLog = CMI.CoopLog
local CoopManager = CMI.CoopManager
local Font = CMI.Font
local Tilt = CMI.Tilt
local getGame = CMI.getGame
local mapsMatch = CMI.mapsMatch
local now = CMI.now
local partnerFrameOffset = CMI.partnerFrameOffset
local stackTop = CMI.stackTop


-- Draw authentic rotating Poké Ball above battlers (compact retro r=2.2)
function CoopManager.drawSpinningPokeball(bx, by, r)
  r = r or 2.2
  local t = now()
  local angle = (t * 5) % (2 * math.pi)
  local bob = math.floor(math.sin(t * 6) * 1.5)

  love.graphics.push()
  love.graphics.translate(bx, by + bob)
  love.graphics.rotate(angle)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.circle("fill", 0, 0, r + 0.8)
  if love.graphics.arc then
    love.graphics.setColor(0.9, 0.15, 0.15, 1)
    love.graphics.arc("fill", 0, 0, r, math.pi, 2 * math.pi)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.arc("fill", 0, 0, r, 0, math.pi)
  else
    love.graphics.setColor(0.9, 0.15, 0.15, 1)
    love.graphics.circle("fill", 0, 0, r)
  end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", -r, -0.6, r * 2, 1.2)
  love.graphics.circle("fill", 0, 0, math.max(1, r * 0.45))
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("fill", 0, 0, math.max(0.5, r * 0.22))
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

-- 1px-bordered white pill with notched corners, the shape every co-op
-- label uses
local function drawPill(bx, by, bw, bh)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", bx + 1, by, bw - 2, 1)
  love.graphics.rectangle("fill", bx + 1, by + bh - 1, bw - 2, 1)
  love.graphics.rectangle("fill", bx, by + 1, 1, bh - 2)
  love.graphics.rectangle("fill", bx + bw - 1, by + 1, 1, bh - 2)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", bx + 1, by + 1, bw - 2, bh - 2)
end
CoopManager.drawPill = drawPill

-- how tall a character card stands in a render pipeline's 3D scene, in
-- world px at the camera's focus (DramaticShapes; measured from its frames)
local HEAD_3D = 30

local function screenPoint(ow, wx, wy)
  -- through a render pipeline's camera (drawWorldProjected)
  if CoopManager.projectPoint then return CoopManager.projectPoint(wx, wy) end
  local cam = ow.camera
  local vw, vh = (ow.viewW or 160), (ow.viewH or 144)
  local fx = wx - cam.x + 8
  local fy = wy - cam.y + 16
  if Tilt.active and Tilt.active() then
    return Tilt.groundPoint(fx, fy, vw, vh)
  end
  return fx, fy
end
CoopManager.screenPoint = screenPoint

-- A small arrow on the screen edge pointing at a partner who is on this map
-- (or a connected one) but out of view.
local function drawOffscreenArrow(sx, sy, vw, vh)
  local cx, cy = vw / 2, vh / 2
  local dx, dy = sx - cx, sy - cy
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then return end
  dx, dy = dx / len, dy / len
  local margin = 7
  local tx = (dx ~= 0) and ((dx > 0 and (vw - margin - cx) or (margin - cx)) / dx) or math.huge
  local ty = (dy ~= 0) and ((dy > 0 and (vh - margin - cy) or (margin - cy)) / dy) or math.huge
  local t = math.min(math.abs(tx), math.abs(ty))
  local ax, ay = cx + dx * t, cy + dy * t
  local px, py = -dy, dx
  local tip = 5
  local base = 3
  local pts = {
    ax + dx * tip, ay + dy * tip,
    ax + px * base, ay + py * base,
    ax - px * base, ay - py * base,
  }
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.polygon("fill", pts[1] + dx, pts[2] + dy, pts[3] + px, pts[4] + py, pts[5] - px, pts[6] - py)
  love.graphics.setColor(40 / 255, 112 / 255, 248 / 255, 1)
  love.graphics.polygon("fill", pts)
  love.graphics.setColor(1, 1, 1, 1)
end

-- WHERE A MAP SITS ON THE TOWN MAP, to point at a partner on another map.
-- Gen 2: every map carries its landmark (a building, its town's), whose
-- coordinates are the POKeGEAR map's; Kanto has a picture of its own, so
-- its landmarks are put to the east of Johto's, which is where Kanto is.
-- Gen 1: field.townMap holds a square per map.  nil when there is none.
local GEN2_KANTO_FIRST = 0x2E

function CoopManager.mapPoint(game, mapId)
  local data = game and game.data
  local tm = data and data.field and data.field.townMap
  if type(tm) ~= "table" or type(mapId) ~= "string" then return nil end
  if type(tm.landmarks) == "table" then
    local def = data.maps and data.maps[mapId]
    local id = def and tonumber(def.landmark)
    local e = id and (tm.landmarks[id] or tm.landmarks[tostring(id)])
    local x, y = type(e) == "table" and tonumber(e.x), type(e) == "table" and tonumber(e.y)
    if not (x and y) then return nil end
    if id >= GEN2_KANTO_FIRST then x = x + 160 end
    return x, y
  end
  local locs = type(tm.locations) == "table" and tm.locations or tm
  local e = locs[mapId]
  if type(e) ~= "table" then return nil end
  local c = type(e.coords) == "table" and e.coords or e
  local x, y = tonumber(c.x or c.col), tonumber(c.y or c.row)
  if x and y then return x, y end
  return nil
end

function CoopManager.drawWorld(ow)
  if not ow or not ow.camera then return end
  local partner = CoopManager.partner
  local npc = CoopManager.partnerNpc
  local view = CoopManager.projectView
  local vw, vh = view and view[1] or (ow.viewW or 160), view and view[2] or (ow.viewH or 144)
  local MicroFont = require("src.render.MicroFont")
  local t = now()

  if CoopManager.connected and npc and CoopManager.render then
    local sx, sy, depth = screenPoint(ow, npc.px, npc.py - (partner.hopY or 0))
    -- a 3D card stands taller than the flat 16 px (about 30 world px at
    -- the focus, more near the camera): what hangs over the head rises with
    -- it, what sits at the feet does not
    local lift = CoopManager.projectPoint and math.max(0, HEAD_3D * (depth or 1) - 18) or 0
    local onScreen = sx >= -8 and sx <= vw + 8 and sy >= 0 and sy <= vh + 16
    if onScreen then
      local name = require("src.coop.CoopI18n").truncate(string.upper(partner.name or "PARTNER"), 8)
      local bw = math.max(16, MicroFont.width(name) + 6)
      local bx = math.floor(sx - bw / 2)
      local by = math.floor(sy + 2)
      drawPill(bx, by, bw, 9)
      love.graphics.setColor(0, 0, 0, 1)
      MicroFont.draw(name, bx + 3, by + 2)
      love.graphics.setColor(1, 1, 1, 1)

      local headY = math.floor(sy - 18 - lift + (partner.hopY or 0))
      local ballY = headY - 5
      if partner.inBattle then
        CoopManager.drawSpinningPokeball(sx, ballY, 2.0)
      elseif partner.emote and partner.inDialogue then
        -- a reaction from inside their scene's dialogue (1.20 duo) shows
        -- over the "..." it would otherwise hide behind
        require("src.coop.CoopEmotes").draw(getGame(ow), partner.emote, sx, sy - lift + (partner.hopY or 0),
                                            2.5 - (partner.emoteTimer or 0))
      elseif partner.inDialogue then
        local bxB = math.floor(sx - 5)
        local byB = math.floor(ballY - 3)
        drawPill(bxB, byB, 11, 7)
        love.graphics.setColor(0, 0, 0, 1)
        local dots = math.floor(t * 3) % 3 + 1
        for i = 1, dots do
          love.graphics.rectangle("fill", bxB + 2 + (i - 1) * 3, byB + 3, 1, 1)
        end
        love.graphics.setColor(1, 1, 1, 1)
      elseif partner.emote then
        require("src.coop.CoopEmotes").draw(getGame(ow), partner.emote, sx, sy - lift + (partner.hopY or 0),
                                            2.5 - (partner.emoteTimer or 0))
      elseif partner.readyAt and t - partner.readyAt < 4 then
        local word = require("src.coop.CoopI18n").t(partner.ready and "READY!" or "WAIT")
        local rw = MicroFont.width(word) + 6
        drawPill(math.floor(sx - rw / 2), ballY - 4, rw, 9)
        love.graphics.setColor(0, 0, 0, 1)
        MicroFont.draw(word, math.floor(sx - rw / 2) + 3, ballY - 2)
        love.graphics.setColor(1, 1, 1, 1)
      end
    else
      drawOffscreenArrow(sx, sy - 8, vw, vh)
    end
  elseif CoopManager.connected and partner.map and ow.map and not mapsMatch(partner.map, ow.map.id) then
    -- ON ANOTHER MAP: the arrow points their way across the town map (the
    -- HUD's pill names the place); inside the same town there is none
    local game = getGame(ow)
    local mx, my = CoopManager.mapPoint(game, ow.map.id)
    local px, py = CoopManager.mapPoint(game, partner.map)
    if mx and px and (mx ~= px or my ~= py) then
      drawOffscreenArrow(vw / 2 + (px - mx) * 1000, vh / 2 + (py - my) * 1000, vw, vh)
    end
  end

  if CoopManager.localEmote and ow.player then
    local p = ow.player
    local sx, sy, depth = screenPoint(ow, p.px, p.py)
    if CoopManager.projectPoint then sy = sy - math.max(0, HEAD_3D * (depth or 1) - 18) end
    require("src.coop.CoopEmotes").draw(getGame(ow), CoopManager.localEmote, sx, sy,
                                        2.5 - (CoopManager.localEmoteTimer or 0))
  end
  for name, fn in pairs(CoopManager.worldDrawers) do
    local ok, err = pcall(fn, ow)
    if not ok and CoopManager.drawerErr ~= err then
      CoopManager.drawerErr = err
      CoopLog.error("MANAGER", "world drawer " .. name .. " failed: " .. tostring(err))
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- name -> fn(ow): feature modules drawing on the world (visitors' names)
CoopManager.worldDrawers = {}

-- The same layers through a render pipeline's camera (lib/Hooks wraps
-- Pipelines.drawWorld): `project(wx, wy)` maps a world point to canvas
-- pixels and `scale` is canvas pixels per world pixel.  Everything drawWorld
-- anchors goes through screenPoint, so while this runs screenPoint answers
-- with the projected foot, in world-pixel units under the scaled transform.
function CoopManager.drawWorldProjected(ow, project, scale)
  if not (ow and ow.camera and project) then return end
  scale = (scale and scale > 0) and scale or 1
  local canvas = love.graphics.getCanvas()
  local cw, ch = 160 * scale, 144 * scale
  if canvas and canvas.getDimensions then cw, ch = canvas:getDimensions() end
  CoopManager.projectPoint = function(wx, wy)
    local x, y, depth = project(wx + 8, wy + 16)
    if not x then return -1e4, -1e4, 1 end  -- behind the camera
    -- depth: how much bigger than at the focus a card here is drawn
    return x / scale, y / scale, depth or 1
  end
  CoopManager.projectView = { cw / scale, ch / scale }
  love.graphics.push()
  love.graphics.scale(scale, scale)
  local ok, err = pcall(CoopManager.drawWorld, ow)
  love.graphics.pop()
  CoopManager.projectPoint, CoopManager.projectView = nil, nil
  if not ok then error(err, 0) end
end

-- word-wrap to `width` characters, at most `maxLines` lines
local function wrap(text, width, maxLines)
  -- counted in letters, not bytes: "compañero" is nine, not ten
  local function len(t) return select(2, t:gsub("[^\128-\191]", "")) end
  local function head(t, n)
    local count = 0
    for pos in t:gmatch("()[^\128-\191]") do
      count = count + 1
      if count > n then return t:sub(1, pos - 1), t:sub(pos) end
    end
    return t, ""
  end
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    while len(word) > width do
      if line ~= "" then lines[#lines + 1] = line; line = "" end
      local first, rest = head(word, width)
      lines[#lines + 1] = first
      word = rest
    end
    if line == "" then
      line = word
    elseif len(line) + 1 + len(word) <= width then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  while #lines > maxLines do table.remove(lines) end
  return lines
end
CoopManager.wrap = wrap

local function drawSignal(x, y, bars)
  for i = 1, 3 do
    local h = i * 2
    if i <= bars then
      love.graphics.setColor(0, 0, 0, 1)
    else
      love.graphics.setColor(0.7, 0.7, 0.7, 1)
    end
    love.graphics.rectangle("fill", x + (i - 1) * 2, y + 6 - h, 1, h)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- The link HUD: a small pill in the top-right corner, never a full window.
-- Signal bars + partner name; underneath, where the partner is when they are
-- not on a map we can see; a blinking LINK LOST while reconnecting.
local function drawHud(ow)
  local MicroFont = require("src.render.MicroFont")
  local state = CoopManager.linkState()
  if state == "off" then return end
  -- the UI pass's width, NOT ow.viewW: that is the WORLD view, which grows
  -- as the zoom goes out, and anchoring to it pushed the link and partner
  -- pills off the right edge of the screen until you zoomed back in
  local game = getGame(ow)
  local renderer = game and game.renderer
  local vw = (renderer and renderer.uiSize and select(1, renderer:uiSize())) or 160
  -- the mod's Font proxy cuts what would run past this edge (CoopI18n.font)
  local okW, I18nW = pcall(require, "src.coop.CoopI18n")
  if okW then I18nW.screenW = vw end
  local partner = CoopManager.partner

  local label
  if state == "reconnecting" then
    label = (math.floor(now() * 2) % 2 == 0) and "LINK LOST" or "RECONNECT"
  elseif state == "listening" then
    label = "WAITING P2"
  elseif not CoopManager.connected then
    label = "LINKING"
  else
    label = require("src.coop.CoopI18n").truncate(string.upper(partner.name or "P2"), 8)
    if partner.ready then label = label .. " OK" end
  end
  local net = CoopManager.net
  local bars = (net and net.linkQuality) and net:linkQuality() or 0
  local w = MicroFont.width(label) + 14
  local x = vw - w - 1
  drawPill(x, 1, w, 9)
  drawSignal(x + 3, 2, bars)
  love.graphics.setColor(0, 0, 0, 1)
  MicroFont.draw(label, x + 11, 3)

  if CoopManager.connected and partner.map and ow and ow.map and not partnerFrameOffset(ow) then
    local area = require("src.coop.CoopI18n").truncate(CoopManager.mapLabel(partner.map), 18)
    local aw = MicroFont.width(area) + 6
    local ax = vw - aw - 1
    drawPill(ax, 11, aw, 9)
    love.graphics.setColor(0, 0, 0, 1)
    MicroFont.draw(area, ax + 3, 13)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function CoopManager.drawUI(ow)
  local game = (ow and ow.game) or getGame(ow)
  local top = stackTop(game)
  local hasTextBox = top and (top.isTextBox or (top.lines ~= nil and top.page ~= nil))
  local isTypingChat = top and top.isChatBox

  -- the last co-op double's result, while nothing else is on the line
  local CoopSummary = package.loaded["src.coop.CoopSummary"]
  local summary = not (CoopManager.statusMessage and CoopManager.statusTimer > 0) and not hasTextBox
                  and CoopSummary and CoopSummary.current(now())
  -- status first, at the top, so it never sits on the dialogue box
  if summary then
    local I18n = require("src.coop.CoopI18n")
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 0, 20, #summary + 2)
    love.graphics.setColor(0, 0, 0, 1)
    for i, l in ipairs(summary) do Font.draw(I18n.fit(l, 18), 8, 8 * i) end
    love.graphics.setColor(1, 1, 1, 1)
  elseif CoopManager.statusMessage and CoopManager.statusTimer > 0 then
    -- three rows: a Spanish notice is often longer than its English one
    local lines = wrap(CoopManager.statusMessage, 18, 3)
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 0, 20, #lines + 2)
    love.graphics.setColor(0, 0, 0, 1)
    for i, l in ipairs(lines) do
      Font.draw(l, 8, 8 * i)
    end
    love.graphics.setColor(1, 1, 1, 1)
  else
    drawHud(ow)
  end

  -- the partner's event, read along without being frozen by it
  local okStory, CoopStory = pcall(require, "src.coop.CoopStory")
  local page = okStory and CoopStory.currentPage and CoopStory.currentPage()
  if page and not hasTextBox and not isTypingChat then
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    -- the partner's game's own words: shown as they are
    Font.raw.draw(page[1] or "", 8, 112)
    Font.raw.draw(page[2] or "", 8, 128)
    -- whose scene this is, on the frame: a small blue tab
    local MicroFont = require("src.render.MicroFont")
    local who = require("src.coop.CoopI18n").truncate(string.upper(CoopManager.partner.name or "P2"), 8)
    local tw = MicroFont.width(who) + 5
    love.graphics.setColor(0.16, 0.44, 0.97, 1)
    love.graphics.rectangle("fill", 8, 94, tw, 8)
    love.graphics.setColor(1, 1, 1, 1)
    MicroFont.draw(who, 10, 95)
    love.graphics.setColor(1, 1, 1, 1)
    -- 1.20 duo: A turns it, SELECT reacts (src/coop/CoopDuo.lua)
    pcall(require("src.coop.CoopDuo").drawFeedExtras, game)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  -- our own shared scene's box, with the partner in it: SELECT reacts
  if hasTextBox then
    pcall(require("src.coop.CoopDuo").drawSceneExtras, game)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if not isTypingChat then
    -- over a dialogue box the bubble moves to the top, under any status
    local statusUp = CoopManager.statusMessage and CoopManager.statusTimer > 0
    CoopManager.drawChatBubble(hasTextBox and (statusUp and 4 or 0) or nil)
  end
  love.graphics.setColor(1, 1, 1, 1)
  CoopManager.drawOverlays(ow)
end

-- Feature overlays drawn over the field after the HUD (a minigame's clock
-- and score, src/coop/CoopMinigame.lua): fn(ow), each under pcall.
CoopManager.overlays = CoopManager.overlays or {}
function CoopManager.onDraw(name, fn) CoopManager.overlays[name] = fn end
function CoopManager.drawOverlays(ow)
  local names = {}
  for n in pairs(CoopManager.overlays) do names[#names + 1] = n end
  table.sort(names)
  for _, n in ipairs(names) do
    local ok, err = pcall(CoopManager.overlays[n], ow)
    if not ok and not CoopManager.overlayErr then
      CoopManager.overlayErr = err
      CoopLog.error("HUD", "overlay " .. n .. ": " .. tostring(err))
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- What the chat bubble shows: the partner typing live first (that is the
-- newest thing there is), then the latest message.
function CoopManager.chatBubble()
  local typing = CoopManager.partnerTyping
  if typing then
    local cursor = (math.floor(now() * 3) % 2 == 0) and "_" or " "
    local name = require("src.coop.CoopI18n").truncate(string.upper(CoopManager.partner.name or "PARTNER"), 8)
    local text = typing.text ~= "" and (typing.text .. cursor) or ("is typing" .. string.rep(".", math.floor(now() * 3) % 4))
    return name, text, true
  end
  local chat = CoopManager.activeChatMessage
  if chat and chat.timer > 0 then return chat.sender, chat.text, false end
  return nil
end

-- a chat line as it is drawn: an accented letter the font has no glyph for
-- loses its accent (CoopI18n.fitGlyphs), the way the mod's own Spanish does
local function chatGlyphs(text)
  return require("src.coop.CoopI18n").fitGlyphs(tostring(text or ""))
end
CoopManager.chatGlyphs = chatGlyphs

-- ty = nil: the classic box along the bottom; a number: a compact box at
-- that row (over dialogue, or over a battle)
function CoopManager.drawChatBubble(ty)
  local sender, text, typing = CoopManager.chatBubble()
  if not sender then return false end
  if not typing then CoopManager.chatShown = true end
  love.graphics.setColor(1, 1, 1, 1)
  if ty == nil then
    -- the name and up to five rows: a whole message from the chat box
    local lines = wrap(text, 18, 5)
    local top = 17 - (#lines + 2)
    Font.drawBox(0, top, 20, #lines + 3)
    love.graphics.setColor(0, 0, 0, 1)
    -- chat is what the players typed: never translated, only written in
    -- letters this font has ("QUÉ" as "QUE", not "QU ")
    Font.raw.draw(chatGlyphs(sender .. ":"), 8, (top + 1) * 8)
    for i, l in ipairs(lines) do Font.raw.draw(chatGlyphs(l), 8, (top + 1 + i) * 8) end
  else
    local lines = wrap(sender .. ": " .. text, 18, 6)
    Font.drawBox(0, ty, 20, #lines + 2)
    love.graphics.setColor(0, 0, 0, 1)
    for i, l in ipairs(lines) do Font.raw.draw(chatGlyphs(l), 8, (ty + i) * 8) end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- a co-op double draws the bubble across the top of the battle screen
function CoopManager.drawBattleChat(battle)
  local overlay = CoopManager.chatOverlay
  if overlay and overlay.game == (battle and battle.game) then
    overlay:draw()
    return
  end
  if not CoopManager.connected then return end
  local game = battle and battle.game
  local top = stackTop(game)
  if top and top.isChatBox then return end
  CoopManager.drawChatBubble(0)
end

-- The last `count` lines of the chat log (and the partner's live line) for
-- the chat box, wrapped to `width`.
function CoopManager.chatLines(width, count)
  local out = {}
  local function add(s)
    for _, l in ipairs(wrap(s, width, 6)) do out[#out + 1] = chatGlyphs(l) end
  end
  for _, m in ipairs(CoopManager.chatLog) do add(m.sender .. ": " .. m.text) end
  local typing = CoopManager.partnerTyping
  if typing then
    local name = require("src.coop.CoopI18n").truncate(string.upper(CoopManager.partner.name or "PARTNER"), 8)
    add(name .. ": " .. (typing.text ~= "" and (typing.text .. "_") or "..."))
  end
  local first = math.max(1, #out - count + 1)
  local tail = {}
  for i = first, #out do tail[#tail + 1] = out[i] end
  return tail
end

-- Backward compatibility for single draw call
function CoopManager.draw(ow)
  CoopManager.drawUI(ow)
end

-- the feature modules register their messages, rules and per-frame work in
-- the tables above when they load.  They require this module back, so it is
-- published first: `require` would otherwise see a module still loading.
package.loaded["src.coop.CoopManager"] = CoopManager
for _, name in ipairs(CoopManager.FEATURES or {}) do
  local ok, err = pcall(require, name)
  if not ok then CoopLog.error("MANAGER", "feature " .. name .. " failed to load: " .. tostring(err)) end
end

return CoopManager

end

return M
