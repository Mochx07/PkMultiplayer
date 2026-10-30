-- src/coop/CoopBattle.lua
-- Co-op double battles for Gen2Recomped.
--
-- LOCKSTEP.  Each player runs the same trainer battle on their own machine:
-- their own Pokemon in PLAYER_LEFT, the partner's in PLAYER_RIGHT.  A turn
-- resolves only when both actions for THAT turn are in hand, and both sides
-- re-seed the shared RNG from (battle seed, turn) right before resolving, so
-- the dice agree even if an earlier turn drifted.
--
-- Actions cross the wire as plain descriptions, never as the engine's own
-- tables: a move is its slot in the partner's move list, a switch is an index
-- into the three chosen Pokemon, positions are mirrored (my LEFT is your
-- RIGHT).  Sending the live move/mon tables used to hand the receiver a
-- detached copy, so PP never moved and a switched-in partner duplicated.
--
-- The host is authoritative for HP and the result: it reports both after
-- every turn and when the battle ends, and the guest corrects itself between
-- turns (never mid-animation).
--
-- If the partner drops or leaves, their Pokemon is handed to the ally AI and
-- the battle carries on; nobody is left waiting forever.  That is the ONLY
-- way the AI takes a partner's place: an emergency, never a menu choice --
-- a partner who is still connected and thinking is waited for.

local Font = require("src.coop.CoopI18n").font()
local CoopLog = require("src.coop.CoopLog")
local Strings = require("src.core.Strings")

local CoopBattle = {}

CoopBattle.active = false
CoopBattle.currentBattle = nil
CoopBattle.localAction = nil
CoopBattle.partnerAction = nil
CoopBattle.waitingForPartner = false
CoopBattle.waitTimer = 0
CoopBattle.fallbackAllowed = false

CoopBattle.LINK_GRACE = 180.0      -- a dropped link gets this long to come back mid-battle
CoopBattle.RESUME_WAIT = 10.0      -- after a reconnect, how long the partner has to say it is still in the battle
CoopBattle.RESULT_GRACE = 6.0      -- guest finishes on its own this long after the host did
CoopBattle.REPLACE_WAIT = 30.0     -- a fallen partner slot waits this long only once the link is gone
-- true = every fallen slot takes the first healthy Pokemon without asking
-- (both copies agree by construction); the headless lockstep suite sets it
CoopBattle.AUTO_REPLACE = false

-- actions that arrive before their battle exists (keyed by invite id); only
-- the newest few battles are kept
CoopBattle.early = {}
CoopBattle.EARLY_MAX = 4
-- how far ahead of ours a partner's turn can be (they wait for us)
CoopBattle.TURN_AHEAD_MAX = 2
-- turns whose copies disagreed and were put right from the host's word
CoopBattle.desyncs = 0

local POS = { PLAYER_LEFT = 0, OPPONENT_LEFT = 1, PLAYER_RIGHT = 2, OPPONENT_RIGHT = 3 }

local function BattleStatePos()
  local ok, BattleState = pcall(require, "src.battle.BattleState")
  return (ok and BattleState and BattleState.POS) or POS
end

local function manager()
  local ok, CoopManager = pcall(require, "src.coop.CoopManager")
  if ok then return CoopManager end
  return nil
end

local function linked()
  local CM = manager()
  return CM and CM.net and CM.isConnected and CM.isConnected()
end

-- A reconnecting session keeps what we send and delivers it, once, when the
-- link resumes (CoopNet): a turn, a pick after a faint or the host's sync
-- sent into a dropped link is not lost any more, and nobody waits for ever
-- on a message that died with the old connection.
local function send(msg)
  local CM = manager()
  local net = CM and CM.net
  if not net or net.closed then return end
  if CM.connected or net.sessionActive then net:send(msg) end
end

-- ---------------------------------------------------------------------
-- deterministic RNG (Park-Miller).  Pure Lua and exact in doubles, so two
-- machines given the same seed produce the same sequence regardless of
-- platform or LÖVE build.
-- ---------------------------------------------------------------------

local MOD = 2147483647

local function mixSeed(seed, turn)
  local s = (math.floor(tonumber(seed) or 1) * 7919 + (turn or 0) * 104729 + 13) % MOD
  if s <= 0 then s = s + MOD - 1 end
  return s
end
CoopBattle.mixSeed = mixSeed

local function newRng(seed)
  local state = { x = mixSeed(seed, 0) }
  local function nextUnit()
    state.x = (state.x * 48271) % MOD
    return state.x / MOD
  end
  local fn = function(a, b)
    local r = nextUnit()
    if a and b then
      if b < a then a, b = b, a end
      return a + math.floor(r * (b - a + 1))
    end
    if a then return 1 + math.floor(r * a) end
    return r
  end
  return fn, state
end
CoopBattle.newRng = newRng

local function reseed(battle, turn)
  local c = battle.coop
  if c and c.rngState then
    c.rngState.x = mixSeed(c.seed, turn)
  end
end

-- ---------------------------------------------------------------------
-- action encoding
-- ---------------------------------------------------------------------

local function mirror(pos)
  pos = tonumber(pos)
  if pos == POS.PLAYER_LEFT then return POS.PLAYER_RIGHT end
  if pos == POS.PLAYER_RIGHT then return POS.PLAYER_LEFT end
  return pos
end
CoopBattle.mirror = mirror

local function indexOf(list, item)
  for i, v in ipairs(list or {}) do
    if v == item then return i end
  end
  return nil
end

function CoopBattle.encodeAction(battle, action, opts)
  if opts and opts.locked then return { kind = "locked" } end
  if action == nil then return { kind = "spectator" } end
  if type(action) ~= "table" then return { kind = "locked" } end
  if action.special == "playerSwitch" then
    return { kind = "switch", index = indexOf(battle.coopChosenMons, action.mon),
             species = action.mon and action.mon.species }
  end
  if action.special == "playerItem" then
    return { kind = "item", id = action.id, targetNick = action.targetNick,
             messages = action.messages, heal = action.heal, boost = action.boost }
  end
  if action.special then return { kind = "locked" } end
  local P = BattleStatePos()
  local user = battle.battlerAt and battle:battlerAt(P.PLAYER_LEFT)
  return {
    kind = "move",
    id = action.id,
    slot = user and indexOf(user.curMoves, action),
    struggle = action.struggle or nil,
    target = action.targetPosition,
  }
end

-- Turn a partner's wire action into what the engine wants for the ally
-- slot.  nil means "let the engine decide" (locked move, nobody on the field).
function CoopBattle.decodeAction(battle, w)
  if type(w) ~= "table" then return nil end
  local P = BattleStatePos()
  local ally = battle.battlerAt and battle:battlerAt(P.PLAYER_RIGHT)
  if w.kind == "move" then
    if not ally then return nil end
    local moves = ally.curMoves or {}
    local mv = w.slot and moves[w.slot]
    if not mv or mv.id ~= w.id then
      mv = nil
      for _, m in ipairs(moves) do
        if m.id == w.id then mv = m break end
      end
    end
    if w.struggle or not mv then
      mv = { id = w.id or "STRUGGLE", pp = 1, struggle = w.struggle or (w.id == "STRUGGLE") or nil }
    end
    mv.targetPosition = w.target and mirror(w.target) or nil
    return mv
  elseif w.kind == "switch" then
    local party = (battle.ally and battle.ally.party) or {}
    local mon = w.index and party[w.index]
    -- the same-species search is only for an index this copy does not have:
    -- never the Pokemon already standing in the partner's slot.  A fainted
    -- one at the index stays the answer -- executeAction sends nobody in for
    -- it, which is what the partner's own copy does with the same switch;
    -- answering nil here would hand the slot to the ally AI on this copy only
    if not mon and w.species then
      local out = ally and ally.mon
      for _, m in ipairs(party) do
        if m.species == w.species and (m.hp or 0) > 0 and m ~= out then mon = m break end
      end
    end
    if mon then return { special = "playerSwitch", mon = mon } end
    return nil
  elseif w.kind == "item" then
    return { special = "playerItem", id = w.id, targetNick = w.targetNick, messages = w.messages,
             heal = type(w.heal) == "table" and w.heal or nil,
             boost = type(w.boost) == "table" and w.boost or nil }
  end
  return nil
end

