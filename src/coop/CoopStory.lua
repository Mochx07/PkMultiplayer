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
CoopStory.ARRIVE_SETTLE = 0.6 -- the partner has been on the map this long
-- WHO LEADS A BIG SCENE YOU BOTH WALKED INTO (nightly.2).  Each game
-- starts its own copy of a map-load scene; walked into together, both asked
-- CO-OP/SOLO and both invited the other, and the two invites crossed.  Now
-- the scene is claimed at once (coop_story_hold), a beat is waited for the
-- partner's own claim, and when both claimed it the host leads: the guest
-- stands by for the host's invite, reading along.
CoopStory.CLAIM_BEAT = 0.35

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
  if CM.storyCompatible and not CM.storyCompatible() then return false end
  local map = ow and ow.map and ow.map.id
  return map ~= nil and CM.mapsMatch(CM.partner.map, map)
end

-- Gold / Silver / Crystal's Elite Four chambers: entering one plays a scene
-- (walk in, the door shuts) that belongs to whoever walked in
local LEAGUE_ENTRANCES = { WILLS_ROOM = true, KOGAS_ROOM = true, BRUNOS_ROOM = true,
                           KARENS_ROOM = true, LANCES_ROOM = true }

-- Gen 1 Safari Zone gate: each player pays and plays their own Safari game,
-- and declining "Leaving early?" warps only that player back into the zone
local PERSONAL_MAPS = { SAFARI_ZONE_GATE = true }

-- Gen 1 maps whose onEnter hook only refreshes blocks or toggles from flags
-- (never queues a cutscene), safe to re-run live when partner flags arrive
local LIVE_REFRESH_MAPS = {
  GAME_CORNER = true,
  POKEMON_TOWER_7F = true,
  MR_FUJIS_HOUSE = true,
  SILPH_CO_2F = true, SILPH_CO_3F = true, SILPH_CO_4F = true,
  SILPH_CO_5F = true, SILPH_CO_6F = true, SILPH_CO_7F = true,
  SILPH_CO_8F = true, SILPH_CO_9F = true, SILPH_CO_10F = true,
  SILPH_CO_11F = true, SAFFRON_CITY = true,
  ROUTE_12 = true, ROUTE_16 = true,
  VICTORY_ROAD_1F = true, VICTORY_ROAD_2F = true, VICTORY_ROAD_3F = true,
  POKEMON_MANSION_1F = true, POKEMON_MANSION_2F = true,
  POKEMON_MANSION_3F = true, POKEMON_MANSION_B1F = true,
  CINNABAR_GYM = true,
  LORELEIS_ROOM = true, BRUNOS_ROOM = true, AGATHAS_ROOM = true,
}

-- the outbox holds at most this many events; the oldest go first
CoopStory.OUTBOX_MAX = 300

-- Is there a partner this event is owed to?  Linked now, or -- for a save
-- that has played with someone (save.coopPartner) -- linked again later.
local function sharing(save)
  local CM = manager()
  if not (CM and CM.storySync) then return false end
  if CM.isConnected and CM.isConnected() then
    -- Gold/Silver with Crystal: their event flags are other bits
    return not CM.storyCompatible or CM.storyCompatible()
  end
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
  local toggles = {}
  for map, objs in pairs(type(save and save.objectToggles) == "table" and save.objectToggles or {}) do
    toggles[map] = copyTable(objs)
  end
  return { flags = copyTable(save and save.flags), scenes = copyTable(save and save.g2Scenes),
           call = save and save.g2SpecialCall,
           -- `variablesprite`: who stands where in the story (the Rocket
           -- disguises, the Lake of Rage, the Radio Tower director)
           sprites = copyTable(save and save.gen2VarSprites),
           -- the script WRAM mirror (Underground switches, event variables)
           wram = copyTable(save and save.g2Wram),
           rival = save and save.player and save.player.rival,
           roam = save and save.g2RoamReleased == true,
           toggles = toggles,
           taken = copyTable(save and save.itemsTaken),
           hidden = copyTable(save and save.hiddenTaken),
           trainers = copyTable(save and save.defeatedTrainers) }
end

