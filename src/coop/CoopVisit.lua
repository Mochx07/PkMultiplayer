-- src/coop/CoopVisit.lua
-- VISITORS: MORE THAN TWO IN THE SAME WORLD.  A co-op session is two
-- players (the shared story, the battles, the saves); up to MAX more can
-- VISIT it: they walk the same maps, see everyone and are seen, and chat and
-- emote with the whole group.  Each visitor plays their own game -- no story,
-- battles or items cross with them.
--
-- The host opens a second port (the session's port + 1) while it hosts.  A
-- visitor picks START -> CO-OP -> VISIT and types the host's address.  The
-- host relays: every visitor gets everybody's position (host, guest and the
-- other visitors) and the guest gets the visitors' over the co-op link
-- (coop_visitors); chat goes to all.
--
-- Visitor wire (JSON over its own ENet link):
--   visitor -> host  { t = "hi", name, sprite, proto, ver } { t = "pos", n, map, px, py, f, e }
--                    { t = "chat", text }
--   host -> visitor  { t = "world", list = { {id, name, sprite, map, px, py, f, e} } }
--                    { t = "chat", from, text }  { t = "full" }  { t = "old", ver }
--
-- A visitor on another protocol is told the host's version and sent home;
-- its positions carry a counter so a late one never moves it backwards, and
-- its chat is held to a few lines every few seconds.

local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")
local Json = require("src.link.Json")

local okEnet, enet = pcall(require, "enet")
if not okEnet then enet = rawget(_G, "enet") end

local CoopVisit = {}

CoopVisit.MAX = 4
CoopVisit.SEND_EVERY = 0.1
CoopVisit.CONNECT_TIMEOUT = 12

-- host side: { enetHost, port, visitors = { [peer] = info }, nextId, timer }
CoopVisit.server = nil
-- visitor side: { enetHost, peer, linked, timer, at, hostName }
CoopVisit.client = nil
-- everybody this machine should draw besides its partner: id -> entry
CoopVisit.others = {}

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function encode(t)
  local ok, s = pcall(Json.encode, t)
  return ok and s or nil
end

local function decode(s)
  local ok, t = pcall(Json.decode, s)
  return ok and type(t) == "table" and t or nil
end

local function sendTo(peer, t, reliable)
  local s = peer and encode(t)
  if s then pcall(peer.send, peer, s, 0, reliable and "reliable" or "unsequenced") end
end

-- the version this player picked: a Kanto avatar is dressed in its colour
local function myVersion()
  local ok, V = pcall(require, "src.core.GameVersion")
  return ok and V.get and V.get() or nil
end

local function myEntry(game, ow, id)
  local p = ow and ow.player
  if not (p and ow.map) then return nil end
  local e = (CoopManager.localEmoteTimer or 0) > 0 and CoopManager.localEmote or nil
  return { id = id, name = CoopManager.getLocalPlayerName(game), sprite = CoopManager.localSpriteId(p),
           map = ow.map.id, px = p.px, py = p.py, f = p.facing, e = e, game = myVersion() }
end

-- ---------------------------------------------------------------------
-- host side
-- ---------------------------------------------------------------------

function CoopVisit.startServer(port)
  if CoopVisit.server or not enet then return CoopVisit.server ~= nil end
  local ok, h = pcall(enet.host_create, ("*:%d"):format(port), CoopVisit.MAX + 1, 1)
  if not (ok and h) then
    CoopLog.warn("VISIT", "could not open the visitor port " .. tostring(port))
    return false
  end
  CoopVisit.server = { enetHost = h, port = port, visitors = {}, nextId = 1, timer = 0 }
  CoopLog.info("VISIT", "visitors can join on port " .. port)
  return true
end

function CoopVisit.stopServer()
  local srv = CoopVisit.server
  if not srv then return end
  for peer in pairs(srv.visitors) do pcall(peer.disconnect_now, peer, 0) end
  pcall(srv.enetHost.flush, srv.enetHost)
  pcall(srv.enetHost.destroy, srv.enetHost)
  CoopVisit.server = nil
  CoopVisit.others = {}
end

local function visitorList(except)
  local out = {}
  for peer, v in pairs(CoopVisit.server.visitors) do
    if peer ~= except and v.map then
      out[#out + 1] = { id = "v" .. v.id, name = v.name, sprite = v.sprite, map = v.map,
                        px = v.px, py = v.py, f = v.f, e = v.e, game = v.game }
    end
  end
  return out
end

local function broadcastChat(from, text, except)
  if not CoopVisit.server then return end
  for peer in pairs(CoopVisit.server.visitors) do
    if peer ~= except then sendTo(peer, { t = "chat", from = from, text = text }, true) end
  end
end

