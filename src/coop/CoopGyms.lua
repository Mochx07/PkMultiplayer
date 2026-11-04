-- src/coop/CoopGyms.lua
-- GYMS FOR TWO AND THE RIVAL 2v2 (1.20, capability "story.gyms").
--
-- A co-op gym battle used to be the cartridge's leader padded out with
-- copies of his own team (CoopBalance): FALKNER with two PIDGEOTTO and two
-- PIDGEY.  With both players on 1.20 the leader brings a team made for two:
--
--   * MORE OF HIS TYPE.  Two more Pokemon (one when the two of you bring three
--     or fewer between you), at least two foes for every three of yours, up
--     to six: species of the leader's type from POOLS below, ones his team
--     does not already have first, put in before his ace.
--   * ABOVE THE ONE BEHIND.  His whole team moves up together, keeping its
--     spread, until his lowest Pokemon is a level above the weaker team's
--     average.  Never down: a pair ahead of the cartridge faces the cartridge.
--     HARD FOES adds its three levels on top.
--   * NOTHING HANDED OUT.  Nothing in the battle's rewards changes here: the
--     badge, the TM and the money are still the cartridge's to give, one each
--     (CoopDuo), and the extra Pokemon are the leader's, not a gift.
--
-- THE RIVAL 2v2 (Gold, Silver, Crystal).  When the two meet him together
-- (the big-battle invite of CoopInvites/CoopReady), the far side is two
-- trainers, the way the engine fights two who walked up at once
-- (enemyParty / enemyPartyB, BattleState:addOpponentTrainer): the host's
-- rival on the left, the guest's own rival -- his name, and the team his
-- starter gave him -- on the right.  The guest says which (its starter flag
-- and its rival's name) when it is ready; the host's go carries the pair to
-- both copies, so both build the same two teams from the same data.  With
-- BALANCED FOES each rival brings his last four (his starter among them);
-- HARD FOES the whole team three levels up; both off the whole team.
--
-- Both copies work it out from the battle's own rules (the host's word,
-- foeRules.gymTeam) and the same two lists of chosen Pokemon, with no dice.
-- A 1.6.x partner never sees any of it: the rule is only set, and the rival
-- only offered, when both have the capability.

local CoopManager = require("src.coop.CoopManager")

local CoopGyms = {}

CoopGyms.CAP = "story.gyms"
CoopManager.registerCap(CoopGyms.CAP)

CoopGyms.MAX_PARTY = 6
CoopGyms.RIVAL_KEEP = 4      -- what each rival brings under BALANCED FOES
CoopGyms.HARD_LEVELS = 3

-- Species by name (the name the data gives them), the leader's type, in the
-- order they are added.  A name the game's data does not have is skipped.
CoopGyms.POOLS = {
  gen2 = {
    FALKNER = { "HOOTHOOT", "SPEAROW", "NATU", "DODUO" },
    BUGSY = { "LEDYBA", "SPINARAK", "BUTTERFREE", "BEEDRILL", "PARAS", "VENONAT" },
    WHITNEY = { "SNUBBULL", "TEDDIURSA", "AIPOM", "FURRET", "JIGGLYPUFF" },
    MORTY = { "MISDREAVUS", "GASTLY", "HAUNTER", "GENGAR" },
    CHUCK = { "MACHOKE", "HITMONLEE", "HITMONCHAN", "HERACROSS", "MANKEY" },
    JASMINE = { "SKARMORY", "FORRETRESS", "MAGNETON", "MAGNEMITE" },
    PRYCE = { "SWINUB", "SNEASEL", "JYNX", "CLOYSTER", "DELIBIRD" },
    CLAIR = { "SEADRA", "DRAGONAIR", "DRATINI", "HORSEA" },
    BROCK = { "SUDOWOODO", "GOLEM", "AERODACTYL" },
    MISTY = { "CLOYSTER", "LANTURN", "POLIWHIRL", "SEAKING" },
    LT_SURGE = { "AMPHAROS", "JOLTEON", "LANTURN" },
    ERIKA = { "VILEPLUME", "SUNFLORA", "EXEGGUTOR" },
    JANINE = { "MUK", "QWILFISH", "TENTACRUEL" },
    SABRINA = { "XATU", "GIRAFARIG", "SLOWBRO", "HYPNO" },
    BLAINE = { "ARCANINE", "FLAREON", "NINETALES" },
    BLUE = { "MACHAMP", "TAUROS" },
  },
  gen1 = {
    BROCK = { "GEODUDE", "RHYHORN", "OMANYTE", "KABUTO" },
    MISTY = { "HORSEA", "SHELLDER", "GOLDEEN", "STARYU" },
    LT_SURGE = { "PIKACHU", "MAGNEMITE", "ELECTABUZZ" },
    ERIKA = { "GLOOM", "WEEPINBELL", "TANGELA" },
    KOGA = { "GRIMER", "VENONAT", "WEEZING" },
    JANINE = { "GRIMER", "VENONAT", "WEEZING" },
    SABRINA = { "DROWZEE", "SLOWPOKE", "KADABRA" },
    BLAINE = { "GROWLITHE", "PONYTA", "MAGMAR" },
    GIOVANNI = { "SANDSLASH", "MAROWAK", "RHYHORN" },
  },
}

