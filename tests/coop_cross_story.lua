-- GOLD / SILVER <-> CRYSTAL STORY (nightly.2, EXPERIMENTAL, CoopCrossStory).
-- Off by default; on (and both with story.cross), a partner on the other
-- cartridge's events arrive with each EVENT_G2_#### flag turned into the
-- same event's bit here, and what is laid out apart is dropped.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
T.fixtures.fresh()
local CoopManager = require("src.coop.CoopManager")
local Cross = require("src.coop.CoopCrossStory")
local Map = require("src.coop.CoopFlagMap")
local GV = require("src.core.GameVersion")
require("src.coop.CoopLog").enabled = false

T.check(Map.count > 1000, "the map knows " .. Map.count .. " events in both games")
-- the first one that moves: Gold's bit and Crystal's bit of the same event
local g, c
for gi, ci in pairs(Map.g2c) do if gi ~= ci and (not g or gi < g) then g, c = gi, ci end end
T.check(g and c, "events move between the two numberings (gold " .. tostring(g) .. " -> crystal " .. tostring(c) .. ")")

CoopManager.connected = true
CoopManager.partner.game = "gold"
-- nightly.3: the share goes through the version matrix (story.compat) too
CoopManager.partner.caps = { [Cross.CAP] = true, ["story.compat"] = true }
GV.set("crystal")
CoopManager.crossStory = false
T.check(not CoopManager.storyCompatible(), "Crystal with a Gold partner, rule off: no shared story (as before)")
CoopManager.crossStory = true
T.check(Cross.active() and CoopManager.storyCompatible(), "rule on, both able: the story is shared")

local msg = { rewards = {
  { kind = "set_flag", id = string.format("EVENT_G2_%04d", g) },
  { kind = "item", id = "POTION", count = 1 },
  { kind = "scene", map = "X", scene = 1 },
  { kind = "wram", addr = 1, value = 2 },
  { kind = "set_flag", id = "ENGINE_ZEPHYRBADGE" },
  { kind = "set_flag", id = "FLAG_G2_0040" },
} }
Cross.translate(msg)
local ids = {}
for _, r in ipairs(msg.rewards) do ids[#ids + 1] = r.kind .. ":" .. tostring(r.id or "") end
T.check(msg.rewards[1].id == string.format("EVENT_G2_%04d", c), "a Gold flag lands on Crystal's bit for the same event")
T.check(#msg.rewards == 3, "the scene and the WRAM write are dropped, and an unnamed engine row (" .. table.concat(ids, " ") .. ")")
T.check(msg.rewards[2].kind == "item" and msg.rewards[3].id == "ENGINE_ZEPHYRBADGE", "items and named engine flags cross as they are")

GV.set("gold")
CoopManager.partner.game = "crystal"
T.check(Cross.flag(string.format("EVENT_G2_%04d", c)) == string.format("EVENT_G2_%04d", g), "...and back: Crystal's bit onto Gold's")

CoopManager.partner.caps = {}
T.check(not Cross.active(), "a partner without story.cross: not shared")
CoopManager.partner.game = "silver"
CoopManager.partner.caps = { [Cross.CAP] = true, ["story.compat"] = true }
T.check(not Cross.active() and CoopManager.storyCompatible(), "Gold with Silver: nothing to translate (shared as always)")
CoopManager.crossStory = false
T.finish("Gold/Silver <-> Crystal story")
