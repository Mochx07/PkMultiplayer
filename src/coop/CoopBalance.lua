-- src/coop/CoopBalance.lua
-- CO-OP DIFFICULTY.  Two players bring up to six Pokemon between them to a
-- trainer who brought the team it would use against one: a gym leader with
-- three fell before he had done anything.  Two shared rules (the host's word,
-- like the others) make the foe a match for the pair:
--
--   BALANCED FOES (on by default)  the trainer brings at least two foes for
--       every three of yours -- the extra ones are copies of its own team, in
--       order -- and its team is a level or two up when yours is ahead of it
--   HARD FOES  one foe for each of yours, and three levels on top
--
-- Both off is the cartridge's team.  Only trainer doubles: a wild pair, the
-- Battle Tower (its own level rules) and P1 vs P2 are never touched.  Both
-- copies of the battle work it out from the same two lists of chosen
-- Pokemon and the same trainer, with no dice, so they agree to the level.

local CoopManager = require("src.coop.CoopManager")

local CoopBalance = {}

CoopManager.addRule("balancedFoes", "BALANCED FOES", true)
CoopManager.addRule("hardFoes", "HARD FOES", false)

CoopBalance.MAX_PARTY = 6

local function fighters(list)
  local n, levels = 0, 0
  for _, m in ipairs(list or {}) do
    if type(m) == "table" and not m.isEgg and (tonumber(m.hp) or 1) > 0 then
      n = n + 1
      levels = levels + (tonumber(m.level) or 1)
    end
  end
  return n, levels
end

local function copyMon(m)
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

-- `mon` at `level`, its stats worked out again the cartridge's way
local function relevel(data, mon, level)
  local def = data and data.pokemon and data.pokemon[mon.species]
  if not def or level == mon.level then return end
  local okS, Stats = pcall(require, "src.pokemon.Stats")
  if not okS then return end
  local ok, stats = pcall(Stats.calc, def, level, mon.dvs, mon.statExp)
  if not (ok and type(stats) == "table") then return end
  mon.level = level
  mon.stats = stats
  mon.hp = stats.hp
  local okG, Growth = pcall(require, "src.pokemon.Growth")
  if okG and Growth.expForLevel and def.growthRate then
    local okE, exp = pcall(Growth.expForLevel, def.growthRate, level)
    if okE then mon.exp = exp end
  end
end

-- What the rules ask of a trainer facing these two teams: { foes, boost },
-- or nil for the cartridge's own team.
function CoopBalance.plan(enemyParty, mineList, theirsList)
  local hard = CoopManager.hardFoes == true
  if not (hard or CoopManager.balancedFoes) then return nil end
  local a, la = fighters(mineList)
  local b, lb = fighters(theirsList)
  local players, playerLevels = a + b, la + lb
  local foes, foeLevels = fighters(enemyParty)
  if players == 0 or foes == 0 then return nil end
  local want = hard and players or math.ceil(players * 2 / 3)
  want = math.min(CoopBalance.MAX_PARTY, math.max(foes, want))
  local ahead = playerLevels / players - foeLevels / foes
  local boost = 0
  if hard then
    boost = 3
  elseif ahead >= 5 then
    boost = 2
  elseif ahead > 0 then
    boost = 1
  end
  if want == foes and boost == 0 then return nil end
  return { foes = want, boost = boost }
end

-- Applies the plan to battle.enemyParty in place.  Returns true when the
-- party changed (the caller places the lead foe again).
function CoopBalance.apply(battle, mineList, theirsList)
  if type(battle) ~= "table" or type(battle.enemyParty) ~= "table" then return false end
  if battle.coopWild or battle.battleTower or battle.isLinkBattle then return false end
  local plan = CoopBalance.plan(battle.enemyParty, mineList, theirsList)
  if not plan then return false end
  local data = (battle.game and battle.game.data) or battle.data
  local party = battle.enemyParty
  local own = #party
  for i = own + 1, plan.foes do
    local copy = copyMon(party[((i - own - 1) % own) + 1])
    if copy then
      copy.hp = (copy.stats and copy.stats.hp) or copy.hp
      copy.status = nil
      party[#party + 1] = copy
    end
  end
  if plan.boost > 0 then
    for _, m in ipairs(party) do
      if type(m) == "table" then
        relevel(data, m, math.min(100, (tonumber(m.level) or 1) + plan.boost))
      end
    end
  end
  battle.coopBalanced = plan
  require("src.coop.CoopLog").battle("BALANCE", string.format("foe brings %d (had %d), +%d levels",
                                     #party, own, plan.boost))
  return true
end

return CoopBalance
