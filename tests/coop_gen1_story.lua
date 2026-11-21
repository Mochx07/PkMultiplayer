-- RED / BLUE / YELLOW'S STORY, SHARED.
--
-- Gen 1's story is Lua talk handlers (data/scripts/gyms.lua, story*.lua),
-- which ScriptRunner never saw, so nothing of it reached the partner: not
-- BROCK's badge and TM, not the Mt. Moon fossil.  Each handler now runs in
-- a story context of its own (lib/Hooks.lua -> CoopStory.wrapTalk), and the
-- Gen 1 leaders are asked CO-OP or SOLO before their first line.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local GV = require("src.core.GameVersion")
local wasGame = GV.get()
GV.set("yellow")

local SaveData = require("src.core.SaveData")
local CoopManager = require("src.coop.CoopManager")
local CoopStory = require("src.coop.CoopStory")
require("src.coop.CoopLog").enabled = false
package.loaded["src.core.Sound"] = { play = function() end }

local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1 print("FAIL " .. label) end
end

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end }
CoopManager.connected = true
local realIsConnected = CoopManager.isConnected
CoopManager.isConnected = function() return true end
CoopManager.storySync = true
CoopManager.partner = CoopManager.partner or {}
CoopManager.partner.name = "TOBY"
CoopManager.partner.healthy = 3
CoopManager.partner.map = "PALLET_TOWN"
CoopManager.partner.game = "yellow"

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local function newGame(name)
  local save = SaveData.newGame()
  save.player.name = name
  save.coopPartner = "TOBY"
  save.money = 3000
  return { data = Data, save = save, stack = newStack(),
           input = { wasPressed = function() return false end, isDown = function() return false end } }
end

local function lastRewards()
  for i = #sent, 1, -1 do
    if sent[i].type == "coop_story_rewards" then return sent[i] end
  end
  return nil
end

local function find(rewards, kind, key, value)
  for _, r in ipairs(rewards or {}) do
    if r.kind == kind and (key == nil or r[key] == value) then return r end
  end
  return nil
end

-- ---------------------------------------------------------------------
-- the leaders' badges, Gen 1 spelling
-- ---------------------------------------------------------------------
check(CoopManager.leaderBadgeFor("OPP_KOGA") == "SOULBADGE", "Gen 1 KOGA holds the SOULBADGE")
check(CoopManager.leaderBadgeFor("OPP_GIOVANNI", 3) == "EARTHBADGE", "Viridian's GIOVANNI gives the EARTHBADGE")
check(CoopManager.leaderBadgeFor("OPP_GIOVANNI", 1) == nil, "the Rocket Hideout's GIOVANNI gives no badge")
check(CoopManager.leaderBadgeFor("OPP_BROCK") == "BOULDERBADGE", "BROCK still maps")
for _, c in ipairs({ "OPP_LORELEI", "OPP_BRUNO", "OPP_AGATHA", "OPP_LANCE", "OPP_KOGA", "OPP_GIOVANNI", "OPP_RIVAL3" }) do
  check(CoopManager.isBigBattleClass(c, newGame("A").save), c .. " is a big battle in Red/Blue/Yellow")
end
local kogaBeaten = newGame("A").save
require("src.inventory.Badges").set(kogaBeaten, { id = "SOULBADGE" }, true)
check(not CoopManager.isBigBattleClass("OPP_KOGA", kogaBeaten), "KOGA is not asked about again after his badge")
GV.set("gold")
check(CoopManager.leaderBadgeFor("OPP_ELITE_FOUR_KOGA") == nil, "Gold's Elite Four KOGA gives no badge")
check(CoopManager.leaderBadgeFor("OPP_GIOVANNI", 3) == nil, "the Gen 1 table stays out of Gold")
GV.set("yellow")

-- ---------------------------------------------------------------------
-- the talk handlers come out wrapped
-- ---------------------------------------------------------------------
local scripts = require("data.scripts.init")
local brock = scripts.talkScript("PEWTER_GYM", "TEXT_PEWTERGYM_BROCK")
local base = require("src.script.MapScripts").baseTalk("PEWTER_GYM", "TEXT_PEWTERGYM_BROCK")
check(type(brock) == "function" and brock ~= base, "BROCK's handler is handed out inside a story context")
check(scripts.talkScript("PEWTER_GYM", "TEXT_PEWTERGYM_BROCK") == brock, "the same wrapper every time")

-- ---------------------------------------------------------------------
-- BROCK, won: badge, TM, flags and the gym guy shared; the prize money and
-- the potion used in the battle are the player's own
-- ---------------------------------------------------------------------
local host = newGame("MOCHX")
host.save.inventory.POTION = 3
local ow = { map = { id = "PEWTER_GYM" } }
local leader = CoopStory.wrapTalk(function(game, _, _, done)
  local battle = { kind = "trainer", oppClass = "OPP_BROCK" }
  CoopStory.onBattle(battle)
  game.save.inventory.POTION = 2           -- used in the battle
  game.save.money = game.save.money + 1386 -- the prize
  game.save.flags.EVENT_BEAT_BROCK = true
  game.save.inventory.BOULDERBADGE = 1
  game.save.inventory.TM_BIDE = 1
  require("src.script.Commands").hide_object({ game = game, save = game.save }, "PEWTER_CITY", "PEWTERCITY_YOUNGSTER")
  done()
end)
sent = {}
local doneCalled = false
leader(host, ow, {}, function() doneCalled = true end)
local ev = lastRewards()
check(doneCalled, "the handler's own done still runs")
check(ev ~= nil, "the victory goes to the partner")
local r = ev and ev.rewards or {}
check(find(r, "set_flag", "id", "EVENT_BEAT_BROCK"), "with EVENT_BEAT_BROCK")
check(find(r, "item", "id", "TM_BIDE"), "with TM34 BIDE")
check(find(r, "item", "id", "BOULDERBADGE"), "with the BOULDERBADGE")
check(find(r, "toggle", "obj", "PEWTERCITY_YOUNGSTER"), "with the gym guy gone from PEWTER")
check(not find(r, "money"), "not with the prize money")
check(not find(r, "take_item", "id", "POTION"), "not with the potion used in battle")
check(CoopStory.current == nil, "the context is closed")

