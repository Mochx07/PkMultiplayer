-- src/coop/CoopMenu.lua
-- In-game UI for creating, joining and managing the Co-op session.
-- Designed natively for Game Boy 4:3 (160x144, 20x18 tiles) with pure retro aesthetic.

local CoopManager = require("src.coop.CoopManager")
local CoopNet = require("src.coop.CoopNet")
local Font = require("src.coop.CoopI18n").font()
local Strings = require("src.core.Strings")

local CoopMenu = {}
CoopMenu.__index = CoopMenu
CoopMenu.isOpaque = true

local CURSOR = 0xED
local DOWN_ARROW = 0xEE
-- rows the linked menu shows at once (it scrolls past that)
local VISIBLE_ROWS = 9

-- The address being typed, as twelve digits (three per octet), so the
-- cursor can walk them one by one.  Starts from this machine's own address,
-- which on a ZeroTier network shares its first three octets with the host's.
local function ipDigits(ip)
  local octets = { (ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$") }
  if #octets ~= 4 then octets = { 192, 168, 1, 100 } end
  local text = ""
  for _, o in ipairs(octets) do
    text = text .. ("%03d"):format(math.min(255, tonumber(o) or 0))
  end
  local digits = {}
  for ch in text:gmatch("%d") do digits[#digits + 1] = tonumber(ch) end
  return digits
end

-- ...and back to "a.b.c.d", each octet capped at 255
local function digitsIP(digits)
  local text = table.concat(digits)
  local parts = {}
  for chunk in text:gmatch("%d%d%d") do
    parts[#parts + 1] = tostring(math.min(255, tonumber(chunk)))
  end
  return table.concat(parts, ".")
end

-- the digit under the cursor, turned like a dial
local function turnDigit(self, step)
  self.addr[self.addrPos] = (self.addr[self.addrPos] + step) % 10
end

-- the cursor, kept on the twelve digits
local function moveCursor(self, step)
  local pos = self.addrPos + step
  if pos >= 1 and pos <= #self.addr then self.addrPos = pos end
end

-- ---------------------------------------------------------------------
-- what went wrong, in words the player can act on
-- ---------------------------------------------------------------------

-- `text` cut at spaces into lines of at most n letters (after translation)
local function wrap(text, n, maxLines)
  local I18n = require("src.coop.CoopI18n")
  text = I18n.t(tostring(text or ""))
  local len = function(t) return select(2, t:gsub("[^\128-\191]", "")) end
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if line == "" then
      line = word
    elseif len(line) + 1 + len(word) <= n then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  for i, l in ipairs(lines) do lines[i] = I18n.fit(l, n) end
  while maxLines and #lines > maxLines do table.remove(lines) end
  return lines
end
CoopMenu.wrap = wrap

-- THE REASON, AND WHAT TO DO ABOUT IT.  The menu used to print the error cut
-- to 18 letters ("PARTNER PLAYS OTHE") with nothing after it; most of them
-- come down to the same few causes.
local ADVICE = {
  { "NOT FOUND", "CHECK IP AND PORT; FIREWALL: ALLOW UDP %d" },
  { "UNREACHABLE", "CHECK IP AND PORT; FIREWALL: ALLOW UDP %d" },
  { "IN USE", "ANOTHER GAME HOSTS HERE: JOIN OR VISIT IT" },
  { "BUSY", "IT HAS A PARTNER: VISIT IT INSTEAD" },
  { "HAS V", "BOTH PLAYERS NEED THE SAME MOD VERSION" },
  { "OTHER GAME", "PLAY THE SAME GENERATION AS THE HOST" },
  { "LOST", "RECONNECT FROM THIS MENU" },
  { "UNAVAILABLE", "NO NETWORK: IS ZEROTIER ON?" },
  { "BAD ADDRESS", "CHECK THE IP" },
  { "CODE", "ASK THE HOST FOR THEIR CODE AGAIN" },
}

function CoopMenu.errorLines(err, port, maxLines)
  maxLines = maxLines or 3
  local lines = wrap(err, 18, math.max(1, maxLines - 1))
  local upper = tostring(err or ""):upper()
  for _, a in ipairs(ADVICE) do
    if upper:find(a[1], 1, true) then
      local tip = a[2]:format(tonumber(port) or CoopNet.DEFAULT_PORT)
      for _, l in ipairs(wrap(tip, 18)) do
        if #lines >= maxLines then break end
        lines[#lines + 1] = l
      end
      break
    end
  end
  return lines
end

local function drawError(err, port, x, y, maxLines)
  love.graphics.setColor(0.8, 0.1, 0.1, 1)
  for i, line in ipairs(CoopMenu.errorLines(err, port, maxLines)) do
    Font.draw(line, x, y + (i - 1) * 8)
    if i == 1 then love.graphics.setColor(0, 0, 0, 1) end
  end
  love.graphics.setColor(0, 0, 0, 1)
end
CoopMenu.drawError = drawError

-- the five port digits, turned like the address dial
local function portDigits(port)
  local text = ("%05d"):format(math.max(0, math.min(65535, tonumber(port) or CoopNet.DEFAULT_PORT)))
  local digits = {}
  for ch in text:gmatch("%d") do digits[#digits + 1] = tonumber(ch) end
  return digits
end

local function isPhone()
  local name = love and love.system and love.system.getOS and love.system.getOS()
  return name == "iOS" or name == "Android"
end

local function setKeyboard(on)
  pcall(function()
    if love.keyboard and love.keyboard.setTextInput then love.keyboard.setTextInput(on) end
  end)
end

function CoopMenu.new(game)
  local self = setmetatable({}, CoopMenu)
  self.game = game
  self.stage = "main"
  self.index = 1
  self.addr = ipDigits(CoopNet.zeroTierIP() or CoopNet.lanIP())
  self.addrPos = 12
  self.port = CoopNet.DEFAULT_PORT
  return self
end

-- Listening for a partner (and VISITORS, src/coop/CoopVisit.lua) with
-- nobody linked yet.  The door stays open while the host plays: the
-- hosting screen's B goes back to the game, not to "cancel" -- cancelling
-- was the only way out, and it shut the door on everyone visiting.
local function hostingOpen()
  local net = CoopManager.net
  return CoopManager.isHost and net ~= nil and not net.closed and net.isHost == true
     and not CoopManager.isConnected()
end
CoopMenu.hostingOpen = hostingOpen

local function visitorCount()
  local srv = package.loaded["src.coop.CoopVisit"] and package.loaded["src.coop.CoopVisit"].server
  local n = 0
  for _ in pairs(srv and srv.visitors or {}) do n = n + 1 end
  return n
end

local function findOverworld(game)
  if not game then return nil end
  if game.overworld and game.overworld.isOverworld then return game.overworld end
  local stack = game.stack
  local states = stack and stack.states
  if states then
    for i = #states, 1, -1 do
      if states[i] and states[i].isOverworld then return states[i] end
    end
  end
  return nil
end

function CoopMenu:close()
  self.game.stack:pop()
end

local function onOff(v) return v and "ON" or "OFF" end

-- the warp row shows its cooldown while it recharges
local function warpLabel()
  if CoopManager.warpAsking and CoopManager.warpAsking() then return "WARP (ASKING)" end
  local left = math.ceil(CoopManager.warpCooldownLeft())
  if left <= 0 then return "WARP TO PARTNER" end
  return string.format("WARP (%d:%02d)", math.floor(left / 60), left % 60)
end

-- A rule row: the name on the left, ON/OFF lined up on the right edge of
-- the 16 columns a label has.
local function ruleLabel(name, on)
  local I18n = require("src.coop.CoopI18n")
  name, on = I18n.t(name), I18n.t(onOff(on))
  local len = function(t) return select(2, t:gsub("[^\128-\191]", "")) end
  return name .. string.rep(" ", math.max(1, 16 - len(name) - len(on))) .. on
end

-- THE VERSION ROW: highlighted, the box above says which PkMultiplayer this
-- is, the link protocol it speaks, and -- linked -- the partner's version
-- (a partner from before 1.4.1-alpha.1 does not send one).
local function versionRow()
  local info = { ("MOD V%s"):format(CoopManager.modVersion():upper()):sub(1, 18),
                 ("LINK PROTOCOL %d"):format(CoopNet.PROTOCOL) }
  if CoopManager.isConnected() then
    local v = CoopManager.partner and CoopManager.partner.version
    info[3] = (v and ("P2 V" .. tostring(v):upper()) or "P2 V? (OLDER MOD)"):sub(1, 18)
  end
  return { label = "VERSION", info = info, run = function() end }
end

-- THE LINKED MENU, as data: what it says and what A does.
--
-- It used to be one list of nineteen rows -- things to do, the partner's
-- things and the shared ON/OFF rules all mixed together, nine on screen at a
-- time -- and reported from play: "the co-op menu with so many options can
-- be overwhelming".  Now the top page is seven rows that fit without
-- scrolling; what you do WITH your partner is under PARTNER, the shared
-- rules under RULES (`sub` opens a page, B comes back), and each rule says
-- what it does in the box above while it is highlighted (`info`).  The rules
-- are shared -- toggling one changes it for both players (coop_rules).
function CoopMenu:connectedRows(ow, page)
  local menu = self
  page = page or self.page or "main"
  local function open(sub)
    return function()
      menu.parentIndex = menu.index
      menu.page, menu.index, menu.scroll = sub, 1, 1
    end
  end
  if page == "partner" then
    return {
      { label = "ITEM FOR PARTNER", run = function()
        menu:close()
        if ow then CoopManager.useItemOnPartner(menu.game, ow) end
      end },
      { label = "WATCH " .. tostring(CoopManager.partner.name or "PARTNER"):upper():sub(1, 7), run = function()
        require("src.coop.CoopWatch").open(menu.game)
      end },
      { label = "TRADE", run = function()
        menu:close()
        require("src.coop.CoopLink").invite(menu.game, "trade")
      end },
      { label = "BATTLE P1 VS P2", run = function()
        menu:close()
        require("src.coop.CoopLink").invite(menu.game, "battle")
      end },
      { label = "MYSTERY GIFT", run = function()
        menu:close()
        require("src.coop.CoopGift").ask(menu.game, ow)
      end },
    }
  elseif page == "rules" then
    local function rule(key, name, info)
      return { label = ruleLabel(name, CoopManager[key]), info = info, ruleKey = key, run = function()
        CoopManager.setRule(key, not CoopManager[key])
      end }
    end
    local okV, GameVersion = pcall(require, "src.core.GameVersion")
    local gen1 = okV and GameVersion.isGen1()
    local storyInfo = { "STORY EVENTS ONE", "OF YOU SEES COUNT", "FOR BOTH OF YOU." }
    if not CoopManager.storyCompatible() then
      storyInfo = { "OFF: GOLD/SILVER", "AND CRYSTAL KEEP", "THEIR OWN STORY." }
    end
    local rows = {
      rule("storySync", "STORY SYNC", storyInfo),
      rule("wildTogether", "TEAM UP WILD",
           { "A WILD POKéMON", "NEAR YOU BOTH CAN", "BE FOUGHT AS TWO." }),
      rule("shareDex", "SHARE DEX",
           { "WHAT EITHER OF YOU", "CATCHES SHOWS AS", "SEEN FOR BOTH." }),
      rule("shareDayCare", "LINK DAYCARE",
           { "BREED WITH THE", "POKéMON YOUR", "PARTNER BOARDED." }),
      rule("partnerHeals", "PARTNER HEAL",
           { "AFTER YOU WIN A", "CO-OP BATTLE, BOTH", "TEAMS ARE HEALED." }),
      rule("soulLink", "SOUL LINK",
           { "PAIRED CATCHES:", "IF ONE FAINTS,", "BOTH ARE LOST." }),
      rule("balancedFoes", "BALANCED FOES",
           { "TRAINERS FACING", "YOU TWO BRING MORE", "POKéMON, + LEVELS." }),
      rule("hardFoes", "HARD FOES",
           { "ONE FOE FOR EACH", "OF YOURS, AND", "3 LEVELS HIGHER." }),
      { label = "SOUL LINKS", info = { "SEE WHICH OF YOUR", "POKéMON ARE LINKED", "AND TO WHICH." },
        run = function() require("src.coop.CoopSoulLink").open(menu.game) end },
    }
    -- Red / Blue / Yellow's DAY-CARE MAN breeds nothing
    if gen1 then
      for i = #rows, 1, -1 do
        if rows[i].ruleKey == "shareDayCare" then table.remove(rows, i) end
      end
    end
    return rows
  end
  return {
    -- the way into the chat on a phone, which has no T key
    { label = "CHAT  (KEY T)", run = function()
      menu:close()
      CoopManager.openChat(menu.game, ow)
    end },
    { label = "EMOTE  (KEY Y)", run = function()
      menu:close()
      require("src.coop.CoopEmotes").openPicker(menu.game)
    end },
    { label = warpLabel(), run = function()
      menu:close()
      if ow then CoopManager.warpToPartner(ow) end
    end },
    { label = "PARTNER", sub = "partner", run = open("partner") },
    { label = "POKéDEX", run = function()
      require("src.coop.CoopDex").open(menu.game)
    end },
    { label = "RULES", sub = "rules", run = open("rules") },
    versionRow(),
    { label = "DISCONNECT", run = function()
      require("src.coop.CoopRejoin").stop(menu.game)
      CoopManager.disconnect()
      menu.page, menu.index = "main", 1
    end },
  }
end

-- The offline menu, the same way.  RECONNECT leads it when the save
-- remembers a link (CoopRejoin): the host listens again, the guest dials.
function CoopMenu:offlineRows()
  local menu = self
  local rows = {}
  local link = self.game.save and self.game.save.coopLink
  if link then
    local who = tostring(link.partner or "PARTNER"):sub(1, 6)
    rows[#rows + 1] = { label = "RECONNECT " .. who, run = function()
      menu.errorMsg = nil
      if require("src.coop.CoopRejoin").try(menu.game, true) then
        menu.stage = (link.role == "host") and "hosting" or "joining"
      else
        menu.errorMsg = (CoopManager.net and CoopManager.net.error) or "FAILED"
      end
    end }
  end
  if hostingOpen() then
    -- already hosting: see who is here, or close the door for good.  HOST
    -- again restarted the session and dropped every visitor.
    rows[#rows + 1] = { label = "HOSTING...", run = function() menu.stage = "hosting" end }
    rows[#rows + 1] = { label = "STOP HOSTING", run = function()
      CoopManager.disconnect()
      menu.index = 1
    end }
  else
    rows[#rows + 1] = { label = "HOST", run = function()
      menu.errorMsg = nil
      if CoopManager.host(menu.port) then
        menu.stage = "hosting"
      else
        menu.errorMsg = (CoopManager.net and CoopManager.net.error) or "FAILED TO HOST"
      end
    end }
    rows[#rows + 1] = { label = "JOIN", run = function()
      menu:openJoin(false)
    end }
    -- a third (fourth, fifth...) player walks the host's world: src/coop/CoopVisit.lua
    local CoopVisit = require("src.coop.CoopVisit")
    if CoopVisit.visiting() then
      rows[#rows + 1] = { label = "STOP VISITING", run = function() CoopVisit.leave() end }
    else
      rows[#rows + 1] = { label = "VISIT", run = function()
        menu:openJoin(true)
      end }
    end
    -- the port this game hosts on and dials (a second game on the same
    -- machine hosts on another)
    rows[#rows + 1] = { label = "PORT " .. tostring(menu.port),
                        info = { "THE UDP PORT YOU", "HOST ON AND JOIN.", "USUALLY 7777." },
                        run = function()
      menu.portEdit, menu.portPos = portDigits(menu.port), 5
      menu.stage = "portEntry"
    end }
  end
  rows[#rows + 1] = { label = "STORY SYNC " .. onOff(CoopManager.storySync), run = function()
    -- through the shared setter: it is saved, and sent on the next link
    CoopManager.setRule("storySync", not CoopManager.storySync)
  end }
  rows[#rows + 1] = { label = "EMOTE", run = function()
    menu:close()
    require("src.coop.CoopEmotes").openPicker(menu.game)
  end }
  rows[#rows + 1] = versionRow()
  rows[#rows + 1] = { label = "EXIT", run = function() menu:close() end }
  return rows
end

-- JOIN / VISIT: the hosts joined lately first, then the two ways to name
-- a new one -- the address dial (a pad) or the host's invite code (a
-- keyboard, a phone's on-screen one, or the clipboard)
function CoopMenu:openJoin(visit)
  self.visitMode = visit and true or nil
  self.errorMsg = nil
  self.stage, self.pickIndex = "joinPick", 1
end

function CoopMenu:joinRows()
  local menu = self
  local rows = {}
  for _, h in ipairs(CoopNet.recentHosts()) do
    rows[#rows + 1] = { label = h.ip, info = { "JOINED BEFORE:", h.ip, "PORT " .. h.port },
                        run = function() menu:connectTo(h.ip, h.port) end }
  end
  rows[#rows + 1] = { label = "TYPE THE IP", info = { "TURN THE DIGITS", "WITH THE D-PAD." },
                      run = function() menu.stage = "addrEntry" end }
  rows[#rows + 1] = { label = "TYPE A CODE", info = { "THE HOST'S CODE,", "LIKE 30AG-0B4.", "CTRL+V PASTES IT." },
                      run = function() menu:openCode() end }
  return rows
end

-- dials the host (a visit knocks on the port after theirs)
function CoopMenu:connectTo(ip, port)
  self.errorMsg = nil
  port = tonumber(port) or self.port
  if self.visitMode then
    local ok, why = require("src.coop.CoopVisit").visit(ip, port + 1)
    if ok then
      CoopNet.rememberHost(ip, port)
      self:close()
    else
      self.errorMsg = why or "FAILED TO CONNECT"
    end
    return
  end
  if CoopManager.join(ip, port) then
    self.stage = "joining"
  else
    self.errorMsg = (CoopManager.net and CoopManager.net.error) or "FAILED TO CONNECT"
  end
end

function CoopMenu:openCode()
  self.code, self.errorMsg = "", nil
  self.stage = "codeEntry"
  setKeyboard(true)
end

function CoopMenu:leaveCode()
  if isPhone() then setKeyboard(false) end
  self.stage = "joinPick"
end

function CoopMenu:submitCode()
  local ip, port = CoopNet.parseInviteCode(self.code)
  if not ip then
    self.errorMsg = "THAT CODE IS NOT RIGHT"
    return
  end
  if isPhone() then setKeyboard(false) end
  self:connectTo(ip, port)
  if self.stage == "codeEntry" then self.stage = "joinPick" end
end

-- typed letters, only while a code is being typed
function CoopMenu:onTextInput(text)
  if self.stage ~= "codeEntry" or type(text) ~= "string" then return end
  local clean = text:upper():gsub("[^%w%-]", "")
  if #self.code + #clean <= 12 then self.code = self.code .. clean end
end

-- THE KEYBOARD.  While a code is typed, every key is the code's (Z and X
-- would otherwise also press A and B); elsewhere the keys go on to the
-- game's input as they always did.
function CoopMenu:onKeyPressed(key)
  if self.stage ~= "codeEntry" then
    require("src.core.Input"):keypressed(key)
    return
  end
  local k = love and love.keyboard
  local ctrl = k and k.isDown and (k.isDown("lctrl") or k.isDown("rctrl") or k.isDown("lgui") or k.isDown("rgui"))
  if key == "backspace" then
    self.code = self.code:sub(1, -2)
  elseif key == "return" or key == "kpenter" then
    self:submitCode()
  elseif key == "escape" then
    self:leaveCode()
  elseif key == "v" and ctrl then
    local ok, clip = pcall(function() return love.system.getClipboardText() end)
    if ok and type(clip) == "string" then
      self.code = clip:upper():gsub("[^%w%-]", ""):sub(1, 12)
    end
  end
end

-- where an offline row sits (RECONNECT pushes the others down)
function CoopMenu:offlineIndex(label)
  for i, row in ipairs(self:offlineRows()) do
    if row.label == label then return i end
  end
  return 1
end

function CoopMenu:update(dt)
  local input = self.game.input
  local ow = findOverworld(self.game)
  -- the transport is pumped by CoopManager.update from Game:update; pumping
  -- it here as well split the inbox between two readers

  if self.stage == "main" then
    local isConn = CoopManager.isConnected()
    if not isConn then self.page = "main" end
    local rows = isConn and self:connectedRows(ow) or self:offlineRows()
    local maxItems = #rows
    if self.index > maxItems then self.index = 1 end

    if input:wasPressed("down") then
      self.index = (self.index % maxItems) + 1
    elseif input:wasPressed("up") then
      self.index = ((self.index - 2) % maxItems) + 1
    elseif input:wasPressed("b") then
      if self.page and self.page ~= "main" then
        -- back to the row the page was opened from
        self.page, self.index, self.scroll = "main", self.parentIndex or 1, 1
      else
        self:close()
      end
    elseif input:wasPressed("a") then
      local row = rows[self.index]
      if row and row.run then row.run() end
    end

  elseif self.stage == "hosting" then
    if input:wasPressed("b") then
      -- back to the game; the session keeps listening (STOP HOSTING ends it)
      self:close()
      CoopManager.showStatus("Still hosting", 2.5)
      return
    end
    if CoopManager.isConnected() then
      self.stage = "main"
      self.index = 1
    end

  elseif self.stage == "joinPick" then
    local rows = self:joinRows()
    if self.pickIndex > #rows then self.pickIndex = 1 end
    if input:wasPressed("down") then
      self.pickIndex = (self.pickIndex % #rows) + 1
    elseif input:wasPressed("up") then
      self.pickIndex = ((self.pickIndex - 2) % #rows) + 1
    elseif input:wasPressed("b") then
      self.stage = "main"
      self.index = self:offlineIndex(self.visitMode and "VISIT" or "JOIN")
    elseif input:wasPressed("a") then
      rows[self.pickIndex].run()
    end

  elseif self.stage == "codeEntry" then
    -- a pad still confirms and backs out
    if input:wasPressed("b") then
      self:leaveCode()
    elseif input:wasPressed("a") or input:wasPressed("start") then
      self:submitCode()
    end

  elseif self.stage == "portEntry" then
    local d = self.portEdit
    if input:wasPressed("b") then
      self.stage = "main"
    elseif input:wasPressed("up") then
      d[self.portPos] = (d[self.portPos] + 1) % 10
    elseif input:wasPressed("down") then
      d[self.portPos] = (d[self.portPos] + 9) % 10
    elseif input:wasPressed("left") then
      self.portPos = math.max(1, self.portPos - 1)
    elseif input:wasPressed("right") then
      self.portPos = math.min(5, self.portPos + 1)
    elseif input:wasPressed("a") then
      local port = tonumber(table.concat(d)) or CoopNet.DEFAULT_PORT
      if port < 1024 or port > 65534 then
        self.errorMsg = "PORT 1024 TO 65534"
      else
        self.port, self.errorMsg = port, nil
        self.stage = "main"
      end
    end

  elseif self.stage == "addrEntry" then
    if input:wasPressed("b") then
      self.stage = "joinPick"
    elseif input:wasPressed("up") then
      turnDigit(self, 1)
    elseif input:wasPressed("down") then
      turnDigit(self, -1)
    elseif input:wasPressed("left") then
      moveCursor(self, -1)
    elseif input:wasPressed("right") then
      moveCursor(self, 1)
    elseif input:wasPressed("a") then
      self:connectTo(digitsIP(self.addr), self.port)
    end

  elseif self.stage == "joining" then
    if input:wasPressed("b") then
      CoopManager.disconnect()
      self.stage = "joinPick"
    elseif CoopManager.isConnected() then
      self.stage = "main"
      self.index = 1
    elseif not CoopManager.net or CoopManager.net.closed then
      -- the real reason: the host's refusal says why (another version...)
      self.errorMsg = (CoopManager.net and CoopManager.net.error) or CoopManager.lastLinkError
                      or "HOST NOT FOUND"
      self.stage = "joinPick"
    end

  end
end

-- Clear screen to Game Boy background
local function clearGB()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
end

local function fit(text, n)
  -- translated, then cut to n letters (not bytes: an accent is two)
  return require("src.coop.CoopI18n").fit(text, n)
end

-- All lines fit the 18 columns inside a full-width box (x 8..152).
function CoopMenu:draw()
  clearGB()
  local isConn = CoopManager.isConnected()
  local partner = CoopManager.partner

  if self.stage == "main" then
    Font.drawBox(0, 0, 20, 5)
    local rows = isConn and self:connectedRows(findOverworld(self.game)) or self:offlineRows()
    local current = rows[self.index]
    if type(current) == "table" and current.info then
      -- what the highlighted row is about (a rule, the versions), above
      local info = require("src.coop.CoopI18n").lines(current.info)
      for i, line in ipairs(info) do Font.draw(line, 8, i * 8) end
    elseif not isConn and self.errorMsg then
      -- up here, where nothing else is drawn: at the foot of the list it
      -- landed on top of the last row (EXIT)
      -- the reason in full, and what to do about it
      drawError(self.errorMsg, self.port, 8, 8, 3)
    elseif not isConn then
      Font.draw("CO-OP LINK", 8, 8)
      Font.draw("YOUR IP:", 8, 16)
      Font.draw(fit(CoopNet.zeroTierIP() or CoopNet.lanIP(), 18), 8, 24)
    else
      Font.draw("LINK: " .. fit(partner.name or "PARTNER", 8), 8, 8)
      Font.draw("AREA:", 8, 16)
      -- the round trip, right-aligned on the AREA line
      local ms = CoopManager.net and tonumber(CoopManager.net.rttMs)
      if ms then
        local text = ("%dMS"):format(math.min(9999, ms))
        Font.draw(text, 152 - #text * 8, 16)
      end
      Font.draw(fit(CoopManager.mapLabel and CoopManager.mapLabel(partner.map) or partner.map, 18), 8, 24)
    end
    local labels = {}
    for i, row in ipairs(rows) do labels[i] = row.label or row end
    Font.drawBox(0, 5, 20, 13)
    -- tighter rows once linked: the list is longer than the five offline ones.
    -- Nine rows at 9px fill the box exactly, from under its top border (48)
    -- to the footer (128); B closes the menu, so there is no RESUME row.
    -- Labels are 16 characters at most: x = 24 to the border at 152.
    -- More than nine rows scroll, a window of nine kept around the cursor,
    -- with the down arrow while more rows wait below (the font has no up
    -- arrow; the cursor shows the way back).
    local pitch = (#rows > 8) and 9 or ((#rows > 6) and 10 or 12)
    local top = 48
    local first = 1
    if #rows > VISIBLE_ROWS then
      self.scroll = self.scroll or 1
      if self.index < self.scroll then self.scroll = self.index end
      if self.index > self.scroll + VISIBLE_ROWS - 1 then self.scroll = self.index - VISIBLE_ROWS + 1 end
      first = self.scroll
    end
    for i = first, math.min(#rows, first + VISIBLE_ROWS - 1) do
      Font.draw(labels[i], 24, top + (i - first) * pitch)
      -- a row that opens a page carries an arrow at the right edge
      if type(rows[i]) == "table" and rows[i].sub then
        Font.drawCode(CURSOR, 144, top + (i - first) * pitch)
      end
    end
    Font.drawCode(CURSOR, 12, top + (self.index - first) * pitch)
    if first + VISIBLE_ROWS - 1 < #rows then
      Font.drawCode(DOWN_ARROW, 144, top + (VISIBLE_ROWS - 1) * pitch)
    end
    Font.draw("A:OK  B:BACK", 8, 128)

  elseif self.stage == "hosting" then
    local port = (CoopManager.net and CoopManager.net.port) or self.port
    local ip = CoopNet.zeroTierIP() or CoopNet.lanIP()
    Font.drawBox(0, 0, 20, 7)
    Font.draw("HOSTING SESSION", 8, 8)
    Font.draw("PORT: " .. tostring(port), 8, 16)
    Font.draw(fit("CODE: " .. tostring(CoopNet.inviteCode(ip, port) or "?"), 18), 8, 24)
    Font.draw("IP:", 8, 32)
    Font.draw(fit(ip, 18), 8, 40)
    Font.drawBox(0, 7, 20, 11)
    Font.draw("TELL YOUR FRIEND", 8, 64)
    Font.draw("THE CODE OR IP.", 8, 72)
    local dots = string.rep(".", math.floor((love.timer and love.timer.getTime() or 0) * 2) % 4)
    Font.draw("WAITING" .. dots, 8, 88)
    Font.draw(fit("VISIT PORT: " .. (port + 1), 18), 8, 96)
    Font.draw("VISITORS: " .. visitorCount(), 8, 104)
    Font.draw("B:PLAY ON", 8, 128)

  elseif self.stage == "joinPick" then
    local rows = self:joinRows()
    local current = rows[self.pickIndex] or rows[1]
    Font.drawBox(0, 0, 20, 5)
    if self.errorMsg then
      drawError(self.errorMsg, self.port, 8, 8, 3)
    else
      local info = require("src.coop.CoopI18n").lines(current.info or {})
      for i, line in ipairs(info) do Font.draw(fit(line, 18), 8, i * 8) end
    end
    Font.drawBox(0, 5, 20, 13)
    Font.draw(self.visitMode and "VISIT WHO?" or "JOIN WHO?", 8, 48)
    for i, row in ipairs(rows) do
      Font.draw(fit(row.label, 16), 24, 56 + i * 10)
    end
    Font.drawCode(CURSOR, 12, 56 + self.pickIndex * 10)
    Font.draw("A:OK  B:BACK", 8, 128)

  elseif self.stage == "codeEntry" then
    Font.drawBox(0, 0, 20, 4)
    Font.draw(self.visitMode and "VISIT WITH CODE" or "JOIN WITH CODE", 8, 12)
    Font.drawBox(0, 4, 20, 14)
    local blink = math.floor((love.timer and love.timer.getTime() or 0) * 2) % 2 == 0
    Font.draw((self.code or "") .. (blink and "_" or ""), 16, 52)
    Font.draw("TYPE THE CODE,", 8, 72)
    Font.draw("CTRL+V PASTES IT.", 8, 80)
    if self.errorMsg then drawError(self.errorMsg, self.port, 8, 96, 2) end
    Font.draw("ENTER:OK  ESC:BACK", 8, 128)

  elseif self.stage == "portEntry" then
    Font.drawBox(0, 0, 20, 4)
    Font.draw("CO-OP PORT", 8, 12)
    Font.drawBox(0, 4, 20, 14)
    for i, d in ipairs(self.portEdit or {}) do
      local x = 48 + (i - 1) * 12
      Font.draw(tostring(d), x, 52)
      if i == self.portPos then Font.drawCode(DOWN_ARROW, x, 60) end
    end
    Font.draw("HOST AND JOIN ON", 8, 80)
    Font.draw("THIS UDP PORT.", 8, 88)
    if self.errorMsg then drawError(self.errorMsg, self.port, 8, 104, 1) end
    Font.draw("A:OK  B:BACK", 8, 128)

  elseif self.stage == "addrEntry" then
    Font.drawBox(0, 0, 20, 4)
    Font.draw(self.visitMode and "VISIT: HOST IP" or "ENTER HOST IP", 8, 12)
    Font.drawBox(0, 4, 20, 14)
    for i = 1, 12 do
      local octet = math.floor((i - 1) / 3)
      local x = 16 + (i - 1) * 9 + octet * 6
      Font.draw(tostring(self.addr[i]), x, 52)
      if i == self.addrPos then
        Font.drawCode(DOWN_ARROW, x, 60)
      end
    end
    for octet = 1, 3 do
      Font.draw(".", 16 + octet * 33 - 6, 52)
    end
    Font.draw("PORT: " .. (self.visitMode and (self.port + 1) or self.port), 8, 80)
    Font.draw("D-PAD: EDIT IP", 8, 96)
    Font.draw(self.visitMode and "A:VISIT  B:BACK" or "A:JOIN  B:BACK", 8, 128)

  elseif self.stage == "joining" then
    Font.drawBox(0, 0, 20, 6)
    local dots = string.rep(".", math.floor((love.timer and love.timer.getTime() or 0) * 2) % 4)
    Font.draw("CONNECTING" .. dots, 8, 16)
    Font.drawBox(0, 6, 20, 12)
    Font.draw("WAITING FOR THE", 8, 64)
    Font.draw("HOST TO ANSWER", 8, 72)
    Font.draw("B:CANCEL", 8, 128)

  end

  if self.errorMsg and self.stage == "addrEntry" then
    drawError(self.errorMsg, self.port, 8, 104, 2)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return CoopMenu
