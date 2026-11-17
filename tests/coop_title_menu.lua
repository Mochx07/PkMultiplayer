-- ONE CO-OP ROW ON THE TITLE SCREEN (nightly.2, Hooks.titleMenuItems over
-- the engine's ui.title_menu.items hook).
--
-- CONTINUE CO-OP and NEW CO-OP GAME used to be two rows; now there is one,
-- CO-OP, under NEW GAME.  With a save it asks CONTINUE / NEW GAME; without
-- one it goes straight to a new co-op game.  Either way the co-op link
-- screen comes first and the title screen's own callback starts the game.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local Strings = require("src.core.Strings")
local GameVersion = require("src.core.GameVersion")
local Hooks = rawget(_G, "__PKMULTIPLAYER").hooks
local CoopNewGame = require("src.coop.CoopNewGame")

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local function setup(withSave)
  local game = { data = Data, stack = newStack(), save = {},
                 input = { wasPressed = function() return false end, isDown = function() return false end } }
  local started = {}
  local title = { onContinue = function() started[#started + 1] = "continue" end,
                  onNewGame = function() started[#started + 1] = "new" end }
  game.stack:push(title)
  local items = {}
  if withSave then items[#items + 1] = { label = Strings("CONTINUE"), onSelect = function() end } end
  items[#items + 1] = { label = Strings("NEW GAME"), onSelect = function() end }
  items[#items + 1] = { label = Strings("OPTION"), onSelect = function() end }
  items[#items + 1] = { label = Strings("EXIT GAME"), onSelect = function() end }
  return game, title, items, started
end

local function labels(items)
  local out = {}
  for i, it in ipairs(items) do out[i] = it.label end
  return table.concat(out, "|")
end

-- the co-op link screen, captured instead of opened
local made = {}
local realNew = CoopNewGame.new
CoopNewGame.new = function(game, cb, mode)
  local s = { coopNewGame = true, mode = mode or "new", cb = cb }
  made[#made + 1] = s
  return s
end

for _, ver in ipairs({ "gold", "red" }) do
  GameVersion.set(ver)
  made = {}
  local game, title, items, started = setup(true)
  items = Hooks.titleMenuItems(function(_, i) return i end, game, items)
  T.check(labels(items) == table.concat({ Strings("CONTINUE"), Strings("NEW GAME"), "CO-OP",
                                          Strings("OPTION"), Strings("EXIT GAME") }, "|"),
          ver .. ": one CO-OP row, under NEW GAME (" .. labels(items) .. ")")
  local n = 0
  for _, it in ipairs(items) do if tostring(it.label):find("CO%-OP") then n = n + 1 end end
  T.check(n == 1, ver .. ": no CONTINUE CO-OP / NEW CO-OP GAME rows any more")
  items[3].onSelect()
  local sub = game.stack:top()
  T.check(sub and sub.coopTitleChoice, ver .. ": with a save, CO-OP asks which")
  local subItems = sub and sub.items or {}
  T.check(#subItems == 2 and subItems[1].label == Strings("CONTINUE") and subItems[2].label == Strings("NEW GAME"),
          ver .. ": ...CONTINUE or NEW GAME")
  game.stack:pop()
  subItems[1].onSelect()
  T.check(#made == 1 and made[1].mode == "continue", ver .. ": CONTINUE opens the co-op link to continue")
  made[1].cb()
  T.check(started[1] == "continue", ver .. ": ...and the title screen's own CONTINUE starts the game")
  subItems[2].onSelect()
  T.check(#made == 2 and made[2].mode == "new", ver .. ": NEW GAME opens the co-op link for a new game")
  made[2].cb()
  T.check(started[2] == "new", ver .. ": ...and the title screen's NEW GAME starts it")

  made = {}
  local game2, _, items2 = setup(false)
  items2 = Hooks.titleMenuItems(function(_, i) return i end, game2, items2)
  T.check(labels(items2) == table.concat({ Strings("NEW GAME"), "CO-OP", Strings("OPTION"), Strings("EXIT GAME") }, "|"),
          ver .. ": no save: the row is still under NEW GAME")
  items2[2].onSelect()
  T.check(#made == 1 and made[1].mode == "new" and not (game2.stack:top() or {}).coopTitleChoice,
          ver .. ": no save: straight to a new co-op game, nothing to ask")
end

-- a Gen 3 menu is left as it is
GameVersion.set("emerald")
if GameVersion.generation() == 3 then
  local game, _, items = setup(true)
  local before = labels(items)
  items = Hooks.titleMenuItems(function(_, i) return i end, game, items)
  T.check(labels(items) == before, "Gen 3: the title menu is untouched")
end
GameVersion.set("gold")
CoopNewGame.new = realNew

T.finish("one CO-OP row on the title screen")
