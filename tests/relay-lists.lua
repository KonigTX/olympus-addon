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
local LETTERS2 = "abcdefghijklmnopqrstuvwxyz"
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

-- A guild master's list as Nominees.Parts cuts it, its parts of `size` bytes or so (the relay reads
-- no more than its guild, for its trust).
local function MasterList(guild, rev, parts, salt, size)
	local words = {}
	for i = 1, parts do
		words[i] = ("NM~1~%s~%d~%d~%d~"):format(guild, rev, i, parts) .. ("c=Filler %s;"):format(salt or "Name"):rep(math.floor((size or 150) / 16))
	end
	return words
end
-- The relay's view of who it can trust for a kind (its receivers' own test): the Church's desk a
-- keeper; `masters` proven guild masters.
local function Trusting(R, masters)
	R.Church = { IsKeeper = function(n) return ns.ShortName(n) == "Church Desk" end }
	R.Nominees = { Proven = function(n) return masters ~= nil and masters[ns.ShortName(n)] == true end }
end
local DESK = "Church Desk-CAMWOWUS2Realm3PvE"

-- Fails before (one-piece lists went by the trickle, where nothing holds an origin to one a window).
test("relay lists (1.5.4): cadence: from one origin a list of a kind goes once each LIST_EVERY: a second after the first went out is refused and reaches nobody, past LIST_EVERY the next goes", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 3
		Trusting(R, { ["Garrick Ashby"] = true })
		local GM = "Garrick Ashby-CAMWOWUS2Realm3PvE"
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		local first = R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000000, 1, "A", 60))
		eq(#R.Codec.Chunk(first, "0"), 1, "a list in one piece")
		HandIn(R, GM, first, "11")
		Run(30)
		eq(Reporters(R, sent, REPORTERS, first), REPORTERS)
		local second = R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000001, 1, "B", 60))
		HandIn(R, GM, second, "12")
		Run(20)
		eq(Reporters(R, sent, REPORTERS, second), 0, "a second within LIST_EVERY, none of the first waiting: nobody")
		local st = R.Relay.Stats()
		eq(st.lists, 1); eq(st.listsRefused, 1); eq(st.listsReplaced, 0)
		R.clock = R.clock + R.Relay.LIST_EVERY
		Register(R, REPORTERS)
		local third = R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000002, 1, "C", 60))
		HandIn(R, GM, third, "13")
		Run(30)
		eq(Reporters(R, sent, REPORTERS, third), REPORTERS, "past LIST_EVERY the next list reaches everyone")
		eq(R.Relay.Stats().lists, 2)
	end)
end)

-- Fails before (each of the desk's lists went to every reporter, the census snapshots waiting behind
-- every one of them).
test("relay lists (1.5.4): the Church's rows reach a guild once an hour at most (their kind's hold), the newest when it is due; a guild new to the relay gets the one it holds then", function()
	Relayed(function(R, sent, Run)
		Trusting(R)
		local lists = {}
		for k = 1, 3 do
			R.clock = R.clock + 1800
			Register(R, k == 1 and 3 or 4)
			lists[k] = R.Comm.PackList("NR", Rows(21, "hd" .. k, "m", "Desk" .. LETTERS2:sub(k, k)))
			HandIn(R, DESK, lists[k], tostring(80 + k))
			Run(100)
		end
		for i = 1, 3 do
			local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
			eq(got[lists[1]], 1, "the first")
			eq(got[lists[2]], nil, "not the one half an hour later")
			eq(got[lists[3]], 1, "the newest once the hour passed")
		end
		local got = Assembled(R, sent, "Rep Number4-")
		eq(got[lists[2]], 1, "a guild new to the relay gets the one it holds then")
		eq(got[lists[3]], nil, "and the next one only an hour later")
	end)
end)

