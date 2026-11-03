-- src/coop/CoopClock.lua (split out of CoopManager.lua for 1.20)
-- install(CoopManager, CMI) runs this code where it used to sit in
-- CoopManager.lua: CoopManager.* names are the manager's own, and CMI
-- carries the manager's file-level locals it reads (and the ones it
-- hands on to the code after it).
--
-- time of day: both players can agree to share one clock.  mode is
-- "host", "guest" or "off" (each keeps their own); every side computes its
-- own offset from the offsets in the message, so the result is identical
-- whichever end decided.

local M = {}

function M.install(CoopManager, CMI)
local CoopLog = CMI.CoopLog
local CoopManager = CMI.CoopManager
local CoopNet = CMI.CoopNet
local getGame = CMI.getGame
local realDate = CMI.realDate
local realTime = CMI.realTime


-- ONE CLOCK FOR THE WHOLE GAME.  Day and night, the night music, the
-- evolutions that need it, the weekly events and the daily ones all read the
-- wall clock in different places (os.date/os.time).  While the two players
-- share a clock, the game's view of "now" is shifted to the agreed one --
-- every reader at once, rather than a handful patched and the rest left on
-- the local time.  A date TABLE passed to os.time, or a time passed to
-- os.date, is converted as given: only "what time is it" moves.
--
-- What measures real time keeps the real clock: the save's backups and
-- "open elsewhere" markers, sign-in tokens, downloads, the mod index, the
-- Bug Contest's twenty minutes and the co-op log.  Shifted, a session on a
-- clock 3 h ahead left a backup stamped 3 h in the future, and no rolling
-- backup was taken for the 3 h after it ended; a link that dropped mid-contest
-- moved its deadline by the whole offset.
CoopManager.REAL_CLOCK = {
  "src/core/Save", "src/core/BootTrace", "src/core/DiscordPresence", "src/cloud/",
  "src/net/", "src/mods/", "src/import/", "BugContest.lua", "CoopLog.lua",
}
local realCallers = {}
local function callerWantsReal()
  -- 1 = here, 2 = the shim, 3 = whoever asked the time (past a pcall)
  local info = debug.getinfo(3, "S")
  if info and info.what == "C" then info = debug.getinfo(4, "S") end
  local src = info and info.source
  if type(src) ~= "string" then return false end
  local real = realCallers[src]
  if real == nil then
    real = false
    for _, pat in ipairs(CoopManager.REAL_CLOCK) do
      if src:find(pat, 1, true) then real = true break end
    end
    realCallers[src] = real
  end
  return real
end

local function installClockShim()
  if (CoopManager.timeOffsetSec or 0) == 0 then
    os.time, os.date = realTime, realDate
    return
  end
  os.time = function(t)
    if t ~= nil then return realTime(t) end
    if callerWantsReal() then return realTime() end
    return realTime() + (CoopManager.timeOffsetSec or 0)
  end
  os.date = function(fmt, t)
    if t == nil then
      t = callerWantsReal() and realTime() or realTime() + (CoopManager.timeOffsetSec or 0)
    end
    return realDate(fmt or "%c", t)
  end
end
CoopManager.realTime = realTime

-- the weekday Mom's clock picked (Gen 2 save.g2DayOffset), shared too, or
-- the two would disagree about Bug Contest days and the weekday siblings
function CoopManager.dayOffset(save)
  if CoopManager.dayOffsetOverride ~= nil then return CoopManager.dayOffsetOverride end
  return (save and tonumber(save.g2DayOffset)) or 0
end

function CoopManager.applyTimeMode(mode, hostOffsetSec, guestOffsetSec, hostDay, guestDay)
  local localTz = (CoopManager.net and CoopManager.net.timezone) or CoopNet.detectTimezone()
  local localOff = localTz.offsetSec or 0
  local target, day
  if mode == "host" then target, day = tonumber(hostOffsetSec), tonumber(hostDay)
  elseif mode == "guest" then target, day = tonumber(guestOffsetSec), tonumber(guestDay) end
  CoopManager.timeMode = mode
  CoopManager.timeOffsetSec = target and (target - localOff) or 0
  CoopManager.dayOffsetOverride = (mode == "host" or mode == "guest") and day or nil
  installClockShim()
  CoopLog.sync("TIME_SYNC", string.format("mode=%s offset=%ds day=%s", tostring(mode),
               CoopManager.timeOffsetSec, tostring(CoopManager.dayOffsetOverride)))
end

function CoopManager.chooseTimeMode(mode)
  local localTz = (CoopManager.net and CoopManager.net.timezone) or CoopNet.detectTimezone()
  local partnerTz = CoopManager.partner.timezone or localTz
  local hostOff = CoopManager.isHost and localTz.offsetSec or partnerTz.offsetSec
  local guestOff = CoopManager.isHost and partnerTz.offsetSec or localTz.offsetSec
  local game = getGame()
  local myDay = (game and game.save and tonumber(game.save.g2DayOffset)) or 0
  local partnerDay = tonumber(CoopManager.partner.dayOffset) or 0
  local hostDay = CoopManager.isHost and myDay or partnerDay
  local guestDay = CoopManager.isHost and partnerDay or myDay
  CoopManager.applyTimeMode(mode, hostOff, guestOff, hostDay, guestDay)
  if CoopManager.net then
    CoopManager.net:send({ type = "coop_time_sync", mode = mode,
                           hostOffsetSec = hostOff, guestOffsetSec = guestOff,
                           hostDay = hostDay, guestDay = guestDay })
  end
end

local function promptTimezoneChoice(game)
  local localTz = CoopManager.net.timezone
  local partnerTz = CoopManager.partner.timezone or localTz
  local items = {
    { label = string.format("HOST %s", localTz.timeStr or "12:00"), onSelect = function()
      CoopManager.chooseTimeMode("host")
      CoopManager.showStatus("Sharing host clock!", 2.5)
    end },
    { label = string.format("GUEST %s", partnerTz.timeStr or "12:00"), onSelect = function()
      CoopManager.chooseTimeMode("guest")
      CoopManager.showStatus("Sharing guest clock!", 2.5)
    end },
    { label = "OWN CLOCKS", onSelect = function()
      CoopManager.chooseTimeMode("off")
    end },
  }
  game.stack:push(require("src.coop.CoopI18n").menu().new(game, items, {
    tx = 2, ty = 3, tw = 16,
    header = "SHARE CLOCK?",
    cancelable = true,
    onCancel = function() CoopManager.chooseTimeMode("off") end,
  }))
end

CMI.promptTimezoneChoice = promptTimezoneChoice
end

return M
