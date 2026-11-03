-- src/coop/CoopSleepClause.lua
-- THE SLEEP CLAUSE of the VS formats (1.20, capability "vs.sleep").
--
-- In a format battle (LEVEL 50, LEVEL 100, LITTLE CUP, ONE TYPE -- never a
-- FREE BATTLE, never outside the Cable Club) a team may have only one
-- Pokemon put to sleep by the other side at a time: while one of them is
-- still asleep from a foe's move, a move that would put a second one to
-- sleep fails, with its own line instead of the sleep.
--
-- What counts, and what does not:
--   * only sleep the OTHER side caused with a move (SPORE, HYPNOSIS, SING,
--     SLEEP POWDER, LOVELY KISS, and the same moves called by METRONOME or
--     MIRROR MOVE) puts a Pokemon on the clause
--   * a team's OWN sleep -- REST, also through SLEEP TALK -- never counts and
--     is never stopped: resting is a choice, not something done to the team.
--     A Pokemon the foe put to sleep that then RESTs is asleep by its own
--     move from then on and no longer holds the clause
--   * a Pokemon that woke up (or was cured) or fainted no longer counts; one
--     switched out while asleep still does, as it is still asleep
--
-- LOCKSTEP.  Both copies run the battle and so must both apply the rule the
-- same way: it reads nothing but the battle itself (the parties, who used
-- the move), it rolls nothing when it stops a sleep (the engine's sleep
-- counter roll is skipped on both copies alike), and it is only armed when
-- both copies have it (bothHave(CAP)), decided once, before the battle, from
-- the format both agreed on.  A replay notes that the clause was on
-- (CoopReplay `sleepClause`) and the spectator that plays it is armed the
-- same way, so the replay fails the same move the battle did.
--
-- How it sits in the engine (lib/Hooks.lua): LinkBattle.new and
-- LinkBattle.newSpectator arm the battle when their net -- the co-op tunnel
-- or the replay's feed -- carries `sleepClause`; StatusRegistry.inflict, the
-- one place a sleep move lands, asks inflict() below first in an armed
-- battle only.  Every other battle never gets here.
local CoopSleepClause = {}

CoopSleepClause.CAP = "vs.sleep"
CoopSleepClause.TEXT = "SLEEP CLAUSE:\nit won't sleep!"

-- does this format play under the clause on both copies?
function CoopSleepClause.agreed(fmt)
  if not (type(fmt) == "table" and type(fmt.rules) == "table" and fmt.rules.sleep) then return false end
  local ok, CM = pcall(require, "src.coop.CoopManager")
  return ok and type(CM) == "table" and CM.bothHave ~= nil and CM.bothHave(CoopSleepClause.CAP) or false
end

-- the line shown when the clause stops a sleep, in the player's language
-- (text only: the two copies may read it in different languages)
function CoopSleepClause.message()
  local ok, I18n = pcall(require, "src.coop.CoopI18n")
  if ok and I18n.t then return I18n.t(CoopSleepClause.TEXT) end
  return CoopSleepClause.TEXT
end

local function asleep(mon)
  return type(mon) == "table" and mon.status == "SLP" and (tonumber(mon.hp) or 0) > 0
end

-- `battle`'s Pokemon that woke up, were cured or fainted leave the clause
function CoopSleepClause.sweep(battle)
  local st = battle and battle.coopSleepClause
  if not st then return end
  for _, party in ipairs({ battle.playerParty or {}, battle.enemyParty or {} }) do
    for _, mon in ipairs(party) do
      if st.asleep[mon] and not asleep(mon) then st.asleep[mon] = nil end
    end
  end
end

-- the Pokemon of `target`'s team, other than the target, that is asleep from
-- a foe's move (in party order), or nil
function CoopSleepClause.holder(battle, target)
  local st = battle and battle.coopSleepClause
  if not (st and target) then return nil end
  local party = target.isPlayer and battle.playerParty or battle.enemyParty
  for _, mon in ipairs(party or {}) do
    if mon ~= target.mon and st.asleep[mon] and asleep(mon) then return mon end
  end
  return nil
end

-- is this sleep the other side's doing, with a move?
function CoopSleepClause.fromFoe(battle, target, opts)
  if type(opts) ~= "table" or opts.selfInflicted or opts.synchronized then return false end
  local moves = battle.data and battle.data.moves
  if not (opts.source and moves and moves[opts.source]) then return false end
  -- the battle notes who is using the move (BattleState:performMove)
  local user = opts.user or battle.lastAttacker
  return type(user) == "table" and user ~= target and user.isPlayer ~= target.isPlayer
end

-- StatusRegistry.inflict in an armed battle (lib/Hooks.lua)
function CoopSleepClause.inflict(inflict, battle, target, status, opts, ...)
  local st = battle.coopSleepClause
  if status ~= "SLP" or type(target) ~= "table" or type(target.mon) ~= "table" then
    return inflict(battle, target, status, opts, ...)
  end
  local foe = CoopSleepClause.fromFoe(battle, target, opts)
  -- a target that cannot fall asleep anyway (already has a status, behind
  -- SAFEGUARD) fails the engine's own way
  if foe and not target.mon.status and not target.safeguardTurns then
    CoopSleepClause.sweep(battle)
    if CoopSleepClause.holder(battle, target) then
      st.blocked = st.blocked + 1
      -- the move fails: no sleep animation, as for "But, it failed!"
      if battle.cancelMoveAnim then battle:cancelMoveAnim() end
      return { CoopSleepClause.message() }
    end
  end
  local msgs = inflict(battle, target, status, opts, ...)
  -- (a MINT BERRY may already have woken it)
  if foe and asleep(target.mon) then st.asleep[target.mon] = true end
  return msgs
end

-- `battle` plays under the clause from now on
function CoopSleepClause.arm(battle)
  if type(battle) ~= "table" or battle.coopSleepClause then return battle end
  local st = { asleep = {}, blocked = 0 }
  battle.coopSleepClause = st
  local perform = battle.performMove
  if type(perform) == "function" then
    battle.performMove = function(s, user, target, moveInst, ...)
      CoopSleepClause.sweep(s)
      local mon = type(user) == "table" and user.mon or nil
      local hpBefore = mon and mon.hp
      local a, b, c = perform(s, user, target, moveInst, ...)
      -- a REST that worked (picked, or called by SLEEP TALK): the sleep is
      -- the Pokemon's own now
      if mon and st.asleep[mon] and mon.status == "SLP" and mon.stats
         and hpBefore and hpBefore < mon.stats.hp and mon.hp == mon.stats.hp then
        local move = s.moveDef and s:moveDef(moveInst)
        if move and move.id == "REST" then st.asleep[mon] = nil end
      end
      return a, b, c
    end
  end
  return battle
end

return CoopSleepClause