-- Fails before (a list of another kind than the Church's was carried from anyone; more than one
-- collecting from an origin each took a place of LIST_OPEN; a trusted origin's had no place past it).
test("relay lists (1.5.4): bounds: a second list of a kind within LIST_EVERY only takes its waiting batches' place; another kind keeps its own window; past LIST_MAX_PIECES the trickle; one collecting from an origin of a kind, LIST_OPEN from origins not trusted, a trusted one's always; a kind not carried whole keeps the trickle; Relay.Stats counts each", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 35
		Trusting(R, { ["Proven Master"] = true })
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		local first, second = R.Comm.PackList("NR", Rows(21, "abc", "m", "A")), R.Comm.PackList("NR", Rows(21, "abd", "m", "B"))
		HandIn(R, DESK, first, "11")
		-- (The first reporter's batch of the first list is in the queue already; every other's waits
		-- in the drip, where the second takes its place: that reporter keeps the first, the rest get
		-- the second alone.)
		HandIn(R, DESK, second, "12")
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
		eq(st.lists, 1, "one taken"); eq(st.listsReplaced, 1, "one took its place")
		-- Another kind (the block terms') from the same origin keeps its own window. (The reporters
		-- register again, as every REGISTER_EVERY they do: a registration lasts REPORTER_FOR.)
		Register(R, REPORTERS)
		local terms = {}
		for i = 1, 30 do terms[i] = ("BW~0badc0de~+term%s@1800000000"):format(("w"):rep(40) .. i) end
		local other = R.Comm.PackList("BW", terms)
		HandIn(R, DESK, other, "15")
		Run(600)
		eq(Reporters(R, sent, REPORTERS, other), REPORTERS, "a list of another kind, within the first kind's window, goes")
		eq(R.Relay.Stats().lists, 2)
		-- More than LIST_MAX_PIECES: the trickle, which with 35 reporters takes no word in pieces.
		R.clock = R.clock + 3600
		Register(R, REPORTERS)
		local big = {}
		for i = 1, 60 do big[i] = ("NR~1~p~abg~m~%d~%s~1~1"):format(i, ("n"):rep(30)) end
		local long = R.Comm.PackList("NR", big)
		eq(#R.Codec.Chunk(long, "0") > R.Relay.LIST_MAX_PIECES, true, "a list past LIST_MAX_PIECES pieces")
		local refused = R.Relay.Stats().listsRefused
		HandIn(R, DESK, long, "16")
		Run(300)
		eq(Reporters(R, sent, REPORTERS, long), 0, "too long a list reaches nobody by the drip")
		eq(R.Relay.Stats().listsRefused, refused + 1)
		-- Collecting: one from an origin of a kind (a newer first piece takes the older's place), then
		-- LIST_OPEN in all from origins the relay cannot trust; a trusted origin's list opens past them.
		local function FirstPiece(who, k)
			local text = R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000000 + k, 3, "N" .. k))
			R.Relay.HandleIn("WHISPER", who, "RL~P~" .. R.Codec.Chunk(text, tostring(60 + k % 900))[1])
		end
		refused = R.Relay.Stats().listsRefused
		for k = 1, 20 do FirstPiece("Some Member-CAMWOWUS2Realm3PvE", k) end
		eq(R.Relay.Stats().listsRefused, refused, "one origin's newer list takes its older one's place: one open")
		for k = 2, R.Relay.LIST_OPEN do FirstPiece(("Some Member%s-CAMWOWUS2Realm3PvE"):format(("abcdefghijklmnopqrstuvwxyz"):sub(k, k)), 100 + k) end
		eq(R.Relay.Stats().listsRefused, refused, ("%d open"):format(R.Relay.LIST_OPEN))
		FirstPiece("Late Member-CAMWOWUS2Realm3PvE", 200)
		eq(R.Relay.Stats().listsRefused, refused + 1, "one more origin not trusted: refused")
		local proven = R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000300, 3, "Pm"))
		HandIn(R, "Proven Master-CAMWOWUS2Realm3PvE", proven, "301")
		eq(R.Relay.Stats().listsRefused, refused + 1, "the proven master's list opens past them")
		Run(600)
		eq(Reporters(R, sent, REPORTERS, proven), REPORTERS, "and reaches every reporter")
		-- A list of a kind the relay does not carry whole: its pieces keep the trickle (none, here).
		local unknown = R.Comm.PackList("X1", (function() local t = {} for i = 1, 20 do t[i] = ("X1~row %d %s"):format(i, ("w"):rep(40)) end return t end)())
		HandIn(R, DESK, unknown, "17")
		Run(300)
		eq(Reporters(R, sent, REPORTERS, unknown), 0, "a list of a kind not carried whole is no list to the relay")
	end)
end)

