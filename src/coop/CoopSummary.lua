-- src/coop/CoopSummary.lua
-- THE CO-OP RESULT, after every co-op double: who knocked out how many of
-- the foes, the experience each of you took home, and the Pokemon that did
-- the most.  It shows for a few seconds at the top of the screen once the
-- overworld is back, without stopping anyone -- the partner may already be
-- walking off.
--
-- Counted from the engine's own battle events (main.lua subscribes):
--   battle.fainted     -- a foe down; BattleState:killerOf says who did it
--   battle.exp_gained  -- a Pokemon paid; each copy pays both teams the same
--                         split, so both screens add up to the same numbers
-- A Pokemon is the partner's when it is one of the battle's ally party (the
-- copies of their team); every other one on our side is ours.

local CoopSummary = {}

CoopSummary.SHOW = 6       -- seconds on screen
CoopSummary.pending = nil  -- { lines = {...}, since = first drawn } waiting to show

local function owner(battle, mon)
  local party = battle and battle.ally and battle.ally.party
  for _, m in ipairs(type(party) == "table" and party or {}) do
    if m == mon then return "partner" end
  end
  return "you"
end

local function monName(battle, mon)
  if type(mon) ~= "table" then return "?" end
  local def = battle and battle.data and battle.data.pokemon and battle.data.pokemon[mon.species]
  return string.upper(tostring(mon.nickname or (def and def.name) or mon.species or "?"))
end

-- CoopBattle.initBattle: a fresh tally for this battle
function CoopSummary.begin(battle)
  if type(battle) ~= "table" then return end
  battle.coopTally = { ko = { you = 0, partner = 0 }, exp = { you = 0, partner = 0 },
                       byMon = {}, names = {} }
end

function CoopSummary.onFainted(payload)
  local battle = type(payload) == "table" and payload.battle
  local fallen = type(payload) == "table" and payload.battler
  local tally = type(battle) == "table" and battle.coopTally
  if not (tally and type(fallen) == "table") or fallen.isPlayer then return end
  local killer = battle.killerOf and battle:killerOf(fallen)
  if not (type(killer) == "table" and killer.isPlayer and killer.mon) then return end
  local who = owner(battle, killer.mon)
  tally.ko[who] = tally.ko[who] + 1
  tally.byMon[killer.mon] = (tally.byMon[killer.mon] or 0) + 1
  tally.names[killer.mon] = monName(battle, killer.mon)
end

function CoopSummary.onExpGained(payload)
  local battle = type(payload) == "table" and payload.battle
  local tally = type(battle) == "table" and battle.coopTally
  local gained = tonumber(type(payload) == "table" and payload.gained)
  if not (tally and gained and gained > 0) then return end
  local who = owner(battle, payload.mon)
  tally.exp[who] = tally.exp[who] + gained
end

local function short(name, n)
  return require("src.coop.CoopI18n").truncate(string.upper(tostring(name or "")), n)
end

-- the lines for a finished battle (nil when it was not a co-op one)
function CoopSummary.lines(battle, result, youName, partnerName)
  local tally = type(battle) == "table" and battle.coopTally
  if not tally then return nil end
  -- run from, or lost before anyone landed a blow: nothing to tell
  if tally.ko.you + tally.ko.partner == 0 and tally.exp.you + tally.exp.partner == 0 then return nil end
  local lines = { result == "win" and "CO-OP WIN!" or "CO-OP RESULT" }
  lines[2] = string.format("%s %dKO %dXP", short(youName or "YOU", 6), tally.ko.you, tally.exp.you)
  lines[3] = string.format("%s %dKO %dXP", short(partnerName or "P2", 6), tally.ko.partner, tally.exp.partner)
  local best, most = nil, 0
  for mon, n in pairs(tally.byMon) do
    if n > most or (n == most and best and tally.names[mon] < tally.names[best]) then
      best, most = mon, n
    end
  end
  if best then lines[4] = string.format("MVP: %s", short(tally.names[best], 10)) end
  return lines
end

-- OverworldState:afterBattle (lib/Hooks.lua): the result waits to be shown
function CoopSummary.finish(battle, result)
  if type(battle) ~= "table" or not battle.coopTally then return end
  local CM = package.loaded["src.coop.CoopManager"]
  local you = CM and CM.getLocalPlayerName and CM.getLocalPlayerName() or "YOU"
  local partner = CM and CM.partner and CM.partner.name or "P2"
  local lines = CoopSummary.lines(battle, result, you, partner)
  battle.coopTally = nil
  if lines then CoopSummary.pending = { lines = lines } end
end

-- the lines to draw at time `t`; the clock starts the first time they are
-- drawn (the overworld back on screen), not as the battle ends
function CoopSummary.current(t)
  local p = CoopSummary.pending
  if not (p and t) then return nil end
  p.since = p.since or t
  if t - p.since > CoopSummary.SHOW then
    CoopSummary.pending = nil
    return nil
  end
  return p.lines
end

return CoopSummary
