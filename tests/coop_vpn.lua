-- MORE VPNs (nightly.2, CoopNet.detectVPNs / addresses).  ZeroTier, and now
-- Tailscale, Radmin VPN, Hamachi and WireGuard, found by the source address
-- the OS would use to reach each range (nothing sent) and by interface /
-- adapter names; the home network's own address is never taken for one.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
T.fixtures.fresh()
local CoopNet = require("src.coop.CoopNet")

local LAN = "192.168.1.20"
local function prober(routes)
  return function(target)
    for prefix, addr in pairs(routes) do
      if target:sub(1, #prefix) == prefix then return addr end
    end
    return LAN
  end
end
local function names(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e.name .. "=" .. e.ip end
  return table.concat(out, " ")
end
local none = function() return {} end

local l = CoopNet.detectVPNs(prober({}), none, LAN)
T.check(#l == 0, "no VPN: nothing found (" .. names(l) .. ")")
l = CoopNet.detectVPNs(prober({ ["100.100."] = "100.101.7.9" }), none, LAN)
T.check(l[1] and l[1].name == "TAILSCALE" and l[1].ip == "100.101.7.9", "Tailscale by its 100.64/10 route")
l = CoopNet.detectVPNs(prober({ ["26."] = "26.12.3.4", ["25."] = "25.1.2.3" }), none, LAN)
T.check(names(l):find("RADMIN=26.12.3.4") and names(l):find("HAMACHI=25.1.2.3"), "Radmin (26/8) and Hamachi (25/8) together (" .. names(l) .. ")")
l = CoopNet.detectVPNs(prober({ ["100.100."] = "100.20.1.1" }), none, LAN)
T.check(#l == 0, "an address outside 100.64/10 is not Tailscale")
l = CoopNet.detectVPNs(prober({}), function() return { { name = "wg0", addr = "10.8.0.2" }, { name = "eth0", addr = LAN },
                                                          { name = "tailscale0", addr = "100.88.1.2" } } end, LAN)
T.check(names(l):find("WIREGUARD=10.8.0.2") and names(l):find("TAILSCALE=100.88.1.2") and not names(l):find(LAN),
        "interfaces: wg0 is WireGuard, tailscale0 Tailscale, the home one is left out (" .. names(l) .. ")")
l = CoopNet.detectVPNs(prober({}), function() return { { name = "ethernet adapter radmin vpn:", addr = "26.5.5.5", adapter = true } } end, LAN)
T.check(l[1] and l[1].name == "RADMIN", "a Windows adapter named Radmin VPN")
local code = CoopNet.inviteCode("100.101.7.9", 7777)
local ip = CoopNet.parseInviteCode(code)
T.check(ip == "100.101.7.9", "an invite code carries a Tailscale address (" .. tostring(code) .. ")")

T.finish("more VPNs")
