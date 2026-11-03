-- src/coop/CoopDuo.lua
-- SHARED SCENES WITH TWO LEADS (1.20, capability "story.duo").
--
-- Before 1.20 the partner standing in your scene was its audience: they read
-- the lines in a box that turned by itself every 2.4 seconds, and what the
-- scene handed them came as a status line, "You got POTION too!".  Mochi:
-- "que se vea que uno no es fantasma o la sombra del otro".  With both copies
-- on 1.20 (CoopManager.bothHave(CAP)):
--
--   * THE PARTNER TURNS THEIR OWN PAGES.  The box over their game waits for
--     THEIR A (it never holds up the one playing the scene); one left behind
--     gets the pages they missed folded into one "Skipped N pages", and
--     once the scene is over only its last pages stay.
--   * BOTH CAN REACT.  During a shared scene, SELECT + a direction (or the
--     number pad's 1-4) puts one of four bubbles over your avatar on both
--     screens, and the other screen reads a short line: "TOBY: WOW!".
--   * WHAT THE SCENE GIVES IS HANDED OVER, AS THE CARTRIDGE DOES.  The one
--     playing it reads "MOCHI received POTION!" -- their own name, not "MOCHI
--     & TOBY" -- and the partner gets a box of their own, "TOBY received
--     POTION!" with the item's jingle; the first screen then reads "TOBY got
--     one too!".  A badge won in a co-op big battle is handed over the same
--     way, on each screen to its own player, with the badge's fanfare.
--
-- With a partner from before 1.20 none of this runs: the feed keeps its
-- timer, the gifts their status line.

local CoopDuo = {}

CoopDuo.CAP = "story.duo"

CoopDuo.FEED_MIN = 0.25     -- a page is up this long before A turns it
CoopDuo.FEED_IDLE = 12      -- ...and turns by itself after this long
CoopDuo.FEED_BEHIND = 4     -- pages waiting behind the one on screen, at most
CoopDuo.FEED_AFTER_END = 2  -- ...and once the partner's scene is over
CoopDuo.SCENE_IDLE = 20     -- a partner scene with no line for this long is over
CoopDuo.REACT_GAP = 0.4     -- seconds between two reactions
CoopDuo.HANDOVER_WAIT = 6   -- seconds a gift box waits for the pages before it

-- the four reactions: the emote's bubble (CoopEmotes; an older partner knows
-- these ids), the SELECT + direction that sends it, the line the other reads
CoopDuo.REACTIONS = {
  { id = "exclaim",  dir = "up",    line = "%s: WOW!" },
  { id = "question", dir = "right", line = "%s: HUH?" },
  { id = "happy",    dir = "down",  line = "%s: HA HA!" },
  { id = "sad",      dir = "left",  line = "%s: OH NO..." },
}
local REACT_BY_ID, REACT_BY_DIR = {}, {}
for _, r in ipairs(CoopDuo.REACTIONS) do REACT_BY_ID[r.id], REACT_BY_DIR[r.dir] = r, r end
CoopDuo.REACT_BY_ID = REACT_BY_ID

CoopDuo.partnerScene = nil  -- { map, at }: the partner's scene we are reading
CoopDuo.handovers = {}      -- gift boxes waiting to be shown here
CoopDuo.lastReact = nil

local function manager()
  local ok, CM = pcall(require, "src.coop.CoopManager")
  return ok and CM or nil
end

local function story()
  return package.loaded["src.coop.CoopStory"] or require("src.coop.CoopStory")
end

local function I18n() return require("src.coop.CoopI18n") end

local function clock()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

function CoopDuo.on()
  local CM = manager()
  return CM ~= nil and CM.bothHave ~= nil and CM.bothHave(CoopDuo.CAP) == true
end

function CoopDuo.reset()
  CoopDuo.partnerScene = nil
  CoopDuo.handovers = {}
  CoopDuo.lastReact = nil
end

-- ---------------------------------------------------------------------
-- the handover line: "{PLAYER} received\nTM24."
-- ---------------------------------------------------------------------

