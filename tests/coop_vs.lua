-- VS FORMATS (1.20, src/coop/CoopVS.lua): which Pokemon a format lets play,
-- the party the Cable Club sends, the invite that carries the rules, and the
-- level menu the format skips.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local CoopManager = require("src.coop.CoopManager")
local CoopLink = require("src.coop.CoopLink")
local CoopVS = require("src.coop.CoopVS")
require("src.coop.CoopLog").enabled = false

-- a small dex: a three-stage line, a lone Pokemon, a legend, two types
local data = { pokemon = {
  BULB = { dex = 1, types = { "GRASS", "POISON" }, evolutions = { { species = "IVY" } } },
  IVY = { dex = 2, types = { "GRASS", "POISON" }, evolutions = { { species = "VENU" } } },
  VENU = { dex = 3, types = { "GRASS", "POISON" }, evolutions = {} },
  ODD = { dex = 43, types = { "GRASS", "POISON" }, evolutions = { { species = "GLOOM" } } },
  GLOOM = { dex = 44, types = { "GRASS", "POISON" }, evolutions = {} },
  TAUROS = { dex = 128, types = { "NORMAL" }, evolutions = {} },
  CHARM = { dex = 4, types = { "FIRE" }, evolutions = { { species = "CHAR2" } } },
  CHAR2 = { dex = 5, types = { "FIRE" }, evolutions = {} },
  MEWTWO = { dex = 150, types = { "PSYCHIC" }, evolutions = {} },
  LUGIA = { dex = 249, types = { "PSYCHIC", "FLYING" }, evolutions = {} },
} }
local function mon(species, opts)
  local m = { species = species, level = 30, moves = { { id = "TACKLE" } } }
  for k, v in pairs(opts or {}) do m[k] = v end
  return m
