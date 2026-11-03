-- GYMS FOR TWO AND THE RIVAL 2v2 (src/coop/CoopGyms.lua, cap story.gyms):
-- a co-op leader brings a team made for two, the rival can be two rivals,
-- both copies build the very same battle, and a 1.6.x partner is unchanged.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local GV = require("src.core.GameVersion")
local wasGame = GV.get()
GV.set("gold")
local Pokemon = require("src.pokemon.Pokemon")
local CoopManager = require("src.coop.CoopManager")
local CoopBalance = require("src.coop.CoopBalance")
local CoopGyms = require("src.coop.CoopGyms")
require("src.coop.CoopLog").enabled = false

-- the fixture's species under the names the pools ask for
local function alias(id, name, from)
  local def = {}
  for k, v in pairs(Data.pokemon[from or "FIXMON_A"]) do def[k] = v end
  def.name = name
  Data.pokemon[id] = def
end
alias("SPECIES_016", "PIDGEY")
alias("SPECIES_017", "PIDGEOTTO", "FIXMON_B")
alias("SPECIES_163", "HOOTHOOT")
alias("SPECIES_021", "SPEAROW", "FIXMON_B")
alias("SPECIES_177", "NATU")
alias("SPECIES_152", "CHIKORITA")
alias("SPECIES_155", "CYNDAQUIL")
alias("SPECIES_158", "TOTODILE")
alias("SPECIES_092", "GASTLY")
alias("SPECIES_041", "ZUBAT")

local function team(n, level, species)
  local out = {}
  for i = 1, n do out[i] = Pokemon.new(Data, species or (i % 2 == 0 and "FIXMON_B" or "FIXMON_A"), level, function(a) return a end) end
  return out
end
local function falkner(rules)
  local p = { Pokemon.new(Data, "SPECIES_016", 7, function(a) return a end),
              Pokemon.new(Data, "SPECIES_017", 9, function(a) return a end) }
  return { data = Data, oppClass = "OPP_LEADER", partyIndex = 1, enemyParty = p,
           coopBalanceRules = rules or { balancedFoes = true, hardFoes = false, gymTeam = true } }
