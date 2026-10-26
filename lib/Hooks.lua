-- The co-op build's engine changes that only run BEFORE or AFTER an engine
-- function, as wrappers rather than copies -- so the engine's own body (and
-- whatever upstream changes in it later) stays the engine's.
--
-- Each entry is applied once, when its engine module is first available
-- (lib/Install.lua).  The comments name the co-op build's own lines they
-- stand for.

local Hooks = {}

local function coopManager()
  local ok, CM = pcall(require, "src.coop.CoopManager")
  if ok then return CM end
  return nil
end

local function ctrlDown(withGui)
  local k = love and love.keyboard
  if not (k and k.isDown) then return false end
  if k.isDown("lctrl") or k.isDown("rctrl") then return true end
  return withGui and (k.isDown("lgui") or k.isDown("rgui")) or false
end

-- the partner is told we are gone (coop_bye), so their copy drops our avatar
-- now instead of after the link times out
local function sayGoodbye()
  local CM = package.loaded["src.coop.CoopManager"]
  if CM and CM.disconnect then
    pcall(function()
      if CM.connected or (CM.isConnected and CM.isConnected()) then CM.disconnect() end
    end)
  end
end
Hooks.sayGoodbye = sayGoodbye

-- engine functions a wrapper below expected and did not find
Hooks.missing = {}