-- what the script changed, as rewards the partner's copy can apply
local function stateChanges(save, before)
  local out = {}
  if not (save and before) then return out end
  local flags = save.flags or {}
  local wasFlags = before.flags or {}
  -- Pokemon Tower 7F's rescue script warps out without hiding 7F's Mr. Fuji;
  -- record the hide in objectToggles so the partner (and any re-entry) sees
  -- the room empty once he is at his house
  if flags.EVENT_RESCUED_MR_FUJI == true and not wasFlags.EVENT_RESCUED_MR_FUJI then
    save.objectToggles = save.objectToggles or {}
    save.objectToggles.POKEMON_TOWER_7F = save.objectToggles.POKEMON_TOWER_7F or {}
    save.objectToggles.POKEMON_TOWER_7F.POKEMONTOWER7F_MR_FUJI = false
  end
  -- Yellow spells Silph Co. 11F's single grunt SILPHCO11F_ROCKET where Red/Blue
  -- have ROCKET1 and ROCKET2; hide both spellings so a Red <-> Yellow pair clears 11F
  if flags.EVENT_BEAT_SILPH_CO_GIOVANNI == true and not wasFlags.EVENT_BEAT_SILPH_CO_GIOVANNI then
    save.objectToggles = save.objectToggles or {}
    save.objectToggles.SILPH_CO_11F = save.objectToggles.SILPH_CO_11F or {}
    save.objectToggles.SILPH_CO_11F.SILPHCO11F_ROCKET = false
  end
  local keys = {}
  for k in pairs(flags) do keys[k] = true end
  for k in pairs(wasFlags) do keys[k] = true end
  for k in pairs(keys) do
    local now = flags[k] == true
    local was = wasFlags[k] == true
    if now ~= was and not NOT_SHARED_FLAGS[k] then
      out[#out + 1] = { kind = now and "set_flag" or "clear_flag", id = k }
    end
  end
  for k, v in pairs(save.g2Scenes or {}) do
    if (before.scenes or {})[k] ~= v then out[#out + 1] = { kind = "scene_key", map = k, scene = v } end
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
  local beforeToggles = before.toggles or {}
  for map, objs in pairs(type(save.objectToggles) == "table" and save.objectToggles or {}) do
    if type(objs) == "table" then
      local was = beforeToggles[map] or {}
      for obj, visible in pairs(objs) do
        if was[obj] ~= visible then
          out[#out + 1] = { kind = "toggle", map = map, obj = obj, visible = visible }
        end
      end
    end
  end
  local beforeTaken = before.taken or {}
  for k, v in pairs(type(save.itemsTaken) == "table" and save.itemsTaken or {}) do
    if v and not beforeTaken[k] then out[#out + 1] = { kind = "taken", key = k } end
  end
  local beforeHidden = before.hidden or {}
  for k, v in pairs(type(save.hiddenTaken) == "table" and save.hiddenTaken or {}) do
    if v and not beforeHidden[k] then out[#out + 1] = { kind = "hidden_taken", key = k } end
  end
  local beforeTrainers = before.trainers or {}
  for k, v in pairs(type(save.defeatedTrainers) == "table" and save.defeatedTrainers or {}) do
    if v and not beforeTrainers[k] then out[#out + 1] = { kind = "trainer", npcId = k } end
  end
  return out
end
CoopStory.stateChanges = stateChanges
CoopStory.snapshot = snapshot

local function shortName(n)
  return require("src.coop.CoopI18n").truncate(tostring(n or ""), 7)
end

-- Leading pure read-only guard commands evaluated on a disposable probe ctx
-- before scanning for a big battle, so inactive coord triggers (Indigo Plateau
-- Mon/Wed rival rematch) or already-beaten Elite Four members never pop up a
-- phantom CO-OP/SOLO prompt whose script immediately returns.
local GUARD_SKIP = {
  label = true, g2_nop = true, face_player = true, face = true, face_npc = true,
}
local GUARD_EVAL = {
  check_flag = true, check_item = true, check_dex_owned = true,
  g2_check_scene = true, g2_readvar = true, g2_compare = true,
  g2_setvar = true, g2_addvar = true, g2_divide_var = true,
  g2_check_just_battled = true, g2_endifjustbattled = true,
  g2_checktime = true, g2_check_money = true, g2_check_poke = true,
  g2_check_coins = true, g2_check_party_egg = true,
}
local unpack = table.unpack or unpack

local function resolveScriptTarget(target, labels, len)
  if target == "end" then return nil end
  if type(target) == "string" then return labels[target] end
  if type(target) == "number" and target >= 1 and target <= len and target % 1 == 0 then
    return target
  end
  return nil
end

local function copyArray(arr)
  local out = {}
  for i = 1, #(arr or {}) do out[i] = arr[i] end
  return out
end

local function bigBattleFromRow(CM, row, save)
  if type(row) ~= "table" then return nil end
  local class, party
  if row[1] == "g2_load_trainer" then
    class, party = row[2], row[3]
  elseif row[1] == "start_battle" and row[2] == "trainer" then
    class, party = row[3], row[4]
  elseif row[1] == "rival_battle" then
    -- Red / Blue / Yellow's rival: his class and the fight's base party
    -- (Commands.rival_battle adds the starter's offset)
    class, party = row[2], row[3]
  end
  if type(class) == "string" and CM.isBigBattleClass(class, save, party) then
    return class, party
  end
  return nil
end

-- The trainer an event leads to, when it is one worth deciding about before
-- the talking starts (CoopManager.isBigBattleClass): evaluates leading
-- read-only guard checks first, then scans only rows reachable from there.
function CoopStory.findBigBattle(script, save, ctx)
  local CM = manager()
  if not (CM and CM.isBigBattleClass and type(script) == "table") then return nil end
  local len = #script
  if len == 0 then return nil end
  local labels = {}
  for i = 1, len do
    local row = script[i]
    if type(row) == "table" and row[1] == "label" and type(row[2]) == "string" and labels[row[2]] == nil then
      labels[row[2]] = i
    end
  end

  local okC, Commands = pcall(require, "src.script.Commands")
  if okC then pcall(require, "src.script.Gen2Commands") end
  local probe = {
    save = save,
    game = ctx and ctx.game,
    overworld = ctx and ctx.overworld,
    justBattled = ctx and ctx.justBattled,
    lastCheck = false,
    g2Var = 0,
    g2Stack = {},
  }

  -- Phase 1: evaluate pure read-only leading guards without mutating live state.
  local pc = 1
  for _ = 1, 256 do
    if not pc or pc < 1 or pc > len then return nil end
    local row = script[pc]
    if type(row) ~= "table" then
      pc = pc + 1
    else
      local class, party = bigBattleFromRow(CM, row, save)
      if class then return class, party end
      local cmd = row[1]
      if GUARD_SKIP[cmd] then
        pc = pc + 1
      elseif cmd == "end" then
        return nil
      elseif cmd == "jump" then
        pc = resolveScriptTarget(row[2], labels, len)
        if not pc then return nil end
      elseif cmd == "jump_if_true" then
        if probe.lastCheck then
          pc = resolveScriptTarget(row[2], labels, len)
          if not pc then return nil end
        else
          pc = pc + 1
        end
      elseif cmd == "jump_if_false" then
        if not probe.lastCheck then
          pc = resolveScriptTarget(row[2], labels, len)
          if not pc then return nil end
        else
          pc = pc + 1
        end
      elseif cmd == "g2_call" then
        probe.g2Stack[#probe.g2Stack + 1] = row[2]
        pc = pc + 1
      elseif cmd == "g2_return" then
        if #probe.g2Stack > 0 then
          pc = resolveScriptTarget(table.remove(probe.g2Stack), labels, len)
          if not pc then return nil end
        else
          return nil
        end
      elseif cmd == "g2_readmem" and type(save) == "table" then
        local addr = row[2] or probe.g2HalfwordVar
        local val = (type(save.g2Wram) == "table" and addr and save.g2Wram[addr]) or 0
        probe.g2Var = val
        probe.lastCheck = val ~= 0
        pc = pc + 1
      elseif GUARD_EVAL[cmd] and type(save) == "table" and okC and type(Commands[cmd]) == "function" then
        local ok, ret = pcall(Commands[cmd], probe, unpack(row, 2))
        if not ok then break end
        if ret == "end" then return nil end
        pc = pc + 1
      else
        break
      end
    end
  end

  -- Phase 2: reachability DFS from the post-guard pc following branches and calls.
  local work = { { pc = pc, stack = copyArray(probe.g2Stack) } }
  local visited = {}
  while #work > 0 do
    local frame = table.remove(work)
    local p, cs = frame.pc, frame.stack
    while p and p >= 1 and p <= len do
      local key = tostring(p) .. ":" .. tostring(cs[#cs] or "")
      if visited[key] then break end
      visited[key] = true
      local row = script[p]
      if type(row) ~= "table" then
        p = p + 1
      else
        local class, party = bigBattleFromRow(CM, row, save)
        if class then return class, party end
        local cmd = row[1]
        if cmd == "end" then
          break
        elseif cmd == "g2_return" then
          if #cs > 0 then
            p = resolveScriptTarget(table.remove(cs), labels, len)
          else
            break
          end
        elseif cmd == "g2_call" then
          cs[#cs + 1] = row[2]
          p = p + 1
        elseif cmd == "jump" then
          p = resolveScriptTarget(row[2], labels, len)
        elseif cmd == "jump_if_true" or cmd == "jump_if_false" then
          local branch = resolveScriptTarget(row[2], labels, len)
          if branch then
            work[#work + 1] = { pc = branch, stack = copyArray(cs) }
          end
          p = p + 1
        else
          p = p + 1
        end
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
  local preBefore = CoopStory.pendingBefore
  CoopStory.pendingBefore = nil
  local outer = CoopStory.current and CoopStory.current.lua and CoopStory.current or nil
  if not ctx or ctx.coopRemote or ctx.phoneCaller then return end
  -- a map callback only re-derives this map from the save as it loads (who
  -- stands where, which scene is up); sent across it would overwrite the
  -- partner's own -- the Bug Contest gate's scene in the middle of theirs
  if ctx.mapCallback then return end
  if not sharing(ctx.save) then
    CoopStory.current = nil
    return
  end
  local ow = ctx.overworld
  local here = partnerHere(ow)
  local CM = manager()
  local class, party = CoopStory.findBigBattle(script, ctx.save, ctx)
  -- A Lua talk/victory handler that starts a helper runner (Mt. Moon fossil,
  -- Pokemon Tower 7F grunt exit) keeps its own outer story context so items
  -- and flags written before runner:run are still part of one event; when
  -- the runner itself is the big battle (Pokemon Tower 2F rival), the runner
  -- takes over and the outer wrapper stands down.
  if outer then
    if not class then
      outer.handedToRunner = true
      ctx.coopStory = outer
      return
    end
    outer.personal = true
  end
  CoopStory.current = nil
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
    before = preBefore or (outer and outer.before) or snapshot(ctx.save),
  }
  CoopStory.current = ctx.coopStory
  -- A LEAGUE CHAMBER'S DOOR IS EACH PLAYER'S OWN.  Its scene walks you in
  -- and shuts the door behind you.  Sent across, it set the partner's scene
  -- and door flag too: they walked in after you with no scene, onto the
  -- door already shut (reported from play: "he walks through the door").
  -- The Safari Zone gate is personal the same way: each player pays and
  -- leaves or stays in their own Safari game.
  if (not class and LEAGUE_ENTRANCES[ctx.coopStory.map or ""])
     or PERSONAL_MAPS[ctx.coopStory.map or ""] then
    ctx.coopStory.personal = true
    ctx.coopStory.here = false
    return
  end
  -- A BIG BATTLE WITH THE PARTNER ELSEWHERE: wait for them, or go alone.
  -- Reported from play: the BURNED TOWER's rival walks up the moment you
  -- step in, so the one who got there first always fought him solo.
  if not here and class then
    here = CoopStory.waitForPartner(ctx, class, party)
    ctx.coopStory.here = here
  end
  if not here then return end
  -- (a scene we already held for them with WAIT is ours: they stood by)
  if class and not ctx.coopHoldSent and CoopStory.claim(ctx, class) == "theirs" then
    ctx.coopSkipScript = true
    ctx.coopStory = nil
    CoopStory.current = nil
    return
  end
  -- a gym leader / League / rival scene: CO-OP or SOLO is asked now, before
  -- the first line, so the partner can read it all with you
  if class and CM.offerBigBattle then
    CM.offerBigBattle(ctx, class, party)
  end
end

-- an invisible pause inside the script's coroutine: `secs`, or until
-- `done()` says so
local Beat = {}
Beat.__index = Beat
Beat.isOpaque = false
function Beat:update(dt)
  self.t = self.t + (dt or 0.016)
  if self.t >= self.secs or (self.done and self.done()) then
    local stack = self.game.stack
    for i = #stack.states, 1, -1 do
      if stack.states[i] == self then table.remove(stack.states, i) break end
    end
    self.runner:resume()
  end
end
function Beat:draw() end

-- "ours" (lead the scene) or "theirs" (the partner leads it)
function CoopStory.claim(ctx, class)
  local CM = manager()
  local game, runner, ow = ctx.game, ctx.runner, ctx.overworld
  if not (CM and CM.net and CM.isConnected and CM.isConnected() and game and game.stack
          and runner and runner.yield and ow and ow.map) then
    return "ours"
  end
  CM.net:send({ type = "coop_story_hold", map = ow.map.id, class = class })
  ctx.coopHoldSent, ctx.coopHoldSent_map = true, ow.map.id
  local function theirClaim() return CoopStory.heldHere(ow, class) end
  -- the beat needs the script's coroutine to pause in (outside one -- a
  -- direct call -- it decides at once)
  local co = coroutine.running()
  local inside = co ~= nil and (not coroutine.isyieldable or coroutine.isyieldable())
  if inside and not theirClaim() then
    game.stack:push(setmetatable({ game = game, runner = runner, t = 0, secs = CoopStory.CLAIM_BEAT,
                                   done = theirClaim }, Beat))
    runner:yield()
  end
  if theirClaim() and not CM.isHost then
    local t = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
    CoopStory.held = { map = ow.map.id, class = class, at = t }
    return "theirs"
  end
  -- ours: their claim (if any) yields to the host
  if CM.isHost then CoopStory.held = nil end
  return "ours"
end

-- "TOBY & MOCHX" while a shared, non-personal script is on screen
function CoopStory.duoName()
  if CoopStory.renderDuo then return CoopStory.renderDuo end
  local st = CoopStory.current
  if st and st.here and not st.personal then return st.duo end
  return nil
end

-- EACH SCREEN NAMES ITS OWN PLAYER FIRST (1.20).  The partner used to get the
-- line already filled in on our side -- "MOCHI & TOBY" on TOBY's screen too,
-- always second, the guest in someone else's story.  The line now also goes
-- over unfilled (`raw`), and each copy fills it in itself: "TOBY & MOCHI"
-- there.  A partner from before 1.20 reads `text`, as it always did.
function CoopStory.localDuo(game)
  local CM = manager()
  if not CM then return nil end
  return shortName(CM.getLocalPlayerName(game)) .. " & " .. shortName(CM.partner.name or "PARTNER")
end

function CoopStory.fillForUs(game, raw, speaker)
  local okTB, TextBox = pcall(require, "src.render.TextBox")
  if not okTB then return nil end
  -- 1.20 duo: a page that hands something over names the one who got it
  local okD, CoopDuo = pcall(require, "src.coop.CoopDuo")
  local duoFilled = okD and CoopDuo.fillForUs(game, raw, CoopStory.localDuo(game), speaker)
  if duoFilled then return duoFilled end
  CoopStory.renderDuo = CoopStory.localDuo(game)
  local ok, shown = pcall(TextBox.substitute, game, raw)
  CoopStory.renderDuo = nil
  return ok and type(shown) == "string" and shown or nil
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
  elseif name == "set_field" and row[2] == "safari" then
    -- Safari Zone admission / early exit belongs to this player alone
    st.personal = true
    st.here = false
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
  CM.net:send({ type = "coop_story_text", map = st.map, text = shown, raw = text,
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

-- also lifted by CoopCatchUp.watchHold when the script dies before its end
CoopStory.releaseHold = releaseHold

function CoopStory.finish(ctx)
  local st = ctx and ctx.coopStory
  if st and st.lua then
    if st.luaCloseDone then
      return CoopStory.finishLua({ game = ctx.game, save = ctx.save, overworld = ctx.overworld,
                                   coopStory = st, coopHoldSent = ctx.coopHoldSent,
                                   coopHoldSent_map = ctx.coopHoldSent_map })
    end
    return
  end
  if CoopStory.current == st then CoopStory.current = nil end
  -- the scene's flags go first (below), so the partner's own copy of the
  -- scene is already closed by the time the hold on it lifts
  local function done()
    -- If this script sent a big-battle CO-OP invite that never launched a
    -- battle, cancel it now so the partner is never left stranded in READ ALONG.
    if ctx and ctx.coopBigInviteId then
      local CM = manager()
      local big = CM and CM.bigBattle
      if big and big.inviteId == ctx.coopBigInviteId then
        CM.bigBattle = nil
        if CM.net and CM.isConnected and CM.isConnected() then
          CM.net:send({ type = "coop_battle_cancel", inviteId = ctx.coopBigInviteId })
        end
      end
      ctx.coopBigInviteId = nil
    end
    releaseHold(ctx)
    -- 1.20 duo: the partner reading along hears the scene is over
    if st and st.here then
      pcall(function() require("src.coop.CoopDuo").sendSceneEnd(st.map) end)
    end
  end
  if not st or st.personal then return done() end
  -- flags, scenes and the armed call first, the warp after everything
  for _, r in ipairs(stateChanges(ctx.save, st.before)) do st.rewards[#st.rewards + 1] = r end
  -- the scene walks the partner along only if they were in it; if the script
  -- walked the player after the warp (e.g. Vermilion Dock's two steps past
  -- the ticket guard), land the partner at the final cell on that map
  if st.warp and st.here then
    local ow = ctx.overworld
    if ow and ow.map and ow.map.id == st.warp.map and ow.player then
      st.warp.x = ow.player.cellX or st.warp.x
      st.warp.y = ow.player.cellY or st.warp.y
      st.warp.facing = ow.player.facing or st.warp.facing
    end
    st.rewards[#st.rewards + 1] = st.warp
  end
  CoopStory.deliver(ctx, st)
  done()
end

-- the event goes out now, or waits in the save for the next link
function CoopStory.deliver(ctx, st)
  if #st.rewards == 0 then return end
  local CM = manager()
  local eid = CoopStory.stamp(ctx.save)
  if not (CM and CM.net and CM.isConnected and CM.isConnected()) then
    CoopStory.queue(ctx.save, st.rewards, eid)
    return
  end
  local Compat = package.loaded["src.coop.CoopEditions"]
  if Compat then Compat.tag(ctx.game, st.rewards) end
  CM.net:send({ type = "coop_story_rewards", map = st.map, rewards = st.rewards, eid = eid,
                src = require("src.core.GameVersion").get(),
                speaker = CM.getLocalPlayerName(ctx.game) })
end

-- ---------------------------------------------------------------------
-- Red / Blue / Yellow's story: Lua talk handlers
-- ---------------------------------------------------------------------
--
-- Gen 1's story is hand-ported Lua (data/scripts/story*.lua, gyms.lua): a
-- talk handler is a function (game, ow, npc, done), not script rows, so
-- ScriptRunner -- and begin/finish above -- never saw OAK's PARCEL, the
-- Mt. Moon fossil or a leader's badge and TM, and the partner was left to
-- do it all again.  Each handler now runs inside a story context of its
-- own (lib/Hooks.lua wraps MapScripts.talkScript): the save is compared
-- before and after, as for Gen 2, plus what Gen 1 keeps outside the flags
-- -- objects shown or hidden, item balls and hidden items taken -- and the
-- bag and the wallet, since its gifts are Bag.add calls, not rows.
--
-- PERSONAL, as in Gen 2: a Pokemon given, traded or met in a wild battle
-- (the Celadon EEVEE, ZAPDOS), or anything paid for.  A trainer battle
-- inside the handler (BROCK) keeps its badge, TM and flags, but its prize
-- money and the potions used in it are the player's own.

local function monKeys(save)
  local keys, n = {}, 0
  for _, m in ipairs(type(save.party) == "table" and save.party or {}) do
    keys[tostring(m)] = true
    n = n + 1
  end
  for _, box in pairs(type(save.boxes) == "table" and save.boxes or {}) do
    if type(box) == "table" then n = n + #box end
  end
  return keys, n
end

local function luaSnapshot(save)
  local s = snapshot(save)
  s.bag = copyTable(save.inventory)
  s.money = tonumber(save.money) or 0
  s.coins = tonumber(save.coins) or 0
  s.monKeys, s.monCount = monKeys(save)
  s.safari = save.safari ~= nil
  s.safariNags = tonumber(save.safariNags) or 0
  return s
end
CoopStory.luaSnapshot = luaSnapshot

-- what a handler changed beyond the flags, and whether it was personal
local function luaChanges(save, before, battled)
  local out = {}
  if (save.safari ~= nil) ~= (before.safari == true)
     or (tonumber(save.safariNags) or 0) ~= (tonumber(before.safariNags) or 0) then
    return out, true
  end
  local keys, count = monKeys(save)
  if count ~= before.monCount then return out, true end
  for k in pairs(before.monKeys) do
    if not keys[k] then return out, true end
  end
  local bag = type(save.inventory) == "table" and save.inventory or {}
  local spent = false
  for id, n in pairs(before.bag) do
    local left = tonumber(bag[id]) or 0
    if left < (tonumber(n) or 0) then
      spent = true
      if not battled then out[#out + 1] = { kind = "take_item", id = id, count = n - left } end
    end
  end
  for id, n in pairs(bag) do
    local had = tonumber(before.bag[id]) or 0
    if (tonumber(n) or 0) > had then out[#out + 1] = { kind = "item", id = id, count = n - had } end
  end
  local money = tonumber(save.money) or 0
  if not battled then
    -- money that left is a purchase; money that came with goods gone, a sale
    if money < before.money then return out, true end
    if money > before.money then
      if spent then return out, true end
      out[#out + 1] = { kind = "money", amount = money - before.money }
    end
  end
  return out, false
end
CoopStory.luaChanges = luaChanges

-- a handler that never called its `done` would hold the context open for
-- good; past this many seconds it no longer counts
CoopStory.LUA_MAX = 600

local function luaCurrent()
  local st = CoopStory.current
  if not (st and st.lua) then return nil end
  local t = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
  if t - (st.at or t) > CoopStory.LUA_MAX then
    CoopStory.current = nil
    return nil
  end
  return st
end

function CoopStory.beginLua(game, ow)
  local okV, V = pcall(require, "src.core.GameVersion")
  if not (okV and V.isGen1 and V.isGen1()) then return nil end
  local save = game and game.save
  if type(save) ~= "table" or not sharing(save) then return nil end
  local mapId = ow and ow.map and ow.map.id
  if PERSONAL_MAPS[mapId or ""] then return nil end
  -- a handler inside a story already being recorded adds nothing to it
  luaCurrent()
  if CoopStory.current then return nil end
  local CM = manager()
  local ctx = { game = game, save = save, overworld = ow }
  ctx.coopStory = {
    map = mapId,
    here = partnerHere(ow),
    rewards = {},
    personal = false,
    lua = true,
    at = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock(),
    duo = shortName(CM.getLocalPlayerName(game)) .. " & " .. shortName(CM.partner.name or "PARTNER"),
    lines = 0,
    before = luaSnapshot(save),
  }
  CoopStory.current = ctx.coopStory
  return ctx
end

function CoopStory.finishLua(ctx)
  local st = ctx and ctx.coopStory
  if not st then return end
  if st.handedToRunner and not st.luaCloseDone then
    local r = ctx.overworld and ctx.overworld.runner
    if r and r.isRunning and r:isRunning() then
      st.luaCloseDone = true
      return
    end
  end
  if CoopStory.current == st then CoopStory.current = nil end
  releaseHold(ctx)
  if st.here then
    pcall(function() require("src.coop.CoopDuo").sendSceneEnd(st.map) end)
  end
  if st.personal then return end
  local more, personal = luaChanges(ctx.save, st.before, st.battled)
  if personal then return end
  for _, r in ipairs(stateChanges(ctx.save, st.before)) do st.rewards[#st.rewards + 1] = r end
  for _, r in ipairs(more) do st.rewards[#st.rewards + 1] = r end
  if st.warp and st.here then st.rewards[#st.rewards + 1] = st.warp end
  CoopStory.deliver(ctx, st)
end

-- Synchronous Gen 1 actions that bypass ScriptRunner and talkScript:
-- picking up an item ball (LIFT_KEY, SILPH_SCOPE, CARD_KEY, GOLD_TEETH),
-- finding a hidden item, opening a Silph Co. Card Key door, or Bill's
-- Cell Separator exit.
function CoopStory.recordAction(game, ow, fn)
  local okV, V = pcall(require, "src.core.GameVersion")
  if not (okV and V.isGen1 and V.isGen1()) then return fn() end
  local save = game and game.save
  local mapId = ow and ow.map and ow.map.id
  if type(save) ~= "table" or not sharing(save) or CoopStory.current
     or PERSONAL_MAPS[mapId or ""] then
    return fn()
  end
  local before = luaSnapshot(save)
  local a, b, c = fn()
  if (tonumber(save.coins) or 0) ~= (tonumber(before.coins) or 0) then
    return a, b, c
  end
  local more, personal = luaChanges(save, before, false)
  if not personal then
    local rewards = stateChanges(save, before)
    for _, r in ipairs(more) do rewards[#rewards + 1] = r end
    if #rewards > 0 then
      local ctx = { game = game, save = save, overworld = ow }
      CoopStory.deliver(ctx, { map = mapId, rewards = rewards })
    end
  end
  return a, b, c
end

-- Wrap Gen 1 map hooks (MapScripts.get) for coordinate triggers and map-entry
-- scripts that mutate story state outside ScriptRunner (Pokemon Tower 6F's
-- ghost Marowak, Silph Co. 11F's Giovanni, Vermilion Dock's S.S. Anne
-- departure, Route 25's Bill toggle).
local wrappedMapHooks = setmetatable({}, { __mode = "k" })

function CoopStory.wrapMapHooks(mapId, hooks)
  if type(hooks) ~= "table" then return hooks end
  local w = wrappedMapHooks[hooks]
  if w then return w end
  w = {}
  for k, v in pairs(hooks) do w[k] = v end

  if mapId == "POKEMON_TOWER_6F" and type(hooks.onStep) == "function" then
    local origStep = hooks.onStep
    w.onStep = function(game, ow, x, y, ...)
      if game and game.save and not game.save.flags.EVENT_BEAT_GHOST_MAROWAK
         and x == 10 and y == 16 then
        if CoopStory.heldHere(ow, "GHOST_MAROWAK") then
          if ow and ow.scriptMove and ow.player then ow:scriptMove(ow.player, "right", 1) end
          return true
        end
        local ok, ctx = pcall(CoopStory.beginLua, game, ow)
        if not ok then ctx = nil end
        local triggered = origStep(game, ow, x, y, ...)
        if triggered and ctx and ctx.coopStory then
          ctx.coopStory.battled = true
          ctx.coopStory.marowak = true
          CoopStory.activeStepCtx = ctx
          local CM = manager()
          if CM and CM.net and CM.isConnected and CM.isConnected() then
            CM.net:send({ type = "coop_story_hold", map = "POKEMON_TOWER_6F", class = "GHOST_MAROWAK" })
            ctx.coopHoldSent, ctx.coopHoldSent_map = true, "POKEMON_TOWER_6F"
          end
        elseif ctx then
          CoopStory.finishLua(ctx)
        end
        return triggered
      end
      return origStep(game, ow, x, y, ...)
    end
  elseif mapId == "SILPH_CO_11F" and type(hooks.onStep) == "function" then
    local origStep = hooks.onStep
    w.onStep = function(game, ow, x, y, ...)
      if game and game.save and not game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI
         and ((x == 6 and y == 13) or (x == 7 and y == 12)) then
        if CoopStory.heldHere(ow, "OPP_GIOVANNI")
           or (CoopStory.stepHold and CoopStory.stepHold.map == "SILPH_CO_11F")
           or (ow and ow.scriptMoves and #ow.scriptMoves > 0) then
          return true
        end
        local triggered = origStep(game, ow, x, y, ...)
        if triggered then
          local CM = manager()
          if CM and CM.net and CM.isConnected and CM.isConnected() then
            CM.net:send({ type = "coop_story_hold", map = "SILPH_CO_11F", class = "OPP_GIOVANNI" })
            CoopStory.stepHold = { map = "SILPH_CO_11F", class = "OPP_GIOVANNI" }
          end
        end
        return triggered
      end
      return origStep(game, ow, x, y, ...)
    end
  end

  if mapId == "VERMILION_DOCK" and type(hooks.onEnter) == "function" then
    local origEnter = hooks.onEnter
    w.onEnter = function(game, ow, ...)
      local save = game and game.save
      local before = (type(save) == "table" and sharing(save)) and snapshot(save) or nil
      local qLen = ow and ow.scriptQueue and #ow.scriptQueue or 0
      local res = origEnter(game, ow, ...)
      local newLen = ow and ow.scriptQueue and #ow.scriptQueue or 0
      if before and newLen > qLen then
        CoopStory.pendingBefore = before
      end
      return res
    end
  elseif mapId == "ROUTE_25" and type(hooks.onEnter) == "function" then
    local origEnter = hooks.onEnter
    w.onEnter = function(game, ow, fromMapId, ...)
      local f = game and game.save and game.save.flags
      if f and f.EVENT_MET_BILL_2 and not f.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING then
        return CoopStory.recordAction(game, ow, function() return origEnter(game, ow, fromMapId) end)
      end
      return origEnter(game, ow, fromMapId, ...)
    end
  end

  wrappedMapHooks[hooks] = w
  return w
end

function CoopStory.onAfterBattle()
  local ctx = CoopStory.activeStepCtx
  if not ctx then return end
  CoopStory.activeStepCtx = nil
  pcall(CoopStory.finishLua, ctx)
end

-- the handler, run inside its story context; `done` closes it (once)
local wrapped = setmetatable({}, { __mode = "k" })

function CoopStory.wrapTalk(handler)
  if type(handler) ~= "function" then return handler end
  local w = wrapped[handler]
  if w then return w end
  w = function(game, ow, npc, done, ...)
    local ok, ctx = pcall(CoopStory.beginLua, game, ow)
    if not ok then ctx = nil end
    local closed = false
    local function close(...)
      if not closed then
        closed = true
        if ctx then
          local okF, err = pcall(CoopStory.finishLua, ctx)
          if not okF then require("src.coop.CoopLog").warn("STORY", "lua story: " .. tostring(err)) end
        end
      end
      if done then return done(...) end
    end
    return handler(game, ow, npc, close, ...)
  end
  wrapped[handler] = w
  return w
end

-- OverworldState:pushBattle, inside a handler: a trainer battle's money and
-- items stay out of the event, a wild one makes it personal (except the
-- Pokemon Tower 6F uncatchable ghost Marowak, which is a shared story gate)
function CoopStory.onBattle(battle)
  local st = luaCurrent()
  if not (st and type(battle) == "table") then return end
  st.battled = true
  if battle.kind == "wild" and not battle.noCatch then st.personal = true end
end

-- TextBox.new, inside a handler: the partner standing here reads along
function CoopStory.onLuaText(game, text)
  local st = luaCurrent()
  if not (st and st.here) then return end
  CoopStory.onText({ game = game, coopStory = st }, text)
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
  local CM = manager()
  if CM and CM.showStatus then
    local name = (CM.partner and CM.partner.name) or "Partner"
    local fmt = require("src.coop.CoopI18n").t("%s is waiting for you!")
    CM.showStatus(string.format(fmt, name), 3)
  end
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
  if self.onDone then self.onDone(self.arrived) end
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
  local pname = require("src.coop.CoopI18n").truncate(string.upper(CM.partner.name or "PARTNER"), 8)
  local name = CM.trainerDisplayName and CM.trainerDisplayName(game, class, party) or "TRAINER"
  local choice = "solo"
  game.stack:push(require("src.coop.CoopI18n").menu().new(game, {
    { label = "WAIT " .. pname, onSelect = function() choice = "wait" runner:resume() end },
    { label = "SOLO", onSelect = function() choice = "solo" runner:resume() end },
  }, { tx = 3, ty = 4, tw = 14, header = require("src.coop.CoopI18n").truncate("VS " .. name, 12), cancelable = true,
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
  if CM.storyCompatible and not CM.storyCompatible() then return 0 end
  local speaker = CM.getLocalPlayerName(game)
  for _, entry in ipairs(box) do
    -- saves from before 1.5 kept the bare reward list
    local rewards = entry.rewards or entry
    local Compat = package.loaded["src.coop.CoopEditions"]
    if Compat then Compat.tag(game, rewards) end
    CM.net:send({ type = "coop_story_rewards", backlog = true, rewards = rewards,
                  eid = entry.eid, speaker = speaker, src = require("src.core.GameVersion").get() })
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
  local text = msg.text
  if type(msg.raw) == "string" and msg.raw ~= "" then
    text = CoopStory.fillForUs(game, msg.raw, msg.speaker) or text
  end
  local okTB, TextBox = pcall(require, "src.render.TextBox")
  local lines = {}
  if okTB then
    local okP, pages = pcall(TextBox.paginate, text, 18)
    if okP and type(pages) == "table" then
      for _, page in ipairs(pages) do
        for _, line in ipairs(page) do lines[#lines + 1] = line end
      end
    end
  end
  if #lines == 0 then
    for line in (text .. "\n"):gmatch("(.-)[\n\v\f]") do lines[#lines + 1] = line end
  end
  for i = 1, #lines, 2 do
    table.insert(CoopStory.feed, { lines[i], lines[i + 1] or "" })
  end
  -- 1.20 duo: the pages wait for this player's A, and the ones left behind
  -- fold into one (src/coop/CoopDuo.lua)
  local okD, CoopDuo = pcall(require, "src.coop.CoopDuo")
  if okD and CoopDuo.on() then
    CoopDuo.onPartnerLine(msg.map)
    return
  end
  -- never let a long scene pile up behind the player
  while #CoopStory.feed > 12 do table.remove(CoopStory.feed, 1) end
end

local function itemName(game, id)
  local def = game.data and game.data.items and game.data.items[id]
  return (def and def.name) or tostring(id)
end

-- ---------------------------------------------------------------------
-- Cross-version story reward remapping (Gen 2: Gold vs Silver)
-- ---------------------------------------------------------------------
--
-- In Gen 2, two events hand out legendary wings based on cartridge version:
--   1. Goldenrod Radio Tower (Director, after Rocket takeover):
--      Gold receives RAINBOW_WING (ITEM_178) and EVENT_GOT_RAINBOW_WING (120).
--      Silver receives SILVER_WING (ITEM_071) and EVENT_GOT_SILVER_WING (121).
--   2. Pewter City (Gramps, Kanto postgame):
--      Gold receives SILVER_WING (ITEM_071) and EVENT_GOT_SILVER_WING (121).
--      Silver receives RAINBOW_WING (ITEM_178) and EVENT_GOT_RAINBOW_WING (120).
--
-- Sharing these rewards raw meant a Silver player co-oping with Gold received
-- Ho-Oh's RAINBOW_WING at the 7th Johto gym, locked out their own SILVER_WING,
-- and broke Pewter City later. We remap the wing and its event flag to match
-- the local receiver's cartridge rules.

local function isRainbowWingItem(id)
  return id == 178 or id == "178" or id == "ITEM_178" or id == "RAINBOW_WING"
end

local function isSilverWingItem(id)
  return id == 71 or id == "071" or id == "71" or id == "ITEM_071" or id == "SILVER_WING"
end

local function isRainbowWingFlag(id)
  return id == 120 or id == "120" or id == "EVENT_G2_0120" or id == "EVENT_GOT_RAINBOW_WING"
end

local function isSilverWingFlag(id)
  return id == 121 or id == "121" or id == "EVENT_G2_0121" or id == "EVENT_GOT_SILVER_WING"
end

local function toItemFormat(targetKind, sampleId)
  if targetKind == "silver" then
    if type(sampleId) == "number" then return 71 end
    if sampleId == "RAINBOW_WING" or sampleId == "SILVER_WING" then return "SILVER_WING" end
    return "ITEM_071"
  else
    if type(sampleId) == "number" then return 178 end
    if sampleId == "SILVER_WING" or sampleId == "RAINBOW_WING" then return "RAINBOW_WING" end
    return "ITEM_178"
  end
end

local function toFlagFormat(targetKind, sampleId)
  if targetKind == "silver" then
    if type(sampleId) == "number" or sampleId == "120" or sampleId == "121" then return 121 end
    if sampleId == "EVENT_GOT_RAINBOW_WING" or sampleId == "EVENT_GOT_SILVER_WING" then return "EVENT_GOT_SILVER_WING" end
    return "EVENT_G2_0121"
  else
    if type(sampleId) == "number" or sampleId == "120" or sampleId == "121" then return 120 end
    if sampleId == "EVENT_GOT_SILVER_WING" or sampleId == "EVENT_GOT_RAINBOW_WING" then return "EVENT_GOT_RAINBOW_WING" end
    return "EVENT_G2_0120"
  end
end

local function isRadioTowerEvent(msg, rewards, save)
  if type(msg.map) == "string" and msg.map:find("RADIO_TOWER") then
    return true
  end
  for _, r in ipairs(rewards) do
    if r.kind == "set_flag" then
      if r.id == 1889 or r.id == "1889" or r.id == "EVENT_G2_1889" or r.id == "EVENT_TEAM_ROCKET_DISBANDED" then
        return true
      end
    elseif r.kind == "scene" or r.kind == "scene_key" then
      if type(r.map) == "string" and r.map:find("RADIO_TOWER") then
        return true
      end
    end
  end
  if type(msg.map) == "string" and msg.map:find("PEWTER") then
    return false
  end
  local beatE4 = save and save.flags and (save.flags.EVENT_G2_0068 == true or save.flags.EVENT_BEAT_ELITE_FOUR == true)
  local kantoBadges = save and save.kantoBadges and next(save.kantoBadges) ~= nil
  if not beatE4 and not kantoBadges then
    return true
  end
  return false
end

function CoopStory.remapVersionRewards(game, msg)
  if type(msg) ~= "table" or type(msg.rewards) ~= "table" then return end
  -- Gold/Silver <-> Crystal (experimental): the partner's flags made ours
  -- another edition's event made this edition's (src/coop/CoopEditions.lua)
  local Compat = package.loaded["src.coop.CoopEditions"]
  if Compat then Compat.filter(game, msg) end
  local okV, V = pcall(require, "src.core.GameVersion")
  if not (okV and V and V.isGen2 and V.isGen2()) then return end
  local isSilver = V.isSilver and V.isSilver()
  local isGold = V.isGold and V.isGold()
  if not (isSilver or isGold) then return end

  local hasWing = false
  for _, r in ipairs(msg.rewards) do
    if (r.kind == "item" or r.kind == "take_item") and (isRainbowWingItem(r.id) or isSilverWingItem(r.id)) then
      hasWing = true
      break
    elseif (r.kind == "set_flag" or r.kind == "clear_flag") and (isRainbowWingFlag(r.id) or isSilverWingFlag(r.id)) then
      hasWing = true
      break
    end
  end
  if not hasWing then return end

  local save = game and game.save
  local isRadio = isRadioTowerEvent(msg, msg.rewards, save)
  local targetWing
  if isSilver then
    targetWing = isRadio and "silver" or "rainbow"
  else
    targetWing = isRadio and "rainbow" or "silver"
  end

  for _, r in ipairs(msg.rewards) do
    if (r.kind == "item" or r.kind == "take_item") and (isRainbowWingItem(r.id) or isSilverWingItem(r.id)) then
      local oldId = r.id
      r.id = toItemFormat(targetWing, oldId)
      if oldId ~= r.id then
        require("src.coop.CoopLog").info("STORY", string.format("remapped partner wing item %s -> %s for %s", tostring(oldId), tostring(r.id), isSilver and "Silver" or "Gold"))
      end
    elseif (r.kind == "set_flag" or r.kind == "clear_flag") and (isRainbowWingFlag(r.id) or isSilverWingFlag(r.id)) then
      local oldId = r.id
      r.id = toFlagFormat(targetWing, oldId)
      if oldId ~= r.id then
        require("src.coop.CoopLog").info("STORY", string.format("remapped partner wing flag %s -> %s for %s", tostring(oldId), tostring(r.id), isSilver and "Silver" or "Gold"))
      end
    end
  end
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
    elseif r.kind == "toggle" then
      state = true
      if ((save.objectToggles or {})[r.map] or {})[r.obj] ~= r.visible then differs = true end
    elseif r.kind == "taken" then
      state = true
      if not (save.itemsTaken or {})[r.key] then differs = true end
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
  if CM.storyCompatible and not CM.storyCompatible() then
    require("src.coop.CoopLog").info("STORY", "event from the other cartridge's numbering ignored")
    return
  end
  if not (game and game.save and game.overworld) then
    -- still on the title screen / loading: applied once the save is up
    if #CoopStory.inbox < CoopStory.OUTBOX_MAX then CoopStory.inbox[#CoopStory.inbox + 1] = msg end
    return
  end
  CoopStory.remapVersionRewards(game, msg)
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
  local got, changed, resync = {}, false, false
  -- what was handed over, for the 1.20 duo's boxes (CoopDuo.queueGifts)
  local gifts = {}
  for _, r in ipairs(msg.rewards) do
    local ok, err = pcall(function()
      if skipGoods and MONEY_KINDS[r.kind] then return end
      if r.kind ~= "warp" then changed = true end
      if r.kind == "item" then
        if require("src.inventory.Bag").add(save, r.id, r.count or 1, game.data) then
          got[#got + 1] = itemName(game, r.id)
          local def = game.data and game.data.items and game.data.items[r.id]
          gifts[#gifts + 1] = { name = got[#got], count = tonumber(r.count) or 1,
                                key = def and def.keyItem and true or false }
        end
      elseif r.kind == "money" then
        save.money = math.min(999999, (save.money or 0) + r.amount)
        got[#got + 1] = "MONEY"
        gifts[#gifts + 1] = { money = r.amount }
      elseif r.kind == "coins" and Commands.g2_give_coins then
        Commands.g2_give_coins(ctx, r.amount)
      elseif r.kind == "take_item" then
        local inv = save.inventory or {}
        local held = tonumber(inv[r.id]) or 0
        if held > 0 then
          local take = math.min(held, tonumber(r.count) or 1)
          local okB, Bag = pcall(require, "src.inventory.Bag")
          if okB and Bag and Bag.remove then
            Bag.remove(save, r.id, take)
          else
            local left = held - take
            inv[r.id] = left > 0 and left or nil
          end
        end
      elseif r.kind == "set_flag" then
        Commands.set_flag(ctx, r.id)
        if r.id == "EVENT_RESCUED_MR_FUJI" and Commands.hide_object then
          Commands.hide_object(ctx, "POKEMON_TOWER_7F", "POKEMONTOWER7F_MR_FUJI")
        end
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
      elseif r.kind == "toggle" and type(r.map) == "string" and type(r.obj) == "string" then
        local cmd = r.visible and Commands.show_object or Commands.hide_object
        if cmd then cmd(ctx, r.map, r.obj) end
      elseif r.kind == "taken" and type(r.key) == "string" then
        save.itemsTaken = save.itemsTaken or {}
        save.itemsTaken[r.key] = true
        resync = true
      elseif r.kind == "hidden_taken" and type(r.key) == "string" then
        save.hiddenTaken = save.hiddenTaken or {}
        save.hiddenTaken[r.key] = true
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
  -- an item ball the partner picked up leaves this screen too, and any door
  -- or barrier flag the partner unlocked (Silph Co. card key doors, Rocket
  -- Hideout lift gate, Game Corner poster) updates on the live map
  if resync and ow.syncObjectVisibility then pcall(ow.syncObjectVisibility, ow) end
  if changed and ow then
    if ow.stampClosedDoors then pcall(ow.stampClosedDoors, ow) end
    local curMap = ow.map and ow.map.id
    if curMap and LIVE_REFRESH_MAPS[curMap] then
      local okM, MS = pcall(require, "src.script.MapScripts")
      local hooks = okM and MS and MS.get and MS.get(curMap)
      if hooks and hooks.onEnter then pcall(hooks.onEnter, game, ow) end
    end
  end
  local okD, CoopDuo = pcall(require, "src.coop.CoopDuo")
  if #gifts > 0 and here and okD and CoopDuo.on() then
    -- 1.20 duo: handed over in a box each, with the jingle, as the cartridge
    -- does -- "TOBY received POTION!" -- once this player is free
    CoopDuo.queueGifts(game, gifts, msg.eid)
  elseif #got > 0 then
    -- (the font has no "+": "TM34 +1" read "TM34 1", like a count)
    if #got > 1 then
      CM.showStatus(string.format("You got %s and %d more too!", got[1], #got - 1), 3)
    else
      CM.showStatus(string.format("You got %s too!", got[1]), 3)
    end
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
      -- Gen 1's HALL_OF_FAME onEnter only runs Oak's induction and credits
      -- when save.pendingHallOfFame is armed by the Champions Room script
      if w.map == "HALL_OF_FAME" and game.save then
        local okV, V = pcall(require, "src.core.GameVersion")
        if okV and V and V.isGen1 and V.isGen1() then
          game.save.pendingHallOfFame = true
        end
      end
      pcall(ow.startWarpTo, ow, w.map, w.x, w.y, f)
    end
  end
  local okD, CoopDuo = pcall(require, "src.coop.CoopDuo")
  if okD then
    -- gift boxes already applied to the save show even if the link dropped
    pcall(CoopDuo.tick, dt, game)
    if CoopDuo.on() then
      -- 1.20 duo: the page waits for this player's A
      CoopDuo.tickFeed(dt, game)
      return
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
  local repaired = false
  local r = AIDE_REPAIR
  local beat = f[r.beat] == true or f.ZEPHYRBADGE == true
  if beat and f[r.egg] ~= true and f[r.aideAway] == true
     and save.g2SpecialCall == nil and save.g2SpecialCallActive == nil then
    save.g2SpecialCall = r.call
    require("src.core.Logger").info("co-op story repair: re-armed Elm's call for the Togepi egg")
    repaired = true
  end

  -- Repair legendary wings: Silver players before Kanto must not hold the Rainbow Wing,
  -- and Gold players before Kanto must not hold the Silver Wing.
  local beatE4 = f.EVENT_G2_0068 == true or f.EVENT_BEAT_ELITE_FOUR == true
  local kantoBadges = save.kantoBadges and next(save.kantoBadges) ~= nil
  local reachedKanto = beatE4 or kantoBadges
  if version == "silver" and not reachedKanto then
    local hadRainbow = false
    if save.inventory and save.inventory.ITEM_178 then
      save.inventory.ITEM_178 = nil
      hadRainbow = true
    end
    if type(save.bagOrder) == "table" then
      for i = #save.bagOrder, 1, -1 do
        if save.bagOrder[i] == "ITEM_178" then
          table.remove(save.bagOrder, i)
          hadRainbow = true
        end
      end
    end
    if f.EVENT_G2_0120 == true or f.EVENT_GOT_RAINBOW_WING == true or f[120] == true then
      f.EVENT_G2_0120 = nil
      f.EVENT_GOT_RAINBOW_WING = nil
      f[120] = nil
      hadRainbow = true
    end
    if (f.EVENT_G2_1889 == true or hadRainbow) and save.inventory then
      if not save.inventory.ITEM_071 then
        save.inventory.ITEM_071 = 1
        if type(save.bagOrder) == "table" then
          save.bagOrder[#save.bagOrder + 1] = "ITEM_071"
        end
      end
      f.EVENT_G2_0121 = true
    end
    if hadRainbow then
      pcall(function()
        require("src.coop.CoopLog").info("STORY", "repaired Silver save: removed premature Rainbow Wing and restored Silver Wing")
      end)
      repaired = true
    end
  elseif version == "gold" and not reachedKanto then
    local hadSilver = false
    if save.inventory and save.inventory.ITEM_071 then
      save.inventory.ITEM_071 = nil
      hadSilver = true
    end
    if type(save.bagOrder) == "table" then
      for i = #save.bagOrder, 1, -1 do
        if save.bagOrder[i] == "ITEM_071" then
          table.remove(save.bagOrder, i)
          hadSilver = true
        end
      end
    end
    if f.EVENT_G2_0121 == true or f.EVENT_GOT_SILVER_WING == true or f[121] == true then
      f.EVENT_G2_0121 = nil
      f.EVENT_GOT_SILVER_WING = nil
      f[121] = nil
      hadSilver = true
    end
    if (f.EVENT_G2_1889 == true or hadSilver) and save.inventory then
      if not save.inventory.ITEM_178 then
        save.inventory.ITEM_178 = 1
        if type(save.bagOrder) == "table" then
          save.bagOrder[#save.bagOrder + 1] = "ITEM_178"
        end
      end
      f.EVENT_G2_0120 = true
    end
    if hadSilver then
      pcall(function()
        require("src.coop.CoopLog").info("STORY", "repaired Gold save: removed premature Silver Wing and restored Rainbow Wing")
      end)
      repaired = true
    end
  end

  return repaired
end

require("src.coop.CoopTouch").bind(WaitHere, "wait")

return CoopStory
