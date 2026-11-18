-- THE VERSION MATRIX (nightly.3, src/coop/CoopEditions.lua).
-- Which editions share the story, and what of a third edition's event is
-- applied on a base edition (and the other way round).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
T.fixtures.fresh()
local CoopManager = require("src.coop.CoopManager")
local Compat = require("src.coop.CoopEditions")
local Cross = require("src.coop.CoopCrossStory")
local GV = require("src.core.GameVersion")
require("src.coop.CoopLog").enabled = false

-- relations
local R = Compat.relation
T.check(R("red", "red") == "same", "Red with Red: same")
T.check(R("red", "blue") == "pair" and R("gold", "silver") == "pair", "Red/Blue and Gold/Silver: a pair")
T.check(R("red", "yellow") == "third" and R("yellow", "blue") == "third", "Red or Blue with Yellow: third edition")
T.check(R("crystal", "gold") == "third", "Gold with Crystal: third edition")
T.check(R("red", "gold") == "capsule", "Gen 1 with Gen 2: the Time Capsule")
T.check(R("red", nil) == nil, "an unknown partner game: no answer (the old behaviour applies)")
local p = Compat.profile("yellow")
T.check(p.family == "rby" and p.third == true and p.gen == 1, "Yellow's profile: rby, third edition, Gen 1")

-- sharing
CoopManager.connected = true
CoopManager.partner.caps = { [Compat.CAP] = true, [Cross.CAP] = true }
GV.set("red")
CoopManager.partner.game = "blue"
T.check(CoopManager.storyCompatible(), "Red with Blue: one story")
CoopManager.partner.game = "yellow"
CoopManager.crossStory = true
T.check(CoopManager.storyCompatible(), "Red with Yellow, 3RD ED. STORY on: one story")
CoopManager.crossStory = false
T.check(not CoopManager.storyCompatible(), "...rule off: apart")
CoopManager.crossStory = true
CoopManager.partner.caps = { [Cross.CAP] = true }
T.check(not CoopManager.storyCompatible(), "...a partner without story.compat: apart")
CoopManager.partner.caps = { [Compat.CAP] = true, [Cross.CAP] = true }
CoopManager.partner.game = "gold"
T.check(not CoopManager.storyCompatible(), "Red with Gold: no story across generations")

-- Yellow's own scripts, read from the engine
local owned = Compat.scriptOwned().yellow or {}
T.check(owned.EVENT_CHOSE_PIKACHU and owned.EVENT_BEAT_MT_MOON_3_JESSIE_JAMES,
        "Yellow's scripts own EVENT_CHOSE_PIKACHU and Jessie & James at Mt. Moon")
T.check(not owned.EVENT_GOT_POKEDEX, "...not EVENT_GOT_POKEDEX, which every edition's scripts write")

-- Red receives Yellow's events
local redData = { trainer_headers = { MtMoonB2F = { { event = "EVENT_BEAT_MT_MOON_3_SUPER_NERD" } },
                                      ViridianForest = { { event = "EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0" } } },
                  field = {} }
local red = { data = redData }
CoopManager.partner.game = "yellow"
local msg = { src = "yellow", rewards = {
  { kind = "set_flag", id = "EVENT_GOT_POKEDEX" },
  { kind = "set_flag", id = "EVENT_CHOSE_PIKACHU" },
  { kind = "set_flag", id = "EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_3", ed = true },
  { kind = "set_flag", id = "EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0", ed = true },
  { kind = "item", id = "POTION", count = 1 },
} }
Compat.filter(red, msg)
local ids = {}
for _, r in ipairs(msg.rewards) do ids[#ids + 1] = tostring(r.id) end
T.check(#msg.rewards == 3, "kept: the shared flag, the trainer both have, the item (" .. table.concat(ids, " ") .. ")")
T.check(msg.rewards[1].id == "EVENT_GOT_POKEDEX" and msg.rewards[2].id == "EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0",
        "dropped: Yellow's Pikachu flag and a Viridian Forest trainer Red does not have")
T.check(not msg.exclusive, "an event with shared story is not Yellow's own")

-- a whole Yellow event: Jessie & James at Mt. Moon, with its prize
local jj = { src = "yellow", rewards = {
  { kind = "set_flag", id = "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES" },
  { kind = "money", amount = 500 },
} }
Compat.filter(red, jj)
T.check(jj.exclusive and #jj.rewards == 0, "Jessie & James on Red: Yellow's own, the money stays there too")

-- Yellow receives Red's events
GV.set("yellow")
CoopManager.partner.game = "red"
local yellow = { data = { trainer_headers = { MtMoonB2F = {} }, field = {} } }
local rocket = { src = "red", rewards = {
  { kind = "set_flag", id = "EVENT_BEAT_MT_MOON_3_SUPER_NERD", ed = true },
} }
Compat.filter(yellow, rocket)
T.check(rocket.exclusive and #rocket.rewards == 0, "Red's Mt. Moon trainer on Yellow: not applied")
local shared = { src = "red", rewards = { { kind = "set_flag", id = "EVENT_GOT_POKEDEX" } } }
Compat.filter(yellow, shared)
T.check(#shared.rewards == 1, "a shared event crosses as it is")

-- tags on the way out
GV.set("red")
local out = { { kind = "set_flag", id = "EVENT_BEAT_MT_MOON_3_SUPER_NERD" }, { kind = "set_flag", id = "EVENT_GOT_POKEDEX" } }
Compat.tag(red, out)
T.check(out[1].ed == true and out[2].ed == nil, "the sender tags only its edition's own flags")

-- a pair is not filtered
CoopManager.partner.game = "blue"
local pair = { src = "blue", rewards = { { kind = "set_flag", id = "EVENT_CHOSE_PIKACHU" } } }
T.check(Compat.filter(red, pair) == 0 and #pair.rewards == 1, "Red with Blue: nothing filtered")

-- Gen 2: Gold <-> Crystal through the event map
GV.set("crystal")
CoopManager.partner.game = "gold"
local Map = require("src.coop.CoopFlagMap")
local g, c
for gi, ci in pairs(Map.g2c) do if gi ~= ci and (not g or gi < g) then g, c = gi, ci end end
local gc = { src = "gold", rewards = { { kind = "set_flag", id = string.format("EVENT_G2_%04d", g) },
                                       { kind = "wram", addr = 1, value = 2 } } }
Compat.filter({ data = {} }, gc)
T.check(#gc.rewards == 1 and gc.rewards[1].id == string.format("EVENT_G2_%04d", c),
        "Gold's event lands on Crystal's number; the WRAM write is dropped")
CoopManager.crossStory = nil
T.finish("version matrix")
