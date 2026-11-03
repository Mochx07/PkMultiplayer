-- SHARED SCENES WITH TWO LEADS (1.20, capability "story.duo",
-- src/coop/CoopDuo.lua).
--
-- Mochi: "que se vea que uno no es fantasma o la sombra del otro".  The
-- partner standing in a scene used to read a box that turned by itself and
-- got "You got POTION too!" on the status line.  With both copies on 1.20:
--   * the partner turns their pages with their own A (the one playing the
--     scene is never held up); pages left behind fold into one;
--   * either can react (SELECT + a direction, or the number pad's 1-4): a
--     bubble over their avatar and a short line on the other screen;
--   * the scene's gift reaches the partner in a box of its own, "TOBY
--     received POTION!" with its jingle, and the first screen reads "TOBY
--     got one too!"; the handover page on the first screen names its own
--     player only; a badge won together is handed over the same way.
-- A 1.6 partner (no caps) gets everything exactly as before.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local CoopManager = require("src.coop.CoopManager")
local CoopStory = require("src.coop.CoopStory")
local CoopDuo = require("src.coop.CoopDuo")
local I18n = require("src.coop.CoopI18n")
local TextBox = require("src.render.TextBox")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end }
CoopManager.connected = true
CoopManager.isConnected = function() return true end
CoopManager.storySync = true
CoopManager.partner = CoopManager.partner or {}
CoopManager.partner.name = "TOBY"
CoopManager.partner.map = "ELMS_LAB"
CoopManager.partner.emoteTimer = 0
CoopManager.getLocalPlayerName = function(game)
  return game and game.save and game.save.player and game.save.player.name or "MOCHX"
end

local function lastOf(kind)
  for i = #sent, 1, -1 do if sent[i].type == kind then return sent[i] end end
end
local function count(kind)
  local n = 0
  for _, m in ipairs(sent) do if m.type == kind then n = n + 1 end end
  return n
end
local function duo(on)
  CoopManager.partner.caps = on and { ["story.duo"] = true } or nil
end

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local function newInput()
  return { pressQueue = {}, pressed = {}, state = {},
           isDown = function(self, b) return self.state[b] == true end,
           wasPressed = function(self, b) return self.pressed[b] == true end }
end

local function newGame(name, map)
  local ow = { map = { id = map or "ELMS_LAB" }, npcs = {} }
  local g = { data = Data, save = { player = { name = name }, flags = {}, inventory = {} },
              stack = newStack(), overworld = ow, input = newInput() }
  ow.game = g
  g.stack:push(ow)
  return g
end

-- ---------------------------------------------------------------------
-- the capability
-- ---------------------------------------------------------------------
T.check(CoopManager.CAPS["story.duo"] == true, "this copy announces story.duo")
duo(false)
T.check(not CoopDuo.on(), "a partner without it (1.6): the duo is off")
duo(true)
T.check(CoopDuo.on(), "both have it: on")

-- ---------------------------------------------------------------------
-- the handover page
-- ---------------------------------------------------------------------
T.check(CoopDuo.isHandover("{PLAYER} received\nTM24."), "\"{PLAYER} received\" is a handover")
T.check(CoopDuo.isHandover("{PLAYER} got\nPOTION!"), "\"{PLAYER} got\" (verbosegiveitem) too")
T.check(CoopDuo.isHandover("{PLAYER} got ¥{RAM:wBattleReward}\nfor winning!"), "...and the prize money")
T.check(CoopDuo.isHandover("{RAM:wPlayerName} received\nZEPHYRBADGE."), "the RAM spelling of the name too")
T.check(not CoopDuo.isHandover("Here, {PLAYER}!"), "a line that only names the player is not")
T.check(not CoopDuo.isHandover("{PLAYER} turned on\nthe PC."), "a line where the player does something else is not")
T.check(not CoopDuo.isHandover("ELM: {PLAYER} received\nit."), "the name has to open the page")

