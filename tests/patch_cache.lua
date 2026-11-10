-- THE BUILT PATCHES ARE KEPT BETWEEN RUNS (1.20, lib/Transplant.lua + main.lua).
--
-- Placing every edit by its context is most of what loading the mod costs.
-- The second time the game starts with the same engine and the same patch,
-- the texts come from modstorage; what the engine ends up running must be
-- exactly what a build from scratch gives, and a cache that is stale, cut
-- short or tampered with must simply not be used.
--
--   cd <Gen2Recomped checkout>
--   PKM_EAGER=1 PKM_PRE=<mod>/tests/patch_cache_pre.lua luajit <mod>/tests/run.lua <mod>/tests/patch_cache.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local first = assert(rawget(_G, "__PKMULTIPLAYER"), "run through tests/run.lua")
assert(love and love.data and love.data.hash, "run with PKM_PRE=tests/patch_cache_pre.lua")
local here = first.mod.path
local index = dofile(here .. "/lib/patches/index.lua")
local lf = love.filesystem
local DIR = "modstorage/PkMultiplayer/patchcache"

local fails, total = 0, 0
local function check(cond, what)
  total = total + 1
  if not cond then
    fails = fails + 1
    print("FAIL " .. what)
  end
end

local function boot()
  rawset(_G, "__PKMULTIPLAYER", nil)
  local lines = {}
  local function logger(level)
    return function(_, fmt, ...) lines[#lines + 1] = level .. " " .. fmt:format(...) end
  end
  local api = {
    id = "PkMultiplayer", version = "test", path = here, generation = 2,
    log = { info = logger("info"), warn = logger("warn"), error = logger("error") },
    hooks = { wrap = function() end },
  }
  function api:read(rel)
    local f = io.open(here .. "/" .. rel, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
  end
  assert(loadfile(here .. "/main.lua"))(api)
  return assert(rawget(_G, "__PKMULTIPLAYER")), lines
end

local function tally(state)
  local units, cached, failed, sources = 0, 0, 0, {}
  for _, spec in ipairs(index.modules) do
    local r = assert(state.reports[spec.module], spec.module .. " has no report")
    units = units + r.replaced
    cached = cached + (r.cached or 0)
    failed = failed + #r.failed
    sources[spec.module] = r.source
  end
  return units, cached, failed, sources
end

local function fileOf(module) return DIR .. "/" .. module:gsub("[^%w]", "_") .. ".lua" end

-- the first load built everything and wrote it down
local units1, cached1, failed1, sources1 = tally(first)
check(failed1 == 0 and units1 > 100, "first load: every module patched (" .. units1 .. " functions)")
check(cached1 == 0, "first load: nothing came from a cache that did not exist")
-- (a module whose patch only adds functions of its own has nothing to keep)
local function ownUnits(spec)
  local own, all = 0, 0
  for _, u in ipairs(dofile(here .. "/" .. spec.patch).units or {}) do
    all = all + 1
    if u.text then own = own + 1 end
  end
  return own, all
end
local written, expected = 0, 0
for _, spec in ipairs(index.modules) do
  local own, all = ownUnits(spec)
  if own < all then expected = expected + 1 end
  if lf.read(fileOf(spec.module)) then written = written + 1 end
end
check(written == expected and written > 15, ("first load: one cache file per module with edits (%d of %d)"):format(written, expected))

-- the second load takes the texts from there, and runs the very same code
local second = boot()
local units2, cached2, failed2, sources2 = tally(second)
check(failed2 == 0 and units2 == units1, "second load: every module patched again")
check(cached2 > units1 * 0.8, ("second load: the built texts come from the cache (%d of %d)"):format(cached2, units1))
local same = true
for module, text in pairs(sources1) do
  if sources2[module] ~= text then
    same = false
    print("  differs: " .. module)
  end
end
check(same, "second load: what the engine runs is byte for byte what a fresh build gave")

-- a cache for another engine file or another patch is not used
local probe = index.modules[1].module
local good = lf.read(fileOf(probe))
lf.write(fileOf(probe), (good:gsub('key = "', 'key = "x', 1)))
local third = boot()
check((third.reports[probe].cached or 0) == 0 and #third.reports[probe].failed == 0
      and third.reports[probe].source == sources1[probe],
      "a cache made for other files is ignored and the module is built afresh")
check(lf.read(fileOf(probe)) == good, "...and replaced by a good one")

-- one cut short, or that is not a table, or that tries to do something
for _, bad in ipairs({ good:sub(1, #good / 2), "return 7", "os.exit(3)", "error('x')", "" }) do
  lf.write(fileOf(probe), bad)
  local state = boot()
  check(#state.reports[probe].failed == 0 and state.reports[probe].source == sources1[probe],
        "a broken cache file never breaks the load (" .. bad:sub(1, 12):gsub("\n", " ") .. ")")
end

-- a unit whose function moved in the file is rebuilt, the rest still kept
local text = lf.read(fileOf(probe))
local moved = text:gsub("line = (%d+)", function(n) return "line = " .. (tonumber(n) + 1) end, 1)
lf.write(fileOf(probe), moved)
local state = boot()
local r = state.reports[probe]
check(#r.failed == 0 and r.source == sources1[probe]
      and (r.cached or 0) == (second.reports[probe].cached or 0) - 1 and (r.cached or 0) > 0,
      "a function that is not where the cache says is rebuilt; the others are kept")

-- off on request
local env = os.getenv
os.getenv = function(k) if k == "PKM_NO_PATCH_CACHE" then return "1" end return env(k) end
local off = boot()
os.getenv = env
local _, cachedOff, failedOff = tally(off)
check(cachedOff == 0 and failedOff == 0, "PKM_NO_PATCH_CACHE=1 builds everything from scratch")

print(("%d/%d checks passed  (patch cache)"):format(total - fails, total))
if fails > 0 then os.exit(1) end
