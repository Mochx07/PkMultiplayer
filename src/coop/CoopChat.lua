-- src/coop/CoopChat.lua (split out of CoopManager.lua for 1.20)
-- install(CoopManager, CMI) runs this code where it used to sit in
-- CoopManager.lua: CoopManager.* names are the manager's own, and CMI
-- carries the manager's file-level locals it reads (and the ones it
-- hands on to the code after it).
--
-- chat & interaction

local M = {}

function M.install(CoopManager, CMI)
local CoopManager = CMI.CoopManager
local Strings = CMI.Strings
local getGame = CMI.getGame
local now = CMI.now
local playSound = CMI.playSound
local stackTop = CMI.stackTop


-- LIVE CHAT.  The partner sees what you type AS you type it: every change in
-- the chat box goes out on the fast channel (unreliable, sequenced, never
-- stuck behind a battle turn), at most every LIVE_EVERY seconds, and when
-- the typing pauses the latest text is repeated on the reliable channel in
-- case the last fast packet was lost.  Every live packet carries a counter
-- so a late one never resurrects text that was already sent or cancelled.
--
-- Messages are kept in a short log the chat box shows, so nothing that
-- arrives while you are typing is missed, and a message's time on screen
-- only runs while it is actually visible (not behind a dialogue box).

-- in LETTERS: the chat box takes 70 (src/coop/CoopChatBox.lua); a message
-- from an older version is cut here, never in the middle of a letter
CoopManager.CHAT_MAX = 76
function CoopManager.clipLetters(text, n)
  local count = 0
  for pos in tostring(text):gmatch("()[^\128-\191]") do
    count = count + 1
    if count > n then return text:sub(1, pos - 1) end
  end
  return text
end
CoopManager.CHAT_LOG_MAX = 8
CoopManager.LIVE_EVERY = 0.05
CoopManager.LIVE_SETTLE = 0.35
CoopManager.TYPING_STALE = 5
CoopManager.chatLog = {}
-- name -> fn(sender, text, own): every line the chat shows (visitors hear it)
CoopManager.chatListeners = {}
-- set while this game VISITS someone else's (src/coop/CoopVisit.lua): the
-- chat goes there instead of to a co-op partner
CoopManager.chatRoute = nil
CoopManager.partnerTyping = nil
CoopManager.partnerLiveN = 0
CoopManager.liveOut = { n = 0, at = -1 }
CoopManager.chatShown = false

