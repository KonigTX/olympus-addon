-- Guild verification between relays (1.5.4). Real Comm + Relay + Verify path; only Blizzard's wire
-- and timers are simulated. Unlike tests/verify-relay.lua, no relay is ever handed an "RY~" it did not
-- earn: on Forever a relay's own client counts itself as answered (Relay.Pick), so it never pings or
-- sweeps the other relays and never learns one of them answered. Every verifier (the King, the High
-- Council, the author) is a relay, so before this fix each relay was an island for verification:
-- an approval reached the verifier's own reporters and guild only, and a relay's own ask reached
-- nobody. A member's sweep answer ("RY~" from its relay) and its guild's registration ("RR") are what
-- a real member's client sends, so they are delivered here as the wire would.
local ns, test, eq, RelayWorld, ADDON_DIR = ...
local T0 = 1800000000
local GUILD, OTHER = "Olympus Vanguard", "Olympus Embers"
local MASTER = "Guild Master-Realm"
local HC, HUB = "Max Ran-Realm", "Hildryn Payne-Realm" -- both on the signed list, so both relays

local function World(fn, hubVerifies)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo }
	local dialogs = {}; for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	local nodes, timers, now = {}, {}, T0
	GetChannelName = function() return 0 end
	ns.IsMember = function() return true end
	IsInGuild = function() return true end
	local function As(n, f, ...)
		C_ChatInfo = n.chat
		GetGuildInfo = function() return n.guild, "Member", 3 end
		return f(...)
	end
	local function Node(name, guild)
		local c, deliver, sent, _, pump, sentOf = RelayWorld(name, guild)
		local n = { c = c, deliver = deliver, sent = sent, pump = pump, sentOf = sentOf,
			guild = guild, chat = C_ChatInfo, cursor = 0 }
		c.clock, c.realm, c.RealmPages = now, "Realm", {}
		c.rdb.guilds = { [GUILD] = { leader = MASTER, realm = "Realm" }, [OTHER] = { leader = MASTER, realm = "Realm" } }
		c.IsHighCouncillor = function(who)
			local full = c.FullName(who)
			return full == HC or (hubVerifies == true and full == HUB)
		end
		c.IsKingCharacter = function() return false end
		c.Workshop = { IsAuthorName = function() return false end }
		c.Fire, c.On = function() end, function() end
		c.UI = { Refresh = function() end }
		c.After = function(delay, _, f) timers[#timers + 1] = { at = now + delay, n = n, f = f } end
		c.Every = function() end
		As(n, function() assert(loadfile(ADDON_DIR .. "Verify.lua"))("Olympus", c) end)
		c.Verify.Clock = function() return now end
		c.Verify.random = function(a) return a end
		nodes[#nodes + 1] = n
		return n
	end
	local function Flush()
		for _ = 1, 60 do
			local moved = false
			for _, n in ipairs(nodes) do
				As(n, n.pump, 40)
				while n.cursor < #n.sent do
					n.cursor = n.cursor + 1
					local p = n.sent[n.cursor]
					for _, to in ipairs(nodes) do
						if to ~= n and ((p.dist == "WHISPER" and ns.ShortName(to.c.me) == ns.ShortName(p.target))
							or (p.dist == "GUILD" and to.guild == n.guild)) then
							As(to, to.deliver, p.dist, n.c.me, p.msg); moved = true
						end
					end
				end
			end
			if not moved then return end
		end
		error("verification wire did not settle")
	end
	local function Advance(seconds)
		now = now + seconds
		for _, n in ipairs(nodes) do n.c.clock = now end
		local due = timers; timers = {}
		for _, t in ipairs(due) do
			if t.at <= now then As(t.n, t.f) else timers[#timers + 1] = t end
		end
		Flush()
	end
	local ok, err = pcall(fn, Node, As, Flush, Advance)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = dialogs[k] end
	if not ok then error(err, 0) end
end

-- A member of `guild` whose sweep its relay answered and whose guild registered there.
local function Member(Node, As, name, guild, relay)
	local m = Node(name, guild)
	As(m, m.deliver, "WHISPER", relay.c.me, "RY~")
	As(relay, relay.deliver, "WHISPER", m.c.me, "RL~P~RR~" .. guild)
	return m
end

local function Count(n, prefix, target)
	local k = 0
	for _, p in ipairs(n.sent) do
		if p.msg:sub(1, #prefix) == prefix and (target == nil or ns.ShortName(p.target or "") == ns.ShortName(target)) then k = k + 1 end
	end
	return k
end

test("verify mesh: a verifier relay's approval reaches every other relay and the guilds registered there, live", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node(HUB, "Olympus Hearth")
		local verifier = Node(HC, "Olympus Crown")
		local member = Member(Node, As, "New Member-Realm", GUILD, hub)
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(10)
		eq(Count(verifier, "RL~P~RP~") + Count(hub, "RL~P~RP~"), 0, "relays never ping one another (Relay.Pick counts our own client)")
		eq(As(hub, hub.c.Verify.Status, GUILD), "verified", "the other relay holds the approval")
		eq(As(member, member.c.Verify.Status, GUILD), "verified", "a guild registered with another relay holds it")
		local e = member.c.rdb.verify.list[ns.Fold(GUILD)]
		eq(e.by, HC, "the verifier is never replaced by a relay"); eq(e.at, T0)
		eq(As(verifier, verifier.c.Verify.Revoke, GUILD), true)
		Flush(); Advance(10)
		eq(member.c.rdb.verify.list[ns.Fold(GUILD)].k, "R", "a revocation travels the same way")
	end)
end)

test("verify mesh: a relay that was offline when the approval was made (the dev's client) recovers it with its own ask, then answers its own clients", function()
	World(function(Node, As, Flush, Advance)
		local verifier = Node(HC, "Olympus Crown")
		As(verifier, verifier.c.Verify.Observe)
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(3600)
		local hub = Node(HUB, "Olympus Hearth") -- logs in an hour later, a verifier itself
		eq(As(hub, hub.c.Verify.Status, GUILD) ~= "verified", true)
		eq(As(hub, hub.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(As(hub, hub.c.Verify.Status, GUILD), "verified", "the relay's own ask reached the verifier relay")
		local e = hub.c.rdb.verify.list[ns.Fold(GUILD)]
		eq(e.at, T0, "the original time"); eq(e.by, HC, "the original verifier")
		eq(hub.c.rdb.verify.start[ns.Fold(GUILD)].at, T0, "recovery never restarts the grace")
		-- Its own clients next: a member whose guild is registered with the hub asks it.
		local member = Member(Node, As, "Hub Client-Realm", GUILD, hub)
		eq(As(member, member.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(As(member, member.c.Verify.Status, GUILD), "verified", "the relay now answers its own clients")
		eq(member.c.rdb.verify.list[ns.Fold(GUILD)].by, HC)
	end, true)
end)

test("verify mesh: a member that was offline recovers an approval its own relay cannot answer for", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node(HUB, "Olympus Hearth") -- a relay that is no verifier here: it never answers
		local verifier = Node(HC, "Olympus Crown")
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(3600)
		local member = Member(Node, As, "New Member-Realm", GUILD, hub)
		local guildmate = Node("Late Guildmate-Realm", GUILD)
		eq(As(member, member.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(As(member, member.c.Verify.Status, GUILD), "verified", "the ask crossed to the verifier relay")
		eq(member.c.rdb.verify.list[ns.Fold(GUILD)].at, T0)
		eq(As(guildmate, guildmate.c.Verify.Status, GUILD), "verified", "the member hands the answer to its guild once")
	end)
end)

test("verify mesh: bounded: verification never makes relays forward everything to each other, an answer is one transfer to the asker", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node(HUB, "Olympus Hearth")
		local verifier = Node(HC, "Olympus Crown")
		local reporters = {}
		for i = 1, 6 do reporters[i] = Member(Node, As, "Reporter " .. i .. "-Realm", "Olympus Guild " .. i, i <= 3 and hub or verifier) end
		for i = 1, 12 do eq(As(verifier, verifier.c.Verify.Approve, "Olympus Recovery " .. i, MASTER), true) end
		Flush(); Advance(10)
		Advance(3600)
		local late = Member(Node, As, "Late Member-Realm", GUILD, hub)
		eq(As(late, late.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(late.c.Verify.Digest() >= 12, true, "the late member holds every approval")
		-- The answer went to the asker alone, as one bounded transfer: no reporter of either relay got it.
		local function Answer(n, to)
			local k = 0
			for _, p in ipairs(n.sent) do
				if ns.ShortName(p.target or "") == ns.ShortName(to) and (p.msg:find("^RM~P~[^~]+~GV~1~S~") or p.msg:find("^CR%d+:%d+:%d+:")) then k = k + 1 end
			end
			return k
		end
		for _, r in ipairs(reporters) do
			eq(Answer(hub, r.c.me) + Answer(verifier, r.c.me), 0, "no snapshot fan-out to " .. r.c.me)
		end
		local pieces = Answer(verifier, late.c.me)
		eq(pieces >= 1 and pieces <= ns.Codec.MAX_CHUNKS, true, "one transfer to the asker: " .. pieces .. " pieces")
		-- After all this verification traffic, an ordinary word a client hands the hub still does not
		-- cross to the other relay: verification must never switch on relay-to-relay forwarding of
		-- every word (the census alone would be ~140 words a minute times every other relay).
		local before = Count(hub, "RX~", verifier.c.me)
		As(hub, hub.deliver, "WHISPER", "Some Client-Realm", "RL~P~X1~ordinary")
		Flush()
		eq(Count(hub, "RX~", verifier.c.me), before, "an ordinary word never crosses because of verification traffic")
		-- A word that claims to be an approval from someone who is no verifier never crosses relays
		-- (its own relay's guilds refuse it, as in 1.5.2); a verifier's own does, once.
		local rw = Count(hub, "RW~")
		As(hub, hub.deliver, "WHISPER", "Forger Here-Realm", ("RL~L~GV~1~A~%d~%s~%s"):format(T0 + 3700, OTHER, MASTER))
		Flush()
		eq(Count(hub, "RW~"), rw, "a forged approval does not cross relays")
		eq(late.c.rdb.verify.list[ns.Fold(OTHER)], nil, "and no guild takes it")
	end)
end)
