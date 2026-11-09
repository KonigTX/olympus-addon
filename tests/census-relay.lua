-- Production Data -> Comm chunk queue -> Relay envelopes -> native send API.
local ns, test, eq, extra = ...

test("census scope relay: count snapshots and portable observations drain through the actual relay while revoked capabilities stop", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, deliver, sent, _, pump = extra.RelayWorld("Original-Realm", "Olympus II")
		local relay = O.Relay.Pick()
		deliver("WHISPER", relay .. "-Realm", "RY~")
		O.group, O.faction, O.db = "ForeverPvP", "Alliance", {}
		O.rdb.guilds, O.rdb.seen = {}, {}
		local trusted = true
		O.Church = { IsLedgerRelay = function() return trusted end }
		O.QuietPresence = function() return false end
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", O)
		O.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, t = O.clock, from = "CAMWOWUS1Realm8PvP" }
		local function Contains(needle, since)
			for i = (since or 0) + 1, #sent do
				if sent[i].msg:find(needle, 1, true) then
					eq(sent[i].dist, "WHISPER"); eq(sent[i].target, relay)
					return true
				end
			end
			return false
		end
		assert(O.Data.SendGlobalCensus())
		pump(100)
		assert(Contains("CG~2~S~"), "accepted global snapshot must actually leave the native whisper API")
		assert(O.Data.RecordGroupCensus())
		O.group = "ForeverPvE" -- a carried PvP observation is sent after travelling to another origin
		assert(O.Data.SayGroupCensus())
		pump(100)
		assert(Contains("CX~3~S~"), "portable observation must leave through the same guarded relay route")
		O.group = "ForeverPvP"
		O.db.groupDetails["Alliance|Other"] = { group = "Other", faction = "Alliance", observed = O.clock,
			rows = { dawn = { name = "Olympus Dawn", total = 640, online = 40, avg10 = 300, observed = O.clock } } }
		assert(O.Data.SayGroupDetails())
		pump(100)
		assert(Contains("CX~2~S~"), "compatible detail transport also retains its logical channel capability")
		local before = #sent
		assert(O.Data.SendGlobalCensus())
		trusted = false
		pump(100)
		eq(Contains("CG~2~S~", before), false, "losing original trust cancels the queued snapshot")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

