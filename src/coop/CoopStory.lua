-- src/coop/CoopStory.lua
-- Shared story for co-op: an event one player triggers counts for the
-- partner too.  Standing on the same map, they live it with you (names,
-- text, the warp); anywhere else, they just get its outcome.
--
--   * Names.  While such a script runs, {PLAYER} reads "TOBY & MOCHX" in its
--     text boxes (TextBox soft-wraps the longer line), on both screens.
--   * Text.  Every line the script shows is sent to the partner, who reads it
--     in a box over their own game -- without being frozen -- so both follow
--     Elm, the rival, Mr. POKEMON at the same time.
--   * Rewards.  When the script ends, what it handed over -- items, money,
--     coins -- and EVERYTHING IT CHANGED IN THE SAVE'S STORY STATE (every
--     event and engine flag, every map scene, the armed POKeGEAR call) is
--     applied to the partner as well, so a gift, an item ball or a cutscene
--     is not left waiting for them to do it all again.
--
--     The state is compared before and after rather than collected command
--     by command, because a command list is never complete: Falkner's
--     `specialphonecall` (Elm's call that puts his aide in the POKEMON
--     CENTER) was not on it, so the partner got the badge, never got the
--     call, never got the egg -- and Route 32's guard, who turns away anyone
--     who has not met the aide, walled them inside Violet City for good.
--     `disappear`, `toggleevent` and the specials that write flags were
--     missing the same way.
--
-- A script that gives or takes a POKEMON (the starter, the Odd Egg, an
-- in-game trade), lets you catch one (Sudowoodo, the Red GYARADOS, the
-- legendaries) or sells you something is PERSONAL: the partner still reads
-- it, but nothing is copied, or its flags would mark the partner's own
-- choice as already made -- or hand them for free what you paid for.
--
-- A partner who is not linked at that moment (the link dropped, their game
-- was closed) is owed the event all the same: it waits in the save
-- (save.coopStoryOutbox) and goes out the next time the two link up.
--
-- Scripts the partner's copy APPLIES never run through here, so nothing
-- echoes back.

local CoopStory = {}

CoopStory.current = nil   -- the story record of the script running right now
CoopStory.feed = {}       -- partner lines waiting to be shown here
CoopStory.FEED_PAGE = 2.4 -- seconds a page of partner text stays up
CoopStory.inbox = {}      -- partner events that arrived before our save was up
CoopStory.deferred = {}   -- partner events that arrived while a script of ours ran
CoopStory.held = nil      -- a big battle's scene the partner is holding for us
CoopStory.HOLD_MAX = 900  -- seconds a hold is honoured without word from them
CoopStory.WAIT_MAX = 300  -- seconds a scene waits for the partner to arrive
CoopStory.ARRIVE_SETTLE = 1.5 -- the partner has been on the map this long

local function manager()
  local ok, CM = pcall(require, "src.coop.CoopManager")
  return ok and CM or nil
end

-- rows that make a script one player's own business: a Pokemon handed over
-- or taken, and the Bug-Catching Contest (entering it holds YOUR party and
-- arms YOUR timer -- copying its flags would sign the partner up blind)
-- `load_wild`: a scripted wild battle (each player catches their own);
-- `apricorn` / `item_var`: Kurt's balls are made from YOUR apricorns
local PERSONAL = { "give_poke", "egg", "trade", "shuckle", "party_mon", "aggron",
                   "orphan", "contest", "load_wild", "apricorn", "item_var" }

local function isPersonal(name)
  for _, frag in ipairs(PERSONAL) do
    if name:find(frag, 1, true) then return true end
  end
  return false
end

local function partnerHere(ow)
  local CM = manager()
  if not (CM and CM.isConnected and CM.isConnected() and CM.storySync) then return false end
  local map = ow and ow.map and ow.map.id
  return map ~= nil and CM.mapsMatch(CM.partner.map, map)
end

-- the outbox holds at most this many events; the oldest go first
CoopStory.OUTBOX_MAX = 300

-- Is there a partner this event is owed to?  Linked now, or -- for a save
-- that has played with someone (save.coopPartner) -- linked again later.
local function sharing(save)
  local CM = manager()
  if not (CM and CM.storySync) then return false end
  if CM.isConnected and CM.isConnected() then return true end
  return type(save) == "table" and type(save.coopPartner) == "string"
