-- src/coop/CoopEditions.lua
-- THE VERSION MATRIX (nightly.3, link protocol 17).
--
-- Two copies may play different editions of the same generation: Red with
-- Blue (a PAIR: the same story, only their wild Pokemon differ), or a base
-- edition with its THIRD one -- Red/Blue with Yellow, Gold/Silver with
-- Crystal -- whose story is mostly the same and partly its own.  Before
-- this, Gen 1 shared everything (Yellow's Jessie & James and gift starters
-- landed on Red as flags) and Gold/Silver with Crystal shared nothing
-- unless an experimental rule was on.
--
-- Every story event now goes through one filter on the copy that RECEIVES
-- it, which knows its own edition:
--
--   * SAME / PAIR: as it comes (Gold <-> Silver still swap their wings,
--     CoopStory.remapVersionRewards).
--   * THIRD, Gen 1: the sender tags each flag that comes from its edition's
--     own data (`ed`: a trainer in trainer_headers, a field event), and the
--     receiver keeps such a flag only if its edition has it too -- Red's
--     Mt. Moon and Pokemon Tower Rockets are Yellow's Jessie & James.  Flags
--     written only by the other edition's own scripts (the engine's
--     data/scripts/*yellow*.lua: Pikachu, the catch tutorial, the Cerulean
--     BULBASAUR, Jessie & James) are dropped.  CONFLICT lists, per family,
--     what exists in both but must not cross, or crosses renamed.
--   * THIRD, Gen 2: each EVENT_G2_#### is moved to the other cartridge's
--     number (src/coop/CoopCrossStory.lua, 1159 events by name); what has no
--     twin, and what is laid out apart (scenes, WRAM), is dropped.
--   * An event whose story pieces were ALL dropped is the other edition's
--     own: its items and money are not handed out either.
--
-- The third-edition share is the rule "3RD ED. STORY" (on by default; it
-- was the experimental G/S+C STORY, off).
local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")

local CoopEditions = {}
CoopEditions.CAP = "story.compat"
CoopManager.registerCap(CoopEditions.CAP)

CoopEditions.FAMILY = { red = "rby", blue = "rby", yellow = "rby",
                      gold = "gsc", silver = "gsc", crystal = "gsc" }
CoopEditions.THIRD = { yellow = true, crystal = true }

-- per family: a flag that exists in both editions but must not cross
-- (false), or crosses as another name (a string).  Empty until a real test
-- shows one; each entry says why.
CoopEditions.CONFLICT = { rby = {}, gsc = {} }

local function GV() return require("src.core.GameVersion") end

-- this copy's (or `id`'s) edition, for the hello and the logs
function CoopEditions.profile(id)
  local V = GV()
  id = id or V.get()
  local okG, gen = pcall(V.generation, id)
  return { version = id, gen = okG and gen or nil, family = CoopEditions.FAMILY[id],
           third = CoopEditions.THIRD[id] == true }
end

-- "same" | "pair" | "third" | "capsule" | "other" | nil (not known: the
-- old behaviour applies)
function CoopEditions.relation(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return nil end
  if a == b then return "same" end
  local fa, fb = CoopEditions.FAMILY[a], CoopEditions.FAMILY[b]
  if fa and fa == fb then
    if (CoopEditions.THIRD[a] == true) ~= (CoopEditions.THIRD[b] == true) then return "third" end
    return "pair"
  end
  local V = GV()
  local okA, ga = pcall(V.generation, a)
  local okB, gb = pcall(V.generation, b)
  if okA and okB and ((ga == 1 and gb == 2) or (ga == 2 and gb == 1)) then return "capsule" end
  if fa and fb then return "other" end
  return nil
end

-- the third-edition share is on for this link
function CoopEditions.thirdOn()
  return CoopManager.crossStory ~= false and CoopManager.bothHave(CoopEditions.CAP)
end

-- ---------------------------------------------------------------- Gen 1

-- the events this edition's own data names (trainers, field), per dataset
local editionCache = setmetatable({}, { __mode = "k" })
local function editionEvents(data)
  if type(data) ~= "table" then return {} end
  local got = editionCache[data]
  if got then return got end
  local set = {}
  for _, list in pairs(type(data.trainer_headers) == "table" and data.trainer_headers or {}) do
    for _, h in pairs(type(list) == "table" and list or {}) do
      if type(h) == "table" and type(h.event) == "string" then set[h.event] = true end
    end
  end
  local seen = {}
  local function walk(t, depth)
    if depth > 6 or seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
      if type(v) == "string" and v:match("^EVENT_[%u%d_]+$") then set[v] = true
      elseif type(k) == "string" and k:match("^EVENT_[%u%d_]+$") then set[k] = true end
      if type(v) == "table" then walk(v, depth + 1) end
    end
  end
  if type(data.field) == "table" then walk(data.field, 0) end
  editionCache[data] = set
  return set
end
CoopEditions.editionEvents = editionEvents

-- Flags only the engine's scripts for one edition write: { version = set }.
-- Read once from data/scripts (the files named after that edition), less
-- what any other script writes too.
local scriptOwned
local function readScript(path)
  local fs = love and love.filesystem
  if fs and fs.read then
    local ok, s = pcall(fs.read, path)
    if ok and type(s) == "string" then return s end
  end
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local function listScripts()
  local fs = love and love.filesystem
  if fs and fs.getDirectoryItems then
    local ok, items = pcall(fs.getDirectoryItems, "data/scripts")
    if ok and type(items) == "table" and #items > 0 then return items end
  end
  local out = {}
  local p = io.popen and io.popen('ls data/scripts 2>/dev/null')
  if p then
    for line in p:lines() do out[#out + 1] = line end
    p:close()
  end
  return out
end
function CoopEditions.scriptOwned()
  if scriptOwned then return scriptOwned end
  local per, common = {}, {}
  for _, name in ipairs(listScripts()) do
    if name:match("%.lua$") then
      local src = readScript("data/scripts/" .. name) or ""
      local owner
      for v in pairs(CoopEditions.THIRD) do
        if name:find(v, 1, true) then owner = v end
      end
      for _, cmd in ipairs({ "set_flag", "clear_flag" }) do
        for id in src:gmatch('"' .. cmd .. '", *"(EVENT_[%u%d_]+)"') do
          if owner then
            per[owner] = per[owner] or {}
            per[owner][id] = true
          else
            common[id] = true
          end
        end
      end
    end
  end
  for _, set in pairs(per) do
    for id in pairs(common) do set[id] = nil end
  end
  scriptOwned = per
  return per
end

-- before a story event goes out: each flag this edition's data names is
-- tagged, so a receiver on another edition can tell it from the shared ones
function CoopEditions.tag(game, rewards)
  if type(rewards) ~= "table" then return rewards end
  local data = game and game.data
  local set = editionEvents(data)
  for _, r in ipairs(rewards) do
    if (r.kind == "set_flag" or r.kind == "clear_flag") and type(r.id) == "string" and set[r.id] then
      r.ed = true
    end
  end
  return rewards
end

local function keepGen1(game, r, mine)
  local id = r.id
  if type(id) ~= "string" then return true end
  local conflict = CoopEditions.CONFLICT.rby[id]
  if conflict == false then return false end
  if type(conflict) == "string" then r.id = conflict id = conflict end
  for v, set in pairs(CoopEditions.scriptOwned()) do
    if v ~= mine and set[id] then return false end
  end
  if r.ed and not editionEvents(game and game.data)[id] then return false end
  return true
end

-- ---------------------------------------------------------------- filter

local STORY = { set_flag = true, clear_flag = true, scene = true, scene_key = true, toggle = true,
                taken = true, hidden_taken = true, wram = true, var_sprite = true, special_call = true }
local GOODS = { item = true, money = true, coins = true, take_item = true }

-- A partner's story event, made this edition's (in place).  Returns how many
-- pieces were dropped.  `msg.src` is the sender's edition (older senders:
-- the partner's game).
function CoopEditions.filter(game, msg)
  if type(msg) ~= "table" or type(msg.rewards) ~= "table" or msg.compatDone then return 0 end
  msg.compatDone = true
  local V = GV()
  local mine = V.get()
  local theirs = type(msg.src) == "string" and msg.src or (CoopManager.partner and CoopManager.partner.game)
  local rel = CoopEditions.relation(mine, theirs)
  if rel ~= "third" then return 0 end
  local family = CoopEditions.FAMILY[mine]
  local before, storyIn = #msg.rewards, 0
  for _, r in ipairs(msg.rewards) do if STORY[r.kind] then storyIn = storyIn + 1 end end
  if family == "gsc" then
    local Cross = require("src.coop.CoopCrossStory")
    Cross.translate(msg)
  elseif family == "rby" then
    local out = {}
    for _, r in ipairs(msg.rewards) do
      if not ((r.kind == "set_flag" or r.kind == "clear_flag") and not keepGen1(game, r, mine)) then
        out[#out + 1] = r
      end
    end
    msg.rewards = out
  end
  local storyOut = 0
  for _, r in ipairs(msg.rewards) do if STORY[r.kind] then storyOut = storyOut + 1 end end
  -- the whole story of it was the other edition's own: so are its goods
  if storyIn > 0 and storyOut == 0 then
    local out = {}
    for _, r in ipairs(msg.rewards) do if not GOODS[r.kind] then out[#out + 1] = r end end
    msg.rewards = out
    msg.exclusive = true
  end
  local dropped = before - #msg.rewards
  if dropped > 0 then
    CoopLog.info("STORY", string.format("%s -> %s: %d piece(s) are %s's own, not applied%s",
      tostring(theirs), tostring(mine), dropped, tostring(theirs), msg.exclusive and " (the whole event)" or ""))
  end
  return dropped
end

-- ---------------------------------------------------------------- sharing

-- CoopManager.storyCompatible, through the matrix: one edition with itself
-- or its pair always; with its third edition while the rule is on; never
-- across generations (the Time Capsule shares no story)
local legacy = CoopManager.storyCompatible
CoopManager.storyCompatible = function(theirGame, ...)
  if CoopManager.capsule and theirGame == nil then return false end
  local theirs = theirGame or (CoopManager.partner and CoopManager.partner.game)
  local rel = CoopEditions.relation(GV().get(), theirs)
  if rel == "same" or rel == "pair" then return true end
  if rel == "third" then return CoopEditions.thirdOn() end
  if rel == "capsule" or rel == "other" then return false end
  return legacy(theirGame, ...)
end

return CoopEditions
