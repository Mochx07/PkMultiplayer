-- LEGENDS AND BOSSES IN CO-OP (1.20, src/coop/CoopBoss.lua, capability
-- "story.bosses").
--
-- Which battles are bosses and beasts, the capability gate (a 1.6.x partner
-- gets the old battles), and two real copies of each kind of battle over an
-- in-memory bus, as coop_lockstep.lua: a wild boss and RED alone on their
-- side with more HP, moving twice a turn, the two copies agreeing on every
-- HP; a roaming beast that does not run from two and is never retired by a
-- co-op knock-out; and the partner's beasts shared for the POKEGEAR.
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
    local top = b.game.stack:top()
    if top ~= b and top and top.update then
      top:update(1 / 60)
    elseif not b:updateQueue() then
      return (b.afterQueue == "finish" or b.result) and "done" or nil
    end
  end
  error("battle queue never drained (phase " .. tostring(b.phase) .. ")")
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
  CoopBoss.guestMark(junk, { boss = "mewtwo", beast = "LUGIA" })
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
local function twoCopies(make, mark, opts)
  opts = opts or {}
  link()
  local hostGame = newGame("HOST", opts.hostTeam or { "FIXMON_A", "FIXMON_A" }, opts.level or 30)
  local guestGame = newGame("GUEST", opts.guestTeam or { "FIXMON_C", "FIXMON_C" }, opts.level or 30)
  local bus = { host = {}, guest = {} }
  local sender = "host"
  CoopManager.net = { send = function(_, m) table.insert(bus[sender == "host" and "guest" or "host"], onWire(m)) end,
                      isLinked = function() return true end, flush = function() end }
  local hw, gw = {}, {}
  for i, m in ipairs(hostGame.save.party) do hw[i] = CoopManager.wireMon(m) end
  for i, m in ipairs(guestGame.save.party) do gw[i] = CoopManager.wireMon(m) end
  local hb = make(hostGame, true)
  if opts.hostFinish then hb.onFinish = opts.hostFinish(hb) end
  mark(hb)
  hostGame.stack:push(hb)
  CoopBattle.initBattle(hb, hostGame.save.party, gw, { name = "GUEST" }, opts.seed or 4242, "BOSS")
  local gb = make(guestGame, false, hb)
  gb.isCoopGuest = true
  mark(gb)
  guestGame.stack:push(gb)
  CoopBattle.initBattle(gb, guestGame.save.party, hw, { name = "HOST" }, opts.seed or 4242, "BOSS")
  local moves = { [hb] = 0, [gb] = 0 }
  for _, b in ipairs({ hb, gb }) do
    local orig = b.executeAction
    b.executeAction = function(self, who, target, action, ...)
      if who and who == self:battlerAt(P.OPPONENT_LEFT) then moves[self] = moves[self] + 1 end
      return orig(self, who, target, action, ...)
    end
  end
  local function deliver(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m) end
    end
  end
  local function agree()
    return hpOf(hb, P.PLAYER_LEFT) == hpOf(gb, P.PLAYER_RIGHT) and hpOf(hb, P.PLAYER_RIGHT) == hpOf(gb, P.PLAYER_LEFT)
       and hpOf(hb, P.OPPONENT_LEFT) == hpOf(gb, P.OPPONENT_LEFT)
       and hpOf(hb, P.OPPONENT_RIGHT) == hpOf(gb, P.OPPONENT_RIGHT)
  end
  drain(hb); drain(gb)
  local log = { hb = hb, gb = gb, turns = {} }
  log.startHp = { hpOf(hb, P.OPPONENT_LEFT), hpOf(gb, P.OPPONENT_LEFT) }
  log.startMax = hb:battlerAt(P.OPPONENT_LEFT) and hb:battlerAt(P.OPPONENT_LEFT).mon.stats.hp
  if opts.setup then opts.setup(hb, gb) end
  for turn = 1, opts.turns or 3 do
    if hb.result or gb.result then break end
    local before = { [hb] = moves[hb], [gb] = moves[gb] }
    local foeBefore = hb:battlerAt(P.OPPONENT_LEFT)
    for _, side in ipairs({ { "host", hb }, { "guest", gb } }) do
      sender = side[1]
      local b = side[2]
      CoopBattle.currentBattle = b
      local me = b:battlerAt(P.PLAYER_LEFT)
      local locked = me and b:menuLockedAction(me)
      if locked then
        b:submitTurnAction(locked, true)
      elseif me then
        local mv = me.curMoves[1]
        mv.targetPosition = P.OPPONENT_LEFT
        CoopBattle.onLocalActionSelected(b, mv)
      else
        CoopBattle.onSpectatorTurn(b)
      end
    end
    deliver("guest"); deliver("host")
    drain(hb); drain(gb)
    log.turns[turn] = {
      agree = agree(),
      hostMoves = moves[hb] - before[hb], guestMoves = moves[gb] - before[gb],
      rightEmpty = hb:battlerAt(P.OPPONENT_RIGHT) == nil and gb:battlerAt(P.OPPONENT_RIGHT) == nil,
      foeHp = hpOf(hb, P.OPPONENT_LEFT), sameFoe = foeBefore == hb:battlerAt(P.OPPONENT_LEFT),
      result = hb.result,
    }
  end
  return log
