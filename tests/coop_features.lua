-- THE CO-OP EXTRAS (src/coop/Coop*.lua feature modules), one block each,
-- against a fake link that records what goes out.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local SaveData = require("src.core.SaveData")
local CoopManager = require("src.coop.CoopManager")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end,
                    update = function() end, poll = function() return {} end }
CoopManager.connected = true
CoopManager.linkSerial = 1
CoopManager.partner.name = "TOBY"

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local pressed = {}
local save = SaveData.newGame()
save.player.name = "ME"
local game = { data = Data, save = save, stack = newStack(),
               input = { wasPressed = function(_, b) return pressed[b] end, isDown = function() return false end } }
package.loaded["src.core.Game"] = game

local function sentOf(kind)
  local out = {}
  for _, m in ipairs(sent) do if m.type == kind then out[#out + 1] = m end end
  return out
end

local function recv(msg) CoopManager.dispatch(nil, msg) end

-- two species the fixture data knows
local species = {}
for id in pairs(Data.pokemon) do species[#species + 1] = id end
table.sort(species)
local A, B, C = species[1], species[2], species[3]

-- ---------------------------------------------------------------------
-- POKéDEX: compare, and SHARE DEX
-- ---------------------------------------------------------------------

do
  local CoopDex = require("src.coop.CoopDex")
  save.pokedex = { seen = { [A] = true }, owned = { [A] = true } }
  sent = {}
  CoopManager.update(nil, 1 / 60)
  local whole = sentOf("coop_dex")
  T.check(#whole == 1 and whole[1].owned[1] == A, "the whole dex goes out once per link")
  CoopManager.update(nil, 1 / 60)
  T.check(#sentOf("coop_dex") == 1, "...and only once")

  save.pokedex.owned[B] = true
  CoopDex.checkTimer = CoopDex.CHECK_EVERY
  CoopManager.update(nil, 1 / 60)
  local adds = sentOf("coop_dex_add")
  T.check(#adds == 1 and adds[1].owned[1] == B, "a new catch goes out as it lands")

  recv({ type = "coop_dex", owned = { A, C }, seen = { A, C } })
  T.check(not save.pokedex.seen[C], "SHARE DEX off: the partner's catches stay theirs")
  local screen = CoopDex.open(game)
  local lists = screen:lists()
  T.check(#lists[1] == 1 and lists[1][1] == C, "the screen lists what only the partner has")
  T.check(#lists[2] == 1 and lists[2][1] == B, "...and what only you have")
  game.stack:pop()

  sent = {}
  CoopManager.setRule("shareDex", true)
  T.check(#sentOf("coop_rules") == 1, "SHARE DEX is a shared rule")
  T.check(#sentOf("coop_dex_req") == 1, "switching it on asks for the partner's dex")
  recv({ type = "coop_dex", owned = { A, C }, seen = { A, C } })
  T.check(save.pokedex.seen[C] and not save.pokedex.owned[C], "SHARE DEX on: their catch is SEEN, not owned")
  save.pokedex.seen[C] = nil
  recv({ type = "coop_dex_add", owned = { C } })
  T.check(save.pokedex.seen[C], "...and so is each new one")
  CoopManager.setRule("shareDex", false)

  CoopManager.linkSerial = 2
  sent = {}
  CoopManager.update(nil, 1 / 60)
  T.check(#sentOf("coop_dex") == 1 and CoopDex.partner == nil, "a new link starts over")
end

-- ---------------------------------------------------------------------
-- RECONNECT: the save remembers the link and picks it back up
-- ---------------------------------------------------------------------

do
  local CoopRejoin = require("src.coop.CoopRejoin")
  CoopManager.isHost = false
  CoopManager.net.address, CoopManager.net.port = "10.147.17.5:7777", 7777
  CoopManager.linkSerial = 3
  CoopManager.update(nil, 1 / 60)
  local link = save.coopLink
  T.check(link and link.role == "guest" and link.ip == "10.147.17.5" and link.partner == "TOBY",
    "a link is written into the save")

  local join, idleFn = CoopManager.join, CoopManager.overworldIdle
  local dials = 0
  CoopManager.join = function() dials = dials + 1 return true end
  CoopManager.overworldIdle = function() return true end
  CoopManager.connected = false
  CoopManager.net.closed = true
  local ow = { map = { id = "ROUTE_29" } }
  for _ = 1, 60 do CoopManager.update(ow, 1 / 60) end
  T.check(dials == 0, "not on the first second back on the map")
  for _ = 1, 120 do CoopManager.update(ow, 1 / 60) end
  T.check(dials == 1, "the guest dials the host once settled")
  for _ = 1, 40 do CoopManager.update(ow, 0.25) end
  T.check(dials == 1, "...and waits between tries")
  for _ = 1, 50 do CoopManager.update(ow, 0.25) end
  T.check(dials == 2, "...then tries again")
  CoopRejoin.stop(game)
  for _ = 1, 200 do CoopManager.update(ow, 0.25) end
  T.check(dials == 2, "DISCONNECT stops the tries")
  local opts = package.loaded["pkmultiplayer.options"]
  package.loaded["pkmultiplayer.options"] = { on = function() return false end }
  T.check(not CoopRejoin.enabled(), "AUTO RECONNECT can be switched off")
  package.loaded["pkmultiplayer.options"] = opts
  CoopManager.join, CoopManager.overworldIdle = join, idleFn
  CoopManager.connected = true
  CoopManager.net.closed = nil
end

-- ---------------------------------------------------------------------
-- THE FOLLOWER finds things, and sparkles when shiny
-- ---------------------------------------------------------------------

do
  local FollowMon = require("src.follow.FollowMon")
  Data.items.FIX_POTION.key = "POTION"
  Data.items.FIX_BALL.key = "POKE_BALL"
  save.pkmFollowerFind = nil
  local lead = { species = A, happiness = 50, hp = 10 }
  local always = function(n) if n then return 1 end return 0.01 end
  FollowMon.onStep(game, lead, always)
  T.check(save.pkmFollowerFind == nil, "an unfriendly lead finds nothing")
  lead.happiness = 150
  FollowMon.onStep(game, lead, function(n) if n then return 2 end return 0.01 end)
  T.check(save.pkmFollowerFind == nil, "most steps find nothing")
  FollowMon.onStep(game, lead, always)
  T.check(save.pkmFollowerFind and save.pkmFollowerFind.key == "POTION", "a friendly lead finds something")
  T.check(FollowMon.rollFind(game, function() return 0.99 end) == "POKE_BALL",
    "only what this cartridge has, and nothing that needs badges")
  FollowMon.onStep(game, lead, function(n) if n then return 1 end return 0.99 end)
  T.check(save.pkmFollowerFind.key == "POTION", "one find at a time")

  local shown
  local TextBox = package.loaded["src.render.TextBox"]
  package.loaded["src.render.TextBox"] = { new = function(_, text) shown = text return { text = text } end }
  save.party = { lead }
  save.inventory = save.inventory or {}
  FollowMon.talk(game, { player = {} }, { facePlayer = function() end })
  package.loaded["src.render.TextBox"] = TextBox
  game.stack:pop()
  T.check((save.inventory.FIX_POTION or 0) >= 1 and save.pkmFollowerFind == nil, "A on it hands the find over")
  T.check(shown and shown:find("found") ~= nil, "...and says so")

  local snap
  local ow = { npcs = { { pkmFollower = true, spriteName = "SPRITE_MON_001", px = 0, py = 0,
                          facing = "down", pkmShiny = true } } }
  snap = FollowMon.snapshot(ow)
  T.check(snap and snap.sh == true, "a shiny follower tells the partner it is shiny")
end

-- ---------------------------------------------------------------------
-- MYSTERY GIFT: ask, yes, one gift each way, once a day
-- ---------------------------------------------------------------------

do
  local CoopGift = require("src.coop.CoopGift")
  Data.items.FIX_POTION.key = "BERRY"
  save.coopGifts = nil
  save.inventory = {}
  local boxes = {}
  local TextBox = package.loaded["src.render.TextBox"]
  package.loaded["src.render.TextBox"] = { new = function(_, text, onDone, opts)
    boxes[#boxes + 1] = { text = text, opts = opts } return { text = text } end }
  local idleFn = CoopManager.overworldIdle
  CoopManager.overworldIdle = function() return true end
  local ow = { map = { id = "ROUTE_29" } }
  sent = {}
  CoopGift.ask(game, ow)
  local req = sentOf("coop_gift_req")[1]
  T.check(req ~= nil, "MYSTERY GIFT asks the partner")
  -- the partner's game (same process: its handlers, its save)
  CoopManager.dispatch(ow, req)
  local prompt = boxes[#boxes]
  T.check(prompt and prompt.opts and prompt.opts.choice, "the partner is asked yes or no")
  T.check(prompt.text:match("^[^\n]+\n(.*)$") and #prompt.text:match("\n(.*)$") <= 18, "the question fits the text box")
  save.coopGifts = nil -- the asker's save is the same table here
  prompt.opts.choice(true)
  local reply = sentOf("coop_gift_reply")[1]
  T.check(reply and reply.ok and reply.item == "BERRY", "a yes sends a gift back with it")
  save.coopGifts = nil
  CoopManager.dispatch(ow, reply)
  local give = sentOf("coop_gift_give")[1]
  T.check(give and give.item == "BERRY", "the asker sends one too")
  T.check((save.inventory.FIX_POTION or 0) == 1, "the gift lands in the BAG")
  CoopManager.dispatch(ow, give)
  T.check((save.inventory.FIX_POTION or 0) == 2, "...on both sides")
  T.check(CoopGift.swappedToday(save), "the swap is written down for today")
  local before = #sentOf("coop_gift_req")
  CoopGift.ask(game, ow)
  T.check(#sentOf("coop_gift_req") == before and boxes[#boxes].text:find("today"), "once a day per partner")

  -- a shared clock that moves the hours hands out no second swap
  local realDate = os.date
  os.date = function(fmt, t) return realDate(fmt, (t or os.time()) + 86400 * 3) end
  T.check(CoopGift.swappedToday(save), "the once-a-day is the real calendar, not the shared clock")
  os.date = realDate

  -- their YES after the wait ran out still completes the swap
  save.coopGifts = nil
  sent = {}
  CoopGift.ask(game, ow)
  local ask2 = sentOf("coop_gift_req")[1]
  CoopGift.asking.at = -1e9
  CoopManager.idleTickers.gift(0.1, game)
  T.check(CoopGift.asking == nil and CoopGift.late == ask2.id, "the wait runs out, the answer is still expected")
  local bagBefore = save.inventory.FIX_POTION or 0
  CoopManager.dispatch(ow, { type = "coop_gift_reply", id = ask2.id, ok = true, item = "BERRY" })
  T.check((save.inventory.FIX_POTION or 0) == bagBefore + 1 and sentOf("coop_gift_give")[1],
          "a late yes still delivers both gifts")

  -- a gift this cartridge has no item for arrives as one of the same rarity
  T.check(CoopGift.substitute(game, "MIRAGE_MAIL") == "BERRY", "an unknown gift becomes one this game has")
  package.loaded["src.render.TextBox"] = TextBox
  CoopManager.overworldIdle = idleFn
  game.stack = newStack()
end

-- ---------------------------------------------------------------------
-- STORY EVENTS: each lived once, never in the middle of our own script
-- ---------------------------------------------------------------------

do
  local CoopStory = require("src.coop.CoopStory")
  local Bag = require("src.inventory.Bag")
  local running = false
  local storyGame = { data = Data, save = SaveData.newGame(), stack = newStack(),
                      overworld = { map = { id = "ROUTE_29" },
                                    runner = { isRunning = function() return running end } } }
  storyGame.save.flags = {}
  storyGame.save.inventory = {}
  CoopManager.storySync = true
  local function event(eid)
    return { type = "coop_story_rewards", backlog = true, eid = eid, speaker = "TOBY",
             rewards = { { kind = "item", id = "FIX_POTION", count = 1 } } }
  end
  CoopStory.onPartnerRewards(storyGame, event("P:1"))
  T.check(storyGame.save.inventory.FIX_POTION == 1, "a partner's event hands out its item")
  CoopStory.onPartnerRewards(storyGame, event("P:1"))
  T.check(storyGame.save.inventory.FIX_POTION == 1, "the same event arriving again is not lived twice")

  -- both of us talked to the same NPC: theirs lands while ours is talking
  running = true
  CoopStory.onPartnerRewards(storyGame, { type = "coop_story_rewards", eid = "P:2", speaker = "TOBY",
    rewards = { { kind = "set_flag", id = "EVENT_FIX_GIFT" }, { kind = "item", id = "FIX_POTION", count = 1 } } })
  T.check(storyGame.save.inventory.FIX_POTION == 1 and not storyGame.save.flags.EVENT_FIX_GIFT,
          "an event that arrives mid-script waits for the script")
  -- our own script gives the item and sets the flag
  Bag.add(storyGame.save, "FIX_POTION", 1, Data)
  storyGame.save.flags.EVENT_FIX_GIFT = true
  CoopStory.tick(0.1, storyGame)
  T.check(#CoopStory.deferred == 1, "...for as long as it runs")
  running = false
  CoopStory.tick(0.1, storyGame)
  T.check(#CoopStory.deferred == 0 and storyGame.save.inventory.FIX_POTION == 2,
          "once it ends, the partner's copy sees the flag set and gives nothing more")

  -- each event leaving this save has its own name
  local a, b = CoopStory.stamp(save), CoopStory.stamp(save)
  T.check(a ~= b and a:find(":") ~= nil, "every event gets its own id")
  save.coopStoryOutbox = nil
  CoopStory.queue(save, { { kind = "money", amount = 10 } })
  T.check(save.coopStoryOutbox[1].eid ~= nil, "a queued event keeps its id for the partner")
  save.coopStoryOutbox = nil
end

-- ---------------------------------------------------------------------
-- DRAMATICSHAPES: a co-op double on the flat screen keeps the back pics
-- ---------------------------------------------------------------------

do
  local CoopCompat = require("src.coop.CoopCompat")
  local CoopBattle = require("src.coop.CoopBattle")
  local OB = { begin = function() return true end, wantsFront = function() return true end }
  rawset(_G, "__DRAMATIC_SHAPE_V", { require = function() return OB end })
  CoopCompat.done = nil
  T.check(CoopCompat.wrapDramaticShapes(), "DramaticShapes is wrapped")
  local was = CoopBattle.currentBattle
  CoopBattle.currentBattle = nil
  T.check(OB.wantsFront() == true, "outside co-op its 3D battles still ask for front pics")
  CoopBattle.currentBattle = { coopDouble = true, coop = {} }
  T.check(OB.wantsFront() == false, "a co-op double gets our Pokemon's back pics")
  CoopBattle.currentBattle = { coopWild = true, coop = { finished = true } }
  T.check(OB.wantsFront() == true, "...only while it lasts")
  CoopBattle.currentBattle = was
  rawset(_G, "__DRAMATIC_SHAPE_V", nil)
end

-- ---------------------------------------------------------------------
-- SOUL LINK: first catches bound by area, fainting together
-- ---------------------------------------------------------------------

do
  local SL = require("src.coop.CoopSoulLink")
  save.soulLinks = nil
  CoopManager.setRule("soulLink", true)
  local m1 = { species = A, hp = 20 }
  local m2 = { species = B, hp = 20 }
  local m3 = { species = C, hp = 20 }
  save.party = { m1, m2 }
  save.box = { m3 }
  sent = {}
  SL.onCaught(game, m1, "UNION_CAVE_B1F")
  local c = sentOf("coop_soul_catch")[1]
  T.check(c and c.area == "UNION_CAVE" and m1.soulId == c.id, "the first catch in an area is bound (floors are one area)")
  SL.onCaught(game, m2, "UNION_CAVE_1F")
  T.check(m2.soulId == nil and #sentOf("coop_soul_catch") == 1, "the second catch there is free")
  SL.onCaught(game, m3, "ROUTE_30")
  recv({ type = "coop_soul_catch", area = "UNION_CAVE", id = "p1", species = C })
  recv({ type = "coop_soul_catch", area = "ROUTE_30", id = "p2", species = A })
  T.check(save.soulLinks.UNION_CAVE.theirs == "p1", "the partner's catch there is its pair")

  m1.hp = 0
  sent = {}
  SL.watch(game)
  local d = sentOf("coop_soul_dead")[1]
  T.check(d and d.area == "UNION_CAVE" and save.soulLinks.UNION_CAVE.dead, "a faint breaks the bond and tells the partner")
  m1.hp = 25
  SL.watch(game)
  T.check(m1.hp == 0, "...and a Pokemon Center can't bring it back")

  recv({ type = "coop_soul_dead", area = "ROUTE_30", id = "p2" })
  T.check(m3.hp == 0 and m3.soulDead, "the partner's faint takes ours with it, even in the PC")

  m2.hp = 0
  sent = {}
  SL.watch(game)
  T.check(#sentOf("coop_soul_dead") == 0, "an unbound Pokemon's faint is only a faint")

  -- notes compared on a new link: a faint while apart
  save.soulLinks.LAKE = { mine = "x9", mineSpecies = B }
  local m4 = { species = B, hp = 30, soulId = "x9" }
  save.party[3] = m4
  recv({ type = "coop_soul_sync", links = { { area = "LAKE", id = "q", species = A, dead = true } } })
  T.check(m4.hp == 0 and save.soulLinks.LAKE.theirs == "q", "a faint told late still counts")
  CoopManager.setRule("soulLink", false)
  save.party, save.box = {}, {}
end

-- ---------------------------------------------------------------------
-- POKéGEAR: the partner in the phone book, a call opens the chat
-- ---------------------------------------------------------------------

do
  local PokegearMenu = require("src.ui.PokegearMenu")
  local menu = setmetatable({ game = game }, { __index = PokegearMenu })
  save.g2Phone = nil
  local list = menu:contacts()
  T.check(list[1] and list[1].coopPartner and list[1].name == "TOBY", "the partner heads the phone book")
  T.check(list[2] and list[2].name ~= "TOBY", "...above the usual numbers")
  T.check(not PokegearMenu.canDeleteContact(list[1]), "the partner's number can't be deleted")
  local opened
  local openChat = CoopManager.openChat
  CoopManager.openChat = function() opened = true end
  local TextBox = package.loaded["src.render.TextBox"]
  local after
  package.loaded["src.render.TextBox"] = { new = function(_, text, onDone) after = onDone return { text = text } end }
  sent = {}
  menu:startPhoneCall(list[1])
  T.check(#sentOf("coop_call") == 1, "CALL rings the partner")
  if after then after() end
  T.check(opened, "...and opens the chat")
  package.loaded["src.render.TextBox"] = TextBox
  CoopManager.openChat = openChat
  game.stack = newStack()
  CoopManager.connected = false
  T.check(not menu:contacts()[1].coopPartner, "unlinked, the phone book is the cartridge's")
  CoopManager.connected = true
end

-- ---------------------------------------------------------------------
-- WILD TOGETHER: a random encounter asks a nearby partner along
-- ---------------------------------------------------------------------

do
  local CoopWild = require("src.coop.CoopWild")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  save.party = { Pokemon.new(Data, A, 10) }
  game.stack = newStack()
  local battle = BattleState.newWild(game, B, 7)
  local ow = { map = { id = "ROUTE_29" }, player = { cellX = 5, cellY = 5 }, pkmRandomEncounter = true,
               game = game }
  local p = CoopManager.partner
  p.map, p.cx, p.cy, p.lastSeen, p.healthy = "ROUTE_29", 6, 5, math.huge, 2
  p.inBattle, p.busy, p.inDialogue = false, false, false
  CoopManager.net.stalled = false
  CoopManager.setRule("wildTogether", false)
  T.check(not CoopWild.offer(ow, battle), "rule off: the battle is yours")
  CoopManager.setRule("wildTogether", true)
  ow.pkmRandomEncounter = nil
  T.check(not CoopWild.offer(ow, battle), "a scripted wild battle stays yours")
  ow.pkmRandomEncounter = true
  p.cx = 40
  T.check(not CoopWild.offer(ow, battle), "a partner across the map is not asked")
  p.cx = 6
  sent = {}
  T.check(CoopWild.offer(ow, battle), "a partner close by is asked")
  local inv = sentOf("coop_battle_invite")[1]
  T.check(inv and inv.battleKind == "wild" and inv.species == B and inv.wildMon, "the invite carries the wild Pokemon")
  T.check(CoopManager.pendingBattleInvite and CoopManager.pendingBattleInvite.battle == battle, "...and the battle waits on the answer")
  CoopManager.pendingBattleInvite = nil
  game.stack = newStack()

  local copy = CoopWild.guestBattle(game, inv)
  local a, b = battle.enemy.mon, copy.enemy.mon
  T.check(b.species == a.species and b.level == a.level and b.hp == a.hp
          and (b.dvs and a.dvs and b.dvs.attack == a.dvs.attack or b.dvs == a.dvs),
    "the partner fights the same individual")
  CoopWild.prepare(copy)
  T.check(copy.coopWild and copy.enemyParty and copy.enemyParty[1] == b, "it becomes a one-Pokemon party, mirrored by the double")

  local ItemEffects = require("src.inventory.ItemEffects")
  local ballId
  for id, def in pairs(Data.items) do
    if ItemEffects.isBall and ItemEffects.isBall(id, def) then ballId = id end
  end
  if ballId then
    save.inventory = { [ballId] = 1 }
    local plain = ItemEffects.use(Data, save, ballId, nil, battle)
    local r, msgs = ItemEffects.use(Data, save, ballId, nil, copy)
    T.check(plain == "ball" and r == "failed" and msgs and msgs[1]:find("together"), "no BALL in a battle together")
  end

  sent = {}
  copy.coopDouble = true
  copy.coop = { inviteId = "w1" }
  copy:tryRun()
  T.check(copy.result == "run" and #sentOf("coop_wild_run") == 1, "RUN gets both away, no roll")
  CoopManager.setRule("wildTogether", false)
end

-- ---------------------------------------------------------------------
-- DRAMATICSHAPES: a co-op double is not staged in 3D (its HUD is cut for
-- singles); singles still are
-- ---------------------------------------------------------------------

do
  local staged, finished = 0, 0
  local OB = { begin = function() staged = staged + 1 return true end,
               finish = function() finished = finished + 1 end }
  rawset(_G, "__DRAMATIC_SHAPE_V", { require = function(name) return name == "OverworldBattle" and OB or nil end })
  CoopManager.update(nil, 1 / 60)
  T.check(OB.begin({}, { coopDouble = true }) == false and staged == 0, "a co-op double stays on the classic screen")
  T.check(OB.begin({}, { kind = "wild" }) == true and staged == 1, "a single is still staged")
  local wrapped = OB.begin
  CoopManager.update(nil, 1 / 60)
  T.check(OB.begin == wrapped, "wrapped once")
  rawset(_G, "__DRAMATIC_SHAPE_V", nil)
end

-- ---------------------------------------------------------------------
-- WATCH: the partner's battle, as it happens
-- ---------------------------------------------------------------------

do
  local CoopWatch = require("src.coop.CoopWatch")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  save.party = { Pokemon.new(Data, A, 10) }
  game.stack = newStack()
  local battle = BattleState.newWild(game, B, 7)
  battle.current = { text = "Wild one\nappeared!" }
  game.stack:push(battle)
  sent = {}
  CoopManager.update(nil, 1 / 60)
  T.check(#sentOf("coop_watch_frame") == 0, "nothing goes out while nobody watches")
  recv({ type = "coop_watch", on = true })
  CoopManager.update(nil, 1 / 60)
  local f = sentOf("coop_watch_frame")[1]
  T.check(f and f.foe and f.foe.species == B and f.mine and f.mine.species == A, "watched: the battle goes out")
  T.check(f and f.text == "Wild one appeared!", "...with the line on the text box")
  game.stack:pop()
  sent = {}
  CoopWatch.timer = 0
  CoopManager.update(nil, 1 / 60)
  f = sentOf("coop_watch_frame")[1]
  T.check(f and f.idle, "out of battle: 'not in a battle'")
  recv({ type = "coop_watch", on = false })
  recv({ type = "coop_watch_frame", foe = { species = B }, mine = { species = A }, text = "x" })
  T.check(CoopWatch.frame and CoopWatch.frame.text == "x", "the watcher keeps the latest frame")
end

-- ---------------------------------------------------------------------
-- VISITORS: the guest hears of them; every chat line goes on to them
-- ---------------------------------------------------------------------

do
  local CoopVisit = require("src.coop.CoopVisit")
  recv({ type = "coop_visitors", list = { { id = "v1", name = "ASH", map = "ROUTE_29", px = 16, py = 32 } } })
  T.check(CoopVisit.others.v1 and CoopVisit.others.v1.name == "ASH", "the guest learns who is visiting")
  local out = {}
  local peer = { send = function(_, s) out[#out + 1] = s end }
  CoopVisit.server = { visitors = { [peer] = { id = 1, name = "ASH" } }, enetHost = {} }
  CoopManager.onChatReceived("TOBY", "HEY", false)
  T.check(#out == 1 and out[1]:find("HEY"), "a chat line goes on to the visitors")
  CoopVisit.relaying = true
  CoopManager.onChatReceived("ASH", "MINE", false)
  CoopVisit.relaying = false
  T.check(#out == 1, "...but a visitor's own line is not echoed back by the listener")
  CoopVisit.server = nil
  CoopVisit.others = {}
  local routed
  CoopManager.connected = false
  CoopManager.chatRoute = function(sender, text) routed = text end
  CoopManager.sendChat("VISITING")
  T.check(routed == "VISITING", "a visitor's chat goes to the host's world")
  CoopManager.chatRoute = nil
  CoopManager.connected = true

  -- the host's door: old versions sent home, late positions ignored, chat held back
  local Json = require("src.link.Json")
  local events = {}
  local wasHost = CoopManager.isHost
  CoopManager.isHost = true
  CoopManager.net.isHost, CoopManager.net.closed, CoopManager.net.port = true, false, 7777
  CoopVisit.server = { visitors = {}, nextId = 1, timer = 99,
                       enetHost = { service = function() return table.remove(events, 1) end,
                                    flush = function() end } }
  local function visitor()
    local v = { out = {} }
    v.send = function(_, s2) v.out[#v.out + 1] = Json.decode(s2) end
    v.disconnect_later = function() v.gone = true end
    return v
  end
  local function tick() CoopManager.idleTickers.visit(0.016, game, nil) end
  local old = visitor()
  events[#events + 1] = { type = "connect", peer = old }
  events[#events + 1] = { type = "receive", peer = old, data = Json.encode({ t = "hi", name = "OLD", proto = 13 }) }
  tick()
  T.check(old.gone and old.out[1] and old.out[1].t == "old", "a visitor on another version is told and sent home")
  local ash = visitor()
  events[#events + 1] = { type = "connect", peer = ash }
  events[#events + 1] = { type = "receive", peer = ash,
                          data = Json.encode({ t = "hi", name = "ASH", proto = CoopManager.PROTOCOL }) }
  events[#events + 1] = { type = "receive", peer = ash, data = Json.encode({ t = "pos", n = 5, map = "ROUTE_29", px = 80, py = 0 }) }
  events[#events + 1] = { type = "receive", peer = ash, data = Json.encode({ t = "pos", n = 4, map = "ROUTE_29", px = 16, py = 0 }) }
  tick()
  local v = CoopVisit.server.visitors[ash]
  T.check(v and v.px == 80, "a late position never moves a visitor backwards")
  sent = {}
  for i = 1, 10 do
    events[#events + 1] = { type = "receive", peer = ash, data = Json.encode({ t = "chat", text = "SPAM" .. i }) }
  end
  tick()
  T.check(#sentOf("coop_chat") == CoopVisit.CHAT_BURST, "a visitor's flood of chat is held to a few lines")
  CoopVisit.server = nil
  CoopManager.isHost = wasHost
  CoopManager.net.isHost, CoopManager.net.closed = nil, nil
end

-- ---------------------------------------------------------------------
-- LINK DAYCARE: the partner's boarder breeds with ours -- in the sums only
-- ---------------------------------------------------------------------

do
  local DayCare = require("src.pokemon.DayCare")
  require("src.pokemon.Gen2Breeding")
  require("src.coop.CoopDayCare")
  local own = { species = A, level = 20, otId = 1, dvs = { attack = 15, defense = 3, speed = 3, special = 3 } }
  save.daycare = { breed = { [DayCare.MAN] = { mon = own } } }
  CoopManager.setRule("shareDayCare", true)
  sent = {}
  CoopManager.update(nil, 1 / 60)
  local ann = sentOf("coop_daycare")[1]
  T.check(ann and ann.mon and ann.mon.species == A, "our boarder is told to the partner")
  recv({ type = "coop_daycare", mon = { species = A, level = 22, otId = 2,
                                        dvs = { attack = 0, defense = 9, speed = 9, special = 9 } } })
  T.check(save.coopDayCareMate and save.coopDayCareMate.mon.otId == 2, "theirs is kept as a copy")
  T.check(DayCare.mon(save, DayCare.LADY) == nil, "the DAY-CARE's own talk never sees it")
  local seen
  local CoopDayCare = package.loaded["src.coop.CoopDayCare"]
  CoopDayCare.within(save, function() seen = DayCare.mon(save, DayCare.LADY) end)
  T.check(seen and seen.otId == 2, "the breeding sums do")
  local fakeData = { pokemon = { [A] = { eggGroups = { "MONSTER" }, genderRatio = 127 } } }
  local a, b = DayCare.pair(fakeData, save)
  T.check(a == own and b and b.otId == 2, "DayCare.pair sees the pair")
  T.check(DayCare.compatibility(fakeData, save) == 4, "same species, different trainers: the best match")
  recv({ type = "coop_daycare" })
  T.check(save.coopDayCareMate == nil and DayCare.pair(fakeData, save) == nil, "theirs withdrawn: no pair")
  CoopManager.setRule("shareDayCare", false)
  save.daycare = nil
end

-- ---------------------------------------------------------------------
-- BATTLE TOWER multi: only Pokemon under the cap may join
-- ---------------------------------------------------------------------

do
  local CoopTower = require("src.coop.CoopTower")
  local party = { { level = 50, hp = 10 }, { level = 20, hp = 10 }, { level = 18, hp = 0 },
                  { level = 10, hp = 5, isEgg = true }, { level = 15, hp = 3 } }
  local ok = CoopTower.eligible(party, 20)
  T.check(#ok == 2 and ok[1].level == 20 and ok[2].level == 15, "over the cap, fainted and eggs stay home")
  T.check(not CoopTower.isTower({ kind = "trainer" }) and CoopTower.isTower({ battleTower = true }), "a tower battle is told apart")
end

T.finish("co-op extras")