-- Fails before (keyed by the piece's id, the older short list went too; now as any list in the drip).
test("relay lists (1.5.4): a list in one piece goes by the drip as any list: a newer one takes the waiting batches' place; a list of a kind not carried whole stays a word of the trickle keyed by its kind", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 3
		Trusting(R)
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		local older, newer = R.Comm.PackList("NR", Rows(1, "abc", "m", "A")), R.Comm.PackList("NR", Rows(1, "abd", "m", "B"))
		local other = R.Comm.PackList("X1", { "X1~one", "X1~two" })
		eq(#R.Codec.Chunk(older, "0"), 1, "one piece")
		HandIn(R, DESK, older, "51")
		HandIn(R, DESK, newer, "52")
		HandIn(R, DESK, other, "53")
		Run(100)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		eq(Reporters(R, sent, REPORTERS, older), 1, "the reporter whose batch had begun keeps the older")
		eq(Reporters(R, sent, REPORTERS, newer), REPORTERS - 1, "the others get the newer in its place")
		eq(Reporters(R, sent, REPORTERS, other), REPORTERS, "and the other kind's, by the trickle")
	end)
end)

-- The first cut of 1.5.4 had one share for every list, taken first come: a member's list every few
-- minutes kept the Church desk's longer one out of it. Fails before (neither of the desk's two lists
-- reaches the reporters).
test("relay lists (1.5.4): a member flooding lists of the Church's kind takes only the share of origins the relay cannot trust: the keeper's lists still reach every one of 35 reporters, and the flood a list or two in 70 minutes", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 35
		Trusting(R)
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		local desk, flood, n = {}, {}, 0
		for pump = 1, 3600 do
			if pump % 100 == 1 then Register(R, REPORTERS) end
			if pump % 102 == 1 then
				n = n + 1
				flood[n] = R.Comm.PackList("NR", Rows(8, "fl" .. n, "a", "Flood"))
				HandIn(R, "Flood Member-CAMWOWUS2Realm3PvE", flood[n], tostring(400 + n))
			end
			if pump == 250 or pump == 3400 then -- (more than an hour apart: the Church's hold)
				desk[#desk + 1] = R.Comm.PackList("NR", Rows(21, "dk" .. pump, "m", "Desk"))
				HandIn(R, DESK, desk[#desk], tostring(pump))
			end
			Run(1)
		end
		Run(600)
		eq(#R.Codec.Chunk(flood[1], "0"), 2, "the flood's lists in two pieces")
		eq(Reporters(R, sent, REPORTERS, desk[1]), REPORTERS, "the desk's first list reaches every reporter")
		eq(Reporters(R, sent, REPORTERS, desk[2]), REPORTERS, "and its second")
		local through = 0
		for k = 1, n do if Reporters(R, sent, REPORTERS, flood[k]) > 0 then through = through + 1 end end
		eq(through <= 3, true, ("the flood's %d lists: %d went, within LIST_OTHERS"):format(n, through))
	end)
end)

-- Fails before (the master changing his list every two minutes took the share the other's needed).
test("relay lists (1.5.4): one trusted origin takes its own share of its kind's, never the whole: a guild master changing his list every two minutes leaves room for another master's, repeated as masters do", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 35
		Trusting(R, { ["Garrick Ashby"] = true, ["Selene Moor"] = true })
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		local hers, n = nil, 0
		for pump = 1, 1500 do
			if pump % 100 == 1 then Register(R, REPORTERS) end
			if pump % 102 == 1 then
				n = n + 1
				HandIn(R, "Garrick Ashby-CAMWOWUS2Realm3PvE", R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000000 + n, 2, "G" .. n)), tostring(500 + n))
			end
			if pump >= 500 and pump % 250 == 0 then
				-- (Hers from the tenth minute, repeated every five as a master's client does.)
				hers = hers or R.Comm.PackList("NM", MasterList("Olympus Thorn", 1800000000, 2, "Selene"))
				HandIn(R, "Selene Moor-CAMWOWUS2Realm3PvE", hers, tostring(700 + pump % 99))
			end
			Run(1)
		end
		Run(600)
		eq(Reporters(R, sent, REPORTERS, hers), REPORTERS, "the other master's list reaches every reporter")
	end)
end)

-- Fails before (every repeat went to every reporter again).
test("relay lists (1.5.4): a guild is sent a list it does not hold: an unchanged repeat goes to nobody, a new guild's reporter gets it at the next repeat, a guild whose reporter changed does not get it again, a changed list goes to every guild, and past `refresh` an unchanged one goes again", function()
	Relayed(function(R, sent, Run)
		Trusting(R, { ["Garrick Ashby"] = true })
		local GM = "Garrick Ashby-CAMWOWUS2Realm3PvE"
		local A = R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000000, 2, "A"))
		local B = R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000600, 2, "B"))
		local function Step(text, id, reporters)
			R.clock = R.clock + 600
			Register(R, reporters)
			HandIn(R, GM, text, id)
			Run(100)
		end
		local function Times(word, i) return Assembled(R, sent, ("Rep Number%d-"):format(i))[word] or 0 end
		Step(A, "1", 3)
		for i = 1, 3 do eq(Times(A, i), 1, "the list, once each") end
		Step(A, "2", 3)
		for i = 1, 3 do eq(Times(A, i), 1, "its repeat goes to nobody") end
		eq(R.Relay.Stats().listsSame, 1)
		Step(A, "3", 4)
		eq(Times(A, 4), 1, "a new guild's reporter gets it at the next repeat")
		for i = 1, 3 do eq(Times(A, i), 1, "and nobody else again") end
		-- Guild 1's reporter changes (another member is elected): the guild holds the list already.
		R.Relay.HandleIn("WHISPER", "Other Member-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild 1")
		Step(A, "4", 4)
		eq(Assembled(R, sent, "Other Member-")[A], nil, "a guild whose reporter changed does not get it again")
		R.Relay.HandleIn("WHISPER", "Rep Number1-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild 1")
		Step(B, "5", 4)
		for i = 1, 4 do eq(Times(B, i), 1, "a changed list goes to every guild") end
		R.clock = R.clock + R.Relay.LIST_KINDS.NM.refresh
		Step(B, "6", 4)
		for i = 1, 4 do eq(Times(B, i), 2, "past refresh, an unchanged one goes again") end
	end)
