-- A MOD THAT WRAPPED AN ENGINE FUNCTION FIRST KEEPS ITS WRAPPER.
--
-- The co-op copy of the function goes INSIDE the other mod's wrapper (in
-- place of the engine's original), and the wrapper stays on the module.
--
--   PKM_EAGER=1 PKM_PRE=<mod>/tests/foreign_wrapper_pre.lua \
--     luajit <mod>/tests/run.lua <mod>/tests/foreign_wrapper.lua
local BattleState = require("src.battle.BattleState")
local STATE = rawget(_G, "__PKMULTIPLAYER")
local W = assert(_G.__OTHER_MOD_WRAPPERS, "run with PKM_PRE=tests/foreign_wrapper_pre.lua")
local fails = 0
local function check(ok, msg)
  print((ok and "ok   " or "FAIL ") .. msg)
  if not ok then fails = fails + 1 end
end

local report = STATE.reports["src.battle.BattleState"]
-- (at least: since 0.8.57 the engine wraps a few of its own BattleState
-- methods from another file, and the co-op copies go in under those too)
check(report and report.wrapped >= 2, "the two units went in under the other mod's wrappers")
check(report and #report.drift == 0, "no false 'changed upstream'")
for name, wrapper in pairs(W) do
  check(BattleState[name] == wrapper, name .. ": the other mod's wrapper is still on the module")
  local inner
  for i = 1, 10 do
    local n, v = debug.getupvalue(wrapper, i)
    if n and n:match("^inner") then inner = v end
  end
  local src = debug.getinfo(inner, "S").source
  check(src:find("lib/patches/BattleState.lua", 1, true) ~= nil,
        name .. ": the wrapper now calls the co-op copy (" .. src .. ")")
end
print(("%d failures"):format(fails))
if fails > 0 then os.exit(1) end