local function manager()
  return package.loaded["src.coop.CoopManager"] or CoopManager
end

function CoopGyms.on()
  local CM = manager()
  return CM.bothHave ~= nil and CM.bothHave(CoopGyms.CAP) == true
end

local function isGen1()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.isGen1 and GV.isGen1() == true
end

local function isGen2()
  local ok, GV = pcall(require, "src.core.GameVersion")
  if not ok then return false end
  if GV.isGen2 then return GV.isGen2() == true end
  return false
end

local function log(msg)
  pcall(function() require("src.coop.CoopLog").battle("GYMS", msg) end)
end

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

-- the leader's key in POOLS (FALKNER, BUGSY...), or nil when this trainer
-- is no leader with a badge to give
function CoopGyms.leaderKey(oppClass, partyIndex)
  if type(oppClass) ~= "string" then return nil end
  local CM = manager()
  if not (CM.leaderBadgeFor and CM.leaderBadgeFor(oppClass, partyIndex)) then return nil end
  local key = oppClass:upper():gsub("^OPP_", ""):gsub("^LEADER_", "")
  if key == "LEADER" then key = "FALKNER" end
  return key
end

-- name -> species id, built once per data table (the smallest id wins a tie,
-- so both copies pick the same one whatever order pairs() walks)
local nameIndex = setmetatable({}, { __mode = "k" })
local function speciesByName(data, name)
  local pokemon = data and data.pokemon
  if type(pokemon) ~= "table" then return nil end
  local idx = nameIndex[pokemon]
  if not idx then
    idx = {}
    for id, def in pairs(pokemon) do
      if type(def) == "table" and type(def.name) == "string" then
        local was = idx[def.name]
        if was == nil or tostring(id) < tostring(was) then idx[def.name] = id end
      end
    end
    nameIndex[pokemon] = idx
  end
  return idx[name]
end

