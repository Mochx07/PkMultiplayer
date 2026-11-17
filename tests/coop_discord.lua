-- DISCORD AND AFK (nightly.2, src/coop/CoopDiscord.lua).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
T.fixtures.fresh()
local CoopManager = require("src.coop.CoopManager")
local CD = require("src.coop.CoopDiscord")
local CoopNet = require("src.coop.CoopNet")
require("src.coop.CoopLog").enabled = false

local joined = {}
local shown = {}
package.loaded["src.core.DiscordPresence"] = { setJoinCode = function(code, kind, size, max)
  shown[#shown + 1] = { code = code, kind = kind, size = size, max = max }
end }
local sent = {}
CoopManager.net = { port = 7777, closed = false, send = function(_, m) sent[#sent + 1] = m end }
CoopManager.isHost = true
CoopManager.connected = false
CoopNet.bestIP = function() return "100.101.7.9", true, "TAILSCALE" end

CD.refresh(true)
local last = shown[#shown]
T.check(last and last.kind == "coop" and last.code == CoopNet.inviteCode("100.101.7.9", 7777) and last.size == 1,
        "hosting: the invite code is offered on Discord, party 1/2")
CoopManager.connected = true
CoopManager.partner.name = "TOBY"
CoopManager.partner.caps = { afk = true }
CD.refresh(false)
T.check(shown[#shown].size == 2, "linked: the party shows 2/2")

local act = { details = "ROUTE 29", state = "Exploring the overworld", assets = { large_image = "logo" } }
CoopManager.discordDecorate(act, {})
T.check(act.state == "Co-op with TOBY", "the activity says with whom (" .. act.state .. ")")
CD.lastInput = -1000
sent = {}
CD.setAfk(true)
act = { assets = {} }
CoopManager.discordDecorate(act, {})
T.check(act.state:find("AFK") and act.assets.small_text == "AFK", "AFK on Discord")
T.check(sent[1] and sent[1].type == "coop_afk" and sent[1].afk == true, "...and the partner is told")
CD.onInput()
T.check(not CD.afk and sent[2] and sent[2].afk == false, "a key: back, and the partner is told")
CoopManager.handlers.coop_afk(nil, { afk = true })
T.check(CoopManager.partner.afk == true, "the partner's AFK is kept for the Zzz over them")

-- a friend's click
CoopManager.connected = false
local realJoin = CoopManager.join
CoopManager.join = function(ip, port) joined[#joined + 1] = ip .. ":" .. tostring(port) return true end
T.check(CD.onJoinRequested({ kind = "c", code = CoopNet.inviteCode("100.101.7.9", 7777) }) and joined[1] == "100.101.7.9:7777",
        "a Discord join click dials the host")
T.check(not CD.onJoinRequested({ kind = "m", code = "ABCD" }), "an online-match click is the engine's, not ours")
CoopManager.join = realJoin
T.finish("Discord and AFK")