-- WHAT THE PARTNER IS GOING TO DO.  Requested from play: "you should know
-- which attack the other player is going to use", "and don't forget items".
-- Their choice for this turn is already here once they have made it (their
-- coop_battle_action), so while this player picks, the empty box left of
-- the action menu says it: their move and its target, the Pokemon they
-- switch to, the item and who it is for -- or that they are still choosing.
-- Lines: their name, then up to two of detail; nil when there is nothing
-- to say (no partner in the battle, or the AI plays for them).
function CoopBattle.partnerPlan(battle)
  local c = battle and battle.coop
  if not c or c.partnerLost or c.finished or not battle.battlerAt then return nil end
  local P = BattleStatePos()
  local ally = battle:battlerAt(P.PLAYER_RIGHT)
  if not ally then return nil end
  local CM = manager()
  local who = string.upper(tostring((CM and CM.partner and CM.partner.name) or "PARTNER"))
  local okI, I18n = pcall(require, "src.coop.CoopI18n")
  local function t(text) return okI and I18n.t(text) or text end
  local okS, Strings = pcall(require, "src.core.Strings")
  local function game(text) -- the game's own names, in the game's language
    if okS and Strings.lookup and type(text) == "string" then return Strings.lookup(text) or text end
    return text
  end
  local data = battle.data or (battle.game and battle.game.data) or {}
  local w = c.partnerActions and c.partnerActions[c.turn]
  if not w then
    if c.partnerInBag then
      return { who, t("IN BAG..."), t("CHOOSING...") }
    end
    return { who, t("CHOOSING...") }
  end
  if w.kind == "move" then
    local def = data.moves and data.moves[w.id]
    local name = game(def and def.name or tostring(w.id or "?"))
    local target = w.target and battle:battlerAt(mirror(w.target))
    local tname = nil
    if target then
      if target == ally then
        tname = t("SELF")
      elseif target.position == P.PLAYER_LEFT then
        tname = target and game(target.name or (target.mon and target.mon.species)) or t("YOU")
      else
        tname = target and game(target.name or (target.mon and target.mon.species)) or nil
        local op1 = battle:battlerAt(P.OPPONENT_LEFT)
        local op2 = battle:battlerAt(P.OPPONENT_RIGHT)
        local n1 = op1 and game(op1.name or (op1.mon and op1.mon.species))
        local n2 = op2 and game(op2.name or (op2.mon and op2.mon.species))
        if n1 and n2 and n1 == n2 and not (op1.fainted or op1.faintQueued) and not (op2.fainted or op2.faintQueued) then
          if target.position == P.OPPONENT_LEFT then
            tname = (tname or "") .. " 1"
          elseif target.position == P.OPPONENT_RIGHT then
            tname = (tname or "") .. " 2"
          end
        end
      end
    else
      local okT, Targeting = pcall(require, "src.battle.Targeting")
      local k = okT and Targeting and def and Targeting.kindOf and Targeting.kindOf(def)
      if k == (Targeting and Targeting.USER) then
        tname = t("SELF")
      elseif k == (Targeting and Targeting.BOTH) then
        tname = t("ALL FOES")
      elseif k == (Targeting and Targeting.FOES_AND_ALLY) then
        tname = t("EVERYONE")
      end
    end
    return { who, name, tname and ("> " .. tname) or nil }
  elseif w.kind == "switch" then
    local mon = w.index and battle.ally and battle.ally.party and battle.ally.party[w.index]
    local def = mon and data.pokemon and data.pokemon[mon.species]
    local name = (mon and mon.nickname) or (def and game(def.name)) or tostring(w.species or "?")
    return { who, t("SWITCH TO"), "> " .. name }
  elseif w.kind == "item" then
    local def = data.items and data.items[w.id]
    local name = game(def and def.name or tostring(w.id or "?"))
    local tname = w.targetNick and game(w.targetNick) or nil
    if not tname then
      local boost = w.boost
      if boost and boost.flute then
        tname = t("EVERYONE")
      else
        tname = t("SELF")
      end
    end
    return { who, name, tname and ("> " .. tname) or nil }
  elseif w.kind == "locked" then
    return { who, t("SAME MOVE") }
  end
  return nil
end

-- the small font has capitals, digits and a few signs: the rest is folded
local FOLD = { ["Á"] = "A", ["É"] = "E", ["Í"] = "I", ["Ó"] = "O", ["Ú"] = "U", ["Ñ"] = "N", ["Ü"] = "U",
               ["á"] = "A", ["é"] = "E", ["í"] = "I", ["ó"] = "O", ["ú"] = "U", ["ñ"] = "N", ["ü"] = "U" }
