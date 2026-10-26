-- THE FOES OF A CO-OP DOUBLE, THINKING ABOUT BOTH OF YOU.
--
-- Johto's trainers carry no AI flags this port runs, so in a double every
-- foe used to roll one of its moves at random and aim it at a coin flip --
-- a Hypnosis into a Pokemon already asleep, a Splash with a KO on the table,
-- both foes emptying everything into a Pokemon the first one had already
-- finished.  This is the HGSS-era doubles brain, and then some: every usable
-- (move, target) pair is scored and the best one is taken.
--
--   * damage is ESTIMATED -- the cartridge's formula on the live stats and
--     stages, a middle damage roll, no crit -- and never rolled, because the
--     shared RNG is drawn in the same order on both copies of the battle and
--     a draw spent here on one copy only would split them;
--   * the foes SCOUT you first (DoublesAI.scout): how much each of your
--     Pokemon can take off each of them with the moves it carries, who can
--     knock out whom, and who moves first.  A knockout is worth the HP it
--     takes plus what it removes -- so the dangerous Pokemon is the one they
--     want gone, not just the frail one -- and more again when the foe is
--     faster and the target falls before it gets to move at all;
--   * the two foes plan the turn TOGETHER: the first to choose scores every
--     pair of (its move, its partner's move) at once, so they can split up,
--     or gang up on a Pokemon neither could knock out alone, and the partner
--     is handed its half of the plan.  A partner that is locked into a move,
--     or chooses on its own, still sees what the first one is dealing and
--     does not pile onto a Pokemon that is going down anyway;
--   * a status move is worth nothing on a Pokemon that already has one, sits
--     behind a SUBSTITUTE, is about to be knocked out, or whose type shrugs it
--     off -- and two foes never both spend the turn putting one Pokemon to
--     sleep;
--   * they look after themselves: PROTECT when one of you is about to knock
--     it out first (its partner gets a free turn), heal while healing still
--     outpaces the damage, set up only when it is safe, put up REFLECT or
--     LIGHT SCREEN against the kind of attack you actually carry, and blow up
--     only when they are going down anyway;
--   * a spread move that also hits its own partner pays for that.
--
-- Only state both copies hold is read, every list is walked in a fixed order
-- (foesOf's canonical order -- the host's Pokemon first on both copies --
-- and move-slot order), nothing is summed in `pairs` order, and a tie in a
-- lone foe's choice is the only thing the RNG decides -- so both machines
-- pick the same pairs.

local Targeting = require("src.battle.Targeting")
local TypeChart = require("src.battle.TypeChart")
local Damage = require("src.battle.Damage")
local Stats = require("src.pokemon.Stats")

local DoublesAI = {}

local function alive(b)
  return b and b.mon and not b.fainted and not b.faintQueued and (b.mon.hp or 0) > 0
end

local function maxHp(b)
  local s = b.curStats or b.mon.stats or {}
  return math.max(1, s.hp or b.mon.maxHp or b.mon.hp or 1)
end

local function hpPct(b) return (b.mon.hp or 0) * 100 / maxHp(b) end

local function hasType(b, t)
  for _, x in ipairs(b.curTypes or {}) do if x == t then return true end end
  return false
end

local function eff(moveType, b)
  local ok, m = pcall(TypeChart.effectiveness, moveType, b.curTypes or {})
  return ok and tonumber(m) or 10
end

local function accuracy(def)
  local a = tonumber(def.accuracy) or 100
  if a <= 0 then return 1 end
  return math.min(100, a) / 100
end

local function stat(b, key)
  local s = b.curStats or b.mon.stats or {}
  local v = s[key]
  if v == nil and (key == "spatk" or key == "spdef") then v = s.special end
  return math.max(1, Stats.applyStage(v or 1, Damage.stageOf(b, key)))
end

-- the speed the turn order will actually use (paralysis, badges, weather)
local function speedOf(battle, b)
  local ok, TurnOrder = pcall(require, "src.battle.TurnOrder")
  if ok and TurnOrder.effectiveSpeed and b.curStats then
    local okS, s = pcall(TurnOrder.effectiveSpeed, b, battle)
    if okS and tonumber(s) then return s end
  end
  local s = stat(b, "speed")
  if b.mon.status == "PAR" then s = math.max(1, math.floor(s / 4)) end
  return s
end

-- TurnOrder's own table: QUICK ATTACK goes first, COUNTER last
local PRIORITY = { QUICK_ATTACK = 1, COUNTER = -1 }
local function priorityOf(def) return tonumber(def.priority) or PRIORITY[def.id] or 0 end

-- would `user` using `def` move before `target` does?
local function movesFirst(battle, user, def, target)
  local p = priorityOf(def)
  if p ~= 0 then return p > 0 end
  return speedOf(battle, user) > speedOf(battle, target)
end

local FIXED = { SONICBOOM = 20, DRAGON_RAGE = 40 }
local LEVEL_DAMAGE = { SEISMIC_TOSS = true, NIGHT_SHADE = true, PSYWAVE = true }
-- power 1 in the move record; the real number is worked out when it hits
local VARIABLE_POWER = {
  RETURN_EFFECT = 70, FRUSTRATION_EFFECT = 40, HIDDEN_POWER_EFFECT = 60,
  MAGNITUDE_EFFECT = 70, PRESENT_EFFECT = 40, REVERSAL_EFFECT = 60,
  BEAT_UP_EFFECT = 40,
}
local MULTI_HIT = { TWO_TO_FIVE_ATTACKS_EFFECT = 3, ATTACK_TWICE_EFFECT = 2, TWINEEDLE_EFFECT = 2 }
local TWO_TURN = { SOLARBEAM_EFFECT = true, FLY_EFFECT = true, CHARGE_EFFECT = true }
local MAJOR_STATUS = { SLEEP_EFFECT = true, PARALYZE_EFFECT = true, POISON_EFFECT = true,
                       TOXIC_EFFECT = true }

-- expected HP this move takes off `target`, before accuracy
local function estimate(battle, user, target, def, spread)
  local power = tonumber(def.power) or 0
  if power <= 0 then return 0 end
  local e = eff(def.type, target)
  if e == 0 then return 0 end
  local id = def.id
  if FIXED[id] then return FIXED[id] end
  if LEVEL_DAMAGE[id] then return user.mon.level or 1 end
  if def.effect == "SUPER_FANG_EFFECT" then return math.max(1, math.floor((target.mon.hp or 0) / 2)) end
  if def.effect == "OHKO_EFFECT" then
    if (user.mon.level or 0) < (target.mon.level or 0) then return 0 end
    return target.mon.hp or 0
  end
  if def.effect == "DREAM_EATER_EFFECT" and target.mon.status ~= "SLP" then return 0 end
  if power <= 1 then power = VARIABLE_POWER[def.effect] or 50 end
  local special = Damage.isSpecial(def.type)
  local atk = stat(user, special and "spatk" or "attack")
  local dfn = stat(target, special and "spdef" or "defense")
  local d = Damage.base(user.mon.level or 1, power, atk, dfn) + 2
  if hasType(user, def.type) then d = d * 1.5 end
  d = d * e / 10
  -- Gen 2 keeps the screens on the Pokemon that raised them, later games on the side
  local side = battle.sides and battle.sides[target.isPlayer and 1 or 2]
  local screen = special and (target.lightScreen or (side and side.lightScreen))
                 or (not special and (target.reflect or (side and side.reflect)))
  if screen then d = d * 2 / 3 end
  if spread then d = d * 3 / 4 end
  d = d * (MULTI_HIT[def.effect] or 1) * 236 / 255 -- the middle of the damage roll
  if def.effect == "FALSE_SWIPE_EFFECT" then d = math.min(d, (target.mon.hp or 1) - 1) end
  return math.max(1, math.floor(d))
end

DoublesAI.estimate = estimate -- for the tests, to set up exact HP

-- the moves a battler can pick, the way TrainerAI.chooseMove lists them
local function usableOf(b)
  local out = {}
  for i, mv in ipairs(b.curMoves or {}) do
    if b.disabledSlot ~= i and (mv.pp or 0) > 0 then out[#out + 1] = mv end
  end
  return out
end

local function stageOf(b, s) return (b.stages and b.stages[s]) or 0 end

-- ---------------------------------------------------------------------
-- scouting: what each of the players' Pokemon can do to the foes
-- ---------------------------------------------------------------------

-- Fills, once per turn:
--   plan.threat[t]   how dangerous t is: the best share of HP one of its
--                    moves takes off one foe (a knockout counts 40 more);
--                    a sleeping or frozen Pokemon is a lot less of a worry
--   plan.incoming[o] the most one hit from either player can take off o
--   plan.doomed[o]   someone who moves first can knock o out this turn
--   plan.physical / plan.special   how many players hit hardest that way
function DoublesAI.scout(battle, plan, players, side)
  if plan.scouted then return end
  plan.scouted = true
  plan.threat, plan.incoming, plan.doomed = {}, {}, {}
  plan.physical, plan.special = 0, 0
  local moves = battle.data and battle.data.moves or {}
  for _, t in ipairs(players) do
    local best, bestSpecial = 0, false
    for _, mv in ipairs(usableOf(t)) do
      local def = moves[mv.id]
      if def then
        if (tonumber(def.power) or 0) > 0 then
          for _, o in ipairs(side) do
            local d = estimate(battle, t, o, def, false)
            local hp = o.mon.hp or 0
            local v = math.min(d * accuracy(def), hp) * 100 / maxHp(o)
            if d >= hp then
              v = v + 40 * accuracy(def)
              if movesFirst(battle, t, def, o) then plan.doomed[o] = true end
            end
            if d > (plan.incoming[o] or 0) then plan.incoming[o] = d end
            if v > best then best, bestSpecial = v, Damage.isSpecial(def.type) end
          end
        elseif def.effect == "SLEEP_EFFECT" then
          for _, o in ipairs(side) do
            if not o.mon.status then best = math.max(best, 30 * accuracy(def)) end
          end
        end
      end
    end
    local st = t.mon.status
    if st == "SLP" or st == "FRZ" then best = best * 0.4
    elseif st == "PAR" then best = best * 0.8 end
    plan.threat[t] = best
    if best > 0 then
      if bestSpecial then plan.special = plan.special + 1 else plan.physical = plan.physical + 1 end
    end
  end
end

local function threatOf(plan, t) return (plan.threat and plan.threat[t]) or 0 end

-- 0.75 for a Pokemon that cannot hurt anyone, up to 1.25 for a real danger
local function threatMul(plan, t)
  return 0.75 + 0.5 * math.min(threatOf(plan, t), 120) / 120
end

-- ---------------------------------------------------------------------
-- what damage is worth
-- ---------------------------------------------------------------------

-- What the hits in `list` (each { d = damage, p = chance it lands, first =
-- lands before the target moves }) are worth together against `target`, and
-- how likely they are to knock it out.  The list is walked in order and only
-- multiplied and summed, so its order cannot change the answer's rounding on
-- the other copy.
local function dmgValue(battle, plan, target, list)
  local n = #list
  if n == 0 then return 0, 0 end
  local cap, hp = maxHp(target), target.mon.hp or 0
  local exp, sum, all, allFirst, noSolo, soloFirst = 0, 0, 1, true, 1, false
  for i = 1, n do
    local c = list[i]
    exp, sum, all = exp + c.d * c.p, sum + c.d, all * c.p
    if not c.first then allFirst = false end
    if c.d >= hp then
      noSolo = noSolo * (1 - c.p)
      if c.first then soloFirst = true end
    end
  end
  local sub = target.substituteHP
  if sub and sub > 0 then
    -- the doll takes it all; breaking it is worth a little
    return math.min(exp, sub) * 40 / cap + ((sum >= sub) and 8 or 0), 0
  end
  local threat = threatOf(plan, target)
  local v = math.min(exp, hp) * 100 / cap * threatMul(plan, target)
  local koP, first = 1 - noSolo, soloFirst
  if koP == 0 and sum >= hp then koP, first = all, allFirst end  -- only together
  if koP > 0 then
    local bonus = 45 + 0.5 * threat
    if first then bonus = bonus + 0.4 * threat end  -- it falls before it moves
    v = v + bonus * koP
  end
  return v, koP
end

-- the hits already planned against `f`, plus `extra` (a list, or nil)
local function planned(plan, f, extra)
  local out = {}
  local had = plan.hits and plan.hits[f]
  if had then for i = 1, #had do out[#out + 1] = had[i] end end
  if extra then for i = 1, #extra do out[#out + 1] = extra[i] end end
  return out
end

-- ---------------------------------------------------------------------
-- status and self moves
-- ---------------------------------------------------------------------

local STAT_DOWN = {
  ATTACK_DOWN_EFFECT = "attack", DEFENSE_DOWN_EFFECT = "defense", SPEED_DOWN_EFFECT = "speed",
  SP_ATK_DOWN_EFFECT = "spatk", SP_DEF_DOWN_EFFECT = "spdef", ACCURACY_DOWN_EFFECT = "accuracy",
  EVASION_DOWN_EFFECT = "evasion",
  ATTACK_DOWN2_EFFECT = "attack", DEFENSE_DOWN2_EFFECT = "defense", SPEED_DOWN2_EFFECT = "speed",
  SP_ATK_DOWN2_EFFECT = "spatk", SP_DEF_DOWN2_EFFECT = "spdef", ACCURACY_DOWN2_EFFECT = "accuracy",
  EVASION_DOWN2_EFFECT = "evasion",
}
local STAT_UP = {
  ATTACK_UP_EFFECT = "attack", DEFENSE_UP_EFFECT = "defense", SPEED_UP_EFFECT = "speed",
  SP_ATK_UP_EFFECT = "spatk", SP_DEF_UP_EFFECT = "spdef", EVASION_UP_EFFECT = "evasion",
  ATTACK_UP2_EFFECT = "attack", DEFENSE_UP2_EFFECT = "defense", SPEED_UP2_EFFECT = "speed",
  SP_ATK_UP2_EFFECT = "spatk", SP_DEF_UP2_EFFECT = "spdef", EVASION_UP2_EFFECT = "evasion",
}
for _, t in ipairs({ STAT_DOWN, STAT_UP }) do
  local extra = {}
  for k, v in pairs(t) do
    if not k:find("2_EFFECT$") then extra[(k:gsub("_EFFECT$", "1_EFFECT"))] = v end
  end
  for k, v in pairs(extra) do t[k] = v end
end
local SELF_HEAL = { HEAL_EFFECT = true, SYNTHESIS_EFFECT = true, MORNING_SUN_EFFECT = true,
                    MOONLIGHT_EFFECT = true }

-- a status move aimed at one foe, before the threat it is aimed at counts
local function statusValue(battle, user, target, def, foes)
  local fx = def.effect or ""
  local acc = accuracy(def)
  local st = target.mon.status
  local side = battle.sides and battle.sides[target.isPlayer and 1 or 2]
  local guarded = side and side.safeguard or target.safeguardTurns
  if target.substituteHP and target.substituteHP > 0 then return 0 end
  if fx == "SLEEP_EFFECT" then
    if st or guarded then return 0 end
    return 55 * acc
  elseif fx == "PARALYZE_EFFECT" then
    if st or guarded or eff(def.type, target) == 0 then return 0 end
    -- slowing down what outruns the whole side is what PARALYZE is for
    local outruns = 0
    for _, o in ipairs(foes) do
      if speedOf(battle, target) > speedOf(battle, o) then outruns = outruns + 1 end
    end
    return (outruns >= 2 and 50 or outruns == 1 and 40 or 28) * acc
  elseif fx == "POISON_EFFECT" or fx == "TOXIC_EFFECT" then
    if st or guarded or hasType(target, "POISON") or hasType(target, "STEEL") then return 0 end
    return (hpPct(target) > 50 and 30 or 12) * acc
  elseif fx == "CONFUSION_EFFECT" or fx == "SWAGGER_EFFECT" then
    if target.confusedTurns or guarded then return 0 end
    return 26 * acc
  elseif fx == "LEECH_SEED_EFFECT" then
    if target.leechSeeded or hasType(target, "GRASS") then return 0 end
    return 24 * acc
  elseif fx == "MEAN_LOOK_EFFECT" then
    if battle.meanLookHolds and battle:meanLookHolds(target) then return 0 end
    return 6 * acc
  elseif fx == "ATTRACT_EFFECT" then
    return 14 * acc
  elseif STAT_DOWN[fx] then
    -- worth a turn early on, not over a hit that does real damage
    if stageOf(target, STAT_DOWN[fx]) <= -2 or (user.turnsOut or 0) > 3 then return 0 end
    return (hpPct(user) > 50 and 7 or 2) * acc
  elseif fx == "SPLASH_EFFECT" then
    return 0
  end
  return 8 * acc
end

-- a move the user aims at itself or its side
local function selfValue(battle, plan, user, ally, def)
  local fx = def.effect or ""
  local pct = hpPct(user)
  local hp, cap = user.mon.hp or 0, maxHp(user)
  local incoming = (plan.incoming and plan.incoming[user]) or 0
  local doomed = plan.doomed and plan.doomed[user]
  local side = battle.sides and battle.sides[user.isPlayer and 1 or 2]
  if SELF_HEAL[fx] then
    if incoming >= hp + cap / 2 then return 4 end    -- healing would not save it
    if pct < 35 then return 80 elseif pct < 60 then return 35 end
    if incoming >= hp and pct < 75 then return 40 end
    return 0
  elseif fx == "REST_EFFECT" or def.id == "REST" then
    if incoming >= cap then return 4 end
    if pct < 35 or (user.mon.status and pct < 60) then return 60 end
    if incoming >= hp and pct < 70 then return 35 end
    return 0
  elseif STAT_UP[fx] then
    if stageOf(user, STAT_UP[fx]) >= 2 or doomed then return 0 end
    -- set up only while nobody can punish it for the turn
    if incoming < hp * 0.4 then return (user.turnsOut or 0) <= 2 and 26 or 10 end
    return (pct > 70 and (user.turnsOut or 0) <= 1) and 8 or 2
  elseif fx == "REFLECT_EFFECT" then
    if user.reflect or (side and side.reflect) then return 0 end
    return 8 + 14 * (plan.physical or 0)
  elseif fx == "LIGHT_SCREEN_EFFECT" then
    if user.lightScreen or (side and side.lightScreen) then return 0 end
    return 8 + 14 * (plan.special or 0)
  elseif fx == "PROTECT_EFFECT" or fx == "ENDURE_EFFECT" then
    -- a second PROTECT in a row is likely to fail (the engine counts protectRun)
    if user.protectedLastTurn or (user.protectCount or 0) > 0 or (user.protectRun or 0) > 0 then return 0 end
    -- about to be knocked out first: shield, and the partner hits freely
    if doomed then return ally and 55 or 30 end
    if incoming >= hp then return 25 end
    return pct < 30 and 18 or 3
  elseif fx == "SUBSTITUTE_EFFECT" then
    if user.substituteHP or pct < 30 then return 0 end
    return incoming >= cap / 4 and 5 or 18           -- a doll that survives a hit
  elseif fx == "BELLY_DRUM_EFFECT" then
    return (pct > 75 and stageOf(user, "attack") < 6 and incoming < hp / 2) and 30 or 0
  elseif fx == "SPLASH_EFFECT" then
    return 0
  end
  return 8
end

-- ---------------------------------------------------------------------
-- the options one foe has
-- ---------------------------------------------------------------------

-- Every (move, target) `user` could pick from `usable`, each scored on its
-- own part only:
--   base    what does not depend on the partner (self moves, the cost of
--           hitting its own partner, blowing itself up)
--   hits    { [foe index] = { d, p, first } } for a damaging move
--   status  the foe a status move is aimed at, `sv` its raw worth
local function optionsFor(battle, plan, user, usable, foes, ally)
  local moves = battle.data and battle.data.moves or {}
  local doomed = plan.doomed and plan.doomed[user]
  local out = {}
  for _, mv in ipairs(usable) do
    local def = moves[mv.id]
    if def then
      local kind = Targeting.kindOf(def)
      local acc = accuracy(def)
      local damaging = (tonumber(def.power) or 0) > 0
      local factor = 1
      if TWO_TURN[def.effect] and not (def.effect == "SOLARBEAM_EFFECT" and battle.field
                                       and battle.field.weather == "SUN") then
        factor = 0.55
      elseif def.effect == "HYPER_BEAM_EFFECT" then
        factor = 0.8
      end
      -- trading itself away is fine when it is going down this turn anyway
      local boom = (def.effect == "EXPLODE_EFFECT" and hpPct(user) > 35 and not doomed) and -120 or 0
      local function hit(f, spread)
        local d = estimate(battle, user, f, def, spread)
        if d <= 0 then return nil end
        return { d = d, p = acc * factor, first = movesFirst(battle, user, def, f) }
      end
      if kind == Targeting.USER or kind == Targeting.OPPONENTS_FIELD or kind == Targeting.ALLY then
        out[#out + 1] = { mv = mv, base = selfValue(battle, plan, user, ally, def), hits = {} }
      elseif kind == Targeting.BOTH or kind == Targeting.FOES_AND_ALLY then
        local o = { mv = mv, base = boom, hits = {} }
        -- the spread cut needs two targets still standing
        local standing = 0
        for _, f in ipairs(foes) do if (f.mon.hp or 0) > 0 then standing = standing + 1 end end
        if kind == Targeting.FOES_AND_ALLY and ally and (ally.mon.hp or 0) > 0 then standing = standing + 1 end
        for i, f in ipairs(foes) do
          if damaging then
            o.hits[i] = hit(f, standing > 1)
          else
            o.base = o.base + statusValue(battle, user, f, def, foes) * 0.75 * threatMul(plan, f)
          end
        end
        if kind == Targeting.FOES_AND_ALLY and ally and damaging then
          local d = estimate(battle, user, ally, def, true)
          local cost = math.min(d, ally.mon.hp) * 100 / maxHp(ally)
          if d >= ally.mon.hp then cost = cost + 70 end
          o.base = o.base - cost * 1.2
        end
        out[#out + 1] = o
      else
        for i, f in ipairs(foes) do
          if damaging then
            out[#out + 1] = { mv = mv, target = f, base = boom, hits = { [i] = hit(f, false) } }
          else
            out[#out + 1] = { mv = mv, target = f, base = 0, hits = {}, status = i,
                              major = MAJOR_STATUS[def.effect] or false,
                              sv = statusValue(battle, user, f, def, foes) * threatMul(plan, f) }
          end
        end
      end
    end
  end
  return out
end

-- one option on top of what is already planned (and, in a pair, of what
-- the partner's option adds): the damage it adds, plus its status part
local function score(battle, plan, foes, a, b)
  local s = a.base + (b and b.base or 0)
  local koP = {}
  for i, f in ipairs(foes) do
    local extra = {}
    if a.hits[i] then extra[#extra + 1] = a.hits[i] end
    if b and b.hits[i] then extra[#extra + 1] = b.hits[i] end
    local before = dmgValue(battle, plan, f, planned(plan, f))
    local after, p = dmgValue(battle, plan, f, planned(plan, f, extra))
    s = s + after - before
    koP[i] = p
  end
  local function statusPart(o, other)
    if not o or not o.status then return 0 end
    local i = o.status
    local f = foes[i]
    if o.major and plan.statused and plan.statused[f] then return 0 end
    -- two foes do not both put the same Pokemon to sleep
    if o.major and other and other.status == i and other.major and other.sv >= o.sv then return 0 end
    return o.sv * (1 - (koP[i] or 0))
  end
  s = s + statusPart(a, b) + statusPart(b, a)
  return math.floor(s * 10 + 0.5)
end

local function commit(plan, foes, o)
  plan.hits = plan.hits or {}
  for i, f in ipairs(foes) do
    local h = o.hits[i]
    if h then
      plan.hits[f] = plan.hits[f] or {}
      table.insert(plan.hits[f], h)
    end
  end
  if o.status and o.major then
    plan.statused = plan.statused or {}
    plan.statused[foes[o.status]] = true
  end
end

local function inList(list, mv)
  for _, x in ipairs(list) do if x == mv then return true end end
  return false
end

-- reset the shared plan; the battle calls this before the foes choose
function DoublesAI.beginTurn(battle)
  battle.doublesAIPlan = {}
end

-- Best (move, target) for `user` among `usable` (entries of user.curMoves).
-- `target` is nil for a move that picks its own (spread, self).  Answers nil
-- when nothing scores at all, so the caller keeps its old behaviour.
function DoublesAI.choose(battle, user, usable)
  if not (battle and user and usable and usable[1]) then return nil end
  local foes = {}
  for _, f in ipairs(battle:foesOf(user)) do if alive(f) then foes[#foes + 1] = f end end
  if #foes == 0 then return nil end
  local ally = battle.partnerOf and battle:partnerOf(user)
  if not alive(ally) then ally = nil end
  local plan = battle.doublesAIPlan or {}
  battle.doublesAIPlan = plan
  plan.chosen = plan.chosen or {}
  plan.assign = plan.assign or {}

  -- the side standing, in position order, for the scouting
  local side = {}
  for _, b in ipairs(battle:foesOf(foes[1])) do if alive(b) then side[#side + 1] = b end end
  DoublesAI.scout(battle, plan, foes, side)

  -- the partner already planned this foe's half of the turn
  local given = plan.assign[user]
  plan.assign[user] = nil
  if given and inList(usable, given.mv) then
    plan.chosen[user] = true
    commit(plan, foes, given)
    return given.mv, given.target
  end

  local mine = optionsFor(battle, plan, user, usable, foes, ally)
  if #mine == 0 then return nil end

  -- PLAN THE TURN TOGETHER when the partner chooses after this one and is
  -- free to: every pair is scored at once.  A tie keeps the first pair found
  -- (this foe's moves in slot order, then the partner's) -- no RNG, so the
  -- number of draws does not depend on how many pairs tied.
  local locked = ally and battle.lockedAction and battle:lockedAction(ally)
  if ally and not locked and not plan.chosen[ally]
     and (tonumber(user.position) or 0) < (tonumber(ally.position) or 0) then
    local theirs = optionsFor(battle, plan, ally, usableOf(ally), foes, user)
    if #theirs > 0 then
      local best, bestA, bestB
      for _, a in ipairs(mine) do
        for _, b in ipairs(theirs) do
          local s = score(battle, plan, foes, a, b)
          if best == nil or s > best then best, bestA, bestB = s, a, b end
        end
      end
      if best and best > 0 then
        plan.chosen[user] = true
        plan.assign[ally] = bestB
        commit(plan, foes, bestA)
        return bestA.mv, bestA.target
      end
    end
  end

  -- on its own: the best option on top of what is already planned
  local best, tied = nil, {}
  for _, o in ipairs(mine) do
    local s = score(battle, plan, foes, o, nil)
    if best == nil or s > best then
      best, tied = s, { o }
    elseif s == best then
      tied[#tied + 1] = o
    end
  end
  if best == nil or best <= 0 then return nil end
  local pick = tied[1]
  if #tied > 1 and battle.rng then pick = tied[battle.rng(1, #tied)] end
  plan.chosen[user] = true
  commit(plan, foes, pick)
  return pick.mv, pick.target
end

return DoublesAI
