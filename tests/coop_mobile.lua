-- CO-OP ON A PHONE.
--
-- A phone has no shell to ask for the ZeroTier address and no T key to open
-- the chat.  This pins the ways round both: the routing probe, the CHAT row
-- in the co-op menu, SELECT in a co-op double, and the on-screen keyboard
-- (raised for the chat, lowered after it on a phone only).
--
--   luajit <mod>/tests/run.lua <mod>/tests/coop_mobile.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local fails, total = 0, 0
local function check(ok, msg)
  total = total + 1
  print((ok and "ok   " or "FAIL ") .. msg)
  if not ok then fails = fails + 1 end
end

local CoopNet = require("src.coop.CoopNet")
local CoopManager = require("src.coop.CoopManager")
require("src.coop.CoopLog").enabled = false

-- ------------------------------------------------------------ ZeroTier
-- a phone on Wi-Fi 192.168.1.50 with the ZeroTier VPN routing 10.147.17.0/24
local function phone(target)
  if target:find("^10%.147%.17%.") then return "10.147.17.122" end
  return "192.168.1.50"
end
check(CoopNet.probeZeroTierIP(phone) == "10.147.17.122", "the ZeroTier address is found by its route")
check(CoopNet.probeZeroTierIP(function() return "192.168.1.50" end) == nil,
      "no ZeroTier: nothing is found")
check(CoopNet.probeZeroTierIP(function() return "192.168.192.20" end) == nil,
      "a home network on a ZeroTier-looking range is not mistaken for ZeroTier")
local function wide(target)
  if target:find("^10%.244%.") then return "10.244.3.9" end
  return "192.168.1.50"
end
check(CoopNet.probeZeroTierIP(wide) == "10.244.3.9", "a /16 pool is probed too")

-- ------------------------------------------------------------ keyboard
local keyboard = {}
love.keyboard = love.keyboard or {}
love.keyboard.setTextInput = function(on) keyboard[#keyboard + 1] = on end
love.system = love.system or {}
local osName = "Linux"
love.system.getOS = function() return osName end

local pushed = {}
local input = { pressed = {} }
function input:wasPressed(b) return self.pressed[b] == true end
local game = { data = {}, input = input,
               stack = { states = {} } }
function game.stack:push(s) self.states[#self.states + 1] = s; pushed[#pushed + 1] = s end
function game.stack:pop() self.states[#self.states] = nil end
function game.stack:top() return self.states[#self.states] end

local CoopChatBox = require("src.coop.CoopChatBox")
keyboard = {}
local box = CoopChatBox.new(game)
game.stack:push(box)
check(keyboard[1] == true, "opening the chat raises the keyboard")
box:close()
check(#keyboard == 1, "a desktop keeps text input on after the chat")

osName = "iOS"
keyboard = {}
box = CoopChatBox.new(game)
game.stack:push(box)
input.pressed = { a = true }
box:update(0.2)
check(keyboard[2] == true, "on a phone, A brings back a keyboard swiped away")
input.pressed = {}
box:close()
check(keyboard[#keyboard] == false, "a phone lowers the keyboard after the chat")

-- ------------------------------------------------------------ CHAT row
local CoopMenu = require("src.coop.CoopMenu")
local menu = CoopMenu.new(game)
local rows = menu:connectedRows(nil)
check(rows[1] and rows[1].label:find("^CHAT") ~= nil, "the linked co-op menu starts with CHAT")
local opened = 0
local realOpen = CoopManager.openChat
CoopManager.openChat = function() opened = opened + 1 end
game.stack:push(menu)
rows[1].run()
check(opened == 1, "the CHAT row opens the chat")

-- ------------------------------------------------------- SELECT in battle
local BattleState = require("src.battle.BattleState")
local ran = 0
local fake = setmetatable({ coopDouble = true, phase = "menu", game = game }, {
  __index = function(_, k)
    if k == "updateQueue" or k == "updateFx" then return function() ran = ran + 1 end end
    return nil
  end,
})
CoopManager.connected = true
opened = 0
input.pressed = { select = true }
local ok = pcall(BattleState.update, fake, 1 / 60)
check(ok and opened == 1, "SELECT on a co-op double's action menu opens the chat")
fake.phase = "moveSelect"
opened = 0
pcall(BattleState.update, fake, 1 / 60)
check(opened == 0, "SELECT in the move list still reorders moves (no chat)")
fake.phase = "menu"
CoopManager.connected = false
opened = 0
pcall(BattleState.update, fake, 1 / 60)
check(opened == 0, "with no partner linked SELECT does nothing new")
CoopManager.openChat = realOpen

-- ------------------------------------------------------------ nightly.3
-- no key hints on a phone's co-op menu, and the on-screen R talks
do
  osName = "Android"
  CoopManager.connected = true
  local CoopMenu = require("src.coop.CoopMenu")
  local m = CoopMenu.new({ stack = { push = function() end, pop = function() end }, data = {} })
  local okR, rows = pcall(m.connectedRows, m, nil)
  local labels = {}
  for _, r in ipairs(okR and rows or {}) do if type(r) == "table" then labels[#labels + 1] = tostring(r.label) end end
  local text = table.concat(labels, " | ")
  check(okR and not text:find("KEY", 1, true) and not text:find("(R)", 1, true),
        "a phone's co-op menu names no keys (" .. text:sub(1, 60) .. ")")
  local CoopVoice = require("src.coop.CoopVoice")
  local TC = { held = {} }
  package.loaded["src.core.TouchControls"] = TC
  love.keyboard.isDown = function() return false end
  check(not CoopVoice.pttHeld({ stack = { top = function() return nil end } }), "nothing held: not talking")
  TC.held.r = 1
  check(CoopVoice.pttHeld({ stack = { top = function() return nil end } }), "the on-screen R held: talking")
  package.loaded["src.core.TouchControls"] = nil
  CoopManager.connected = false
  osName = "Linux"
end

print(("%d/%d checks passed  (co-op on a phone)"):format(total - fails, total))
if fails > 0 then os.exit(1) end