end

-- save state a story script may write, snapshotted at its start
local function copyTable(t)
  local out = {}
  for k, v in pairs(type(t) == "table" and t or {}) do out[k] = v end
  return out
end

-- flags that describe the player rather than the story, and Gen 2's
-- EVENT_TEMPORARY_UNTIL_MAP_RELOAD_1..8 (EVENT_G2_0000..0007): bits a scene
-- keeps until the map loads again, meaningless on the other game
local NOT_SHARED_FLAGS = { ENGINE_FLASH = true, ENGINE_POKEMON_MODE = true }
for i = 0, 7 do NOT_SHARED_FLAGS[string.format("EVENT_G2_%04d", i)] = true end

local function snapshot(save)
  return { flags = copyTable(save and save.flags), scenes = copyTable(save and save.g2Scenes),
           call = save and save.g2SpecialCall,
           -- `variablesprite`: who stands where in the story (the Rocket
           -- disguises, the Lake of Rage, the Radio Tower director)
           sprites = copyTable(save and save.gen2VarSprites),
           -- the script WRAM mirror (Underground switches, event variables)
           wram = copyTable(save and save.g2Wram),
           rival = save and save.player and save.player.rival,
           roam = save and save.g2RoamReleased == true }
end

-- what the script changed, as rewards the partner's copy can apply
local function stateChanges(save, before)
  local out = {}
  if not (save and before) then return out end
  local keys = {}
  for k in pairs(save.flags or {}) do keys[k] = true end
  for k in pairs(before.flags) do keys[k] = true end
  for k in pairs(keys) do
    local now = (save.flags or {})[k] == true
    local was = before.flags[k] == true
    if now ~= was and not NOT_SHARED_FLAGS[k] then
      out[#out + 1] = { kind = now and "set_flag" or "clear_flag", id = k }
    end
  end
  for k, v in pairs(save.g2Scenes or {}) do
    if before.scenes[k] ~= v then out[#out + 1] = { kind = "scene_key", map = k, scene = v } end
  end
  if save.g2SpecialCall ~= before.call and save.g2SpecialCall ~= nil then
    out[#out + 1] = { kind = "special_call", id = save.g2SpecialCall }
  end
  -- the table keys may be numbers, so they travel as values
  for k, v in pairs(save.gen2VarSprites or {}) do
    if before.sprites and before.sprites[k] ~= v then
      out[#out + 1] = { kind = "var_sprite", slot = k, sprite = v }
    end
  end
  for k, v in pairs(save.g2Wram or {}) do
    if before.wram and before.wram[k] ~= v then
      out[#out + 1] = { kind = "wram", addr = k, value = v }
    end
  end
  -- the officer's scene in ELM's lab names the thief once, for both: the
  -- partner gets the scene's flags, so they would never be asked
  local rival = save.player and save.player.rival
  if type(rival) == "string" and rival ~= "" and rival ~= before.rival then
    out[#out + 1] = { kind = "rival_name", name = rival }
  end
  -- the Burned Tower: the three beasts run off on both games
  if save.g2RoamReleased == true and not before.roam then
    out[#out + 1] = { kind = "roam_release" }
  end
  return out
end
CoopStory.stateChanges = stateChanges
CoopStory.snapshot = snapshot

local function shortName(n)
  n = tostring(n or "")
  if #n > 7 then n = n:sub(1, 7) end
  return n
end

-- The trainer an event leads to, when it is one worth deciding about before
-- the talking starts (CoopManager.isBigBattleClass): scanned off the script
-- rows, `loadtrainer` (Gen 2) or a trainer `start_battle`.
function CoopStory.findBigBattle(script, save)
  local CM = manager()
  if not (CM and CM.isBigBattleClass and type(script) == "table") then return nil end
  for _, row in ipairs(script) do
    if type(row) == "table" then
      local class, party
      if row[1] == "g2_load_trainer" then
        class, party = row[2], row[3]
      elseif row[1] == "start_battle" and row[2] == "trainer" then
        class, party = row[3], row[4]
      end
      if type(class) == "string" and CM.isBigBattleClass(class, save) then
        return class, party
      end
    end
  end
  return nil
end

-- called by ScriptRunner:run.  Every story script is recorded while there
-- is a partner to owe it to; only one with the partner standing here
-- (`here`) is lived together -- the names, the lines, the warp, the
-- CO-OP/SOLO question.
function CoopStory.begin(ctx, script)
  CoopStory.current = nil
  if not ctx or ctx.coopRemote or ctx.phoneCaller then return end
  -- a map callback only re-derives this map from the save as it loads (who
  -- stands where, which scene is up); sent across it would overwrite the
  -- partner's own -- the Bug Contest gate's scene in the middle of theirs
  if ctx.mapCallback then return end
  if not sharing(ctx.save) then return end
  local ow = ctx.overworld
  local here = partnerHere(ow)
  local CM = manager()
  local class, party = CoopStory.findBigBattle(script, ctx.save)
  -- THE PARTNER IS ALREADY LIVING THIS SCENE FOR BOTH OF YOU.  A scene that
  -- starts as the map loads (the rival in the BURNED TOWER) fires on each
  -- game as each player walks in; theirs is waiting for you, so this copy
  -- does not play its own -- it stands by for their CO-OP invite, and their
  -- scene's flags arrive when it ends (onPartnerRewards).
  if class and CoopStory.heldHere(ow, class) then
    ctx.coopSkipScript = true
    return
  end
  ctx.coopStory = {
    map = ow and ow.map and ow.map.id,
    here = here,
    rewards = {},
    personal = false,
    duo = shortName(CM.getLocalPlayerName(ctx.game)) .. " & " .. shortName(CM.partner.name or "PARTNER"),
    lines = 0,
    before = snapshot(ctx.save),
  }
  CoopStory.current = ctx.coopStory
  -- A BIG BATTLE WITH THE PARTNER ELSEWHERE: wait for them, or go alone.
  -- Reported from play: the BURNED TOWER's rival walks up the moment you
  -- step in, so the one who got there first always fought him solo.
  if not here and class then
    here = CoopStory.waitForPartner(ctx, class, party)
    ctx.coopStory.here = here
  end
  if not here then return end
  -- a gym leader / League / rival scene: CO-OP or SOLO is asked now, before
  -- the first line, so the partner can read it all with you
  if class and CM.offerBigBattle then
    CM.offerBigBattle(ctx, class, party)
  end
end

-- "TOBY & MOCHX" while a shared, non-personal script is on screen
function CoopStory.duoName()
  local st = CoopStory.current
  if st and st.here and not st.personal then return st.duo end
  return nil
end

-- called by ScriptRunner:exec after every row that ran
function CoopStory.observe(ctx, name, row)
  local st = ctx and ctx.coopStory
  if not st or type(name) ~= "string" then return end
  if isPersonal(name) then
    st.personal = true
    return
  end
  local add = function(r) st.rewards[#st.rewards + 1] = r end
  if name == "start_battle" and row[2] == "wild" then
    -- a scripted wild Pokemon: the partner gets to meet their own
    st.personal = true
  elseif name == "give_item" or name == "g2_giveitem" then
    -- a refused gift (bag full) set lastCheck false and is not shared
    if ctx.lastCheck ~= false and row[2] then
      add({ kind = "item", id = row[2], count = tonumber(row[3]) or 1 })
    end
  elseif name == "take_item" then
    -- what the scene took (the MYSTERY EGG back to ELM, the SECRETPOTION to
    -- JASMINE, the MACHINE PART) leaves the partner's bag too, if it is there
    if ctx.lastCheck ~= false and row[2] then
      add({ kind = "take_item", id = row[2], count = tonumber(row[3]) or 1 })
    end
  elseif name == "give_money" then
    local n = tonumber(row[2])
    if n and n > 0 then add({ kind = "money", amount = n }) end
    -- money paid out is a purchase: yours, not the partner's
    if n and n < 0 then st.personal = true end
  elseif name == "g2_give_coins" then
    local n = tonumber(row[2])
    if n and n > 0 then add({ kind = "coins", amount = n }) end
    if n and n < 0 then st.personal = true end
  elseif name == "g2_warp" or name == "warp" then
    -- the scene takes the player somewhere (Lance walking you into the HALL
    -- OF FAME): the partner standing in it comes along.  Only the last warp
    -- of a script matters, and it is applied after everything else.
    if type(row[2]) == "string" and row[2] ~= "" then
      st.warp = { kind = "warp", map = row[2], x = tonumber(row[3]), y = tonumber(row[4]), facing = row[5] }
    end
  end
end

-- called by Commands.show_text with the line about to be shown
function CoopStory.onText(ctx, text)
  local st = ctx and ctx.coopStory
  if not st or not st.here or type(text) ~= "string" or text == "" then return end
  local CM = manager()
  if not (CM and CM.net and CM.connected) then return end
  local okTB, TextBox = pcall(require, "src.render.TextBox")
  local shown = okTB and TextBox.substitute(ctx.game, text) or text
  st.lines = st.lines + 1
  CM.net:send({ type = "coop_story_text", map = st.map, text = shown,
                speaker = CM.getLocalPlayerName(ctx.game) })
end

-- EVERY EVENT HAS ITS OWN NAME: this save's co-op id and a counter kept in
-- the save.  The partner remembers the names it has applied (in its own
-- save), so an event that reaches it twice -- sent live and again from the
-- outbox of a game that quit before saving, or resent after a dropped link
-- -- is only lived once.  A partner that did not save either lost what it
-- applied, and takes it again: the two files stay in step.
function CoopStory.stamp(save)
  if type(save) ~= "table" then return nil end
  local CM = manager()
  local id = CM and CM.coopId and CM.coopId(save) or "?"
  save.coopEventN = (tonumber(save.coopEventN) or 0) + 1
  return id .. ":" .. save.coopEventN
end

CoopStory.SEEN_MAX = 1500

local function seen(save, eid)
  return type(eid) == "string" and type(save.coopEventsSeen) == "table"
         and save.coopEventsSeen[eid] == true
end

local function markSeen(save, eid)
  if type(eid) ~= "string" then return end
  local set = type(save.coopEventsSeen) == "table" and save.coopEventsSeen or {}
  local order = type(save.coopEventsOrder) == "table" and save.coopEventsOrder or {}
  save.coopEventsSeen, save.coopEventsOrder = set, order
  if set[eid] then return end
  set[eid] = true
  order[#order + 1] = eid
  while #order > CoopStory.SEEN_MAX do
    set[table.remove(order, 1)] = nil
  end
end
CoopStory.seen, CoopStory.markSeen = seen, markSeen

-- an event the partner could not be told about: kept in the save until
-- the two link again
function CoopStory.queue(save, rewards, eid)
  if type(save) ~= "table" or type(rewards) ~= "table" or #rewards == 0 then return end
  local box = save.coopStoryOutbox
  if type(box) ~= "table" then box = {} save.coopStoryOutbox = box end
  box[#box + 1] = { eid = eid or CoopStory.stamp(save), rewards = rewards }
  while #box > CoopStory.OUTBOX_MAX do table.remove(box, 1) end
end

-- called by ScriptRunner:run when the script ends
local function releaseHold(ctx)
  if not (ctx and ctx.coopHoldSent) then return end
  ctx.coopHoldSent = nil
  local CM = manager()
  if CM and CM.net and CM.isConnected and CM.isConnected() then
    CM.net:send({ type = "coop_story_release", map = ctx.coopHoldSent_map })
  end
end

function CoopStory.finish(ctx)
  local st = ctx and ctx.coopStory
  if CoopStory.current == st then CoopStory.current = nil end
  -- the scene's flags go first (below), so the partner's own copy of the
  -- scene is already closed by the time the hold on it lifts
  local function done() releaseHold(ctx) end
  if not st or st.personal then return done() end
  -- flags, scenes and the armed call first, the warp after everything
  for _, r in ipairs(stateChanges(ctx.save, st.before)) do st.rewards[#st.rewards + 1] = r end
  -- the scene walks the partner along only if they were in it
  if st.warp and st.here then st.rewards[#st.rewards + 1] = st.warp end
  if #st.rewards == 0 then return done() end
  local CM = manager()
  local eid = CoopStory.stamp(ctx.save)
  if not (CM and CM.net and CM.isConnected and CM.isConnected()) then
    CoopStory.queue(ctx.save, st.rewards, eid)
    return done()
  end
  CM.net:send({ type = "coop_story_rewards", map = st.map, rewards = st.rewards, eid = eid,
                speaker = CM.getLocalPlayerName(ctx.game) })
  done()
end

-- ---------------------------------------------------------------------
-- waiting for the partner at a big battle
-- ---------------------------------------------------------------------

local function clock()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

function CoopStory.onPartnerHold(msg)
  if type(msg) ~= "table" or type(msg.map) ~= "string" or type(msg.class) ~= "string" then return end
  CoopStory.held = { map = msg.map, class = msg.class, at = clock() }
end

function CoopStory.onPartnerRelease(msg)
  CoopStory.held = nil
end

function CoopStory.heldHere(ow, class)
  local h = CoopStory.held
  if not h then return false end
  local CM = manager()
  if not (CM and CM.isConnected and CM.isConnected()) or clock() - (h.at or 0) > CoopStory.HOLD_MAX then
    CoopStory.held = nil
    return false
  end
  local map = ow and ow.map and ow.map.id
  return map ~= nil and CM.mapsMatch(h.map, map) and h.class == class
end

local Font
local WaitHere = {}
WaitHere.__index = WaitHere
WaitHere.isOpaque = false

function WaitHere:finish(arrived)
  if self.done then return end
  self.done = true
  self.arrived = arrived and true or false
  local stack = self.game and self.game.stack
  if stack and stack.states then
    for i = #stack.states, 1, -1 do
      if stack.states[i] == self then
        if i == #stack.states then stack:pop() else table.remove(stack.states, i) end
        break
      end
    end
  end
  if self.runner and self.runner.resume then self.runner:resume() end
end

function WaitHere:update(dt)
  dt = dt or 0.016
  self.timer = self.timer + dt
  local CM = manager()
  if not (CM and CM.isConnected and CM.isConnected()) then return self:finish(false) end
  -- they are on the map, and have been for a moment: their own copy of the
  -- scene has had its frame to stand down (heldHere) before the invite
  if partnerHere(self.ow) then
    self.hereFor = self.hereFor + dt
    if self.hereFor >= CoopStory.ARRIVE_SETTLE then return self:finish(true) end
  else
    self.hereFor = 0
  end
  if self.timer >= self.timeout then return self:finish(false) end
  local input = self.game and self.game.input
  if input and input.wasPressed and input:wasPressed("b") and self.timer >= 0.5 then
    return self:finish(false)
  end
end

function WaitHere:draw()
  Font = Font or require("src.coop.CoopI18n").font()
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 0, 20, 5)
  love.graphics.setColor(0, 0, 0, 1)
  local left = math.max(0, math.ceil(self.timeout - self.timer))
  Font.draw(require("src.coop.CoopI18n").fit("WAITING " .. self.name, 15), 8, 8)
  Font.draw(string.format("%3d", left), 128, 8)
  Font.draw("TO COME HERE" .. string.rep(".", math.floor(self.timer * 2) % 4), 8, 16)
  Font.draw("B: BATTLE SOLO", 8, 24)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Inside the script's coroutine: asks WAIT or SOLO, and with WAIT holds the
-- scene -- and tells the partner's game to hold its own copy -- until they
-- walk onto this map.  true once they are here.
function CoopStory.waitForPartner(ctx, class, party)
  local CM = manager()
  local game, runner, ow = ctx.game, ctx.runner, ctx.overworld
  if not (CM and game and game.stack and runner and runner.yield and ow and ow.map) then return false end
  if not (CM.isConnected and CM.isConnected() and CM.net) then return false end
  if (CM.partner.healthy or 0) <= 0 then return false end
  local pname = string.upper(CM.partner.name or "PARTNER")
  if #pname > 8 then pname = pname:sub(1, 8) end
  local name = CM.trainerDisplayName and CM.trainerDisplayName(game, class, party) or "TRAINER"
  local choice = "solo"
  game.stack:push(require("src.coop.CoopI18n").menu().new(game, {
    { label = "WAIT " .. pname, onSelect = function() choice = "wait" runner:resume() end },
    { label = "SOLO", onSelect = function() choice = "solo" runner:resume() end },
  }, { tx = 3, ty = 4, tw = 14, header = ("VS " .. name):sub(1, 12), cancelable = true,
       onCancel = function() choice = "solo" runner:resume() end }))
  runner:yield()
  if choice ~= "wait" or not CM.isConnected() then return false end
  CM.net:send({ type = "coop_story_hold", map = ow.map.id, class = class })
  ctx.coopHoldSent, ctx.coopHoldSent_map = true, ow.map.id
  local w = setmetatable({ game = game, runner = runner, ow = ow, name = pname,
                           timer = 0, hereFor = 0, timeout = CoopStory.WAIT_MAX }, WaitHere)
  game.stack:push(w)
  runner:yield()
  return w.arrived == true
end
CoopStory.WaitHere = WaitHere

-- Sends what the partner missed while the two were apart, one event per
-- message so each is judged on its own on their side.  Called once the
-- handshake completes; the partner must be the one this save plays with.
function CoopStory.flushOutbox(game)
  local save = game and game.save
  local box = save and save.coopStoryOutbox
  if type(box) ~= "table" or #box == 0 then return 0 end
  local CM = manager()
  if not (CM and CM.storySync and CM.net and CM.isConnected and CM.isConnected()) then return 0 end
  local partner = CM.partner and CM.partner.name
  if save.coopPartner and partner and partner ~= save.coopPartner then return 0 end
  local pid = CM.partner and CM.partner.id
  if save.coopPartnerId and pid and pid ~= save.coopPartnerId then return 0 end
  local speaker = CM.getLocalPlayerName(game)
  for _, entry in ipairs(box) do
    -- saves from before 1.5 kept the bare reward list
    local rewards = entry.rewards or entry
    CM.net:send({ type = "coop_story_rewards", backlog = true, rewards = rewards,
                  eid = entry.eid, speaker = speaker })
  end
  local n = #box
  save.coopStoryOutbox = nil
  require("src.coop.CoopLog").info("STORY", "sent " .. n .. " event(s) the partner missed")
  return n
end

-- ---------------------------------------------------------------------
-- the partner's side
-- ---------------------------------------------------------------------

local function sameMap(game, map)
  local CM = manager()
  local ow = game and game.overworld
  return CM and ow and ow.map and CM.mapsMatch(ow.map.id, map)
end

function CoopStory.onPartnerText(game, msg)
  local CM = manager()
  if not (CM and CM.storySync) then return end
  if not sameMap(game, msg.map) or type(msg.text) ~= "string" then return end
  local okTB, TextBox = pcall(require, "src.render.TextBox")
  local lines = {}
  if okTB then
    local okP, pages = pcall(TextBox.paginate, msg.text, 18)
    if okP and type(pages) == "table" then
      for _, page in ipairs(pages) do
        for _, line in ipairs(page) do lines[#lines + 1] = line end
      end
    end
  end
  if #lines == 0 then
    for line in (msg.text .. "\n"):gmatch("(.-)[\n\v\f]") do lines[#lines + 1] = line end
  end
  for i = 1, #lines, 2 do
    table.insert(CoopStory.feed, { lines[i], lines[i + 1] or "" })
  end
  -- never let a long scene pile up behind the player
  while #CoopStory.feed > 12 do table.remove(CoopStory.feed, 1) end
end

local function itemName(game, id)
  local def = game.data and game.data.items and game.data.items[id]
  return (def and def.name) or tostring(id)
end

-- Did the receiver already live this event?  An event that changed story
-- state and changes nothing here was done on this side too (both of you
-- talked to the same NPC, or played it apart before linking up): its items
-- and money are not handed out a second time.
local function alreadyLived(save, rewards)
  local state, differs = false, false
  local flags = save.flags or {}
  for _, r in ipairs(rewards) do
    if r.kind == "set_flag" then
      state = true
      if flags[r.id] ~= true then differs = true end
    elseif r.kind == "clear_flag" then
      state = true
      if flags[r.id] == true then differs = true end
    elseif r.kind == "scene_key" then
      state = true
      if (save.g2Scenes or {})[r.map] ~= r.scene then differs = true end
    end
  end
  return state and not differs
end
CoopStory.alreadyLived = alreadyLived

local MONEY_KINDS = { item = true, money = true, coins = true, take_item = true }

function CoopStory.onPartnerRewards(game, msg)
  local CM = manager()
  if not (CM and CM.storySync) then return end
  if type(msg.rewards) ~= "table" then return end
  if not (game and game.save and game.overworld) then
    -- still on the title screen / loading: applied once the save is up
    if #CoopStory.inbox < CoopStory.OUTBOX_MAX then CoopStory.inbox[#CoopStory.inbox + 1] = msg end
    return
  end
  local save = game.save
  if seen(save, msg.eid) then
    require("src.coop.CoopLog").info("STORY", "event " .. msg.eid .. " was already lived here")
    return
  end
  -- NOT IN THE MIDDLE OF OUR OWN SCRIPT.  Both talking to the same NPC, or
  -- the leader's after-battle script running on both games: the partner's
  -- flags and items landing between our script's check and its GIVEITEM
  -- handed the item out twice.  It waits for the script to end; by then
  -- the flags match and its goods are not given again.
  local ow = game.overworld
  if not msg.deferredAt and ow.runner and ow.runner.isRunning and ow.runner:isRunning() then
    msg.deferredAt = love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
    CoopStory.deferred[#CoopStory.deferred + 1] = msg
    return
  end
  markSeen(save, msg.eid)
  local here = not msg.backlog and sameMap(game, msg.map)
  local skipGoods = alreadyLived(save, msg.rewards)
  local Commands = require("src.script.Commands")
  pcall(require, "src.script.Gen2Commands")
  -- mapCallback: a flag write re-syncs the objects on this map at once (an
  -- NPC the scene sent away leaves the partner's screen too)
  local ctx = { game = game, overworld = game.overworld, save = save, coopRemote = true,
                mapCallback = true }
  local got, changed = {}, false
  for _, r in ipairs(msg.rewards) do
    local ok, err = pcall(function()
      if skipGoods and MONEY_KINDS[r.kind] then return end
      if r.kind ~= "warp" then changed = true end
      if r.kind == "item" then
        if require("src.inventory.Bag").add(save, r.id, r.count or 1, game.data) then
          got[#got + 1] = itemName(game, r.id)
        end
      elseif r.kind == "money" then
        save.money = math.min(999999, (save.money or 0) + r.amount)
        got[#got + 1] = "MONEY"
      elseif r.kind == "coins" and Commands.g2_give_coins then
        Commands.g2_give_coins(ctx, r.amount)
      elseif r.kind == "take_item" then
        local inv = save.inventory or {}
        local held = tonumber(inv[r.id]) or 0
        if held > 0 then
          local left = held - math.min(held, tonumber(r.count) or 1)
          inv[r.id] = left > 0 and left or nil
        end
      elseif r.kind == "set_flag" then
        Commands.set_flag(ctx, r.id)
      elseif r.kind == "clear_flag" then
        Commands.clear_flag(ctx, r.id)
      elseif r.kind == "scene" and Commands.g2_set_scene then
        Commands.g2_set_scene(ctx, r.map, r.scene)
      elseif r.kind == "scene_key" and type(r.map) == "string" then
        -- already the save's own key (the sender's g2Scenes)
        save.g2Scenes = save.g2Scenes or {}
        save.g2Scenes[r.map] = r.scene
      elseif r.kind == "special_call" and Commands.g2_special_call then
        Commands.g2_special_call(ctx, tonumber(r.id))
      elseif r.kind == "var_sprite" and Commands.g2_variablesprite then
        Commands.g2_variablesprite(ctx, tonumber(r.slot) or r.slot, r.sprite)
      elseif r.kind == "wram" and tonumber(r.addr) then
        save.g2Wram = save.g2Wram or {}
        save.g2Wram[tonumber(r.addr)] = r.value
      elseif r.kind == "rival_name" and type(r.name) == "string" and r.name ~= "" then
        save.player = save.player or {}
        save.player.rival = r.name
      elseif r.kind == "roam_release" and Commands.g2_init_roam_mons then
        if not save.g2RoamReleased then Commands.g2_init_roam_mons(ctx) end
      elseif r.kind == "trainer" then
        if CM.markTrainerBeaten then CM.markTrainerBeaten(game, game.overworld, r) end
      elseif r.kind == "warp" then
        -- applied when this player is free to move (not mid-dialogue), and
        -- only to a partner who was in the scene
        if here then CoopStory.pendingWarp = r end
      end
    end)
    if not ok then
      require("src.coop.CoopLog").warn("STORY", "reward " .. tostring(r.kind) .. " failed: " .. tostring(err))
    end
  end
  if #got > 0 then
    CM.showStatus("You got " .. got[1] .. (#got > 1 and " +" .. (#got - 1) or "") .. " too!", 3)
    pcall(function() require("src.core.Sound").play(game.data, "Get_Item1") end)
  elseif changed and not here and not skipGoods then
    CM.showStatus("Story shared by " .. tostring(msg.speaker or CM.partner.name or "partner"), 2.5)
  end
end

-- ticked by CoopManager.update; returns the page to draw (two lines) or nil
CoopStory.DEFER_MAX = 120   -- seconds an event waits for our script, at most

function CoopStory.tick(dt, game)
  if #CoopStory.deferred > 0 and game and game.save and game.overworld then
    local ow = game.overworld
    local busy = ow.runner and ow.runner.isRunning and ow.runner:isRunning()
    local t = love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
    local first = CoopStory.deferred[1]
    if not busy or (t - (first.deferredAt or t)) > CoopStory.DEFER_MAX then
      local list = CoopStory.deferred
      CoopStory.deferred = {}
      for _, msg in ipairs(list) do
        msg.deferredAt = true
        CoopStory.onPartnerRewards(game, msg)
      end
    end
  end
  if #CoopStory.inbox > 0 and game and game.save and game.overworld then
    local inbox = CoopStory.inbox
    CoopStory.inbox = {}
    for _, msg in ipairs(inbox) do
      msg.backlog = true
      CoopStory.onPartnerRewards(game, msg)
    end
  end
  local w = CoopStory.pendingWarp
  if w and game then
    local CM = manager()
    local ow = game.overworld
    if CM and ow and CM.overworldIdle(game, ow) and ow.startWarpTo and w.x and w.y then
      CoopStory.pendingWarp = nil
      CoopStory.feed = {}
      local f = type(w.facing) == "string" and w.facing:lower() or "down"
      if f ~= "up" and f ~= "down" and f ~= "left" and f ~= "right" then f = "down" end
      pcall(ow.startWarpTo, ow, w.map, w.x, w.y, f)
    end
  end
  local page = CoopStory.feed[1]
  if not page then return end
  CoopStory.feedTimer = (CoopStory.feedTimer or 0) + (dt or 0)
  if CoopStory.feedTimer >= CoopStory.FEED_PAGE then
    CoopStory.feedTimer = 0
    table.remove(CoopStory.feed, 1)
  end
end

function CoopStory.currentPage()
  return CoopStory.feed[1]
end

-- ---------------------------------------------------------------------
-- saves that were caught by the old, incomplete sharing
-- ---------------------------------------------------------------------

-- A partner who watched Falkner fall before the state diff above got the
-- ZEPHYRBADGE and EVENT_BEAT_FALKNER but never Elm's call (SPECIALCALL 3,
-- whose script clears EVENT_ELMS_AIDE_IN_VIOLET_POKEMON_CENTER), so the aide
-- never appears with the Togepi egg and the Route 32 guard sends them back
-- into Violet City for ever.  Arming the call again lets Elm ring the next
-- time they step outside, exactly as he would have.  Gold/Silver numbering.
local AIDE_REPAIR = {
  beat = "EVENT_G2_1213",        -- EVENT_BEAT_FALKNER
  egg = "EVENT_G2_0045",         -- EVENT_GOT_TOGEPI_EGG_FROM_ELMS_AIDE
  aideAway = "EVENT_G2_1792",    -- EVENT_ELMS_AIDE_IN_VIOLET_POKEMON_CENTER (set = hidden)
  call = 3,                      -- SPECIALCALL: Elm, "my aide is in VIOLET's POKEMON CENTER"
}

function CoopStory.repairSave(save)
  if type(save) ~= "table" or type(save.flags) ~= "table" then return false end
  local okV, V = pcall(require, "src.core.GameVersion")
  local version = okV and V.get and V.get() or nil
  if version ~= "gold" and version ~= "silver" then return false end
  local f = save.flags
  local r = AIDE_REPAIR
  local beat = f[r.beat] == true or f.ZEPHYRBADGE == true
  if beat and f[r.egg] ~= true and f[r.aideAway] == true
     and save.g2SpecialCall == nil and save.g2SpecialCallActive == nil then
    save.g2SpecialCall = r.call
    require("src.core.Logger").info("co-op story repair: re-armed Elm's call for the Togepi egg")
    return true
  end
  return false
end

return CoopStory
