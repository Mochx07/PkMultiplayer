-- CO-OP CHAT: TYPING AND SENDING.
--
--   * only what is sent reaches the partner; while the box holds a letter
--     they see "is typing..." (fast channel, confirmed on the reliable one,
--     kept alive), and an empty box says nothing (nightly.2);
--   * a late typing packet never brings back a line that was already sent or
--     cancelled;
--   * ENTER sends and keeps the box open for the reply; ESC tells the
--     partner you stopped typing;
--   * the box shows the conversation, and a message's time on screen only
--     runs while it is visible.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local SaveData = require("src.core.SaveData")
local CoopManager = require("src.coop.CoopManager")
local CoopChatBox = require("src.coop.CoopChatBox")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.net = { send = function(_, m, opts) sent[#sent + 1] = { msg = m, fast = opts and opts.fast or false } return true end,
                    isLinked = function() return true end, flush = function() end,
                    update = function() end, poll = function() return {} end }
CoopManager.connected = true
CoopManager.partner.name = "MOCHI"

local function lives()
  local out = {}
  for _, s in ipairs(sent) do if s.msg.type == "coop_chat_live" then out[#out + 1] = s end end
  return out
end

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local save = SaveData.newGame()
save.player.name = "ME"
local game = { data = Data, save = save, stack = newStack(),
               input = { wasPressed = function() return false end, isDown = function() return false end } }
package.loaded["src.core.Game"] = game

-- ---------------------------------------------------------------------
-- sending: "typing", never the letters (nightly.2)
-- ---------------------------------------------------------------------

do
  sent = {}
  CoopManager.liveOut = { n = 0, at = -1 }
  CoopManager.openChat(game, nil)
  local box = game.stack:top()
  T.check(box and box.isChatBox, "T opens the chat box")
  T.check(#lives() == 0, "opening the box tells the partner nothing (no letter yet)")
  box.swallowOpenKey = false
  box:onTextInput("h")
  local l = lives()
  T.check(#l == 1 and l[1].msg.text == "" and l[1].fast, "the first letter: 'typing' goes out, without the letter")
  box:onTextInput("o"); box:onTextInput("la")
  T.check(#lives() == 1, "more letters send nothing more")
  for _, x in ipairs(lives()) do
    T.check(x.msg.text == "" or x.msg.stop, "no packet carries what is being typed")
  end
  -- the start is confirmed reliably, then kept alive
  CoopManager.LIVE_SETTLE = 0
  CoopManager.update(nil, 1 / 60)
  l = lives()
  T.check(#l == 2 and not l[2].fast and l[2].msg.text == "", "it is confirmed on the reliable channel")
  CoopManager.liveOut.at = -100
  CoopManager.update(nil, 1 / 60)
  T.check(#lives() == 3, "...and repeated while the typing goes on (under the partner's " .. CoopManager.TYPING_STALE .. " s)")
  -- erasing every letter: the partner is told you stopped
  sent = {}
  for _ = 1, 4 do box:onKeyPressed("backspace") end
  l = lives()
  T.check(#l == 1 and l[1].msg.stop, "an emptied box stops the 'typing'")
  box:onTextInput("hola!")
  T.check(#lives() == 2 and lives()[2].msg.text == "", "a letter again: 'typing' again")

  -- ENTER: the message goes, the box stays for the reply
  sent = {}
  box:onKeyPressed("return")
  local chat
  for _, s in ipairs(sent) do if s.msg.type == "coop_chat" then chat = s.msg end end
  T.check(chat and chat.text == "hola!" and chat.n, "ENTER sends the message with its counter")
  T.check(game.stack:top() == box and box.text == "", "...and the box stays open, empty, for the reply")
  T.check(CoopManager.chatLog[#CoopManager.chatLog].text == "hola!", "your message is in the log")

  -- ESC on an empty box: nothing was being typed, nothing to stop
  sent = {}
  box:onTextInput("x")
  box:onKeyPressed("escape")
  l = lives()
  T.check(#l == 2 and l[2].msg.stop, "ESC with letters in the box tells the partner you stopped typing")
  T.check(game.stack:top() ~= box, "ESC closes the box")
end

-- ---------------------------------------------------------------------
-- receiving
-- ---------------------------------------------------------------------

do
  CoopManager.partnerLiveN = 0
  CoopManager.partnerTyping = nil
  CoopManager.onChatLive({ n = 1, text = "" })
  local name, text, typing = CoopManager.chatBubble()
  T.check(typing and name == "MOCHI" and text:find("typing"), "the partner typing reads 'is typing...'")
  -- an older partner still sends its letters: they are not shown
  CoopManager.onChatLive({ n = 2, text = "que" })
  CoopManager.onChatLive({ n = 3, text = "que tal" })
  T.check(CoopManager.partnerTyping and CoopManager.partnerTyping.text == "", "an older partner's letters are not shown")
  local lines = CoopManager.chatLines(18, 4)
  T.check(not lines[#lines]:find("que", 1, true) and lines[#lines]:find("...", 1, true),
          "the chat box shows only that they are typing")
  _, text = CoopManager.chatBubble()
  T.check(text:find("typing") and not text:find("que"), "...and so does the bubble")

  CoopManager.onChatReceived("MOCHI", "que tal?", false, 4)
  T.check(CoopManager.partnerTyping == nil, "the sent message replaces the typing line")
  CoopManager.onChatLive({ n = 3, text = "" })
  T.check(CoopManager.partnerTyping == nil, "...and a typing packet that arrives late cannot bring it back")
  T.check(CoopManager.chatLog[#CoopManager.chatLog].text == "que tal?", "the message is in the log")

  CoopManager.onChatLive({ n = 5, text = "" })
  CoopManager.onChatLive({ n = 6, stop = true })
  T.check(CoopManager.partnerTyping == nil, "the partner stopping clears their line")
  CoopManager.onChatLive({ n = 5, text = "" })
  T.check(CoopManager.partnerTyping == nil, "a late packet after a stop stays dead")
end

-- ---------------------------------------------------------------------
-- a message waits while it is hidden
-- ---------------------------------------------------------------------

do
  CoopManager.partnerTyping = nil
  CoopManager.onChatReceived("MOCHI", "hidden behind a dialogue", false)
  local t0 = CoopManager.activeChatMessage.timer
  for _ = 1, 120 do CoopManager.update(nil, 1 / 60) end   -- nothing drew it
  T.check(CoopManager.activeChatMessage and CoopManager.activeChatMessage.timer == t0,
          "a message nobody could see has not used up its time")
  CoopManager.chatShown = true
  CoopManager.update(nil, 0.5)
  T.check(CoopManager.activeChatMessage.timer < t0, "it counts down once it is on screen")
  T.check(t0 > 3, "a longer message stays up longer (" .. t0 .. " s)")
end

-- the log keeps the last few
do
  for i = 1, 20 do CoopManager.onChatReceived("ME", "msg " .. i, true) end
  T.check(#CoopManager.chatLog == CoopManager.CHAT_LOG_MAX, "the log keeps the last " .. CoopManager.CHAT_LOG_MAX)
  local lines = CoopManager.chatLines(18, 4)
  T.check(#lines == 4 and lines[4]:find("msg 20", 1, true), "the box shows the newest lines")
end

T.finish("co-op live chat")
