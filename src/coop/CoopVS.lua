-- src/coop/CoopVS.lua
-- VS FORMATS for the P1-vs-P2 battle (1.20, capability "vs.formats").
--
-- The Cable Club battle (src/link LinkBattle) already plays a lockstep link
-- battle and can level every Pokemon to one level (`forceLevel`, the host's
-- rule).  A format adds what a fair match needs on top of that, the way the
-- player knows it from the Stadium-style cups:
--
--   FREE BATTLE   real levels, no rules: the old P1 VS P2
--   LEVEL 50      everyone at 50; no legends, no one-hit KO or evasion moves,
--                 one of each species, one of each held item
--   LEVEL 100     the same at 100
--   LITTLE CUP    Pokemon that have not evolved yet and still can, at 5
--   ONE TYPE      the same rules as LEVEL 50, the whole team shares a type
--
-- Nobody has to rearrange their party at the PC first: legalParty() takes
-- the party as it is, keeps the Pokemon the format allows (in party order)
-- and names the ones it left out, and only refuses when none is left.  Each
-- copy checks its own party; the one that is sent to the battle is the kept
-- one (CoopVS.packFor, called from the Protocol.packParty hook).
local CoopVS = {}

-- Pokedex numbers, the same in Red/Blue/Yellow and Gold/Silver/Crystal
CoopVS.LEGENDS = { [150] = true, [151] = true, [249] = true, [250] = true, [251] = true }
CoopVS.OHKO_MOVES = { FISSURE = true, HORN_DRILL = true, GUILLOTINE = true }
CoopVS.EVASION_MOVES = { DOUBLE_TEAM = true, MINIMIZE = true }

local CUP = { species = true, item = true, legends = true, ohko = true, evasion = true }

CoopVS.FORMATS = {
  { id = "free", name = "FREE BATTLE", invite = "P1 VS P2 BATTLE?",
    info = { "REAL LEVELS AND", "NO RULES: THE", "CLASSIC P1 VS P2." } },
  { id = "lv50", name = "LEVEL 50", invite = "LEVEL 50 RULES", level = 50, rules = CUP,
    info = { "ALL AT LEVEL 50.", "NO LEGENDS, OHKO", "OR EVASION MOVES." } },
  { id = "lv100", name = "LEVEL 100", invite = "LEVEL 100 RULES", level = 100, rules = CUP,
    info = { "ALL AT LEVEL 100.", "SAME RULES AS", "LEVEL 50." } },
  { id = "little", name = "LITTLE CUP", invite = "LITTLE CUP RULES", level = 5, rules = CUP, little = true,
    info = { "ONLY POKéMON THAT", "CAN STILL EVOLVE,", "ALL AT LEVEL 5." } },
  { id = "mono", name = "ONE TYPE", invite = "ONE TYPE RULES", level = 50, rules = CUP, mono = true,
    info = { "THE WHOLE TEAM", "SHARES ONE TYPE,", "ALL AT LEVEL 50." } },
}
for _, f in ipairs(CoopVS.FORMATS) do CoopVS.FORMATS[f.id] = f end

function CoopVS.format(id)
  return type(id) == "string" and CoopVS.FORMATS[id] or nil
end

local function isEgg(mon)
  return mon.isEgg == true or (tonumber(mon.eggSteps) or 0) > 0
end

local function speciesDef(data, mon)
  return data and data.pokemon and data.pokemon[mon.species] or nil
end

-- species some other species evolves into, per data table
local evolvedCache = setmetatable({}, { __mode = "k" })
local function evolvedSet(data)
  local set = evolvedCache[data]
  if set then return set end
  set = {}
  for _, def in pairs(data and data.pokemon or {}) do
    if type(def) == "table" then
      for _, e in ipairs(def.evolutions or {}) do
        if type(e) == "table" and e.species then set[e.species] = true end
      end
    end
  end
  evolvedCache[data] = set
  return set
end

