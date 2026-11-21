-- Touch geometry and every mod screen's interactive rows, ROM-free.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("src.coop.CoopTouch")
local CM = require("src.coop.CoopManager")
require("src.coop.CoopLog").enabled = false
local total, failures = 0, 0
local function check(ok, message)
  total = total + 1
  if not ok then failures = failures + 1 end
  print((ok and "ok   " or "FAIL ") .. message)
end
local game = { coopTouchUsed = true, data = {}, save = { player = { name = "RED" }, party = {} },
  input = { wasPressed = function() return false end, isDown = function() return false end },
  renderer = { uiPresentation = { x = 137, y = 31, w = 480, h = 432, scaleX = 3, scaleY = 3 } },
  stack = { states = {} } }
function game.stack:top() return self.states[#self.states] end
function game.stack:push(s) self.states[#self.states + 1] = s end
function game.stack:pop() self.states[#self.states] = nil end
local function mount(s) game.stack.states = { s } return s end
local function target(s, id)
  for _, r in ipairs(T.targets(s)) do if r.id == id then return r end end
end
local function screenPoint(x, y)
  local p = game.renderer.uiPresentation
  return p.x + x * p.scaleX, p.y + y * p.scaleY
end
local function tapAt(s, x, y, id)
  local px, py = screenPoint(x, y)
  s:touchpressed(id or 1, px, py)
  s:touchreleased(id or 1, px, py)
end
local function tap(s, id)
  local r = assert(target(s, id), "missing " .. id)
  tapAt(s, r.x + r.w / 2, r.y + r.h / 2)
end
local function geometry(s, label)
  local list = T.targets(s)
  check(#list > 0, label .. " has targets")
  for n, r in ipairs(list) do
    for j = n + 1, #list do
      local other = list[j]
      check(math.min(r.x + r.w, other.x + other.w) <= math.max(r.x, other.x)
        or math.min(r.y + r.h, other.y + other.h) <= math.max(r.y, other.y),
        label .. " targets do not overlap: " .. r.id .. "/" .. other.id)
    end
    check(r.x >= 0 and r.y >= 0 and r.x + r.w <= 160 and r.y + r.h <= 144,
      label .. " " .. r.id .. " inside 160x144")
    check(T.hit(r, r.x, r.y) and not T.hit(r, r.x + r.w, r.y + r.h), label .. " " .. r.id .. " half-open edges")
  end
end
for _, p in ipairs({
  { x = 137, y = 31, scaleX = 3, scaleY = 3 },
  { x = 52.5, y = 98, scaleX = 1.25, scaleY = 2.5 },
  { x = 0, y = 0, scaleX = 0.75, scaleY = 0.75 },
}) do
  game.renderer.uiPresentation = p
  local x, y = T.toGame(game, p.x + 80 * p.scaleX, p.y + 72 * p.scaleY)
  check(x == 80 and y == 72, "UI presentation scale and letterbox inverse")
  check(T.toGame(game, p.x - 0.01, p.y) == nil, "left letterbox rejected")
  check(T.toGame(game, p.x, p.y + 144 * p.scaleY) == nil, "bottom edge rejected")
end
game.renderer.uiPresentation = { x = 137, y = 31, scaleX = 3, scaleY = 3 }
local Menu = require("src.coop.CoopMenu")
CM.connected = false
local m = mount(Menu.new(game))
for _, stage in ipairs({"main", "diag", "hosting", "hubHost", "hubJoin", "joinPick", "codeEntry", "portEntry", "addrEntry", "joining"}) do
  m.stage, m.portEdit, m.portPos, m.code = stage, {0,7,7,7,7}, 5, ""
  geometry(m, "menu " .. stage)
end
m.stage = "main"
local ran = {}
m.offlineRows = function()
  local rows = {}
  for n = 1, 25 do rows[n] = {label = "ROW", run = function() ran[n] = (ran[n] or 0) + 1 end} end
  return rows
end
tap(m, "row:3")
check(m.index == 3 and ran[3] == 1, "tap row selects and confirms once")
local px, py = screenPoint(70, 100)
m:touchpressed(1, px, py)
m:touchmoved(1, px, py - 90)
m:touchreleased(1, px, py - 90)
check(m.index == 6 and ran[6] == nil, "drag scrolls and never confirms")
local r = target(m, "row:4")
px, py = screenPoint(r.x + 1, r.y + 1)
m:touchpressed(1, px, py) m:touchpressed(2, px, py)
m:touchreleased(2, px, py) m:touchreleased(1, px, py)
check(ran[4] == 1, "second finger cannot double confirm")
-- A view changing under a held finger must not execute a stale target.
m:touchpressed(1, px, py) m.stage = "diag" m:touchreleased(1, px, py)
check(ran[4] == 1, "stale gesture discarded after stage change")
m.stage = "main"
m:touchpressed(1, 0, 0) m:touchreleased(1, 0, 0)
check(game.stack:top() == nil, "outside letterbox cancels")
mount(m)
m.stage, m.portEdit, m.portPos = "portEntry", {0,0,0,0,0}, 1
tap(m, "ok") check(m.errorMsg == "PORT 1024 TO 65534", "invalid port rejected")
m.portEdit = {0,7,9,4,0}
tap(m, "ok") check(m.port == 7940 and m.stage == "main", "valid touch port accepted")
m.stage = "addrEntry"
tap(m, "digit:5") local was = m.addr[5]
tap(m, "up") check(m.addrPos == 5 and m.addr[5] == (was + 1) % 10, "IP digit is selected and turned")
m.stage, m.code = "codeEntry", ""
tap(m, "key:A") tap(m, "key:9") tap(m, "erase")
check(m.code == "A", "code keyboard types and erases")
-- Long Link Hub invite codes (up to 24 chars) can be typed and drawn cleanly
for ch in ("BCD-EFGH-JKLM-NPQR-STUV"):gmatch(".") do tap(m, "key:" .. ch) end
check(#m.code == 24, "code keyboard accepts full 24-char Link Hub code")
local okDraw = pcall(m.draw, m)
check(okDraw, "long Link Hub code renders cleanly on touch keyboard")
m.code = "A"
tap(m, "ok") check(m.errorMsg == "WRONG CODE", "invalid code rejected")
tap(m, "back") check(m.stage == "joinPick", "keyboard back returns to address list")
-- Every connected menu page uses the same row geometry.
CM.connected, CM.partner = true, {name = "BLUE", id = "blue", caps = CM.CAPS}
CM.net = { rttMs = 0, isLinked = function() return true end }
local live = mount(Menu.new(game))
for _, page in ipairs({"main", "partner", "rules", "vs", "minigames", "record", "replays"}) do
  live.page, live.index, live.scroll = page, 1, 1
  geometry(live, "connected " .. page)
end
CM.connected, CM.net = false, nil
-- Name and lobby screens.
local Lobby = require("src.coop.CoopNewGame")
local lobby = mount(Lobby.new(game, function() end, "new"))
for _, stage in ipairs({"name", "role", "ipEntry", "codeEntry", "connecting", "confirm"}) do
  lobby.stage, lobby.code = stage, ""
  geometry(lobby, "lobby " .. stage)
end
lobby.stage, lobby.nameEdit = "name", {buf = "", pos = 1}
tap(lobby, "key:R") tap(lobby, "key:E") tap(lobby, "key:D")
check(lobby.nameEdit.buf == "RED", "name typed by touch")
tap(lobby, "ok") check(lobby.stage == "role" and lobby.name == "RED", "name confirmed by touch")
local Select = require("src.coop.CoopBattleSelect")
local party = {}
for n = 1, 6 do party[n] = {hp = n == 6 and 0 or 20, species = "PIKACHU"} end
local chosen
local select = mount(Select.new(game, party, function(p) chosen = p end))
geometry(select, "team")
tap(select, "mon:2") check(select.cursor == 2 and not select:isSelected(2), "team tap toggles selected mon")
tap(select, "mon:6") check(select.message == "POKéMON HAS NO HP!", "fainted mon rejected")
tap(select, "confirm") check(chosen and #chosen == 2, "team confirmed by touch")
local accepted, declined = 0, 0
local Invite = require("src.coop.CoopBattleInviteModal")
local invite = mount(Invite.new(game, "BLUE", "BROCK", function() accepted = accepted + 1 end, function() declined = declined + 1 end))
geometry(invite, "invite")
tap(invite, "answer:1") check(accepted == 0, "unarmed invite cannot accept accidental touch")
invite:update(1)
tap(invite, "answer:1") check(accepted == 1 and game.stack:top() == nil, "armed invite touch accepts once")
mount(invite) invite.armed = true
tap(invite, "answer:2") check(declined == 1, "decline row cancels")
local Emotes = require("src.coop.CoopEmotes")
local picked
local picker = mount(Emotes.newPicker(game, function(id) picked = id end))
picker.timer = 1
geometry(picker, "emotes")
check(target(picker, "back").y >= 56,"emote BACK stays below all bubble-number labels")
for n = 1, #Emotes.LIST do check(target(picker, "emote:" .. n) ~= nil, "emote has target " .. n) end
tap(picker, "emote:3") check(picked == Emotes.LIST[3].id, "emote tap selects and sends")
local canceled = 0
local wait = mount(require("src.coop.CoopWaitModal").new(game, "BLUE", function() canceled = canceled + 1 end))
wait.timer = 1 geometry(wait, "wait") tap(wait, "back") check(canceled == 1, "wait canceled by touch")
-- Chat keyboard also works when it is an overlay outside the stack.
local realChat, sent = CM.sendChat, nil
CM.sendChat = function(line) sent = line end
local chat = mount(require("src.coop.CoopChatBox").new(game))
geometry(chat, "chat")
tap(chat, "key:T") tap(chat, "key:O") tap(chat, "space") tap(chat, "key:R")
check(chat.text == "TO R", "touch typing preserves the first T and spaces")
tap(chat, "ok") check(sent == "TO R" and chat.text == "", "chat touch sends and clears input")
tap(chat, "back") check(game.stack:top() == nil, "chat touch back closes")
CM.sendChat = realChat
-- Generic mod menus serve catch ownership, tower, contest and battle mode.
local pick = nil
local menu = mount(require("src.coop.CoopI18n").menu().new(game, {
 {label = "I KEEP IT", onSelect = function() pick = 1 end},
 {label = "FOR BLUE", onSelect = function() pick = 2 end},
 {label = "LET FATE DECIDE", onSelect = function() pick = 3 end},
}, {tx = 2, ty = 5, tw = 18, th = 8}))
geometry(menu, "keeper/tower/contest")
menu.coopKeepMenu, menu.cancelable = true, false
tapAt(menu, 0, 0) check(pick == 3, "keeper outside touch resolves with fair coin")
for _, kind in ipairs({"aim", "match", "link", "watch", "souls", "wait"}) do
  local s = {game = game, touchKind = kind, stage = "battleOptions"}
  geometry(s, kind)
end
-- Independent row positions pin geometry to the actual draw coordinates.
local fixture = mount(Select.new(game, party))
check(target(fixture, "mon:6").y == 82 and target(fixture, "confirm").y == 94,
  "six-party geometry matches the renderer's last row and confirm line")
check(target(invite, "answer:1").y == 72 and target(invite, "answer:2").y == 88,
  "invite rows match the rendered JOIN and DECLINE lines")
local m2 = mount(Menu.new(game))
m2.stage = "joinPick"
check(target(m2, "row:1").y == 66, "join list hit row matches printed first row")
-- Pending gestures belong to the original screen even when the stack moves.
local replacement = {game = game}
local rowRect = target(m2, "row:1")
local sx, sy = screenPoint(rowRect.x + 2, rowRect.y + 2)
m2:touchpressed(1, sx, sy) game.stack:push(replacement) m2:touchreleased(1, sx, sy)
check(m2.stage == "joinPick", "release over a replacement screen does not act")
-- The engine's start/title menus become touchable only when the mod adds
-- its own row; the title's CONTINUE / NEW GAME choice stays touchable too.
local H = rawget(_G, "__PKMULTIPLAYER").hooks
local EngineMenu = require("src.ui.Menu")
local S = require("src.core.Strings")
mount({})
local startItems = H.startMenuItems(function(_, items) return items end,game,{{label=S("SAVE")}})
local startMenu = mount(EngineMenu.new(game,startItems,{tx=4,ty=2,tw=16,th=6}))
check(startMenu.touchKind == "list","start menu with co-op row gets touch routing")
geometry(startMenu,"start co-op entry")
tap(startMenu,"row:2")
check(game.stack:top().touchKind == "menu","touch start-menu row opens co-op menu")
mount({onNewGame=function() end,onContinue=function() end})
local titleItems = H.titleMenuItems(function(_, items) return items end,game,{
  {label=S("CONTINUE")},{label=S("NEW GAME")},
})
local titleMenu = mount(EngineMenu.new(game,titleItems,{tx=4,ty=2,tw=16,th=8}))
geometry(titleMenu,"title co-op entry") tap(titleMenu,"row:3")
local titleChoice = game.stack:top()
check(titleChoice.coopTitleChoice and titleChoice.touchKind == "list","title choice is touchable")
geometry(titleChoice,"continue/new choice") tap(titleChoice,"row:2")
check(game.stack:top().touchKind == "lobby","touch NEW GAME opens name step")
-- Horizontal slop follows scaleX even on a non-square DPI presentation.
game.renderer.uiPresentation = {x=0,y=0,scaleX=3,scaleY=1}
mount(m2) m2.stage = "diag"
m2:touchpressed(1,60,60) m2:touchmoved(1,70,60)
check(not m2.touchGesture.dragged,"sub-threshold horizontal movement uses scaleX")
game.coopTouchOwners = {[1] = m2}
T.reset(game)
check(not m2.touchGesture and not game.coopTouchOwners,"focus reset releases cancelled gestures")
local real = game.input
local broken = { game = game, update = function() error("touch fixture error") end }
local ok = pcall(T.action, broken, "a")
check(not ok and game.input == real, "action restores input even on error")
check(not game.input.pressQueue, "touch actions leave no queued engine keys")
print(("%d/%d checks passed (co-op touch)"):format(total - failures, total))
if failures > 0 then os.exit(1) end