end)

-- Fails before (nothing was kept: after a /reload every guild was sent every list again).
test("relay lists (1.5.4): a relay's /reload keeps which guild holds which list (its saved data): an unchanged repeat goes to nobody, a changed one to every guild", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 3
		Trusting(R, { ["Garrick Ashby"] = true })
		local GM = "Garrick Ashby-CAMWOWUS2Realm3PvE"
		local A = R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000000, 2, "A"))
		local B = R.Comm.PackList("NM", MasterList("Olympus Ember", 1800000600, 2, "B"))
		Register(R, REPORTERS)
		R.clock = R.clock + 120
		HandIn(R, GM, A, "1")
		Run(100)
		-- The /reload: Relay.lua loaded again over the same saved data, its reporters registering again.
		assert(loadfile(ADDON_DIR .. "Relay.lua"))("Olympus", R)
		Trusting(R, { ["Garrick Ashby"] = true })
		R.clock = R.clock + 600
		Register(R, REPORTERS)
		HandIn(R, GM, A, "2")
		Run(100)
		for i = 1, REPORTERS do eq(Assembled(R, sent, ("Rep Number%d-"):format(i))[A], 1, "after the reload, its repeat goes to nobody") end
		R.clock = R.clock + 600
		Register(R, REPORTERS)
		HandIn(R, GM, B, "3")
		Run(100)
		for i = 1, REPORTERS do eq(Assembled(R, sent, ("Rep Number%d-"):format(i))[B], 1, "a changed list to every guild") end
	end)
end)