end
local function names(party)
  local out = {}
  for _, m in ipairs(party) do out[#out + 1] = Data.pokemon[m.species].name .. m.level end
  return table.concat(out, " ")
end

T.check(CoopManager.CAPS[CoopGyms.CAP] == true, "story.gyms is announced in the hello")
T.check(CoopGyms.leaderKey("OPP_LEADER", 1) == "FALKNER" and CoopGyms.leaderKey("OPP_LEADER_BUGSY", 1) == "BUGSY",
        "FALKNER and BUGSY are leaders, by either spelling")
T.check(CoopGyms.leaderKey("OPP_YOUNGSTER", 1) == nil and CoopGyms.leaderKey("OPP_RIVAL1", 4) == nil,
        "a youngster or the rival is no leader")

-- FALKNER (PIDGEY 7, PIDGEOTTO 9) against three at 14 and three at 12
local b = falkner()
T.check(CoopBalance.apply(b, team(3, 14), team(3, 12)), "the leader's team changes")
T.check(#b.enemyParty == 4, "six against FALKNER: he brings four (" .. #b.enemyParty .. ")")
T.check(names(b.enemyParty) == "PIDGEY13 HOOTHOOT13 SPEAROW13 PIDGEOTTO15",
        "two more of his type, new species, before his ace; a level above the weaker team (" .. names(b.enemyParty) .. ")")
T.check(b.enemyParty[2].hp == b.enemyParty[2].stats.hp and b.enemyParty[2].hp > 0, "the new ones come in at full HP")
local Stats = require("src.pokemon.Stats")
T.check(b.enemyParty[4].stats.hp == Stats.calc(Data.pokemon.SPECIES_017, 15, b.enemyParty[4].dvs, b.enemyParty[4].statExp).hp,
        "the ace's stats are worked out for his new level")
T.check(b.enemyParty[2].moves and #b.enemyParty[2].moves >= 1, "the new ones know their level-up moves")
local dvs = Data.constants and Data.constants.trainerDvs
T.check(dvs == nil or (b.enemyParty[2].dvs and b.enemyParty[2].dvs.atk == dvs.atk), "and fight with trainer DVs")
T.check(b.coopGymTeam and b.coopBalanced == nil, "it is the gym plan, not BALANCED FOES' copies")

-- the levels follow the WEAKER team, not the pair's average
local w = falkner()
CoopBalance.apply(w, team(3, 40), team(3, 10))
T.check(w.enemyParty[1].level == 11 and w.enemyParty[#w.enemyParty].level == 13,
        "one team far ahead does not push him past the one behind (" .. names(w.enemyParty) .. ")")

-- never down
local low = falkner()
CoopBalance.apply(low, team(2, 4), team(1, 5))
T.check(low.enemyParty[1].level == 7 and low.enemyParty[#low.enemyParty].level == 9,
        "a pair behind the cartridge faces the cartridge's levels (" .. names(low.enemyParty) .. ")")
T.check(#low.enemyParty == 3, "three between you: one more, not two (" .. #low.enemyParty .. ")")

-- HARD FOES: one foe for each of yours, three levels on top
local hard = falkner({ balancedFoes = false, hardFoes = true, gymTeam = true })
CoopBalance.apply(hard, team(3, 14), team(3, 12))
T.check(#hard.enemyParty == 6 and hard.enemyParty[1].level == 16, "HARD FOES: six, three levels up (" .. names(hard.enemyParty) .. ")")
T.check(names(hard.enemyParty) == "PIDGEY16 HOOTHOOT16 SPEAROW16 NATU16 HOOTHOOT16 PIDGEOTTO18",
        "the pool goes round again when it runs out")

-- both off: the cartridge's team
local off = falkner({ balancedFoes = false, hardFoes = false, gymTeam = true })
T.check(not CoopBalance.apply(off, team(3, 30), team(3, 30)) and #off.enemyParty == 2, "both rules off: the cartridge's FALKNER")

-- a 1.6.x partner: no gymTeam in the rules, BALANCED FOES as before (copies)
local old = falkner({ balancedFoes = true, hardFoes = false })
CoopBalance.apply(old, team(3, 14), team(3, 12))
T.check(#old.enemyParty == 4 and old.enemyParty[3].species == "SPECIES_016" and old.coopGymTeam == nil,
        "without story.gyms the leader is padded with his own team, as in 1.6 (" .. names(old.enemyParty) .. ")")
CoopManager.partner = { caps = {} }
T.check(CoopBalance.currentRules().gymTeam == nil, "and the rule is not set while the partner lacks the capability")
CoopManager.partner = { caps = { [CoopGyms.CAP] = true } }
T.check(CoopBalance.currentRules().gymTeam == true, "it is set when both have it")

-- the same on both copies (the lists arrive the other way round on the guest)
local hostCopy, guestCopy = falkner(), falkner()
local mine, theirs = team(3, 18), team(2, 25)
CoopBalance.apply(hostCopy, mine, theirs)
CoopBalance.apply(guestCopy, theirs, mine)
local same = #hostCopy.enemyParty == #guestCopy.enemyParty
for i, m in ipairs(hostCopy.enemyParty) do
  local g = guestCopy.enemyParty[i]
  same = same and g and g.species == m.species and g.level == m.level and g.hp == m.hp
         and g.stats.atk == m.stats.atk and #(g.moves or {}) == #(m.moves or {})
end
T.check(same, "both copies build the very same leader team")

-- a leader with no pool of names in this game brings more of his own species
local fresh = { data = Data, oppClass = "OPP_LEADER_BUGSY", partyIndex = 1,
                enemyParty = { Pokemon.new(Data, "FIXMON_A", 14, function(a) return a end),
                               Pokemon.new(Data, "FIXMON_B", 16, function(a) return a end) },
                coopBalanceRules = { balancedFoes = true, gymTeam = true } }
CoopBalance.apply(fresh, team(3, 14), team(3, 14))
T.check(#fresh.enemyParty == 4 and fresh.enemyParty[2].species == "FIXMON_A", "no names to find: more of his own (" .. #fresh.enemyParty .. ")")

-- ---------------------------------------------------------------- the rival
Data.trainers = Data.trainers or {}
local function row(name, level) for id, d in pairs(Data.pokemon) do if d.name == name then return { species = id, level = level } end end end
Data.trainers.OPP_RIVAL1 = { name = "RIVAL", baseMoney = 20, parties = {} }
local starters = { "CHIKORITA", "CYNDAQUIL", "TOTODILE" }
for stage = 0, 1 do
  for v = 1, 3 do
    Data.trainers.OPP_RIVAL1.parties[stage * 3 + v] = stage == 0 and { row(starters[v], 5) }
      or { row("GASTLY", 12), row("ZUBAT", 14), row("ZUBAT", 14), row("GASTLY", 15), row(starters[v], 16) }
  end
end
T.check(CoopGyms.isRivalClass("OPP_RIVAL1") and CoopGyms.isRivalClass("OPP_RIVAL2"), "Gold's rival classes")
GV.set("yellow")
T.check(not CoopGyms.isRivalClass("OPP_RIVAL1"), "Yellow's rival is not paired")
GV.set("gold")

local function saveWith(flag) return { flags = flag and { [string.format("EVENT_G2_%04d", flag)] = true } or {}, player = { rival = "KAMON" } } end
T.check(CoopGyms.rivalVariant(saveWith(28)) == 1 and CoopGyms.rivalVariant(saveWith(29)) == 2
        and CoopGyms.rivalVariant(saveWith(nil)) == 3,
        "TOTODILE -> his CHIKORITA, CHIKORITA -> CYNDAQUIL, CYNDAQUIL -> TOTODILE")
T.check(CoopGyms.rivalIndexFor(7, 2) == 8 and CoopGyms.rivalIndexFor(13, 3) == 15 and CoopGyms.rivalIndexFor(4, 1) == 4
        and CoopGyms.rivalIndexFor(1, 3) == 3, "the same fight, the other starter's team")

CoopManager.partner = { caps = {} }
T.check(CoopGyms.readyInfo({ save = saveWith(29) }, "OPP_RIVAL1") == nil, "a 1.6.x partner is never told about the rival")
T.check(CoopGyms.rivalPair({ data = Data, save = saveWith(28) }, { oppClass = "OPP_RIVAL1", partyIndex = 4 },
                           { variant = 2, name = "KAMON" }) == nil, "and the host does not pair them without it")
CoopManager.partner = { caps = { [CoopGyms.CAP] = true } }
local info = CoopGyms.readyInfo({ save = saveWith(29) }, "OPP_RIVAL1")
T.check(info and info.variant == 2 and info.name == "KAMON", "the guest says which rival is his")
T.check(CoopGyms.readyInfo({ save = saveWith(29) }, "OPP_LEADER") == nil, "and only for the rival")
local hostGame = { data = Data, save = { flags = {}, player = { rival = "SILVER" } } }
local pair = CoopGyms.rivalPair(hostGame, { oppClass = "OPP_RIVAL1", partyIndex = 4 }, info)
T.check(pair and pair.aName == "SILVER" and pair.bName == "KAMON" and pair.bIndex == 5,
        "the host pairs his rival (#4) with the guest's (#5)")
T.check(CoopGyms.checkPair(Data, "OPP_RIVAL1", { bIndex = 99, aName = "A", bName = "B" }) == nil
        and CoopGyms.checkPair(Data, "OPP_LEADER", pair) == nil, "a pair that cannot be built is dropped")

local BattleState = require("src.battle.BattleState")
local function rivalBattle(rules)
  local party = BattleState.buildTrainerParty({ data = Data }, "OPP_RIVAL1", 4, Data.trainers.OPP_RIVAL1.parties[4])
  return { data = Data, oppClass = "OPP_RIVAL1", partyIndex = 4, enemyParty = party,
           trainer = setmetatable({ name = "WRONG" }, { __index = Data.trainers.OPP_RIVAL1 }),
           coopRivalPair = CoopGyms.checkPair(Data, "OPP_RIVAL1", pair),
           coopBalanceRules = rules or { balancedFoes = true, gymTeam = true } }
end
local r = rivalBattle()
T.check(CoopBalance.apply(r, team(3, 15), team(3, 15)), "the rival battle is built as a pair")
T.check(r.enemyPartyB and #r.enemyPartyB == 4 and #r.enemyParty == 4,
        "BALANCED FOES: each rival brings his last four (" .. #r.enemyParty .. "+" .. #(r.enemyPartyB or {}) .. ")")
T.check(Data.pokemon[r.enemyParty[4].species].name == "CHIKORITA" and Data.pokemon[r.enemyPartyB[4].species].name == "CYNDAQUIL",
        "the host's rival has his starter's partner, the guest's rival the guest's")
T.check(r.trainer.name == "SILVER" and r.trainerB.name == "KAMON" and r.trainer.baseMoney == 20,
        "each rival by his own player's name, on both copies")
T.check(r.introText and r.introText:find("SILVER & KAMON", 1, true), "both named in the intro: " .. tostring(r.introText))
T.check(r.coopBalanced == nil and r.enemyParty[1].level == 14, "no padding or levels on top of two teams")

local full = rivalBattle({ balancedFoes = false, hardFoes = true, gymTeam = true })
CoopBalance.apply(full, team(3, 15), team(3, 15))
T.check(#full.enemyParty == 5 and #full.enemyPartyB == 5 and full.enemyPartyB[5].level == 19,
        "HARD FOES: both whole teams, three levels up")

local h, g = rivalBattle(), rivalBattle()
CoopBalance.apply(h, mine, theirs)
CoopBalance.apply(g, theirs, mine)
local agree = #h.enemyPartyB == #g.enemyPartyB and #h.enemyParty == #g.enemyParty
for i, m in ipairs(h.enemyPartyB) do
  agree = agree and g.enemyPartyB[i].species == m.species and g.enemyPartyB[i].hp == m.hp
end
T.check(agree, "both copies build the same two rivals")

-- the bench both copies compare after every turn holds both teams
local CoopBattle = require("src.coop.CoopBattle")
local both = CoopBattle.foeParty(h)
T.check(#both == #h.enemyParty + #h.enemyPartyB and both[#both] == h.enemyPartyB[#h.enemyPartyB],
        "the synced bench is both rivals' teams")
T.check(CoopBattle.foeParty(b) == b.enemyParty, "one trainer: his own team, as before")

CoopManager.partner = nil
GV.set(wasGame)
T.finish("gyms for two")
