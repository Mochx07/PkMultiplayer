-- src/coop/CoopLog.lua
-- High-performance, robust logging system for Gen2Recomped Co-op mode.
-- Supports in-memory circular buffer, file output with rotation, and categorized tags.

local CoopLog = {}

CoopLog.MAX_BUFFER = 200
CoopLog.MAX_FILE_BYTES = 1024 * 1024 -- 1 MB rotation cap

CoopLog.buffer = {}
CoopLog.fileHandle = nil
CoopLog.filePath = "coop.log"
CoopLog.enabled = true

local function getTimestamp()
  local ok, dateStr = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and dateStr then
    local ms = math.floor(((love and love.timer and love.timer.getTime() or 0) % 1) * 1000)
    return string.format("%s.%03d", dateStr, ms)
  end
  return "0000-00-00 00:00:00.000"
end

local function getLogFilePath()
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local saveDir = love.filesystem.getSaveDirectory()
    return saveDir .. "/coop.log"
  end
  return "coop.log"
end

local function openLogFile()
  if CoopLog.fileHandle then return CoopLog.fileHandle end
  CoopLog.filePath = getLogFilePath()

  -- Check size for rotation
  local okSize, fTest = pcall(io.open, CoopLog.filePath, "r")
  if okSize and fTest then
    local currentSize = fTest:seek("end") or 0
    fTest:close()
    if currentSize > CoopLog.MAX_FILE_BYTES then
      pcall(os.rename, CoopLog.filePath, CoopLog.filePath .. ".old")
    end
  end

  local ok, f = pcall(io.open, CoopLog.filePath, "a")
  if ok and f then
    CoopLog.fileHandle = f
    f:write(string.format("\n=== CO-OP SESSION STARTED AT %s ===\n", getTimestamp()))
    f:flush()
  end
  return CoopLog.fileHandle
end

function CoopLog.write(level, tag, message)
  if not CoopLog.enabled then return end

  local ts = getTimestamp()
  local entry = {
    timestamp = ts,
    level = level or "INFO",
    tag = tag or "GENERAL",
    message = tostring(message or ""),
  }

  -- In-memory circular buffer
  table.insert(CoopLog.buffer, entry)
  if #CoopLog.buffer > CoopLog.MAX_BUFFER then
    table.remove(CoopLog.buffer, 1)
  end

  -- Formatted line
  local line = string.format("[%s] [%s] [%s] %s\n", entry.timestamp, entry.level, entry.tag, entry.message)

  -- Write to file
  -- Buffered: a flush is a syscall, and the battle/sync paths log several
  -- lines a frame.  Warnings and errors still reach the disk immediately so a
  -- crash right after one leaves it in the file.
  pcall(function()
    local f = openLogFile()
    if f then
      f:write(line)
      local t = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
      if level == "ERROR" or level == "WARN" or (t - (CoopLog.lastFlush or 0)) >= 1.0 then
        CoopLog.lastFlush = t
        f:flush()
      end
    end
  end)

  -- shared with the partner (src/coop/CoopLogShare.lua)
  if CoopLog.onLine then pcall(CoopLog.onLine, entry, line) end

  -- If error level, print to standard console too
  if level == "ERROR" then
    io.stderr:write("[COOP ERROR] " .. line)
  end
end

function CoopLog.info(tag, msg)
  CoopLog.write("INFO", tag, msg)
end

function CoopLog.warn(tag, msg)
  CoopLog.write("WARN", tag, msg)
end

function CoopLog.error(tag, msg)
  CoopLog.write("ERROR", tag, msg)
end

function CoopLog.net(direction, msgType, details)
  local detailStr = details and (type(details) == "table" and (" " .. (details.seq and ("seq=" .. details.seq) or "")) or (" " .. tostring(details))) or ""
  CoopLog.write("NET", "NET", string.format("%s %s%s", direction, msgType, detailStr))
end

function CoopLog.battle(tag, msg)
  CoopLog.write("INFO", "BATTLE:" .. (tag or "TURN"), msg)
end

function CoopLog.sync(tag, msg)
  CoopLog.write("INFO", "SYNC:" .. (tag or "STATE"), msg)
end

function CoopLog.getRecent(count)
  count = count or 20
  local startIdx = math.max(1, #CoopLog.buffer - count + 1)
  local result = {}
  for i = startIdx, #CoopLog.buffer do
    table.insert(result, CoopLog.buffer[i])
  end
  return result
end

function CoopLog.close()
  if CoopLog.fileHandle then
    pcall(function()
      CoopLog.fileHandle:write(string.format("=== CO-OP SESSION CLOSED AT %s ===\n\n", getTimestamp()))
      CoopLog.fileHandle:flush()
      CoopLog.fileHandle:close()
    end)
    CoopLog.fileHandle = nil
  end
end

return CoopLog
