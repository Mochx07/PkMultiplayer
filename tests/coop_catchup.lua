-- NOBODY LEFT BEHIND, NOBODY WAITING FOR NOTHING (src/coop/CoopCatchUp.lua).
--
--   1. a hold whose scene died before its end is lifted all the same;
--   2. a big battle's answer that lands while the host picks their three
--      (the partner's team ready, or B in READ ALONG) is not lost;
--   3. CATCH UP: the one behind in badges asks to fly to the partner's last
--      key town, the partner says yes or no, no badges change hands;
--   4. a team far behind: boosted EXP on its owner's copy, and the foe is
--      levelled against the weaker team (both copies, behind the cap).
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local CoopManager = require("src.coop.CoopManager")
local CoopStory = require("src.coop.CoopStory")
local CoopCatchUp = require("src.coop.CoopCatchUp")
local CoopBalance = require("src.coop.CoopBalance")
require("src.coop.CoopLog").enabled = false

local sent = {}
local function sentOf(kind)
  local out = {}
  for _, m in ipairs(sent) do if m.type == kind then out[#out + 1] = m end end
  return out
end
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end }
CoopManager.connected = true
CoopManager.isConnected = function() return true end
CoopManager.storySync = true
CoopManager.partner = CoopManager.partner or {}
CoopManager.partner.name = "TOBY"
CoopManager.partner.healthy = 3
CoopManager.partner.lastSeen = math.huge
CoopManager.partner.caps = { [CoopCatchUp.CAP] = true }

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

T.check(CoopManager.CAPS[CoopCatchUp.CAP] == true, "the story.catchup capability is announced in the hello")
local listed = false
for _, c in ipairs(CoopManager.localCaps()) do if c == CoopCatchUp.CAP then listed = true end end
T.check(listed, "...in the hello's caps list")

-- ---------------------------------------------------------------------
-- 1. the hold goes with its script
-- ---------------------------------------------------------------------
do
  local runner = { co = true }
  function runner:isRunning() return self.co ~= nil end
  local ctx = { coopHoldSent = true, coopHoldSent_map = "BURNED_TOWER1_F" }
  runner.ctx = ctx
  local game = { overworld = { runner = runner } }
  sent = {}
  CoopCatchUp.watchHold(game)
  T.check(#sentOf("coop_story_release") == 0, "hold: kept while its scene is still running")
  -- a script error, or the engine putting a stranded script down
  -- (OverworldState:watchStuckScript): the coroutine is simply dropped,
  -- and ScriptRunner:run never reaches CoopStory.finish
  runner.co = nil
  T.check(CoopCatchUp.watchHold(game) == true, "hold: the scene died -- the watchdog lifts it")
  local rel = sentOf("coop_story_release")
  T.check(#rel == 1 and rel[1].map == "BURNED_TOWER1_F", "hold: the partner is told (coop_story_release)")
  T.check(ctx.coopHoldSent == nil, "hold: marked lifted, so the scene's own end would not send it again")
  CoopCatchUp.watchHold(game)
  T.check(#sentOf("coop_story_release") == 1, "hold: lifted once")

  -- the partner's side: their game stops holding that scene
  CoopStory.onPartnerHold({ map = "BURNED_TOWER1_F", class = "OPP_RIVAL1" })
  local owB = { map = { id = "BURNED_TOWER1_F" } }
  T.check(CoopStory.heldHere(owB, "OPP_RIVAL1"), "hold: (the partner's game was holding it)")
  CoopStory.onPartnerRelease(rel[1])
  T.check(not CoopStory.heldHere(owB, "OPP_RIVAL1"), "hold: ...and can play that scene again")

  -- the usual way: the scene ends (CoopStory.finish) -- nothing more from here
  sent = {}
  local ctx2 = { coopHoldSent = true, coopHoldSent_map = "VIOLET_GYM" }
  runner.co, runner.ctx = true, ctx2
  CoopCatchUp.watchHold(game)
  CoopStory.finish(ctx2)
  runner.co = nil
  CoopCatchUp.watchHold(game)
  T.check(#sentOf("coop_story_release") == 1, "hold: a scene that ends normally sends one release, not two")

  -- another script starts after the held one died: still lifted
  sent = {}
  local ctx3 = { coopHoldSent = true, coopHoldSent_map = "ECRUTEAK_GYM" }
  runner.co, runner.ctx = true, ctx3
  CoopCatchUp.watchHold(game)
  runner.ctx = { }     -- the runner moved on to a sign's text
  CoopCatchUp.watchHold(game)
  T.check(#sentOf("coop_story_release") == 1, "hold: a new script on the same runner does not keep the dead one's hold")
end

-- ---------------------------------------------------------------------
-- 2. the big battle's answer while the host picks their three
-- ---------------------------------------------------------------------
local selects, pushed = {}, {}
package.loaded["src.coop.CoopBattleSelect"] = { new = function(game, party, onPick, onCancel)
  local s = { isCoopBattleSelect = true, onPick = onPick, onCancel = onCancel }
  selects[#selects + 1] = s
  return s
end }
local function hostGame()
  local save = SaveData.newGame()
  save.player.name = "MOCHI"
  save.party = { Pokemon.new(Data, "FIXMON_A", 20, function(a) return a end) }
  local game = { data = Data, save = save, stack = newStack(),
                 input = { wasPressed = function() return false end, isDown = function() return false end } }
  local ow = { game = game, map = { id = "VIOLET_GYM" } }
  function ow:pushBattle(b, opts) pushed[#pushed + 1] = b end
  game.overworld = ow
  return game, ow
end
local function waitModalUp(game)
  for _, s in ipairs(game.stack.states) do if s.isCoopWaitModal then return s end end
  return nil
end
local CoopBattle = require("src.coop.CoopBattle")
local realInit = CoopBattle.initBattle
CoopBattle.initBattle = function(battle, mine, theirs) battle.coopDouble = true battle.partnerMons = theirs end

-- (a) the partner's three arrive while the host is still picking
do
  local game, ow = hostGame()
  selects, pushed, sent = {}, {}, {}
  CoopManager.bigBattle = { inviteId = "BIG-1", oppClass = "OPP_LEADER", partyIndex = 1, name = "FALKNER" }
  local battle = { kind = "trainer", oppClass = "OPP_LEADER", partyIndex = 1 }
  T.check(CoopManager.promptCoopBattle(ow, battle, {}) == true, "late ready: the host's team picker opens")
  T.check(#selects == 1, "late ready: (picker up)")
  CoopManager.onBigBattleReady(ow, { inviteId = "BIG-1", chosenMons = { { species = "FIXMON_B", level = 18 } } })
  T.check(#sentOf("coop_battle_cancel") == 0, "late ready: the partner is not thrown out (no coop_battle_cancel)")
  selects[1].onPick(game.save.party)
  T.check(#sentOf("coop_bigbattle_go") == 1, "late ready: the battle starts together the moment the host has picked")
  T.check(pushed[1] == battle and battle.coopDouble and battle.partnerMons[1].species == "FIXMON_B",
          "late ready: a co-op double with the partner's three")
  T.check(waitModalUp(game) == nil, "late ready: no WAITING box for an answer that already came")
  local go = sentOf("coop_bigbattle_go")[1]
  T.check(go ~= nil and type(go.foeRules) == "table" and go.foeRules.balancedFoes == true,
          "late ready: the go carries the host's difficulty for the guest's copy")
  T.check(CoopManager.hostingBig == nil, "late ready: nothing left over")
end

-- (b) the partner leaves (B in READ ALONG, or its time ran out) while the host picks
do
  local game, ow = hostGame()
  selects, pushed, sent = {}, {}, {}
  CoopManager.pendingBattleInvite = nil
  CoopManager.bigBattle = { inviteId = "BIG-2", oppClass = "OPP_LEADER", partyIndex = 1, name = "FALKNER",
                            partnerMons = { { species = "FIXMON_B", level = 18 } } }
  local battle = { kind = "trainer", oppClass = "OPP_LEADER", partyIndex = 1 }
  CoopManager.promptCoopBattle(ow, battle, {})
  CoopManager.onBattleDeclined(ow, { inviteId = "BIG-2", reason = "declined" })
  selects[1].onPick(game.save.party)
  T.check(#sentOf("coop_bigbattle_go") == 0, "left: no go to a partner who left (it fought them with the AI)")
  T.check(waitModalUp(game) == nil, "left: no 60s WAITING box for nobody")
  T.check(pushed[1] == battle and not battle.coopDouble, "left: the host battles solo at once")
  T.check(CoopManager.hostingBig == nil, "left: nothing left over")
end

-- (c) a ready for an invite nobody is hosting is still answered with a cancel
do
  sent = {}
  CoopManager.bigBattle, CoopManager.hostingBig, CoopManager.pendingBattleInvite = nil, nil, nil
  CoopManager.onBigBattleReady({}, { inviteId = "OLD" })
  T.check(#sentOf("coop_battle_cancel") == 1, "an answer to an invite long gone still tells them we went solo")
end
CoopBattle.initBattle = realInit
CoopManager.bigBattle = nil

-- ---------------------------------------------------------------------
-- 3. CATCH UP
-- ---------------------------------------------------------------------
-- a small world: three towns in FLY order, a cave between
local W = {
  field = {
    flyOrder = { "NEW_BARK_TOWN", "VIOLET_CITY", "GOLDENROD_CITY", "UNION_CAVE" },
    flyWarps = { NEW_BARK_TOWN = { x = 13, y = 6, name = "NEW BARK TOWN" },
                 VIOLET_CITY = { x = 31, y = 26, name = "VIOLET CITY" },
                 GOLDENROD_CITY = { x = 15, y = 28, name = "GOLDENROD CITY" },
                 UNION_CAVE = { x = 5, y = 5 } },
  },
  maps = { NEW_BARK_TOWN = { outdoor = true }, VIOLET_CITY = { outdoor = true },
           GOLDENROD_CITY = { outdoor = true }, UNION_CAVE = { outdoor = false },
           ROUTE_31 = { outdoor = true } },
  constants = { badges = { { id = "ZEPHYRBADGE" }, { id = "HIVEBADGE" }, { id = "PLAINBADGE" }, { id = "FOGBADGE" } } },
}
local function worldGame(name, at)
  local save = SaveData.newGame()
  save.player.name = name
  save.flags = save.flags or {}
  save.visited = {}
  local game = { data = W, save = save, stack = newStack(),
                 input = { wasPressed = function() return false end, isDown = function() return false end } }
  local ow = { game = game, map = { id = at }, player = {} }
  ow.flown = nil
  function ow:flyTo(id) self.flown = id end
  game.overworld = ow
  return game, ow
end

-- the key town of a save that never kept one: the furthest it has been to
local gA, owA = worldGame("MOCHI", "NEW_BARK_TOWN")
gA.save.visited = { NEW_BARK_TOWN = true, VIOLET_CITY = true, GOLDENROD_CITY = true, UNION_CAVE = true }
gA.save.flags.ZEPHYRBADGE, gA.save.flags.HIVEBADGE, gA.save.flags.PLAINBADGE = true, true, true
T.eq(CoopCatchUp.keyTown(gA), "GOLDENROD_CITY", "key town: the furthest town reached, in FLY order")
-- flying home does not make home the key town; a NEW town does
owA.map.id = "NEW_BARK_TOWN"
T.check(CoopCatchUp.noteTown(gA) == false and gA.save.coopKeyTown == "GOLDENROD_CITY",
        "key town: going back somewhere already reached changes nothing")
gA.save.coopTownsSeen.ECRUTEAK_CITY = nil
W.maps.ECRUTEAK_CITY = { outdoor = true }
W.field.flyWarps.ECRUTEAK_CITY = { x = 23, y = 28, name = "ECRUTEAK CITY" }
owA.map.id = "ECRUTEAK_CITY"
T.check(CoopCatchUp.noteTown(gA) == true and gA.save.coopKeyTown == "ECRUTEAK_CITY", "key town: a new town is the new key town")
owA.map.id = "UNION_CAVE"
T.check(CoopCatchUp.noteTown(gA) == false, "key town: a cave is no town")
owA.map.id = "GOLDENROD_CITY"

-- the info goes out only to a partner that has the capability
sent = {}
CoopManager.partner.caps = {}
T.check(CoopCatchUp.sendInfo(gA) == false and #sent == 0, "1.6.x partner: nothing new goes on the wire")
CoopManager.partner.caps = { [CoopCatchUp.CAP] = true }
T.check(CoopCatchUp.sendInfo(gA) == true, "info: sent to a partner with story.catchup")
local info = sentOf("coop_catchup_info")[1]
T.check(info and info.town == "ECRUTEAK_CITY" and #info.badges == 3, "info: the key town and the three badges")
T.check(CoopCatchUp.sendInfo(gA) == false, "info: not sent again while nothing changed")
gA.save.flags.FOGBADGE = true
T.check(CoopCatchUp.sendInfo(gA) == true, "info: sent again when a badge is won")
gA.save.flags.FOGBADGE = nil
CoopCatchUp.sendInfo(gA)

-- the other copy: one badge, in Violet
local gB, owB = worldGame("TOBY", "VIOLET_CITY")
gB.save.flags.ZEPHYRBADGE = true
CoopCatchUp.onInfo(sentOf("coop_catchup_info")[#sentOf("coop_catchup_info")])
T.check(CoopCatchUp.behind(gB), "behind: one badge against the partner's three")
local miss = CoopCatchUp.missing(gB)
T.eq(table.concat(miss, ","), "HIVEBADGE,PLAINBADGE", "behind: the badges the partner has and you lack")
local text = CoopCatchUp.describe(gB)
T.check(text:find("TOBY has 2\nbadges you lack:", 1, true) and text:find("HIVE, PLAIN", 1, true),
        "the box says how many and which (" .. text:gsub("\n", "/"):gsub("\f", " | ") .. ")")
for line in (text .. "\n"):gsub("\f", "\n"):gmatch("(.-)\n") do
  T.check(#line <= 18, "box line fits 18 columns: '" .. line .. "'")
end

-- the one ahead is not offered it
CoopManager.partner.catchup = { town = "VIOLET_CITY", badges = { "ZEPHYRBADGE" } }
T.check(not CoopCatchUp.behind(gA), "ahead: no CATCH UP")
CoopManager.partner.catchup = nil
CoopCatchUp.onInfo(CoopCatchUp.info(gA))

-- the menu row
local CoopMenu = require("src.coop.CoopMenu")
local function labels(game)
  local menu = CoopMenu.new(game)
  local out = {}
  for _, r in ipairs(menu:connectedRows(game.overworld)) do out[#out + 1] = r.label end
  return table.concat(out, "|"), menu
end
local rowsB = labels(gB)
T.check(rowsB:find("CATCH UP", 1, true), "menu: CATCH UP for the one behind (" .. rowsB .. ")")
T.check(rowsB:find("WARP", 1, true) and rowsB:find("WARP", 1, true) < rowsB:find("CATCH UP", 1, true),
        "menu: right after the warp row")
CoopManager.partner.caps = {}
T.check(not labels(gB):find("CATCH UP", 1, true), "menu: not with a 1.6.x partner")
CoopManager.partner.caps = { [CoopCatchUp.CAP] = true }
local savedInfo = CoopManager.partner.catchup
CoopManager.partner.catchup = { town = "NEW_BARK_TOWN", badges = {} }
T.check(not labels(gB):find("CATCH UP", 1, true), "menu: not for the one ahead")
CoopManager.partner.catchup = savedInfo
for _, r in ipairs((select(2, labels(gB))):connectedRows(owB)) do
  if r.label == "CATCH UP" then
    T.check(r.info[1] == "2 BADGES BEHIND.", "menu: its box says how far behind (" .. tostring(r.info[1]) .. ")")
  end
end

-- the rules, like WARP TO PARTNER
CoopManager.lastWarpAt = nil
local ok, why = CoopCatchUp.canCatchUp(gB, owB)
T.check(ok and why == "ECRUTEAK_CITY", "rules: free to go, to the partner's key town (" .. tostring(why) .. ")")
CoopManager.partner.inBattle = true
T.check(select(2, CoopCatchUp.canCatchUp(gB, owB)) == "Partner is busy", "rules: not while the partner battles")
CoopManager.partner.inBattle = nil
owB.player.surfing = true
T.check(not CoopCatchUp.canCatchUp(gB, owB), "rules: not off the water")
owB.player.surfing = nil
CoopManager.lastWarpAt = (love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
local _, cool = CoopCatchUp.canCatchUp(gB, owB)
T.check(tostring(cool):find("^Warp ready in"), "rules: shares the warp's cooldown (" .. tostring(cool) .. ")")
CoopManager.lastWarpAt = nil
gB.stack:push({ kind = "trainer" })
T.check(select(2, CoopCatchUp.canCatchUp(gB, owB)) == "Can't warp in battle!", "rules: not from a battle")
gB.stack:pop()
owB.map.id = "ECRUTEAK_CITY"
T.check(select(2, CoopCatchUp.canCatchUp(gB, owB)) == "You are already there", "rules: not when already there")
owB.map.id = "VIOLET_CITY"
W.field.flyWarps.ECRUTEAK_CITY = nil
T.check(select(2, CoopCatchUp.canCatchUp(gB, owB)) == "No town to go to", "rules: only a town this game can fly to")
W.field.flyWarps.ECRUTEAK_CITY = { x = 23, y = 28, name = "ECRUTEAK CITY" }

-- the row: the box, then YES asks the partner
local TB = require("src.render.TextBox")
local realTB = TB.new
local boxes = {}
TB.new = function(game, txt, onDone, opts) local b = { text = txt, onDone = onDone, opts = opts } boxes[#boxes + 1] = b return b end
sent = {}
T.check(CoopCatchUp.open(gB, owB) == true, "open: the box with the question")
local box = boxes[#boxes]
T.check(box and box.text:find("Meet TOBY in\nECRUTEAK CITY?", 1, true), "open: ...ends 'Meet TOBY in ECRUTEAK CITY?'")
T.check(box and box.opts and box.opts.defaultNo == true, "open: the cursor starts on NO")
T.check(#sentOf("coop_catchup_req") == 0, "open: nothing asked before YES")
box.opts.choice(true)
local req = sentOf("coop_catchup_req")[1]
T.check(req and req.town == "ECRUTEAK_CITY", "YES: the partner is asked")
T.check(CoopCatchUp.request(gB, owB) == false, "a second request waits for the first answer")

-- the partner's game: asked only when idle
local gP, owP = worldGame("TOBY", "ECRUTEAK_CITY")
gP.stack:push(owP)
sent = {}
gP.stack:push({ isTextBox = true })
CoopCatchUp.onRequest(gP, owP, req)
T.check(sentOf("coop_catchup_reply")[1] and sentOf("coop_catchup_reply")[1].why == "busy", "partner busy: answered busy at once")
gP.stack:pop()
sent, boxes = {}, {}
CoopCatchUp.onRequest(gP, owP, req)
local ask = boxes[#boxes]
T.check(ask and ask.text:find("wants to\ncatch up. OK?", 1, true) and ask.opts.defaultNo, "partner: asked YES/NO, NO first")
ask.opts.choice(false)
local no = sentOf("coop_catchup_reply")[1]
T.check(no and no.ok == false, "partner: NO goes back")
CoopCatchUp.onReply(gB, owB, no)
T.check(owB.flown == nil and CoopCatchUp.ask == nil, "NO: nobody flies")

-- YES: the flight, the cooldown, the partner told; the badges stay where they are
CoopCatchUp.request(gB, owB)
req = sentOf("coop_catchup_req")[#sentOf("coop_catchup_req")]
sent = {}
T.check(CoopCatchUp.onReply(gB, owB, { id = req.id, ok = true }) == true, "YES: the flight starts")
T.check(owB.flown == "ECRUTEAK_CITY", "YES: FLY to the partner's key town")
T.check(CoopManager.warpCooldownLeft() > 0, "YES: the warp's cooldown starts")
T.check(#sentOf("coop_catchup_done") == 1, "YES: the partner hears of it")
T.check(require("src.inventory.Badges").count(W, gB.save) == 1, "no badges handed out")
TB.new = realTB

-- an answer that comes too late
CoopManager.lastWarpAt = nil
CoopCatchUp.request(gB, owB)
CoopCatchUp.ask.at = CoopCatchUp.ask.at - 100
owB.flown = nil
CoopCatchUp.onReply(gB, owB, { id = CoopCatchUp.ask.id, ok = true })
T.check(owB.flown == nil, "an answer after the time ran out moves nobody")

-- a partner message with junk in it
CoopCatchUp.onInfo({ town = string.rep("X", 500), badges = { 5, "HIVEBADGE", {} } })
T.check(CoopManager.partner.catchup.town == nil and #CoopManager.partner.catchup.badges == 1, "junk in the info is dropped")

-- ---------------------------------------------------------------------
-- 4. a team far behind
-- ---------------------------------------------------------------------
local function team(n, level)
  local out = {}
  for i = 1, n do out[i] = Pokemon.new(Data, i % 2 == 0 and "FIXMON_B" or "FIXMON_A", level, function(a) return a end) end
  return out
end

T.check(CoopCatchUp.gap(team(3, 10), team(3, 30)) == 20 and CoopCatchUp.gap(team(3, 30), team(3, 10)) == 0,
        "gap: how far YOUR three trail the partner's")

-- the foe, levelled against the weaker team -- with the rule, on both copies
do
  local foes = team(2, 20)
  local strong, weak = team(3, 40), team(3, 12)
  local without = CoopBalance.plan(foes, weak, strong, { balancedFoes = true })
  T.check(without and without.boost == 2, "no rule: the pair's average (26) is far over the foe's 20: +2")
  local with = CoopBalance.plan(foes, weak, strong, { balancedFoes = true, catchUp = true })
  T.check(with and with.boost == 0, "catchUp: levelled against the weaker three (12): no levels added")
  local mirror = CoopBalance.plan(foes, strong, weak, { balancedFoes = true, catchUp = true })
  T.check(mirror and mirror.boost == with.boost and mirror.foes == with.foes, "catchUp: the other copy works out the same")
  local close = CoopBalance.plan(foes, team(3, 24), team(3, 28), { balancedFoes = true, catchUp = true })
  T.check(close and close.boost == 2, "catchUp: teams close together keep the usual rule")
  local hard = CoopBalance.plan(foes, weak, strong, { hardFoes = true, catchUp = true })
  T.check(hard and hard.boost == 3, "HARD FOES stays hard")
end
-- the rule travels only when both copies have it
CoopManager.partner.caps = {}
T.check(CoopBalance.currentRules().catchUp == nil, "1.6.x partner: the invite's foe rules are as before")
CoopManager.partner.caps = { [CoopCatchUp.CAP] = true }
T.check(CoopBalance.currentRules().catchUp == true, "both 1.20: the foe rules carry catchUp")
-- and the guest's copy reads it from the invite
do
  local made
  local BS = require("src.battle.BattleState")
  local realNew = BS.newTrainer
  BS.newTrainer = function() made = { kind = "trainer" } return made end
  local realI = CoopBattle.initBattle
  CoopBattle.initBattle = function() end
  local g = { stack = newStack(), save = SaveData.newGame() }
  CoopManager.startGuestBattle(g, { game = g }, { oppClass = "OPP_LEADER", foeRules = { balancedFoes = true, catchUp = true } }, {})
  T.check(made and made.coopBalanceRules and made.coopBalanceRules.catchUp == true, "guest: the invite's catchUp is applied")
  BS.newTrainer, CoopBattle.initBattle = realNew, realI
end

-- boosted EXP, on the owner's copy, for the one far behind
do
  local game = { save = { party = team(3, 10) } }
  local paidTraded = {}
  local b = { game = game, enemyParty = team(2, 20), coopBalanceRules = { balancedFoes = true } }
  b.awardExp = function(self, fallen)
    for i, m in ipairs(self.game.save.party) do paidTraded[i] = m.traded end
  end
  game.save.party[2].traded = false
  T.check(CoopCatchUp.prepareBattle(b, game.save.party, team(3, 30)) == true, "far behind: boosted EXP this battle")
  b:awardExp({})
  T.check(paidTraded[1] == true and paidTraded[3] == true, "far behind: paid as the cartridge pays a traded Pokemon (x1.5)")
  T.check(game.save.party[1].traded == nil and game.save.party[2].traded == false, "...and nobody is left marked traded")
  T.check(CoopCatchUp.prepareBattle(b, game.save.party, team(3, 30)) == false, "once per battle")
  -- the stronger copy: nothing
  local b2 = { game = game, enemyParty = team(2, 20), coopBalanceRules = { balancedFoes = true }, awardExp = function() end }
  local orig = b2.awardExp
  T.check(CoopCatchUp.prepareBattle(b2, team(3, 30), team(3, 10)) == false and b2.awardExp == orig, "the one ahead: the usual EXP")
  local b3 = { game = game, enemyParty = team(2, 20), coopBalanceRules = { balancedFoes = true }, awardExp = function() end }
  T.check(CoopCatchUp.prepareBattle(b3, team(3, 25), team(3, 30)) == false, "close together: the usual EXP")
  local b4 = { game = game, enemyParty = team(2, 20), coopBalanceRules = {}, awardExp = function() end }
  T.check(CoopCatchUp.prepareBattle(b4, team(3, 10), team(3, 30)) == false, "both difficulty rules off: the cartridge's EXP")
  local b5 = { game = game, battleTower = true, enemyParty = team(2, 20), coopBalanceRules = { balancedFoes = true }, awardExp = function() end }
  T.check(CoopCatchUp.prepareBattle(b5, team(3, 10), team(3, 30)) == false, "BATTLE TOWER: its own rules")
  -- an error inside still puts the flags back
  local b6 = { game = game, enemyParty = team(2, 20), coopBalanceRules = { balancedFoes = true },
               awardExp = function() error("boom") end }
  CoopCatchUp.prepareBattle(b6, game.save.party, team(3, 30))
  pcall(b6.awardExp, b6, {})
  T.check(game.save.party[1].traded == nil, "an error while paying still clears the boost")
end

-- Spanish
local I18n = require("src.coop.CoopI18n")
local realLang = I18n.language
I18n.language = function() return "es" end
T.eq(I18n.t("CATCH UP"), I18n.fitGlyphs("PONERSE AL DÍA"), "Spanish: the row")
T.check(#("PONERSE AL DIA") <= 16, "Spanish: the row fits 16")
T.eq(I18n.t("Meet %s in\n%s?"), I18n.fitGlyphs("¿Ir con %s a\n%s?"), "Spanish: the question")
local es = CoopCatchUp.describe(gB)
T.check(es:find(I18n.fitGlyphs("medallas más:"), 1, true) and es:find("COLMENA", 1, true), "Spanish: the box (" .. es:gsub("\n", "/"):gsub("\f", " | ") .. ")")
I18n.language = realLang

T.finish("nobody left behind")
