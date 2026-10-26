-- src/battle/SinglesAI.lua
-- SMARTER TRAINERS IN GOLD, SILVER AND CRYSTAL.  The engine reads Gen 1's
-- trainer AI layers only: a Gen 2 trainer's record carries none, so in a
-- single battle every Johto trainer -- Whitney, Lance, the rival -- picked a
-- move at random, GROWL as often as its best hit.  Here the same scouting the
-- co-op doubles foes use (DoublesAI: who can knock out whom, who moves
-- first, what is already set up) picks the move instead:
--
--   * gym leaders, the Elite Four, the champion, the rival, RED and the
--     Rocket executives always do;
--   * a COOLTRAINER most of the time; everyone else about half of the time,
--     and otherwise the cartridge's pick -- a route trainer should not play
--     like a gym leader against someone just starting out.
--
-- Only the MOVE is chosen here.  A trainer's item or switch (the class AI),
-- a locked move (THRASH, a charging SOLARBEAM) and anything a link, the
-- Battle Tower's own rules or a co-op double decide stay as they were.
-- MODS -> PkMultiplayer -> OPTIONS -> SMARTER TRAINERS switches it off.

local DoublesAI = require("src.battle.DoublesAI")

local SinglesAI = {}

local FULL_PATTERNS = { "^OPP_LEADER", "^OPP_ELITE_FOUR", "^OPP_CHAMPION", "^OPP_RIVAL",
                        "^OPP_PKMN_TRAINER_RED", "^OPP_ROCKET_EXECUTIVE" }

function SinglesAI.skill(oppClass)
  if type(oppClass) ~= "string" then return 0.5 end
  for _, p in ipairs(FULL_PATTERNS) do
    if oppClass:find(p) then return 1 end
  end
  if oppClass:find("^OPP_COOLTRAINER") then return 0.8 end
  return 0.5
end

function SinglesAI.isGen2()
  local ok, V = pcall(require, "src.core.GameVersion")
  return ok and V.isGen2 and V.isGen2() or false
end

-- the switch in the MODS panel (main.lua); on when there is no panel
function SinglesAI.on()
  local o = package.loaded["pkmultiplayer.options"]
  return not (o and o.on) or o.on("smartTrainers")
end

function SinglesAI.applies(battle)
  if type(battle) ~= "table" or battle.kind ~= "trainer" then return false end
  if battle.coopDouble or battle.coopWild or battle.pokedudeDemo or battle.palace then return false end
  if battle.isDouble and battle:isDouble() then return false end
  return SinglesAI.on() and SinglesAI.isGen2()
end

local function isMoveOf(battler, action)
  for _, mv in ipairs(battler.curMoves or {}) do
    if mv == action then return true end
  end
  return false
end

local function usableOf(b)
  local out = {}
  for i, mv in ipairs(b.curMoves or {}) do
    if b.disabledSlot ~= i and (mv.pp or 0) > 0 then out[#out + 1] = mv end
  end
  return out
end

-- the battle.enemy_action hook: `next` is the engine's own choice
function SinglesAI.enemyAction(next, battle, who)
  local action = next(battle, who)
  if not SinglesAI.applies(battle) then return action end
  who = who or battle.enemy
  if not who or (battle.lockedAction and battle:lockedAction(who)) then return action end
  -- the class AI used an item or switched: that stays
  if type(action) ~= "table" or not isMoveOf(who, action) then return action end
  local roll = battle.rng and battle.rng() or math.random()
  if roll >= SinglesAI.skill(battle.oppClass) then return action end
  local usable = usableOf(who)
  if #usable < 2 then return action end
  DoublesAI.beginTurn(battle)
  local ok, mv = pcall(DoublesAI.choose, battle, who, usable)
  if ok and mv then return mv end
  return action
end

return SinglesAI