local function chatDuration(text) return math.min(9, 3 + #text * 0.09) end

-- is a co-op double the screen on top?  (chat works there too)
local function coopBattleOnTop(game)
  local top = stackTop(game)
  return top ~= nil and top.coopDouble == true and top.chooseAction ~= nil
end
CoopManager.coopBattleOnTop = coopBattleOnTop

function CoopManager.openChat(game, ow)
  game = game or getGame(ow)
  if not game or not game.stack then return end
  if not (CoopManager.connected or CoopManager.chatRoute) then return end

  local top = stackTop(game)
  if top and (top.isChatBox or top.isTextBox or (top.lines ~= nil and top.page ~= nil)) then
    return
  end
  if CoopManager.chatOverlay then return end
  if coopBattleOnTop(game) then
    -- inside the battle, which keeps running (src/coop/CoopChatBox.lua)
    CoopManager.chatOverlay = require("src.coop.CoopChatBox").new(game, { overlay = true })
    CoopManager.sendChatLive("")
    return
  end
  if not coopBattleOnTop(game) then
    local curOw = ow or game.overworld
    if curOw and (curOw.engaging or curOw.transitioning or curOw.inBattle) then
      return
    end
  end
  local CoopChatBox = require("src.coop.CoopChatBox")
  game.stack:push(CoopChatBox.new(game))
  CoopManager.sendChatLive("")
end

local function sendLiveNow(reliable)
  local live = CoopManager.liveOut
  local net = CoopManager.net
  if not (CoopManager.connected and net and live.text ~= nil) then return end
  live.n = live.n + 1
  live.at = now()
  live.sentText = live.text
  live.settled = reliable or false
  net:send({ type = "coop_chat_live", n = live.n, text = live.text }, (not reliable) and { fast = true } or nil)
end

-- the chat box reports its text on every change; nil + stop = box closed
function CoopManager.sendChatLive(text, stop)
  local live = CoopManager.liveOut
  if stop then
    live.text, live.sentText, live.settled = nil, nil, true
    if CoopManager.connected and CoopManager.net then
      live.n = live.n + 1
      CoopManager.net:send({ type = "coop_chat_live", n = live.n, stop = true })
    end
    return
  end
  text = tostring(text or ""):sub(1, CoopManager.CHAT_MAX)
  if text == live.sentText and live.text ~= nil then return end
  live.text = text
  if now() - (live.at or -1) >= CoopManager.LIVE_EVERY then sendLiveNow(false) end
end

-- once a frame: a change held back by the rate limit goes out, and a pause
-- in the typing is confirmed on the reliable channel
local function tickLive()
  local live = CoopManager.liveOut
  if live.text == nil then return end
  local t = now()
  if live.text ~= live.sentText then
    if t - (live.at or -1) >= CoopManager.LIVE_EVERY then sendLiveNow(false) end
  elseif not live.settled and t - (live.at or 0) >= CoopManager.LIVE_SETTLE then
    sendLiveNow(true)
  end
end

function CoopManager.onChatLive(msg)
  local n = tonumber(msg.n) or 0
  if n <= (CoopManager.partnerLiveN or 0) then return end
  CoopManager.partnerLiveN = n
  if msg.stop then
    CoopManager.partnerTyping = nil
    return
  end
  CoopManager.partnerTyping = { text = tostring(msg.text or ""):sub(1, CoopManager.CHAT_MAX), at = now() }
end

function CoopManager.sendChat(text)
  text = text and text:match("^%s*(.-)%s*$") or ""
  local live = CoopManager.liveOut
  live.text, live.sentText, live.settled = nil, nil, true
  if text == "" then
    CoopManager.sendChatLive(nil, true)
    return
  end
  text = CoopManager.clipLetters(text, CoopManager.CHAT_MAX)

  local game = getGame()
  local sender = CoopManager.getLocalPlayerName(game) or "ME"
  if not CoopManager.connected and CoopManager.chatRoute then
    pcall(CoopManager.chatRoute, sender, text)
  end
  if CoopManager.connected and CoopManager.net then
    -- the counter goes with it: the partner drops the typing line for good
    live.n = live.n + 1
    CoopManager.net:send({ type = "coop_chat", sender = sender, text = text, n = live.n })
  end
  CoopManager.onChatReceived(sender, text, true)
end

function CoopManager.onChatReceived(sender, text, own, n)
  if type(text) ~= "string" or text == "" then return end
  sender = require("src.coop.CoopI18n").truncate(string.upper(tostring(sender or "PARTNER")), 8)
  text = CoopManager.clipLetters(text, CoopManager.CHAT_MAX)
  if not own then
    CoopManager.partnerTyping = nil
    n = tonumber(n)
    if n and n > (CoopManager.partnerLiveN or 0) then CoopManager.partnerLiveN = n end
  end
  local log = CoopManager.chatLog
  log[#log + 1] = { sender = sender, text = text, own = own and true or false }
  while #log > CoopManager.CHAT_LOG_MAX do table.remove(log, 1) end
  CoopManager.activeChatMessage = {
    sender = sender,
    text = text,
    timer = chatDuration(text),
    own = own and true or false,
  }
  if not own then playSound(getGame(), "Menu") end
  for _, fn in pairs(CoopManager.chatListeners) do pcall(fn, sender, text, own) end
end

function CoopManager.interact(game, ow)
  local partner = CoopManager.partner
  local pName = partner.name or "PARTNER"
  local Menu = require("src.coop.CoopI18n").menu()
  local items = {
    { label = Strings("HIGH FIVE!"), onSelect = function()
      CoopManager.sendEmote("highfive")
      CoopManager.showStatus("High five with " .. pName .. "!", 2.5)
    end },
    { label = Strings("USE ITEM"), onSelect = function()
      CoopManager.useItemOnPartner(game, ow)
    end },
    { label = Strings("CHAT"), onSelect = function()
      CoopManager.openChat(game, ow)
    end },
    { label = Strings("TRADE"), onSelect = function()
      require("src.coop.CoopLink").invite(game, "trade")
    end },
    { label = Strings("BATTLE"), onSelect = function()
      require("src.coop.CoopLink").invite(game, "battle")
    end },
  }
  game.stack:push(Menu.new(game, items, {
    tx = 2,
    ty = 4,
    tw = 16,
    cancelable = true,
  }))
end

CMI.coopBattleOnTop = coopBattleOnTop
CMI.tickLive = tickLive
end

return M