local function ScheduledCarry(rejectFirst)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo, random = math.random }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, deliver, sent, _, pump = extra.RelayWorld("Carrier-Realm", "Olympus II")
		local relay = O.Relay.Pick()
		deliver("WHISPER", relay .. "-Realm", "RY~")
		local timers, init, start, stamped = {}, {}, O.clock, 0
		O.group, O.faction, O.db = "ForeverPvE", "Alliance", { blocked = {} }
		O.rdb.guilds, O.rdb.seen = {}, {}
		O.Church = { IsLedgerRelay = function() return false end }
		O.QuietPresence = function() return false end
		O.On = function(event, fn) if event == "INIT" then init[#init + 1] = fn end end
		O.After = function(delay, label, fn)
			if label == "census groups" then timers[#timers + 1] = { at = O.clock + delay, fn = fn } end
		end
		O.Every = function(delay, label, fn)
			if label == "census groups" then timers[#timers + 1] = { at = O.clock + delay, fn = fn, every = delay } end
		end
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", O)
		for _, rules in ipairs({ "PvE", "PvP", "RP" }) do
			O.group, O.me = "Forever" .. rules, "Observer" .. rules .. "-Realm"
			O.rdb.guilds = { ["Olympus " .. rules] = { total = 100, online = 10, t = O.clock - 60,
				from = "CAMWOWUS1Realm1" .. rules } }
			assert(O.Data.RecordGroupCensus())
		end
		O.group, O.me, O.rdb.guilds = "ForeverPvE", "Carrier-Realm", {}
		math.random = function(a, b) return b or a end -- latest allowed first send
		local attempts, refused = {}, 0
		local send = O.Comm.SendChunked
		O.Comm.SendChunked = function(payload, ...)
			if payload:match("^CX~3~") then
				attempts[#attempts + 1] = payload
				if rejectFirst and refused == 0 then refused = 1; return false end
			end
			return send(payload, ...)
		end
		for _, fn in ipairs(init) do fn() end
		local function Advance(to)
			while true do
				table.sort(timers, function(a, b) return a.at < b.at end)
				local t = timers[1]
				if not t or t.at > to then break end
				table.remove(timers, 1); O.clock = t.at; t.fn()
				if t.every then t.at = O.clock + t.every; timers[#timers + 1] = t end
				pump(100)
				for i = stamped + 1, #sent do sent[i].at = O.clock end
				stamped = #sent
			end
			O.clock = to
		end
		Advance(start + 40)
		eq(#attempts, 1, "INIT attempts the first foreign origin within 40 seconds")
		assert(not attempts[1]:find("~ForeverPvE~", 1, true), "the local origin never consumes the first slot")
		Advance(start + (rejectFirst and 170 or 105))
		eq(#attempts, rejectFirst and 3 or 2, "foreign origins drain at 65-second intervals")
		if rejectFirst then eq(attempts[1], attempts[2], "a rejected queue admission does not skip the origin") end
		local last = #attempts
		Advance(start + 1799)
		eq(#attempts, last, "unchanged origins are not repeated within their 30-minute window")
		Advance(start + 2000)
		assert(#attempts > last, "the next bounded window permits a refresh")
		-- Feed actual native packets through the relay into a client that never visited either origin.
		local R, rdeliver, rsent, _, rpump = extra.RelayWorld(relay .. "-Realm", "Olympus Relay")
		rdeliver("WHISPER", "Late-Realm", "RL~P~RR~Olympus Late")
		for _, p in ipairs(sent) do
			if p.target == relay and p.at and p.at <= start + 170 and p.msg:find("CX~3~", 1, true) then
				R.clock = p.at; rdeliver("WHISPER", "Carrier-Realm", p.msg); rpump(100)
			end
		end
		local L, ldeliver = extra.RelayWorld("Late-Realm", "Olympus Late")
		L.group, L.faction, L.db = "ForeverPvE", "Alliance", { blocked = {} }
		L.rdb.guilds, L.rdb.seen = {}, {}
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", L)
		L.Comm.Handle("CX", L.Data.ReceiveGroupCensus)
		for _, p in ipairs(rsent) do if p.target == "Late" then ldeliver("WHISPER", R.me, p.msg) end end
		local all = L.Data.Groups()
		eq(#all.rows, 2, "both never-visited origins arrive through the actual relay")
		for _, row in ipairs(all.rows) do
			eq(row.characters, 100); eq(row.observed, start - 60); eq(row.counted, false)
		end
		eq(L.Data.Summary().characters, 0, "foreign observations never change local authority or current census")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo, math.random =
		saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat, saved.random
	if not ok then error(err, 0) end
end

test("census carry schedule: INIT delivers two foreign origins promptly without repeating unchanged observations", function()
	ScheduledCarry(false)
end)
test("census carry schedule: rejected admission retries the same origin before progressing without a send storm", function()
	ScheduledCarry(true)
end)

test("census scope relay: two large ordinary-origin observations cross the same reporter budget as complete atomic aggregates", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local function Census(N)
			N.group, N.faction, N.db = "ForeverPvP", "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function() return false end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.Comm.Handle("CX", N.Data.ReceiveGroupCensus)
		end
		local carrier = "Carrier" .. string.rep("x", 70) .. "-Realm"
		local O, odeliver, osent, _, opump = extra.RelayWorld(carrier, "Olympus II")
		local relay = O.Relay.Pick()
		odeliver("WHISPER", relay .. "-Realm", "RY~")
		Census(O)
		for _, rules in ipairs({ "PvE", "RP" }) do
			O.group, O.me = "Forever" .. rules, "Observer" .. rules .. "-Realm"
			for i = 1, 20 do
				O.rdb.guilds["Olympus Lengthy Guild " .. i] = { total = 50, online = 10, t = O.clock - 60,
					from = "CAMWOWUS1Realm1" .. rules }
			end
			assert(O.Data.RecordGroupCensus())
			local fullBytes = 0
			for _, guild in ipairs(O.Data.GroupGuilds(O.group)) do fullBytes = fullBytes + #guild.name + 24 end
			assert(fullBytes > 4 * O.Codec.CHUNK, "the full detail source originally exceeds the ordinary trickle")
		end
		O.group, O.me = "ForeverPvP", carrier
		for _ = 1, 2 do
			assert(#O.Data.PortablePayload() <= O.Codec.CHUNK, "complete aggregate and partial detail must fit one logical chunk")
		end
		assert(O.Data.SayGroupCensus()); assert(O.Data.SayGroupCensus()); opump(100)
		local R, rdeliver, rsent, _, rpump = extra.RelayWorld(relay .. "-Realm", "Olympus Relay")
		Census(R)
		rdeliver("WHISPER", "Late-Realm", "RL~P~RR~Olympus Late")
		for _, packet in ipairs(osent) do if packet.target == relay then rdeliver("WHISPER", O.me, packet.msg) end end
		rpump(100)
		local L, ldeliver = extra.RelayWorld("Late-Realm", "Olympus Late")
		Census(L)
		local pieces = 0
		for _, packet in ipairs(rsent) do
			if packet.target == "Late" then pieces = pieces + 1; ldeliver("WHISPER", R.me, packet.msg) end
		end
		eq(pieces, R.Relay.REPORTER_RATE, "both two-envelope origins fit the unchanged four-piece budget")
		local all = L.Data.Groups()
		eq(#all.rows, 2, "the second origin cannot strand the first observation mid-transfer")
		for _, row in ipairs(all.rows) do
			eq(row.characters, 1000); eq(row.guilds, 20); eq(row.observed, O.clock - 60)
			eq(row.counted, false, "carriers do not manufacture authenticated originals")
			assert(#L.Data.GroupGuilds(row.group) < 20, "only explicitly partial guild details fit beside the full aggregate")
		end
		eq(L.Data.Summary().characters, 0)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

test("census scope relay: a multi-part scoped snapshot survives the relay fanout and restores an empty reporter", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local function Census(N)
			N.group, N.faction, N.db = "ForeverPvP", "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function() return true end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.Comm.Handle("CG", N.Data.ReceiveGlobalCensus)
		end
		local O, odeliver, osent, _, opump = extra.RelayWorld("Original-Realm", "Olympus II")
		local relay = O.Relay.Pick()
		odeliver("WHISPER", relay .. "-Realm", "RY~")
		Census(O)
		local total = 0
		for i = 1, 12 do
			O.rdb.guilds["Olympus Origin Guild " .. i] = { total = 50 + i, online = 10, t = O.clock - 60, from = "CAMWOWUS1Realm8PvP" }
			total = total + 50 + i
		end
		assert(#O.Data.GlobalCensusPayload() > O.Codec.CHUNK, "exercise several independently relayed chunks")
		assert(O.Data.SendGlobalCensus()); opump(100)
		local R, rdeliver, rsent, _, rpump = extra.RelayWorld(relay .. "-Realm", "Olympus Relay")
		Census(R)
		for _, packet in ipairs(osent) do
			if packet.target == relay then rdeliver("WHISPER", O.me, packet.msg) end
		end
		eq(R.Data.Summary().characters, total, "the receiving relay assembles every original count")
		rdeliver("WHISPER", "Late-Realm", "RL~P~RR~Olympus Late")
		assert(R.Data.SendGlobalCensus()); rpump(100)
		local L, ldeliver = extra.RelayWorld("Late-Realm", "Olympus Late")
		Census(L)
		L.Comm.loginAt = L.clock
		for _, packet in ipairs(rsent) do
			if packet.target == "Late" then ldeliver("WHISPER", R.me, packet.msg) end
		end
		eq(L.Data.Summary().characters, total, "all parts reach the reporter before any local rebuild")
		eq(#L.Data.Summary().guilds, 12); eq(next(L.rdb.guilds), nil)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

-- 1.5.4 (the dev, 2026-11-08: "O censo não tá fazendo a retransmissão dos dados do PVP ... tá na
-- minha conta, para mim mostra os dados, eu olhei a conta do Asmon e de várias outras pessoas, não
-- mostra para ninguém"). Fails before: 1.5.2 left every Forever family out of CX 1 and marked any
-- Forever row it heard unproven, and a carried CX 3 counts only from its own observer, who is on the
-- other family by definition. No client counted another family unless its own account played there;
-- the README's "when a moderator says it" never happened for the launch's families.
test("census family trust: a trusted relay's own look at the other family counts on a client that never played there, through the actual relay; an ordinary carrier's stays reported", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local function Census(N)
			N.faction, N.db = "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function(name)
				local short = ns.ShortName(name or "")
				return short == "Hildryn Payne" or short == "Max Ran" -- two signed councillors
			end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.Comm.Handle("CX", N.Data.ReceiveGroupCensus)
		end
		-- The signed relay's account: one of its PvP characters counted 19 PvP guilds...
		local D, _, dsent, _, dpump = extra.RelayWorld("Pvp Alt-CAMWOWUS1Realm8PvP", "Olympus Relay")
		Census(D)
		D.group = "ForeverPvP"
		local total = 0
		for i = 1, 19 do
			D.rdb.guilds["Olympus Pvp " .. i] = { total = 190 + i, online = 20, t = D.clock - 60, from = "CAMWOWUS1Realm8PvP" }
			total = total + 190 + i
		end
		assert(D.Data.RecordGroupCensus())
		-- ...and it now plays the signed relay on PvE, where a guild's reporter registered with it.
		D.me, D.group, D.rdb.guilds = "Hildryn Payne-CAMWOWUS2Realm1PvE", "ForeverPvE", {}
		D.Relay.HandleIn("WHISPER", "Kay Near-CAMWOWUS2Realm1PvE", "RL~P~RR~Olympus Near")
		for _ = 1, 3 do
			D.Data.SayGroupCensus()
			dpump(100)
			D.clock = D.clock + D.Data.GROUP_SEND_GAP
		end
		local K, kdeliver = extra.RelayWorld("Kay Near-CAMWOWUS2Realm1PvE", "Olympus Near")
		Census(K)
		K.group, K.clock = "ForeverPvE", D.clock
		for _, p in ipairs(dsent) do if tostring(p.target):find("^Kay Near") then kdeliver("WHISPER", D.me, p.msg) end end
		local function PvP(g)
			for _, r in ipairs(g.rows) do if r.group == "ForeverPvP" and r.faction == "Alliance" then return r end end
		end
		local g = K.Data.Groups()
		local row = assert(PvP(g), "the PvP row reaches the PvE reporter through the relay")
		eq(row.characters, total); eq(row.guilds, 19)
		eq(row.counted, true, "a trusted relay's own look counts alone (1.4.0: a moderator's alone)")
		eq(row.src, "relay")
		eq(g.characters, total, "and enters the all-server total"); eq(g.kinds.pvp and g.kinds.pvp.characters, total)
		eq(K.Data.Summary().characters, 0, "it never becomes the PvE census")
		-- An ordinary carrier's newer one-guild look, by CX 1 or CX 3, stays reported: it neither
		-- counts nor replaces the trusted count.
		K.clock = K.clock + 60
		K.Data.ReceiveGroupCensus("CHANNEL", "Plain Carrier-CAMWOWUS2Realm1PvE",
			("CX~1~S~%d~ForeverPvP,Alliance,151,151,1,%d"):format(K.clock, K.clock - 30))
		K.Data.ReceiveGroupCensus("CHANNEL", "Plain Carrier-CAMWOWUS2Realm1PvE",
			("CX~3~S~Other Pvp-CAMWOWUS1Realm6PvP~ForeverPvP~Alliance~151,151,1,%d~"):format(K.clock - 20))
		g = K.Data.Groups()
		row = assert(PvP(g))
		eq(row.characters, total); eq(row.counted, true); eq(g.characters, total)
		-- Another councillor whose own PvP character saw only its own guild: newer, trusted, and still
		-- not the family's count while the 19-guild look counts.
		K.Data.ReceiveGroupCensus("CHANNEL", "Max Ran-CAMWOWUS2Realm1PvE",
			("CX~1~S~%d~ForeverPvP,Alliance,151,151,1,%d"):format(K.clock, K.clock - 10))
		row = assert(PvP(K.Data.Groups()))
		eq(row.characters, total, "a trusted one-guild look does not replace a counted 19-guild look")
		-- The same word from an ordinary sender never counts (the 1.5.2 rule, unchanged).
		local U, udeliver = extra.RelayWorld("Una Far-CAMWOWUS2Realm1PvE", "Olympus Far")
		Census(U)
		U.group, U.clock = "ForeverPvE", K.clock
		U.Church.IsLedgerRelay = function() return false end
		for _, p in ipairs(dsent) do if tostring(p.target):find("^Kay Near") then udeliver("WHISPER", D.me, p.msg) end end
		local u = U.Data.Groups()
		eq(u.characters, 0, "the same words from a sender this client does not trust stay reported")
		eq(assert(PvP(u)).counted, false)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

-- The review of the 1.5.4 candidate, beside the test above: clients of a Forever realm group's PvE
-- family whose Data.lua trusts the two signed councillors, as there.
local function FamilyWorld(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local function Client(me, guild)
			local N = extra.RelayWorld(me, guild)
			N.faction, N.db = "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function(name)
				local short = ns.ShortName(name or "")
				return short == "Hildryn Payne" or short == "Max Ran"
			end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.group = "ForeverPvE"
			return N
		end
		fn(Client)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end
local function PvP(g)
	for _, r in ipairs(g.rows) do if r.group == "ForeverPvP" and r.faction == "Alliance" then return r end end
end
local function Look(N, from, characters, guilds, observed)
	return N.Data.ReceiveGroupCensus("CHANNEL", from,
		("CX~1~S~%d~ForeverPvP,Alliance,%d,%d,%d,%d"):format(N.clock, characters, characters, guilds, observed))
end

-- Fails before: the one-guild look was kept for being newer, and the older 19-guild look was refused
-- for being older, so the family's count was one guild's until a newer full look came.
test("census family trust: a trusted one-guild look of the family heard before an older trusted 19-guild look ends with the 19-guild look counted", function()
	FamilyWorld(function(Client)
		local K = Client("Kay Near-CAMWOWUS2Realm1PvE", "Olympus Near")
		local t0 = K.clock
		Look(K, "Max Ran-CAMWOWUS2Realm1PvE", 151, 1, t0 - 10)
		eq(assert(PvP(K.Data.Groups())).guilds, 1, "alone, the one-guild look is what is held")
		Look(K, "Hildryn Payne-CAMWOWUS2Realm1PvE", 3800, 19, t0 - 600)
		local row = assert(PvP(K.Data.Groups()))
		eq(row.guilds, 19, "the older 19-guild look replaces it"); eq(row.characters, 3800)
		eq(row.counted, true); eq(row.src, "relay")
		K.clock = t0 + 60
		Look(K, "Max Ran-CAMWOWUS2Realm1PvE", 151, 1, K.clock - 5)
		eq(assert(PvP(K.Data.Groups())).guilds, 19, "and the one-guild look, newer again, does not take its place back")
	end)
end)

-- Fails before: the refused look was noted as heard first (groupHeard), which keeps this client from
-- saying any look of the family not newer than it, so the councillor stopped saying its own.
test("census family trust: a councillor's own 19-guild look of the other family is still said after a newer trusted one-guild look of it was refused", function()
	FamilyWorld(function(Client)
		local D = Client("Pvp Alt-CAMWOWUS1Realm8PvP", "Olympus Relay")
		D.group = "ForeverPvP"
		for i = 1, 19 do D.rdb.guilds["Olympus Pvp " .. i] = { total = 190 + i, online = 20, t = D.clock - 60, from = "CAMWOWUS1Realm8PvP" } end
		assert(D.Data.RecordGroupCensus())
		D.me, D.group, D.rdb.guilds = "Hildryn Payne-CAMWOWUS2Realm1PvE", "ForeverPvE", {}
		assert(tostring(D.Data.GroupCensusPayload()):find("~ForeverPvP,Alliance,", 1, true), "its own look is said")
		D.clock = D.clock + 30 * 60
		Look(D, "Max Ran-CAMWOWUS2Realm1PvE", 151, 1, D.clock - 10)
		local row = assert(PvP(D.Data.Groups()))
		eq(row.guilds, 19, "the newer one-guild look is refused"); eq(row.src, "own")
		local said = D.Data.GroupCensusPayload()
		assert(tostring(said):find("~ForeverPvP,Alliance,", 1, true), "and its own 19-guild look is still said: " .. tostring(said))
	end)
end)

-- Fails before: a trusted client said every family row it held in its trusted name, a row it took
-- from someone else as well (in the session it took it in, what it heard kept it quiet; in a later
-- one nothing did), so a forged row it took would travel on as a councillor's own word.
test("census family trust: a councillor that took a row of the family from someone else does not say it, in a later session either", function()
	FamilyWorld(function(Client)
		local D = Client("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus Relay")
		local t0 = D.clock
		Look(D, "Max Ran-CAMWOWUS2Realm1PvE", 3800, 19, t0 - 600)
		local row = assert(PvP(D.Data.Groups()))
		eq(row.counted, true); eq(row.src, "relay", "taken from the other councillor")
		eq(D.Data.GroupCensusPayload(), nil, "not said in its name")
		-- A later session (a reload): the row is still held, and still not said.
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", D)
		D.clock = t0 + 60
		eq(assert(PvP(D.Data.Groups())).src, "relay", "still held")
		eq(D.Data.GroupCensusPayload(), nil, "nor in a later session")
	end)
end)

-- Fails before: on Forever a whisper arrives with the sender's bare name and the relay's client stamps
-- its own sub-realm on the origin (Relay.lua's HandleIn), so a councillor's own look came back to her
-- from her guild's reporter as "Hildryn Payne-<the relay's sub-realm>": past the self check (whole
-- names), trusted by her short name, noted as heard (groupHeard), and her own look was never said
-- again that session (once per login instead of every half hour; a relay's own client is not
-- affected, its origin being ns.me, which Comm drops as an echo). The same echo of her global census
-- snapshot (CG) passed the self check there and its rows were taken as another councillor's.
test("census family trust: a councillor's own look of the other family heard back stamped with the relay's sub-realm is still said again, and her own global snapshot so stamped is taken from nobody", function()
	FamilyWorld(function(Client)
		local D = Client("Pvp Alt-CAMWOWUS1Realm8PvP", "Olympus Relay")
		D.group = "ForeverPvP"
		for i = 1, 19 do D.rdb.guilds["Olympus Pvp " .. i] = { total = 190, online = 10, t = D.clock - 60, from = "CAMWOWUS1Realm8PvP" } end
		assert(D.Data.RecordGroupCensus())
		D.me, D.group, D.rdb.guilds = "Hildryn Payne-CAMWOWUS2Realm1PvE", "ForeverPvE", {}
		D.clock = D.clock + 600
		local said = assert(D.Data.GroupCensusPayload(), "her own look is said")
		eq(D.Data.ReceiveGroupCensus("CHANNEL", "Hildryn Payne-CAMWOWUS2Realm3PvE", said), true, "her own word back, stamped by the relay")
		eq(assert(PvP(D.Data.Groups())).src, "own", "her own look is still her own")
		D.clock = D.clock + 31 * 60
		local again = D.Data.GroupCensusPayload()
		assert(tostring(again):find("~ForeverPvP,Alliance,3610,3610,19,", 1, true), "said again half an hour later: " .. tostring(again))
		-- The same look from the other councillor is his word, and keeps her quiet as before.
		eq(D.Data.ReceiveGroupCensus("CHANNEL", "Max Ran-CAMWOWUS2Realm3PvE", again), true)
		D.clock = D.clock + 31 * 60
		eq(D.Data.GroupCensusPayload(), nil, "another councillor's same look: heard, not said over")
		-- Her own global snapshot back the same way: taken from nobody (before: a row by "Hildryn
		-- Payne-CAMWOWUS2Realm3PvE", as another councillor's word).
		eq(D.Data.ReceiveGlobalCensus("CHANNEL", "Hildryn Payne-CAMWOWUS2Realm3PvE",
			("CG~2~S~%d~ForeverPvE~Alliance~Olympus Near,100,10,30,%d"):format(D.clock, D.clock - 60)), true)
		eq((D.rdb.censusGlobal or {})["olympus near"], nil, "nothing taken from her own echo")
	end)
end)
