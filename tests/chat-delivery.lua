-- 1.5.5 (the dev, 2026-11-10: "only half the chat messages arrive"): every Olympus chat line reaches
-- every member once, through a busy relay, under any of a guildmate's stamps, and a secret chat
-- event never errors. Forged lines are still dropped.
local ns, test, eq, extra = ...

-- A relay with `n` reporters registered (each its own guild), its clock and timers run by hand.
local function BusyRelay(n)
	local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
	local timers = {}
	R.After = function(_, _, fn) timers[#timers + 1] = fn end
	for i = 1, n do
		R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
	end
	local function Run(pumps)
		for _ = 1, pumps do
			R.clock = R.clock + 1.2 -- (one pump each SEND_INTERVAL)
			R.Comm.Pump()
			local due = timers; timers = {}
			for _, fn in ipairs(due) do fn() end
		end
	end
	return R, sent, Run
end

-- The chat lines (M1 bodies) each reporter was whispered, by reporter number.
local function LinesByReporter(R, sent, n)
	local got = {}
	for i = 1, n do got[i] = {} end
	for _, s in ipairs(sent) do
		local i = s.target and tonumber(s.target:match("^Rep Number(%d+)"))
		local body = i and s.msg:match("^RM~L~[^~]+~(M1~.*)$")
		if body then got[i][body] = (got[i][body] or 0) + 1 end
	end
	return got
end

local function WithMember(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		fn()
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end

test("chat delivery (1.5.5): a burst of Olympus chat lines through a relay with 46 reporters reaches every reporter, each line once, while census words keep coming", function()
	WithMember(function()
		local n = 46
		local R, sent, Run = BusyRelay(n)
		local lines = {}
		for k = 1, 4 do
			lines[k] = ("M1~A~Olympus Guild%d~%d~WA~hello army, line %d"):format(k, 100 + k, k)
			R.Relay.HandleIn("WHISPER", ("Speaker Number%d-CAMWOWUS2Realm3PvE"):format(k), "RL~L~" .. lines[k])
			-- Other clients' census words between the lines (the trickle's, keyed: a newer one replaces).
			R.Relay.HandleIn("WHISPER", ("Reporter Census%d-CAMWOWUS2Realm5PvE"):format(k), ("RL~P~X1~census %d"):format(k))
			Run(2)
		end
		Run(3000)
		local got = LinesByReporter(R, sent, n)
		local missing, twice = 0, 0
		for i = 1, n do
			for k = 1, 4 do
				local c = got[i][lines[k]] or 0
				if c == 0 then missing = missing + 1 elseif c > 1 then twice = twice + 1 end
			end
		end
		eq(missing, 0, "no chat line lost for any reporter's guild")
		eq(twice, 0, "and none sent twice")
	end)
end)

test("chat delivery (1.5.5): a reporter whose queue is full of other words still hands every relayed chat line to its guild", function()
	WithMember(function()
		local R, _, sent = extra.RelayWorld("Plain Reporter-CAMWOWUS2Realm7PvE", "Olympus II")
		-- The reporter's queue full of ordinary words (its guild's own, the relay's census trickle).
		for i = 1, R.Comm.MAX_QUEUE - 1 do R.Comm.Send("GUILD", ("X1~word %d"):format(i), nil, false) end
		local line = "M1~A~Olympus Dawn~7~WA~can anyone hear me"
		R.Relay.HandleRelayed("WHISPER", "Max Ran-CAMWOWUS2Realm1PvE", "RM~L~Speaker Far-CAMWOWUS2Realm3PvE~" .. line)
		-- More words after it, every one ordinary: a full queue pushes out its oldest waiting ones.
		for i = 1, R.Comm.MAX_QUEUE do R.Comm.Send("GUILD", ("X1~later %d"):format(i), nil, false) end
		for _ = 1, 400 do R.Comm.Pump() end
		local handed = 0
		for _, s in ipairs(sent) do
			if s.dist == "GUILD" and s.msg == "RG~L~Speaker Far-CAMWOWUS2Realm3PvE~" .. line then handed = handed + 1 end
		end
		eq(handed, 1, "the chat line reached the guild, once")
	end)
end)

-- The addon's own event dispatcher (Core.lua), found by a probe: no other frame's.
local function Dispatcher(probeEvent)
	local hit = false
	ns.RegisterEvent(probeEvent, function() hit = true end)
	for _, f in ipairs(EVENT_SCRIPTS) do
		hit = false
		pcall(f, nil, probeEvent, "probe", "Probe-Realm")
		if hit then return f end
	end
	error("no dispatcher")
end

test("chat delivery (1.5.5): a chat event whose text or sender is a secret value reaches no handler; another secret field reaches them as nil; a plain one as it came", function()
	local savedSecret, savedCapture = rawget(_G, "issecretvalue"), ns.CaptureError
	local ok, err = pcall(function()
		local dispatch = Dispatcher("CHAT_MSG_OLYMPUS_TEST")
		local secret = setmetatable({}, { __index = function() error("a secret value was read") end,
			__len = function() error("a secret value was measured") end, __eq = function() error("a secret value was compared") end })
		issecretvalue = function(v) return rawequal(v, secret) end
		local errors = {}
		ns.CaptureError = function(where, e) errors[#errors + 1] = where .. ": " .. tostring(e) end
		local calls = {}
		ns.RegisterEvent("CHAT_MSG_OLYMPUS_TEST", function(...) calls[#calls + 1] = { n = select("#", ...), ... } end)
		local before = ns.secretChatSkipped
		dispatch(nil, "CHAT_MSG_OLYMPUS_TEST", secret, "Some One-Realm", "", "", "", "", 0, 6, "OlympusNet2")
		dispatch(nil, "CHAT_MSG_OLYMPUS_TEST", "hello", secret, "", "", "", "", 0, 6, "OlympusNet2")
		eq(#calls, 0, "a secret text or sender: no handler called")
		eq(ns.secretChatSkipped - before, 2, "counted for /oly status")
		dispatch(nil, "CHAT_MSG_OLYMPUS_TEST", "hello", "Some One-Realm", "", "", "", "", 0, 6, secret, 0, secret)
		eq(#calls, 1, "a secret GUID or channel name: called")
		eq(calls[1][1], "hello"); eq(calls[1][2], "Some One-Realm"); eq(calls[1][8], 6)
		eq(calls[1][9], nil, "the secret field as nil"); eq(calls[1][11], nil); eq(calls[1][10], 0)
		dispatch(nil, "CHAT_MSG_OLYMPUS_TEST", "plain", "Some One-Realm", "x")
		eq(#calls, 2); eq(calls[2][1], "plain"); eq(calls[2][3], "x")
		-- The game's own non-chat events are passed as they come (a secret there is the handler's).
		local other = {}
		ns.RegisterEvent("OLYMPUS_TEST_OTHER", function(a) other[#other + 1] = a end)
		dispatch(nil, "OLYMPUS_TEST_OTHER", secret)
		eq(#other, 1)
		eq(#errors, 0, table.concat(errors, "; "))
	end)
	issecretvalue, ns.CaptureError = savedSecret, savedCapture
	if not ok then error(err, 0) end
end)

test("chat delivery (1.5.5): the relay's readers of the server's \"No player named\" line leave a secret one unread", function()
	local savedSecret, savedNotFound = rawget(_G, "issecretvalue"), ERR_CHAT_PLAYER_NOT_FOUND_S
	WithMember(function()
		local R = extra.RelayWorld("Plain Reporter-CAMWOWUS2Realm7PvE", "Olympus II")
		ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
		local line = ERR_CHAT_PLAYER_NOT_FOUND_S:format("Max Ran")
		eq(R.Relay.QuietLine(nil, "CHAT_MSG_SYSTEM", line), true, "a plain line for a relay: kept out of the chat")
		local checked = 0
		local ok, err = pcall(function()
			issecretvalue = function(v) if v == line then checked = checked + 1 return true end return false end
			eq(R.Relay.QuietLine(nil, "CHAT_MSG_SYSTEM", line), false, "a secret one: not read, the chat frame shows it as the game's own")
			eq(R.Relay.NotFound(line), false, "not read: no relay left out")
			assert(checked >= 2, "checked for secrecy first: " .. checked)
			issecretvalue = savedSecret
			eq(R.Relay.NotFound(line), true, "the plain line still leaves an offline relay out")
		end)
		issecretvalue, ERR_CHAT_PLAYER_NOT_FOUND_S = savedSecret, savedNotFound
		if not ok then error(err, 0) end
	end)
end)

-- Our guild on Forever: the roster names every member bare, each plays on a sub-realm of his own.
local function ForeverGuild(fn)
	local saved = { total = GetNumGuildMembers, info = GetGuildRosterInfo, guild = GetGuildInfo, member = ns.IsMember,
		realm = ns.realm, group = ns.group, me = ns.me, split = ns.splitNames, chat = ns.db.addonChat, mute = ns.db.chatMute,
		history = ns.rdb.chat }
	local ok, err = pcall(function()
		ns.realm, ns.group, ns.splitNames = "CAMWOWUS2Realm1PvE", "ForeverPvE", true
		ns.me = "Wazizo Thelongone-CAMWOWUS2Realm1PvE"
		ns.IsMember = function() return true end
		GetGuildInfo = function() return "OLYMPUS GODS", "Member", 3 end
		local rows = { { "Wazizo Thelongone", "Member", 3 }, { "Hater Fistinator", "Officer", 1 }, { "Quiet Member", "Member", 3 } }
		GetNumGuildMembers = function() return #rows, #rows end
		GetGuildRosterInfo = function(i)
			local r = rows[i]
			if r then return r[1], r[2], r[3], 60, "Warrior", "Stormwind City", "", "", true, 0, "WARRIOR" end
		end
		ns.Roster.Scan()
		ns.db.addonChat, ns.db.chatMute = true, { A = true } -- (muted: each line kept in the history alone)
		fn()
	end)
	GetNumGuildMembers, GetGuildRosterInfo, GetGuildInfo, ns.IsMember = saved.total, saved.info, saved.guild, saved.member
	ns.realm, ns.group, ns.me, ns.splitNames = saved.realm, saved.group, saved.me, saved.split
	ns.db.addonChat, ns.db.chatMute, ns.rdb.chat = saved.chat, saved.mute, saved.history
	ns.Roster.Scan()
	if not ok then error(err, 0) end
end

test("chat delivery (1.5.5, Forever): guildmates on other sub-realms and under their plain names are shown, one line once under any stamp, our own line once; a stranger claiming our guild is still forged", function()
	ForeverGuild(function()
		local C, Codec = ns.Channels, ns.Codec
		local function Line(id, text) return Codec.EncodeChat("A", "OLYMPUS GODS", id, "WA", text) end
		local function Stat(k) return C.Stats()[k] or 0 end
		local forged, dup = Stat("forged"), Stat("dup")
		-- A player's /oly bug of 2026-11-10 (1.5.3): guildmates' lines "dropped: forged", one of them
		-- under two sub-realm stamps a minute apart.
		local _, why = C.Receive("CHANNEL", "Hater Fistinator-CAMWOWUS1Realm5PvE", Line(4101, "first line from the officer"), 7000)
		eq(why, "muted", "a guildmate stamped with another sub-realm of our family: taken")
		_, why = C.Receive("CHANNEL", "Hater Fistinator-CAMWOWUS2Realm3PvE", Line(4101, "first line from the officer"), 7001)
		eq(why, "dup", "the same line under the relay's stamp: once")
		_, why = C.Receive("CHANNEL", "Hater Fistinator", Line(4101, "first line from the officer"), 7002)
		eq(why, "dup", "and under his plain name: once")
		_, why = C.Receive("CHANNEL", "Quiet Member", Line(4102, "plain name line"), 7003)
		eq(why, "muted", "a guildmate by his plain name: taken")
		_, why = C.Receive("CHANNEL", "Quiet Member-CAMWOWUS1Realm7PvE", Line(4103, "next line"), 7004)
		eq(why, "muted", "his next line under a sub-realm stamp: taken")
		eq(Stat("forged") - forged, 0, "none of them forged")
		-- Not one of us: still forged, on our family's sub-realms and on another family's.
		_, why = C.Receive("CHANNEL", "Fake Officer-CAMWOWUS1Realm5PvE", Line(4104, "I speak for your guild"), 7005)
		eq(why, "forged", "a name our roster does not hold")
		_, why = C.Receive("CHANNEL", "Hater Fistinator-CAMWOWUS1Realm8PvP", Line(4105, "from the PvP family"), 7006)
		eq(why, "forged", "the same name on another realm family is another player")
		eq(Stat("forged") - forged, 2)
		eq(Stat("dup") - dup, 2)
		-- Our own line coming back by the relay under another sub-realm's stamp: shown once, when sent.
		local mine = { ["4106#my own words"] = 7007 }
		local ok, reason = C.Admit("Wazizo Thelongone-CAMWOWUS1Realm5PvE", "OLYMPUS GODS", "my own words", 7008,
			{ tier = "A", id = 4106, mine = mine, seen = {}, buckets = {} })
		eq(ok, false); eq(reason, "own", "our own echo under another stamp")
		eq(C.IsMe("Wazizo Thelongone-CAMWOWUS2Realm7PvE"), true)
		eq(C.IsMe("Wazizo Thelongone-CAMWOWUS1Realm8PvP"), false, "a namesake of another family is not us")
	end)
end)

test("chat delivery (1.5.5): /oly status names the chat windows open beside the ones chosen, so a window \"gone\" can be told apart from one never made", function()
	local saved = { frame = rawget(_G, "ChatFrame3"), info = rawget(_G, "GetChatWindowInfo"), windows = ns.db.chatWindows }
	local ok, err = pcall(function()
		ChatFrame3 = { AddMessage = function() end }
		GetChatWindowInfo = function(i) if i == 3 then return "Trade", 14, 1, 1, 1, 1, true end end
		ns.db.chatWindows = { [ns.me] = { A = "Olympus", C = "Olympus", L = "Olympus" } }
		local line = ns.StatusText():match("chat windows:[^\n]*") or ""
		assert(line:find('[Olympus] "Olympus" ' .. ns.L.CHATWIN_GONE_TAG, 1, true), line)
		assert(line:find('open: "Trade"', 1, true), line)
		ChatFrame3 = nil
		line = ns.StatusText():match("chat windows:[^\n]*") or ""
		assert(line:find("open: the main one alone", 1, true), line)
	end)
	ChatFrame3, GetChatWindowInfo, ns.db.chatWindows = saved.frame, saved.info, saved.windows
	if not ok then error(err, 0) end
end)

test("chat delivery (1.5.5, Forever): another guild's officer and master speak in [Captains] and [Lords] under any sub-realm stamp; their reporters' stamps give one census picture; a plain member of theirs, or another family's namesake, is still no Captain", function()
	ForeverGuild(function()
		local saved, savedInfo, savedMute = ns.rdb.guilds, GetGuildInfo, ns.db.chatMute
		local ok, err = pcall(function()
			ns.rdb.guilds = {}
			GetGuildInfo = function() return "OLYMPUS GODS", "Master", 0 end -- (we read every channel)
			ns.db.chatMute = { A = true, C = true, L = true }
			local function Rep() return { guild = "Olympus Dawn", total = 40, online = 9, zones = {}, leader = "Dawn Master",
				officers = { { name = "Dawn Officer", online = true, days = 0 } } } end
			-- Its reports reach us stamped with their senders' sub-realms (the relay's copies).
			ns.Data.Receive(Rep(), "Dawn Reporter-CAMWOWUS2Realm3PvE")
			ns.Data.Receive(Rep(), "Dawn Witness-CAMWOWUS1Realm5PvE")
			eq(ns.rdb.guilds["Olympus Dawn"].conflict, nil, "one picture, whatever its senders' stamps")
			eq(ns.Data.KnownRank("Dawn Officer-CAMWOWUS2Realm7PvE", "Olympus Dawn"), 1, "his officer under a third stamp")
			eq(ns.Data.KnownRank("Dawn Master-CAMWOWUS1Realm7PvE", "Olympus Dawn"), 0, "his master too")
			eq(ns.Data.KnownRank("Dawn Officer-CAMWOWUS1Realm8PvP", "Olympus Dawn"), nil, "another family's namesake is nobody there")
			eq(ns.Data.KnownRank("Dawn Member-CAMWOWUS2Realm7PvE", "Olympus Dawn"), nil)
			local C, Codec = ns.Channels, ns.Codec
			local function Line(tier, id, text) return Codec.EncodeChat(tier, "Olympus Dawn", id, "WA", text) end
			local _, why = C.Receive("CHANNEL", "Dawn Officer-CAMWOWUS2Realm7PvE", Line("C", 4201, "captains, to me"), 8000)
			eq(why, "muted", "his [Captains] line taken")
			_, why = C.Receive("CHANNEL", "Dawn Master-CAMWOWUS1Realm7PvE", Line("L", 4202, "lords, to me"), 8010)
			eq(why, "muted", "his master's [Lords] line taken")
			_, why = C.Receive("CHANNEL", "Dawn Member-CAMWOWUS2Realm7PvE", Line("C", 4203, "let me in"), 8020)
			eq(why, "unverified", "a member the census names no officer: not in [Captains]")
			_, why = C.Receive("CHANNEL", "Dawn Officer-CAMWOWUS1Realm8PvP", Line("C", 4204, "me too"), 8030)
			eq(why, "unverified", "another family's namesake: not in [Captains]")
		end)
		ns.rdb.guilds, GetGuildInfo, ns.db.chatMute = saved, savedInfo, savedMute
		if not ok then error(err, 0) end
	end)
end)
