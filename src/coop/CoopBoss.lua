-- src/coop/CoopBoss.lua
-- LEGENDS AND BOSSES IN CO-OP (1.20, capability "story.bosses").
--
-- ROAMING BEASTS (Raikou, Entei, Suicune).  Each player keeps their OWN
-- beasts: they roam in each save (save.g2Roam, Gen2Commands' InitRoamMons /
-- UpdateRoamMons) and nothing of one save is written into the other.
--   * POKEGEAR: each copy sends where its beasts are (coop_roam, again
--     whenever one moves or a new link comes up), and the MAP card shows the
--     partner's beside your own: the same icon in a blinking blue frame --
--     the partner's mark's colours -- where yours has the engine's green one.
--   * ENCOUNTER: when YOUR beast steps out (the cartridge's own roll in your
--     game) while the partner stands on the same map and TEAM UP WILD is on,
--     the partner is asked in, as for any TEAM UP WILD battle.  It is your
--     beast (its HP and DVs from your save) alone on its side, against one
--     Pokemon of each of you.
--   * THE CATCH RULE.  Together you fight; you don't catch -- TEAM UP WILD's
--     rule, no BALL with four out.  Cornered by two, the beast does not run
--     at the end of the turn.  Whatever HP it is left with stays in YOUR save
--     (as when it runs from you alone), and a beast knocked out together is
--     NOT gone for good, as a knock-out is on the cartridge: it gets away
--     with 1 HP and keeps roaming.  To catch it, meet it on your own (TEAM UP
--     WILD off, or the partner off the map): it is still that weak.  The
--     partner's own beast, in their save, is untouched by any of this.
--
-- BOSSES.  The Red GYARADOS (Lake of Rage), SUDOWOODO (Route 36), SNORLAX
-- (Vermilion) and RED (Mt. Silver), met with the partner on the same map:
--   * the wild three ask BATTLE MODE: CO-OP BOSS / SOLO BATTLE first (SOLO is
--     the way to catch it: a co-op boss can't be caught, a knock-out is the
--     cartridge's other ending and the script carries on from it);
--   * RED is a big battle already (CoopReady): its CO-OP DOUBLE is the boss
--     one;
--   * the boss stands ALONE on its side (Red sends his team one at a time),
--     with HP_MUL times the HP, and MOVES TWICE A TURN: its second move comes
--     after everybody has moved, chosen by the same AI.  Both copies decide
--     it from the battle's shared rng and nothing else, so they agree.
--
-- Wire: the battle invite / big battle "go" carry boss = "gyarados" |
-- "sudowoodo" | "snorlax" | "red", or beast = "RAIKOU" | ...; coop_roam
-- { beasts = { { n, s, m, l } } }.  All of it only when both copies have
-- the capability: a 1.6.x partner gets the plain battles of before.

local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")
local Strings = require("src.core.Strings")

local CoopBoss = {}

CoopBoss.CAP = "story.bosses"
CoopManager.registerCap(CoopBoss.CAP)

-- how much more HP a boss has (RED: each of his six)
CoopBoss.HP_MUL = { gyarados = 2, sudowoodo = 2, snorlax = 2, red = 1.5 }
CoopBoss.BEASTS = { RAIKOU = true, ENTEI = true, SUICUNE = true }
CoopBoss.SEND_EVERY = 1.0   -- seconds between looks at our own beasts

local DEX = { gyarados = 130, sudowoodo = 185, snorlax = 143, pikachu = 25 }
local NAME_DEX = { GYARADOS = 130, SUDOWOODO = 185, SNORLAX = 143, PIKACHU = 25 }

local function on() return CoopManager.bothHave(CoopBoss.CAP) end

local function send(msg)
  if CoopManager.connected and CoopManager.net then CoopManager.net:send(msg) end
end

-- the national dex number of a species id ("SPECIES_130", "GYARADOS", ...)
function CoopBoss.dexOf(data, species)
  -- the cartridge's own ids are national numbers ("SPECIES_130"); a def's
  -- `dex` can be a regional one, so it is only the fallback
  local s = tostring(species or ""):upper()
  local n = tonumber(s:match("^SPECIES_(%d+)$")) or NAME_DEX[s]
  if n then return n end
  local def = data and data.pokemon and species and data.pokemon[species]
  return type(def) == "table" and tonumber(def.nationalDex or def.national or def.dex) or nil
end

local function mapKey(id) return tostring(id or ""):upper():gsub("_", "") end

-- which boss a battle is, or nil
function CoopBoss.kindOf(battle, ow)
  if type(battle) ~= "table" then return nil end
  local data = (battle.game and battle.game.data) or battle.data
  if battle.kind == "trainer" then
    -- RED: the only trainer whose lead is a level 70+ PIKACHU (Lv81 in Gold,
    -- Silver and Crystal), whatever the import called his class
    local lead = type(battle.enemyParty) == "table" and battle.enemyParty[1]
    if type(lead) == "table" and CoopBoss.dexOf(data, lead.species) == DEX.pikachu
       and (tonumber(lead.level) or 0) >= 70 then
      return "red"
    end
    return nil
  end
  if battle.kind ~= "wild" then return nil end
  -- a scripted one: not a step in the grass, a beast, the Safari or the Contest
  if (ow and ow.pkmRandomEncounter) or battle.roamer or battle.safari or battle.bugContest
     or battle.ghost or battle.demo then
    return nil
  end
  local mon = battle.enemy and battle.enemy.mon
  if type(mon) ~= "table" then return nil end
  local dex = CoopBoss.dexOf(data, mon.species)
  if dex == DEX.sudowoodo then return "sudowoodo" end
  if dex == DEX.snorlax then return "snorlax" end
  if dex == DEX.gyarados then
    local Pokemon = require("src.pokemon.Pokemon")
    local okS, shiny = pcall(Pokemon.isShiny, mon)
    local map = ow and ow.map and mapKey(ow.map.id)
    if okS and shiny and (map == nil or map == "LAKEOFRAGE") then return "gyarados" end
  end
  return nil
end

-- the Gen 2 roaming beast a battle is, or nil
function CoopBoss.beastOf(battle)
  local r = type(battle) == "table" and battle.roamer
  return type(r) == "string" and CoopBoss.BEASTS[r] and r or nil
end

-- OverworldState:pushBattle (CoopManager.promptCoopBattle): a boss is marked
-- as one when the two of us can fight it that way
function CoopBoss.mark(ow, battle)
  if battle.coopBoss or battle.coopHandled or not on() then return end
  battle.coopBoss = CoopBoss.kindOf(battle, ow)
end

-- the guest's copy of the host's battle (CoopManager.startGuestBattle)
function CoopBoss.guestMark(battle, msg)
  if not (CoopManager.CAPS[CoopBoss.CAP] and type(msg) == "table") then return end
  if type(msg.boss) == "string" and CoopBoss.HP_MUL[msg.boss] then battle.coopBoss = msg.boss end
  if type(msg.beast) == "string" and CoopBoss.BEASTS[msg.beast] then battle.coopBeast = msg.beast end
end

-- ---------------------------------------------------------------------
-- asking the partner in
-- ---------------------------------------------------------------------

local function offerBoss(ow, battle, opts)
  local ok, why = CoopManager.partnerAvailable(ow, false, true)
  if not ok then
    battle.coopBoss = nil
    if why ~= "Partner is far away" then CoopManager.showStatus(tostring(why) .. ". Solo!", 2.5) end
    return false
  end
  local game = CoopManager.getGame(ow)
  if not (game and game.stack and game.save) then return false end
  battle.coopHandled = true
  local kind = battle.coopBoss
  local function solo()
    battle.coopBoss = nil
    ow:pushBattle(battle, opts)
  end
  local items = {
    { label = Strings("CO-OP BOSS"), onSelect = function()
      local CoopBattleSelect = require("src.coop.CoopBattleSelect")
      game.stack:push(CoopBattleSelect.new(game, game.save.party, function(chosen)
        local still, why = CoopManager.partnerAvailable(ow, false, true)
        if not still then
          CoopManager.showStatus(tostring(why) .. ". Solo!", 2.5)
          solo()
          return
        end
        battle.coopHandled = false
        if not require("src.coop.CoopWild").invite(ow, battle, opts, { boss = kind }, chosen) then
          battle.coopHandled = true
          solo()
          return
        end
        CoopLog.info("BOSS", "asked the partner in against the boss " .. kind)
      end, solo))
    end },
    { label = Strings("SOLO BATTLE"), onSelect = solo },
  }
  game.stack:push(require("src.coop.CoopI18n").menu().new(game, items, {
    tx = 3, ty = 4, tw = 14, header = "BATTLE MODE:", cancelable = true, onCancel = solo,
  }))
  return true
end

local function offerBeast(ow, battle, opts, name)
  if not (CoopManager.wildTogether and on()) then return false end
  if not CoopManager.partnerAvailable(ow) then return false end
  battle.coopBeast = name
  if require("src.coop.CoopWild").invite(ow, battle, opts, { beast = name }) then
    CoopLog.info("BOSS", "asked the partner in against our " .. name)
    return true
  end
  battle.coopBeast = nil
  return false
end

-- a wild battle: true when it has been taken over here
function CoopBoss.offer(ow, battle, opts)
  if battle.coopHandled then return false end
  if battle.coopBoss then return offerBoss(ow, battle, opts) end
  local beast = CoopBoss.beastOf(battle)
  if beast then return offerBeast(ow, battle, opts, beast) end
  return false
end

-- ---------------------------------------------------------------------
-- the battle (both copies)
-- ---------------------------------------------------------------------

local function standing(b)
  return b and b.mon and (tonumber(b.mon.hp) or 0) > 0 and not b.fainted and not b.faintQueued
end

local function nameOf(battle, b)
  local mon = b and b.mon or {}
  local data = battle.data or (battle.game and battle.game.data) or {}
  local def = data.pokemon and mon.species and data.pokemon[mon.species]
  return tostring(mon.nickname or (b and b.name) or (def and def.name) or mon.species or "?"):upper()
end

local function scale(mon, mul, done)
  if type(mon) ~= "table" or done[mon] or type(mon.stats) ~= "table" then return end
  done[mon] = true
  local max = tonumber(mon.stats.hp) or 0
  if max <= 0 then return end
  local hp = tonumber(mon.hp) or max
  mon.stats.hp = math.floor(max * mul + 0.5)
  mon.hp = math.min(mon.stats.hp, math.floor(hp * mul + 0.5))
end

-- KNOCKED OUT TOGETHER, THE BEAST GETS AWAY (the catch rule above): the
-- host's own beast is never retired by a co-op battle; its HP goes back to
-- the save, at least 1
local function beastFinish(battle)
  local name = battle.roamer
  local beast = battle.enemyParty and battle.enemyParty[1]
  local orig = battle.onFinish
  battle.onFinish = function(result, ...)
    local hp = math.floor(tonumber(beast and beast.hp) or 0)
    battle.roamer = nil   -- the solo bookkeeping would retire it on a knock-out
    if orig then orig(result, ...) end
    local save = battle.game and battle.game.save
    local RoamMons = require("src.world.RoamMons")
    RoamMons.remember(save, name, math.max(1, hp))
    CoopLog.info("BOSS", string.format("%s left with %d HP (%s)", name, math.max(1, hp), tostring(result)))
    if hp <= 0 then CoopManager.showStatus(Strings("%s got away with 1 HP!", nameOf(battle, { mon = beast })), 4) end
  end
end

-- CoopBattle.initBattle, after the foes are set and balanced: true when the
-- foe stands alone on its side
function CoopBoss.setup(battle)
  if not (battle and (battle.coopBoss or battle.coopBeast)) then return false end
  local P = require("src.battle.BattleState").POS
  if battle.battlerAt and battle:battlerAt(P.OPPONENT_RIGHT) then battle:placeBattler(P.OPPONENT_RIGHT, nil) end
  if battle.coopBoss then
    local mul = CoopBoss.HP_MUL[battle.coopBoss] or 2
    local done = {}
    for _, m in ipairs(type(battle.enemyParty) == "table" and battle.enemyParty or {}) do scale(m, mul, done) end
    local b = (battle.battlerAt and battle:battlerAt(P.OPPONENT_LEFT)) or battle.enemy
    if b and b.mon then
      scale(b.mon, mul, done)
      b.shownHP = b.mon.hp
    end
    CoopManager.showStatus(Strings("Boss battle: it moves twice!"), 4)
  else
    if battle.roamer and not battle.isCoopGuest then beastFinish(battle) end
    local b = (battle.battlerAt and battle:battlerAt(P.OPPONENT_LEFT)) or battle.enemy
    CoopManager.showStatus(Strings("%s can't run from two!", nameOf(battle, b)), 4)
  end
  CoopLog.battle("BOSS", string.format("%s alone on its side (boss %s, beast %s)", tostring(battle.enemy
    and battle.enemy.mon and battle.enemy.mon.species), tostring(battle.coopBoss), tostring(battle.coopBeast)))
  return true
end

-- BattleState:sendOutSecondPair (lib/Hooks.lua): the right-hand foe slot
-- stays empty
function CoopBoss.alone(battle, sendOutSecondPair, ...)
  if not battle.coopDouble then return sendOutSecondPair(battle, ...) end
  local party = battle.enemyParty
  if type(party) == "table" then battle.enemyParty = { party[1] } end
  local ok, a, b, c = pcall(sendOutSecondPair, battle, ...)
  battle.enemyParty = party
  battle.enemyIndexRight = nil
  if not ok then error(a, 0) end
  return a, b, c
end

-- BattleState:resolveTurn (lib/Hooks.lua) queued this turn's moves after
-- `before`, the end of the turn last: the boss's second move goes in just
-- ahead of that
function CoopBoss.secondAction(battle, before)
  local q = battle.queue
  if type(q) ~= "table" or #q <= (before or 0) then return end
  table.insert(q, #q, { fn = function() CoopBoss.actAgain(battle) end })
end

function CoopBoss.actAgain(battle)
  if battle.result then return end
  local P = require("src.battle.BattleState").POS
  local b = battle:battlerAt(P.OPPONENT_LEFT)
  if not standing(b) then return end
  local foe = false
  for _, f in ipairs(battle.foesOf and battle:foesOf(b) or {}) do foe = foe or standing(f) end
  if not foe then return end
  local okD, DoublesAI = pcall(require, "src.battle.DoublesAI")
  if okD then DoublesAI.beginTurn(battle) end
  local action = battle:enemyAction(b)
  -- a second move, never a second switch or potion
  if type(action) == "table" and (action.special == "aiSwitch" or action.special == "aiItem") then
    action = require("src.battle.TrainerAI").chooseMove(b, battle.rng, battle)
  end
  if not action then return end
  local chosen = (battle.chosenTargets or {})[b.position]
  battle.coopBossMoves = (battle.coopBossMoves or 0) + 1
  battle:sayNext(Strings("%s moves\nagain!", nameOf(battle, b)))
  battle:actNext(function()
    if battle.result or not standing(b) then return end
    local Targeting = require("src.battle.Targeting")
    local target = Targeting.redirect(battle, b, nil, chosen)[1] or battle:defaultTargetFor(b)
    if target then battle:executeAction(b, target, action) end
  end)
end

-- ---------------------------------------------------------------------
-- the beasts in the POKEGEAR
-- ---------------------------------------------------------------------

CoopBoss.partnerBeasts = {}
CoopBoss.clock = 0

-- our beasts still roaming, in a fixed order
function CoopBoss.beastsOf(save)
  local out = {}
  local roam = type(save) == "table" and save.g2RoamReleased and save.g2Roam
  if type(roam) ~= "table" then return out end
  for _, name in ipairs({ "RAIKOU", "ENTEI", "SUICUNE" }) do
    local info = roam[name]
    if type(info) == "table" and info.active ~= false and tonumber(info.landmark) then
      out[#out + 1] = { n = name, s = info.speciesId, m = info.mapId, l = tonumber(info.landmark) }
    end
  end
  return out
end

local function signature(list)
  local parts = {}
  for _, e in ipairs(list) do parts[#parts + 1] = string.format("%s@%s/%s", e.n, tostring(e.m), tostring(e.l)) end
  return table.concat(parts, ";")
end

-- CoopManager.update: ours go out when they move, and again on a new link
function CoopBoss.tick(dt, game)
  if not (CoopManager.connected and on() and game and game.save) then return end
  CoopBoss.clock = CoopBoss.clock + (dt or 0)
  if CoopBoss.clock < CoopBoss.SEND_EVERY then return end
  CoopBoss.clock = 0
  local list = CoopBoss.beastsOf(game.save)
  local sig = signature(list)
  local to = CoopManager.partner and CoopManager.partner.caps
  if sig == CoopBoss.sentSig and to == CoopBoss.sentTo then return end
  CoopBoss.sentSig, CoopBoss.sentTo = sig, to
  send({ type = "coop_roam", beasts = list })
end

CoopManager.handlers.coop_roam = function(_, msg)
  local out = {}
  for i, e in ipairs(type(msg.beasts) == "table" and msg.beasts or {}) do
    if i > 3 then break end
    if type(e) == "table" and CoopBoss.BEASTS[e.n] and tonumber(e.l) then
      out[#out + 1] = { n = e.n, s = e.s, m = e.m, l = tonumber(e.l) }
    end
  end
  CoopBoss.partnerBeasts = out
end

local function iconFor(game, species)
  local data = game and game.data or {}
  local by = (data.icons and data.icons.bySpecies) or {}
  local entry = species and (by[species] or by[tostring(species):lower()])
  if type(entry) == "table" and entry.image then return entry.image end
  if type(entry) == "string" then return entry end
  local def = data.pokemon and species and data.pokemon[species]
  return type(def) == "table" and def.icon or nil
end

local icons = {}
local function loadIcon(path)
  if not path then return nil end
  if icons[path] == nil then
    local ok, img = pcall(function()
      return love.graphics.newImage(require("src.render.Assets").resolve(path))
    end)
    icons[path] = ok and img or false
  end
  return icons[path] or nil
end

-- the partner's beasts on the POKEGEAR's town map (CoopGear.drawMap):
-- where the beast's landmark is, beside ours when we have one there too
function CoopBoss.drawGear(menu)
  if not (on() and #CoopBoss.partnerBeasts > 0) then return end
  local game = menu.game
  local town = (game.data.field or {}).townMap or {}
  if type(town.landmarks) ~= "table" then return end
  local t = love.timer and love.timer.getTime() or 0
  if t % 1 > 0.66 then return end
  local mine = {}
  for _, e in ipairs(CoopBoss.beastsOf(game.save)) do mine[e.l] = true end
  local g = love.graphics
  for _, e in ipairs(CoopBoss.partnerBeasts) do
    local loc = town.landmarks[e.l] or town.landmarks[tostring(e.l)]
    if loc then
      local cx = (tonumber(loc.x) or 0) - 4 + (mine[e.l] and 6 or 0)
      local cy = (tonumber(loc.y) or 0) - 12 + (mine[e.l] and 2 or 0)
      g.setColor(0.55, 0.8, 1, 1)
      g.rectangle("line", cx - 9, cy - 9, 18, 18)
      local img = loadIcon(iconFor(game, e.s))
      if img then
        g.setColor(1, 1, 1, 1)
        local iw, ih = img:getDimensions()
        if ih >= 32 and iw <= 16 then
          g.draw(img, g.newQuad(0, 0, iw, 16, iw, ih), cx - 8, cy - 8)
        else
          g.draw(img, cx - 8, cy - 8, 0, math.min(16 / iw, 16 / ih), math.min(16 / iw, 16 / ih))
        end
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

return CoopBoss