end
local function names(list)
  local o = {}
  for _, m in ipairs(list) do o[#o + 1] = m.species or m.mon.species end
  return table.concat(o, " ")
end
local function whys(left)
  local o = {}
  for _, l in ipairs(left) do o[#o + 1] = l.mon.species .. "=" .. l.why end
  return table.concat(o, " ")
end
local F = CoopVS.FORMATS

-- ------------------------------------------------------------ the formats
T.check(#F == 5 and F.free and F.lv50 and F.lv100 and F.little and F.mono, "five formats, by id too")
for _, f in ipairs(F) do
  local fits = #f.name <= 16 and #f.invite <= 16
  for _, l in ipairs(f.info) do fits = fits and #l <= 18 end
  T.check(fits, f.id .. ": name, invite line and help box fit their boxes")
end
T.check(F.lv50.level == 50 and F.lv100.level == 100 and F.little.level == 5 and F.mono.level == 50
        and F.free.level == nil, "the levels: 50, 100, 5, 50, and real ones in a free battle")
T.check(CoopVS.format("lv50") == F.lv50 and CoopVS.format("nope") == nil and CoopVS.format(7) == nil,
        "a format is looked up by id; anything else is none")

-- --------------------------------------------------------------- LEVEL 50
local party = { mon("VENU"), mon("MEWTWO"), mon("TAUROS", { moves = { { id = "FISSURE" } } }),
                mon("VENU"), mon("GLOOM", { item = "LEFTOVERS" }), mon("CHAR2", { item = "LEFTOVERS" }),
                mon("LUGIA", { isEgg = true }) }
local kept, left, err = CoopVS.legalParty(data, party, F.lv50)
T.check(err == nil and names(kept) == "VENU GLOOM", "LEVEL 50 keeps VENU and GLOOM, in party order: " .. names(kept))
T.check(whys(left) == "MEWTWO=BANNED TAUROS=BANNED MOVE VENU=SAME SPECIES CHAR2=SAME ITEM",
        "...and says why each other one sits out: " .. whys(left))
T.check(kept[1] == party[1] and kept[2] == party[5], "the kept Pokemon are the party's own tables")
local _, left2 = CoopVS.legalParty(data, { mon("TAUROS", { moves = { { id = "TACKLE" }, { id = "DOUBLE_TEAM" } } }),
                                         mon("CHAR2", { moves = { "MINIMIZE" } }) }, F.lv50)
T.check(#left2 == 2 and left2[1].why == "BANNED MOVE" and left2[2].why == "BANNED MOVE",
        "evasion moves are banned too (a move as a table or a bare id)")
local _, _, err2 = CoopVS.legalParty(data, { mon("MEWTWO"), mon("LUGIA") }, F.lv50)
T.check(err2 == "Your team breaks the rules", "nobody left to play: the format is refused")

-- ------------------------------------------------------------ FREE BATTLE
local k3, l3, e3 = CoopVS.legalParty(data, { mon("MEWTWO"), mon("MEWTWO"), mon("TAUROS", { moves = { "FISSURE" } }) }, F.free)
T.check(e3 == nil and #k3 == 3 and #l3 == 0, "FREE BATTLE keeps everyone")

-- ------------------------------------------------------------- LITTLE CUP
T.check(CoopVS.isLittle(data, "BULB") and CoopVS.isLittle(data, "ODD") and CoopVS.isLittle(data, "CHARM"),
        "first stages that can evolve are LITTLE CUP Pokemon")
T.check(not CoopVS.isLittle(data, "IVY") and not CoopVS.isLittle(data, "VENU") and not CoopVS.isLittle(data, "TAUROS"),
        "a middle stage, a last stage and a Pokemon that never evolves are not")
local k4, l4 = CoopVS.legalParty(data, { mon("IVY"), mon("BULB"), mon("TAUROS"), mon("CHARM"), mon("ODD") }, F.little)
T.check(names(k4) == "BULB CHARM ODD" and whys(l4) == "IVY=ALREADY EVOLVED TAUROS=ALREADY EVOLVED",
        "LITTLE CUP: " .. names(k4) .. " / " .. whys(l4))

-- --------------------------------------------------------------- ONE TYPE
local k5, l5 = CoopVS.legalParty(data, { mon("VENU"), mon("CHAR2"), mon("GLOOM"), mon("TAUROS") }, F.mono)
T.check(names(k5) == "VENU GLOOM" and whys(l5) == "CHAR2=OTHER TYPE TAUROS=OTHER TYPE",
        "ONE TYPE keeps the lead's type: " .. names(k5) .. " / " .. whys(l5))
local k6 = CoopVS.legalParty(data, { mon("TAUROS"), mon("VENU") }, F.mono)
T.check(names(k6) == "TAUROS", "a lone NORMAL lead plays alone")

-- -------------------------------------------------- the party that is sent
local game = { data = data, save = { party = { mon("VENU"), mon("MEWTWO"), mon("GLOOM") } } }
local tunnel = CoopLink.newTunnel("L-test")
local vs = CoopVS.attach(tunnel, game, F.lv50)
T.check(vs and #vs.party == 2 and #vs.left == 1, "a format battle carries its kept party on the tunnel")
T.check(CoopVS.packFor(game.save.party) == vs.party, "packing the save's party sends the kept part")
local other = { mon("TAUROS") }
T.check(CoopVS.packFor(other) == other, "any other party packs as it is")
tunnel:close()
T.check(CoopVS.packFor(game.save.party) == game.save.party, "once the Cable Club closes, the whole party again")
local t2 = CoopLink.newTunnel("L-free")
T.check(CoopVS.attach(t2, game, F.free) == nil and t2.vs == nil, "a free battle attaches nothing")
t2:close()

-- the hook on Protocol.packParty (lib/Hooks.lua)
local Hooks = rawget(_G, "__PKMULTIPLAYER").hooks
local packed
local Protocol = { packParty = function(p) packed = p return p end }
Hooks.modules["src.link.Protocol"](Protocol)
local t3 = CoopLink.newTunnel("L-hook")
CoopVS.attach(t3, game, F.lv50)
Protocol.packParty(game.save.party)
T.check(packed == t3.vs.party, "Protocol.packParty, hooked, packs the kept party")
t3:close()
Protocol.packParty(game.save.party)
T.check(packed == game.save.party, "...and the save's party after the battle")

-- ------------------------------------------------------- the level menu
local started
local ls = { decideCompat = function(self, mode, isHost) self.stage = isHost and mode == "battle" and "battleOptions" or "x" end,
             startMode = function(self, mode, isHost) started = { mode = mode, isHost = isHost, level = self.forceLevel } end }
CoopVS.skipLevelMenu(ls, F.little)
ls:decideCompat("battle", true)
T.check(started and started.mode == "battle" and started.isHost and started.level == 5,
        "the asker skips the Cable Club's level menu: the format's level is set")

-- ------------------------------------------------------- the invite
local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end, flush = function() end }
CoopManager.connected = true
CoopManager.partner.name = "TOBY"
local function lastSent(kind) for i = #sent, 1, -1 do if sent[i].type == kind then return sent[i] end end end
local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local g = { data = data, save = { party = { mon("VENU"), mon("GLOOM") }, player = { name = "ME" } }, stack = newStack() }
package.loaded["src.core.Game"] = g
CoopManager.isConnected = function() return true end
T.check(CoopLink.invite(g, "battle", F.lv50), "a LEVEL 50 invite goes out")
T.check(lastSent("coop_link_invite").format == "lv50", "...carrying the format's id")
CoopLink.pending = nil
CoopLink.invite(g, "battle", F.free)
T.check(lastSent("coop_link_invite").format == nil, "a free battle sends no format (a 1.6 partner reads it as ever)")
CoopLink.pending = nil
local bad = { data = data, save = { party = { mon("MEWTWO") }, player = { name = "ME" } }, stack = newStack() }
sent = {}
T.check(not CoopLink.invite(bad, "battle", F.lv50) and lastSent("coop_link_invite") == nil,
        "a team with nobody legal does not even ask")

-- the asked side: an unknown format and a team that cannot play are declined
local overworldIdle = CoopManager.overworldIdle
CoopManager.overworldIdle = function() return true end
sent = {}
CoopLink.onInvite(g, { id = "L1", mode = "battle", format = "cup-from-the-future", name = "TOBY" })
T.check(lastSent("coop_link_decline") and lastSent("coop_link_decline").reason == "rules",
        "a format this copy does not know is declined, not played free")
sent = {}
CoopLink.onInvite(bad, { id = "L2", mode = "battle", format = "lv50", name = "TOBY" })
T.check(lastSent("coop_link_decline") and lastSent("coop_link_decline").reason == "rules",
        "a team with nobody legal declines")
sent = {}
CoopLink.asked = nil
CoopLink.onInvite(g, { id = "L3", mode = "battle", format = "little", name = "TOBY" })
T.check(lastSent("coop_link_decline") and lastSent("coop_link_decline").reason == "rules",
        "LITTLE CUP with only last stages declines")
sent = {}
CoopLink.asked = nil
CoopLink.onInvite(g, { id = "L4", mode = "battle", format = "lv50", name = "TOBY" })
local modal = CoopLink.asked
T.check(modal and modal.lines[3] == "LEVEL 50 RULES" and lastSent("coop_link_decline") == nil,
        "a legal team is asked, and the box names the rules")
CoopManager.overworldIdle = overworldIdle

T.finish("co-op VS formats")
