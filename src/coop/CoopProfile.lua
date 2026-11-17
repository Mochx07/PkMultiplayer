-- src/coop/CoopProfile.lua
-- YOUR CO-OP NAME (nightly.2).  The co-op screens used to call a player with
-- no trainer name yet -- a NEW CO-OP GAME, before the intro asks for one --
-- "HOST" or "GUEST", and the lobby showed "HOST & GUEST".  The link screen
-- now asks for a name first (CoopNewGame, stage "name"), kept here across
-- games in modstorage/PkMultiplayer/profile.json, not in a save.  The
-- trainer's own name, once the save has one, still comes first
-- (CoopManager.getLocalPlayerName).

local CoopProfile = {}

CoopProfile.FILE = "modstorage/PkMultiplayer/profile.json"
CoopProfile.MAX = 7  -- a Gen 1 / Gen 2 trainer name
-- the letters the cartridge's name screen offers, plus digits
CoopProfile.LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "

local function fs() return love and love.filesystem end
local function json() return require("src.link.Json") end

local cache = nil
function CoopProfile.forget() cache = nil end

function CoopProfile.load()
  if cache then return cache end
  local t = {}
  local f = fs()
  if f and f.read then
    local ok, text = pcall(f.read, CoopProfile.FILE)
    if ok and type(text) == "string" then
      local ok2, r = pcall(json().decode, text)
      if ok2 and type(r) == "table" then t = r end
    end
  end
  cache = t
  return cache
end

-- only what the name screen could have typed: upper case, letters, digits,
-- single spaces, at most MAX, trimmed
function CoopProfile.clean(name)
  if type(name) ~= "string" then return "" end
  local s = name:upper():gsub("[^A-Z0-9 ]", ""):gsub("  +", " "):gsub("^ +", "")
  s = s:sub(1, CoopProfile.MAX):gsub(" +$", "")
  return s
end

function CoopProfile.name()
  local n = CoopProfile.clean(CoopProfile.load().name)
  return n ~= "" and n or nil
end

function CoopProfile.setName(name)
  local n = CoopProfile.clean(name)
  if n == "" then return false end
  local t = CoopProfile.load()
  t.name = n
  local f = fs()
  if f and f.write then
    pcall(function()
      f.createDirectory(CoopProfile.FILE:match("^(.*)/[^/]+$"))
      f.write(CoopProfile.FILE, json().encode(t))
    end)
  end
  return true
end

-- one letter of the D-pad editor stepped by `d` through LETTERS
function CoopProfile.step(ch, d)
  local L = CoopProfile.LETTERS
  local i = L:find(ch or " ", 1, true) or #L
  i = ((i - 1 + d) % #L) + 1
  return L:sub(i, i)
end

return CoopProfile
