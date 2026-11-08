-- 1.5.4: a list of words of one kind as one word (Comm.SendList, the LS envelope), the relay collecting
-- it whole from any origin within bounds and handing it to each reporter whole, every receiver handing
-- its words to their own handler; the Church's public rows reaching every guild (the dev, 2026-11-08:
-- the Church's scores were not counting right for the other guilds).
local ns, test, eq, extra = ...
local RelayWorld, FreshComm, ADDON_DIR, ROOT = extra.RelayWorld, extra.FreshComm, extra.addon, extra.ROOT

-- A relay with a virtual clock and the drip's timers (as tests/relay-fanout.lua runs one).
local function Relayed(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(delay, _, f) timers[#timers + 1] = { at = R.clock + (tonumber(delay) or 0), f = f } end
		local function Run(pumps)
			for _ = 1, pumps do
				R.clock = R.clock + 1.2
				local due, keep = {}, {}
				for _, t in ipairs(timers) do if t.at <= R.clock then due[#due + 1] = t else keep[#keep + 1] = t end end
				timers = keep
				for _, t in ipairs(due) do t.f() end
				R.Comm.Pump()
			end
		end
		fn(R, sent, Run)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end

-- What one reporter could put together from what the relay sent him: each word, and how often.
local function Assembled(R, sent, prefix)
	local outer, inner, got = R.Codec.NewAssembler(), R.Codec.NewAssembler(), {}
	for _, s in ipairs(sent) do
		if s.target and s.target:sub(1, #prefix) == prefix then
			local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
			local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
			local word = body and (body:match("^C%w+:%d+:%d+:") and R.Codec.Feed(inner, "origin", body, 0) or body)
			if word then got[word] = (got[word] or 0) + 1 end
		end
	end
	return got
end

local function Register(R, n)
	for i = 1, n do
		R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
	end
end
local function Reporters(R, sent, n, word)
	local got = 0
	for i = 1, n do
		if Assembled(R, sent, ("Rep Number%d-"):format(i))[word] then got = got + 1 end
	end
	return got
end
-- Rows as the Church's desk sends them (ChurchCount.SendPublic), `n` of them and the list's end;
-- names of letters, as the Church takes them (Church.WireName).
local LETTERS = "abcdefghijklmnopqrstuvwxyz"
local function Rows(n, at, list, salt)
	local rows = {}
	for i = 1, n do rows[i] = ("NR~1~p~%s~%s~%d~Some %s%s~%d~%d"):format(at, list, i, salt or "Name", LETTERS:sub(i, i):rep(2), i * 10, i * 20) end
	rows[n + 1] = ("NR~1~n~%s~%s~%d"):format(at, list, n)
	return rows
end
local function Pieces(R, text, id) return R.Codec.Chunk(text, id) end
local function HandIn(R, origin, text, id)
	for _, p in ipairs(Pieces(R, text, id)) do R.Relay.HandleIn("WHISPER", origin, "RL~P~" .. p) end
end

test("list envelope (1.5.4): pack and unpack round trip, in pieces too; the separator survives Comm's cleaning where the unit separator would not; mixed kinds, a word with the separator, no words, too many, too long, and a list in a list are refused", function()
	local C, Codec = ns.Comm, ns.Codec
	local rows = Rows(21, "abc", "m")
	local text = C.PackList("NR", rows)
	assert(text, "packed")
	eq(text:sub(1, 11), "LS~1~NR~22~")
	eq(Codec.Plain(text), text, "the separator survives Comm's cleaning of every message (Codec.Plain)")
	eq(Codec.Plain("a\30b"), "ab", "(the unit separator is a control byte: it would not)")
	local kind, words = C.UnpackList(text)
	eq(kind, "NR"); eq(#words, 22)
	for i = 1, 22 do eq(words[i], rows[i]) end
	-- In pieces and back, cleaned piece by piece as Comm cleans what arrives.
	local asm, whole = Codec.NewAssembler(), nil
	local pieces = Codec.Chunk(text, "7")
	eq(#pieces >= 4, true, "22 rows take several pieces")
	for _, p in ipairs(pieces) do whole = Codec.Feed(asm, "Some Sender-Realm", Codec.Plain(p), 0) or whole end
	eq(whole, text)
	-- Refused.
	eq(select(2, C.PackList("NR", { "NR~1~a", "NV~1~b" })), "mixed")
	eq(select(2, C.PackList("NR", { "NR~1~a" .. C.LIST_SEP .. "b" })), "separator")
	eq(select(2, C.PackList("NR", {})), "empty")
	eq(select(2, C.PackList("NR", { "NR~1~a", 7 })), "size")
	local many = {}
	for i = 1, C.LIST_MAX + 1 do many[i] = "NR~" .. i end
	eq(select(2, C.PackList("NR", many)), "count")
	many[#many] = nil
	assert(C.PackList("NR", many), "LIST_MAX words pass")
	eq(select(2, C.PackList("NR", { "NR~" .. ("x"):rep(C.LIST_WORD_MAX) })), "size")
	eq(select(2, C.PackList("LS", { "LS~1~a" })), "kind", "never a list in a list")
	eq(select(2, C.PackList("nr", { "nr~1" })), "kind")
	eq(select(2, C.UnpackList("LS~1~NR~3~NR~a" .. C.LIST_SEP .. "NR~b")), "count")
	eq(select(2, C.UnpackList("LS~1~NR~2~NR~a" .. C.LIST_SEP .. "NV~b")), "word")
	eq(select(2, C.UnpackList("LS~1~NR~2~NR~a" .. C.LIST_SEP)), "word", "an empty word")
	eq(select(2, C.UnpackList("LS~1~LS~1~LS~1~a")), "shape")
	eq(select(2, C.UnpackList("LS~1~NR~0~")), "shape")
	eq(select(2, C.UnpackList("LS~1~NR~65~" .. ("NR~a" .. C.LIST_SEP):rep(64) .. "NR~a")), "shape")
end)

test("Comm.SendList (1.5.4): where the channel works each word goes as its own channel message, no list; where the relay carries the channel, one chunked list word to the relay, and the relay's client can put it together", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		-- A realm whose channel works (no relay: Relay.On() false).
		GetChannelName = function() return 5 end
		local cns = FreshComm()
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, target = target } return 0 end
		C_ChatInfo.SendAddonMessageLogged = C_ChatInfo.SendAddonMessage
		cns.Comm.JoinChannel()
		local rows = Rows(3, "abc", "a")
		eq(cns.Comm.ListRoom("NR", rows), 4, "one place each word")
		eq(cns.Comm.SendList("NR", rows), true)
		for _ = 1, 30 do cns.Comm.Pump() end
		local words = {}
		for _, s in ipairs(sent) do
			if s.dist == "CHANNEL" and s.msg:sub(1, 3) == "NR~" then words[#words + 1] = s.msg end
			assert(not s.msg:find("LS~1~", 1, true), "no list word on a working channel: " .. s.msg)
		end
		eq(table.concat(words, "\n"), table.concat(rows, "\n"), "each row as its own message, in order")
		-- Forever: the relay carries the channel.
		GetChannelName = function() return 0 end
		local R, Deliver, rsent = RelayWorld("Church Desk-CAMWOWUS2Realm3PvE", "Olympus II")
		local relay = R.Relay.Pick()
		Deliver("WHISPER", relay .. "-Realm", "RY~")
		rows = Rows(21, "abc", "m")
		local text = R.Comm.PackList("NR", rows)
		eq(R.Comm.ListRoom("NR", rows), #R.Codec.Chunk(text, "0"), "its pieces")
		eq(R.Comm.SendList("NR", rows), true)
		for _ = 1, 60 do R.Comm.Pump() end
		local outer, inner, got, bare = R.Codec.NewAssembler(), R.Codec.NewAssembler(), nil, 0
		for _, s in ipairs(rsent) do
			eq(s.dist, "WHISPER"); eq(s.target, relay)
			if s.msg:find("^RL~P~NR~") then bare = bare + 1 end
			local rl = s.msg:sub(1, 3) == "RL~" and s.msg or R.Codec.Feed(outer, "origin", s.msg, 0)
			local body = rl and rl:match("^RL~P~(.*)$")
			if body then got = R.Codec.Feed(inner, "origin", body, 0) or got end
		end
		eq(bare, 0, "no row goes on its own")
		eq(got, text, "the relay's client puts the one list word together from the origin's pieces")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

-- The Church's desk is no relay: its rows went through each reporter's trickle one by one, keyed by
-- their type, and with 35 reporters a word in pieces never fits an allowance (ToReporters's need).
-- Fails before (no reporter gets the list).
test("relay lists (1.5.4): a list in pieces from a member who is no relay reaches every one of 35 reporters whole, once, as one word wrapped once; Relay.Stats counts it", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 35
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		local text = R.Comm.PackList("NR", Rows(21, "abc", "m"))
		HandIn(R, "Church Desk-CAMWOWUS2Realm3PvE", text, "88")
		Run(600)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		local whole, once, fewest = 0, 0, 0
		local least = math.ceil(#("RM~P~Church Desk-CAMWOWUS2Realm3PvE~" .. text) / R.Codec.CHUNK)
		for i = 1, REPORTERS do
			local prefix = ("Rep Number%d-"):format(i)
			local got = Assembled(R, sent, prefix)[text]
			if got then whole = whole + 1 end
			if got == 1 then once = once + 1 end
			local whispers = 0
			for _, s in ipairs(sent) do if s.target and s.target:sub(1, #prefix) == prefix and s.msg:sub(1, 1) == "C" then whispers = whispers + 1 end end
			if whispers == least then fewest = fewest + 1 end
		end
		eq(whole, REPORTERS, "every reporter can put the list together")
		eq(once, REPORTERS, "once each")
		eq(fewest, REPORTERS, ("in %d full whispers each, the list wrapped once"):format(least))
		local st = R.Relay.Stats()
		eq(st.lists, 1); eq(st.listsRefused, 0); eq(st.listsReplaced, 0)
	end)
end)

-- Fails before (nothing of a member's list reached any reporter).
test("relay lists (1.5.4): cadence: from one origin a list of a kind is admitted once each LIST_EVERY: a second after the first went out is refused and reaches nobody, past LIST_EVERY the next is admitted", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 3
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		local desk = "Church Desk-CAMWOWUS2Realm3PvE"
		local first = R.Comm.PackList("NR", Rows(21, "abc", "m", "A"))
		HandIn(R, desk, first, "11")
		Run(50) -- (60 s: the three batches went, nothing waits)
		eq(Reporters(R, sent, REPORTERS, first), REPORTERS)
		local second = R.Comm.PackList("NR", Rows(21, "abd", "m", "B"))
		HandIn(R, desk, second, "12")
		Run(20)
		eq(Reporters(R, sent, REPORTERS, second), 0, "a second within LIST_EVERY, none of the first waiting: nobody")
		local st = R.Relay.Stats()
		eq(st.lists, 1); eq(st.listsRefused, 1); eq(st.listsReplaced, 0)
		R.clock = R.clock + R.Relay.LIST_EVERY
		Register(R, REPORTERS)
		local third = R.Comm.PackList("NR", Rows(21, "abe", "m", "C"))
		HandIn(R, desk, third, "13")
		Run(50)
		eq(Reporters(R, sent, REPORTERS, third), REPORTERS, "past LIST_EVERY the next list reaches everyone")
		eq(R.Relay.Stats().lists, 2)
	end)
end)

-- Fails before (no bounds: nothing of a member's list reached the drip at all).
test("relay lists (1.5.4): bounds: a second list of a kind from one origin within LIST_EVERY only takes its waiting batches' place; another kind keeps its own window; more than LIST_MAX_PIECES pieces, a list past the whispers LIST_BURST and LIST_RATE allow, and the LIST_OPEN+1th set collecting go through the trickle (nothing, with 35 reporters); Relay.Stats counts each", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 35
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		local desk = "Church Desk-CAMWOWUS2Realm3PvE"
		local first, second = R.Comm.PackList("NR", Rows(21, "abc", "m", "A")), R.Comm.PackList("NR", Rows(21, "abd", "m", "B"))
		HandIn(R, desk, first, "11")
		-- (The first reporter's batch of the first list is in the queue already; every other's waits
		-- in the drip, where the second takes its place: that reporter keeps the first, the rest get
		-- the second alone.)
		HandIn(R, desk, second, "12")
		Run(600)
		local gotFirst, gotSecond, both = Reporters(R, sent, REPORTERS, first), Reporters(R, sent, REPORTERS, second), 0
		for i = 1, REPORTERS do
			local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
			if got[first] and got[second] then both = both + 1 end
		end
		eq(gotFirst, 1, "the one reporter whose batch had begun keeps the first")
		eq(gotSecond, REPORTERS - 1, "every other reporter gets the second in its place")
		eq(both, 0, "nobody gets both")
		local st = R.Relay.Stats()
		eq(st.lists, 1, "one admitted"); eq(st.listsReplaced, 1, "one took its place")
		-- Another kind from the same origin keeps its own window. (The reporters register again, as
		-- every REGISTER_EVERY they do: a registration lasts REPORTER_FOR.)
		Register(R, REPORTERS)
		local other = R.Comm.PackList("X1", (function() local t = {} for i = 1, 30 do t[i] = ("X1~row %d %s"):format(i, ("w"):rep(40)) end return t end)())
		HandIn(R, desk, other, "15")
		Run(600)
		eq(Reporters(R, sent, REPORTERS, other), REPORTERS, "a list of another kind, within the first kind's window, is admitted")
		eq(R.Relay.Stats().lists, 2)
		-- More than LIST_MAX_PIECES: the trickle, which with 35 reporters takes no word in pieces.
		R.clock = R.clock + R.Relay.LIST_EVERY
		Register(R, REPORTERS)
		local big = {}
		for i = 1, 60 do big[i] = ("NR~1~p~abg~m~%d~%s~1~1"):format(i, ("n"):rep(30)) end
		local long = R.Comm.PackList("NR", big)
		eq(#R.Codec.Chunk(long, "0") > R.Relay.LIST_MAX_PIECES, true, "a list past LIST_MAX_PIECES pieces")
		local refused = R.Relay.Stats().listsRefused
		HandIn(R, desk, long, "16")
		Run(300)
		eq(Reporters(R, sent, REPORTERS, long), 0, "too long a list reaches nobody by the drip")
		eq(R.Relay.Stats().listsRefused, refused + 1)
		-- The whispers lists may spend, from everyone together: a list's pieces and one more to each
		-- reporter, out of LIST_BURST a reporter at once (refilled: the clock ran on) and LIST_RATE a
		-- reporter a minute after. Here two lists of four pieces fit the burst, the third does not,
		-- and the minutes its cost takes to refill admit it.
		R.clock = R.clock + 3600
		Register(R, REPORTERS)
		local lists, admitted = {}, R.Relay.Stats().lists
		local pieces = #R.Codec.Chunk(R.Comm.PackList("NR", Rows(21, "ab1", "a", "K")), "0")
		local cost = (pieces + 1) * REPORTERS
		local fit = math.floor(R.Relay.LIST_BURST * REPORTERS / cost)
		eq(fit, 2, ("two lists of %d pieces fit the burst"):format(pieces))
		for k = 1, fit + 1 do
			lists[k] = R.Comm.PackList("NR", Rows(21, "ab" .. k, "a", "K" .. k))
			HandIn(R, ("Desk Number%d-CAMWOWUS2Realm3PvE"):format(k), lists[k], tostring(20 + k))
		end
		eq(R.Relay.Stats().lists - admitted, fit, "the whispers of two lists admitted, the third's not")
		eq(R.Relay.Stats().listsRefused, refused + 2)
		Run(1500)
		local passed = 0
		for k = 1, fit + 1 do
			local n = Reporters(R, sent, REPORTERS, lists[k])
			eq(n == 0 or n == REPORTERS, true, ("list %d: every reporter or none, not %d"):format(k, n))
			if n == REPORTERS then passed = passed + 1 end
		end
		eq(passed, fit, "the admitted lists reach every reporter")
		-- Refilled at LIST_RATE a reporter a minute: the next list once its cost came back.
		R.clock = R.clock + math.ceil(cost / (R.Relay.LIST_RATE * REPORTERS)) * 60 - 1500 * 1.2
		Register(R, REPORTERS)
		local late = R.Comm.PackList("NR", Rows(21, "ab9", "a", "Late"))
		HandIn(R, "Desk Number9-CAMWOWUS2Realm3PvE", late, "29")
		eq(R.Relay.Stats().lists - admitted, fit + 1, "refilled at LIST_RATE, the next list is admitted")
		-- LIST_OPEN sets collecting at once: within an origin's window its lists keep taking the waiting
		-- batches' place (a first piece each opens a set), until LIST_OPEN sets are open. (The budget
		-- refilled for one more list first.)
		R.clock = R.clock + math.ceil(cost / (R.Relay.LIST_RATE * REPORTERS)) * 60
		Register(R, REPORTERS)
		local base = R.Comm.PackList("NR", Rows(21, "ac0", "m", "Z"))
		HandIn(R, desk, base, "40") -- (admitted; its batches wait: nothing pumped)
		local replaced, refusedBefore = R.Relay.Stats().listsReplaced, R.Relay.Stats().listsRefused
		for k = 1, R.Relay.LIST_OPEN + 1 do
			R.Relay.HandleIn("WHISPER", desk, "RL~P~" .. R.Codec.Chunk(R.Comm.PackList("NR", Rows(21, "ac" .. k, "m", "Z")), tostring(40 + k))[1])
		end
		eq(R.Relay.Stats().listsReplaced - replaced, R.Relay.LIST_OPEN - 1, "sets open until LIST_OPEN, the admitted one among them")
		eq(R.Relay.Stats().listsRefused - refusedBefore, 2, "the rest refused")
	end)
end)

-- Fails before (keyed by the piece's id, the older short list went too).
test("relay lists (1.5.4): a list in one piece is one word of the trickle keyed by its kind: a newer short list of the kind takes the waiting one's place in the queue, a list of another kind keeps its own", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 3
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		local desk = "Church Desk-CAMWOWUS2Realm3PvE"
		local older, newer = R.Comm.PackList("NR", Rows(1, "abc", "m", "A")), R.Comm.PackList("NR", Rows(1, "abd", "m", "B"))
		local other = R.Comm.PackList("X1", { "X1~one", "X1~two" })
		eq(#R.Codec.Chunk(older, "0"), 1, "one piece")
		HandIn(R, desk, older, "51")
		HandIn(R, desk, newer, "52")
		HandIn(R, desk, other, "53")
		Run(100)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		eq(Reporters(R, sent, REPORTERS, older), 0, "no reporter is sent the short list the newer one replaced")
		eq(Reporters(R, sent, REPORTERS, newer), REPORTERS, "every reporter gets the newer")
		eq(Reporters(R, sent, REPORTERS, other), REPORTERS, "and the other kind's")
	end)
end)

test("list envelope (1.5.4): a receiver hands a list's words to their handler one by one, as from its sender, and counts them; a list of a kind with no handler, over GUILD, past its bounds, or a list in a list is dropped whole and counted; a client that knows no LS drops it silently", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, Deliver, _, heard = RelayWorld("Listener Here-CAMWOWUS2Realm1PvE", "Olympus II")
		local C = R.Comm
		local words = { "X1~first word", "X1~second word", "X1~third word" }
		Deliver("CHANNEL", "Some Sender-Realm", C.PackList("X1", words))
		eq(#heard, 3)
		for i = 1, 3 do
			eq(heard[i].text, words[i]); eq(heard[i].sender, "Some Sender-Realm"); eq(heard[i].dist, "CHANNEL"); eq(heard[i].logged, false)
		end
		local st = C.Stats()
		eq(st.lists, 1); eq(st.listWords, 3); eq(st.listsBad, 0)
		eq(st.byType["ch:X1"], 3, "the words counted by their kind, as heard one by one")
		-- Dropped whole: a kind with no handler, GUILD, too many words, a word too long, a list in a list,
		-- a count that does not match, a word of another kind.
		local bad = {
			C.PackList("ZZ", { "ZZ~a" }), nil,
			"LS~1~X1~65~" .. ("X1~a" .. C.LIST_SEP):rep(64) .. "X1~a",
			"LS~1~X1~1~X1~" .. ("x"):rep(255),
			"LS~1~LS~1~LS~1~X1~a",
			"LS~1~X1~2~X1~a",
			"LS~1~X1~2~X1~a" .. C.LIST_SEP .. "M1~b",
		}
		Deliver("CHANNEL", "Some Sender-Realm", bad[1])
		Deliver("GUILD", "Some Sender-Realm", C.PackList("X1", words))
		for k = 3, #bad do Deliver("CHANNEL", "Some Sender-Realm", bad[k]) end
		eq(#heard, 3, "nothing more heard")
		st = C.Stats()
		eq(st.lists, 1); eq(st.listWords, 3); eq(st.listsBad, 7)
		-- A failing handler never keeps the other words from theirs.
		C.Handle("X2", function(_, _, text) if text == "X2~bad" then error("boom") end heard[#heard + 1] = { text = text } end)
		Deliver("CHANNEL", "Some Sender-Realm", C.PackList("X2", { "X2~bad", "X2~good" }))
		eq(heard[#heard].text, "X2~good")
		-- A client that knows no LS (1.5.3): the whole word has no handler and is no piece: dropped, no
		-- error, no bad report counted, nothing heard.
		C.Handle("LS", nil)
		local before = C.Stats()
		Deliver("CHANNEL", "Some Sender-Realm", C.PackList("X1", words))
		eq(#heard, 4)
		eq(C.Stats().bad, before.bad); eq(C.Stats().lists, before.lists)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- The Church's public rows over the real relay, with the real ChurchCount at both ends: the desk's
-- keeper (a Church world client whose words leave through a real Comm and Relay as the origin), the
-- signed relay, another guild's reporter (a real Comm and Relay; the Church's handlers his world
-- client's) and his guildmate (the same, hearing the reporter's hand-over to the guild).
---------------------------------------------------------------------------
local function ChurchOverRelay(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, time = GetTime }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus Ember", "Member", 3 end
		local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
		local A1, A2 = "Aldric Vane-Realm", "Bera Stone-Realm"
		local w = World.New({ apostles = { A1, A2 } })
		local author = w:Client(World.AUTHOR)
		local keeper = w:Client(A1)
		local vik = w:Client("Vik Stone", { guild = World.GUILD2 })
		local oda = w:Client("Oda Finch", { guild = World.GUILD2 })
		local wes = w:Client("Wes Brook")
		GetTime = function() return w.clock end
		-- The desk's rankings: ten people showing their row in each (the ledger's shape, Count.Ranking).
		local function Ranking(list)
			local rows = {}
			for i = 1, 10 do
				local name = ("%s %s"):format(list == "a" and "Apostle" or "Missionary", LETTERS:sub(i, i):upper() .. LETTERS:sub(i, i):rep(2))
				rows[i] = { key = World.Key(name), name = name, score = 110 - i * 10, own = 50, pub = true, joins = i, rank = i }
			end
			return rows
		end
		keeper.c.ChurchCount.Ranking = function(list) return Ranking(list) end
		-- Both the desk's words and the relay's hops run on the real Comm and Relay, node by node (each
		-- RelayWorld takes the game's send API: a node is pumped before the next is made).
		local function Node(name, guild)
			local cns, Deliver, sent, _, Pump = RelayWorld(name, guild)
			local timers = {}
			cns.After = function(delay, _, f) timers[#timers + 1] = { at = cns.clock + (tonumber(delay) or 0), f = f } end
			local function Run(pumps)
				for _ = 1, pumps do
					cns.clock = cns.clock + 1.2
					local due, keep = {}, {}
					for _, t in ipairs(timers) do if t.at <= cns.clock then due[#due + 1] = t else keep[#keep + 1] = t end end
					timers = keep
					for _, t in ipairs(due) do t.f() end
					cns.Comm.Pump()
				end
			end
			return cns, Deliver, sent, Run
		end
		-- A world client's Church handlers answer in a real node's Comm, as his client (World:As).
		local function Bridge(node, cl)
			for _, kind in ipairs({ "NR", "NB", "NK" }) do
				node.Comm.Handle(kind, function(dist, sender, text) w:As(cl, cl.handlers[kind], dist, sender, text) end)
			end
		end
		fn(w, World, { author = author, keeper = keeper, vik = vik, oda = oda, wes = wes }, Node, Bridge)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, GetTime = saved.channel, saved.member, saved.guild, saved.inGuild, saved.time
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end
local function PublicRows(w, cl)
	local v = w:As(cl, cl.Count.PublicView)
	if not v then return 0, 0 end
	local a, m = 0, 0
	for _ in pairs(v.a) do a = a + 1 end
	for _ in pairs(v.m) do m = m + 1 end
	return a, m
end
-- The sender's words to the relay, the relay's to the reporter, the reporter's to his guild: fed on.
-- (Outside World:As: a node's Comm sees one guild from its queue to its pump; the bridged Church
-- handlers run as their client.)
local function Carry(from, sent, to, Deliver, dist, target)
	local n = 0
	for _, s in ipairs(sent) do
		if s.dist == dist and (target == nil or ns.ShortName(s.target) == ns.ShortName(target)) then
			n = n + 1
			Deliver(dist, from.me, s.msg)
		end
	end
	return n
end

-- Fails before (f9a4a8e8: the rows went one by one, and the reporter's guild ended with one of them).
test("Church public rows (1.5.4): over the relay, another guild's reporter and his guildmate end with every row of both rankings (10 and 10) in their public view, where the rows one by one left them one to four", function()
	ChurchOverRelay(function(w, World, c, Node, Bridge)
		local keeper, vik, oda = c.keeper, c.vik, c.oda
		-- The desk's words leave as the origin's hop to its relay.
		local KC, KDeliver, Ksent, KRun = Node(keeper.name, World.GUILD)
		local relay = KC.Relay.Pick()
		KDeliver("WHISPER", relay .. "-Realm", "RY~")
		local fake = keeper.c.Comm
		local fakeSend = fake.Send
		fake.SendList = function(kind, words, options) return KC.Comm.SendList(kind, words, options) end
		fake.ListRoom = function(kind, words) return KC.Comm.ListRoom(kind, words) end
		fake.QueueRoom = function() return KC.Comm.QueueRoom() end
		fake.Send = function(dist, msg, key, urgent, logged, done, options)
			-- (A public row on its own, as the desk sent them before 1.5.4: the same way out.)
			if dist == "CHANNEL" and msg:match("^NR~1~[pn]~") then return KC.Comm.Send(dist, msg, key, urgent, logged, done, options) end
			return fakeSend(dist, msg, key, urgent, logged, done, options)
		end
		c.author.online = true
		w:Presence()
		w:Tick()
		w:Act(c.author, c.author.Church.SetPublic, true)
		eq((w:As(vik, vik.Church.Public)), true, "the switch reached the other guild")
		w:Tick()
		eq(#w:Sent(keeper, "NR", "CHANNEL"), 0, "no row went by the world's channel: all by the relay")
		KRun(120)
		eq(KC.Comm.QueueSize(), 0, "the desk's queue emptied")
		-- The relay: Vik registered as his guild's reporter.
		local RN, RDeliver, Rsent, RRun = Node(relay .. "-Realm", "Olympus Relay")
		RN.Relay.HandleIn("WHISPER", vik.name, "RL~P~RR~" .. World.GUILD2)
		eq(Carry(KC, Ksent, RN, RDeliver, "WHISPER", relay) > 0, true, "the desk's whispers reached the relay")
		local rs = RN.Relay.Stats()
		RRun(300)
		eq(RN.Comm.QueueSize(), 0, "the relay's queue emptied")
		-- The reporter, his Church the world's Vik.
		local PC, PDeliver, Psent, PRun = Node(vik.name, World.GUILD2)
		Bridge(PC, vik)
		eq(Carry(RN, Rsent, PC, PDeliver, "WHISPER", vik.name) > 0, true, "the relay's whispers reached the reporter")
		PRun(120)
		local a, m = PublicRows(w, vik)
		eq(a .. "+" .. m, "10+10", ("the reporter's public view holds every row of both rankings: %d+%d"):format(a, m))
		eq(PC.Comm.Stats().listWords, 22, "the reporter's Comm handed the list's 22 words to the Church's handler")
		-- His guildmate, from the hand-over to the guild.
		local GC, GDeliver = Node(oda.name, World.GUILD2)
		Bridge(GC, oda)
		eq(Carry(PC, Psent, GC, GDeliver, "GUILD", nil) > 0, true, "the reporter handed it to his guild")
		a, m = PublicRows(w, oda)
		eq(a .. "+" .. m, "10+10", ("the guildmate's public view holds every row too: %d+%d"):format(a, m))
		local v = w:As(oda, oda.Count.PublicView)
		eq(v.a[1].name, "Apostle Aaa"); eq(v.m[10].name, "Missionary Jjj"); eq(v.m[3].s30, 80); eq(v.m[3].sall, 80)
		eq(tostring(rs.lists) .. "/" .. tostring(rs.listsRefused) .. "/" .. tostring(rs.trickled), "1/0/0", "at the relay: one list admitted, nothing refused or trickled")
	end)
end)

test("Church public rows (1.5.4): a member who is no keeper sends the same rows as a list: the relay carries them, and each receiver's TakePublicRow refuses them as it refused them one by one", function()
	ChurchOverRelay(function(w, World, c, Node, Bridge)
		local vik, wes = c.vik, c.wes
		c.author.online = true
		w:Presence()
		w:Tick()
		w:Act(c.author, c.author.Church.SetPublic, true)
		local _, at = w:As(vik, vik.Church.Public)
		local WC, WDeliver, Wsent, WRun = Node(wes.name, World.GUILD)
		local relay = WC.Relay.Pick()
		WDeliver("WHISPER", relay .. "-Realm", "RY~")
		local rows = Rows(10, ns.Codec.Base36(at), "m", "Fake")
		eq(WC.Comm.SendList("NR", rows), true)
		WRun(120)
		local RN, RDeliver, Rsent, RRun = Node(relay .. "-Realm", "Olympus Relay")
		RN.Relay.HandleIn("WHISPER", vik.name, "RL~P~RR~" .. World.GUILD2)
		Carry(WC, Wsent, RN, RDeliver, "WHISPER", relay)
		RRun(300)
		local PC, PDeliver = Node(vik.name, World.GUILD2)
		Bridge(PC, vik)
		local dropped = w:As(vik, vik.Count.Stats).dropped
		local before = dropped.keeper or 0
		eq(Carry(RN, Rsent, PC, PDeliver, "WHISPER", vik.name) > 0, true, "the list reached the reporter")
		eq(PublicRows(w, vik), 0, "nothing of it in his public view")
		eq(dropped.keeper, before + 11, "each row refused where the rows were always refused: the sender is no keeper")
		eq(PC.Comm.Stats().listWords, 11, "the list's words were handed to the Church's handler")
	end)
end)
