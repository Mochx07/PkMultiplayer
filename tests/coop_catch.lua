-- CATCHING TOGETHER (nightly.2, src/coop/CoopCatch.lua, "catch.together").
--
-- Two real copies of a co-op wild battle over an in-memory bus (as
-- coop_bosses.lua).  A BALL is an item action: the throw is resolved inside
-- the turn on both copies with the shared die, so both see the same shakes;
-- two balls in one turn are ONE joint throw (the better ball, catch rate x1.5);
-- after a catch the rest of the turn stands down and WHO KEEPS IT? settles
-- the same keeper on both copies -- by agreement, or by the same coin.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
require("src.battle.TypeChart").load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local CoopBattle = require("src.coop.CoopBattle")
local CoopManager = require("src.coop.CoopManager")
local CoopWild = require("src.coop.CoopWild")
local CoopBoss = require("src.coop.CoopBoss")
local GameVersion = require("src.core.GameVersion")
CoopManager.balancedFoes, CoopManager.hardFoes = false, false
require("src.coop.CoopLog").enabled = false
CoopBattle.AUTO_REPLACE = true
GameVersion.set("gold")
local P = BattleState.POS
local Json = require("src.link.Json")
local function onWire(m) return Json.decode(Json.encode(m)) end

-- a few species with the dex numbers the bosses are known by
local function clone(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = clone(v) end
  return o
end
for id, dex in pairs({ FIX_SNORLAX = 143, FIX_GYARADOS = 130, FIX_PIKACHU = 25, FIX_SUDOWOODO = 185,
                       FIX_RAIKOU = 243 }) do
  local def = clone(Data.pokemon.FIXMON_C)
  def.id, def.dex, def.name = id, dex, id:gsub("^FIX_", "")
  Data.pokemon[id] = def
end

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local function newGame(name, species, level)
  local save = SaveData.newGame()
  save.player.name = name
  save.party = {}
  for i, sp in ipairs(species) do
    local m = Pokemon.new(Data, sp, level, function(a) return a end)
    m.moves = { { id = "FIX_TACKLE", pp = 35 } }
    save.party[i] = m
  end
  return { data = Data, save = save, stack = newStack(),
           input = { wasPressed = function() return false end, isDown = function() return false end } }
end

local function drain(b)
  for _ = 1, 20000 do
    if b.coop and b.coop.localReady then return end
    local up = b.game.stack:top()
    if up and up.coopKeepMenu then return end
    -- caught and stored: the engine's POKeDEX page / nickname prompt wait on a
    -- player; the battle itself is over
    if b.result == "caught" and up ~= b then return "done" end
    local top = b.game.stack:top()
    if top ~= b and top and top.update then
      top:update(1 / 60)
    elseif not b:updateQueue() then
      return (b.afterQueue == "finish" or b.result) and "done" or nil
    end
  end
  local up = b.game.stack:top()
  local keys = {}
  for k in pairs(up or {}) do if #keys < 12 then keys[#keys + 1] = tostring(k) end end
  error("battle queue never drained (phase " .. tostring(b.phase) .. ", result " .. tostring(b.result)
        .. ", top " .. (up == b and "battle" or table.concat(keys, ",")) .. ")")
end

local function hpOf(b, pos) local x = b:battlerAt(pos); return x and x.mon and x.mon.hp or -1 end

local sent = {}
local function link(caps)
  sent = {}
  CoopManager.connected = true
  CoopManager.isConnected = function() return true end
  CoopManager.partner = { name = "TOBY", map = "ROUTE29", lastSeen = os.time() + 1e6, healthy = 3,
                          caps = caps or { [CoopBoss.CAP] = true } }
  CoopManager.net = { send = function(_, m) sent[#sent + 1] = onWire(m) end,
                      isLinked = function() return true end, flush = function() end }
end

-- ------------------------------------------------------------ the gate
T.check(CoopManager.CAPS[CoopBoss.CAP] == true, "story.bosses is announced in the hello")
local inFeatures = false
for _, name in ipairs(CoopManager.FEATURES) do if name == "src.coop.CoopBoss" then inFeatures = true end end
T.check(inFeatures, "CoopBoss is one of the manager's feature modules")

-- ------------------------------------------------------------ which battles
do
  local g = newGame("MOCHI", { "FIXMON_A" }, 30)
  local ow = { map = { id = "ROUTE36" } }
  local wood = BattleState.newWild(g, "FIX_SUDOWOODO", 20)
  T.check(CoopBoss.kindOf(wood, ow) == "sudowoodo", "a scripted SUDOWOODO is a boss")
  local lax = BattleState.newWild(g, "FIX_SNORLAX", 50)
  T.check(CoopBoss.kindOf(lax, { map = { id = "VERMILIONCITY" } }) == "snorlax", "a scripted SNORLAX is a boss")
  T.check(CoopBoss.kindOf(lax, { map = { id = "ROUTE11" }, pkmRandomEncounter = true }) == nil,
          "...but not one that jumped out of the grass")
  local plain = BattleState.newWild(g, "FIX_GYARADOS", 30)
  T.check(CoopBoss.kindOf(plain, { map = { id = "LAKE_OF_RAGE" } }) == nil, "a GYARADOS that is not red is no boss")
  local red = BattleState.newWild(g, "FIX_GYARADOS", 30, { shiny = true })
  T.check(CoopBoss.kindOf(red, { map = { id = "LAKE_OF_RAGE" } }) == "gyarados", "the Red GYARADOS at the Lake of Rage is")
  T.check(CoopBoss.kindOf(red, { map = { id = "ROUTE43" } }) == nil, "...and a shiny one fished elsewhere is not")
  local beast = BattleState.newWild(g, "FIX_RAIKOU", 40, { battleType = "roaming", roamer = "RAIKOU", roamerHP = 0 })
  T.check(CoopBoss.kindOf(beast, ow) == nil and CoopBoss.beastOf(beast) == "RAIKOU", "a roaming RAIKOU is a beast, not a boss")
  local trainer = BattleState.newTrainer(g, "OPP_FIX_YOUNGSTER", 1)
  T.check(CoopBoss.kindOf(trainer, ow) == nil, "an ordinary trainer is no boss")
  trainer.enemyParty[1] = Pokemon.new(Data, "FIX_PIKACHU", 81, function(a) return a end)
  T.check(CoopBoss.kindOf(trainer, ow) == "red", "a trainer leading with a level 81 PIKACHU is RED")

  -- the capability on both sides, or nothing changes
  link({})
  local b1 = BattleState.newWild(g, "FIX_SNORLAX", 50)
  CoopBoss.mark({ map = { id = "VERMILIONCITY" } }, b1)
  T.check(b1.coopBoss == nil, "a 1.6.x partner (no story.bosses): the boss is not marked")
  T.check(CoopBoss.offer({ map = { id = "VERMILIONCITY" } }, b1, nil) == false, "...and nothing takes the battle over")
  link()
  CoopBoss.mark({ map = { id = "VERMILIONCITY" } }, b1)
  T.check(b1.coopBoss == "snorlax", "both with story.bosses: the boss is marked")
  local gb = {}
  CoopBoss.guestMark(gb, { boss = "snorlax", beast = "ENTEI" })
  T.check(gb.coopBoss == "snorlax" and gb.coopBeast == "ENTEI", "the guest takes the host's boss and beast from the invite")
  local junk = {}
  CoopBoss.guestMark(junk, { boss = "deoxys", beast = "LUGIA" })
  T.check(junk.coopBoss == nil and junk.coopBeast == nil, "...but nothing it does not know")
  local plainMsg = {}
  CoopBoss.guestMark(plainMsg, {})
  T.check(plainMsg.coopBoss == nil, "an invite from a 1.6.x host has no boss: a plain battle")

  -- a beast asks the partner in only with TEAM UP WILD on and the partner on the map
  CoopManager.wildTogether = false
  local ow29 = { map = { id = "ROUTE29" } }
  local cb = BattleState.newWild(g, "FIX_RAIKOU", 40, { battleType = "roaming", roamer = "RAIKOU", roamerHP = 0 })
  T.check(CoopBoss.offer(ow29, cb, nil) == false and cb.coopBeast == nil, "TEAM UP WILD off: the beast is your own battle")
  CoopManager.wildTogether = true
  CoopManager.partner.map = "ROUTE30"
  T.check(CoopBoss.offer(ow29, cb, nil) == false, "the partner on another map: your own battle")
  CoopManager.partner.map = "ROUTE29"
  local CMgetGame = CoopManager.getGame
  CoopManager.getGame = function() return g end
  sent = {}
  T.check(CoopBoss.offer(ow29, cb, nil) == true and cb.coopBeast == "RAIKOU", "same map, rule on: the partner is asked in")
  local inv = sent[#sent]
  T.check(inv and inv.type == "coop_battle_invite" and inv.beast == "RAIKOU" and inv.battleKind == "wild",
          "the invite says which beast it is")
  CoopManager.pendingBattleInvite = nil
  CoopManager.getGame = CMgetGame
  CoopManager.wildTogether = false
end

-- ------------------------------------------------------------ two copies
-- `make(game)` builds each copy's battle; `mark(b)` marks it before the init

local CoopCatch = require("src.coop.CoopCatch")
local Catching = require("src.battle.Catching")

-- every throw, per copy
local throws = {}
local realAttempt = Catching.attempt
Catching.attempt = function(ball, mon, def, rng, rate, opts)
  local caught, shakes = realAttempt(ball, mon, def, rng, rate, opts)
  local b = opts and opts.battle
  throws[#throws + 1] = { battle = b, ball = ball, rate = rate, caught = caught, shakes = shakes,
                          base = def and def.catchRate }
  return caught, shakes
end

-- a co-op wild double on both copies; `pick(side)` gives each side's action
-- for the turn ("ball:<id>" or "move")
local function wildPair(species, caps, seed)
  link(caps or { [CoopCatch.CAP] = true })
  CoopManager.CAPS[CoopCatch.CAP] = true
  local hostGame = newGame("HOST", { "FIXMON_A" }, 30)
  local guestGame = newGame("GUEST", { "FIXMON_C" }, 30)
  local bus = { host = {}, guest = {} }
  local sender = "host"
  CoopManager.net = { send = function(_, m) table.insert(bus[sender == "host" and "guest" or "host"], onWire(m)) end,
                      isLinked = function() return true end, flush = function() end }
  local hw, gw = {}, {}
  for i, m in ipairs(hostGame.save.party) do hw[i] = CoopManager.wireMon(m) end
  for i, m in ipairs(guestGame.save.party) do gw[i] = CoopManager.wireMon(m) end
  local hb = BattleState.newWild(hostGame, species, 10)
  local wire = CoopManager.wireMon(hb.enemy.mon)
  hostGame.stack:push(hb)
  CoopBattle.initBattle(hb, hostGame.save.party, gw, { name = "GUEST" }, seed or 4242, "CATCH")
  local gb = CoopWild.guestBattle(guestGame, { species = species, level = 10, wildMon = onWire(wire) })
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  CoopBattle.initBattle(gb, guestGame.save.party, hw, { name = "HOST" }, seed or 4242, "CATCH")
  drain(hb); drain(gb)
  local pair = { hb = hb, gb = gb, hostGame = hostGame, guestGame = guestGame }
  function pair.deliver(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m)
      elseif CoopManager.handlers[m.type] then CoopManager.handlers[m.type](nil, m) end
    end
  end
  function pair.turn(hostPick, guestPick)
    for _, side in ipairs({ { "host", hb, hostPick }, { "guest", gb, guestPick } }) do
      sender = side[1]
      local b, pick = side[2], side[3]
      CoopBattle.currentBattle = b
      local me = b:battlerAt(P.PLAYER_LEFT)
      local ball = pick and pick:match("^ball:(.+)$")
      if ball then
        CoopBattle.onLocalActionSelected(b, { special = "playerItem", id = ball, messages = {}, coopBall = ball })
      else
        local mv = me.curMoves[1]
        mv.targetPosition = P.OPPONENT_LEFT
        CoopBattle.onLocalActionSelected(b, mv)
      end
    end
    pair.deliver("guest"); pair.deliver("host")
    drain(hb); drain(gb)
  end
  -- answer WHO KEEPS IT? on one side
  function pair.answer(side, pick)
    sender = side
    local b = side == "host" and hb or gb
    CoopBattle.currentBattle = b
    local menu = b.game.stack:top()
    local row = ({ me = 1, partner = 2, coin = 3 })[pick]
    if menu and menu.coopKeepMenu then
      b.game.stack:pop()
      menu.items[row].onSelect()
    end
    return menu and menu.coopKeepMenu
  end
  return pair
end

-- a species that is never caught (rate 1 and a poor ball: the shakes still roll)
Data.pokemon.FIX_HARD = (function()
  local d = {}
  for k, v in pairs(Data.pokemon.FIXMON_C) do d[k] = v end
  d.id, d.name, d.catchRate = "FIX_HARD", "HARD", 3
  return d
end)()
Data.pokemon.FIX_EASY = (function()
  local d = {}
  for k, v in pairs(Data.pokemon.FIXMON_C) do d[k] = v end
  d.id, d.name, d.catchRate = "FIX_EASY", "EASY", 255
  return d
end)()

-- the gate
do
  link({})
  local g = newGame("X", { "FIXMON_A" }, 10)
  local b = BattleState.newWild(g, "FIX_EASY", 5)
  b.coopWild = true
  T.check(not CoopCatch.allowed(b), "a partner without catch.together: no ball (the old rule)")
  link({ [CoopCatch.CAP] = true })
  T.check(CoopCatch.allowed(b), "both with catch.together: a ball is allowed in a co-op wild battle")
  b.coopBoss = "snorlax"
  T.check(not CoopCatch.allowed(b), "...not at a boss")
  b.coopBoss = nil
  b.kind = "trainer"
  T.check(not CoopCatch.allowed(b), "...never at a trainer's Pokemon")
end

-- the joint throw: both copies, the same single roll
do
  throws = {}
  local pair = wildPair("FIX_HARD")
  pair.turn("ball:POKE_BALL", "ball:GREAT_BALL")
  local byCopy = {}
  for _, th in ipairs(throws) do byCopy[th.battle] = (byCopy[th.battle] or 0) + 1 end
  T.check(byCopy[pair.hb] == 1 and byCopy[pair.gb] == 1, "two balls, one throw on each copy")
  local h, g
  for _, th in ipairs(throws) do if th.battle == pair.hb then h = th else g = th end end
  T.check(h and g and h.ball == "GREAT_BALL" and g.ball == "GREAT_BALL", "the better ball flies (GREAT BALL)")
  T.check(h and h.rate == math.floor(3 * 1.5 + 0.5), "the joint throw has the catch rate x1.5 (" .. tostring(h and h.rate) .. ")")
  T.check(h and g and h.caught == g.caught and h.shakes == g.shakes,
          "both copies see the same outcome (" .. tostring(h and h.shakes) .. " shakes)")
  T.check(not pair.hb.coopCaught and not pair.gb.coopCaught, "missed: the battle goes on")
  T.check(hpOf(pair.hb, P.OPPONENT_LEFT) == hpOf(pair.gb, P.OPPONENT_LEFT), "...and both copies agree on the foe's HP")
  -- one ball alone: an ordinary throw
  throws = {}
  pair.turn("move", "ball:POKE_BALL")
  h = nil
  for _, th in ipairs(throws) do if th.battle == pair.hb then h = th end end
  T.check(#throws == 2 and h and h.rate == nil and h.ball == "POKE_BALL", "one ball: an ordinary throw, on both copies")
end

-- caught: the turn stops, both are asked, and they agree
for _, case in ipairs({
  { "host says ME, guest says FOR HOST", "me", "partner", "host" },
  { "both leave it to fate", "coin", "coin", nil },
  { "both want it: the coin", "me", "me", nil },
  { "fate vs a name (the guest gives it to the host): the host", "coin", "partner", "host" },
}) do
  throws = {}
  local pair = wildPair("FIX_EASY", nil, 777)
  local hostMoves = 0
  local orig = pair.hb.executeAction
  pair.turn("ball:MASTER_BALL", "move")
  T.check(pair.hb.coopCaught and pair.gb.coopCaught, case[1] .. ": caught on both copies")
  local askedH = pair.answer("host", case[2])
  pair.deliver("guest")
  local askedG = pair.answer("guest", case[3])
  pair.deliver("host")
  T.check(askedH and askedG, case[1] .. ": both were asked WHO KEEPS IT?")
  drain(pair.hb); drain(pair.gb)
  local hostKept = #pair.hostGame.save.party == 2
  local guestKept = #pair.guestGame.save.party == 2
  T.check(hostKept ~= guestKept, case[1] .. ": exactly one of the two keeps it (host " .. tostring(hostKept)
          .. ", guest " .. tostring(guestKept) .. ")")
  if case[4] then
    T.check((case[4] == "host") == hostKept, case[1] .. ": the agreed keeper (" .. case[4] .. ") has it")
  end
  T.check(pair.hb.result == "caught" and pair.gb.result == "caught",
          case[1] .. ": both battles end as a catch (" .. tostring(pair.hb.result) .. "/" .. tostring(pair.gb.result) .. ")")
end

-- the coin is the same on both copies
do
  local a1 = CoopCatch.decide("host", "guest", 777, 1)
  local a2 = CoopCatch.decide("host", "guest", 777, 1)
  T.check(a1 == a2, "the coin falls the same way for the same battle and turn")
  T.check(CoopCatch.decide("coin", "guest", 1, 1) == "guest" and CoopCatch.decide("host", "coin", 1, 1) == "host",
          "fate and a name: the name")
end

T.finish("catching together")
