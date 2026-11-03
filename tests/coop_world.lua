-- ONE WORLD FOR TWO (1.20, src/coop/CoopWorld.lua, capability "world.share"):
-- a Strength boulder pushed in one copy is pushed in the other; a partner
-- within 8 steps on the same map lends the field moves their own game can
-- use (their Pokemon, their badge); a 1.6.x partner changes nothing.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local CoopManager = require("src.coop.CoopManager")
local CoopWorld = require("src.coop.CoopWorld")
local I18n = require("src.coop.CoopI18n")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end }
CoopManager.connected = true
local status
CoopManager.showStatus = function(text) status = I18n.t(text) end
local function worldSent(k)
  for i = #sent, 1, -1 do
    if sent[i].type == "coop_world" and sent[i].k == k then return sent[i] end
  end
end
local function clear() for i = #sent, 1, -1 do sent[i] = nil end end

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

-- a copy of the game on map `mapId`, standing on x, y; `party` is what its
-- own partyKnows answers (move -> mon), `badges` what it holds
local function newCopy(mapId, x, y, party, badges)
  local game = { data = Data, save = { party = {} }, stack = newStack() }
  local ow = { game = game, map = { id = mapId }, player = { cellX = x, cellY = y, facing = "up" },
               npcs = {}, entities = {}, dark = false }
  ow.entities[1] = ow.player
  -- the engine's partyKnows: the move on a Pokemon AND its badge
  local function vanilla(self, move)
    local mon = party[move]
    if mon and (badges or {})[move] ~= false then return mon end
    return nil
  end
  function ow:partyKnows(move, ...) return CoopWorld.partyKnows(vanilla, self, move, ...) end
  function ow:npcByIndex(i)
    for _, n in ipairs(self.npcs) do if n.def.index == i then return n end end
  end
  function ow:npcAtCell(cx, cy)
    for _, n in ipairs(self.npcs) do if n.cellX == cx and n.cellY == cy and not n.hidden then return n end end
  end
  function ow:setDark(on) self.dark = on and true or false self.setDarkCalls = (self.setDarkCalls or 0) + 1 end
  game.overworld = ow
  game.stack:push(ow)
  return game, ow
end

