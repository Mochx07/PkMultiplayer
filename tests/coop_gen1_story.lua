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
check(#notices >= 1 and notices[1]:find("Crystal", 1, true), "the link says the story is not shared")
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

GV.set(wasGame)
CoopManager.isConnected = realIsConnected
print(("%d/%d checks passed  (co-op Red/Blue/Yellow story)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