-- ---------------------------------------------------------------------
-- the screen playing the scene
-- ---------------------------------------------------------------------
do
  sent = {}
  local game = newGame("MOCHX")
  local ctx = { game = game, overworld = game.overworld, save = game.save }
  CoopStory.begin(ctx)
  T.check(CoopStory.duoName() == "MOCHX & TOBY", "a shared scene addresses both")
  duo(true)
  T.check(TextBox.substitute(game, "Here, {PLAYER}!") == "Here, MOCHX & TOBY!", "an ordinary line still names both")
  T.check(TextBox.substitute(game, "{PLAYER} received\nTM24.") == "MOCHX received\nTM24.",
          "the handover page names this player alone: " .. tostring(TextBox.substitute(game, "{PLAYER} received\nTM24.")))
  local mixed = TextBox.substitute(game, "Take this, {PLAYER}!\f{PLAYER} got\nPOTION!")
  T.check(mixed == "Take this, MOCHX & TOBY!\fMOCHX got\nPOTION!", "page by page: " .. tostring(mixed))
  T.check(CoopStory.duoName() == "MOCHX & TOBY", "...and the duo is still there after it")
  duo(false)
  T.check(TextBox.substitute(game, "{PLAYER} received\nTM24.") == "MOCHX & TOBY received\nTM24.",
          "a 1.6 partner: the handover names both, as before")
  -- the scene's end goes to the partner only with the duo
  CoopStory.finish(ctx)
  T.check(count("coop_story_end") == 0, "no scene end for a 1.6 partner")
  duo(true)
  ctx = { game = game, overworld = game.overworld, save = game.save }
  CoopStory.begin(ctx)
  CoopStory.finish(ctx)
  local e = lastOf("coop_story_end")
  T.check(e and e.map == "ELMS_LAB", "the scene's end is told to the partner reading it")
  T.check(TextBox.substitute(game, "{PLAYER} received\nTM24.") == "MOCHX received\nTM24.", "outside a scene: the plain name")
  -- a scene with the partner elsewhere tells them nothing
  sent = {}
  CoopManager.partner.map = "ROUTE_29"
  ctx = { game = game, overworld = game.overworld, save = game.save }
  CoopStory.begin(ctx)
  CoopStory.finish(ctx)
  T.check(count("coop_story_end") == 0, "a scene the partner is not in has no end to tell")
  CoopManager.partner.map = "ELMS_LAB"
end

-- ---------------------------------------------------------------------
-- the partner's screen: their line, filled in here
-- ---------------------------------------------------------------------
do
  local game = newGame("TOBY")
  CoopManager.partner.name = "MOCHX"
  CoopStory.feed = {}
  duo(true)
  CoopStory.onPartnerText(game, { map = "ELMS_LAB", text = "MOCHX & TOBY got\nPOTION!",
                                  raw = "{PLAYER} got\nPOTION!", speaker = "MOCHX" })
  local p = CoopStory.feed[1]
  T.check(p and p[1] == "MOCHX got" and p[2] == "POTION!",
          "the handover page names the one who got it: " .. tostring(p and p[1]))
  CoopStory.feed = {}
  CoopStory.onPartnerText(game, { map = "ELMS_LAB", text = "Here, MOCHX & TOBY!", raw = "Here, {PLAYER}!", speaker = "MOCHX" })
  p = CoopStory.feed[1]
  T.check(p and p[1]:gsub("%s+$", "") == "Here, TOBY &", "an ordinary line puts this player first: " .. tostring(p and p[1]))
  CoopStory.feed = {}
  duo(false)
  CoopStory.onPartnerText(game, { map = "ELMS_LAB", text = "MOCHX & TOBY got\nPOTION!",
                                  raw = "{PLAYER} got\nPOTION!", speaker = "MOCHX" })
  p = CoopStory.feed[1]
  T.check(p and p[1]:find("TOBY &", 1, true) == 1, "without the duo: the 1.20 duo fill, as before (" .. tostring(p and p[1]) .. ")")
  CoopStory.feed = {}
  CoopManager.partner.name = "TOBY"
end

