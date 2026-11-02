-- THE RELEASE ZIP CARRIES THE MOD, NOT ITS WORKSHOP.
--
-- tools/pack.py ships every tracked file not listed in .modkitignore.  A
-- development file added without its .modkitignore line goes out to players:
-- 1.6.16's zip carried tools/anim_viewer_app/main.lua, a second LOVE
-- main.lua inside the mod.  Every tracked file under tests/ and tools/ must
-- be ignored, and the only main.lua shipped is the mod's own entry.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local here = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]+$") or "."
local function lines(cmd)
  local out, p = {}, io.popen(cmd)
  if p then
    for l in p:lines() do out[#out + 1] = l end
    p:close()
  end
  return out
end

local ignored = {}
local f = io.open(here .. "/.modkitignore", "r")
T.check(f ~= nil, ".modkitignore is there")
if f then
  for l in f:lines() do
    l = l:match("^%s*(.-)%s*$")
    if l ~= "" and l:sub(1, 1) ~= "#" then ignored[l] = true end
  end
  f:close()
end

local tracked = lines("git -C '" .. here .. "' ls-files")
T.check(#tracked > 0, "git lists the tracked files")
local shipped, leaks, mains = 0, {}, {}
for _, rel in ipairs(tracked) do
  local base = rel:match("[^/]+$")
  if not ignored[rel] and base:sub(1, 1) ~= "." then
    shipped = shipped + 1
    if rel:find("^tests/") or rel:find("^tools/") then leaks[#leaks + 1] = rel end
    if base == "main.lua" then mains[#mains + 1] = rel end
  end
end
T.check(#leaks == 0, "no test or tool ships in the zip" ..
        (#leaks > 0 and (": " .. table.concat(leaks, ", ")) or ""))
T.check(#mains == 1 and mains[1] == "main.lua", "the only main.lua shipped is the mod's entry (" ..
        table.concat(mains, ", ") .. ")")
T.finish("release zip contents (" .. shipped .. " files)")