-- LITTLE CUP: has an evolution and is nobody's evolution
function CoopVS.isLittle(data, species)
  local def = data and data.pokemon and data.pokemon[species]
  if not (def and def.evolutions and #def.evolutions > 0) then return false end
  return not evolvedSet(data)[species]
end

local function typesOf(data, mon)
  local def = speciesDef(data, mon)
  return (def and def.types) or {}
end

-- why `mon` may not play `fmt` on its own (the team rules come after), or nil
local function soloProblem(data, mon, fmt)
  if type(mon) ~= "table" then return "NO POKéMON" end
  if isEgg(mon) then return "EGG" end
  local rules = fmt.rules or {}
  local def = speciesDef(data, mon)
  if rules.legends and def and CoopVS.LEGENDS[tonumber(def.dex) or -1] then return "BANNED" end
  if fmt.little and not CoopVS.isLittle(data, mon.species) then return "ALREADY EVOLVED" end
  for _, mv in ipairs(mon.moves or {}) do
    local id = type(mv) == "table" and mv.id or mv
    if (rules.ohko and CoopVS.OHKO_MOVES[id]) or (rules.evasion and CoopVS.EVASION_MOVES[id]) then
      return "BANNED MOVE"
    end
  end
  return nil
end

-- ONE TYPE: of the lead's types, the one most of the team shares
local function teamType(data, mons)
  local best, bestN
  for _, t in ipairs(typesOf(data, mons[1])) do
    local n = 0
    for _, m in ipairs(mons) do
      for _, u in ipairs(typesOf(data, m)) do if u == t then n = n + 1 break end end
    end
    if not bestN or n > bestN then best, bestN = t, n end
  end
  return best
end

-- party -> kept (the Pokemon that play, in party order), left ({ mon, why }),
-- err (nil, or why nothing can play)
function CoopVS.legalParty(data, party, fmt)
  local kept, left = {}, {}
  if type(fmt) ~= "table" then return kept, left, "NO SUCH RULES" end
  local rules = fmt.rules or {}
  local seenSpecies, seenItem = {}, {}
  for _, mon in ipairs(party or {}) do
    local why = soloProblem(data, mon, fmt)
    if not why and rules.species and seenSpecies[mon.species] then why = "SAME SPECIES" end
    if not why and rules.item and mon.item and mon.item ~= "" and mon.item ~= "NO_ITEM"
       and seenItem[mon.item] then
      why = "SAME ITEM"
    end
    if why then
      if not isEgg(mon) then left[#left + 1] = { mon = mon, why = why } end
    else
      kept[#kept + 1] = mon
      seenSpecies[mon.species] = true
      if mon.item then seenItem[mon.item] = true end
    end
  end
  if fmt.mono and #kept > 0 then
    local t = teamType(data, kept)
    local mono = {}
    for _, m in ipairs(kept) do
      local has = false
      for _, u in ipairs(typesOf(data, m)) do if u == t then has = true break end end
      if has then mono[#mono + 1] = m else left[#left + 1] = { mon = m, why = "OTHER TYPE" } end
    end
    kept = mono
  end
  if #kept == 0 then return kept, left, "Your team breaks the rules" end
  return kept, left, nil
end

-- ---------------------------------------------------------------------
-- the battle: the tunnel carries the format and the kept party
-- ---------------------------------------------------------------------

-- Called when the Cable Club opens for a format battle; `tunnel` is
-- CoopLink's adapter, so all of this ends with it.
function CoopVS.attach(tunnel, game, fmt)
  if not (tunnel and game and game.save and fmt) or fmt.id == "free" then return nil end
  local kept, left, err = CoopVS.legalParty(game.data, game.save.party, fmt)
  if err then return nil, err end
  tunnel.vs = { format = fmt, party = kept, left = left, save = game.save.party }
  return tunnel.vs
end

-- Protocol.packParty's hook: the save's party in a format battle is the kept
-- part of it (the same table, so a trade or anything else is untouched)
function CoopVS.packFor(party)
  local ok, CoopLink = pcall(require, "src.coop.CoopLink")
  local t = ok and CoopLink.adapter
  local vs = t and not t.closed and t.vs
  if vs and party == vs.save then return vs.party end
  return party
end

-- the asker is the Cable Club's host: it picks the level rule in a menu
-- (battleOptions) -- in a format battle the format already picked it
function CoopVS.skipLevelMenu(ls, fmt)
  local decide = ls.decideCompat
  ls.decideCompat = function(self, mode, isHost)
    decide(self, mode, isHost)
    if self.stage == "battleOptions" then
      self.forceLevel = fmt.level
      self:startMode(mode, true)
    end
  end
end

return CoopVS