-- the partner's game takes it once
local guest = newGame("TOBY")
guest.overworld = { map = { id = "PEWTER_CITY" } }
CoopStory.onPartnerRewards(guest, ev)
check(guest.save.flags.EVENT_BEAT_BROCK == true, "the partner has beaten BROCK")
check((guest.save.inventory.TM_BIDE or 0) == 1, "and has the TM")
check(((guest.save.objectToggles or {}).PEWTER_CITY or {}).PEWTERCITY_YOUNGSTER == false, "and the gym guy has gone")
local again = { type = ev.type, rewards = ev.rewards, eid = "other:1", map = ev.map }
CoopStory.onPartnerRewards(guest, again)
check((guest.save.inventory.TM_BIDE or 0) == 1, "the same victory again gives no second TM")

-- ---------------------------------------------------------------------
-- the Mt. Moon fossil, through the real handler: one fossil each, never two
-- ---------------------------------------------------------------------
local boxes = {}
package.loaded["src.render.TextBox"] = { new = function(game, text, cb, opts)
  local b = { text = text, cb = cb, choice = opts and opts.choice }
  boxes[#boxes + 1] = b
  return b
end }
local picker = newGame("MOCHX")
-- (another map id: hide_object then only writes the save, no live NPCs)
local fow = { map = { id = "MT_MOON_B1F" }, player = { cellX = 13, cellY = 7 },
              npcByIndex = function() return nil end }
fow.runner = { run = function(_, rows, opts)
  require("src.script.Commands").hide_object({ game = picker, save = picker.save }, "MT_MOON_B2F", rows[5][3])
  if opts and opts.onDone then opts.onDone() end
end }
local fossil = scripts.talkScript("MT_MOON_B2F", "TEXT_MTMOONB2F_DOME_FOSSIL")
sent = {}
fossil(picker, fow, { def = { name = "MTMOONB2F_DOME_FOSSIL" } }, function() end)
check(boxes[1] and boxes[1].choice, "the fossil asks first")
boxes[1].choice(true)
check(boxes[2] and boxes[2].cb, "then says you got it")
boxes[2].cb()
ev = nil
for _, m in ipairs(sent) do
  if m.type == "coop_story_rewards" and find(m.rewards, "item", "id", "DOME_FOSSIL") then ev = m end
end
check(ev ~= nil, "the fossil goes to the partner")
r = ev and ev.rewards or {}
check(find(r, "set_flag", "id", "EVENT_GOT_DOME_FOSSIL"), "with the flag that closes the choice")
check(find(r, "toggle", "obj", "MTMOONB2F_DOME_FOSSIL") and find(r, "toggle", "obj", "MTMOONB2F_HELIX_FOSSIL"),
      "with both fossils gone from the floor")
check(not find(r, "item", "id", "HELIX_FOSSIL"), "not with the other fossil")
local mate = newGame("TOBY")
mate.overworld = { map = { id = "ROUTE_3" } }
for _, m in ipairs(sent) do
  if m.type == "coop_story_rewards" then CoopStory.onPartnerRewards(mate, m) end
end
check((mate.save.inventory.DOME_FOSSIL or 0) == 1, "the partner has one DOME FOSSIL")
check((mate.save.inventory.HELIX_FOSSIL or 0) == 0, "and no HELIX FOSSIL")
local real = require("data.scripts.story2").MT_MOON_B2F.talk.TEXT_MTMOONB2F_HELIX_FOSSIL
local closed = false
boxes = {}
real(mate, fow, { def = { name = "MTMOONB2F_HELIX_FOSSIL" } }, function() closed = true end)
check(closed and #boxes == 0, "and cannot pick the HELIX FOSSIL on top")

-- ---------------------------------------------------------------------
-- personal: a Pokemon given, or something bought
-- ---------------------------------------------------------------------
local gifter = newGame("MOCHX")
sent = {}
CoopStory.wrapTalk(function(game, _, _, done)
  game.save.flags.EVENT_GOT_EEVEE = true
  table.insert(game.save.party, { species = "EEVEE", level = 25 })
  done()
end)(gifter, ow, {}, function() end)
check(lastRewards() == nil, "a Pokemon given is the player's own")
sent = {}
CoopStory.wrapTalk(function(game, _, _, done)
  game.save.money = game.save.money - 200
  game.save.inventory.POKE_BALL = (game.save.inventory.POKE_BALL or 0) + 1
  done()
end)(gifter, ow, {}, function() end)
check(lastRewards() == nil, "something bought is the player's own")
sent = {}
CoopStory.wrapTalk(function(game, _, _, done)
  CoopStory.onBattle({ kind = "wild" })
  game.save.flags.EVENT_BEAT_ZAPDOS = true
  done()
end)(gifter, ow, {}, function() end)
check(lastRewards() == nil, "a legendary met in the wild is the player's own")

-- a handler that never says it is done does not hold the story for good
local stuck = newGame("MOCHX")
CoopStory.wrapTalk(function() end)(stuck, ow, {}, function() end)
check(CoopStory.current and CoopStory.current.lua, "a handler still running holds its context")
CoopStory.current.at = CoopStory.current.at - CoopStory.LUA_MAX - 1
sent = {}
CoopStory.wrapTalk(function(game, _, _, done)
  game.save.flags.EVENT_GOT_OAKS_PARCEL = true
  done()
end)(stuck, ow, {}, function() end)
check(lastRewards() ~= nil, "but not past LUA_MAX: the next handler is recorded")

-- ---------------------------------------------------------------------
-- Gold/Silver with Crystal: the story is kept apart
-- ---------------------------------------------------------------------
GV.set("gold")
CoopManager.partner.game = "crystal"
check(not CoopManager.storyCompatible(), "Gold and Crystal number their flags apart")
CoopManager.partner.game = "silver"
check(CoopManager.storyCompatible(), "Gold and Silver share them")
CoopManager.partner.game = "crystal"
local gold = newGame("MOCHX")
gold.overworld = { map = { id = "NEW_BARK_TOWN" } }
CoopStory.onPartnerRewards(gold, { type = "coop_story_rewards", eid = "c:1",
  rewards = { { kind = "set_flag", id = "EVENT_G2_0100" }, { kind = "item", id = "POTION", count = 1 } } })
check(not gold.save.flags.EVENT_G2_0100, "a Crystal event is not applied to Gold")
local notices = CoopManager.linkNotices()
check(#notices >= 1 and notices[1]:find("not shared", 1, true), "the link says the story is not shared")
CoopManager.markTrainerBeaten(gold, gold.overworld, { npcId = "X_obj_1", headerEvent = "EVENT_G2_0400" })
check(gold.save.defeatedTrainers.X_obj_1 and not gold.save.flags.EVENT_G2_0400,
      "a co-op trainer is beaten, but the other cartridge's flag is not set")

-- ---------------------------------------------------------------------
-- Legendary Wings Cross-Version Remapping (Gold <-> Silver)
-- ---------------------------------------------------------------------
-- Radio Tower: Gold partner sends Rainbow Wing (178), Silver must receive Silver Wing (071)
GV.set("silver")
CoopManager.partner.game = "gold"
local silver = newGame("MOCHX")
silver.overworld = { map = { id = "ECRUTEAK_CITY" } }
CoopStory.onPartnerRewards(silver, {
  type = "coop_story_rewards", eid = "w:1", map = "RADIO_TOWER5_F",
  rewards = {
    { kind = "item", id = "ITEM_178", count = 1 },
    { kind = "set_flag", id = "EVENT_G2_0120" },
    { kind = "set_flag", id = "EVENT_G2_1889" },
    { kind = "scene", map = "RADIO_TOWER5_F", scene = 2 },
  }
})
check(silver.save.inventory.ITEM_071 == 1, "Silver receives Silver Wing from Radio Tower")
check(silver.save.inventory.ITEM_178 == nil, "Silver does not receive Rainbow Wing from Radio Tower")
check(silver.save.flags.EVENT_G2_0121 == true, "Silver sets EVENT_GOT_SILVER_WING")
check(silver.save.flags.EVENT_G2_0120 == nil, "Silver does not set EVENT_GOT_RAINBOW_WING in Johto")

-- Pewter City: Gold partner sends Silver Wing (071), Silver must receive Rainbow Wing (178)
CoopStory.onPartnerRewards(silver, {
  type = "coop_story_rewards", eid = "w:2", map = "PEWTER_CITY",
  rewards = {
    { kind = "item", id = "ITEM_071", count = 1 },
    { kind = "set_flag", id = "EVENT_G2_0121" },
  }
})
check(silver.save.inventory.ITEM_178 == 1, "Silver receives Rainbow Wing in Pewter City")
check(silver.save.flags.EVENT_G2_0120 == true, "Silver sets EVENT_GOT_RAINBOW_WING in Pewter City")

-- Radio Tower: Silver partner sends Silver Wing (071), Gold must receive Rainbow Wing (178)
GV.set("gold")
CoopManager.partner.game = "silver"
local goldGame = newGame("GOLD")
goldGame.overworld = { map = { id = "ECRUTEAK_CITY" } }
CoopStory.onPartnerRewards(goldGame, {
  type = "coop_story_rewards", eid = "w:3", map = "RADIO_TOWER5_F",
  rewards = {
    { kind = "item", id = "ITEM_071", count = 1 },
    { kind = "set_flag", id = "EVENT_G2_0121" },
    { kind = "set_flag", id = "EVENT_G2_1889" },
  }
})
check(goldGame.save.inventory.ITEM_178 == 1, "Gold receives Rainbow Wing from Radio Tower")
check(goldGame.save.inventory.ITEM_071 == nil, "Gold does not receive Silver Wing from Radio Tower")
check(goldGame.save.flags.EVENT_G2_0120 == true, "Gold sets EVENT_GOT_RAINBOW_WING from Radio Tower")
check(goldGame.save.flags.EVENT_G2_0121 == nil, "Gold does not set EVENT_GOT_SILVER_WING in Johto")

-- Pewter City: Silver partner sends Rainbow Wing (178), Gold must receive Silver Wing (071)
CoopStory.onPartnerRewards(goldGame, {
  type = "coop_story_rewards", eid = "w:4", map = "PEWTER_CITY",
  rewards = {
    { kind = "item", id = "ITEM_178", count = 1 },
    { kind = "set_flag", id = "EVENT_G2_0120" },
  }
})
check(goldGame.save.inventory.ITEM_071 == 1, "Gold receives Silver Wing in Pewter City")
check(goldGame.save.flags.EVENT_G2_0121 == true, "Gold sets EVENT_GOT_SILVER_WING in Pewter City")

-- Test Save Repair for a contaminated Silver save
GV.set("silver")
local badSilver = {
  inventory = { ITEM_178 = 1, ITEM_071 = 1 },
  bagOrder = { "ITEM_071", "ITEM_178" },
  flags = { EVENT_G2_0120 = true, EVENT_G2_0121 = true, EVENT_G2_1889 = true },
}
local repaired = CoopStory.repairSave(badSilver)
check(repaired == true, "repairSave fixed the contaminated Silver save")
check(badSilver.inventory.ITEM_178 == nil, "repairSave stripped premature Rainbow Wing")
check(badSilver.inventory.ITEM_071 == 1, "repairSave preserved Silver Wing")
check(badSilver.flags.EVENT_G2_0120 == nil, "repairSave cleared premature EVENT_GOT_RAINBOW_WING")
check(badSilver.flags.EVENT_G2_0121 == true, "repairSave ensured EVENT_GOT_SILVER_WING")
check(#badSilver.bagOrder == 1 and badSilver.bagOrder[1] == "ITEM_071", "repairSave cleaned bagOrder")

CoopManager.partner.game = "yellow"

-- ---------------------------------------------------------------------
-- B5: Gen 1 story chapters in co-op (S.S. Anne, Pokemon Tower, Rocket
-- Hideout, Silph Co., Safari Zone, Poke Flute & Snorlax)
-- ---------------------------------------------------------------------
GV.set("red")
CoopManager.partner.game = "red"
local MapScripts = require("src.script.MapScripts")
local Commands = require("src.script.Commands")
local BattleState = require("src.battle.BattleState")
local origNewWild, origNewTrainer = BattleState.newWild, BattleState.newTrainer
BattleState.newWild = function(g, sp, lv)
  return {
    kind = "wild", game = g, data = g and g.data,
    enemy = { mon = { species = sp, level = lv } },
    makeUnveiledGhost = function(self) self.unveiled = true end,
    makeGhost = function(self) self.ghost = true end,
  }
end
BattleState.newTrainer = function(g, cls, pIdx)
  return {
    kind = "trainer", game = g, data = g and g.data,
    oppClass = cls, partyIndex = pIdx,
  }
end
Data.pokemon = Data.pokemon or {}
local sampleMon = next(Data.pokemon) and Data.pokemon[next(Data.pokemon)] or {
  id = "LAPRAS", name = "LAPRAS", baseStats = { hp = 130, attack = 85, defense = 80, speed = 60, special = 95 },
  types = { "WATER", "ICE" }, growthRate = "SLOW", learnset = {},
}
Data.pokemon.LAPRAS = Data.pokemon.LAPRAS or sampleMon
Data.pokemon.MAROWAK = Data.pokemon.MAROWAK or sampleMon

-- Helper to run a command-row script through CoopStory.begin/observe/finish
local function runRowScript(game, owMap, rows, opts)
  opts = opts or {}
  local rowOw = opts.ow or { map = { id = owMap }, player = opts.player or { cellX = 5, cellY = 5, facing = "up" } }
  local ctx = { game = game, save = game.save, overworld = rowOw, npc = opts.npc }
  CoopStory.begin(ctx, rows)
  if not ctx.coopSkipScript then
    for _, row in ipairs(rows) do
      local cmd = row[1]
      if cmd == "set_flag" then
        Commands.set_flag(ctx, row[2])
      elseif cmd == "clear_flag" then
        Commands.clear_flag(ctx, row[2])
      elseif cmd == "give_item" then
        ctx.lastCheck = require("src.inventory.Bag").add(ctx.save, row[2], row[3] or 1, game.data)
      elseif cmd == "take_item" then
        Commands.take_item(ctx, row[2], row[3])
      elseif cmd == "show_object" then
        Commands.show_object(ctx, row[2], row[3])
      elseif cmd == "hide_object" then
        Commands.hide_object(ctx, row[2], row[3])
      elseif cmd == "static_battle" then
        if row[4] then Commands.set_flag(ctx, row[4]) end
      elseif cmd == "warp" and opts.afterWarpCell then
        rowOw.map.id = row[2]
        rowOw.player.cellX = opts.afterWarpCell.x
        rowOw.player.cellY = opts.afterWarpCell.y
        rowOw.player.facing = opts.afterWarpCell.facing or row[5]
      end
      CoopStory.observe(ctx, cmd, row)
    end
  end
  CoopStory.finish(ctx)
  return ctx
end

-- 1. S.S. Anne: Bill's ticket, 2F rival, Captain's HM01 Cut, and ship departure
do
  local p1 = newGame("MOCHI")
  local p2 = newGame("TOBY")
  p2.overworld = { map = { id = "BILLS_HOUSE" } }
  CoopManager.partner.map = "BILLS_HOUSE"
  sent = {}
  local billTicket = scripts.talkScript("BILLS_HOUSE", "TEXT_BILLSHOUSE_BILL_SS_TICKET")
  check(type(billTicket) == "table", "Bill's SS Ticket script is registered")
  runRowScript(p1, "BILLS_HOUSE", billTicket)
  local evTicket = lastRewards()
  check(evTicket ~= nil, "Bill's SS Ticket sends rewards")
  check(find(evTicket.rewards, "item", "id", "S_S_TICKET"), "shares S_S_TICKET")
  check(find(evTicket.rewards, "set_flag", "id", "EVENT_GOT_SS_TICKET"), "shares EVENT_GOT_SS_TICKET")
  check(find(evTicket.rewards, "toggle", "obj", "CERULEANCITY_GUARD1"), "shares Cerulean guard show toggle from row script")
  check(find(evTicket.rewards, "toggle", "obj", "CERULEANCITY_GUARD2"), "shares Cerulean guard hide toggle from row script")
  CoopStory.onPartnerRewards(p2, evTicket)
  check((p2.save.inventory.S_S_TICKET or 0) == 1 and p2.save.flags.EVENT_GOT_SS_TICKET == true,
        "partner receives S_S_TICKET and flag for boarding")

  -- Route 25 onEnter after helping Bill
  p1.save.flags.EVENT_MET_BILL_2 = true
  sent = {}
  local r25 = MapScripts.get("ROUTE_25")
  r25.onEnter(p1, { map = { id = "ROUTE_25" } })
  local evR25 = lastRewards()
  check(evR25 and find(evR25.rewards, "set_flag", "id", "EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING"),
        "leaving Bill's house onto Route 25 shares EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING")

  -- Captain's HM01 Cut
  sent = {}
  CoopManager.partner.map = "SS_ANNE_CAPTAINS_ROOM"
  local capScript = scripts.talkScript("SS_ANNE_CAPTAINS_ROOM", "TEXT_SSANNECAPTAINSROOM_CAPTAIN")
  runRowScript(p1, "SS_ANNE_CAPTAINS_ROOM", capScript)
  local evCut = lastRewards()
  check(evCut and find(evCut.rewards, "item", "id", "HM_CUT")
        and find(evCut.rewards, "set_flag", "id", "EVENT_GOT_HM01"),
        "Captain's HM01 Cut and EVENT_GOT_HM01 are shared")

  -- S.S. Anne departure on VERMILION_DOCK: onEnter sets EVENT_SS_ANNE_LEFT before queueScript
  sent = {}
  CoopManager.partner.map = "VERMILION_DOCK"
  local queuedRows
  local dockOw = {
    map = { id = "VERMILION_DOCK" },
    player = { cellX = 14, cellY = 2, facing = "up" },
    scriptQueue = {},
    startDustAnim = function() end,
    queueScript = function(self, rows, opts)
      queuedRows = rows
      table.insert(self.scriptQueue, { rows = rows, opts = opts })
    end,
  }
  local dockHooks = MapScripts.get("VERMILION_DOCK")
  dockHooks.onEnter(p1, dockOw)
  check(p1.save.flags.EVENT_SS_ANNE_LEFT == true and queuedRows ~= nil, "Vermilion Dock onEnter sets EVENT_SS_ANNE_LEFT and queues departure")
  runRowScript(p1, "VERMILION_DOCK", queuedRows, {
    ow = dockOw,
    afterWarpCell = { x = 18, y = 29, facing = "up" },
  })
  local evDock = lastRewards()
  check(evDock ~= nil, "Vermilion Dock departure script sends rewards")
  check(find(evDock.rewards, "set_flag", "id", "EVENT_SS_ANNE_LEFT"),
        "EVENT_SS_ANNE_LEFT set in onEnter before queueScript is captured and shared")
  local dockWarp = find(evDock.rewards, "warp", "map", "VERMILION_CITY")
  check(dockWarp and dockWarp.x == 18 and dockWarp.y == 29,
        "partner on Vermilion Dock warps to (18,29) past the ticket guard")
end

-- 2. Pokemon Tower: 6F Marowak ghost gate, 7F Rockets, Mr. Fuji rescue, Poke Flute
do
  local p1 = newGame("MOCHI")
  local p2 = newGame("TOBY")
  p1.save.inventory.SILPH_SCOPE = 1
  p1.save.inventory.POKE_DOLL = 1
  p2.save.inventory.SILPH_SCOPE = 1
  p2.save.inventory.POKE_DOLL = 1
  CoopManager.partner.map = "POKEMON_TOWER_6F"
  local t6Hooks = MapScripts.get("POKEMON_TOWER_6F")
  local t6Ow = {
    map = { id = "POKEMON_TOWER_6F" },
    player = { cellX = 10, cellY = 16 },
    afterBattle = function() CoopStory.onAfterBattle() end,
    scriptMove = function() end,
  }
  boxes = {}
  sent = {}
  local pushedBattle
  p1.stack.push = function(self, st)
    table.insert(self.states, st)
    if st and st.kind == "wild" then pushedBattle = st end
  end
  local stepped = t6Hooks.onStep(p1, t6Ow, 10, 16)
  check(stepped == true, "stepping on (10,16) in Pokemon Tower 6F triggers Ghost Marowak")
  local heldSent = false
  for _, m in ipairs(sent) do
    if m.type == "coop_story_hold" and m.class == "GHOST_MAROWAK" then heldSent = true end
  end
  check(heldSent, "Ghost Marowak step sends coop_story_hold so partner does not double-trigger")
  -- Partner stepping on (10,16) while held stands back
  CoopStory.onPartnerHold({ map = "POKEMON_TOWER_6F", class = "GHOST_MAROWAK" })
  local p2MovedBack = false
  local p2Ow = {
    map = { id = "POKEMON_TOWER_6F" },
    player = { cellX = 10, cellY = 16 },
    scriptMove = function(_, _, dir, n) if dir == "right" and n == 1 then p2MovedBack = true end end,
  }
  check(t6Hooks.onStep(p2, p2Ow, 10, 16) == true and p2MovedBack,
        "partner stepping on (10,16) while Marowak is held steps back instead of starting a second fight")
  CoopStory.onPartnerRelease()

  check(boxes[1] and boxes[1].cb, "Marowak shows 'Be gone... Intruders...' first")
  boxes[1].cb()
  check(pushedBattle ~= nil and pushedBattle.noCatch == true, "Marowak battle opens with noCatch")
  -- Even if a Poke Doll is consumed during the battle, calming Marowak shares the flag and keeps partner's doll
  p1.save.inventory.POKE_DOLL = nil
  pushedBattle.pokeDollEscape = true
  pushedBattle.onFinish("run")
  local evMarowak = lastRewards()
  check(evMarowak ~= nil, "calming Ghost Marowak sends story rewards to partner")
  check(find(evMarowak.rewards, "set_flag", "id", "EVENT_BEAT_GHOST_MAROWAK"),
        "EVENT_BEAT_GHOST_MAROWAK is shared with partner")
  check(not find(evMarowak.rewards, "take_item", "id", "POKE_DOLL"),
        "Poke Doll used in Marowak battle is not taken from partner's bag")
  p2.overworld = p2Ow
  CoopStory.onPartnerRewards(p2, evMarowak)
  check(p2.save.flags.EVENT_BEAT_GHOST_MAROWAK == true, "partner's Marowak gate is cleared")

  -- 7F Mr. Fuji rescue shares flags, hides 7F Fuji, shows house Fuji, swaps Saffron guards, and warps partner
  sent = {}
  CoopManager.partner.map = "POKEMON_TOWER_7F"
  local fuji7F = scripts.talkScript("POKEMON_TOWER_7F", "TEXT_POKEMONTOWER7F_MR_FUJI")
  runRowScript(p1, "POKEMON_TOWER_7F", fuji7F, {
    afterWarpCell = { x = 3, y = 7, facing = "up" },
  })
  local evFuji = lastRewards()
  check(evFuji ~= nil, "rescuing Mr. Fuji sends rewards")
  check(find(evFuji.rewards, "set_flag", "id", "EVENT_RESCUED_MR_FUJI")
        and find(evFuji.rewards, "set_flag", "id", "EVENT_RESCUED_MR_FUJI_2"),
        "shares EVENT_RESCUED_MR_FUJI and EVENT_RESCUED_MR_FUJI_2")
  check(find(evFuji.rewards, "toggle", "obj", "POKEMONTOWER7F_MR_FUJI")
        and find(evFuji.rewards, "toggle", "obj", "MRFUJISHOUSE_MR_FUJI")
        and find(evFuji.rewards, "toggle", "obj", "SAFFRONCITY_ROCKET8")
        and find(evFuji.rewards, "toggle", "obj", "SAFFRONCITY_ROCKET9"),
        "hides 7F Mr. Fuji, shows house Mr. Fuji, and swaps Saffron Silph guard")
  check(find(evFuji.rewards, "warp", "map", "MR_FUJIS_HOUSE"),
        "warps partner on 7F to MR_FUJIS_HOUSE")
  p2.overworld = { map = { id = "POKEMON_TOWER_7F" } }
  CoopStory.onPartnerRewards(p2, evFuji)
  check(((p2.save.objectToggles or {}).POKEMON_TOWER_7F or {}).POKEMONTOWER7F_MR_FUJI == false,
        "partner's 7F Mr. Fuji is hidden")
  check(CoopStory.pendingWarp and CoopStory.pendingWarp.map == "MR_FUJIS_HOUSE",
        "partner has pending warp to MR_FUJIS_HOUSE")
  CoopStory.pendingWarp = nil

  -- Mr. Fuji's House: Poke Flute gift
  sent = {}
  CoopManager.partner.map = "MR_FUJIS_HOUSE"
  local fujiHouse = scripts.talkScript("MR_FUJIS_HOUSE", "TEXT_MRFUJISHOUSE_MR_FUJI")
  runRowScript(p1, "MR_FUJIS_HOUSE", fujiHouse)
  local evFlute = lastRewards()
  check(evFlute and find(evFlute.rewards, "item", "id", "POKE_FLUTE")
        and find(evFlute.rewards, "set_flag", "id", "EVENT_GOT_POKE_FLUTE"),
        "Mr. Fuji's POKE_FLUTE and EVENT_GOT_POKE_FLUTE are shared")
end

-- 3. Rocket Hideout: Poster, Lift Key (Red & Yellow), Giovanni, Silph Scope item balls
do
  local p1 = newGame("MOCHI")
  local p2 = newGame("TOBY")
  CoopManager.partner.map = "ROCKET_HIDEOUT_B4F"

  -- Red/Blue Rocket 3 after battle drops Lift Key
  sent = {}
  boxes = {}
  local b4Ow = {
    map = { id = "ROCKET_HIDEOUT_B4F", def = { objects = {} } },
    npcs = {},
    entities = {},
    trainerDefeated = function() return true end,
  }
  local r3 = scripts.talkScript("ROCKET_HIDEOUT_B4F", "TEXT_ROCKETHIDEOUTB4F_ROCKET3")
  r3(p1, b4Ow, { id = "ROCKET_HIDEOUT_B4F_obj_4", def = { name = "ROCKETHIDEOUTB4F_ROCKET3" } }, function() end)
  if boxes[1] and boxes[1].cb then boxes[1].cb() end
  local evDrop = lastRewards()
  check(evDrop and find(evDrop.rewards, "set_flag", "id", "EVENT_ROCKET_DROPPED_LIFT_KEY")
        and find(evDrop.rewards, "toggle", "obj", "ROCKETHIDEOUTB4F_LIFT_KEY"),
        "Rocket Hideout B4F grunt drops LIFT_KEY for both players (Red/Blue)")

  -- Yellow Rocket beaten by sight then talked to still drops Lift Key
  local y1 = newGame("MOCHI")
  sent = {}
  boxes = {}
  local yr = scripts.talkScript("ROCKET_HIDEOUT_B4F", "TEXT_ROCKETHIDEOUTB4F_ROCKET")
  yr(y1, b4Ow, { id = "ROCKET_HIDEOUT_B4F_obj_4", def = { name = "ROCKETHIDEOUTB4F_ROCKET" } }, function() end)
  if boxes[1] and boxes[1].cb then boxes[1].cb() end
  local evYDrop = lastRewards()
  check(evYDrop and find(evYDrop.rewards, "set_flag", "id", "EVENT_ROCKET_DROPPED_LIFT_KEY")
        and find(evYDrop.rewards, "toggle", "obj", "ROCKETHIDEOUTB4F_LIFT_KEY"),
        "Rocket Hideout B4F grunt drops LIFT_KEY even if beaten by sight first (Yellow)")

  -- Item ball pickup via CoopStory.recordAction (LIFT_KEY & SILPH_SCOPE)
  sent = {}
  CoopStory.recordAction(p1, b4Ow, function()
    require("src.inventory.Bag").add(p1.save, "LIFT_KEY", 1, p1.data)
    p1.save.itemsTaken = p1.save.itemsTaken or {}
    p1.save.itemsTaken["ROCKET_HIDEOUT_B4F_obj_9"] = true
  end)
  local evBall = lastRewards()
  check(evBall and find(evBall.rewards, "item", "id", "LIFT_KEY")
        and find(evBall.rewards, "taken", "key", "ROCKET_HIDEOUT_B4F_obj_9"),
        "picking up LIFT_KEY item ball shares item and itemsTaken key")
  local syncedVis = false
  p2.overworld = { map = { id = "ROCKET_HIDEOUT_B4F" }, syncObjectVisibility = function() syncedVis = true end }
  CoopStory.onPartnerRewards(p2, evBall)
  check((p2.save.inventory.LIFT_KEY or 0) == 1 and p2.save.itemsTaken["ROCKET_HIDEOUT_B4F_obj_9"] == true and syncedVis,
        "partner gets LIFT_KEY and despawns the item ball")

  -- Rocket Hideout B4F Giovanni talk handler reveals Silph Scope and hides Giovanni
  sent = {}
  boxes = {}
  package.loaded["src.render.Transition"] = { new = function(_, mid, fin)
    if mid then mid() end
    if fin then fin() end
    return {}
  end }
  local gioOw = {
    map = { id = "ROCKET_HIDEOUT_B4F", def = { objects = {} } },
    npcs = {},
    entities = {},
    trainerDefeated = function() return false end,
    afterBattle = function() end,
    pushBattle = function(_, b)
      CoopStory.onBattle(b)
      b.onFinish("win")
    end,
  }
  local gioTalk = scripts.talkScript("ROCKET_HIDEOUT_B4F", "TEXT_ROCKETHIDEOUTB4F_GIOVANNI")
  gioTalk(p1, gioOw, { id = "ROCKET_HIDEOUT_B4F_obj_1", def = { name = "ROCKETHIDEOUTB4F_GIOVANNI", trainerClass = "OPP_GIOVANNI", trainerParty = 1 } }, function() end)
  while #boxes > 0 do
    local b = table.remove(boxes, 1)
    if b.cb then b.cb() end
  end
  local evHideoutGio = lastRewards()
  check(evHideoutGio ~= nil, "beating Rocket Hideout Giovanni sends story rewards")
  check(find(evHideoutGio.rewards, "set_flag", "id", "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI"),
        "shares EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI")
  check(find(evHideoutGio.rewards, "toggle", "obj", "ROCKETHIDEOUTB4F_GIOVANNI")
        and find(evHideoutGio.rewards, "toggle", "obj", "ROCKETHIDEOUTB4F_SILPH_SCOPE"),
        "hides Rocket Hideout Giovanni and reveals SILPH_SCOPE item ball for partner")
end

-- 4. Silph Co.: Card Key door unlock, 7F Lapras PERSONAL, 11F Giovanni & Master Ball
do
  local p1 = newGame("MOCHI")
  local p2 = newGame("TOBY")
  CoopManager.partner.map = "SILPH_CO_5F"

  -- Card Key door unlock via CoopStory.recordAction updates partner's live map doors
  sent = {}
  local s5Ow = { map = { id = "SILPH_CO_5F" } }
  CoopStory.recordAction(p1, s5Ow, function()
    p1.save.flags.EVENT_SILPH_CO_5_UNLOCKED_DOOR1 = true
  end)
  local evDoor = lastRewards()
  check(evDoor and find(evDoor.rewards, "set_flag", "id", "EVENT_SILPH_CO_5_UNLOCKED_DOOR1"),
        "unlocking a Silph Co. Card Key door shares its unlock flag")
  local doorsStamped = false
  p2.overworld = { map = { id = "SILPH_CO_5F" }, stampClosedDoors = function() doorsStamped = true end }
  CoopStory.onPartnerRewards(p2, evDoor)
  check(p2.save.flags.EVENT_SILPH_CO_5_UNLOCKED_DOOR1 == true and doorsStamped,
        "partner receives door unlock flag and refreshes closed doors live")

  -- Silph Co. 7F Lapras gift is PERSONAL: partner does NOT get EVENT_GOT_LAPRAS and can claim their own
  CoopManager.partner.map = "SILPH_CO_7F"
  sent = {}
  boxes = {}
  local s7Ow = { map = { id = "SILPH_CO_7F" } }
  local laprasTalk = scripts.talkScript("SILPH_CO_7F", "TEXT_SILPHCO7F_SILPH_WORKER_M1")
  laprasTalk(p1, s7Ow, { def = { name = "SILPHCO7F_SILPH_WORKER_M1" } }, function() end)
  while #boxes > 0 do
    local b = table.remove(boxes, 1)
    if b.cb then b.cb() end
  end
  check(p1.save.flags.EVENT_GOT_LAPRAS == true and #p1.save.party == 1 and p1.save.party[1].species == "LAPRAS",
        "first player receives Lapras and sets EVENT_GOT_LAPRAS")
  check(lastRewards() == nil, "Lapras gift is PERSONAL and sends no story rewards to partner")
  check(not p2.save.flags.EVENT_GOT_LAPRAS, "partner's EVENT_GOT_LAPRAS remains unset")
  laprasTalk(p2, s7Ow, { def = { name = "SILPHCO7F_SILPH_WORKER_M1" } }, function() end)
  while #boxes > 0 do
    local b = table.remove(boxes, 1)
    if b.cb then b.cb() end
  end
  check(p2.save.flags.EVENT_GOT_LAPRAS == true and #p2.save.party == 1 and p2.save.party[1].species == "LAPRAS",
        "partner can talk to the Silph worker to receive their own personal Lapras")

  -- Silph Co. 11F Giovanni step trigger + victory shares flag and Rocket exodus
  CoopManager.partner.map = "SILPH_CO_11F"
  sent = {}
  boxes = {}
  local gioNpc = {
    id = "SILPH_CO_11F_obj_3",
    def = { index = 3, name = "SILPHCO11F_GIOVANNI", trainerClass = "OPP_GIOVANNI", trainerParty = 2 },
    facePlayer = function() end,
  }
  local s11Hooks = MapScripts.get("SILPH_CO_11F")
  local s11Ow
  s11Ow = {
    game = p1,
    map = { id = "SILPH_CO_11F", def = { label = "SilphCo11F", objects = {} } },
    player = { cellX = 6, cellY = 13 },
    npcs = { gioNpc },
    entities = { gioNpc },
    trainerDefeated = function(_, n) return p1.save.defeatedTrainers[n.id] == true end,
    scriptMove = function(_, _, _, _, cb) if cb then cb() end end,
    engageTrainer = function(self, npc, onDone)
      local ctx = CoopStory.beginLua(p1, self)
      if ctx and ctx.coopStory then ctx.coopStory.battled = true end
      p1.save.defeatedTrainers[npc.id] = true
      p1.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI = true
      if onDone then onDone() end
      if ctx then CoopStory.finishLua(ctx) end
    end,
  }
  local s11Triggered = s11Hooks.onStep(p1, s11Ow, 6, 13)
  check(s11Triggered == true, "stepping on (6,13) in Silph Co. 11F triggers Giovanni")
  local evSilphGio = lastRewards()
  check(evSilphGio ~= nil, "beating Silph Co. 11F Giovanni sends story rewards")
  check(find(evSilphGio.rewards, "set_flag", "id", "EVENT_BEAT_SILPH_CO_GIOVANNI"),
        "shares EVENT_BEAT_SILPH_CO_GIOVANNI")
  check(find(evSilphGio.rewards, "toggle", "obj", "SILPHCO11F_GIOVANNI")
        and find(evSilphGio.rewards, "toggle", "obj", "SILPHCO11F_ROCKET1")
        and find(evSilphGio.rewards, "toggle", "obj", "SILPHCO11F_ROCKET"),
        "shares Silph Co. Rocket exodus toggles (Red/Blue and Yellow spellings)")
  p2.overworld = { map = { id = "SILPH_CO_11F" } }
  CoopStory.onPartnerRewards(p2, evSilphGio)
  check(p2.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI == true
        and ((p2.save.objectToggles or {}).SILPH_CO_11F or {}).SILPHCO11F_GIOVANNI == false,
        "partner receives EVENT_BEAT_SILPH_CO_GIOVANNI and hides Silph Co. 11F Giovanni")

  -- Silph President Master Ball
  sent = {}
  local presScript = scripts.talkScript("SILPH_CO_11F", "TEXT_SILPHCO11F_SILPH_PRESIDENT")
  runRowScript(p1, "SILPH_CO_11F", presScript)
  local evMaster = lastRewards()
  check(evMaster and find(evMaster.rewards, "item", "id", "MASTER_BALL")
        and find(evMaster.rewards, "set_flag", "id", "EVENT_GOT_MASTER_BALL"),
        "Silph President's MASTER_BALL and EVENT_GOT_MASTER_BALL are shared")
end

-- 5. Safari Zone: gate admission/exit PERSONAL, Surf and Gold Teeth / Strength shared
do
  local p1 = newGame("MOCHI")
  local p2 = newGame("TOBY")
  CoopManager.partner.map = "SAFARI_ZONE_GATE"
  local gateOw = {
    map = { id = "SAFARI_ZONE_GATE", warpAtCell = function() return nil end },
    player = { cellX = 3, cellY = 2 },
    scriptMove = function(_, _, _, _, cb) if cb then cb() end end,
  }
  check(CoopStory.beginLua(p1, gateOw) == nil,
        "Safari Zone Gate opens no shared Lua story context (admission stays personal)")

  -- Yellow broke free admission (0 money, 4th try -> 1 ball) also stays personal even off-map
  GV.set("yellow")
  p1.save.money = 0
  p1.save.safariNags = 3
  local beforeY = CoopStory.luaSnapshot(p1.save)
  p1.save.safari = { balls = 1, steps = 502 }
  p1.save.safariNags = nil
  local _, isPers = CoopStory.luaChanges(p1.save, beforeY, false)
  check(isPers == true, "Yellow's free 1-ball Safari admission is detected as personal")
  GV.set("red")

  -- Safari Zone Gate onEnter ("Leaving early?" -> NO -> warp back to SAFARI_ZONE_CENTER) stays personal
  sent = {}
  runRowScript(p1, "SAFARI_ZONE_GATE", {
    { "show_text", "_SafariZoneGateSafariZoneWorker1GoodLuckText" },
    { "warp", "SAFARI_ZONE_CENTER", 14, 25, "up" },
  })
  check(lastRewards() == nil, "Safari Zone Gate warp back to SAFARI_ZONE_CENTER is not sent to partner")

  -- Safari Zone Secret House HM03 Surf is shared
  sent = {}
  CoopManager.partner.map = "SAFARI_ZONE_SECRET_HOUSE"
  local surfScript = scripts.talkScript("SAFARI_ZONE_SECRET_HOUSE", "TEXT_SAFARIZONESECRETHOUSE_FISHING_GURU")
  runRowScript(p1, "SAFARI_ZONE_SECRET_HOUSE", surfScript)
  local evSurf = lastRewards()
  check(evSurf and find(evSurf.rewards, "item", "id", "HM_SURF")
        and find(evSurf.rewards, "set_flag", "id", "EVENT_GOT_HM03"),
        "Safari Zone Secret House HM03 Surf and EVENT_GOT_HM03 are shared")

  -- Gold Teeth pickup in Safari Zone West & Warden's HM04 Strength in Warden's House
  sent = {}
  CoopStory.recordAction(p1, { map = { id = "SAFARI_ZONE_WEST" } }, function()
    require("src.inventory.Bag").add(p1.save, "GOLD_TEETH", 1, p1.data)
    p1.save.itemsTaken = p1.save.itemsTaken or {}
    p1.save.itemsTaken["SAFARI_ZONE_WEST_obj_4"] = true
  end)
  local evTeeth = lastRewards()
  check(evTeeth and find(evTeeth.rewards, "item", "id", "GOLD_TEETH")
        and find(evTeeth.rewards, "taken", "key", "SAFARI_ZONE_WEST_obj_4"),
        "picking up GOLD_TEETH in Safari Zone West shares item and itemsTaken")
  p2.overworld = { map = { id = "SAFARI_ZONE_WEST" } }
  CoopStory.onPartnerRewards(p2, evTeeth)
  check((p2.save.inventory.GOLD_TEETH or 0) == 1, "partner receives GOLD_TEETH")

  sent = {}
  CoopManager.partner.map = "WARDENS_HOUSE"
  p2.overworld = { map = { id = "WARDENS_HOUSE" } }
  local wardenScript = scripts.talkScript("WARDENS_HOUSE", "TEXT_WARDENSHOUSE_WARDEN")
  runRowScript(p1, "WARDENS_HOUSE", wardenScript)
  local evWarden = lastRewards()
  check(evWarden and find(evWarden.rewards, "take_item", "id", "GOLD_TEETH")
        and find(evWarden.rewards, "item", "id", "HM_STRENGTH")
        and find(evWarden.rewards, "set_flag", "id", "EVENT_GAVE_GOLD_TEETH")
        and find(evWarden.rewards, "set_flag", "id", "EVENT_GOT_HM04"),
        "Warden takes GOLD_TEETH and shares HM04 Strength and flags")
  CoopStory.onPartnerRewards(p2, evWarden)
  check(p2.save.inventory.GOLD_TEETH == nil and (p2.save.inventory.HM_STRENGTH or 0) == 1
        and p2.save.flags.EVENT_GOT_HM04 == true,
        "partner's GOLD_TEETH is taken and replaced by HM04 Strength")
end

-- 6. Poke Flute and the two Snorlax (Route 12 & Route 16): reachable as "snorlax" boss and shared
do
  local ItemEffects = require("src.inventory.ItemEffects")
  local CoopBoss = require("src.coop.CoopBoss")
  local p1 = newGame("MOCHI")
  local p2 = newGame("TOBY")
  p1.save.inventory.POKE_FLUTE = 1
  for _, route in ipairs({
    { map = "ROUTE_12", obj = "ROUTE12_SNORLAX", flag = "EVENT_BEAT_ROUTE12_SNORLAX" },
    { map = "ROUTE_16", obj = "ROUTE16_SNORLAX", flag = "EVENT_BEAT_ROUTE16_SNORLAX" },
  }) do
    local snorlaxNpc = { id = route.map .. "_obj_1", cellX = 10, cellY = 10, def = { name = route.obj } }
    local rOw = {
      map = { id = route.map },
      player = { cellX = 10, cellY = 9 },
      npcs = { snorlaxNpc },
      entities = { snorlaxNpc },
    }
    local res, _, extra = ItemEffects.use(p1.data, p1.save, "POKE_FLUTE", nil, nil, nil, rOw)
    check(res == "flute_wake" and extra and extra.mapId == route.map and extra.npc == snorlaxNpc,
          "POKE_FLUTE wakes sleeping Snorlax on " .. route.map)
    local battle = { kind = "wild", game = p1, data = p1.data, enemy = { mon = { species = "SNORLAX", level = 30 } } }
    check(CoopBoss.kindOf(battle, rOw) == "snorlax",
          route.map .. " Snorlax is recognized as the 'snorlax' co-op boss")
    local mod = MapScripts.get(route.map)
    check(mod and mod.snorlaxWake and type(mod.snorlaxWake.script) == "table",
          route.map .. " carries snorlaxWake.script")
    sent = {}
    CoopManager.partner.map = route.map
    runRowScript(p1, route.map, mod.snorlaxWake.script, { ow = rOw, npc = snorlaxNpc })
    local evSnorlax = lastRewards()
    check(evSnorlax and find(evSnorlax.rewards, "set_flag", "id", route.flag)
          and find(evSnorlax.rewards, "toggle", "obj", route.obj),
          "waking and clearing " .. route.map .. " Snorlax shares " .. route.flag .. " and hides " .. route.obj)
    p2.overworld = { map = { id = route.map } }
    CoopStory.onPartnerRewards(p2, evSnorlax)
    check(p2.save.flags[route.flag] == true
          and ((p2.save.objectToggles or {})[route.map] or {})[route.obj] == false,
          "partner clears " .. route.map .. " Snorlax roadblock too")
  end
end

-- 7. Gen 1 Hall of Fame partner warp arms save.pendingHallOfFame
do
  local p2 = newGame("TOBY")
  local warpedMap, armedAtWarp
  p2.overworld = {
    map = { id = "CHAMPIONS_ROOM" },
    startWarpTo = function(_, map)
      warpedMap = map
      armedAtWarp = p2.save.pendingHallOfFame
    end,
  }
  local realIdle = CoopManager.overworldIdle
  CoopManager.overworldIdle = function() return true end
  CoopStory.pendingWarp = { kind = "warp", map = "HALL_OF_FAME", x = 4, y = 7, facing = "up" }
  CoopStory.tick(0.016, p2)
  CoopManager.overworldIdle = realIdle
  check(warpedMap == "HALL_OF_FAME" and armedAtWarp == true,
        "Gen 1 partner warp to HALL_OF_FAME arms save.pendingHallOfFame before warping")
end

BattleState.newWild, BattleState.newTrainer = origNewWild, origNewTrainer
GV.set(wasGame)
CoopManager.isConnected = realIsConnected
print(("%d/%d checks passed  (co-op Red/Blue/Yellow story)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
