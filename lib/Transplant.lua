-- Transplant: put a newer copy of an engine function into the running engine.
--
-- A patch file (lib/patches/*.lua) holds functions exactly as they read in
-- the co-op build, the way they would sit in the engine file itself.  The
-- engine file's own `local`s (helpers, tables, other modules) are not
-- reachable from a separate chunk, so the patch chunk runs in an environment
-- that resolves every one of those names to the live value the engine's own
-- functions hold as an upvalue:
--
--   1. names the patch declares itself (its own `local`s)    -- plain Lua
--   2. the engine file's top-level locals (`scope`)          -- upvalues
--   3. everything else                                       -- _G
--
-- A local FUNCTION the patch replaces (or a local table it redefines) is
-- written back into that shared upvalue, so every untouched engine function
-- calling it gets the new one as well.

local Transplant = {}

local getupvalue, setupvalue = debug.getupvalue, debug.setupvalue

-- WHAT WAS THERE BEFORE THIS MOD, and a way to put it back.
--
-- Going back to the launcher takes the mod's globals out of _G, but the
-- engine's modules stay loaded -- still holding the co-op functions of the
-- load before.  Those are not the engine's source, so the next load could not
-- edit them ("the engine function's source is not readable") and left half
-- the co-op unpatched.  Every change made here is now written down:
--   * Transplant.record, when main.lua sets it, gets an undo for each one --
--     put back only while the slot still holds what this mod put there, so a
--     wrapper another mod added since is never thrown away;
--   * ORIG maps each function this mod put in to the one it replaced, so a
--     copy left over from an earlier load can be seen through to the engine's.
-- ORIG lives on `package`, which outlives a load (the engine does not put it
-- back), and holds its keys weakly.
local ORIG = rawget(package, "__pkmultiplayer_orig")
if not ORIG then
  ORIG = setmetatable({}, { __mode = "k" })
  rawset(package, "__pkmultiplayer_orig", ORIG)
end
Transplant.ORIG = ORIG
-- ...and which load put each one in (package.__pkmultiplayer_load, set by
-- main.lua): only an EARLIER load's copy is looked through -- this load's own
-- (a co-op copy a wrapper then goes around) is the thing to build on
local BORN = rawget(package, "__pkmultiplayer_born")
if not BORN then
  BORN = setmetatable({}, { __mode = "k" })
  rawset(package, "__pkmultiplayer_born", BORN)
end
local function thisLoad() return rawget(package, "__pkmultiplayer_load") end

-- the function behind every copy an earlier load of this mod put in front of it
local function original(f)
  local now = thisLoad()
  for _ = 1, 32 do
    local o = ORIG[f]
    if o == nil or BORN[f] == now then break end
    f = o
  end
  return f
end
Transplant.original = original

local function note(undo)
  if Transplant.record then Transplant.record(undo) end
end

-- upvalue `idx` of `fn` := v, written down
local function setUp(fn, idx, v)
  local _, old = getupvalue(fn, idx)
  if old == v then return end
  if type(v) == "function" and type(old) == "function" then ORIG[v], BORN[v] = old, thisLoad() end
  note(function()
    local _, cur = getupvalue(fn, idx)
    if cur == v then setupvalue(fn, idx, old) end
  end)
  setupvalue(fn, idx, v)
end

-- t[k] went from `old` to its current value: written down
local function noteField(t, k, old)
  local v = rawget(t, k)
  if v == old then return end
  if type(v) == "function" and type(old) == "function" then ORIG[v], BORN[v] = old, thisLoad() end
  note(function()
    if rawget(t, k) == v then rawset(t, k, old) end
  end)
end
local getinfo = debug.getinfo

-- ---------------------------------------------------------------- hashing
-- FNV-1a over the bytes, the same as tools/gen_patches.py, so a patch can
-- tell whether the engine function it replaces is still the one it was
-- written against.
local bit = bit or (pcall(require, "bit") and require("bit")) or nil

function Transplant.fnv(s)
  if not bit then return nil end
  -- 32-bit FNV prime 0x01000193, multiplied in two halves so no product
  -- passes 2^53
  local h = 0x811C9DC5
  for i = 1, #s do
    h = bit.bxor(h, s:byte(i))
    if h < 0 then h = h + 0x100000000 end
    h = (h * 0x193 + (h * 0x100) % 0x10000 * 0x10000) % 0x100000000
  end
  return bit.tohex(h)
end

local function readSource(path)
  if love and love.filesystem and love.filesystem.read then
    local ok, text = pcall(love.filesystem.read, path)
    if ok and type(text) == "string" then return text end
  end
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local sourceLines = {}
local function linesOf(path)
  local hit = sourceLines[path]
  if hit == nil then
    local text = readSource(path)
    hit = false
    if text then
      hit = {}
      for line in (text .. "\n"):gmatch("([^\n]*)\n") do hit[#hit + 1] = line end
    end
    sourceLines[path] = hit
  end
  return hit or nil
end

-- The text of a Lua function as it stands in its file, or nil.
function Transplant.sourceOf(fn)
  if type(fn) ~= "function" then return nil end
  local info = getinfo(fn, "S")
  if not info or info.what ~= "Lua" then return nil end
  local src = info.source or ""
  if src:sub(1, 1) ~= "@" then return nil end
  local lines = linesOf(src:sub(2))
  if not lines then return nil end
  local first, last = info.linedefined, info.lastlinedefined
  if not (first and last and first > 0 and last >= first) then return nil end
  return table.concat(lines, "\n", first, math.min(last, #lines))
end

-- Was this chunk loaded from `file`?  "@src/x.lua" under LOVE,
-- "@./src/x.lua" under a plain `luajit` run.
local function isFile(src, file)
  return type(src) == "string" and src:sub(1, 1) == "@"
     and src:sub(-#file) == file
     and (#src == #file + 1 or src:sub(-#file - 1, -#file - 1) == "/")
end
Transplant.isFile = isFile

-- ------------------------------------------------------------ the scope
-- Every top-level local of `file`, found as an upvalue of some function that
-- file defined.  Walks the module table and, through upvalues, the local
-- helpers and local tables those functions hold.
function Transplant.scope(module, file)
  local refs = {}
  local seenFn, seenTab = {}, {}
  local visitTab

  -- `foreign` counts the steps taken through functions from OTHER files: a
  -- mod that wrapped an engine method holds the original as an upvalue, and
  -- the original's locals are still the engine file's
  local function visitFn(f, foreign)
    if seenFn[f] then return end
    seenFn[f] = true
    local info = getinfo(f, "S")
    if not info then return end
    if not isFile(info.source, file) then
      if (foreign or 0) >= 2 then return end
      local i = 1
      while true do
        local name, value = getupvalue(f, i)
        if not name then break end
        if type(value) == "function" then visitFn(value, (foreign or 0) + 1) end
        i = i + 1
      end
      return
    end
    local i = 1
    while true do
      local name, value = getupvalue(f, i)
      if not name then break end
      if refs[name] == nil then refs[name] = { fn = f, idx = i } end
      if type(value) == "function" then
        visitFn(value)
      elseif type(value) == "table" then
        visitTab(value, 0)
      end
      i = i + 1
    end
  end

  function visitTab(t, depth)
    if seenTab[t] or depth > 3 then return end
    seenTab[t] = true
    for _, v in pairs(t) do
      if type(v) == "function" then
        visitFn(v)
      elseif type(v) == "table" then
        visitTab(v, depth + 1)
      end
    end
    local mt = getmetatable(t)
    if type(mt) == "table" and type(mt.__index) == "table" then
      visitTab(mt.__index, depth + 1)
    end
  end

  visitTab(module, 0)
  return refs
end

-- ------------------------------------------------------------ the edits
local function trim(line) return (line:match("^%s*(.-)%s*$")) end
local function lineHash(line) return Transplant.fnv(trim(line)) end

local function splitLines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
  return out
end

-- Where does `edit` go in `lines` (whose hashes are `hashes`), and how many
-- lines does it cut?  At its recorded line when the function is the one the
-- patch was made against.  Otherwise by its context -- the lines it cuts, and
-- the two before and after -- taking the match nearest to where it is
-- expected (its recorded line, shifted as much as the edit before it was)
-- and never before the end of that edit.  When upstream changed lines
-- INSIDE the block the co-op build replaces, the block is found between its
-- before and after context instead.
local function locate(edit, hashes, exact, expect, floor)
  local cut = edit.cut or 0
  if exact then return edit.at, cut end
  local ctx = edit.ctx or {}
  local before, old, after = ctx.before or {}, ctx.old or {}, ctx.after or {}
  local function matchesAt(p, seq)
    for k = 1, #seq do
      if hashes[p + k - 1] ~= seq[k] then return false end
    end
    return true
  end
  -- the start of `seq`'s match nearest `want`, at or after `lo`
  local function nearest(seq, want, lo)
    if #seq == 0 then return nil end
    local best, dist
    for p = math.max(1, lo), #hashes - #seq + 1 do
      if matchesAt(p, seq) then
        local d = math.abs(p - want)
        if not dist or d < dist then best, dist = p, d end
      end
    end
    return best
  end
  local function cat(...)
    local out = {}
    for _, t in ipairs({ ... }) do for _, h in ipairs(t) do out[#out + 1] = h end end
    return out
  end
  local nb = #before
  local p = nearest(cat(before, old, after), expect - nb, floor - nb)
  if p then return p + nb, cut end
  if #old > 0 then
    p = nearest(cat(before, old), expect - nb, floor - nb)
    if p then return p + nb, cut end
    p = nearest(cat(old, after), expect, floor)
    if p then return p, cut end
    p = nearest(old, expect, floor)
    if p then return p, cut end
  end
  -- bracketed by its context: whatever stands between them is the block
  if nb > 0 and #after > 0 then
    local b = nearest(before, expect - nb, floor - nb)
    if b then
      local a = nearest(after, b + nb + #old, b + nb)
      if a and a - (b + nb) <= #old * 2 + 5 then return b + nb, a - (b + nb) end
    end
  end
  -- ...or between the function's first line and its after context
  if nb == 0 and edit.at == 1 and #after > 0 then
    local a = nearest(after, 1 + #old, 1)
    if a and a - 1 <= #old * 2 + 5 then return 1, a - 1 end
  end
  if #old == 0 then
    if nb > 0 then
      p = nearest(before, expect - nb, floor - nb)
      if p then return p + nb, 0 end
    end
    if #after > 0 then
      p = nearest(after, expect, floor)
      if p then return p, 0 end
    end
  end
  return nil
end

-- The co-op build's text of one function: `src` (the engine's function as
-- the player's copy has it) with the unit's edits applied.  nil, why when an
-- edit cannot be placed.
function Transplant.build(src, unit)
  if unit.text then return table.concat(unit.text, "\n") end
  if not src then return nil, "the engine function's source is not readable" end
  local lines = splitLines(src)
  local hashes = {}
  for i, l in ipairs(lines) do hashes[i] = lineHash(l) end
  local exact = unit.base ~= nil and Transplant.fnv(src) == unit.base
  local placed, cuts = {}, {}
  local shift, floor = 0, 1
  for i, e in ipairs(unit.edits or {}) do
    local at, cut = locate(e, hashes, exact, e.at + shift, floor)
    if not at then return nil, ("edit %d (line %d) has no place"):format(i, e.at) end
    placed[i], cuts[i] = at, cut
    shift = at - e.at
    floor = at + cut
  end
  -- a ref names a line of the engine function: by number, checked by hash,
  -- searched for by hash when the function moved
  local function refLine(r)
    local l = lines[r.r]
    if not (l and hashes[r.r] == r.h) then
      l = nil
      for k, h in ipairs(hashes) do
        if h == r.h then l = lines[k] break end
      end
    end
    if not l then return nil end
    return (r.i or "") .. trim(l)
  end
  -- every put resolved against the untouched function first: a ref names a
  -- line as it stands BEFORE any edit moves the others
  local puts = {}
  for i, e in ipairs(unit.edits or {}) do
    local put = {}
    for k, p in ipairs(e.put or {}) do
      if type(p) == "table" then
        local l = refLine(p)
        if not l then return nil, ("edit %d: engine line %d is gone"):format(i, p.r) end
        put[k] = l
      else
        put[k] = p
      end
    end
    puts[i] = put
  end
  local order = {}
  for i = 1, #placed do order[i] = i end
  table.sort(order, function(a, b) return placed[a] > placed[b] end)
  for _, i in ipairs(order) do
    local at, put = placed[i], puts[i]
    for _ = 1, cuts[i] do table.remove(lines, at) end
    for k = #put, 1, -1 do table.insert(lines, at, put[k]) end
  end
  return table.concat(lines, "\n")
end

-- ------------------------------------------------------------ the patch
-- spec = {
--   module   = "src.battle.BattleState",  file = "src/battle/BattleState.lua",
--   name     = "BattleState",       -- the file's own local for the module
--   scope    = { "Strings", ... },  -- the file's top-level locals
--   live     = { "counter", ... },  -- locals the engine reassigns (never cached)
--   patch    = { prelude = { lines }, units = { ... } }   -- lib/patches/*.lua
--   chunkname = "@mods/PkMultiplayer/...",
-- }
-- Returns a report { replaced, wrapped, injected, drift = { names },
-- missing = { names }, failed = { "name: why" } }.
function Transplant.apply(module, spec, log)
  local report = { replaced = 0, wrapped = 0, injected = 0, drift = {}, missing = {}, failed = {} }
  local refs = Transplant.scope(module, spec.file)
  local inScope, live = {}, {}
  for _, n in ipairs(spec.scope or {}) do inScope[n] = true end
  for _, n in ipairs(spec.live or {}) do live[n] = true end
  local units = spec.patch.units or {}

  local function pathOf(name)
    local path = {}
    for part in name:gmatch("[^.:]+") do path[#path + 1] = part end
    return path
  end

  -- the engine function a unit names, as the module holds it right now --
  -- looking through any copy an earlier load of this mod left there
  local function resolve(name, kind)
    if kind == "local" then
      local ref = refs[name]
      if not ref then return nil end
      local _, v = getupvalue(ref.fn, ref.idx)
      return original(v)
    end
    local path = pathOf(name)
    local cur
    if path[1] == spec.name then
      cur = module
    else
      local ref = refs[path[1]]
      if ref then
        local _, v = getupvalue(ref.fn, ref.idx)
        cur = v
      end
    end
    for i = 2, #path do
      if type(cur) ~= "table" then return nil end
      cur = rawget(cur, path[i])
    end
    return original(cur)
  end

  local function hashOf(f)
    local text = Transplant.sourceOf(f)
    return text and Transplant.fnv(text)
  end

  -- ANOTHER MOD MAY HAVE WRAPPED THE ENGINE FUNCTION FIRST (the bundled
  -- voxel mod wraps BattleState:draw and friends).  Then the field holds the
  -- wrapper, and the engine's function is an upvalue somewhere inside it:
  -- that upvalue is what gets the co-op version, and the wrapper stays where
  -- it is, still wrapping.  Prefers the function matching the base hash.
  local function findInner(f, base, kind)
    local best
    local seen = {}
    local function walk(g, depth)
      local i = 1
      while true do
        local name, v = getupvalue(g, i)
        if not name then break end
        if type(v) == "function" and not seen[v] then
          seen[v] = true
          local real = original(v)
          local info = getinfo(real, "S")
          if info and isFile(info.source, spec.file) then
            local hit = { holder = g, idx = i, fn = real }
            if base and hashOf(v) == base then return hit end
            best = best or (kind ~= "local" and hit) or nil
          elseif depth < 4 then
            local hit = walk(real, depth + 1)
            if hit then return hit end
          end
        end
        i = i + 1
      end
    end
    return walk(f, 0) or best
  end

  -- the engine's own function behind a name, looking through wrappers
  local function engineFn(name, kind, base)
    local f = resolve(name, kind)
    if type(f) ~= "function" then return f, nil end
    if kind ~= "local" then
      local info = getinfo(f, "S")
      if info and not isFile(info.source, spec.file) then
        local inner = findInner(f, base, kind)
        if inner then return inner.fn, { wrapper = f, inner = inner } end
      end
    end
    return f, nil
  end

  -- THE BUILT TEXTS ARE KEPT BETWEEN RUNS (1.20).  Placing every edit by
  -- its context lines is most of what loading the mod costs, and its result
  -- only depends on the engine file and on the patch.  With a cache
  -- (Transplant.cache, set by main.lua) a unit's text is taken from the last
  -- run when the engine file and the patch are byte for byte what they were
  -- and the function it edits still starts on the same line of that file --
  -- which a function another mod replaced does not.
  local key, kept, fresh = nil, nil, false
  if Transplant.cache and Transplant.hash and spec.patchKey then
    local text = readSource(spec.file)
    if text then
      key = Transplant.hash(text) .. "-" .. spec.patchKey
      local ok, hit = pcall(Transplant.cache.get, spec.module, key)
      kept = ok and type(hit) == "table" and hit or nil
    end
  end
  local keep = { units = {} }
  local function lineIn(fn)
    local info = type(fn) == "function" and getinfo(fn, "S")
    return info and isFile(info.source, spec.file) and info.linedefined or nil
  end

  -- build every unit's text from the engine as it is now
  local texts, wrapped, fwd = {}, {}, {}
  for unitIndex, u in ipairs(units) do
    local text, why
    if u.text then
      text = table.concat(u.text, "\n")
    else
      local srcName, srcKind = u.from or u.name, u.fromKind or u.kind
      local fn, w = engineFn(srcName, srcKind, u.base)
      if fn == nil then
        report.missing[#report.missing + 1] = srcName
        why = "not found"
      else
        local line = key and lineIn(fn)
        local old = line and kept and kept.units[unitIndex]
        if type(old) == "table" and old.line == line and type(old.text) == "string" then
          text = old.text
          if old.drift then report.drift[#report.drift + 1] = srcName end
          keep.units[unitIndex] = old
          report.cached = (report.cached or 0) + 1
        else
          local src = Transplant.sourceOf(fn)
          local drift = src and u.base and Transplant.fnv(src) ~= u.base or false
          if drift then report.drift[#report.drift + 1] = srcName end
          text, why = Transplant.build(src, u)
          if text and line then
            keep.units[unitIndex] = { line = line, text = text, drift = drift or nil }
            fresh = true
          end
        end
        if w and not u.from then
          w.unit = u
          wrapped[#wrapped + 1] = w
        end
      end
    end
    if text then
      if u.kind == "local" then
        fwd[#fwd + 1] = u.name
        text = text:gsub("^local%s+function", "function", 1)
      end
      texts[#texts + 1] = text
    else
      report.failed[#report.failed + 1] = u.name .. ": " .. tostring(why)
    end
  end

  -- a module whose edits did not all land is left as the engine has it: half
  -- a co-op battle would be worse than none
  if #report.failed > 0 then
    if log then
      log("NOT patched %s: %s", spec.module, table.concat(report.failed, "; "))
    end
    return report
  end

  if key and fresh then pcall(Transplant.cache.put, spec.module, key, keep) end

  local prelude = spec.patch.prelude or {}
  local source = {}
  if #fwd > 0 then source[#source + 1] = "local " .. table.concat(fwd, ", ") end
  for _, l in ipairs(prelude) do source[#source + 1] = l end
  for _, t in ipairs(texts) do source[#source + 1] = t end
  -- every local the chunk declared at its top level, handed back
  local declared = {}
  for _, n in ipairs(fwd) do declared[#declared + 1] = n end
  for _, l in ipairs(prelude) do
    local names = l:match("^local%s+([%a_][%w_%s,]-)%s*=") or l:match("^local%s+([%a_][%w_%s,]-)%s*$")
    if names and not l:match("^local%s+function") then
      for n in names:gmatch("[%a_][%w_]*") do declared[#declared + 1] = n end
    end
  end
  local ret = {}
  for _, n in ipairs(declared) do ret[#ret + 1] = n .. " = " .. n end
  source[#source + 1] = "return { locals = { " .. table.concat(ret, ", ") .. " } }"
  source = table.concat(source, "\n")
  report.source = source

  local cache = {}
  local env = setmetatable({}, {
    __index = function(_, k)
      if k == spec.name then return module end
      if inScope[k] then
        local c = cache[k]
        if c ~= nil then return c end
        local ref = refs[k]
        if ref then
          local _, v = getupvalue(ref.fn, ref.idx)
          if not live[k] and (type(v) == "table" or type(v) == "function") then
            cache[k] = v
          end
          return v
        end
      end
      return _G[k]
    end,
    __newindex = function(_, k, v)
      local ref = inScope[k] and refs[k]
      if ref then
        cache[k] = nil
        setUp(ref.fn, ref.idx, v)
      else
        _G[k] = v
      end
    end,
  })

  local chunk, err = loadstring(source, spec.chunkname or ("=" .. spec.module))
  if not chunk then error(("%s: the co-op version does not compile: %s"):format(spec.module, err), 0) end
  setfenv(chunk, env)

  -- every slot a unit writes, as it stands before the chunk runs
  local slots = {}
  for _, u in ipairs(units) do
    if u.kind ~= "local" then
      local path = pathOf(u.name)
      local owner = module
      if path[1] ~= spec.name then owner = env[path[1]] end
      for i = 2, #path - 1 do owner = type(owner) == "table" and rawget(owner, path[i]) or nil end
      if type(owner) == "table" then
        local key = path[#path]
        slots[#slots + 1] = { owner = owner, key = key, old = rawget(owner, key) }
      end
    end
  end

  local result = chunk()

  -- the wrapped ones: the wrapper goes back on the field, and calls the
  -- co-op version where it called the engine's
  for _, w in ipairs(wrapped) do
    local path = pathOf(w.unit.name)
    local owner = module
    if path[1] ~= spec.name then owner = env[path[1]] end
    for i = 2, #path - 1 do owner = owner and owner[path[i]] end
    local key = path[#path]
    local fresh = owner and rawget(owner, key)
    if type(fresh) == "function" and fresh ~= w.wrapper then
      rawset(owner, key, w.wrapper)          -- back to what it was: not a change
      setUp(w.inner.holder, w.inner.idx, fresh)
    end
  end
  report.wrapped = #wrapped
  for _, slot in ipairs(slots) do noteField(slot.owner, slot.key, slot.old) end

  -- locals the patch (re)defined: written into the engine's shared upvalue,
  -- and into any module field that was exporting the old value
  local locals = type(result) == "table" and result.locals or {}
  for name, value in pairs(locals) do
    local ref = refs[name]
    if ref then
      local _, old = getupvalue(ref.fn, ref.idx)
      if old ~= value then
        setUp(ref.fn, ref.idx, value)
        cache[name] = nil
        report.injected = report.injected + 1
        if old ~= nil then
          for k, v in pairs(module) do
            if v == old then
              rawset(module, k, value)
              noteField(module, k, old)
            end
          end
        end
      end
    end
  end
  report.replaced = #units
  report.env = env
  report.refs = refs
  if log then
    log("patched %s: %d functions (%d under another mod's wrapper, %d from the cache), %d locals%s",
        spec.module, report.replaced, report.wrapped, report.cached or 0, report.injected, #report.drift > 0 and
        (" -- engine changed since the patch was made, edits placed by context: "
         .. table.concat(report.drift, ", ")) or "")
  end
  return report
end

return Transplant