local function micro(text)
  text = tostring(text):gsub("[\195][\128-\191]", function(ch) return FOLD[ch] or "" end)
  -- anything else outside plain ASCII (a game's own space, a symbol) is a space
  text = text:gsub("[\128-\255]+", " "):gsub("  +", " ")
  return text:upper()
end

-- in the box left of FIGHT / PKMN / ITEM / RUN (x 8..64, y 104..136)
function CoopBattle.drawPartnerPlan(battle)
  if not (battle and battle.coopDouble and battle.phase == "menu") then return end
  local lines = CoopBattle.partnerPlan(battle)
  if not lines then return end
  local MicroFont = require("src.render.MicroFont")
  love.graphics.setColor(0, 0, 0, 1)
  local c = battle.coop
  local inBag = c and c.partnerInBag
  local nameWidth = inBag and 44 or 56
  Font.raw.draw(Font.raw.fit and Font.raw.fit(lines[1], nameWidth) or lines[1]:sub(1, inBag and 6 or 7), 8, 104)
  if inBag then
    love.graphics.rectangle("fill", 56, 107, 6, 4)
    love.graphics.rectangle("line", 57, 104, 4, 3)
  end
  for i = 2, 3 do
    local l = lines[i]
    if l then
      l = micro(l)
      while #l > 1 and MicroFont.width(l) > 56 do l = l:sub(1, -2) end
      MicroFont.draw(l, 8, 106 + (i - 1) * 9)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------
-- the owner's word on their own Pokemon
--
-- Experience is paid on the owner's machine only: a level-up raises the
-- owner's stats and current HP, and the partner's copy never hears of it, so
-- from that turn on the two battles computed different damage.  Every action
-- therefore carries the sender's three Pokemon as they stand right now, and
-- the receiver writes that onto its copies just before the turn resolves --
-- at which point both machines hold the same numbers.
-- ---------------------------------------------------------------------

function CoopBattle.packOwnState(battle)
  local out = {}
  for i, mon in ipairs(battle.coopChosenMons or {}) do
    if type(mon) == "table" then
      local moves = {}
      for j, mv in ipairs(mon.moves or {}) do
        moves[j] = { id = mv.id, pp = mv.pp }
      end
      out[i] = {
        species = mon.species, level = mon.level, exp = mon.exp,
        hp = mon.hp, status = mon.status,
        stats = mon.stats, statExp = mon.statExp,
        moves = moves,
      }
    else
      out[i] = false
    end
  end
  return out
end

local function statsDiffer(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return true end
  for k, v in pairs(b) do
    if a[k] ~= v then return true end
  end
  return false
end

function CoopBattle.applyPartnerState(battle, state)
  if type(state) ~= "table" then return end
  local party = battle.ally and battle.ally.party
  if type(party) ~= "table" then return end
  for i, st in ipairs(state) do
    local copy = party[i]
    if type(copy) == "table" and type(st) == "table" and copy.species == st.species then
      copy.level = st.level or copy.level
      copy.exp = st.exp or copy.exp
      if type(st.statExp) == "table" then copy.statExp = st.statExp end
      -- a NEW table, the way a level-up replaces it: an active battler keeps
      -- reading the table it was built with, on the owner's machine too
      if type(st.stats) == "table" and statsDiffer(copy.stats, st.stats) then
        copy.stats = st.stats
      end
      if tonumber(st.hp) then copy.hp = st.hp end
      copy.status = st.status
      if type(st.moves) == "table" then
        copy.moves = copy.moves or {}
        for j, mv in ipairs(st.moves) do
          local cur = copy.moves[j]
          if type(cur) == "table" then
            cur.id, cur.pp = mv.id, mv.pp
          else
            copy.moves[j] = { id = mv.id, pp = mv.pp }
          end
        end
        for j = #copy.moves, #st.moves + 1, -1 do table.remove(copy.moves, j) end
      end
    end
  end
  local P = BattleStatePos()
  local b = battle.battlerAt and battle:battlerAt(P.PLAYER_RIGHT)
  if b and b.mon and b.shownHP and battle.phase ~= "messages" then b.shownHP = b.mon.hp end
  if battle.syncShownStatus then pcall(battle.syncShownStatus, battle) end
end

-- ---------------------------------------------------------------------
-- items used from the bag, on either player's Pokemon
--
-- The bag works on this copy the moment the player picks the target, and
-- that used to be sent across at once -- landing on the partner's copy
-- whenever it arrived, which could be in the middle of their screen still
-- playing out the turn before.  It now rides with this turn's action and
-- both copies write it in as the turn opens (executeTurn).
--
-- What it carries is the Pokemon AFTER the item, merged the one way an item
-- can move it -- HP up, a status or confusion gone, PP up -- so a heal from
-- each player on the same Pokemon in the same turn ends the same on both.
-- `side` is the sender's: "own" (their three) or "ally" (the partner's).
-- ---------------------------------------------------------------------

local function battlerOf(battle, mon)
  for p = 0, 3 do
    local b = battle.battlerAt and battle:battlerAt(p)
    if b and b.mon == mon then return b end
  end
  return nil
end

function CoopBattle.itemHeal(battle, mon)
  if type(mon) ~= "table" then return nil end
  local side, index = "own", indexOf(battle.coopChosenMons, mon)
  if not index then
    side, index = "ally", indexOf(battle.ally and battle.ally.party, mon)
  end
  if not index then return nil end
  local pp = {}
  for j, mv in ipairs(mon.moves or {}) do pp[j] = mv.pp end
  local b = battlerOf(battle, mon)
  return { side = side, index = index, species = mon.species, hp = mon.hp,
           status = mon.status or false, pp = pp,
           confused = b and (b.confusedTurns ~= nil) or nil }
end

-- `mine`: the Pokemon is this copy's own (one of coopChosenMons)
function CoopBattle.applyItemHeal(battle, heal, mine)
  if type(heal) ~= "table" then return end
  local list = mine and battle.coopChosenMons or (battle.ally and battle.ally.party)
  local mon = type(list) == "table" and list[tonumber(heal.index) or 0]
  if type(mon) ~= "table" or (heal.species and mon.species ~= heal.species) then return end
  local hp = tonumber(heal.hp)
  if hp and hp > (tonumber(mon.hp) or 0) then mon.hp = hp end
  if heal.status == false then mon.status = nil end
  if type(heal.pp) == "table" then
    for j, v in ipairs(heal.pp) do
      local mv = mon.moves and mon.moves[j]
      if mv and tonumber(v) and v > (mv.pp or 0) then mv.pp = v end
    end
  end
  local b = battlerOf(battle, mon)
  if b then
    b.status = mon.status
    if heal.confused == false then b.confusedTurns = nil end
    if b.shownHP then b.shownHP = mon.hp end
  end
  if battle.syncShownStatus then pcall(battle.syncShownStatus, battle) end
end

-- An X item, DIRE HIT or GUARD SPEC. works on the user's own battler the
-- moment it is picked, on this copy only; what it left behind rides with the
-- action and the partner's copy writes it onto its ally slot as the turn
-- opens.  The POKé FLUTE carries `flute` and wakes the whole field on both.
function CoopBattle.itemBoost(battle)
  local P = BattleStatePos()
  local b = battle.battlerAt and battle:battlerAt(P.PLAYER_LEFT)
  if not (b and b.mon) then return nil end
  local stages = {}
  for k, v in pairs(b.stages or {}) do stages[k] = v end
  return { species = b.mon.species, stages = stages, xAccuracy = b.xAccuracy and true or false,
           focusEnergy = b.focusEnergy and true or false, mist = b.mist and true or false }
end

local function wakeAll(battle)
  local function wake(mon)
    if type(mon) == "table" and mon.status == "SLP" then mon.status = nil end
  end
  for p = 0, 3 do
    local b = battle.battlerAt and battle:battlerAt(p)
    if b and b.mon then
      wake(b.mon)
      if b.status == "SLP" then b.status = nil end
    end
  end
  for _, list in ipairs({ battle.coopChosenMons or {}, (battle.ally and battle.ally.party) or {},
                          battle.enemyParty or {} }) do
    for _, mon in ipairs(list) do wake(mon) end
  end
  if battle.syncShownStatus then pcall(battle.syncShownStatus, battle) end
end

-- `mine`: the boost is this copy's own (already on its battler)
function CoopBattle.applyItemBoost(battle, boost, mine)
  if type(boost) ~= "table" then return end
  if boost.flute then wakeAll(battle) end
  if mine or type(boost.stages) ~= "table" then return end
  local P = BattleStatePos()
  local b = battle.battlerAt and battle:battlerAt(P.PLAYER_RIGHT)
  if not (b and b.mon) or (boost.species and b.mon.species ~= boost.species) then return end
  b.stages = b.stages or {}
  for k, v in pairs(boost.stages) do
    if tonumber(v) then b.stages[k] = v end
  end
  b.xAccuracy = boost.xAccuracy or nil
  b.focusEnergy = boost.focusEnergy or nil
  b.mist = boost.mist or nil
end

-- A REVIVE on a player whose whole team was down leaves their slot empty
-- with a Pokemon able to fight again on the bench.  Nothing would ever send
-- it in -- replacements are only asked for as a Pokemon faints -- so the
-- revive did nothing.  Both copies look as the turn opens, after the heals,
-- and queue the slot: at the end of the turn its owner picks who goes in and
-- the other copy waits for that pick, the same as after a faint.
function CoopBattle.queueRevivedSlots(battle)
  local P = BattleStatePos()
  for _, pos in ipairs({ P.PLAYER_LEFT, P.PLAYER_RIGHT }) do
    if battle.battlerAt and battle:battlerAt(pos) == nil then
      local list = (pos == P.PLAYER_LEFT) and battle.coopChosenMons or (battle.ally and battle.ally.party)
      local able = false
      for _, mon in ipairs(type(list) == "table" and list or {}) do
        if type(mon) == "table" and (mon.hp or 0) > 0 and not mon.isEgg then able = true break end
      end
      local queued = false
      for _, q in ipairs(battle.pendingReplacements or {}) do
        if q == pos then queued = true end
      end
      if able and not queued then
        battle.pendingReplacements = battle.pendingReplacements or {}
        battle.pendingReplacements[#battle.pendingReplacements + 1] = pos
        CoopLog.battle("REVIVE_SLOT", "slot " .. tostring(pos) .. " can fight again")
      end
    end
  end
end

-- ---------------------------------------------------------------------
-- setup
-- ---------------------------------------------------------------------

local function cloneMon(m)
  if type(m) ~= "table" then return nil end
  local seen = {}
  local function copy(v, depth)
    if type(v) ~= "table" then return v end
    if seen[v] or depth > 6 then return nil end
    seen[v] = true
    local out = {}
    for k, val in pairs(v) do out[k] = copy(val, depth + 1) end
    seen[v] = nil
    return out
  end
  return copy(m, 0)
end

-- THE HOST'S RULES ON BOTH COPIES.  The battle ruleset (gen1_faithful,
-- modern_clean...) is each player's own option, and the two copies of a
-- co-op double ran under their own: from turn 1 they worked out different
-- damage, and under gen1_faithful the foes spend no PP (log 2026-10-28: the
-- host's foes kept 15 PP all battle, the guest's did not, and every turn
-- had to be corrected).  The invite carries the host's ruleset by name and
-- the guest's copy takes it before the first turn.
function CoopBattle.rulesetName(battle)
  return battle and battle.ruleset and battle.ruleset.name or nil
end

function CoopBattle.useRuleset(battle, name)
  if not battle or type(name) ~= "string" or name == "" then return end
  if battle.ruleset and battle.ruleset.name == name then return end
  local data = (battle.game and battle.game.data) or battle.data
  local rs = data and type(data.rulesets) == "table" and data.rulesets[name] or nil
  if not rs then
    local ok, mod = pcall(require, "src.battle.rulesets." .. name)
    if ok and type(mod) == "table" then rs = mod end
  end
  if not rs then
    CoopLog.warn("BATTLE", "the host's ruleset " .. name .. " is not known here; keeping "
                 .. tostring(CoopBattle.rulesetName(battle)))
    return
  end
  CoopLog.battle("RULESET", string.format("using the host's %s (ours was %s)", name,
                 tostring(CoopBattle.rulesetName(battle))))
  battle.ruleset = rs
end

function CoopBattle.initBattle(battle, localChosenMons, partnerChosenMons, partnerInfo, seed, inviteId)
  -- READY / NOT READY was about this battle: both start over
  local CM = package.loaded["src.coop.CoopManager"]
  if CM and CM.clearReady then CM.clearReady() end
  -- the result screen's tally (src/coop/CoopSummary.lua)
  local okS, CoopSummary = pcall(require, "src.coop.CoopSummary")
  if okS and CoopSummary.begin then pcall(CoopSummary.begin, battle) end
  if not battle then return end

  CoopLog.battle("INIT", "Co-op double with " .. tostring(partnerInfo and partnerInfo.name)
                 .. " seed=" .. tostring(seed) .. " invite=" .. tostring(inviteId))
  CoopBattle.active = true
  CoopBattle.currentBattle = battle
  CoopBattle.localAction = nil
  CoopBattle.partnerAction = nil
  CoopBattle.waitingForPartner = false
  CoopBattle.waitTimer = 0
  CoopBattle.fallbackAllowed = false

  battle.double = true
  battle.coopDouble = true
  battle.coopChosenMons = localChosenMons
  battle.coopPartnerAction = nil

  local rng, rngState = newRng(seed or 1)
  battle.rng = rng
  battle.coop = {
    seed = seed or 1,
    rngState = rngState,
    inviteId = inviteId,
    turn = 1,
    partnerActions = {},
    partnerStates = {},
    replaceQueue = {},     -- partner's replacement picks, in the order made
    localTurnAction = nil,
    localReady = false,
    partnerLost = false,
    waitTime = 0,
    pendingSync = nil,
    hostResult = nil,
    hostResultAt = nil,
    linkLostAt = nil,
    finished = false,
  }
  local early = inviteId and CoopBattle.early[inviteId]
  if early then
    for turn, e in pairs(early) do
      battle.coop.partnerActions[turn] = e.action
      battle.coop.partnerStates[turn] = e.state
    end
    CoopBattle.early[inviteId] = nil
  end

  local BattleState = require("src.battle.BattleState")
  local data = (battle.game and battle.game.data) or battle.data
  local save = (battle.game and battle.game.save) or battle.save
  local canMakeBattler = BattleState.makeBattler and battle.placeBattler and data and data.pokemon

  local function place(pos, mon, isPlayer, saveRef, isAlly)
    local ok, err = pcall(function()
      local b = BattleState.makeBattler(data, mon, isPlayer, saveRef)
      if isAlly then b.ally = true end
      battle:placeBattler(pos, b)
    end)
    if not ok then CoopLog.error("BATTLE", "placeBattler " .. tostring(pos) .. " failed: " .. tostring(err)) end
  end

  if localChosenMons and localChosenMons[1] and canMakeBattler then
    place(BattleState.POS.PLAYER_LEFT, localChosenMons[1], true, save, false)
  end

  local allyParty = partnerChosenMons or {}
  battle:setAlly({
    party = allyParty,
    name = (partnerInfo and partnerInfo.name) or "PARTNER",
    pic = partnerInfo and partnerInfo.sprite,
    remote = true,
  })
  if allyParty[1] and canMakeBattler then
    place(BattleState.POS.PLAYER_RIGHT, allyParty[1], true, nil, true)
  end

  -- WILD TOGETHER: a wild Pokemon is a one-Pokemon party, mirrored below
  pcall(function() require("src.coop.CoopWild").prepare(battle) end)

  -- CO-OP DIFFICULTY: the foe's team made a match for the two of you
  -- (CoopBalance; the same on both copies)
  local okBal, CoopBalance = pcall(require, "src.coop.CoopBalance")
  if okBal and CoopBalance.apply(battle, localChosenMons, allyParty) and canMakeBattler
     and battle.enemyParty[1] then
    place(BattleState.POS.OPPONENT_LEFT, battle.enemyParty[1], false, nil, false)
  end

  -- Enemy side: a trainer with 2+ Pokemon sends its second one out beside
  -- the first; a lone Pokemon is mirrored so the field is 2 v 2.
  if battle.enemyParty and #battle.enemyParty >= 2 and canMakeBattler then
    place(BattleState.POS.OPPONENT_RIGHT, battle.enemyParty[2], false, nil, false)
    battle.enemyIndexRight = 2
  elseif battle.enemyParty and battle.enemyParty[1] then
    local secondMon = cloneMon(battle.enemyParty[1])
    if secondMon then
      secondMon.hp = (secondMon.stats and secondMon.stats.hp) or secondMon.maxHp or secondMon.hp or 20
      battle.enemyParty = { battle.enemyParty[1], secondMon }
      if canMakeBattler then
        place(BattleState.POS.OPPONENT_RIGHT, secondMon, false, nil, false)
        battle.enemyIndexRight = 2
      end
    end
  end

  pcall(function() battle:sendOutSecondPair() end)
  if battle.syncSides then battle:syncSides() end

  local origFinish = battle.onFinish
  battle.onFinish = function(result)
    local c = battle.coop
    -- finish() pops the battle and only calls this after the return fade, so
    -- the guard is its own flag: "finished" alone can already be set by then
    if c and c.onFinishDone then return end
    if c then
      c.onFinishDone = true
      c.finished = true
    end
    if CoopBattle.currentBattle == battle then
      CoopBattle.active = false
      CoopBattle.currentBattle = nil
      CoopBattle.localAction = nil
      CoopBattle.partnerAction = nil
      CoopBattle.waitingForPartner = false
      CoopBattle.fallbackAllowed = false
    end
    CoopLog.battle("FINISH", "Co-op battle ended with result: " .. tostring(result))

    -- host tells the guest how it ended, so a guest whose copy drifted still
    -- ends the same way
    if not battle.isCoopGuest and c and not c.partnerLost then
      send({ type = "coop_battle_sync", inviteId = c.inviteId, turn = c.turn - 1,
             result = result, final = true })
    end

    if origFinish then origFinish(result) end
  end
end

-- ---------------------------------------------------------------------
-- after the battle
--
-- WHAT A WON CO-OP DOUBLE LEAVES YOUR TEAM IN.  Gemini's version revived
-- every fainted Pokemon to 1 HP and wiped every status after any win, which
-- no Pokemon game does.  The rules are the cartridges':
--
--   * Gen 2 (the default): fainted Pokemon stay fainted, statuses stay, the
--     way any won battle leaves them.  The one exception keeps the win a
--     win: if NONE of your Pokemon can still fight -- your partner carried
--     the battle -- the first of your three gets back up with 1 HP instead of
--     the finish() check whiting you out after a victory.
--   * "PARTNER HEALS" (CoopManager.partnerHeals, the co-op menu): Sinnoh's
--     rule for battles fought beside a partner -- encounter.c heals the
--     party after every battle that was not lost (Cheryl, Mira, Riley...),
--     already used here for Platinum's escorts (afterBattle, gen4Escorted).
--
-- A LOST co-op double (both teams down) is an ordinary blackout for each
-- player: half the money, back to the last POKEMON CENTER, the trainer
-- still waiting.  A battle the script lets you lose (the Cherrygrove rival)
-- is not, on either screen.
--
-- Returns a line for the battle box when the exception fired, else nil.
-- ---------------------------------------------------------------------

function CoopBattle.afterWinRules(battle)
  local save = battle.game and battle.game.save
  if not save then return nil end
  local own = battle.coopChosenMons or save.party or {}
  local CM = manager()
  if CM and CM.partnerHeals then
    local Pokemon = require("src.pokemon.Pokemon")
    for _, mon in ipairs(own) do pcall(Pokemon.heal, mon) end
    return Strings("%s healed\nyour POKéMON!", (CM.partner and CM.partner.name) or "PARTNER")
  end
  local Party = require("src.pokemon.Party")
  if Party.firstHealthy(save.party or {}) then return nil end
  for _, mon in ipairs(own) do
    if type(mon) == "table" and not mon.isEgg then
      mon.hp = 1
      mon.status = nil
      local name = mon.nickname or (battle.data and battle.data.pokemon and battle.data.pokemon[mon.species]
                                   and battle.data.pokemon[mon.species].name) or mon.species
      return Strings("%s got back\nup with 1 HP!", tostring(name))
    end
  end
  return nil
end

-- ---------------------------------------------------------------------
-- turn flow-- ---------------------------------------------------------------------
-- turn flow
-- ---------------------------------------------------------------------

local function isSpectator(battle)
  local P = BattleStatePos()
  return not (battle.battlerAt and battle:battlerAt(P.PLAYER_LEFT))
end

local function setWaiting(battle, on)
  CoopBattle.waitingForPartner = on and true or false
  if on then
    battle.phase = "waitPartner"
  end
end

local function standing(b)
  return b and b.mon and (tonumber(b.mon.hp) or 0) > 0 and not b.fainted and not b.faintQueued
end

local function usable(mon, taken)
  if type(mon) ~= "table" or taken[mon] or (tonumber(mon.hp) or 0) <= 0 then return false end
  if mon.isEgg or (tonumber(mon.eggSteps) or 0) > 0 then return false end
  return true
end

function CoopBattle.executeTurn(battle)
  local c = battle and battle.coop
  if not c or c.finished or (battle and battle.result) then return end
  local turn = c.turn
  local localAction = c.localTurnAction
  local wire = c.partnerActions[turn]
  local partnerState = c.partnerStates[turn]

  c.partnerActions[turn] = nil
  c.partnerStates[turn] = nil
  c.localTurnAction = nil
  c.localReady = false
  c.waitTime = 0
  c.turn = turn + 1
  c.partnerInBag = nil
  c.localInBag = nil
  CoopBattle.localAction = nil
  CoopBattle.partnerAction = nil
  CoopBattle.fallbackAllowed = false
  setWaiting(battle, false)

  if not c.partnerLost and partnerState then
    CoopBattle.applyPartnerState(battle, partnerState)
    CoopBattle.alignPartnerSlot(battle)
  end
  battle.coopPartnerAction = (not c.partnerLost) and CoopBattle.decodeAction(battle, wire) or nil
  -- this turn's bag heals, host's first on both copies.  Ours on the
  -- partner's Pokemon goes in again after their state was written over it;
  -- theirs is "own" = our ally's, or "ally" = ours.
  local mineH = type(localAction) == "table" and localAction.heal or nil
  local theirsH = battle.coopPartnerAction and battle.coopPartnerAction.heal or nil
  local function ours() if mineH and mineH.side == "ally" then CoopBattle.applyItemHeal(battle, mineH, false) end end
  local function theirs() if theirsH then CoopBattle.applyItemHeal(battle, theirsH, theirsH.side == "ally") end end
  if battle.isCoopGuest then theirs() ours() else ours() theirs() end
  -- X items and the flute, the same way: ours is already on our battler
  local mineB = type(localAction) == "table" and localAction.boost or nil
  local theirsB = battle.coopPartnerAction and battle.coopPartnerAction.boost or nil
  if battle.isCoopGuest then
    CoopBattle.applyItemBoost(battle, theirsB, false) CoopBattle.applyItemBoost(battle, mineB, true)
  else
    CoopBattle.applyItemBoost(battle, mineB, true) CoopBattle.applyItemBoost(battle, theirsB, false)
  end
  CoopBattle.queueRevivedSlots(battle)
  if CoopBattle.guardEmptySide(battle) then return end
  local P = BattleStatePos()
  local oppLeft = battle:battlerAt(P.OPPONENT_LEFT)
  local oppRight = battle:battlerAt(P.OPPONENT_RIGHT)
  if not standing(oppLeft) and not standing(oppRight) and battle.sideCanContinue and not battle:sideCanContinue(false) then
    CoopLog.warn("BATTLE", "no opposing Pokemon standing or on bench; the battle is won")
    CoopBattle.forceFinishBattle(battle, "win")
    return
  end
  reseed(battle, turn)
  CoopLog.battle("TURN", string.format("resolve turn %d (partner %s)", turn,
                 c.partnerLost and "AI" or tostring(wire and wire.kind)))
  local ok, err = CoopBattle.withSharedRandom(battle, function() battle:resolveTurn(localAction) end)
  if not ok then
    CoopLog.error("BATTLE", "resolveTurn failed on turn " .. turn .. ": " .. tostring(err))
  end
end

-- NOBODY STANDING ON OUR SIDE, AND THE TURN ABOUT TO RUN ANYWAY.  Reported
-- from play (logs 2026-10-28 22:29, both copies): after the link dropped and
-- the AI took over, the last Pokemon on our side fainted and neither slot was
-- filled, while the side check still counted somebody healthy on a bench --
-- so the battle neither sent anyone out nor ended, and played hundreds of
-- empty turns a second.  Whatever leads there, a turn never runs with our
-- side empty two turns running: a slot holding a fallen battler is cleared, each empty slot
-- takes the first healthy Pokemon from its own bench (ours, or the
-- partner's), and with nobody to send the battle is lost.


function CoopBattle.guardEmptySide(battle)
  if not (battle and battle.coopDouble and battle.battlerAt and battle.placeBattler) then return false end
  local P = BattleStatePos()
  local c = battle.coop or {}
  if standing(battle:battlerAt(P.PLAYER_LEFT)) or standing(battle:battlerAt(P.PLAYER_RIGHT)) then
    c.emptyTurns = 0
    return false
  end
  if battle.sideCanContinue and not battle:sideCanContinue(true) then
    CoopLog.warn("BATTLE", "our side cannot continue; the battle is lost")
    CoopBattle.forceFinishBattle(battle, "lose")
    return true
  end
  -- An empty side at the start of ONE turn can be the engine still sending
  -- someone in: the replacements of the turn before are queued, or still
  -- playing out, on this copy and not yet on the other.  Stepping in there
  -- put a different field on each copy.  The stuck battle is empty turn
  -- after turn with nothing pending, so only that is touched.
  if (battle.pendingReplacements and #battle.pendingReplacements > 0)
     or (type(battle.queue) == "table" and #battle.queue > 0) then
    return false
  end
  c.emptyTurns = (c.emptyTurns or 0) + 1
  if c.emptyTurns < 2 and not c.partnerLost then return false end
  c.emptyTurns = 0
  local taken = {}
  for p = 0, 3 do
    local b = battle:battlerAt(p)
    if b and b.mon then taken[b.mon] = true end
  end
  local BattleState = require("src.battle.BattleState")
  local benches = {
    { pos = P.PLAYER_LEFT, list = battle.coopChosenMons, own = true },
    { pos = P.PLAYER_RIGHT, list = battle.ally and battle.ally.party, own = false },
  }
  local placed, seen = {}, {}
  for _, bench in ipairs(benches) do
    local here = battle:battlerAt(bench.pos)
    if here and not standing(here) then battle:placeBattler(bench.pos, nil) end
    for _, mon in ipairs(type(bench.list) == "table" and bench.list or {}) do
      if type(mon) == "table" then
        seen[#seen + 1] = string.format("%s:%s%s", tostring(mon.species), tostring(mon.hp),
                                        (mon.isEgg or (tonumber(mon.eggSteps) or 0) > 0) and "(egg)" or "")
      end
    end
    if not battle:battlerAt(bench.pos) and BattleState.makeBattler then
      for _, mon in ipairs(type(bench.list) == "table" and bench.list or {}) do
        if usable(mon, taken) then
          local who = battle:placeBattler(bench.pos, BattleState.makeBattler(battle.data, mon, true,
                                          bench.own and battle.game and battle.game.save or nil))
          if who and not bench.own then who.ally = true end
          taken[mon] = true
          placed[#placed + 1] = tostring(mon.species)
          break
        end
      end
    end
  end
  if battle.syncSides then battle:syncSides() end
  if #placed > 0 then
    CoopLog.warn("BATTLE", "our side was empty at the start of the turn; sent in " .. table.concat(placed, ", "))
    return false
  end
  CoopLog.warn("BATTLE", "our side is empty and nobody can come in (benches " .. table.concat(seen, " ")
               .. "); the battle is lost")
  CoopBattle.forceFinishBattle(battle, "lose")
  return true
end

-- THE ONE DIE OF THE TURN.  Engine code that forgets to pass the battle's
-- rng rolls love.math.random instead -- a different number on each machine,
-- and every turn after differs.  While a co-op turn resolves, that call
-- rolls the shared die too (and the log says where, once).
CoopBattle.strayRolls = 0
function CoopBattle.withSharedRandom(battle, fn)
  local lm = love and love.math
  local rng = battle and battle.rng
  if not (lm and lm.random and rng) then return pcall(fn) end
  local real = lm.random
  lm.random = function(...)
    CoopBattle.strayRolls = CoopBattle.strayRolls + 1
    if CoopBattle.strayRolls == 1 then
      CoopLog.warn("BATTLE", "an engine roll skipped the shared rng: " .. tostring(debug.traceback("", 2)):sub(1, 300))
    end
    return rng(...)
  end
  local ok, err = pcall(fn)
  lm.random = real
  return ok, err
end

local function tryExecute(battle)
  local c = battle and battle.coop
  if not c or not c.localReady then return end
  if c.partnerLost or c.partnerActions[c.turn] then
    CoopBattle.executeTurn(battle)
  else
    setWaiting(battle, true)
  end
end

-- the local player has decided (or has nothing to decide: spectator/locked)
function CoopBattle.submitLocal(battle, action, opts)
  local c = battle and battle.coop
  if not c then
    -- not set up as a co-op battle after all: behave like a plain double
    return battle:resolveTurn(action)
  end
  c.localTurnAction = action
  c.localReady = true
  CoopBattle.localAction = action or { special = "spectator" }
  if not c.partnerLost then
    c.lastSent = {
      type = "coop_battle_action",
      inviteId = c.inviteId,
      turn = c.turn,
      action = CoopBattle.encodeAction(battle, action, opts),
      state = CoopBattle.packOwnState(battle),
      -- which of our chosen Pokemon is in our slot: the partner's copy
      -- waiting on a pick for a faint we never had puts it back (ReplaceWait)
      active = (function()
        local me = battle.battlerAt and battle:battlerAt(BattleStatePos().PLAYER_LEFT)
        return me and indexOf(battle.coopChosenMons, me.mon) or nil
      end)(),
    }
    c.sentActions = c.sentActions or {}
    c.sentActions[c.turn] = c.lastSent
    c.sentActions[c.turn - 4] = nil
    send(c.lastSent)
    CoopLog.battle("ACTION_SENT", "turn " .. tostring(c.turn))
  end
  tryExecute(battle)
end

function CoopBattle.onLocalActionSelected(battle, action, opts)
  return CoopBattle.submitLocal(battle, action, opts)
end

function CoopBattle.onSpectatorTurn(battle)
  if not battle then return end
  local c = battle.coop
  if battle.result or (c and c.finished) then return end
  if c and c.localReady then return end -- already submitted, still waiting
  if c and c.partnerLost then
    if battle.sideCanContinue then
      if not battle:sideCanContinue(true) then
        CoopBattle.forceFinishBattle(battle, "lose")
        return
      end
      if not battle:sideCanContinue(false) then
        CoopBattle.forceFinishBattle(battle, "win")
        return
      end
    end
    local now = (love and love.timer and love.timer.getTime) and love.timer.getTime() or os.time()
    if c.lastSpectatorTurnAt and (now - c.lastSpectatorTurnAt) < 0.05 then
      c.fastSpectatorTurns = (c.fastSpectatorTurns or 0) + 1
      if c.fastSpectatorTurns > 4 then
        CoopLog.warn("BATTLE", "onSpectatorTurn rapid loop guard tripped; ending battle")
        local res = (battle.sideCanContinue and battle:sideCanContinue(true)) and "win" or "lose"
        CoopBattle.forceFinishBattle(battle, res)
        return
      end
    else
      c.fastSpectatorTurns = 0
    end
    c.lastSpectatorTurnAt = now

    -- nobody left to watch: the ally AI fights it out
    c.localReady = true
    c.localTurnAction = nil
    return CoopBattle.executeTurn(battle)
  end
  CoopBattle.submitLocal(battle, nil)
end

function CoopBattle.onPartnerAction(msg)
  if type(msg) ~= "table" then return end
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  local turn = tonumber(msg.turn)
  if not turn then return end
  if not c or (msg.inviteId and c.inviteId and msg.inviteId ~= c.inviteId) then
    -- our copy of this battle is not up yet (still in the transition)
    if msg.inviteId then
      if not CoopBattle.early[msg.inviteId] then
        local n = 0
        for _ in pairs(CoopBattle.early) do n = n + 1 end
        if n >= CoopBattle.EARLY_MAX then CoopBattle.early = {} end
        CoopBattle.early[msg.inviteId] = {}
      end
      CoopBattle.early[msg.inviteId][turn] = { action = msg.action, state = msg.state }
    end
    return
  end
  if turn < c.turn then
    CoopLog.warn("BATTLE", "stale action for turn " .. turn .. " (at " .. c.turn .. ")")
    return
  end
  if turn > c.turn + CoopBattle.TURN_AHEAD_MAX then
    CoopLog.warn("BATTLE", "action for a turn too far ahead: " .. turn .. " (at " .. c.turn .. ")")
    return
  end
  c.partnerActions[turn] = msg.action or { kind = "spectator" }
  c.partnerStates[turn] = msg.state
  c.partnerActives = c.partnerActives or {}
  c.partnerActives[turn] = tonumber(msg.active)
  CoopBattle.partnerAction = msg.action
  CoopLog.battle("ACTION_RECV", "turn " .. turn)
  tryExecute(battle)
end

-- backward-compatible entry point (turn, action)
function CoopBattle.onPartnerActionReceived(turn, action)
  local c = CoopBattle.currentBattle and CoopBattle.currentBattle.coop
  CoopBattle.onPartnerAction({ turn = turn or (c and c.turn), action = action,
                               inviteId = c and c.inviteId })
end

-- The partner is gone (left, dropped, or the invite was aborted): their
-- Pokemon keeps fighting under the ally AI and the turn we were waiting on
-- goes ahead.
function CoopBattle.partnerLeft(battle, reason)
  local c = battle and battle.coop
  if not c or c.partnerLost then return end
  c.partnerLost = true
  battle.coopPartnerAction = nil
  CoopBattle.fallbackAllowed = false
  CoopLog.battle("PARTNER_LOST", "partner gone (" .. tostring(reason) .. "); ally AI takes over")
  local CM = manager()
  if CM and CM.showStatus then CM.showStatus("Partner left. AI takes over!", 3) end
  if c.localReady then
    CoopBattle.executeTurn(battle)
  elseif battle.phase == "waitPartner" then
    setWaiting(battle, false)
    battle.phase = "menu"
  end
end

function CoopBattle.onPartnerLeft(msg)
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  if not c then return end
  if msg and msg.inviteId and c.inviteId and msg.inviteId ~= c.inviteId then return end
  CoopBattle.partnerLeft(battle, msg and msg.type or "left")
end

function CoopBattle.onLinkLost(reason)
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  if not c or c.partnerLost then return end
  -- a drop, and the session's own reconnect window running out, still wait
  -- for the partner (LINK_GRACE, RECONNECTING... on screen); only a goodbye
  -- hands their Pokemon to the AI at once
  if reason == "lost" or reason == "timeout" then
    c.linkLostAt = c.linkLostAt or 0
  else
    CoopBattle.partnerLeft(battle, reason or "left")
  end
end

-- The link came back as a NEW session (the partner restarted their game):
-- the battle we were in is not on their side any more.
--
-- RECONNECTING, NOT GIVING UP.  Reported from play: the link dropped for a
-- minute, came back as a new session, and the partner's Pokemon stayed with
-- the AI for the rest of the battle.  The battle now waits (both screens say
-- RECONNECTING...), and when the link is up again each copy tells the other
-- which battle and turn it is on (coop_battle_here): the same battle on both
-- picks up where it stopped -- the actions the other one missed are sent
-- again and the host's state is written over the guest's copy -- and a
-- partner whose game has left the battle answers coop_battle_gone, which
-- hands their Pokemon to the AI at once.  A partner on an older version says
-- neither; after RESUME_WAIT the AI takes over, as it always did.
function CoopBattle.onNewSession()
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  if not c or c.finished then return end
  c.awaitingResume = true
  c.resumeWait = 0
  CoopLog.battle("RESUME", "the link came back as a new session; asking if the partner is still in the battle")
end

function CoopBattle.onPartnerHere(msg)
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  local inviteId = msg and msg.inviteId
  if not c or c.finished or (inviteId and c.inviteId and inviteId ~= c.inviteId) then
    if inviteId then send({ type = "coop_battle_gone", inviteId = inviteId }) end
    return
  end
  c.partnerLost = nil
  c.awaitingResume = nil
  c.resumeWait = nil
  c.linkLostAt = nil
  -- what they may have missed: every action of ours from the turn they are on
  local theirs = tonumber(msg.turn) or c.turn
  for t = math.max(theirs, c.turn - 3), c.turn do
    local a = c.sentActions and c.sentActions[t]
    if a then send(a) end
  end
  -- and the host's state, written over the guest's copy if the two differ
  if not battle.isCoopGuest then pcall(CoopBattle.syncBattleHP, battle) end
  CoopLog.battle("RESUME", string.format("partner is back in the battle (they are on turn %s, we on %d)",
                 tostring(msg.turn), c.turn))
  local CM = manager()
  if CM and CM.showStatus then CM.showStatus("RECONNECTED!", 2.5) end
end

function CoopBattle.onPartnerGone(msg)
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  if not c or (msg and msg.inviteId and c.inviteId and msg.inviteId ~= c.inviteId) then return end
  c.awaitingResume = nil
  CoopBattle.partnerLeft(battle, "partner_not_in_battle")
end

-- The link came back.  A turn sent just before it dropped died with the old
-- connection, so the one we are waiting on goes again; the partner drops it
-- as stale if it did arrive.
function CoopBattle.onLinkRestored()
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  if not c or c.finished then return end
  c.linkLostAt = nil
  if not c.partnerLost and c.localReady and c.lastSent and c.lastSent.turn == c.turn then
    send(c.lastSent)
    CoopLog.battle("ACTION_RESENT", "turn " .. tostring(c.turn))
  end
  send({ type = "coop_battle_here", inviteId = c.inviteId, turn = c.turn })
  if c.awaitingResume then c.resumeWait = 0 end
end

-- ---------------------------------------------------------------------
-- replacements after a faint: each player picks for their own slot
-- ---------------------------------------------------------------------

function CoopBattle.sendReplacement(battle, mon)
  local c = battle and battle.coop
  if not c or c.partnerLost then return end
  send({ type = "coop_battle_replace", inviteId = c.inviteId,
         index = indexOf(battle.coopChosenMons, mon), species = mon and mon.species })
end

function CoopBattle.onPartnerReplace(msg)
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  if not c or (msg.inviteId and c.inviteId and msg.inviteId ~= c.inviteId) then return end
  table.insert(c.replaceQueue, { index = tonumber(msg.index), species = msg.species })
end

local function allyPick(battle, entry)
  local party = (battle.ally and battle.ally.party) or {}
  local taken = {}
  for p = 0, 3 do
    local b = battle.battlerAt and battle:battlerAt(p)
    if b and b.mon then taken[b.mon] = true end
  end
  local function usable(m) return m and (m.hp or 0) > 0 and not m.isEgg and not taken[m] end
  if entry then
    local m = entry.index and party[entry.index]
    if usable(m) then return m end
    for _, mm in ipairs(party) do
      if usable(mm) and mm.species == entry.species then return mm end
    end
  end
  for _, mm in ipairs(party) do
    if usable(mm) then return mm end
  end
  return nil
end

-- THEIR POKEMON FELL ON THEIR SCREEN AND NOT ON THIS ONE.  Reported from
-- play: the partner's Pokemon sat in its slot at 0 HP for the rest of the
-- battle while they were fighting with the one they had sent in after it.
-- The two copies had drifted on the turn it fell, so this one never ran the
-- faint, never waited for their pick (which sat in replaceQueue), and read
-- every later action of theirs against the fallen one.  Their word on their
-- own Pokemon (applyPartnerState) is what says it is down; their pick is
-- already queued, since it is sent before their next action, and goes in
-- here, before that action is read against the slot.
function CoopBattle.alignPartnerSlot(battle)
  local c = battle and battle.coop
  if not c or c.partnerLost or not battle.placeBattler then return end
  local P = BattleStatePos()
  local pos = P.PLAYER_RIGHT
  local fallen = battle.battlerAt and battle:battlerAt(pos)
  if not (fallen and fallen.mon) or (tonumber(fallen.mon.hp) or 0) > 0 then return end
  local entry = table.remove(c.replaceQueue, 1)
  battle:placeBattler(pos, nil)
  local mon = entry and allyPick(battle, entry)
  local BattleState = require("src.battle.BattleState")
  if mon and BattleState.makeBattler then
    local who = battle:placeBattler(pos, BattleState.makeBattler(battle.data, mon, true, nil))
    who.ally = true
  elseif allyPick(battle, nil) then
    -- no pick yet, but they have one to make: the end of this turn waits for it
    battle.pendingReplacements = battle.pendingReplacements or {}
    battle.pendingReplacements[#battle.pendingReplacements + 1] = pos
  end
  battle:syncSides()
  CoopLog.battle("PARTNER_SLOT", string.format("%s was down on the partner's screen; now %s",
                 tostring(fallen.mon.species), tostring(mon and mon.species or "empty")))
end

-- The state awaitPartnerReplacement pushes: a one-line box over the battle
-- until the partner's pick is in the queue.  If they are gone (or take far
-- too long) the next healthy Pokemon goes in, which is what both copies
-- would have done anyway.
local ReplaceWait = {}
ReplaceWait.__index = ReplaceWait
ReplaceWait.isOpaque = false

function CoopBattle.newReplaceWait(battle, pos, place)
  return setmetatable({ battle = battle, pos = pos, place = place, timer = 0, done = false }, ReplaceWait)
end

function ReplaceWait:finish(mon)
  if self.done then return end
  self.done = true
  local stack = self.battle.game and self.battle.game.stack
  if stack and stack.top and stack:top() == self then stack:pop() end
  self.place(mon)
end

function ReplaceWait:update(dt)
  self.timer = self.timer + (dt or 0.016)
  local battle = self.battle
  local c = battle.coop
  -- NO PICK IS MADE FOR A PARTNER WHO IS STILL HERE.  This used to give up
  -- after REPLACE_WAIT and send in the first healthy one -- and when the
  -- partner, still in their party screen, then chose another, each screen
  -- had a different Pokemon in that slot for the rest of the battle (and
  -- their late pick sat in the queue for the next faint).  Their pick always
  -- arrives while the link holds; the wait gives up only once it is gone.
  if not c or c.partnerLost or (self.timer >= CoopBattle.REPLACE_WAIT and not linked()) then
    self:finish(allyPick(battle, nil))
    return
  end
  local entry = table.remove(c.replaceQueue, 1)
  if entry then self:finish(allyPick(battle, entry)) return end
  -- THEIR POKEMON DID NOT FALL ON THEIR SCREEN.  Reported from play: each
  -- screen waited on the other -- this one for the partner's pick after a
  -- faint, theirs for this player's move -- because the faint happened on
  -- this copy only.  Their next turn's move arriving instead of a pick says
  -- so; their word on their own Pokemon is written in, and the one they say
  -- is in their slot goes back in.
  local action = c.partnerActions and c.partnerActions[c.turn]
  if action then
    local state = c.partnerStates and c.partnerStates[c.turn]
    if state then pcall(CoopBattle.applyPartnerState, battle, state) end
    local active = c.partnerActives and c.partnerActives[c.turn]
    CoopLog.warn("BATTLE", "the partner moved on without a pick: their Pokemon did not faint on their screen")
    self:finish(allyPick(battle, active and { index = active } or nil))
  end
end

function ReplaceWait:draw()
  local CM = manager()
  local name = require("src.coop.CoopI18n").truncate(string.upper((CM and CM.partner and CM.partner.name) or "PARTNER"), 9)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw("WAITING " .. name, 8, 112)
  Font.draw("TO SEND OUT ONE" .. string.rep(".", math.floor(self.timer * 2) % 4), 8, 128)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Hand the partner's Pokemon to the ally AI and tell them so.  Kept for the
-- emergency paths; no button reaches it any more.
function CoopBattle.cancelWaitAndBattleSolo(battle)
  local c = battle and battle.coop
  if not c then return end
  send({ type = "coop_battle_leave", inviteId = c.inviteId })
  CoopBattle.partnerLeft(battle, "local_b")
end

-- ---------------------------------------------------------------------
-- host-authoritative corrections
-- ---------------------------------------------------------------------

-- EVERY TURN, THE TWO COPIES COMPARE NOTES.  The host's sync carries the
-- whole state of what the guest copies from it -- the host's Pokemon and
-- both foes: HP, status, stat stages, PP, the held item, the counters that
-- outlast a turn (sleep, toxic, confusion, a WRAP, a SUBSTITUTE, screens...)
-- and the foes' bench -- plus a signature of it.  The guest signs its own
-- copy the same way; when the two differ, the host's word is taken for all
-- of it, the turn is counted (CoopBattle.desyncs) and the log says which part
-- had drifted.  The guest's own Pokemon are never in it: their word on those
-- travels with every action (packOwnState).
local SYNC_VOLATILE = {
  "bideDamage", "bideTurns", "boundTurns", "chargeReady", "charging",
  "confusedTurns", "disabledSlot", "disabledTurns", "focusEnergy",
  "invulnerable", "leechSeeded", "lightScreen", "mist", "mustRecharge",
  "rageMove", "reflect", "sleepTurns", "substituteHP", "thrashMove",
  "thrashTurns", "toxicCounter", "trapDamage", "trapMove", "trappingTurns",
  "protectRun", "safeguard", "perishCount", "encoreTurns", "encoreMove",
  "nightmare", "cursed", "lockedOn", "destinyBond", "foresight",
}
CoopBattle.SYNC_VOLATILE = SYNC_VOLATILE

-- "off" three ways (absent, false, 0) hashes as one (see LinkBattle)
local function off(v) return v == nil or v == false or v == 0 end

local function scalar(v)
  if type(v) == "table" then return v.id or "?" end
  return v
end

local function packBattler(b, full)
  if not b or not b.mon then return nil end
  local out = {
    species = b.mon.species,
    nickname = b.mon.nickname,
    hp = math.max(0, tonumber(b.mon.hp) or 0),
    status = b.mon.status,
  }
  if not full then return out end
  out.item = b.mon.item
  out.stages = {}
  for k, v in pairs(b.stages or {}) do
    if type(v) == "number" and v ~= 0 then out.stages[k] = v end
  end
  out.pp = {}
  for i, mv in ipairs(b.curMoves or b.mon.moves or {}) do
    out.pp[i] = tonumber(mv.pp) or 0
  end
  out.vol = {}
  for _, key in ipairs(SYNC_VOLATILE) do
    local v = b[key]
    if not off(v) and type(v) ~= "function" then out.vol[key] = scalar(v) end
  end
  return out
end
CoopBattle.packBattler = packBattler

local function sortedPairs(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. tostring(t[k]) end
  return table.concat(out, ",")
end

-- one line per part, so a mismatch can say what drifted
local function signParts(packed)
  -- a fainted Pokemon still in its slot on one copy and already taken off
  -- on the other is the same field: both sign it as an empty slot
  if type(packed) ~= "table" or (tonumber(packed.hp) or 0) <= 0 then
    return { actives = "-", volatile = "-" }
  end
  return {
    actives = string.format("%s:%d:%s:%s:%s:%s", tostring(packed.species), tonumber(packed.hp) or 0,
                            tostring(packed.status), tostring(packed.item), sortedPairs(packed.stages),
                            table.concat(packed.pp or {}, ",")),
    volatile = sortedPairs(packed.vol),
  }
end

local function benchOf(party)
  local out = {}
  for i, mon in ipairs(party or {}) do
    if type(mon) == "table" then
      out[i] = { species = mon.species, hp = math.max(0, tonumber(mon.hp) or 0), status = mon.status }
    else
      out[i] = false
    end
  end
  return out
end

local function benchSig(bench)
  local out = {}
  for i, m in ipairs(bench or {}) do
    out[i] = type(m) == "table" and (tostring(m.species) .. ":" .. tostring(m.hp) .. ":" .. tostring(m.status)) or "-"
  end
  return table.concat(out, "|")
end

-- the signature of a sync's worth of state: { actives, volatile, bench }
function CoopBattle.signature(host, enemy1, enemy2, bench)
  local a, b, c = signParts(host), signParts(enemy1), signParts(enemy2)
  return {
    actives = a.actives .. "|" .. b.actives .. "|" .. c.actives,
    volatile = a.volatile .. "|" .. b.volatile .. "|" .. c.volatile,
    bench = benchSig(bench),
  }
end

function CoopBattle.syncBattleHP(battle)
  if not battle or not battle.coopDouble or battle.isCoopGuest then return end
  local c = battle.coop
  if not c or c.partnerLost or not linked() then return end
  local P = BattleStatePos()
  local host = packBattler(battle:battlerAt(P.PLAYER_LEFT), true)
  local enemy1 = packBattler(battle:battlerAt(P.OPPONENT_LEFT), true)
  local enemy2 = packBattler(battle:battlerAt(P.OPPONENT_RIGHT), true)
  local bench = benchOf(battle.enemyParty)
  send({
    type = "coop_battle_sync",
    inviteId = c.inviteId,
    turn = c.turn - 1,
    -- in the HOST's frame: host = host's own Pokemon
    host = host,
    guest = packBattler(battle:battlerAt(P.PLAYER_RIGHT)),
    enemy1 = enemy1,
    enemy2 = enemy2,
    bench = bench,
    sig = CoopBattle.signature(host, enemy1, enemy2, bench),
  })
end

local function applyOne(battle, b, data, partyList)
  if not b or not b.mon or type(data) ~= "table" then return false end
  if data.species and b.mon.species ~= data.species then
    -- a different Pokemon is standing there: the copies disagree about a
    -- switch, which HP cannot fix -- log it rather than corrupt either mon
    CoopLog.warn("BATTLE", "sync species mismatch " .. tostring(b.mon.species) .. " vs " .. tostring(data.species))
    return false
  end
  local hp = tonumber(data.hp)
  local localHp = tonumber(b.mon.hp) or 0
  local changed = false
  -- only correct a living Pokemon to another living value; a faint the guest
  -- has not processed itself must come from its own engine, or the
  -- replacement / end-of-battle flow never runs
  if hp and hp > 0 and localHp > 0 and hp ~= localHp then
    b.mon.hp = hp
    changed = true
  elseif hp and ((hp > 0) ~= (localHp > 0)) then
    CoopLog.warn("BATTLE", string.format("faint disagreement on %s: host %d, guest %d",
                 tostring(b.mon.species), hp, localHp))
  end
  if data.status ~= b.mon.status and (localHp > 0) then
    b.mon.status = data.status
    b.status = data.status
    changed = true
  end
  if data.full then
    -- the rest of the host's word, when the copies were found to differ
    if data.item ~= nil or b.mon.item ~= nil then b.mon.item = data.item end
    b.stages = b.stages or {}
    for k in pairs(b.stages) do if type(b.stages[k]) == "number" then b.stages[k] = nil end end
    for k, v in pairs(type(data.stages) == "table" and data.stages or {}) do b.stages[k] = tonumber(v) end
    for i, mv in ipairs(b.curMoves or b.mon.moves or {}) do
      local pp = type(data.pp) == "table" and tonumber(data.pp[i])
      if pp then mv.pp = pp end
    end
    local vol = type(data.vol) == "table" and data.vol or {}
    for _, key in ipairs(SYNC_VOLATILE) do
      local v = vol[key]
      if v == nil then
        if not off(b[key]) and type(b[key]) ~= "table" then b[key] = nil end
      elseif type(b[key]) == "table" then
        -- a move instance (THRASH, a WRAP, an ENCORE): keep ours when it is the same move
        if scalar(b[key]) ~= v then CoopLog.warn("BATTLE", "sync: " .. key .. " names another move") end
      else
        b[key] = v
      end
    end
    changed = true
  end
  -- ...and onto its entry in the party.  That is the battler's own Pokemon;
  -- a look-alike (same species, same nickname) stands in for it only when
  -- it is not there and there is exactly one.  BALANCED FOES pads a trainer
  -- with copies of its own Pokemon: writing one foe's HP and status onto its
  -- twins mixed the two foes up on the guest's copy at every correction, so
  -- the copies never agreed again (log 2026-10-28, two HITMONCHAN).
  if changed and partyList then
    local own, twins = false, {}
    for _, pm in ipairs(partyList) do
      if pm == b.mon then
        own = true
      elseif type(pm) == "table" and pm.species == b.mon.species and pm.nickname == b.mon.nickname then
        twins[#twins + 1] = pm
      end
    end
    if not own and #twins == 1 then
      twins[1].hp = b.mon.hp
      twins[1].status = b.mon.status
    end
  end
  return changed
end

-- the foes on the bench: HP and status, by position
local function applyBench(battle, bench)
  if type(bench) ~= "table" then return end
  for i, m in ipairs(battle.enemyParty or {}) do
    local w = bench[i]
    if type(m) == "table" and type(w) == "table" and w.species == m.species then
      local hp = tonumber(w.hp)
      if hp and hp > 0 and (tonumber(m.hp) or 0) > 0 then m.hp = hp end
      m.status = w.status
    end
  end
end

function CoopBattle.applySync(battle, msg)
  local P = BattleStatePos()
  -- guest frame: own Pokemon is LEFT, the host's is RIGHT.  The guest's own
  -- Pokemon are never overwritten from here: the host's copy of them can be
  -- a level-up behind (experience is paid on the owner's machine), and the
  -- guest's word on them travels with every action instead.
  local changed = false
  local hostB = battle:battlerAt(P.PLAYER_RIGHT)
  local e1, e2 = battle:battlerAt(P.OPPONENT_LEFT), battle:battlerAt(P.OPPONENT_RIGHT)
  if type(msg.sig) == "table" then
    local mine = CoopBattle.signature(packBattler(hostB, true), packBattler(e1, true),
                                      packBattler(e2, true), benchOf(battle.enemyParty))
    local drift = {}
    for _, part in ipairs({ "actives", "volatile", "bench" }) do
      if mine[part] ~= msg.sig[part] then drift[#drift + 1] = part end
    end
    if #drift > 0 then
      CoopBattle.desyncs = CoopBattle.desyncs + 1
      CoopLog.warn("BATTLE", string.format("turn %s: the copies differ (%s); taking the host's word",
                   tostring(msg.turn), table.concat(drift, ", ")))
      CoopLog.warn("BATTLE", "host  " .. tostring(msg.sig.actives))
      CoopLog.warn("BATTLE", "guest " .. tostring(mine.actives))
      for _, k in ipairs({ "host", "enemy1", "enemy2" }) do
        if type(msg[k]) == "table" then msg[k].full = true end
      end
      applyBench(battle, msg.bench)
    end
  end
  changed = applyOne(battle, hostB, msg.host, battle.ally and battle.ally.party) or changed
  changed = applyOne(battle, e1, msg.enemy1, battle.enemyParty) or changed
  changed = applyOne(battle, e2, msg.enemy2, battle.enemyParty) or changed
  if changed then
    CoopLog.battle("SYNC_APPLY", "corrected guest copy after turn " .. tostring(msg.turn))
    for _, pos in ipairs({ P.PLAYER_LEFT, P.PLAYER_RIGHT, P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local b = battle:battlerAt(pos)
      if b and b.shownHP then b.shownHP = b.mon.hp end
    end
    if battle.syncShownStatus then pcall(battle.syncShownStatus, battle) end
  end
end

function CoopBattle.onPartnerBattleSync(msg)
  local battle = CoopBattle.currentBattle
  if not msg or not battle then return end
  if not battle.coopDouble or not battle.isCoopGuest then return end
  local c = battle.coop
  if c and msg.inviteId and c.inviteId and msg.inviteId ~= c.inviteId then return end
  if c and c.partnerLost then return end

  if msg.result == "win" or msg.result == "lose" or msg.result == "loss" then
    local result = (msg.result == "loss") and "lose" or msg.result
    if c then
      c.hostResult = result
      c.hostResultAt = 0
    else
      CoopBattle.forceFinishBattle(battle, result)
    end
    return
  end
  if c then
    c.pendingSync = msg
  else
    CoopBattle.applySync(battle, msg)
  end
end

function CoopBattle.onPartnerHealedMon(msg)
  if not msg or not CoopBattle.currentBattle then return end
  -- it rides with their action this turn (applyItemHeal)
  if msg.deferred and CoopBattle.currentBattle.coop then return end
  local battle = CoopBattle.currentBattle
  local function matches(mon)
    return mon and (mon.nickname == msg.targetNick or (not mon.nickname and mon.species == msg.species)
                    or (msg.targetNick == mon.species and mon.species == msg.species))
  end
  local function heal(mon)
    if msg.hp then mon.hp = math.min(tonumber(msg.maxHp) or mon.hp or 20, msg.hp) end
    mon.status = msg.status
  end
  -- the item was used on the partner's own Pokemon, or on ours from their bag
  local lists = { battle.ally and battle.ally.party or {}, battle.coopChosenMons or {} }
  for _, list in ipairs(lists) do
    for _, mon in ipairs(list) do
      if matches(mon) then heal(mon) end
    end
  end
  local P = BattleStatePos()
  for _, pos in ipairs({ P.PLAYER_LEFT, P.PLAYER_RIGHT }) do
    local b = battle:battlerAt(pos)
    if b and matches(b.mon) then
      b.status = b.mon.status
      if b.shownHP then b.shownHP = b.mon.hp end
    end
  end
  if battle.syncShownStatus then pcall(battle.syncShownStatus, battle) end
end

function CoopBattle.onPartnerBag(msg)
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  if c and (not msg.inviteId or c.inviteId == msg.inviteId) then
    c.partnerInBag = (msg.inBag == true)
  end
end

-- End a battle the engine did not end on its own.  Goes through finish()
-- when the battle is on top so music, the stack and the return fade are
-- torn down the normal way; otherwise waits until it is.
function CoopBattle.forceFinishBattle(battle, result)
  if not battle then return end
  local c = battle.coop
  if c and c.finished then return end
  result = (result == "loss") and "lose" or (result or "win")
  local game = battle.game
  local top = game and game.stack and (type(game.stack.top) == "function" and game.stack:top() or game.stack.top)
  CoopLog.battle("FORCE_FINISH", "result: " .. tostring(result))
  -- THE HOST'S WIN CLOSES THIS COPY, and a foe still standing here was never
  -- paid for: the experience for it was lost along with the turn.  Pay it
  -- now, before the battle goes (BattleState:awardExp marks each foe it pays)
  if result == "win" and battle.isCoopGuest and battle.awardExp and not battle.noExp then
    local P = BattleStatePos()
    for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local b = battle.battlerAt and battle:battlerAt(pos)
      if b and b.mon and not (battle.expPaidFor and battle.expPaidFor[b.mon]) then
        local ok, err = pcall(battle.awardExp, battle, b)
        if ok then
          CoopLog.battle("FORCE_FINISH", "paid exp for " .. tostring(b.mon.species))
        else
          CoopLog.error("BATTLE", "exp on forced finish failed: " .. tostring(err))
        end
      end
    end
  end
  battle.result = result
  if top == battle and battle.finish then
    CoopBattle.active = false
    CoopBattle.waitingForPartner = false
    local ok, err = pcall(battle.finish, battle)
    if not ok then
      CoopLog.error("BATTLE", "finish failed: " .. tostring(err))
      if battle.onFinish then pcall(battle.onFinish, result) end
    end
  elseif c then
    c.forceResult = result
  else
    battle.phase = "finish"
    if battle.onFinish then pcall(battle.onFinish, result) end
  end
end

-- ---------------------------------------------------------------------
-- per-frame (from CoopManager.update, so it runs whatever is on top)
-- ---------------------------------------------------------------------

local function battleOnStack(battle)
  local states = battle.game and battle.game.stack and battle.game.stack.states
  if not states then return true end
  for _, st in ipairs(states) do
    if st == battle then return true end
  end
  return false
end

local function betweenTurns(battle)
  return battle.phase == "menu" or battle.phase == "waitPartner"
end

function CoopBattle.tick(dt)
  local battle = CoopBattle.currentBattle
  local c = battle and battle.coop
  if not c then return end
  dt = dt or 0.016

  if c.finished then return end
  local onStack = battleOnStack(battle)
  if onStack then
    c.everOnStack = true
  elseif c.everOnStack then
    -- off the stack: either finish() popped it and onFinish follows after
    -- the return fade, or something tore it down without finishing.  Either
    -- way there is nothing left to wait for; onFinish still runs normally.
    if not battle.result then
      CoopLog.warn("BATTLE", "co-op battle left the stack unfinished; releasing")
    end
    c.finished = true
    CoopBattle.active = false
    CoopBattle.waitingForPartner = false
    if CoopBattle.currentBattle == battle then CoopBattle.currentBattle = nil end
    return
  end

  if c.forceResult then
    CoopBattle.forceFinishBattle(battle, c.forceResult)
    return
  end

  -- after a reconnect as a new session: the partner says it is still in the
  -- battle (onPartnerHere) or not (onPartnerGone); an older version says
  -- nothing, and the AI takes over as before
  if c.awaitingResume and not c.partnerLost and linked() then
    c.resumeWait = (c.resumeWait or 0) + dt
    if c.resumeWait >= CoopBattle.RESUME_WAIT then
      c.awaitingResume = nil
      CoopBattle.partnerLeft(battle, "no_resume")
    end
  end

  -- link watchdog: a drop gets a grace period, then the AI takes over
  if not c.partnerLost then
    if linked() then
      c.linkLostAt = nil
    else
      c.linkLostAt = (c.linkLostAt or 0) + dt
      if c.linkLostAt >= CoopBattle.LINK_GRACE then
        -- the AI takes their Pokemon, and they are told so: the message waits
        -- in the session, and when the link comes back their copy hands ours
        -- to the AI as well, instead of waiting for turns we no longer send
        send({ type = "coop_battle_leave", inviteId = c.inviteId, reason = "timeout" })
        CoopBattle.partnerLeft(battle, "timeout")
      end
    end
  end

  if CoopBattle.waitingForPartner then
    c.waitTime = (c.waitTime or 0) + dt
    CoopBattle.waitTimer = c.waitTime
  end

  if c.pendingSync and betweenTurns(battle) then
    local msg = c.pendingSync
    c.pendingSync = nil
    -- only the turn just played: a sync that waited while the next turn
    -- already ran would write an older HP over the newer one
    if tonumber(msg.turn) == nil or tonumber(msg.turn) == c.turn - 1 then
      CoopBattle.applySync(battle, msg)
    else
      CoopLog.info("BATTLE", string.format("dropped the sync of turn %s (now at %d)", tostring(msg.turn), c.turn))
    end
  end

  if c.hostResult then
    c.hostResultAt = (c.hostResultAt or 0) + dt
    if c.hostResultAt >= CoopBattle.RESULT_GRACE or (betweenTurns(battle) and c.hostResultAt >= 1.0) then
      CoopBattle.forceFinishBattle(battle, c.hostResult)
    end
  end

  -- sync local inBag status during menu phase
  if battle.coopDouble and battle.phase == "menu" and not c.partnerLost then
    local stack = battle.game and battle.game.stack
    local top = stack and (type(stack.top) == "function" and stack:top() or stack.top)
    local inBag = (battle.waitingUI and top and top.kind == "bag") and true or false
    if c.localInBag ~= inBag then
      c.localInBag = inBag
      send({ type = "coop_battle_bag", inviteId = c.inviteId, inBag = inBag })
    end
  end
end

-- input while waiting (called from BattleState:update).  Nothing to do: the
-- AI only steps in when the link is gone (tick's watchdog), never on a key.
function CoopBattle.update(battle, dt)
end

-- Drawn over the bottom text box, where the battle's own messages go: the
-- top of the screen belongs to the foes' HUDs and covering them hid their HP.
function CoopBattle.drawReconnecting(battle)
  local c = battle and battle.coop
  if not c or c.partnerLost or c.finished or not (c.linkLostAt or c.awaitingResume) then return false end
  local CM = manager()
  local name = require("src.coop.CoopI18n").truncate(string.upper((CM and CM.partner and CM.partner.name) or "PARTNER"), 14)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(1, 5, 18, 7)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw("RECONNECTING...", 16, 56)
  Font.draw(name, 16, 72)
  if c.linkLostAt then
    Font.draw(string.format("AI IN %ds", math.max(0, math.ceil(CoopBattle.LINK_GRACE - c.linkLostAt))), 16, 88)
  else
    Font.draw("RESUMING...", 16, 88)
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

function CoopBattle.drawWaitPrompt(battle)
  if CoopBattle.drawReconnecting(battle) then return end
  pcall(CoopBattle.drawPartnerPlan, battle)
  if not CoopBattle.waitingForPartner then return end
  local CM = manager()
  local name = require("src.coop.CoopI18n").truncate(string.upper((CM and CM.partner and CM.partner.name) or "PARTNER"), 9)
  local c = battle.coop
  local line1, line2
  if c and c.linkLostAt then
    line1 = "LINK LOST..."
    line2 = string.format("AI PLAYS IN %ds", math.max(0, math.ceil(CoopBattle.LINK_GRACE - c.linkLostAt)))
  elseif isSpectator(battle) then
    line1 = "WATCHING " .. name
    line2 = "WAITING TURN..."
  else
    line1 = "WAITING " .. name
    line2 = "CHOOSING" .. string.rep(".", math.floor((c and c.waitTime or 0) * 2) % 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(line1, 8, 112)
  Font.draw(line2, 8, 128)
  love.graphics.setColor(1, 1, 1, 1)
end

return CoopBattle