local function boulder(ow, index, x, y)
  local npc = { def = { index = index, sprite = "SPRITE_BOULDER" }, cellX = x, cellY = y, px = x * 16, py = y * 16 }
  ow.npcs[#ow.npcs + 1] = npc
  ow.entities[#ow.entities + 1] = npc
  return npc
end

local function partnerAt(mapId, x, y, caps)
  CoopManager.partner = { name = "TOBY", map = mapId, cx = x, cy = y, lastSeen = CoopWorld.now(),
                          caps = caps or { [CoopWorld.CAP] = true } }
end

-- the engine's checkBoulderPush, as far as it matters here: the boulder in
-- front of the player moves one cell when STRENGTH is armed
local function enginePush(log)
  return function(self, dir)
    local d = ({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } })[dir]
    local p = self.player
    log[#log + 1] = { x = p.cellX, y = p.cellY, armed = self.strengthActive, tried = self.boulderTried }
    if not self.strengthActive then return false end
    local npc = self:npcAtCell(p.cellX + d[1], p.cellY + d[2])
    if not npc then return false end
    npc.cellX, npc.cellY = npc.cellX + d[1], npc.cellY + d[2]
    return true
  end
end

-- ------------------------------------------------------------ the cap
T.check(CoopManager.CAPS[CoopWorld.CAP] == true, "world.share is announced in the hello")
local inFeatures = false
for _, name in ipairs(CoopManager.FEATURES) do if name == "src.coop.CoopWorld" then inFeatures = true end end
T.check(inFeatures, "CoopWorld is one of the manager's feature modules")
local okOW, OverworldState = pcall(require, "src.world.OverworldController")
local ORIG = rawget(package, "__pkmultiplayer_orig") or {}
T.check(okOW and ORIG[OverworldState.partyKnows] ~= nil and ORIG[OverworldState.checkBoulderPush] ~= nil,
        "the engine's partyKnows and checkBoulderPush are wrapped (lib/Hooks.lua)")

local CUTTER = { species = "FIXMON_A", nickname = "SNIPS", level = 22, moves = { { id = "CUT" } } }
local SURFER = { species = "FIXMON_B", level = 30, moves = { { id = "SURF" } } }

-- ---------------------------------------------- what our own game lends
do
  local _, ow = newCopy("ROUTE_32", 5, 5, { CUT = CUTTER, SURF = SURFER }, { SURF = false })
  partnerAt("ROUTE_32", 6, 5)
  CoopWorld.onHms({ hms = { STRENGTH = { n = "BOOM", s = "FIXMON_C", l = 40 } } })
  local own = CoopWorld.ownHms(ow)
  T.check(own.CUT and own.CUT.n == "SNIPS" and own.CUT.s == "FIXMON_A" and own.CUT.l == 22,
          "our CUT goes to the partner with its Pokemon's name, species and level")
  T.check(own.SURF == nil, "a move whose badge we lack is not offered (SURF without the badge)")
  T.check(own.STRENGTH == nil, "what the partner lends us is never offered back as ours")
  T.check(CoopWorld.ownOnly == false, "...and partyKnows lends again afterwards")
end

-- ------------------------------------------------ borrowing a field move
do
  local game, ow = newCopy("ROUTE_32", 10, 10, {}, {})
  partnerAt("ROUTE_32", 14, 14) -- 8 steps
  CoopWorld.onHms({ hms = { CUT = { n = "FERALIGATR", s = "FIXMON_C", l = 30 },
                             FLY = { n = "PIDGEOT", s = "FIXMON_A" },
                             SURF = { n = string.rep("X", 40), s = "FIXMON_A" } } })
  T.check(CoopWorld.partnerHms.CUT and CoopWorld.partnerHms.FLY == nil and CoopWorld.partnerHms.SURF == nil,
          "the partner's list keeps only lendable moves with sane names (no FLY, no 40-letter name)")
  clear() status = nil
  local mon = ow:partyKnows("CUT")
  T.check(type(mon) == "table" and mon.nickname == "FERALIGATR" and mon.species == "FIXMON_C"
          and mon.moves[1].id == "CUT" and mon.pkmLentBy == "TOBY",
          "8 steps away on the same map: CUT is the partner's FERALIGATR")
  T.check(status == "TOBY lends you CUT", "the borrower is told (" .. tostring(status) .. ")")
  T.check(worldSent("lent") and worldSent("lent").move == "CUT", "...and so is the partner")
  clear()
  ow:partyKnows("CUT")
  T.check(worldSent("lent") == nil, "asking again for the same prompt tells nobody twice")
  T.check(ow:partyKnows("STRENGTH") == nil, "a move the partner can't use is not lent")
  T.check(game.save.party[1] == nil, "nothing is added to our party")

  CoopManager.partner.cx = 15 -- 9 steps
  T.check(ow:partyKnows("CUT") == nil, "9 steps away: no CUT")
  CoopManager.partner.cx, CoopManager.partner.map = 11, "ROUTE_33"
  T.check(ow:partyKnows("CUT") == nil, "on another map: no CUT")
  CoopManager.partner.map = "ROUTE_32"
  CoopManager.partner.lastSeen = CoopWorld.now() - 10
  T.check(ow:partyKnows("CUT") == nil, "a partner not heard from for 10 s: no CUT")
  CoopManager.partner.lastSeen = CoopWorld.now()
  T.check(ow:partyKnows("CUT") ~= nil, "back in range and fresh: CUT again")

  -- our own Pokemon always wins
  local _, ow2 = newCopy("ROUTE_32", 10, 10, { CUT = CUTTER }, {})
  T.check(ow2:partyKnows("CUT") == CUTTER, "with a CUT of our own, ours is used")

  -- a species our game does not know is still a name for the text
  CoopWorld.onHms({ hms = { SURF = { n = "LAPRAS", s = "SPECIES_NOT_HERE", l = 40 } } })
  local lapras = ow:partyKnows("SURF")
  T.check(lapras and lapras.nickname == "LAPRAS" and lapras.species == nil, "an unknown species: the name only")

  -- in Spanish
  I18n.forced = "es"
  CoopWorld.onHms({ hms = { WHIRLPOOL = { n = "KINGDRA", s = "FIXMON_A" } } })
  ow:partyKnows("WHIRLPOOL")
  T.check(status == "TOBY te presta WHIRLPOOL", "in Spanish: " .. tostring(status))
  CoopWorld.onLent(ow, { move = "CUT" })
  T.check(status == "TOBY usa tu CUT", "the lender, in Spanish: " .. tostring(status))
  I18n.forced = "en"
  CoopWorld.onLent(ow, { move = "CUT" })
  T.check(status == "TOBY borrows your CUT", "the lender is told: " .. tostring(status))
end

-- ---------------------------------------- a partner without world.share
do
  local _, ow = newCopy("ROUTE_32", 10, 10, {}, {})
  partnerAt("ROUTE_32", 11, 10, {}) -- a 1.6.x partner: no caps
  CoopWorld.partnerHms = { CUT = { n = "FERALIGATR" } }
  T.check(ow:partyKnows("CUT") == nil, "a 1.6.x partner lends nothing")
  local npc = boulder(ow, 3, 10, 9)
  local log = {}
  ow.strengthActive = true
  clear()
  local pushed = CoopWorld.checkBoulderPush(enginePush(log), ow, "up")
  T.check(pushed and npc.cellY == 8 and #sent == 0, "a boulder pushed with a 1.6.x partner: the engine's push, nothing sent")
  CoopManager.handlers.coop_world(ow, { type = "coop_world", k = "push", map = "ROUTE_32", i = 3, x = 10, y = 8, dir = "up" })
  T.check(npc.cellY == 8 and #CoopWorld.pending == 0, "...and a stray coop_world is ignored")
  CoopManager.connected = false
  partnerAt("ROUTE_32", 11, 10)
  T.check(ow:partyKnows("CUT") == nil, "not linked: nothing is lent")
  CoopManager.connected = true
end

-- --------------------------------------------- pushing a boulder: the pusher
do
  local _, ow = newCopy("MOUNT_MORTAR_B1_F", 9, 11, {}, {})
  partnerAt("MOUNT_MORTAR_B1_F", 3, 3)
  local npc = boulder(ow, 3, 9, 10)
  local log = {}
  ow.strengthActive = true
  clear()
  T.check(CoopWorld.checkBoulderPush(enginePush(log), ow, "up") == true and npc.cellY == 9, "the boulder moves up")
  local m = worldSent("push")
  T.check(m and m.map == "MOUNT_MORTAR_B1_F" and m.i == 3 and m.x == 9 and m.y == 10 and m.dir == "up",
          "the push goes to the partner: object 3 from 9,10, up")
  -- one step after it, the partner stands where it would land
  ow.player.cellY = 10
  partnerAt("MOUNT_MORTAR_B1_F", 9, 8)
  clear()
  ow.boulderTried = npc
  local before = #log
  T.check(CoopWorld.checkBoulderPush(enginePush(log), ow, "up") == false and npc.cellY == 9 and #log == before,
          "the partner on the cell behind it: the boulder does not move")
  T.check(worldSent("push") == nil and ow.boulderTried == nil, "...nothing is sent, nothing stays armed")
  -- not a boulder in front: just the engine
  ow.player.cellX = 1
  T.check(CoopWorld.checkBoulderPush(enginePush(log), ow, "up") == false and worldSent("push") == nil,
          "no boulder in front: nothing to send")
end

-- ------------------------------------- pushing a boulder: the other copy
do
  local game, ow = newCopy("MOUNT_MORTAR_B1_F", 4, 4, {}, {})
  partnerAt("MOUNT_MORTAR_B1_F", 9, 11)
  local npc = boulder(ow, 3, 9, 10)
  local log = {}
  ow.checkBoulderPush = function(self, dir) return CoopWorld.checkBoulderPush(enginePush(log), self, dir) end
  ow.strengthActive = false
  clear()
  CoopManager.handlers.coop_world(ow, { type = "coop_world", k = "push", map = "MOUNT_MORTAR_B1_F",
                                         i = 3, x = 9, y = 10, dir = "up" })
  T.check(npc.cellX == 9 and npc.cellY == 9, "the partner's push moves our boulder to the same cell")
  local call = log[#log]
  T.check(call and call.x == 9 and call.y == 11 and call.armed == true and call.tried == npc,
          "our own engine pushed it, from where the partner stood, armed as theirs was")
  T.check(ow.player.cellX == 4 and ow.player.cellY == 4 and ow.strengthActive == false,
          "we are back where we were, our STRENGTH as it was")
  T.check(worldSent("push") == nil, "a push from the partner is not sent back")
  -- the same push again (or ours arriving late): it is already there
  T.check(CoopWorld.applyPush(ow, { map = "MOUNT_MORTAR_B1_F", i = 3, x = 9, y = 10, dir = "up" }) == "already",
          "a boulder already on that cell stays")
  -- ours is somewhere else: it is put on the partner's cell
  T.check(CoopWorld.applyPush(ow, { map = "MOUNT_MORTAR_B1_F", i = 3, x = 2, y = 2, dir = "right" }) == "placed"
          and npc.cellX == 3 and npc.cellY == 2, "a boulder not where the partner pushed it from is placed on their cell")
  -- we stand where it lands: it does not go over us
  ow.player.cellX, ow.player.cellY = 4, 2
  T.check(CoopWorld.applyPush(ow, { map = "MOUNT_MORTAR_B1_F", i = 3, x = 3, y = 2, dir = "right" }) == "skip"
          and npc.cellX == 3, "a boulder is never put on us")
  -- another map, a missing object, a rock smash rock
  T.check(CoopWorld.applyPush(ow, { map = "ICE_PATH_B1_F", i = 3, x = 3, y = 2, dir = "up" }) == "skip",
          "a push on another map is not ours")
  T.check(CoopWorld.applyPush(ow, { map = "MOUNT_MORTAR_B1_F", i = 9, x = 3, y = 2, dir = "up" }) == "skip",
          "an object we do not have: nothing")
  local rock = boulder(ow, 5, 6, 6)
  rock.def.smashable = true
  T.check(CoopWorld.applyPush(ow, { map = "MOUNT_MORTAR_B1_F", i = 5, x = 6, y = 6, dir = "up" }) == "skip"
          and rock.cellY == 6, "a ROCK SMASH rock is never moved")

  -- a menu is up: the push waits for the overworld
  ow.player.cellX, ow.player.cellY = 0, 0
  CoopWorld.place(npc, 9, 10)
  game.stack:push({ isMenu = true })
  CoopManager.handlers.coop_world(ow, { type = "coop_world", k = "push", map = "MOUNT_MORTAR_B1_F",
                                         i = 3, x = 9, y = 10, dir = "down" })
  T.check(npc.cellY == 10 and #CoopWorld.pending == 1, "with a menu open the push waits")
  game.stack:pop()
  CoopWorld.flushPending(game, ow)
  T.check(npc.cellY == 11 and #CoopWorld.pending == 0, "...and happens once the overworld is back")
  for _ = 1, 20 do
    CoopWorld.onPush(ow, { map = "X", i = 1, x = 1, y = 1, dir = "up" })
    game.stack:push({}) -- not ready, so they pile up
  end
  T.check(#CoopWorld.pending <= 16, "at most 16 pushes wait")
  CoopWorld.onPush(ow, { map = "X", i = "1", x = 1, y = 1, dir = "up" })
  CoopWorld.onPush(ow, { map = "X", i = 1, x = 1, y = 1, dir = "north" })
  T.check(#CoopWorld.pending <= 16, "a malformed push is dropped")
  CoopWorld.pending = {}
end

-- ------------------------------------- walking onto the partner's map
do
  local _, host = newCopy("MOUNT_MORTAR_B1_F", 1, 1, {}, {})
  local hb = boulder(host, 3, 9, 8)
  boulder(host, 4, 12, 3).hidden = true -- fell through a hole
  local list = CoopWorld.rocks(host)
  T.check(#list == 1 and list[1].i == 3 and list[1].x == 9 and list[1].y == 8,
          "the boulders on our map: where they are, not the ones that fell")
  hb.moving, hb.targetX, hb.targetY = true, 9, 7
  T.check(CoopWorld.rocks(host)[1].y == 7, "a boulder on its way is sent where it lands")

  local _, guest = newCopy("MOUNT_MORTAR_B1_F", 9, 12, {}, {})
  local gb = boulder(guest, 3, 9, 10)
  local gb2 = boulder(guest, 4, 12, 3)
  local n = CoopWorld.applyRocks(guest, { map = "MOUNT_MORTAR_B1_F",
                                          list = { { i = 3, x = 9, y = 7 }, { i = 4, x = 9, y = 12 } } })
  T.check(n == 1 and gb.cellX == 9 and gb.cellY == 7, "walking in: the boulder is where the partner left it")
  T.check(gb2.cellX == 12 and gb2.cellY == 3, "...but never on top of us")
  T.check(CoopWorld.applyRocks(guest, { map = "ICE_PATH_B1_F", list = { { i = 3, x = 1, y = 1 } } }) == 0,
          "a list for another map changes nothing")

  -- asked by the partner: answered only on that map
  clear()
  CoopManager.handlers.coop_world(host, { type = "coop_world", k = "req", map = "ICE_PATH_B1_F" })
  T.check(worldSent("rocks") == nil, "asked about another map: no answer")
  CoopManager.handlers.coop_world(host, { type = "coop_world", k = "req", map = "MOUNT_MORTAR_B1_F" })
  T.check(worldSent("rocks") and #worldSent("rocks").list == 1, "asked about our map: our boulders")
end

-- ------------------------------------------------------ the tick
do
  local game, ow = newCopy("ROUTE_32", 5, 5, { CUT = CUTTER }, {})
  partnerAt("ROUTE_32", 6, 5)
  CoopManager.linkSerial = (CoopManager.linkSerial or 0) + 1
  clear()
  CoopManager.tickers.world(0.016, game, ow)
  T.check(worldSent("req") and worldSent("req").map == "ROUTE_32", "a new map: the partner is asked for its boulders")
  local h = worldSent("hms")
  T.check(h and h.hms.CUT and h.hms.CUT.n == "SNIPS" and h.lit == false, "...and told what we can lend")
  clear()
  CoopManager.tickers.world(1.1, game, ow)
  T.check(worldSent("hms") == nil and worldSent("req") == nil, "nothing changed: nothing sent again")
  game.save.flashLit, ow.dark = true, false
  CoopManager.tickers.world(1.1, game, ow)
  T.check(worldSent("hms") and worldSent("hms").lit == true, "we lit the cave: the partner hears")
  ow.map = { id = "ROUTE_33" }
  clear()
  CoopManager.tickers.world(0.016, game, ow)
  T.check(worldSent("req") and worldSent("req").map == "ROUTE_33", "another map: asked again")
  CoopManager.partner.caps = {}
  clear()
  ow.map = { id = "ROUTE_34" }
  CoopManager.tickers.world(1.1, game, ow)
  T.check(#sent == 0, "a partner without world.share hears nothing")
  CoopManager.partner.caps = { [CoopWorld.CAP] = true }
end

-- ------------------------------------------------------- FLASH
do
  local game, ow = newCopy("DARK_CAVE", 5, 5, {}, {})
  ow.dark = true
  partnerAt("DARK_CAVE", 20, 20)
  CoopWorld.onHms({ hms = {}, lit = true })
  T.check(CoopWorld.tickFlash(game, ow) == false and ow.dark, "the partner's FLASH 30 steps away: still dark")
  CoopManager.partner.cx, CoopManager.partner.cy = 9, 9
  status = nil
  T.check(CoopWorld.tickFlash(game, ow) == true and ow.dark == false and game.save.flashLit == true,
          "within 8 steps: their FLASH lights our cave")
  T.check(status == "TOBY lights the area with FLASH", "...and says whose it was (" .. tostring(status) .. ")")
  T.check(CoopWorld.tickFlash(game, ow) == false and ow.setDarkCalls == 1, "lit once")
  local game2, ow2 = newCopy("DARK_CAVE", 5, 5, {}, {})
  ow2.dark = true
  CoopWorld.onHms({ hms = {}, lit = false })
  T.check(CoopWorld.tickFlash(game2, ow2) == false and ow2.dark, "a partner in the dark too: nothing")
end

T.finish("co-op shared world")
