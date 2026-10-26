-- THE POKéGEAR CLOCK SHOWS THE TIME THE GAME RUNS ON.
--
-- Reported from play: "hora del pokegear rara".  The clock card printed the
-- PLAY TIME as the hour and the day -- while day and night, the weekday
-- siblings and the daily events all read the wall clock and Mom's weekday.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local SaveData = require("src.core.SaveData")
local PokegearMenu = require("src.ui.PokegearMenu")
local CoopManager = require("src.coop.CoopManager")
require("src.coop.CoopLog").enabled = false

local DAYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" }

local function shown(save)
  local out = {}
  local menu = setmetatable({ game = { data = Data, save = save }, blink = 0 }, { __index = PokegearMenu })
  menu.text = function(_, s, x, y) out[#out + 1] = { s = tostring(s), x = x, y = y } end
  for _, k in ipairs({ "drawTilemap", "drawStrip", "textbox", "printBoxText", "drawModeArrow" }) do
    menu[k] = function() end
  end
  menu.groundColor = function() return { 255, 255, 255 } end
  menu:drawClock()
  local at = {}
  for _, t in ipairs(out) do at[t.x .. "," .. t.y] = t.s end
  return at
end

local save = SaveData.newGame()
-- a long game: 100 h 37 min of play, which the old clock printed as the time
save.playTime = 100 * 3600 + 37 * 60
save.playSeconds = save.playTime
save.g2DayOffset = 0
CoopManager.dayOffsetOverride = nil

local now = os.date("*t")
local at = shown(save)
local hour12 = now.hour % 12
if hour12 == 0 then hour12 = 12 end
T.check(at["6,6"] == DAYS[now.wday], ("the day is today's (%s, got %s)"):format(DAYS[now.wday], tostring(at["6,6"])))
T.check(tonumber(at["6,8"]) == hour12, ("the hour is the wall clock's (%d, got %s)"):format(hour12, tostring(at["6,8"])))
T.check(at["12,8"] == (now.hour < 12 and "AM" or "PM"), "AM/PM follows the wall clock")
-- (the minute can tick over between the two reads; allow one)
local m = tonumber(at["9,8"])
T.check(m == now.min or m == (now.min + 1) % 60, ("the minute is the wall clock's (%d, got %s)"):format(now.min, tostring(at["9,8"])))

-- Mom's clock picked another weekday: the POKéGEAR says that one
save.g2DayOffset = 2
local at2 = shown(save)
T.check(at2["6,6"] == DAYS[((now.wday - 1 + 2) % 7) + 1], "the day follows the weekday Mom's clock picked (" .. tostring(at2["6,6"]) .. ")")

-- sharing a clock with a partner shares their weekday as well
CoopManager.dayOffsetOverride = 5
local at3 = shown(save)
T.check(at3["6,6"] == DAYS[((now.wday - 1 + 5) % 7) + 1], "a shared clock's weekday is the one shown (" .. tostring(at3["6,6"]) .. ")")
CoopManager.dayOffsetOverride = nil

T.finish("pokegear clock")
