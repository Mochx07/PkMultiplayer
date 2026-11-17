-- src/coop/CoopDiscord.lua
-- DISCORD AND AFK (nightly.2).
--
--   * HOSTING shows "Ask to Join" on your Discord profile: the join secret is
--     the co-op invite code (the address you are reachable at: LAN or a VPN,
--     src/coop/CoopNet.lua), with its own kind ("c") so the engine leaves the
--     click to this mod; a friend who clicks it while in their game is
--     dialled straight in.  Linked, the party shows 2/2.
--   * The activity says with whom: "Co-op with TOBY" (battle / exploring
--     stays the engine's), and "AFK" after 3 minutes without a key or a
--     button.
--   * AFK reaches the partner too ("afk", capability): a Zzz stays over your
--     avatar on their screen until you are back.

local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")

local CoopDiscord = {}
CoopDiscord.CAP = "afk"
CoopDiscord.AFK_AFTER = 180
CoopManager.registerCap(CoopDiscord.CAP)

local function clock() return love and love.timer and love.timer.getTime() or os.clock() end
CoopDiscord.lastInput = clock()
CoopDiscord.afk = false

-- Hooks: any key or button
function CoopDiscord.onInput()
  CoopDiscord.lastInput = clock()
  if CoopDiscord.afk then CoopDiscord.setAfk(false) end
end

function CoopDiscord.setAfk(on)
  if CoopDiscord.afk == on then return end
  CoopDiscord.afk = on
  CoopLog.info("DISCORD", on and "AFK" or "back")
  if CoopManager.connected and CoopManager.net and CoopManager.bothHave(CoopDiscord.CAP) then
    CoopManager.net:send({ type = "coop_afk", afk = on })
  end
  CoopDiscord.refresh(true)
end

CoopManager.handlers.coop_afk = function(_, msg)
  CoopManager.partner.afk = msg.afk == true
  if msg.afk then
    CoopManager.showStatus(string.format(require("src.coop.CoopI18n").t("%s is AFK"), CoopManager.partner.name or "Partner"), 2.5)
  end
end

-- ------------------------------------------------------------ presence
local function presence() return package.loaded["src.core.DiscordPresence"] end

-- the code to advertise right now, its party size, or nil
function CoopDiscord.wanted()
  local net = CoopManager.net
  if not (net and not net.closed and CoopManager.isHost) then return nil end
  local CoopNet = require("src.coop.CoopNet")
  local ip = CoopNet.bestIP()
  local code = CoopNet.inviteCode(ip, net.port or CoopNet.DEFAULT_PORT)
  if not code then return nil end
  return code, CoopManager.connected and 2 or 1
end

CoopDiscord.shown = nil
function CoopDiscord.refresh(force)
  local DP = presence()
  if not (DP and DP.setJoinCode) then return end
  local code, size = CoopDiscord.wanted()
  local key = tostring(code) .. "/" .. tostring(size) .. "/" .. tostring(CoopDiscord.afk) .. "/" .. tostring(CoopManager.connected)
  if key == CoopDiscord.shown and not force then return end
  CoopDiscord.shown = key
  pcall(DP.setJoinCode, code, code and "coop" or nil, size or 1, 2)
end

-- DiscordPresence's buildActivity (co-op patch): our lines on its activity
function CoopManager.discordDecorate(activity, state)
  if type(activity) ~= "table" then return end
  local bits = {}
  if CoopManager.connected then
    bits[#bits + 1] = "Co-op with " .. tostring(CoopManager.partner.name or "a friend")
  elseif CoopManager.net and not CoopManager.net.closed and CoopManager.isHost then
    bits[#bits + 1] = "Hosting co-op"
  end
  if CoopDiscord.afk then bits[#bits + 1] = "AFK" end
  if #bits > 0 then
    activity.state = table.concat(bits, " - ")
    activity.assets = activity.assets or {}
    activity.assets.small_text = CoopDiscord.afk and "AFK" or "PkMultiplayer"
  end
end

-- a friend clicked our "Ask to Join"
function CoopDiscord.onJoinRequested(payload, game)
  if type(payload) ~= "table" or payload.kind ~= "c" then return false end
  local CoopNet = require("src.coop.CoopNet")
  local ip, port = CoopNet.parseInviteCode(payload.code)
  if not ip then return false end
  if CoopManager.connected then return false end
  CoopLog.info("DISCORD", "join requested: dialling " .. ip .. ":" .. tostring(port))
  CoopManager.showStatus(require("src.coop.CoopI18n").t("Joining from Discord..."), 3)
  return CoopManager.join(ip, port) and true or false
end

CoopManager.onIdleTick("discord", function(dt)
  if not CoopDiscord.afk and clock() - CoopDiscord.lastInput >= CoopDiscord.AFK_AFTER then
    CoopDiscord.setAfk(true)
  end
  CoopDiscord.refresh(false)
end)

return CoopDiscord