-- Fails before (the relay's own repeat, the King's Legates every five minutes, went to every reporter
-- each time).
test("relay lists (1.5.4): the relay's own list skips the shares but never goes again to a reporter who holds it", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 3
		local own = R.Comm.PackList("NM", MasterList("Olympus", 1800000000, 3, "Own"))
		local changed = R.Comm.PackList("NM", MasterList("Olympus", 1800000900, 3, "Own"))
		for step, text in ipairs({ own, own, changed }) do
			R.clock = R.clock + 300
			Register(R, REPORTERS)
			HandIn(R, R.me, text, tostring(step))
			Run(100)
		end
		for i = 1, REPORTERS do
			local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
			eq(got[own], 1, "its list once, its repeat to nobody")
			eq(got[changed], 1, "its changed list to every reporter")
		end
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

---------------------------------------------------------------------------
-- 1.5.4 (the dev: "E as nomeações também"): a guild master's nominees and the shared block terms
-- over the real relay, with the real Nominees.lua and Filter.lua where they are said and heard. A
-- node is a real Comm and Relay (RelayWorld), its own drip timers, its guild while it is used, and
-- the game's send API pointed at it while it is pumped.
---------------------------------------------------------------------------
local EMBER, THORN = "Olympus Ember", "Olympus Thorn"
local MASTER, CLAIMANT, EDITOR = "Garrick Ashby-Realm", "Mallory Crane-Realm", "Editor Quill-Realm"
local function OverRelay(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, server = GetServerTime }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetServerTime = function() return 1800000000 end
		local function Node(name, guild, rank, files)
			GetGuildInfo = function() return guild, rank == 0 and "Master" or "Member", rank end
			local cns, Deliver, sent = RelayWorld(name, guild)
			local send, logged = C_ChatInfo.SendAddonMessage, C_ChatInfo.SendAddonMessageLogged
			local timers = {}
			cns.After = function(delay, _, f) timers[#timers + 1] = { at = cns.clock + (tonumber(delay) or 0), f = f } end
			cns.Fire, cns.MasterHeld = function() end, function() return false end
			-- (The census proves MASTER the master of Olympus Ember, nobody else anything.)
			cns.Data = setmetatable({
				KnownRank = function(who, g) if g == EMBER and ns.ShortName(who) == ns.ShortName(MASTER) then return 0, 2 end return nil end,
				Guild = function() return nil end }, { __index = ns.Data })
			cns.IsHighCouncillor = function(n) return type(n) == "string" and ns.ShortName(n) == ns.ShortName(EDITOR) end
			cns.King, cns.WatchChat, cns.Chronicle = { missing = true }, { missing = true }, { Add = function() end }
			for _, file in ipairs(files or {}) do assert(loadfile(ADDON_DIR .. file .. ".lua"))("Olympus", cns) end
			local node = { ns = cns, sent = sent, name = name }
			local function Mine()
				GetGuildInfo = function() return guild, rank == 0 and "Master" or "Member", rank end
				C_ChatInfo.SendAddonMessage, C_ChatInfo.SendAddonMessageLogged = send, logged
			end
			function node.Deliver(dist, from, msg) Mine(); Deliver(dist, from, msg) end
			function node.Do(f, ...) Mine(); return f(...) end
			function node.Run(pumps)
				Mine()
				for _ = 1, pumps do
					cns.clock = cns.clock + 1.2
					local due, keep = {}, {}
					for _, t in ipairs(timers) do if t.at <= cns.clock then due[#due + 1] = t else keep[#keep + 1] = t end end
					timers = keep
					for _, t in ipairs(due) do t.f() end
					cns.Comm.Pump()
				end
			end
			-- What it sent since `since`, fed to `to` as the server would (dist, and the one name for a whisper).
			function node.CarryTo(to, dist, since)
				local n = 0
				for i = (since or 0) + 1, #sent do
					local s = sent[i]
					if s.dist == dist and (dist ~= "WHISPER" or ns.ShortName(s.target) == ns.ShortName(to.name)) then
						n = n + 1
						to.Deliver(dist, name, s.msg)
					end
				end
				return n
			end
			return node
		end
		fn(Node)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, GetServerTime = saved.channel, saved.member, saved.guild, saved.inGuild, saved.server
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end
-- The relay a node picks, answered (RY), as a node of its own that trusts as its receivers do.
local function RelayFor(node, Node)
	local relay = node.ns.Relay.Pick()
	node.Deliver("WHISPER", relay .. "-Realm", "RY~")
	local R = Node(relay .. "-Realm", "Olympus Relay", 3)
	R.ns.Nominees = { Proven = function(n, g) return g == EMBER and ns.ShortName(n) == ns.ShortName(MASTER) end }
	R.ns.Filter = { IsEditorName = function(n) return ns.ShortName(n) == ns.ShortName(EDITOR) end }
	return R
end
local function Named(prefix, i) return prefix .. " " .. LETTERS2:sub(i, i):upper() .. LETTERS2:sub(i, i):rep(2) end

-- Fails before (part by part, the relay's trickle kept one part of the three for the reporter, keyed
-- by their type, and the list never came together anywhere).
test("nominees over the relay (1.5.4): a proven guild master's whole list (25 Legates, 6 correspondents, three parts) reaches another guild's reporter and his guildmate, every entry; the same list from a member who is no master reaches them and is refused there, the master's kept", function()
	OverRelay(function(Node)
		local G = Node(MASTER, EMBER, 0, { "Nominees" })
		local list = {}
		for i = 1, 25 do list[#list + 1] = { r = "c", n = Named("Legate", i) } end
		for i, dept in ipairs(G.ns.Nominees.Departments()) do list[#list + 1] = { r = "d", d = dept, n = Named("Envoy", i) } end
		G.ns.rdb.nominees = { [G.ns.me] = { guild = EMBER, rev = 1800000000, list = list } }
		local parts = G.Do(G.ns.Nominees.Parts, EMBER, 1800000000, (function()
			local out = {}
			for _, e in ipairs(list) do out[#out + 1] = e.r == "c" and { role = "centurion", name = e.n } or { role = "correspondent", dept = e.d, name = e.n } end
			return out
		end)())
		eq(#parts, 3, "the list in three parts")
		local R = RelayFor(G, Node)
		eq(G.Do(G.ns.Nominees.Send, true), true, "the master's client sends his list")
		G.Run(60)
		local P = Node("Rhea Lindgren-Realm", THORN, 3, { "Nominees" })
		R.Do(R.ns.Relay.HandleIn, "WHISPER", P.name, "RL~P~RR~" .. THORN)
		eq(G.CarryTo(R, "WHISPER") > 0, true, "the master's whispers reached the relay")
		R.Run(200)
		eq(R.CarryTo(P, "WHISPER") > 0, true, "the relay's whispers reached the reporter")
		P.Run(60)
		local Q = Node("Tobin Marsh-Realm", THORN, 3, { "Nominees" })
		eq(P.CarryTo(Q, "GUILD") > 0, true, "the reporter handed it to his guild")
		for _, node in ipairs({ P, Q }) do
			local l = node.Do(node.ns.Nominees.ListOf, EMBER)
			eq(l and #l.entries or 0, 31, node.name .. " holds every entry of the master's list")
			eq(node.Do(node.ns.Nominees.RoleOf, Named("Legate", 25), EMBER), "centurion")
			eq(select(2, node.Do(node.ns.Nominees.RoleOf, Named("Envoy", 5), EMBER)), "Department of Heraldry")
		end
		eq(P.ns.Comm.Stats().listWords, 3, "the reporter's Comm handed the list's three parts to Nominees.Handle")
		eq(R.ns.Relay.Stats().lists, 1, "the relay took one list, from its trusted share")
		-- A member of the master's guild sends a list of the same guild: the relay carries it (its
		-- share of origins it cannot trust), each receiver refuses it.
		local M = Node(CLAIMANT, EMBER, 3, { "Nominees" })
		local relay = M.ns.Relay.Pick()
		M.Deliver("WHISPER", relay .. "-Realm", "RY~")
		local fake = M.Do(M.ns.Nominees.Parts, EMBER, 1800000900, { { role = "centurion", name = "Usurper Zed" }, { role = "centurion", name = Named("Legate", 1) } })
		eq(M.Do(M.ns.Comm.SendList, "NM", fake, nil, "nominees"), true)
		M.Run(30)
		local rs, ps = #R.sent, #P.sent
		eq(M.CarryTo(R, "WHISPER") > 0, true)
		R.Run(100)
		eq(R.CarryTo(P, "WHISPER", rs) > 0, true, "the relay carried the member's list too")
		P.Run(30)
		P.CarryTo(Q, "GUILD", ps)
		eq(P.ns.Comm.Stats().listWords, 4, "it reached the reporter's Nominees.Handle")
		for _, node in ipairs({ P, Q }) do
			local l = node.Do(node.ns.Nominees.ListOf, EMBER)
			eq(l and l.by, MASTER, node.name .. " keeps the master's list")
			eq(node.Do(node.ns.Nominees.RoleOf, "Usurper Zed", EMBER), nil, "nothing of the member's")
		end
	end)
end)

-- Fails before (page by page, the reporter kept the page the relay's trickle let through last).
test("block terms over the relay (1.5.4): an editor's whole shared list in five pages (Filter.SendAll) reaches another guild's reporter as one list, every page taken by Filter.Receive as it came", function()
	OverRelay(function(Node)
		local E = Node(EDITOR, EMBER, 3, { "Filter" })
		local shared = {}
		for i = 1, 40 do
			shared["scamword" .. LETTERS2:sub(math.floor((i - 1) / 26) + 1, math.floor((i - 1) / 26) + 1) .. LETTERS2:sub((i - 1) % 26 + 1, (i - 1) % 26 + 1)] =
				{ on = true, at = 1800000000 - 3600, by = "Somebody Else-Realm", lv = 1 }
		end
		E.ns.rdb.filterShared = shared
		local pages = E.Do(E.ns.Filter.Pages)
		eq(#pages, 5, "five pages")
		local R = RelayFor(E, Node)
		eq(E.Do(E.ns.Filter.SendAll), 5)
		E.Run(60)
		local P = Node("Rhea Lindgren-Realm", THORN, 3, { "Filter" })
		R.Do(R.ns.Relay.HandleIn, "WHISPER", P.name, "RL~P~RR~" .. THORN)
		eq(E.CarryTo(R, "WHISPER") > 0, true)
		R.Run(200)
		eq(R.CarryTo(P, "WHISPER") > 0, true)
		eq(#P.Do(P.ns.Filter.SharedTerms), 40, "the reporter holds every term of the editor's list")
		eq(P.ns.Comm.Stats().listWords, 5, "each of the five pages taken as it came")
	end)
end)

-- Fails before (no keys: two lists sent at once both went; a list too long for the relay went as one
-- word it could never carry whole).
test("Comm.SendList (1.5.4): keyed as the words were (word i by key .. i where the channel works, the list word by key where the relay carries it): a newer list takes a waiting one's place; past the relay's LIST_MAX_PIECES the words go one by one, counted, never cut short", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		GetChannelName = function() return 5 end
		local cns = FreshComm()
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, target = target } return 0 end
		C_ChatInfo.SendAddonMessageLogged = C_ChatInfo.SendAddonMessage
		cns.Comm.JoinChannel()
		local older, newer = Rows(3, "abc", "a", "Old"), Rows(3, "abd", "a", "New")
		cns.Comm.SendList("NR", older, nil, "rows")
		cns.Comm.SendList("NR", newer, nil, "rows")
		for _ = 1, 30 do cns.Comm.Pump() end
		local words = {}
		for _, s in ipairs(sent) do if s.dist == "CHANNEL" then words[#words + 1] = s.msg end end
		eq(table.concat(words, "\n"), table.concat(newer, "\n"), "where the channel works: each newer word in its older one's place")
		-- Forever.
		GetChannelName = function() return 0 end
		local R, Deliver, rsent = RelayWorld("Church Desk-CAMWOWUS2Realm3PvE", "Olympus II")
		local relay = R.Relay.Pick()
		Deliver("WHISPER", relay .. "-Realm", "RY~")
		local first, second = Rows(21, "abc", "m", "Old"), Rows(21, "abd", "m", "New")
		R.Comm.SendList("NR", first, nil, "rows")
		R.Comm.SendList("NR", second, nil, "rows")
		for _ = 1, 60 do R.Comm.Pump() end
		local outer, inner, got = R.Codec.NewAssembler(), R.Codec.NewAssembler(), {}
		for _, s in ipairs(rsent) do
			local rl = s.msg:sub(1, 3) == "RL~" and s.msg or R.Codec.Feed(outer, "origin", s.msg, 0)
			local body = rl and rl:match("^RL~P~(.*)$")
			local word = body and R.Codec.Feed(inner, "origin", body, 0)
			if word then got[#got + 1] = word end
		end
		eq(#got, 1, "one list word went")
		eq(got[1], R.Comm.PackList("NR", second), "the newer, in the older's place")
		-- Too long for the relay to carry whole: word by word, every word, counted.
		local big = {}
		for i = 1, 40 do big[i] = ("NR~1~p~abg~m~%d~%s~1~1"):format(i, ("n"):rep(220)) end
		eq(#R.Codec.Chunk(R.Comm.PackList("NR", big), "0") > R.Relay.LIST_MAX_PIECES, true)
		eq(R.Comm.ListRoom("NR", big), 40, "a place for each word")
		local before = #rsent
		eq(R.Comm.SendList("NR", big, nil, "big"), true)
		for _ = 1, 100 do R.Comm.Pump() end
		local each, packed = 0, 0
		for i = before + 1, #rsent do
			local m = rsent[i].msg
			if m:find("^RL~P~NR~1~p~abg~") then each = each + 1 end
			if m:find("LS~1~", 1, true) then packed = packed + 1 end
		end
		eq(each, 40, "every word, one by one"); eq(packed, 0, "no list word")
		eq(R.Comm.Stats().listsSplit, 1, "counted")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)