-- The cartridge's gift and badge lines start with the player's name and a
-- verb of receiving (`verbosegiveitem`'s "{PLAYER} got", the leaders'
-- "{PLAYER} received\nZEPHYRBADGE.", the battle's "{PLAYER} got ¥.. for
-- winning!").  That page names the one who really gets the thing.
local PLAYER_TOKENS = { "{PLAYER}", "{RAM:wPlayerName}", "<PLAYER>" }
local VERBS = { received = true, got = true, obtained = true,
                ["recibió"] = true, recibio = true, obtuvo = true, ["consiguió"] = true }

function CoopDuo.isHandover(page)
  if type(page) ~= "string" then return false end
  local s = page:gsub("^%s+", "")
  for _, tok in ipairs(PLAYER_TOKENS) do
    if s:sub(1, #tok) == tok then
      local word = s:sub(#tok + 1):match("^ +([^%s]+)")
      return word ~= nil and VERBS[word:lower()] == true
    end
  end
  return false
end

local function pages(text)
  local out = {}
  for p in (text .. "\f"):gmatch("(.-)\f") do out[#out + 1] = p end
  return out
end
CoopDuo.pages = pages

local function hasHandover(list)
  for _, p in ipairs(list) do
    if CoopDuo.isHandover(p) then return true end
  end
  return false
end

-- Fill `text` page by page: `nameFor(page)` is who {PLAYER} is on it.
local function fillPages(substitute, game, list, nameFor, ...)
  local CS = story()
  local out = {}
  for i, p in ipairs(list) do
    CS.renderDuo = nameFor(p)
    local ok, s = pcall(substitute, game, p, ...)
    CS.renderDuo = nil
    if not ok then error(s, 0) end
    out[i] = s
  end
  return table.concat(out, "\f")
end

-- TextBox.substitute, on the screen of the one playing the scene (wrapped in
-- lib/Hooks.lua): its handover pages name this player alone.  nil = no
-- change, the engine's own substitution stands.
function CoopDuo.substitute(substitute, game, text, ...)
  if type(text) ~= "string" or not (text:find("PLAYER", 1, true) or text:find("wPlayerName", 1, true)) then
    return nil
  end
  local CS = package.loaded["src.coop.CoopStory"]
  if not CS or CS.renderDuo ~= nil or not CS.duoName() then return nil end
  if not CoopDuo.on() then return nil end
  local list = pages(text)
  if not hasHandover(list) then return nil end
  local CM = manager()
  local me = CM.getLocalPlayerName(game)
  local duo = CS.duoName()
  return fillPages(substitute, game, list, function(p) return CoopDuo.isHandover(p) and me or duo end, ...)
end

-- The partner's line on this screen: this player first in the duo, and the
-- handover pages naming the one who played them (`speaker`) -- this
-- player's own gift comes in a box of its own (CoopDuo.queueGifts).
function CoopDuo.fillForUs(game, raw, localDuo, speaker)
  if not (CoopDuo.on() and type(speaker) == "string" and speaker ~= "") then return nil end
  local list = pages(raw)
  if not hasHandover(list) then return nil end
  local TextBox = require("src.render.TextBox")
  local ok, out = pcall(fillPages, TextBox.substitute, game, list, function(p)
    return CoopDuo.isHandover(p) and speaker or localDuo
  end)
  return ok and out or nil
end

-- ---------------------------------------------------------------------
-- the partner's pages, turned with this player's A
-- ---------------------------------------------------------------------

local function skippedPage(n)
  local line = I18n().t(string.format("Skipped %d pages", n))
  return { line, "", skipped = n }
end
CoopDuo.skippedPage = skippedPage

-- feed[1] is on screen; past `keep` pages waiting behind it, the oldest of
-- them fold into one "Skipped N pages" page (an earlier fold counts in).
-- Returns how many pages went.
function CoopDuo.fold(feed, keep)
  keep = math.max(1, keep or CoopDuo.FEED_BEHIND)
  local waiting = #feed - 1
  if waiting <= keep then return 0 end
  local cut = waiting - (keep - 1)   -- waiting pages that go into the fold
  local n = 0
  for i = 2, 1 + cut do n = n + (feed[i].skipped or 1) end
  local out = { feed[1], skippedPage(n) }
  for i = 2 + cut, #feed do out[#out + 1] = feed[i] end
  for i = #feed, 1, -1 do feed[i] = nil end
  for i, p in ipairs(out) do feed[i] = p end
  return cut
end

-- the partner's line arrived (CoopStory.onPartnerText): their scene is on
function CoopDuo.onPartnerLine(map)
  CoopDuo.partnerScene = { map = map, at = clock() }
  CoopDuo.fold(story().feed, CoopDuo.FEED_BEHIND)
end

-- coop_story_end: their scene is over; a reader still behind it keeps only
-- its last pages
function CoopDuo.onSceneEnd(msg)
  CoopDuo.partnerScene = nil
  CoopDuo.fold(story().feed, CoopDuo.FEED_AFTER_END)
end

-- the one playing the scene says it is over (CoopStory.finish)
function CoopDuo.sendSceneEnd(map)
  if not CoopDuo.on() then return end
  local CM = manager()
  if CM and CM.net and CM.isConnected and CM.isConnected() then
    CM.net:send({ type = "coop_story_end", map = map })
  end
end

local function feedVisible(game)
  local CS = story()
  if not CS.feed[1] then return false end
  local ow = game and game.overworld
  return ow ~= nil and game.stack and game.stack.top and game.stack:top() == ow
end

-- A on the page: the next one (true when it turned)
function CoopDuo.advance(game)
  local CS = story()
  if not CS.feed[1] or (CS.feedTimer or 0) < CoopDuo.FEED_MIN then return false end
  table.remove(CS.feed, 1)
  CS.feedTimer = 0
  if game and game.data then pcall(function() require("src.core.Sound").play(game.data, "Press_AB") end) end
  return true
end

-- CoopStory.tick, with the duo on: the page on screen ages while it is in
-- view, and only an untouched one turns by itself
function CoopDuo.tickFeed(dt, game)
  local CS = story()
  if not CS.feed[1] then CS.feedTimer = 0 return end
  if game and game.stack and not feedVisible(game) then return end
  CS.feedTimer = (CS.feedTimer or 0) + (dt or 0)
  if CS.feedTimer >= CoopDuo.FEED_IDLE then
    CS.feedTimer = 0
    table.remove(CS.feed, 1)
  end
end

-- ---------------------------------------------------------------------
-- reactions
-- ---------------------------------------------------------------------

-- Is a shared scene on screen here?  Ours with the partner standing in it,
-- or theirs that we are reading.
function CoopDuo.sceneActive(game)
  if not CoopDuo.on() then return false end
  local CS = story()
  if CS.duoName() then return true end
  local ps = CoopDuo.partnerScene
  if ps and clock() - (ps.at or 0) > CoopDuo.SCENE_IDLE then
    CoopDuo.partnerScene, ps = nil, nil
  end
  if CS.feed[1] then return true end
  if not ps then return false end
  local CM = manager()
  local ow = game and game.overworld
  return CM ~= nil and ow ~= nil and ow.map ~= nil and CM.mapsMatch(ps.map, ow.map.id)
end

function CoopDuo.react(game, id)
  local r = REACT_BY_ID[id]
  if not r or not CoopDuo.on() then return false end
  local t = clock()
  if CoopDuo.lastReact and t - CoopDuo.lastReact < CoopDuo.REACT_GAP then return false end
  CoopDuo.lastReact = t
  local CM = manager()
  CM.localEmote = id
  CM.localEmoteTimer = 2.5
  if CM.net and CM.isConnected and CM.isConnected() then
    -- the plain emote message, so the bubble is the one every copy draws;
    -- `react` adds the line on a 1.20 partner's screen
    CM.net:send({ type = "coop_emote", emote = id, react = true })
  end
  return true
end

-- the partner reacted: the bubble is up already (coop_emote); the line
function CoopDuo.onReaction(msg)
  if not (type(msg) == "table" and msg.react and CoopDuo.on()) then return end
  local r = REACT_BY_ID[msg.emote]
  local CM = manager()
  if not (r and CM and CM.showStatus) then return end
  local name = I18n().truncate(string.upper(CM.partner.name or "PARTNER"), 8)
  CM.showStatus(string.format(r.line, name), 2)
end

-- ---------------------------------------------------------------------
-- the buttons: A turns the partner's page, SELECT + a direction reacts
-- ---------------------------------------------------------------------

local DIRS = { "up", "right", "down", "left" }

-- take every queued edge of `btn` (and of the buttons that stand in for it)
local function take(input, btn)
  local q = input.pressQueue
  local names = { [btn] = true }
  for _, from in ipairs(input.buttonAlias and input.buttonAlias[btn] or {}) do names[from] = true end
  local found = false
  for i = #q, 1, -1 do
    if names[q[i]] then
      table.remove(q, i)
      found = true
    end
  end
  return found
end

function CoopDuo.selectHeld(game)
  local input = game and game.input
  if not (input and input.isDown) then return false end
  local ok, down = pcall(input.isDown, input, "select")
  return ok and down == true
end

-- the mod's `input.step` wrapper (main.lua): before the engine reads this
-- step's edges
function CoopDuo.onInputStep(game)
  local input = game and game.input
  if not (input and type(input.pressQueue) == "table" and game.stack and game.stack.top) then return end
  if not CoopDuo.on() then return end
  local top = game.stack:top()
  local ow = game.overworld
  local reading = ow ~= nil and top == ow
  local inScene = CoopDuo.sceneActive(game) and (reading or (top and top.isTextBox == true))
  if inScene then
    local held = CoopDuo.selectHeld(game)
    -- SELECT is the registered item in the field: not while reacting
    if take(input, "select") then held = true end
    if held then
      for _, dir in ipairs(DIRS) do
        if take(input, dir) then CoopDuo.react(game, REACT_BY_DIR[dir].id) end
        -- and a held direction does not walk the reader off
        if reading and input.state then input.state[dir] = false end
      end
    end
  end
  -- A turns the partner's page (only while it is in view, over the field)
  if reading and story().feed[1] and take(input, "a") then CoopDuo.advance(game) end
end

-- the number pad's 1-4 during a scene (lib/Hooks.lua Game.keypressed)
function CoopDuo.onKey(game, key)
  local n = tonumber(tostring(key or ""):match("^kp(%d)$"))
  local r = n and CoopDuo.REACTIONS[n]
  if not r or not CoopDuo.sceneActive(game) then return false end
  local top = game.stack and game.stack.top and game.stack:top()
  if not (top == game.overworld or (top and top.isTextBox)) then return false end
  CoopDuo.react(game, r.id)
  return true
end

-- ---------------------------------------------------------------------
-- gifts: handed over in a box, as the cartridge does
-- ---------------------------------------------------------------------

local function localName(game)
  local CM = manager()
  return (CM and CM.getLocalPlayerName(game)) or "PLAYER"
end

-- one box per thing the partner's scene gave this player.  `gifts`:
-- { name, count, key } items, { money } amounts.  `eid` names the event for
-- the reply.
function CoopDuo.queueGifts(game, gifts, eid)
  if type(gifts) ~= "table" or #gifts == 0 then return 0 end
  local me = localName(game)
  local sign = "¥"
  pcall(function() sign = require("src.core.GameVersion").moneySign() or sign end)
  for i, g in ipairs(gifts) do
    local what
    if g.money then
      what = sign .. tostring(g.money)
    elseif (tonumber(g.count) or 1) > 1 then
      what = string.format("%s x%d", tostring(g.name), tonumber(g.count))
    else
      what = tostring(g.name)
    end
    CoopDuo.handovers[#CoopDuo.handovers + 1] = {
      text = I18n().t(string.format("%s received\n%s!", me, what)),
      sound = g.key and "Get_Key_Item" or "Get_Item1",
      at = clock(),
      -- the first box answers for the whole event
      reply = i == 1 and { type = "coop_story_got", eid = eid, n = #gifts, what = tostring(g.name or what) } or nil,
    }
  end
  return #gifts
end

-- a badge won together (CoopInvites' awardLeaderBadge on the invited side)
function CoopDuo.queueBadge(game, badge)
  if type(badge) ~= "string" then return false end
  CoopDuo.handovers[#CoopDuo.handovers + 1] = {
    text = I18n().t(string.format("%s received\n%s.", localName(game), badge)),
    sound = "Get_Badge",
    at = clock(),
    reply = { type = "coop_story_got", badge = badge, n = 1, what = badge },
  }
  return true
end

-- the box goes up when this player is free (not mid-script, not mid-step
-- into a menu), after the partner's pages on screen -- or past
-- HANDOVER_WAIT, over them
function CoopDuo.tick(dt, game)
  local h = CoopDuo.handovers[1]
  if not (h and game and game.stack) then return end
  local CM = manager()
  if not (CM and CM.overworldIdle and CM.overworldIdle(game, game.overworld)) then return end
  if story().feed[1] and clock() - (h.at or 0) < CoopDuo.HANDOVER_WAIT then return end
  table.remove(CoopDuo.handovers, 1)
  CoopDuo.show(game, h)
end

function CoopDuo.show(game, h)
  local TextBox = require("src.render.TextBox")
  local Sound = require("src.core.Sound")
  local box = TextBox.new(game, h.text, nil, {
    auto = { sound = function() return Sound.play(game.data, h.sound) end, wait = true },
  })
  box.coopGift = true
  game.stack:push(box)
  local CM = manager()
  if h.reply and CM and CM.net and CM.isConnected and CM.isConnected() then
    h.reply.name = localName(game)
    CM.net:send(h.reply)
  end
  return box
end

-- the partner got theirs: "TOBY got one too!"
function CoopDuo.onGot(msg)
  if type(msg) ~= "table" or not CoopDuo.on() then return end
  local CM = manager()
  if not (CM and CM.showStatus) then return end
  local name = type(msg.name) == "string" and msg.name ~= "" and msg.name or CM.partner.name or "PARTNER"
  name = I18n().truncate(string.upper(name), 8)
  local fmt = (tonumber(msg.n) or 1) > 1 and "%s got them too!" or "%s got one too!"
  CM.showStatus(string.format(fmt, name), 3)
end

-- ---------------------------------------------------------------------
-- drawing (src/coop/CoopHud.lua)
-- ---------------------------------------------------------------------

local function drawTab(word, rightX, y)
  local MicroFont = require("src.render.MicroFont")
  local w = MicroFont.width(word) + 5
  local x = rightX - w
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x, y, w, 8)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, 7)
  MicroFont.draw(word, x + 3, y + 1)
  love.graphics.setColor(1, 1, 1, 1)
end

-- the four bubbles in a cross, while SELECT is held in a scene
local function drawCross(game)
  local CoopEmotes = require("src.coop.CoopEmotes")
  local cx, cy = 136, 70
  local at = { up = { 0, -18 }, right = { 18, 0 }, down = { 0, 18 }, left = { -18, 0 } }
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.rectangle("fill", cx - 30, cy - 46, 60, 58)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", cx - 29.5, cy - 45.5, 59, 57)
  for _, r in ipairs(CoopDuo.REACTIONS) do
    local o = at[r.dir]
    -- CoopEmotes.draw hangs the bubble 24 px over the feet it is given
    CoopEmotes.draw(game, r.id, cx + o[1], cy + o[2] + 8, 1)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- over the partner's page: the arrow that says A turns it, the hint
function CoopDuo.drawFeedExtras(game)
  if not CoopDuo.on() then return end
  if math.floor(clock() * 2) % 2 == 0 then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.polygon("fill", 144, 132, 152, 132, 148, 136)
  end
  drawTab(I18n().t("SELECT: REACT"), 152, 94)
  if CoopDuo.selectHeld(game) then drawCross(game) end
  love.graphics.setColor(1, 1, 1, 1)
end

-- over our own scene's dialogue box, with the partner in it
function CoopDuo.drawSceneExtras(game)
  if not CoopDuo.on() then return end
  local CS = story()
  if not CS.duoName() then return end
  drawTab(I18n().t("SELECT: REACT"), 152, 94)
  if CoopDuo.selectHeld(game) then drawCross(game) end
  love.graphics.setColor(1, 1, 1, 1)
end

return CoopDuo