end

-- a wild boss: SNORLAX alone, twice the HP, two moves a turn
do
  local wire
  local function make(game, isHost)
    if isHost then
      local b = BattleState.newWild(game, "FIX_SNORLAX", 30)
      wire = CoopManager.wireMon(b.enemy.mon)
      return b
    end
    return CoopWild.guestBattle(game, { species = "FIX_SNORLAX", level = 30, wildMon = onWire(wire) })
  end
  local log = twoCopies(make, function(b) b.coopBoss = "snorlax" end, { turns = 4, level = 22 })
  local hb, gb = log.hb, log.gb
  T.check(hb.coopWild and gb.coopWild, "the wild boss is a TEAM UP WILD battle on both copies (no BALL)")
  T.check(log.startMax == math.floor(wire.stats.hp * 2 + 0.5), "the boss has twice its HP (" .. tostring(log.startMax)
          .. " for " .. tostring(wire.stats.hp) .. ")")
  T.check(log.startHp[1] == log.startHp[2] and log.startHp[1] == log.startMax, "...full, and the same on both copies")
  local all, twice, empty = true, true, true
  for i, r in ipairs(log.turns) do
    all = all and r.agree
    empty = empty and r.rightEmpty
    if not r.result then twice = twice and r.hostMoves == 2 and r.guestMoves == 2 end
    if i == 1 then T.check(r.hostMoves == 2 and r.guestMoves == 2, "turn 1: the boss moves twice on both copies") end
  end
  T.check(#log.turns >= 3, "the battle ran " .. #log.turns .. " turns")
  T.check(twice, "every turn the boss moves twice, on both copies")
  T.check(empty, "the boss stands alone: no twin on the right, on either copy")
  T.check(all, "both copies agree on every HP, turn after turn")
  T.check(hb.coopBossMoves == gb.coopBossMoves and (hb.coopBossMoves or 0) >= 3,
          "the second moves were the same number on both copies (" .. tostring(hb.coopBossMoves) .. ")")
end

-- the same seed twice: the same battle (nothing of one copy's own leaks in)
do
  local function run(seed)
    math.randomseed(7)
    if love and love.math and love.math.setRandomSeed then love.math.setRandomSeed(7) end
    local wire
    local function make(game, isHost)
      if isHost then
        local b = BattleState.newWild(game, "FIX_SNORLAX", 30)
        wire = CoopManager.wireMon(b.enemy.mon)
        return b
      end
      return CoopWild.guestBattle(game, { species = "FIX_SNORLAX", level = 30, wildMon = onWire(wire) })
    end
    local log = twoCopies(make, function(b) b.coopBoss = "snorlax" end, { turns = 3, level = 22, seed = seed })
    local out = {}
    for _, r in ipairs(log.turns) do out[#out + 1] = r.foeHp .. "/" .. hpOf(log.hb, P.PLAYER_LEFT) end
    return table.concat(out, ",")
  end
  local a, b = run(99), run(99)
  T.check(a == b, "the same seed plays the same boss battle (" .. a .. ")")
end

-- RED: his team one at a time, each with 1.5x the HP and two moves a turn
do
  local function make(game) return BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1) end
  local log = twoCopies(make, function(b) b.coopBoss = "red" end, { turns = 8, level = 40,
    setup = function(hb, gb)
      for _, b in ipairs({ hb, gb }) do b:battlerAt(P.OPPONENT_LEFT).mon.hp = 1 end
    end })
  local hb, gb = log.hb, log.gb
  T.check(#hb.enemyParty == 2 and hb.enemyParty[2].stats.hp > 0, "the trainer keeps his whole team")
  local second = hb.enemyParty[2]
  local fresh = BattleState.newTrainer(newGame("X", { "FIXMON_A" }, 5), "OPP_FIX_YOUNGSTER", 1).enemyParty[2]
  T.check(second.stats.hp == math.floor(fresh.stats.hp * 1.5 + 0.5), "his bench has 1.5x the HP too ("
          .. second.stats.hp .. " for " .. fresh.stats.hp .. ")")
  local empty, all, cameIn = true, true, false
  for _, r in ipairs(log.turns) do
    empty = empty and r.rightEmpty
    all = all and r.agree
    if not r.sameFoe then cameIn = true end
  end
  T.check(log.turns[1] and not log.turns[1].sameFoe, "his lead fell on turn 1; the next one came in on the left")
  T.check(cameIn and empty, "...never beside it: the right stays empty on both copies")
  T.check(all, "both copies agree on every HP through the switch")
  T.check(hb.result == "win" and gb.result == "win", "the last of his team down: won on both copies ("
          .. tostring(hb.result) .. "/" .. tostring(gb.result) .. ")")
end

-- a roaming beast: alone, does not run from two, never retired by a co-op knock-out
do
  local hostSave, beastWire
  local finished = {}
  local function make(game, isHost)
    if isHost then
      hostSave = game.save
      game.save.g2RoamReleased = true
      game.save.g2Roam = { RAIKOU = { mapId = "ROUTE29", speciesId = "FIX_RAIKOU", landmark = 3, active = true,
                                      level = 40, hp = 0 } }
      local b = BattleState.newWild(game, "FIX_RAIKOU", 22, { battleType = "roaming", roamer = "RAIKOU", roamerHP = 0 })
      beastWire = CoopManager.wireMon(b.enemy.mon)
      return b
    end
    return CoopWild.guestBattle(game, { species = "FIX_RAIKOU", level = 22, wildMon = onWire(beastWire) })
  end
  local function hostFinish(b)
    -- what the overworld's afterBattle does with a beast (OverworldController)
    return function(result)
      finished[#finished + 1] = result
      local RoamMons = require("src.world.RoamMons")
      if b.roamer then RoamMons.retire(b.game.save, b.roamer) end
    end
  end
  local log = twoCopies(make, function(b) b.coopBeast = "RAIKOU" end, { turns = 3, level = 22, hostFinish = hostFinish })
  local hb, gb = log.hb, log.gb
  local alive = true
  for i, r in ipairs(log.turns) do
    if os.getenv("PKM_DEBUG") then print("beast turn", i, r.result, r.rightEmpty, r.agree, r.foeHp, hpOf(gb, P.OPPONENT_LEFT)) end
    alive = alive and r.result == nil and r.rightEmpty and r.agree
  end
  if os.getenv("PKM_DEBUG") then print("beast max", log.startMax, hb:battlerAt(P.OPPONENT_LEFT) and hb:battlerAt(P.OPPONENT_LEFT).mon.stats.hp) end
  T.check(#log.turns == 3 and alive, "the beast stays to fight, alone, three turns on, both copies agreeing")
  T.check(hb.roamer == "RAIKOU" and not hb.roamerEscaped, "it never ran (the host's copy is the roaming one)")
  T.check(log.turns[1].hostMoves == 1, "a beast is no boss: one move a turn")
  T.check(log.startMax == beastWire.stats.hp and log.startMax == gb:battlerAt(P.OPPONENT_LEFT).mon.stats.hp,
          "...and its own HP (" .. tostring(log.startMax) .. ")")
  -- knocked out together
  hb.enemyParty[1].hp = 0
  hb.onFinish("win")
  local kept = hostSave.g2Roam.RAIKOU
  T.check(finished[1] == "win", "the overworld still hears of the win")
  T.check(kept ~= nil and kept.hp == 1, "knocked out together, RAIKOU got away with 1 HP and still roams")
end

-- a run from a beast keeps its HP in the finder's save
do
  local game = newGame("HOST", { "FIXMON_A" }, 22)
  game.save.g2RoamReleased = true
  game.save.g2Roam = { ENTEI = { mapId = "ROUTE29", speciesId = "FIX_RAIKOU", landmark = 3, active = true, level = 40, hp = 0 } }
  local b = BattleState.newWild(game, "FIX_RAIKOU", 22, { battleType = "roaming", roamer = "ENTEI", roamerHP = 0 })
  b.coopBeast = "ENTEI"
  b.onFinish = function() end
  link()
  CoopBattle.initBattle(b, game.save.party, { CoopManager.wireMon(game.save.party[1]) }, { name = "G" }, 5, "E")
  b.enemyParty[1].hp = 37
  b.onFinish("run")
  T.check(game.save.g2Roam.ENTEI.hp == 37, "RUN together: ENTEI keeps the 37 HP it was left with")
end

-- ------------------------------------------------------------ the POKEGEAR
do
  local save = SaveData.newGame()
  T.check(#CoopBoss.beastsOf(save) == 0, "before the Burned Tower: no beasts to share")
  save.g2RoamReleased = true
  save.g2Roam = {
    SUICUNE = { mapId = "ROUTE36", speciesId = "SPECIES_245", landmark = 20, active = true },
    RAIKOU = { mapId = "ROUTE42", speciesId = "SPECIES_243", landmark = 31, active = true },
    ENTEI = { mapId = "ROUTE38", speciesId = "SPECIES_244", landmark = 24, active = false },
  }
  local list = CoopBoss.beastsOf(save)
  T.check(#list == 2 and list[1].n == "RAIKOU" and list[2].n == "SUICUNE" and list[1].l == 31,
          "our roaming beasts, in slot order, without the retired one")
  link()
  local game = { save = save, data = Data }
  CoopBoss.sentSig, CoopBoss.sentTo, CoopBoss.clock = nil, nil, 0
  sent = {}
  CoopBoss.tick(2, game)
  T.check(#sent == 1 and sent[1].type == "coop_roam" and #sent[1].beasts == 2, "they go to the partner")
  CoopBoss.tick(2, game)
  T.check(#sent == 1, "...once: nothing more while they stay put")
  save.g2Roam.RAIKOU.mapId, save.g2Roam.RAIKOU.landmark = "ROUTE43", 32
  CoopBoss.tick(2, game)
  T.check(#sent == 2 and sent[2].beasts[1].l == 32, "RAIKOU moved: the partner hears where to")
  CoopManager.partner.caps = { [CoopBoss.CAP] = true }   -- a new link
  CoopBoss.tick(2, game)
  T.check(#sent == 3, "a new link: sent again")
  link({})
  CoopBoss.sentSig = nil
  CoopBoss.tick(2, game)
  T.check(#sent == 0, "a 1.6.x partner is sent nothing")

  CoopManager.handlers.coop_roam(nil, { beasts = { { n = "ENTEI", s = "SPECIES_244", m = "ROUTE38", l = 24 },
                                                    { n = "MEW", l = 1 }, { n = "SUICUNE" }, "junk" } })
  T.check(#CoopBoss.partnerBeasts == 1 and CoopBoss.partnerBeasts[1].n == "ENTEI",
          "the partner's beasts are taken in, nothing else")
  -- drawn on the town map without error (love.graphics stubbed here)
  link()
  local calls = 0
  local lg = love and love.graphics
  if lg then
    local saved = { setColor = lg.setColor, rectangle = lg.rectangle }
    lg.setColor = function() end
    lg.rectangle = function() calls = calls + 1 end
    local timer = love.timer
    love.timer = { getTime = function() return 10.1 end }
    local ok, err = pcall(CoopBoss.drawGear, { game = { save = save, data = { pokemon = Data.pokemon,
      field = { townMap = { landmarks = { [24] = { x = 50, y = 60 } } } } } } })
    love.timer = timer
    lg.setColor, lg.rectangle = saved.setColor, saved.rectangle
    T.check(ok and calls == 1, "the partner's ENTEI gets its frame on the POKEGEAR map (" .. tostring(err) .. ")")
  end
end

-- ------------------------------------------------------------ the words
do
  local ES = require("src.coop.CoopLangES")
  local cat = type(ES) == "table" and (ES.strings or ES) or {}
  for _, k in ipairs({ "CO-OP BOSS", "%s moves\nagain!", "Boss battle: it moves twice!", "%s can't run from two!",
                       "%s got away with 1 HP!" }) do
    T.check(type(cat[k]) == "string", "Spanish for " .. k:gsub("\n", " "))
  end
end

CoopManager.connected = false
T.finish("co-op legends and bosses")