-- a visitor's chat line: shown here, passed to the guest and the others
local function relayChat(peer, v, text)
  CoopVisit.relaying = true
  pcall(CoopManager.onChatReceived, v.name, text, false)
  CoopVisit.relaying = false
  if CoopManager.connected and CoopManager.net then
    CoopManager.net:send({ type = "coop_chat", sender = v.name, text = text })
  end
  broadcastChat(v.name, text, peer)
end

CoopVisit.CHAT_BURST = 4      -- lines a visitor may send at once...
CoopVisit.CHAT_REFILL = 1.5   -- ...and one more every this many seconds

local function chatAllowed(v)
  local t = now()
  v.chatTokens = math.min(CoopVisit.CHAT_BURST,
                          (v.chatTokens or CoopVisit.CHAT_BURST) + (t - (v.chatAt or t)) / CoopVisit.CHAT_REFILL)
  v.chatAt = t
  if v.chatTokens < 1 then return false end
  v.chatTokens = v.chatTokens - 1
  return true
end

local function serveOnce(game, ow)
  local srv = CoopVisit.server
  for _ = 1, 64 do
    local ok, ev = pcall(srv.enetHost.service, srv.enetHost, 0)
    if not ok or not ev then break end
    if ev.type == "connect" then
      local count = 0
      for _ in pairs(srv.visitors) do count = count + 1 end
      if count >= CoopVisit.MAX then
        sendTo(ev.peer, { t = "full" }, true)
        pcall(ev.peer.disconnect_later, ev.peer, 0)
      else
        srv.visitors[ev.peer] = { id = srv.nextId, name = "VISITOR" }
        srv.nextId = srv.nextId + 1
      end
    elseif ev.type == "disconnect" then
      local v = srv.visitors[ev.peer]
      srv.visitors[ev.peer] = nil
      if v and v.named then CoopManager.showStatus(v.name .. " left", 3) end
    elseif ev.type == "receive" then
      local v = srv.visitors[ev.peer]
      local m = v and decode(ev.data)
      if m then
        if m.t == "hi" and (tonumber(m.proto) or 0) ~= CoopManager.PROTOCOL then
          sendTo(ev.peer, { t = "old", ver = CoopManager.modVersion() }, true)
          pcall(ev.peer.disconnect_later, ev.peer, 0)
          srv.visitors[ev.peer] = nil
        elseif m.t == "hi" then
          v.name = tostring(m.name or "VISITOR"):upper():sub(1, 8)
          v.sprite = m.sprite
          v.game = type(m.game) == "string" and m.game or nil
          if not v.named then
            v.named = true
            CoopManager.showStatus(v.name .. " is visiting!", 3)
            sendTo(ev.peer, { t = "chat", from = "*", text = "Welcome to " .. tostring(CoopManager.getLocalPlayerName(game)) .. "'s world!" }, true)
          end
        elseif m.t == "pos" and (tonumber(m.n) or 0) > (v.posN or 0) then
          v.posN = tonumber(m.n)
          v.map, v.px, v.py, v.f, v.e = m.map, tonumber(m.px), tonumber(m.py), m.f, m.e
        elseif m.t == "chat" and type(m.text) == "string" and m.text ~= "" and chatAllowed(v) then
          relayChat(ev.peer, v, m.text:sub(1, CoopManager.CHAT_MAX or 64))
        end
      end
    end
  end
end

