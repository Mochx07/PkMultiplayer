-- src/coop/mg/MagikarpContest.lua
-- THE MAGIKARP CONTEST (1.20, M3), a minigame on the frame in
-- src/coop/CoopMinigame.lua.
--
--   * where: both players at the LAKE OF RAGE, a Gen 2 game, each with a rod
--     of their own in the BAG (canStart says which of the three is missing).
--   * play: two minutes of the engine's own fishing -- the rod from the BAG
--     (or SELECT), the engine's ". . ." / "Oh! It's a bite!", the engine's
--     fish groups for the lake.  What bites is the wild mon the engine makes
--     for the hooked battle (BattleState.newWild); the contest takes it before
--     the battle opens (lib/Hooks.lua, OverworldState:pushBattle).
--   * measure: a MAGIKARP is measured by the engine's own length routine, the
--     Lake of Rage guru's (Gen2Specials, CalcMagikarpLength: DVs and the
--     player's trainer ID, the cartridge's .BCLessThanDE bug included), read
--     off the special that uses it rather than copied.  The score is the
--     longest one in inches (feet * 12 + inches, the guru's own comparison);
--     the longer wins, the same length is a draw.
--   * the catch: every MAGIKARP is measured and LET GO back into the lake.  It
--     never joins the party or the PC and takes no BALL; the POKeDEX gets the
--     "seen" mark the engine's own newWild gives it, not "caught".  Anything
--     else that bites (a GYARADOS on the lake's Good / Super Rod rows) gets
--     away: only MAGIKARP count.  A bite during the countdown or after the
--     whistle is let go too, uncounted.
--   * the prize: the winner (a real length, not a forfeit) gets one GREAT
--     BALL, at most once a real day per save -- small, and not a way to farm.
local CoopMinigame = require("src.coop.CoopMinigame")

local Karp = {}
Karp.MAP = "LAKE_OF_RAGE"
Karp.SPECIES = 129
Karp.PRIZE = "GREAT_BALL"
Karp.RODS = { "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }

local function T(s) return require("src.coop.CoopI18n").t(s) end

local function itemByKey(data, key)
  for id, def in pairs((data and data.items) or {}) do
    if type(def) == "table" and (def.key == key or id == key) then return id end
  end
  return nil
end

local function speciesNumber(species)
  if type(species) == "number" then return species end
  local s = tostring(species or "")
  if s == "MAGIKARP" then return 129 end
  return tonumber(s:match("(%d+)$")) or 0
end

-- ---------------------------------------------------------------------
-- the engine's measure, found where the guru's special keeps it
-- ---------------------------------------------------------------------

local function upvalue(fn, wanted, depth)
  if type(fn) ~= "function" or depth > 3 then return nil end
  for i = 1, 60 do
    local name, v = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted and type(v) == "function" then return v end
  end
  -- a wrapper around the special: look one level in
  for i = 1, 60 do
    local name, v = debug.getupvalue(fn, i)
    if not name then break end
    if type(v) == "function" then
      local found = upvalue(v, wanted, depth + 1)
      if found then return found end
    end
  end
  return nil
end

-- (mon, otId) -> feet, inches; and (feet, inches) -> the cartridge's text
function Karp.engine()
  if Karp.measureFn then return Karp.measureFn, Karp.textFn end
  local ok, Commands = pcall(require, "src.script.Commands")
  if not ok or type(Commands) ~= "table" then return nil end
  pcall(require, "src.script.Gen2Specials")
  local special = Commands.g2_magikarp_length
  Karp.measureFn = upvalue(special, "magikarpLength", 0)
  Karp.textFn = upvalue(special, "lengthText", 0)
  return Karp.measureFn, Karp.textFn
end

-- the engine's length of one mon for this trainer, in inches (nil: no measure)
function Karp.measure(mon, otId)
  local fn = Karp.engine()
  if not (fn and mon) then return nil end
  local ok, feet, inches = pcall(fn, mon, otId)
  if not (ok and tonumber(feet) and tonumber(inches)) then return nil end
  return feet * 12 + inches
end

function Karp.lengthText(total)
  total = math.floor(tonumber(total) or 0)
  local feet, inches = math.floor(total / 12), total % 12
  local _, text = Karp.engine()
  if text then
    local ok, s = pcall(text, feet, inches)
    if ok and type(s) == "string" then return s end
  end
  return string.format("%d'%02d\"", feet, inches)
end

-- ---------------------------------------------------------------------
-- the game
-- ---------------------------------------------------------------------

function Karp.hasRod(game)
  local save, data = game and game.save, game and game.data
  local inv = save and save.inventory
  if not inv then return false end
  for _, key in ipairs(Karp.RODS) do
    local id = itemByKey(data, key)
    if id and (inv[id] or 0) > 0 then return true end
  end
  return false
end

function Karp.canStart(game, ow)
  local GV = require("src.core.GameVersion")
  if not (GV.isGen2 and GV.isGen2()) then return false, "Only in Gen 2" end
  ow = ow or (game and game.overworld)
  local mapId = ow and ow.map and ow.map.id
  if mapId ~= Karp.MAP then return false, "Go to the LAKE OF RAGE" end
  if not Karp.hasRod(game) then return false, "You need a ROD" end
  if not Karp.engine() then return false, "Not here" end
  return true
end

local function playing()
  local s = CoopMinigame.session
  if s and s.id == "karp" then return s end
  return nil
end

-- the hooked battle the engine is about to open, while a contest is on: the
-- fish is measured (or let go) here and no battle opens.  True = swallowed.
function Karp.onHooked(ow, battle)
  local s = playing()
  if not (s and battle and battle.pkmHooked) then return false end
  local game = (battle and battle.game) or (ow and ow.game) or require("src.core.Game")
  local mon = battle.enemy and battle.enemy.mon
  local name = (battle.enemy and battle.enemy.name) or "?"
  local text
  if s.phase ~= "play" then
    text = T("It got away...\nNo contest now.")
  elseif not (mon and speciesNumber(mon.species) == Karp.SPECIES) then
    text = string.format(T("%s\ngot away!\fOnly MAGIKARP\ncount here."), tostring(name))
  else
    local save = game and game.save
    local len = Karp.measure(mon, save and save.player and save.player.id or 0)
    if not len then
      text = T("It got away...\nNo contest now.")
    else
      local d = s.data
      d.catches = (d.catches or 0) + 1
      d.lengths = d.lengths or {}
      d.lengths[#d.lengths + 1] = len
      local best = len > (s.score or 0)
      if best then s:setScore(len) end
      text = string.format(T(best and "MAGIKARP: %s!\nYour longest yet!\fIt swims back into\nthe lake." or "MAGIKARP: %s.\nNot your longest.\fIt swims back into\nthe lake."),
                           Karp.lengthText(len))
    end
  end
  if game and game.stack then
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, text))
  end
  return true
end

local function today()
  local CM = package.loaded["src.coop.CoopManager"]
  return ((CM and CM.realDate) or os.date)("%Y-%m-%d")
end

-- the winner's prize: one GREAT BALL a day; nil when none is due
function Karp.givePrize(game)
  local save = game and game.save
  if not save then return nil end
  if save.coopKarpPrizeDay == today() then return "already" end
  local id = itemByKey(game.data, Karp.PRIZE)
  if not id then return nil end
  local ok, added = pcall(function() return require("src.inventory.Bag").add(save, id, 1, game.data) end)
  if not ok or added == false then return "full" end
  save.coopKarpPrizeDay = today()
  return "given"
end

Karp.def = CoopMinigame.register({
  id = "karp",
  name = "MAGIKARP CONTEST",
  info = { "FISH 2 MIN AT THE", "LAKE OF RAGE. THE", "LONGEST ONE WINS!" },
  duration = 120,
  lowWins = false,
  canStart = Karp.canStart,
  start = function(session)
    session.data.catches = 0
    session.data.lengths = {}
    session:setScore(0)
  end,
  draw = function(session)
    local Font = require("src.render.Font")
    local I18n = require("src.coop.CoopI18n")
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 4, 10, 3)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(I18n.fit(string.format(T("CATCH %d"), session.data.catches or 0), 8), 8, 40)
    love.graphics.setColor(1, 1, 1, 1)
  end,
  scoreText = function(score)
    if not score or score <= 0 then return "-" end
    return Karp.lengthText(score)
  end,
  finish = function(session, game, result)
    if result ~= "win" or not ((session.final or 0) > 0) then return end
    local CM = package.loaded["src.coop.CoopManager"]
    local got = Karp.givePrize(game)
    session.data.prize = got
    if got == "given" and CM and CM.showStatus then
      CM.showStatus(T("Prize: a GREAT BALL!"), 4)
    elseif got == "full" and CM and CM.showStatus then
      CM.showStatus(T("No room for the prize"), 4)
    elseif got == "already" and CM and CM.showStatus then
      CM.showStatus(T("Today's prize is won"), 4)
    end
  end,
})

return Karp