-- ---------------------------------------------------------------------
-- pages turned with this player's A
-- ---------------------------------------------------------------------
do
  local game = newGame("TOBY")
  CoopManager.partner.name = "MOCHX"
  duo(false)
  CoopStory.feed = { { "one", "" }, { "two", "" } }
  CoopStory.feedTimer = 0
  CoopStory.tick(2.5, game)
  T.check(CoopStory.feed[1][1] == "two", "a 1.6 partner: the page turns by itself, as before")
  duo(true)
  CoopStory.feed = { { "one", "" }, { "two", "" } }
  CoopStory.feedTimer = 0
  CoopStory.tick(5, game)
  T.check(CoopStory.feed[1][1] == "one", "with the duo: five seconds later the page still waits")
  table.insert(game.input.pressQueue, "a")
  CoopDuo.onInputStep(game)
  T.check(#game.input.pressQueue == 0, "A is taken by the page, not the field (no NPC talked to)")
  T.check(CoopStory.feed[1][1] == "two", "...and turns it")
  table.insert(game.input.pressQueue, "a")
  CoopDuo.onInputStep(game)
  T.check(CoopStory.feed[1][1] == "two", "a second A at once does not skip the next page")
  CoopStory.tick(0.3, game)
  table.insert(game.input.pressQueue, "a")
  CoopDuo.onInputStep(game)
  T.check(CoopStory.feed[1] == nil, "the last page goes on the next A")
  table.insert(game.input.pressQueue, "a")
  CoopDuo.onInputStep(game)
  T.check(#game.input.pressQueue == 1, "no page: A is the field's again")
  game.input.pressQueue = {}
  -- a menu on top: A is the menu's
  CoopStory.feed = { { "one", "" } }
  CoopStory.feedTimer = 1
  local menu = {}
  game.stack:push(menu)
  table.insert(game.input.pressQueue, "a")
  CoopDuo.onInputStep(game)
  T.check(#game.input.pressQueue == 1 and CoopStory.feed[1] ~= nil, "a menu open: A is left to it")
  CoopStory.tick(30, game)
  T.check(CoopStory.feed[1] ~= nil, "...and the page does not age while out of view")
  game.stack:pop()
  game.input.pressQueue = {}
  CoopStory.feedTimer = 0
  CoopStory.tick(CoopDuo.FEED_IDLE + 0.1, game)
  T.check(CoopStory.feed[1] == nil, "a page nobody turns goes after FEED_IDLE")
  -- the alias that stands in for A (L=A) turns it too
  CoopStory.feed = { { "one", "" } }
  CoopStory.feedTimer = 1
  game.input.buttonAlias = { a = { "l" } }
  table.insert(game.input.pressQueue, "l")
  CoopDuo.onInputStep(game)
  T.check(CoopStory.feed[1] == nil and #game.input.pressQueue == 0, "L as A turns it as well")
  game.input.buttonAlias = nil
  CoopManager.partner.name = "TOBY"
end

-- ---------------------------------------------------------------------
-- left behind: the pages fold
-- ---------------------------------------------------------------------
do
  local feed = {}
  for i = 1, 10 do feed[i] = { "p" .. i, "" } end
  local went = CoopDuo.fold(feed, 4)
  T.check(went == 6 and #feed == 5, "ten pages, four may wait: six fold (" .. #feed .. " left)")
  T.check(feed[1][1] == "p1" and feed[2].skipped == 6 and feed[3][1] == "p8" and feed[5][1] == "p10",
          "the one on screen, \"Skipped 6\", then the newest three")
  T.check(feed[2][1] == "Skipped 6 pages", "the fold says how many: " .. tostring(feed[2][1]))
  feed[#feed + 1] = { "p11", "" }
  feed[#feed + 1] = { "p12", "" }
  CoopDuo.fold(feed, 4)
  T.check(feed[2].skipped == 8 and feed[2][1] == "Skipped 8 pages", "an earlier fold counts in: " .. tostring(feed[2][1]))
  CoopStory.feed = feed
  CoopDuo.onSceneEnd({ map = "ELMS_LAB" })
  T.check(#CoopStory.feed == 3 and CoopStory.feed[2].skipped == 10 and CoopStory.feed[3][1] == "p12",
          "the scene over: only its last page stays behind the fold")
  local short = { { "a", "" }, { "b", "" } }
  T.check(CoopDuo.fold(short, 2) == 0 and #short == 2, "nothing folds while the reader keeps up")
  I18n.forced = "es"
  T.check(CoopDuo.skippedPage(3)[1] == "3 págs. saltadas" or CoopDuo.skippedPage(3)[1] == "3 pags. saltadas",
          "in Spanish: " .. CoopDuo.skippedPage(3)[1])
  I18n.forced = nil
  -- the live path: a partner scene of nine pages, read by nobody
  local game = newGame("TOBY")
  duo(true)
  CoopStory.feed = {}
  for i = 1, 9 do
    CoopStory.onPartnerText(game, { map = "ELMS_LAB", text = "line " .. i, raw = "line " .. i, speaker = "MOCHX" })
  end
  T.check(#CoopStory.feed == 1 + CoopDuo.FEED_BEHIND, "a long scene folds as it comes (" .. #CoopStory.feed .. " pages)")
  T.check(CoopStory.feed[#CoopStory.feed][1] == "line 9", "...keeping the newest")
  CoopStory.feed = {}
end

-- ---------------------------------------------------------------------
-- reactions
-- ---------------------------------------------------------------------
do
  local game = newGame("TOBY")
  CoopManager.partner.name = "MOCHX"
  duo(true)
  CoopDuo.lastReact = nil
  CoopDuo.partnerScene = nil
  CoopStory.feed = {}
  sent = {}
  game.input.state.select = true
  table.insert(game.input.pressQueue, "up")
  CoopDuo.onInputStep(game)
  T.check(count("coop_emote") == 0 and #game.input.pressQueue == 1, "no scene: SELECT + UP is the field's")
  game.input.pressQueue = {}
  CoopStory.onPartnerText(game, { map = "ELMS_LAB", text = "Hi", raw = "Hi", speaker = "MOCHX" })
  T.check(CoopDuo.sceneActive(game), "reading the partner's scene")
  game.input.state.up = true
  table.insert(game.input.pressQueue, "up")
  CoopDuo.onInputStep(game)
  local e = lastOf("coop_emote")
  T.check(e and e.emote == "exclaim" and e.react == true, "SELECT + UP sends the WOW reaction")
  T.check(#game.input.pressQueue == 0 and game.input.state.up == false, "...and the reader does not walk off")
  T.check(CoopManager.localEmote == "exclaim", "...the bubble goes up over this player too")
  table.insert(game.input.pressQueue, "right")
  CoopDuo.onInputStep(game)
  T.check(count("coop_emote") == 1, "two reactions at once: the second waits REACT_GAP")
  CoopDuo.lastReact = -100
  table.insert(game.input.pressQueue, "select")
  CoopDuo.onInputStep(game)
  T.check(#game.input.pressQueue == 0, "SELECT in a scene is not the registered item")
  game.input.state.select = false
  CoopDuo.lastReact = -100
  T.check(CoopDuo.onKey(game, "kp2") and lastOf("coop_emote").emote == "question", "the number pad's 2: HUH?")
  T.check(not CoopDuo.onKey(game, "kp7"), "past 4 the number pad is the plain emote")
  -- the one playing the scene reacts from inside its dialogue box
  CoopStory.feed = {}
  CoopDuo.partnerScene = nil
  local host = newGame("MOCHX")
  CoopManager.partner.name = "TOBY"
  local ctx = { game = host, overworld = host.overworld, save = host.save }
  CoopStory.begin(ctx)
  host.stack:push({ isTextBox = true })
  host.input.state.select = true
  table.insert(host.input.pressQueue, "down")
  CoopDuo.lastReact = -100
  CoopDuo.onInputStep(host)
  T.check(lastOf("coop_emote").emote == "happy", "SELECT + DOWN inside our own scene's box: HA HA!")
  host.input.state.select = false
  CoopStory.finish(ctx)
  -- a 1.6 partner: no reactions at all
  duo(false)
  sent = {}
  CoopDuo.lastReact = -100
  T.check(not CoopDuo.react(host, "exclaim") and count("coop_emote") == 0, "a 1.6 partner: no reactions")
  -- the other screen: the bubble and a line
  duo(true)
  CoopManager.statusMessage = nil
  CoopManager.dispatch(nil, { type = "coop_emote", emote = "question", react = true })
  T.check(CoopManager.partner.emote == "question", "a reaction puts the bubble over the partner")
  T.check(CoopManager.statusMessage == "TOBY: HUH?", "...and a line: " .. tostring(CoopManager.statusMessage))
  CoopManager.statusMessage = nil
  CoopManager.dispatch(nil, { type = "coop_emote", emote = "heart" })
  T.check(CoopManager.statusMessage == nil, "a plain emote has no line, as before")
  I18n.forced = "es"
  CoopManager.dispatch(nil, { type = "coop_emote", emote = "exclaim", react = true })
  T.check(CoopManager.statusMessage == I18n.t("TOBY: WOW!") and CoopManager.statusMessage:find("TOBY", 1, true) == 1
          and CoopManager.statusMessage ~= "TOBY: WOW!", "in Spanish: " .. tostring(CoopManager.statusMessage))
  I18n.forced = nil
  CoopManager.statusMessage = nil
end

-- ---------------------------------------------------------------------
-- the gift, handed over
-- ---------------------------------------------------------------------
do
  local Bag = require("src.inventory.Bag")
  local realAdd = Bag.add
  Bag.add = function(save, id, n) save.inventory[id] = (save.inventory[id] or 0) + n return true end
  local realIdle = CoopManager.overworldIdle
  CoopManager.overworldIdle = function(g, ow) return g.stack:top() == (ow or g.overworld) end
  local game = newGame("TOBY")
  local potion
  for id, def in pairs(Data.items) do if def.name == "POTION" then potion = id break end end
  potion = potion or next(Data.items)
  local pname = Data.items[potion].name
  CoopManager.partner.name = "MOCHX"
  CoopStory.feed = {}
  CoopDuo.handovers = {}

  -- a 1.6 partner: the status line, as before
  duo(false)
  CoopManager.statusMessage = nil
  CoopStory.onPartnerRewards(game, { map = "ELMS_LAB", eid = "x:1", rewards = {
    { kind = "item", id = potion, count = 1 }, { kind = "set_flag", id = "EVENT_DUO_TEST_1" } } })
  T.check(CoopManager.statusMessage == ("You got " .. pname .. " too!"), "1.6: \"You got X too!\" (" .. tostring(CoopManager.statusMessage) .. ")")
  T.check(#CoopDuo.handovers == 0, "...and no box")

  -- the duo: a box of its own
  duo(true)
  sent = {}
  CoopManager.statusMessage = nil
  CoopStory.onPartnerRewards(game, { map = "ELMS_LAB", eid = "x:2", rewards = {
    { kind = "item", id = potion, count = 1 }, { kind = "set_flag", id = "EVENT_DUO_TEST_2" } } })
  T.check(game.save.inventory[potion] == 2, "the gift is in the bag")
  T.check(CoopManager.statusMessage == nil, "no \"You got X too!\" any more")
  T.check(#CoopDuo.handovers == 1, "a box waits to be shown")
  -- not while a page of the scene is still up (until HANDOVER_WAIT)
  CoopStory.feed = { { "ELM: Take care!", "" } }
  CoopStory.tick(0.1, game)
  T.check(game.stack:top() == game.overworld, "the box waits for the scene's last page")
  CoopStory.feed = {}
  game.stack:push({ menu = true })
  CoopStory.tick(0.1, game)
  T.check(#CoopDuo.handovers == 1, "...and for this player to be free")
  game.stack:pop()
  CoopStory.tick(0.1, game)
  local box = game.stack:top()
  T.check(box ~= game.overworld and box.coopGift, "then it opens")
  local shown = box.pages and box.pages[1] and table.concat(box.pages[1], "\n") or ""
  T.check(shown:find("TOBY received", 1, true) and shown:find(pname, 1, true),
          "\"TOBY received " .. pname .. "!\", this player's own name: " .. shown:gsub("\n", " / "))
  T.check(box.auto and box.auto.sound and box.auto.wait, "with the jingle, then A, like give_item's box")
  local got = lastOf("coop_story_got")
  T.check(got and got.eid == "x:2" and got.name == "TOBY" and got.n == 1, "the partner is told it was handed over")
  game.stack:pop()

  -- two things: two boxes, one reply
  sent = {}
  CoopStory.onPartnerRewards(game, { map = "ELMS_LAB", eid = "x:3", rewards = {
    { kind = "item", id = potion, count = 3 }, { kind = "money", amount = 500 },
    { kind = "set_flag", id = "EVENT_DUO_TEST_3" } } })
  T.check(#CoopDuo.handovers == 2, "an item and money: two boxes")
  T.check(CoopDuo.handovers[1].text:find(pname .. " x3", 1, true), "a count shows: " .. CoopDuo.handovers[1].text:gsub("\n", " / "))
  T.check(CoopDuo.handovers[2].text:find("500", 1, true), "money shows its amount: " .. CoopDuo.handovers[2].text:gsub("\n", " / "))
  CoopStory.tick(0.1, game)
  game.stack:pop()
  CoopStory.tick(0.1, game)
  game.stack:pop()
  T.check(count("coop_story_got") == 1 and lastOf("coop_story_got").n == 2, "one reply for the event")

  -- far away: no box (the outcome, as before)
  CoopDuo.handovers = {}
  CoopManager.statusMessage = nil
  CoopStory.onPartnerRewards(game, { map = "GOLDENROD_CITY", eid = "x:4", rewards = {
    { kind = "item", id = potion, count = 1 }, { kind = "set_flag", id = "EVENT_DUO_TEST_4" } } })
  T.check(#CoopDuo.handovers == 0 and CoopManager.statusMessage ~= nil, "not in the scene: the status line, no box")

  -- in Spanish
  I18n.forced = "es"
  CoopDuo.handovers = {}
  CoopDuo.queueGifts(game, { { name = "POTION", count = 1 } }, "x:5")
  T.check(CoopDuo.handovers[1].text == I18n.fitGlyphs("¡TOBY recibió\nPOTION!"), "en español: " .. CoopDuo.handovers[1].text:gsub("\n", " / "))
  I18n.forced = nil
  CoopDuo.handovers = {}

  -- the screen that played it: "TOBY got one too!"
  CoopManager.partner.name = "TOBY"
  CoopManager.statusMessage = nil
  CoopManager.dispatch(nil, { type = "coop_story_got", eid = "x:2", name = "TOBY", n = 1 })
  T.check(CoopManager.statusMessage == "TOBY got one too!", "\"TOBY got one too!\" (" .. tostring(CoopManager.statusMessage) .. ")")
  CoopManager.dispatch(nil, { type = "coop_story_got", name = "TOBY", n = 2 })
  T.check(CoopManager.statusMessage == "TOBY got them too!", "several: \"TOBY got them too!\"")
  I18n.forced = "es"
  CoopManager.dispatch(nil, { type = "coop_story_got", name = "TOBY", n = 1 })
  T.check(CoopManager.statusMessage == I18n.fitGlyphs("¡TOBY también recibió una!"), "en español: " .. tostring(CoopManager.statusMessage))
  I18n.forced = nil
  duo(false)
  CoopManager.statusMessage = nil
  CoopManager.dispatch(nil, { type = "coop_story_got", name = "TOBY", n = 1 })
  T.check(CoopManager.statusMessage == nil, "without the duo the reply is ignored")
  duo(true)

  -- a badge won together
  CoopDuo.handovers = {}
  sent = {}
  CoopDuo.queueBadge(game, "ZEPHYRBADGE")
  CoopStory.tick(0.1, game)
  box = game.stack:top()
  shown = box.pages and box.pages[1] and table.concat(box.pages[1], "\n") or ""
  T.check(shown == "TOBY received\nZEPHYRBADGE.", "the badge, to this player by name: " .. shown:gsub("\n", " / "))
  T.check(lastOf("coop_story_got") and lastOf("coop_story_got").badge == "ZEPHYRBADGE", "...and the partner hears of it")
  game.stack:pop()

  Bag.add = realAdd
  CoopManager.overworldIdle = realIdle
end

-- ---------------------------------------------------------------------
-- the badge on the invited side of a co-op leader battle
-- ---------------------------------------------------------------------
do
  local BattleState = require("src.battle.BattleState")
  local realNew = BattleState.newTrainer
  local CoopBattle = require("src.coop.CoopBattle")
  local realInit, realRules = CoopBattle.initBattle, CoopBattle.useRuleset
  BattleState.newTrainer = function() return {} end
  CoopBattle.initBattle = function() end
  CoopBattle.useRuleset = function() end
  local game = newGame("TOBY", "VIOLET_GYM")
  game.overworld.pushBattle = function(_, b) game.lastBattle = b end
  local Badges = require("src.inventory.Badges")
  local function run(on)
    duo(on)
    CoopDuo.handovers = {}
    CoopManager.statusMessage = nil
    pcall(Badges.set, game.save, { id = "ZEPHYRBADGE" }, false)
    local b = CoopManager.startGuestBattle(game, game.overworld,
      { oppClass = "OPP_FALKNER", partyIndex = 1, mapId = "VIOLET_GYM", localMons = {}, seed = 1 }, {})
    b.onFinish("win")
  end
  run(false)
  T.check(CoopManager.statusMessage == "Earned the ZEPHYRBADGE!" and #CoopDuo.handovers == 0,
          "1.6: the badge on the status line (" .. tostring(CoopManager.statusMessage) .. ")")
  run(true)
  T.check(#CoopDuo.handovers == 1 and CoopDuo.handovers[1].sound == "Get_Badge"
          and CoopDuo.handovers[1].text == "TOBY received\nZEPHYRBADGE.",
          "the duo: a box with the badge's fanfare, to this player by name")
  T.check(Badges.has(game.save, { id = "ZEPHYRBADGE" }), "...and the badge is theirs")
  BattleState.newTrainer = realNew
  CoopBattle.initBattle, CoopBattle.useRuleset = realInit, realRules
  CoopDuo.handovers = {}
end

T.finish("co-op scenes with two leads")