-- t[name] = make(original), if t[name] is a function at all.
--
-- Written down the way lib/Transplant.lua writes its changes down: an undo
-- for the next load (Hooks.record, set by main.lua), and the wrapped function
-- in package.__pkmultiplayer_orig -- so a wrapper an earlier load left here is
-- seen through, and the engine's function is wrapped once, not twice.
local function wrap(t, label, name, make)
  local current = type(t) == "table" and t[name]
  if type(current) ~= "function" then
    Hooks.missing[#Hooks.missing + 1] = label .. "." .. name
    return
  end
  local ORIG = rawget(package, "__pkmultiplayer_orig")
  local BORN = rawget(package, "__pkmultiplayer_born")
  local now = rawget(package, "__pkmultiplayer_load")
  local original = current
  if ORIG and BORN then
    -- only an earlier load's leftovers; this load's co-op copy is wrapped
    for _ = 1, 32 do
      local o = ORIG[original]
      if o == nil or BORN[original] == now then break end
      original = o
    end
  end
  local wrapper = make(original)
  t[name] = wrapper
  if ORIG and BORN then ORIG[wrapper], BORN[wrapper] = original, now end
  if Hooks.record then
    Hooks.record(function()
      if rawget(t, name) == wrapper then rawset(t, name, current) end
    end)
  end
end

-- module name -> function(module) that installs its wrappers
Hooks.modules = {}

Hooks.modules["src.core.Game"] = function(Game)
  -- LEAVING THE GAME LEAVES THE CO-OP SESSION: QUIT (or a soft reset)
  -- without saving used to keep the link up while you sat on the title
  wrap(Game, "Game", "returnToTitle", function(returnToTitle)
    return function(self, ...)
      sayGoodbye()
      return returnToTitle(self, ...)
    end
  end)

  -- the co-op pump: once per frame, under battles and menus too
  wrap(Game, "Game", "update", function(update)
    return function(self, dt, ...)
      local a, b, c = update(self, dt, ...)
      local okCoop, coopErr = pcall(function()
        local CM = require("src.coop.CoopManager")
        if CM and CM.update then CM.update(self.overworld, dt) end
      end)
      if not okCoop and coopErr ~= self._lastCoopErr then
        -- reported once per distinct error: a silent failure here is a
        -- silent desync
        self._lastCoopErr = coopErr
        pcall(function() require("src.coop.CoopLog").error("UPDATE", tostring(coopErr)) end)
      end
      return a, b, c
    end
  end)

  -- T: chat (idle overworld, or a co-op double waiting on the partner);
  -- Y: the emote picker (idle overworld).  After the engine's own
  -- delegation to a state that takes keys, as in the co-op build.
  wrap(Game, "Game", "keypressed", function(keypressed)
    return function(self, key, ...)
      local top = self.stack and self.stack:top()
      local delegated = top and top.onKeyPressed
      if not delegated and key == "t" and not ctrlDown(true) then
        local ow = self.overworld
        local coopBattle = top and top.coopDouble == true and top.chooseAction ~= nil
        if coopBattle or (top == ow and ow and not ow.transitioning
           and not (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
           and not ow.engaging and not ow.inBattle
           and not (ow.scriptMoves and #ow.scriptMoves > 0)) then
          local CM = coopManager()
          if CM and CM.openChat then
            CM.openChat(self, ow)
            return
          end
        end
      end
      if not delegated and key == "y" and not ctrlDown(false) then
        local ow = self.overworld
        if top == ow and ow and not ow.transitioning and not ow.engaging and not ow.inBattle
           and not (ow.runner and ow.runner.isRunning and ow.runner:isRunning()) then
          local okE, CoopEmotes = pcall(require, "src.coop.CoopEmotes")
          if okE and CoopEmotes and CoopEmotes.openPicker(self) then return end
        end
      end
      return keypressed(self, key, ...)
    end
  end)

  -- co-op: the partner's game saves too (CoopManager.onLocalSaved)
  wrap(Game, "Game", "writeSave", function(writeSave)
    return function(self, ...)
      local result = writeSave(self, ...)
      pcall(function()
        local CM = require("src.coop.CoopManager")
        if CM.onLocalSaved then CM.onLocalSaved(result) end
      end)
      return result
    end
  end)

  -- An early co-op build wrote every hit's remaining HP into mon.stats.hp,
  -- shrinking the maximum for good.  A Gen 1/2 maximum is a pure function of
  -- species, level, DVs and stat exp, so a save carrying a lower one gets it
  -- back.
  wrap(Game, "Game", "restoreSave", function(restoreSave)
    return function(self, loaded, ...)
      local GV = require("src.core.GameVersion")
      if type(loaded) == "table" and (GV.isGen1() or GV.isGen2()) then
        local Stats = require("src.pokemon.Stats")
        for _, mon in ipairs(loaded.party or {}) do
          local def = type(mon) == "table" and mon.species and self.data.pokemon
                      and self.data.pokemon[mon.species]
          if def and mon.stats and mon.level and mon.dvs then
            local ok, calc = pcall(Stats.calc, def, mon.level, mon.dvs, mon.statExp)
            if ok and calc and calc.hp and (mon.stats.hp or 0) < calc.hp then
              mon.stats.hp = calc.hp
            end
          end
        end
      end
      return restoreSave(self, loaded, ...)
    end
  end)
end

Hooks.modules["src.core.SaveData"] = function(SaveData)
  -- story state the old co-op sharing left half-copied (src/coop/CoopStory)
  wrap(SaveData, "SaveData", "load", function(load)
    return function(...)
      local data, recovered = load(...)
      if type(data) == "table" then
        pcall(function() require("src.coop.CoopStory").repairSave(data) end)
      end
      return data, recovered
    end
  end)
end

Hooks.modules["src.render.TextBox"] = function(TextBox)
  -- the partner sees a "..." over us while a box is up
  wrap(TextBox, "TextBox", "new", function(new)
    return function(...)
      local self = new(...)
      if type(self) == "table" then
        self.isTextBox = true
        pcall(function()
          local CM = coopManager()
          if CM and CM.setInDialogue then CM.setInDialogue(true) end
        end)
      end
      return self
    end
  end)
end

Hooks.modules["src.ui.Menu"] = function(Menu)
  -- opts.header: a one-line title in its own box over the menu ("VS
  -- FALKNER"); Menu:draw (lib/patches/Menu.lua) draws it
  wrap(Menu, "Menu", "new", function(new)
    return function(game, items, opts, ...)
      local self = new(game, items, opts, ...)
      if type(self) == "table" and type(opts) == "table" then self.header = opts.header end
      return self
    end
  end)
end

Hooks.modules["src.battle.BattleState"] = function(BattleState)
  -- SELECT opens the chat in a co-op double, on the FIGHT / PKMN / ITEM /
  -- RUN menu or while waiting on the partner: the touch layout has no T key.
  -- (SELECT keeps its own job in the move list, where it reorders moves.)
  wrap(BattleState, "BattleState", "update", function(update)
    return function(self, dt, ...)
      local input = self.coopDouble and self.game and self.game.input
      if input and input:wasPressed("select") then
        local CB = package.loaded["src.coop.CoopBattle"]
        local waiting = CB and CB.waitingForPartner and CB.currentBattle == self
        if self.phase == "menu" or waiting then
          local CM = coopManager()
          if CM and CM.connected and CM.openChat then
            CM.openChat(self.game)
            return
          end
        end
      end
      return update(self, dt, ...)
    end
  end)

  -- MOVE ANIMATIONS LAND ON THE MONS IN A STAGED (3D) BATTLE.  DramaticShapes
  -- stands the two Pokemon on the map and carries the whole effects layer
  -- along as one rigid piece: moved to the pair's midpoint and scaled to their
  -- spacing.  Once the camera swings the line between the two marks no longer
  -- runs the way the Game Boy's did, so both ends of an animation missed --
  -- the ball and the hit hung in the air beside the mon.  What the rigid move
  -- leaves over at each mark is handed to the animation player as a per-side
  -- nudge (Gen2AnimPlayer:objectOffset below), in the layer's own pixels.
  -- SOUL LINK: the first catch in an area is bound to the partner's
  -- (src/coop/CoopSoulLink.lua)
  wrap(BattleState, "BattleState", "storeCaughtMon", function(storeCaughtMon)
    return function(self, ...)
      local mon = self.enemy and self.enemy.mon
      local a, b, c = storeCaughtMon(self, ...)
      local SL = package.loaded["src.coop.CoopSoulLink"]
      if SL and SL.onCaught and mon then pcall(SL.onCaught, self.game, mon) end
      return a, b, c
    end
  end)

  wrap(BattleState, "BattleState", "drawAnimLayer", function(drawAnimLayer)
    return function(self, ...)
      local ap = self.animPlayer
      if ap then ap.stageNudge = Hooks.stageNudge(self) end
      return drawAnimLayer(self, ...)
    end
  end)
end

-- DramaticShapes' arena module, when that mod is running (its loader
-- publishes its namespace for drivers; V.require answers from its cache)
local function stagedArena()
  local V = rawget(_G, "__DRAMATIC_SHAPE_V")
  if type(V) ~= "table" or type(V.require) ~= "function" then return nil end
  local ok, OB = pcall(V.require, "OverworldBattle")
  if ok and type(OB) == "table" and OB.geometry and OB.animScale then return OB end
  return nil
end

-- { player = {dx, dy}, enemy = {dx, dy} } or nil: how far each side's mark
-- is from where the rigid move puts its authored slot, divided back through
-- that move's scale.  The same numbers OverworldBattle's drawAnimLayer uses.
function Hooks.stageNudge(battle)
  local shot = battle.dramaticShapeShot
  if not (shot and shot.player and shot.enemy) then return nil end
  if battle.gen3Layout and battle:gen3Layout() then return nil end
  local OB = stagedArena()
  if not OB then return nil end
  local okG, geom = pcall(OB.geometry, battle)
  local a = okG and geom and geom.anchor
  if not (a and a.player and a.enemy) then return nil end
  local px, py = shot.player[1], shot.player[2]
  if OB.backPinned and OB.backPinned() then px, py = a.player[1], a.player[2] end
  local ex, ey = shot.enemy[1], shot.enemy[2]
  local okK, k = pcall(OB.animScale, shot, px, py, a)
  if not okK or type(k) ~= "number" or k <= 0 then return nil end
  local cx, cy = (ex + px) / 2, (ey + py) / 2
  local ax, ay = (a.enemy[1] + a.player[1]) / 2, (a.enemy[2] + a.player[2]) / 2
  local function rest(tx, ty, sx, sy)
    -- the slot after the rigid move: c + k * (slot - midpoint)
    local mx, my = cx + k * (sx - ax), cy + k * (sy - ay)
    return { (tx - mx) / k, (ty - my) / k }
  end
  return {
    player = rest(px, py, a.player[1], a.player[2]),
    enemy = rest(ex, ey, a.enemy[1], a.enemy[2]),
  }
end

-- The single layout's two pic centres in OAM space, as the co-op patch of
-- Gen2AnimPlayer has them: an object takes the nudge of the side it is on,
-- blended only across the middle fifth of the way between the two.
local PLAYER_PIC_OAM = { 40, 88 }
local ENEMY_PIC_OAM = { 132, 44 }

Hooks.modules["src.battle.Gen2AnimPlayer"] = function(Gen2AnimPlayer)
  wrap(Gen2AnimPlayer, "Gen2AnimPlayer", "objectOffset", function(objectOffset)
    return function(self, x, y, ...)
      local dx, dy = objectOffset(self, x, y, ...)
      local n = self.stageNudge
      if not n then return dx, dy end
      local px, py = PLAYER_PIC_OAM[1], PLAYER_PIC_OAM[2]
      local vx, vy = ENEMY_PIC_OAM[1] - px, ENEMY_PIC_OAM[2] - py
      local t = ((x - px) * vx + (y - py) * vy) / (vx * vx + vy * vy)
      local u = (t - 0.4) / 0.2
      if u < 0 then u = 0 elseif u > 1 then u = 1 end
      u = u * u * (3 - 2 * u)
      local p, e = n.player, n.enemy
      return dx + p[1] + (e[1] - p[1]) * u, dy + p[2] + (e[2] - p[2]) * u
    end
  end)
end

-- SHARE DAY CARE (src/coop/CoopDayCare.lua): inside the breeding sums -- and
-- only there -- the empty pen holds a copy of the partner's Pokemon
local function dayCareShare()
  return package.loaded["src.coop.CoopDayCare"]
end

Hooks.modules["src.pokemon.DayCare"] = function(DayCare)
  wrap(DayCare, "DayCare", "mon", function(mon)
    return function(save, which, ...)
      local S = dayCareShare()
      if S and S.scope ~= nil then return S.mon(mon, save, which) end
      return mon(save, which, ...)
    end
  end)
  for _, name in ipairs({ "pair", "parents", "compatibility", "eggSpecies", "inheritMoves", "step" }) do
    wrap(DayCare, "DayCare", name, function(original)
      return function(data, save, ...)
        local S = dayCareShare()
        if not (S and type(save) == "table" and save.coopDayCareMate) then
          return original(data, save, ...)
        end
        return S.within(save, original, data, save, ...)
      end
    end)
  end
end

Hooks.modules["src.pokemon.Gen2Breeding"] = function(Breeding)
  wrap(Breeding, "Gen2Breeding", "inheritDVs", function(inheritDVs)
    return function(data, save, egg, ...)
      local S = dayCareShare()
      if not (S and type(save) == "table" and save.coopDayCareMate) then
        return inheritDVs(data, save, egg, ...)
      end
      return S.within(save, inheritDVs, data, save, egg, ...)
    end
  end)
end

-- WRAP / BIND / FIRE SPIN REMEMBER WHOM THEY HOLD.  The engine's victim is
-- "the other side's lead", which in a co-op double is each copy's own
-- Pokemon -- a foe held on one screen chose a move on the other, and every
-- roll after that differed.  BattleState:trapperOf reads this instead.
Hooks.modules["src.battle.MoveEffects"] = function(MoveEffects)
  local rec = MoveEffects.full and MoveEffects.full.TRAPPING_EFFECT
  wrap(rec, "MoveEffects.full.TRAPPING_EFFECT", "afterDamage", function(afterDamage)
    return function(ctx, ...)
      local was = ctx and ctx.user and ctx.user.trappingTurns
      local a, b, c = afterDamage(ctx, ...)
      if ctx and ctx.user and ctx.user.trappingTurns and not was then
        ctx.user.trapTarget = ctx.target
      end
      return a, b, c
    end
  end)
end

-- WILD TOGETHER: four Pokemon out, no BALL can be aimed
Hooks.modules["src.inventory.ItemEffects"] = function(ItemEffects)
  wrap(ItemEffects, "ItemEffects", "use", function(use)
    return function(data, save, id, target, battle, ...)
      -- a POKé DOLL would end the battle on this copy alone
      local key = ItemEffects.alias and ItemEffects.alias(id, data and data.items and data.items[id]) or id
      if key == "POKE_DOLL" and type(battle) == "table" and battle.coopDouble then
        return "failed", { "Not while you\nbattle together!" }
      end
      local result, a, b, c = use(data, save, id, target, battle, ...)
      if result == "ball" and type(battle) == "table" and battle.coopWild then
        local W = package.loaded["src.coop.CoopWild"]
        return "failed", { (W and W.NO_BALL) or "Not while you\nbattle together!" }
      end
      return result, a, b, c
    end
  end)
end

-- THE PARTNER IN THE POKéGEAR (src/coop/CoopGear.lua): first in the phone
-- book, a call opens the chat, and a blinking mark on the town map
local function gear()
  local ok, G = pcall(require, "src.coop.CoopGear")
  return ok and G or nil
end

Hooks.modules["src.ui.PokegearMenu"] = function(PokegearMenu)
  wrap(PokegearMenu, "PokegearMenu", "contacts", function(contacts)
    return function(self, ...)
      local list = contacts(self, ...)
      local G = gear()
      if not G then return list end
      local ok, out = pcall(G.contacts, list)
      return ok and out or list
    end
  end)
  wrap(PokegearMenu, "PokegearMenu", "startPhoneCall", function(startPhoneCall)
    return function(self, entry, ...)
      local G = gear()
      if G then
        local ok, handled = pcall(G.call, self, entry)
        if ok and handled then return end
      end
      return startPhoneCall(self, entry, ...)
    end
  end)
  wrap(PokegearMenu, "PokegearMenu", "drawMap", function(drawMap)
    return function(self, ...)
      local a, b = drawMap(self, ...)
      local G = gear()
      if G then pcall(G.drawMap, self) end
      return a, b
    end
  end)
end

Hooks.modules["src.battle.TrainerAI"] = function(TrainerAI)
  -- a MEAN LOOK / SPIDER WEB (or a Gen 2 WRAP) holds the foe in as well
  wrap(TrainerAI, "TrainerAI", "switchAction", function(switchAction)
    return function(battle, ...)
      if battle and not battle.arena and battle.canRecall
         and not battle:canRecall(battle.enemy) then
        return nil
      end
      local act = switchAction(battle, ...)
      -- IN A DOUBLE THE OTHER FOE IS OUT TOO.  The bench is read as "every
      -- Pokemon but the one in front of you", which in a double includes the
      -- one fighting in the other slot -- and a JUGGLER switched the left foe
      -- into the Pokemon already standing on the right, two of it on the field
      if act and act.index and battle.isDouble and battle:isDouble() then
        local out = {}
        for p = 0, 3 do
          local b = battle.battlerAt and battle:battlerAt(p)
          if b and b.mon then out[b.mon] = true end
        end
        local party = battle.enemyParty or {}
        if out[party[act.index]] then
          act.index = nil
          for i, mon in ipairs(party) do
            if (mon.hp or 0) > 0 and not out[mon] then act.index = i break end
          end
          if not act.index then return nil end
        end
      end
      return act
    end
  end)
end

Hooks.modules["src.battle.Damage"] = function(Damage)
  -- A Gen 2 co-op double has no doubles numbers in its ruleset and passes
  -- HeartGold/SoulSilver's on opts (BattleState:computeDamage); the ruleset's
  -- own numbers, where it has them, still win.
  local KEYS = { "spreadNum", "spreadDen", "screenDoublesNum", "screenDoublesDen" }
  wrap(Damage, "Damage", "compute", function(compute)
    return function(ruleset, attacker, defender, move, opts, ...)
      if type(opts) == "table" and type(ruleset) == "table" then
        local fill
        for _, k in ipairs(KEYS) do
          if ruleset[k] == nil and opts[k] ~= nil then
            fill = fill or {}
            fill[k] = opts[k]
          end
        end
        if fill then ruleset = setmetatable(fill, { __index = ruleset }) end
      end
      return compute(ruleset, attacker, defender, move, opts, ...)
    end
  end)
end

Hooks.modules["src.script.Gen2Commands"] = function()
  -- a co-op session sharing a clock shares mom's picked weekday too
  local Commands = require("src.script.Commands")
  local readvar = Commands.g2_readvar
  if type(readvar) ~= "function" then return end
  function Commands.g2_readvar(ctx, var, ...)
    local a, b, c = readvar(ctx, var, ...)
    if var == 11 and ctx and ctx.save then
      local okCM, CM = pcall(require, "src.coop.CoopManager")
      local offset = okCM and CM.dayOffset and CM.dayOffset(ctx.save)
      if offset then
        ctx.g2Var = ((tonumber(os.date("%w")) or 0) + offset) % 7
      end
    end
    return a, b, c
  end
end

Hooks.modules["src.world.OverworldController"] = function(OverworldState)
  -- a wild / trainer battle may become a co-op double (the partner is asked)
  -- A STEP OR SWEET SCENT is a random encounter: WILD TOGETHER only shares
  -- those (a scripted wild battle, a gift, a legendary stays the player's)
  for _, name in ipairs({ "onStepComplete", "gen2SweetScentEncounter" }) do
    wrap(OverworldState, "OverworldState", name, function(original)
      return function(self, ...)
        self.pkmRandomEncounter = true
        local ok, a, b, c = pcall(original, self, ...)
        self.pkmRandomEncounter = nil
        if not ok then error(a, 0) end
        return a, b, c
      end
    end)
  end

  wrap(OverworldState, "OverworldState", "pushBattle", function(pushBattle)
    return function(self, battle, opts, ...)
      local CM = coopManager()
      if CM and CM.promptCoopBattle and CM.promptCoopBattle(self, battle, opts) then
        return
      end
      if CM and CM.setInBattle then CM.setInBattle(true) end
      return pushBattle(self, battle, opts, ...)
    end
  end)

  -- a trainer the partner is already fighting on this map does not spot us
  wrap(OverworldState, "OverworldState", "checkTrainerSight", function(checkTrainerSight)
    return function(self, ...)
      local CM = coopManager()
      if CM and CM.connected then
        local partnerEngaging = CM.isPartnerEngaging and CM.isPartnerEngaging(self.map and self.map.id)
        if partnerEngaging or CM.pendingBattleInvite or CM.activeInviteModal then
          return
        end
      end
      return checkTrainerSight(self, ...)
    end
  end)

  wrap(OverworldState, "OverworldState", "afterBattle", function(afterBattle)
    return function(self, result, battle, ...)
      local CM = coopManager()
      if CM then
        if CM.setInBattle then CM.setInBattle(false) end
        CM.partnerEngagingTrainer = nil
      end
      local okCB, CoopBattle = pcall(require, "src.coop.CoopBattle")
      if okCB and CoopBattle then
        CoopBattle.active = false
        CoopBattle.waitingForPartner = false
        CoopBattle.currentBattle = nil
      end
      -- back from a battle, every NPC on the player's tile is hushed so the
      -- player is never re-engaged before taking a step
      if self.player then
        local hush = { cellX = self.player.cellX, cellY = self.player.cellY }
        for _, n in ipairs(self.npcs or {}) do hush[n] = true end
        self.spotHush = hush
      end
      self.engaging = false
      self.emote = nil
      return afterBattle(self, result, battle, ...)
    end
  end)

  -- syncObjectVisibility REMOVES every npc that is not one of this map's own
  -- objects, so the walking Pokemon (no map object at all, and carrying the
  -- previous map's id across a seam) is set aside and put back
  wrap(OverworldState, "OverworldState", "syncObjectVisibility", function(syncObjectVisibility)
    return function(self, ...)
      local held
      for _, name in ipairs({ "npcs", "entities" }) do
        for _, e in ipairs(self[name] or {}) do
          if type(e) == "table" and (e.pkmFollower or e.pkmFollowerRemote or e.coopVisitor) then
            held = held or { npcs = {}, entities = {} }
            table.insert(held[name], e)
          end
        end
      end
      local a, b, c = syncObjectVisibility(self, ...)
      if held then
        for name, list in pairs(held) do
          local present = {}
          for _, e in ipairs(self[name] or {}) do present[e] = true end
          for _, e in ipairs(list) do
            if not present[e] then
              self[name] = self[name] or {}
              table.insert(self[name], e)
            end
          end
        end
      end
      return a, b, c
    end
  end)

  -- A on the walking Pokemon: it answers itself (it has no map text)
  wrap(OverworldState, "OverworldState", "talkTo", function(talkTo)
    return function(self, npc, ...)
      if type(npc) == "table" and npc.pkmFollower then
        local okF, FollowMon = pcall(require, "src.follow.FollowMon")
        if okF and FollowMon.talk(self.game or package.loaded["src.core.Game"], self, npc) then return end
      end
      return talkTo(self, npc, ...)
    end
  end)

  -- the partner's avatar, emotes and chat bubble (world pass), and the
  -- co-op overlays (UI pass)
  wrap(OverworldState, "OverworldState", "drawWorld", function(drawWorld)
    return function(self, ...)
      local a, b, c = drawWorld(self, ...)
      local CM = coopManager()
      if CM and CM.drawWorld then CM.drawWorld(self) end
      return a, b, c
    end
  end)

  wrap(OverworldState, "OverworldState", "drawUI", function(drawUI)
    return function(self, ...)
      local a, b, c = drawUI(self, ...)
      local CM = coopManager()
      if CM and CM.drawUI then CM.drawUI(self) end
      return a, b, c
    end
  end)
end

-- THE WALKING POKEMON (src/follow/FollowMon.lua) rides on Yellow's Pikachu's
-- calls: the engine already makes them on every map load (onMapEntered),
-- every frame (update), and across a seam (current -> keepPikachu, then
-- rebase). Outside Yellow those do nothing of their own.
Hooks.modules["src.world.PikachuFollower"] = function(PikachuFollower)
  local function follow()
    local ok, FollowMon = pcall(require, "src.follow.FollowMon")
    return ok and FollowMon or nil
  end

  wrap(PikachuFollower, "PikachuFollower", "onMapEntered", function(onMapEntered)
    return function(game, ow, opts, ...)
      local keep = opts and opts.keepPikachu
      local mine = type(keep) == "table" and keep.pkmFollower
      -- the engine's own follower must not be handed ours to re-list
      local a, b, c
      if mine then
        local o = {}
        for k, v in pairs(opts) do o[k] = v end
        o.keepPikachu = nil
        a, b, c = onMapEntered(game, ow, o, ...)
      else
        a, b, c = onMapEntered(game, ow, opts, ...)
      end
      local F = follow()
      if F then pcall(F.onMapEntered, game, ow, opts) end
      return a, b, c
    end
  end)

  wrap(PikachuFollower, "PikachuFollower", "update", function(update)
    return function(game, ow, ...)
      local a, b, c = update(game, ow, ...)
      local F = follow()
      if F then
        local ok, err = pcall(F.update, game, ow)
        if not ok and err ~= Hooks._lastFollowErr then
          Hooks._lastFollowErr = err
          pcall(function() require("src.coop.CoopLog").error("FOLLOW", tostring(err)) end)
        end
      end
      return a, b, c
    end
  end)

  -- Yellow's Pikachu first; otherwise ours, so crossConnection carries it
  wrap(PikachuFollower, "PikachuFollower", "current", function(current)
    return function(ow, ...)
      local pika = current(ow, ...)
      if pika then return pika end
      local F = follow()
      return F and F.current(ow) or nil
    end
  end)

  wrap(PikachuFollower, "PikachuFollower", "rebase", function(rebase)
    return function(ow, dx, dy, ...)
      local a, b, c = rebase(ow, dx, dy, ...)
      local F = follow()
      if F then pcall(F.rebase, ow, dx, dy) end
      return a, b, c
    end
  end)
end

-- ui.start_menu.items: the CO-OP (LAN) row, ahead of MODS / QUIT
function Hooks.startMenuItems(next, game, items)
  items = next(game, items)
  if type(items) ~= "table" then return items end
  local Strings = require("src.core.Strings")
  local row = { label = Strings("CO-OP (LAN)"), onSelect = function()
    local CoopMenu = require("src.coop.CoopMenu")
    game.stack:push(CoopMenu.new(game))
  end }
  local at = #items + 1
  for i, item in ipairs(items) do
    if item.label == Strings("MODS") or item.label == Strings("QUIT") then
      at = i
      break
    end
  end
  table.insert(items, at, row)
  return items
end

-- Closing the window says goodbye as well.
function Hooks.installQuit()
  if not love or Hooks._quitWrapped then return end
  Hooks._quitWrapped = true
  local quit = love.quit
  love.quit = function(...)
    sayGoodbye()
    if quit then return quit(...) end
  end
end

return Hooks