local function serveWorld(game, ow, dt)
  local srv = CoopVisit.server
  srv.timer = srv.timer - dt
  if srv.timer > 0 then return end
  srv.timer = CoopVisit.SEND_EVERY
  local me = myEntry(game, ow, "h")
  local guest
  local p = CoopManager.partner
  if CoopManager.connected and p.map then
    guest = { id = "g", name = p.name, sprite = p.sprite, map = p.map, px = p.px, py = p.py,
              f = p.facing, e = (p.emoteTimer or 0) > 0 and p.emote or nil, game = p.game }
  end
  for peer in pairs(srv.visitors) do
    local list = visitorList(peer)
    if me then list[#list + 1] = me end
    if guest then list[#list + 1] = guest end
    sendTo(peer, { t = "world", list = list }, false)
  end
  pcall(srv.enetHost.flush, srv.enetHost)
  -- the guest sees the visitors too
  local visitors = visitorList(nil)
  if CoopManager.connected and CoopManager.net and (#visitors > 0 or srv.toldGuest) then
    CoopManager.net:send({ type = "coop_visitors", list = visitors }, { fast = true })
    srv.toldGuest = #visitors > 0
  end
  -- ...and so do we
  local others = {}
  for _, e in ipairs(visitors) do others[e.id] = e end
  CoopVisit.others = others
end

-- every chat line this machine shows goes on to the visitors (a visitor's own
-- line was already passed on by relayChat)
CoopManager.chatListeners = CoopManager.chatListeners or {}
CoopManager.chatListeners.visit = function(sender, text)
  if CoopVisit.relaying then return end
  broadcastChat(sender, text, nil)
end

CoopManager.handlers.coop_visitors = function(ow, msg)
  local others = {}
  for _, e in ipairs(type(msg.list) == "table" and msg.list or {}) do
    if type(e) == "table" and e.id then others[e.id] = e end
  end
  CoopVisit.others = others
end

-- ---------------------------------------------------------------------
-- visitor side
-- ---------------------------------------------------------------------

function CoopVisit.visiting()
  return CoopVisit.client ~= nil
end

function CoopVisit.visit(ip, port)
  CoopVisit.leave()
  if not enet then return false, "NO NETWORK" end
  local ok, h = pcall(enet.host_create, nil, 1, 1)
  if not (ok and h) then return false, "NETWORK UNAVAILABLE" end
  local okP, peer = pcall(h.connect, h, ("%s:%d"):format(ip, port), 1)
  if not (okP and peer) then
    pcall(h.destroy, h)
    return false, "BAD ADDRESS"
  end
  CoopVisit.client = { enetHost = h, peer = peer, linked = false, timer = 0, at = now() }
  CoopManager.chatRoute = function(sender, text)
    local c = CoopVisit.client
    if c and c.linked then sendTo(c.peer, { t = "chat", text = text }, true) end
  end
  CoopLog.info("VISIT", "visiting " .. ip .. ":" .. port)
  return true
end

function CoopVisit.leave()
  local c = CoopVisit.client
  if not c then return end
  pcall(c.peer.disconnect_now, c.peer, 0)
  pcall(c.enetHost.flush, c.enetHost)
  pcall(c.enetHost.destroy, c.enetHost)
  CoopVisit.client = nil
  CoopVisit.others = {}
  CoopManager.chatRoute = nil
end

local function visitOnce(game, ow, dt)
  local c = CoopVisit.client
  for _ = 1, 64 do
    local ok, ev = pcall(c.enetHost.service, c.enetHost, 0)
    if not ok or not ev then break end
    if ev.type == "connect" then
      c.linked = true
      sendTo(c.peer, { t = "hi", name = CoopManager.getLocalPlayerName(game),
                       sprite = ow and CoopManager.localSpriteId(ow.player), game = myVersion(),
                       proto = CoopManager.PROTOCOL, ver = CoopManager.modVersion() }, true)
    elseif ev.type == "disconnect" then
      CoopManager.showStatus(c.linked and "The visit ended" or "Host not found", 3)
      CoopVisit.leave()
      return
    elseif ev.type == "receive" then
      local m = decode(ev.data)
      if m and m.t == "world" then
        local others = {}
        for _, e in ipairs(type(m.list) == "table" and m.list or {}) do
          if type(e) == "table" and e.id then others[e.id] = e end
        end
        CoopVisit.others = others
        if not c.welcomed then
          c.welcomed = true
          CoopManager.showStatus("Visiting!", 3)
        end
      elseif m and m.t == "chat" then
        CoopManager.onChatReceived(m.from == "*" and "HOST" or m.from, m.text, false)
      elseif m and m.t == "full" then
        CoopManager.showStatus("That world is full", 3)
      elseif m and m.t == "old" then
        c.linked = false
        CoopManager.showStatus("The host has PkMultiplayer v" .. tostring(m.ver or "?") .. ": update to the same version", 5)
      end
    end
  end
  if not c.linked and now() - c.at > CoopVisit.CONNECT_TIMEOUT then
    CoopManager.showStatus("Host not found", 3)
    CoopVisit.leave()
    return
  end
  c.timer = c.timer - dt
  if c.linked and c.timer <= 0 and ow then
    c.timer = CoopVisit.SEND_EVERY
    local me = myEntry(game, ow, "me")
    if me then
      me.t = "pos"
      c.posN = (c.posN or 0) + 1
      me.n = c.posN
      sendTo(c.peer, me, false)
    end
  end
  pcall(c.enetHost.flush, c.enetHost)
end

-- ---------------------------------------------------------------------
-- everybody else, walking on this map
-- ---------------------------------------------------------------------

CoopVisit.avatars = {} -- id -> { npc, x, y, entry }

local function unlistNpc(ow, npc)
  for _, name in ipairs({ "npcs", "entities" }) do
    local list = ow and ow[name]
    if list then
      for i = #list, 1, -1 do if list[i] == npc then table.remove(list, i) end end
    end
  end
end

function CoopVisit.clearAvatars(ow)
  for id, a in pairs(CoopVisit.avatars) do
    if ow then unlistNpc(ow, a.npc) end
    CoopVisit.avatars[id] = nil
  end
end

local function makeAvatar(game, ow, entry, slot)
  local NPC = require("src.world.NPC")
  local sprite = entry.sprite
  if not (type(sprite) == "string" and game.data.sprites and game.data.sprites[sprite]) then
    sprite = "SPRITE_RED"
    if not (game.data.sprites and game.data.sprites[sprite]) then return nil end
  end
  local ok, npc = pcall(NPC.new, game.data, ow.map.id, {
    index = 960 + slot, name = "COOP_VISITOR", sprite = sprite,
    x = 0, y = 0, movement = "STAY", range = "NONE",
  })
  if not ok or not npc then return nil end
  npc.coopVisitor = true
  npc.passable = true
  npc.mapId = ow.map.id
  npc.spriteName = sprite
  npc.update = function() end
  pcall(CoopManager.applyPartnerPalette, npc, entry.game)
  ow.npcs = ow.npcs or {}
  ow.entities = ow.entities or {}
  table.insert(ow.npcs, npc)
  table.insert(ow.entities, npc)
  return npc
end

function CoopVisit.updateAvatars(game, ow, dt)
  if not (ow and ow.map) then return end
  local seen, slot = {}, 0
  for id, e in pairs(CoopVisit.others) do
    slot = slot + 1
    if e.map == ow.map.id and tonumber(e.px) and tonumber(e.py) then
      seen[id] = true
      local a = CoopVisit.avatars[id]
      if a and (a.npc.mapId ~= ow.map.id or a.sprite ~= e.sprite) then
        unlistNpc(ow, a.npc)
        a = nil
      end
      if not a then
        local npc = makeAvatar(game, ow, e, slot)
        if npc then
          a = { npc = npc, x = e.px, y = e.py, sprite = e.sprite }
          CoopVisit.avatars[id] = a
        end
      end
      if a then
        a.entry = e
        local dx, dy = e.px - a.x, e.py - a.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local moved = 0
        if dist > 48 then a.x, a.y = e.px, e.py
        elseif dist > 0.01 then
          local step = math.min(dist, math.max(60, dist * 9) * dt)
          a.x, a.y = a.x + dx / dist * step, a.y + dy / dist * step
          moved = step
        end
        local npc = a.npc
        npc.px, npc.py = math.floor(a.x + 0.5), math.floor(a.y + 0.5)
        npc.cellX, npc.cellY = math.floor((npc.px + 8) / 16), math.floor((npc.py + 8) / 16)
        npc.facing = e.f or "down"
        npc.moving = moved > 0
        if moved > 0 then npc.progress = ((npc.progress or 0) + moved) % 16 end
      end
    end
  end
  for id, a in pairs(CoopVisit.avatars) do
    if not seen[id] then
      unlistNpc(ow, a.npc)
      CoopVisit.avatars[id] = nil
    end
  end
end

-- names over their heads, and their emotes
CoopManager.worldDrawers = CoopManager.worldDrawers or {}
CoopManager.worldDrawers.visit = function(ow)
  local MicroFont = require("src.render.MicroFont")
  local game = CoopManager.getGame(ow)
  for _, a in pairs(CoopVisit.avatars) do
    local e = a.entry or {}
    local sx, sy = CoopManager.screenPoint(ow, a.npc.px, a.npc.py)
    local name = tostring(e.name or "?"):upper():sub(1, 8)
    local bw = math.max(16, MicroFont.width(name) + 6)
    local bx, by = math.floor(sx - bw / 2), math.floor(sy + 2)
    CoopManager.drawPill(bx, by, bw, 9)
    love.graphics.setColor(0, 0, 0, 1)
    MicroFont.draw(name, bx + 3, by + 2)
    love.graphics.setColor(1, 1, 1, 1)
    if e.e then
      pcall(function() require("src.coop.CoopEmotes").draw(game, e.e, sx, sy, 0.5) end)
    end
  end
end

-- ---------------------------------------------------------------------
-- per frame
-- ---------------------------------------------------------------------

CoopManager.onIdleTick("visit", function(dt, game, ow)
  -- the host's door is open exactly while it hosts
  local net = CoopManager.net
  local hosting = CoopManager.isHost and net and not net.closed and net.isHost
  if hosting and not CoopVisit.server then
    CoopVisit.startServer((tonumber(net.port) or 7777) + 1)
  elseif not hosting and CoopVisit.server then
    CoopVisit.stopServer()
  end
  if CoopVisit.server then
    serveOnce(game, ow)
    if CoopVisit.server then serveWorld(game, ow, dt) end
  end
  if CoopVisit.client then visitOnce(game, ow, dt) end
  if not CoopVisit.server and not CoopVisit.client and not CoopManager.connected then
    if next(CoopVisit.others) then CoopVisit.others = {} end
  end
  CoopVisit.updateAvatars(game, ow, dt)
end)

return CoopVisit