-- The plan for a leader facing these two teams, or nil for none:
-- { foes = n, extras = { species ids, in order }, shift = levels, aceAt = i }
function CoopGyms.planGym(data, enemyParty, key, mineList, theirsList, rules)
  rules = type(rules) == "table" and rules or {}
  local hard = rules.hardFoes == true
  if not (hard or rules.balancedFoes == true) then return nil end
  if type(enemyParty) ~= "table" or #enemyParty == 0 then return nil end
  local a, la = fighters(mineList)
  local b, lb = fighters(theirsList)
  local players = a + b
  if players == 0 then return nil end
  local own = #enemyParty
  local extra = players >= 4 and 2 or 1
  local want = math.max(own + extra, hard and players or math.ceil(players * 2 / 3))
  want = math.min(CoopGyms.MAX_PARTY, math.max(own, want))

  -- the weaker team's average (a team with nobody able to fight counts as
  -- the other one)
  local weak
  if a > 0 and b > 0 then
    weak = math.min(math.floor(la / a), math.floor(lb / b))
  else
    weak = math.floor((la + lb) / players)
  end
  local low, aceAt, aceLevel = nil, own, -1
  for i, m in ipairs(enemyParty) do
    local lv = tonumber(m.level) or 1
    if low == nil or lv < low then low = lv end
    if lv > aceLevel then aceLevel, aceAt = lv, i end
  end
  local shift = math.max(0, weak + 1 - low)
  if hard then shift = shift + CoopGyms.HARD_LEVELS end

  local extras = {}
  local pools = CoopGyms.POOLS[isGen1() and "gen1" or "gen2"] or {}
  local pool = {}
  for _, name in ipairs(pools[key] or {}) do
    local id = speciesByName(data, name)
    if id then pool[#pool + 1] = id end
  end
  -- a leader with no pool here (or none of its names in this game) brings
  -- more of his own species instead
  if #pool == 0 then
    for i, m in ipairs(enemyParty) do if i ~= aceAt then pool[#pool + 1] = m.species end end
    if #pool == 0 then pool[1] = enemyParty[aceAt].species end
  end
  if #pool > 0 then
    local has = {}
    for _, m in ipairs(enemyParty) do has[m.species] = true end
    local fresh = {}
    for _, id in ipairs(pool) do if not has[id] then fresh[#fresh + 1] = id end end
    if #fresh == 0 then fresh = pool end
    for i = 1, want - own do extras[i] = fresh[((i - 1) % #fresh) + 1] end
  end
  if #extras == 0 and shift == 0 then return nil end
  return { foes = own + #extras, extras = extras, shift = shift, aceAt = aceAt, base = low }
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
CoopGyms.relevel = relevel

-- Trainer Pokemon the cartridge's way (trainer DVs, level-up moves), from
-- party rows; `class` picks the special-move table (none for the extras).
local function buildRows(data, class, index, rows)
  local okB, BattleState = pcall(require, "src.battle.BattleState")
  if not (okB and BattleState.buildTrainerParty) then return nil end
  local ok, party = pcall(BattleState.buildTrainerParty, { data = data }, class, index, rows)
  if ok and type(party) == "table" then return party end
  log("could not build " .. tostring(class) .. "#" .. tostring(index) .. ": " .. tostring(party))
  return nil
end

function CoopGyms.applyGym(battle, mineList, theirsList)
  local rules = battle.coopBalanceRules
  if not (type(rules) == "table" and rules.gymTeam == true) then return false end
  local key = CoopGyms.leaderKey(battle.oppClass, battle.partyIndex)
  if not key then return false end
  local data = (battle.game and battle.game.data) or battle.data
  local party = battle.enemyParty
  local plan = CoopGyms.planGym(data, party, key, mineList, theirsList, rules)
  if not plan then return false end
  local lv = plan.base + plan.shift
  local rows = {}
  for i, id in ipairs(plan.extras) do rows[i] = { species = id, level = math.min(100, lv) } end
  local extras = #rows > 0 and buildRows(data, "OPP_COOP_GYM", 1, rows) or {}
  if plan.shift > 0 then
    for _, m in ipairs(party) do
      relevel(data, m, math.min(100, (tonumber(m.level) or 1) + plan.shift))
    end
  end
  -- the extras go in before the ace, who stays the last word
  local out = {}
  for i, m in ipairs(party) do
    if i == plan.aceAt then
      for _, e in ipairs(extras or {}) do out[#out + 1] = e end
    end
    out[#out + 1] = m
  end
  battle.enemyParty = out
  battle.coopGymTeam = plan
  local names = {}
  for _, m in ipairs(out) do
    local def = data and data.pokemon and data.pokemon[m.species]
    names[#names + 1] = tostring(def and def.name or m.species) .. ":" .. tostring(m.level)
  end
  log(string.format("%s brings %d for two (+%d levels): %s", key, #out, plan.shift, table.concat(names, " ")))
  return true
end

-- ---------------------------------------------------------------------
-- the rival
-- ---------------------------------------------------------------------

local RIVAL_CLASSES = { OPP_RIVAL1 = true, OPP_RIVAL2 = true }

-- Gen 2's rival, whose team comes in threes by the starter he took
function CoopGyms.isRivalClass(oppClass)
  return RIVAL_CLASSES[oppClass] == true and isGen2() and not isGen1()
end

-- Which of the three he took: pokegold / pokecrystal's rival scripts check
-- EVENT_GOT_TOTODILE_FROM_ELM (28), then EVENT_GOT_CHIKORITA_FROM_ELM (29),
-- else (CYNDAQUIL): CHIKORITA, CYNDAQUIL, TOTODILE -- 1, 2, 3 of each three.
CoopGyms.STARTER_FLAGS = { { flag = 28, variant = 1 }, { flag = 29, variant = 2 } }
function CoopGyms.rivalVariant(save)
  if type(save) ~= "table" then return 3 end
  local okF, Flags = pcall(require, "src.script.Flags")
  local okG, Gen2Flags = pcall(require, "src.script.Gen2Flags")
  for _, s in ipairs(CoopGyms.STARTER_FLAGS) do
    local name = okG and Gen2Flags.eventFlag(s.flag) or string.format("EVENT_G2_%04d", s.flag)
    local set
    if okF and Flags.get then
      set = Flags.get(save, name)
    else
      set = type(save.flags) == "table" and save.flags[name]
    end
    if set then return s.variant end
  end
  return 3
end

-- the same fight, the other starter's team
function CoopGyms.rivalIndexFor(hostIndex, variant)
  hostIndex, variant = tonumber(hostIndex), tonumber(variant)
  if not (hostIndex and variant and variant >= 1 and variant <= 3) then return nil end
  return math.floor((hostIndex - 1) / 3) * 3 + variant
end

-- what the guest says with its three picked (coop_bigbattle_ready)
function CoopGyms.readyInfo(game, oppClass)
  if not (CoopGyms.on() and CoopGyms.isRivalClass(oppClass)) then return nil end
  local save = game and game.save
  local name = save and save.player and save.player.rival
  return { variant = CoopGyms.rivalVariant(save), name = type(name) == "string" and name or nil }
end

local function rivalName(name, fallback)
  if type(name) ~= "string" or name == "" then return fallback end
  return name:sub(1, 10)
end

-- The pair the host's go carries ({ aName, bIndex, bName }), or nil: a
-- single rival, as before.
function CoopGyms.rivalPair(game, battle, partnerInfo)
  if not (type(battle) == "table" and CoopGyms.on() and CoopGyms.isRivalClass(battle.oppClass)) then
    return nil
  end
  if type(partnerInfo) ~= "table" then return nil end
  local data = game and game.data
  local def = data and data.trainers and data.trainers[battle.oppClass]
  local bIndex = CoopGyms.rivalIndexFor(battle.partyIndex or 1, partnerInfo.variant)
  if not (def and def.parties and bIndex and def.parties[bIndex]) then return nil end
  local own = game.save and game.save.player and game.save.player.rival
  return { aName = rivalName(own, "RIVAL"), bIndex = bIndex, bName = rivalName(partnerInfo.name, "RIVAL") }
end

-- a pair as it arrived (the guest's copy of the go)
function CoopGyms.checkPair(data, oppClass, pair)
  if type(pair) ~= "table" or not CoopGyms.isRivalClass(oppClass) then return nil end
  local def = data and data.trainers and data.trainers[oppClass]
  local bIndex = tonumber(pair.bIndex)
  if not (def and def.parties and bIndex and def.parties[bIndex]) then return nil end
  return { aName = rivalName(pair.aName, "RIVAL"), bIndex = bIndex, bName = rivalName(pair.bName, "RIVAL") }
end

local function keepLast(party, n)
  if #party <= n then return party end
  local out = {}
  for i = #party - n + 1, #party do out[#out + 1] = party[i] end
  return out
end

function CoopGyms.applyRivalPair(battle)
  local pair = battle.coopRivalPair
  if type(pair) ~= "table" then return false end
  local data = (battle.game and battle.game.data) or battle.data
  local def = data and data.trainers and data.trainers[battle.oppClass]
  if not (def and def.parties and def.parties[pair.bIndex]) then return false end
  local partyB = buildRows(data, battle.oppClass, pair.bIndex, def.parties[pair.bIndex])
  if not (partyB and partyB[1]) then return false end
  local rules = type(battle.coopBalanceRules) == "table" and battle.coopBalanceRules or {}
  local hard = rules.hardFoes == true
  local partyA = battle.enemyParty or {}
  if rules.balancedFoes == true and not hard then
    partyA = keepLast(partyA, CoopGyms.RIVAL_KEEP)
    partyB = keepLast(partyB, CoopGyms.RIVAL_KEEP)
  elseif hard then
    for _, list in ipairs({ partyA, partyB }) do
      for _, m in ipairs(list) do
        relevel(data, m, math.min(100, (tonumber(m.level) or 1) + CoopGyms.HARD_LEVELS))
      end
    end
  end
  battle.enemyParty = partyA
  battle.enemyIndex = 1
  battle.enemyPartyB = partyB
  battle.enemyIndexB = 1
  -- the names: the host's rival on the left, the guest's own on the right,
  -- the same on both screens
  battle.trainer = setmetatable({ name = pair.aName }, { __index = def })
  battle.trainerB = setmetatable({ name = pair.bName }, { __index = def })
  battle.trainerPicB = battle.trainerPic
  battle.coopRivals = true
  local okI, I18n = pcall(require, "src.coop.CoopI18n")
  local line = string.format("%s & %s\nwant to fight!", pair.aName, pair.bName)
  battle.introText = okI and I18n.t(line) or line
  log(string.format("rival 2v2: %s (%d) and %s (#%d, %d)", pair.aName, #partyA, pair.bName,
                    pair.bIndex, #partyB))
  return true
end

-- From CoopBalance.apply on each copy: true when this battle was one of
-- ours (and the party may have changed), false to leave it to CoopBalance.
function CoopGyms.apply(battle, mineList, theirsList)
  if type(battle) ~= "table" or type(battle.enemyParty) ~= "table" then return false end
  if battle.coopRivalPair then return CoopGyms.applyRivalPair(battle) end
  return CoopGyms.applyGym(battle, mineList, theirsList)
end

return CoopGyms
