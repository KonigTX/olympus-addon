-- The Companion's people sections (Olympus/BridgePeople.lua, and the rankings' boards of
-- Olympus/BridgeSections.lua) on the real modules: the review of 2026-10-20 found every module in
-- tests/bridge-people.lua a stand-in, so a field a module gives in another type (ArenaLedger.History's
-- `title`, a boolean, beside the events' text in the games' `title`) was never seen. Here the bridge's
-- three files are loaded, as the TOC orders them, into a client of the test world with the Arena's
-- own files (tests/arena/lib/world.lua), the Wanted board and the API (as tests/arena/api.lua loads
-- them); and into a client of the Church's world (tests/church-world.lua) with the Church's own files.
-- A public title fight and a Church missionary, then each section's shape: its fields and their
-- types as these modules give them. Caps, audiences and private fields:
-- tests/bridge-people.lua. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local BRIDGE = { "Bridge", "BridgeSections", "BridgePeople" }

-- Each row's fields, empty ones too.
local function Fields(row) local out = {} for f in (row .. "~"):gmatch("(.-)~") do out[#out + 1] = f end return out end
local function Names(fields) local out = {} for f in fields:gmatch("[^~]+") do out[#out + 1] = f end return out end

-- A table's keys all in `allowed`, and each of the type it names ("string", "number", "boolean",
-- "table"); every key `need` names present.
local function Shape(t, allowed, need, what)
	assert(type(t) == "table", what .. ": a table")
	for k, v in pairs(t) do
		local want = allowed[k]
		assert(want, what .. ": field " .. tostring(k))
		eq(type(v), want, what .. "." .. tostring(k))
	end
	for _, k in ipairs(need or {}) do assert(t[k] ~= nil, what .. ": no " .. k) end
end

-- A row string of `fields`: as many fields, each a whole number where `numeric` says so.
local function RowShape(row, fields, numeric, what)
	eq(type(row), "string", what)
	local f, names = Fields(row), Names(fields)
	eq(#f, #names, what .. ": " .. row)
	for i, name in ipairs(names) do
		if numeric[name] and f[i] ~= "" then assert(f[i]:match("^%d+$"), what .. "." .. name .. ": " .. f[i]) end
	end
	return f
end

---------------------------------------------------------------------------
-- The bridge on a client of the Arena's world
---------------------------------------------------------------------------

-- The bridge's files (and, first, the Wanted board and the API) into client c: its own
-- OlympusBridge and OlympusAPI (Bridge.lua's `OlympusBridge or {}` would take the harness's
-- registry), kept as that client's globals; the harness's never touched.
local function LoadBridge(w, c)
	c.globals.OlympusBridge, c.globals.OlympusAPI = false, false
	w:As(c, function()
		local ui = rawget(c.ns, "UI")
		rawset(c.ns, "UI", { AddTab = function() end })
		assert(loadfile(H.ADDON_DIR .. "Wanted.lua"))("Olympus", c.ns)
		rawset(c.ns, "UI", ui)
		assert(loadfile(H.ADDON_DIR .. "Locales/APIText.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "API.lua"))("Olympus", c.ns)
		for _, f in ipairs(BRIDGE) do assert(loadfile(H.ADDON_DIR .. f .. ".lua"))("Olympus", c.ns) end
		c.globals.OlympusBridge, c.globals.OlympusAPI = rawget(_G, "OlympusBridge"), rawget(_G, "OlympusAPI")
	end)
	assert(type(c.globals.OlympusBridge) == "table" and c.globals.OlympusBridge ~= rawget(_G, "OlympusBridge"), "the client's own bridge")
end
local function Section(w, c, name)
	return w:As(c, function()
		local s = OlympusBridge.GetSection(name)
		return s and s.data
	end)
end

-- A public fight its signed arbiter judges (opts: title, ...), set, live, A's knockout of B after
-- a known length (ArenaLedger's rated fights), and its grace gone: final on every client. Its fid.
local function PublicFight(w, cast, opts)
	local AF = W3.M(w, cast.arbiter, "ArenaFights")
	local o = { A = cast.A.name, B = cast.B.name, bo = 1 }
	for k, v in pairs(opts or {}) do o[k] = v end
	local fid = assert(AF.New(o))
	assert(AF.Announce(fid))
	w:Run(0)
	W3.M(w, cast.A, "ArenaFights").Accept(fid)
	W3.M(w, cast.B, "ArenaFights").Accept(fid)
	w:Run(0)
	W3.Stand(cast.arbiter, 100, 100); W3.Stand(cast.A, 110, 100); W3.Stand(cast.B, 100, 120)
	W3.Sees(cast.arbiter, { [cast.A] = true, [cast.B] = true })
	assert(AF.Call(fid))
	w:Run(0)
	W3.M(w, cast.A, "ArenaFights").Here(fid)
	W3.M(w, cast.B, "ArenaFights").Here(fid)
	w:Run(1)
	assert(AF.Bell(fid))
	w:Run(0)
	local f = AF.Find("fights", fid)
	w:Run(math.max(0, f.lockAt - w.clock))
	w:Combat(cast.A, true); w:Combat(cast.B, true)
	w:Run(20)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B, cast.spectator }, cast.A, cast.B)
	w:Run(0)
	w:Combat(cast.A, false); w:Combat(cast.B, false)
	w:Run(cast.arbiter.ns.ArenaFights.GRACE_HELD + cast.arbiter.ns.ArenaFights.FINAL_SLACK + 5)
	return fid
end

local EVENT = { kind = "string", id = "string", at = "number", a = "string", b = "string", winner = "string", state = "string",
	title = "string", titleFight = "boolean", count = "number", official = "boolean" }
local GAMES_OWN = { duelsWon = "number", duelsLost = "number", bonesWon = "number", bonesLost = "number", rating = "number",
	duelsPlace = "number", bonesPlace = "number" }
local PROFILE = { name = "string", guild = "string", rank = "string", rankIndex = "number", role = "string", frame = "string",
	title = "string", level = "number", class = "string", race = "string", nickname = "string", honors = "table", titles = "table" }
local HONOUR = { key = "string", title = "string", frame = "boolean", place = "number" }
local BOARD = { board = "string", period = "string", fields = "string", rows = "table", list = "string", own = "table" }
local NUMERIC = { place = true, rating = true, wins = true, losses = true, won = true, games = true, points = true, deliveries = true,
	customers = true, copper = true, claims = true, points10 = true, allTime10 = true }

test("bridge people (real modules): a public title fight on the Arena's own modules: the games' events keep `title` an event's text and flag the title fight as titleFight; every event, his own record, the boards and his profile in the types those modules give", function()
	local w, cast = W3.New()
	for _, c in ipairs(w.clients) do W3.Companion(w, c) end
	local fid = PublicFight(w, cast, { title = true })
	local plain = PublicFight(w, cast)
	-- The King publishes the arena's ranking (ArenaHome.RankingsPublic, every member's Games tab).
	W3.M(w, cast.king, "ArenaHome").SetRankingsPublic(true, "arena")
	w:Run(1)
	local viewer = cast.A
	LoadBridge(w, viewer)
	-- What the module itself gives: the ledger's flag, a boolean, in History's `title`.
	local hist = W3.M(w, viewer, "ArenaLedger").History({ limit = 30, mode = "L" })
	local byFid = {}
	for _, r in ipairs(hist) do byFid[r.fid] = r end
	assert(byFid[fid], "the title fight in the recent public fights")
	eq(byFid[fid].title, true, "ArenaLedger.History: a title fight's `title` is true"); eq(byFid[plain].title, false)

	local games = assert(Section(w, viewer, "games"), "the games' section")
	Shape(games, { at = "number", events = "table", own = "table" }, { "at", "events", "own" }, "games")
	local seen = {}
	for i, e in ipairs(games.events) do
		Shape(e, EVENT, { "kind", "id", "at", "state" }, "games.events[" .. i .. "]")
		seen[e.id] = e
	end
	local titled, other = assert(seen[fid], "the title fight's event"), assert(seen[plain], "the other fight's event")
	eq(titled.kind, "duel"); eq(titled.state, "over"); eq(titled.titleFight, true, "flagged a title fight")
	eq(titled.title, nil, "never the ledger's boolean in place of an event's text")
	eq(other.titleFight, nil, "not a title fight")
	eq(titled.winner, titled.a, "A won")
	Shape(games.own, GAMES_OWN, { "duelsWon", "duelsLost", "bonesWon", "bonesLost" }, "games.own")
	eq(games.own.duelsWon, 2); eq(games.own.duelsLost, 0); eq(games.own.duelsPlace, 1, "the arena's ranking public: his place")
	eq(games.own.bonesWon, 0); eq(games.own.bonesLost, 0, "no Bones game played")

	local rankings = assert(Section(w, viewer, "rankings"), "the rankings' section")
	local arena
	for i, b in ipairs(rankings.boards) do
		Shape(b, BOARD, { "board", "period", "fields", "rows" }, "rankings.boards[" .. i .. "]")
		for j, row in ipairs(b.rows) do RowShape(row, b.fields, NUMERIC, b.board .. " row " .. j) end
		if b.own then Shape(b.own, { place = "number", value = "number" }, { "place" }, b.board .. ".own") end
		if b.board == "arena" then arena = b end
	end
	assert(arena and #arena.rows >= 2, "the arena's board, its two fighters")
	local top = Fields(arena.rows[1])
	eq(top[1], "1"); eq(top[3], "2", "two wins"); eq(top[4], "0")
	eq(arena.own and arena.own.place, 1, "his own place")

	local profile = assert(Section(w, viewer, "profile"), "his profile")
	Shape(profile, PROFILE, { "name", "guild", "rankIndex", "role", "frame", "honors", "titles" }, "profile")
	eq(profile.name, viewer.name); eq(profile.guild, viewer.guild)
	assert(#profile.honors >= 1, "the honours his title fight won him (HonorsNet.Holdings)")
	for i, h in ipairs(profile.honors) do Shape(h, HONOUR, { "key", "frame" }, "profile.honors[" .. i .. "]") end
	for i, t in ipairs(profile.titles) do eq(type(t), "string", "profile.titles[" .. i .. "]") end
	W3.NoErrors(w)
end)

---------------------------------------------------------------------------
-- The bridge on a client of the Church's world
---------------------------------------------------------------------------

local CW = assert(loadfile(H.ROOT .. "tests/church-world.lua"))(H.ns, H.ROOT)

-- The bridge's files into a Church client (its namespace over the harness's): its own registry,
-- the harness's OlympusBridge put back after; GetSection runs as that client with its registry.
local function ChurchBridge(w, cl)
	local was = rawget(_G, "OlympusBridge")
	rawset(_G, "OlympusBridge", nil)
	local ok, err = pcall(function()
		w:As(cl, function()
			for _, f in ipairs(BRIDGE) do assert(loadfile(H.ADDON_DIR .. f .. ".lua"))("Olympus", cl.c) end
		end)
	end)
	local own = rawget(_G, "OlympusBridge")
	rawset(_G, "OlympusBridge", was)
	if not ok then error(err, 0) end
	assert(type(own) == "table" and own ~= was, "the client's own bridge")
	return function(name)
		local before = rawget(_G, "OlympusBridge")
		rawset(_G, "OlympusBridge", own)
		local okGet, s = pcall(w.As, w, cl, own.GetSection, name)
		rawset(_G, "OlympusBridge", before)
		if not okGet then error(s, 0) end
		return s and s.data
	end
end

local PUBLIC_ROW = { list = "string", place = "number", name = "string", points = "number", allTime = "number" }
local CHURCH_OWN = { role = "string", apostle = "string", parent = "string", guild = "string", windows = "table", invitesWeek = "number",
	invitesAll = "number", guildMembers = "number", guildJoins = "number", guildLeaves = "number", registrations = "number", publicRow = "boolean" }
local CHURCH_WINDOW = { window = "string", ownPoints = "number", points = "number", recruits = "number", pending = "number", stays = "number",
	transfers = "number", taken = "number", openRegistrations = "number", network = "number" }

test("bridge people (real modules): a Church missionary on the Church's own modules: the public rows while its ranking is open and his own numbers as his Mine page reads them, in the types those modules give, never a registration's name", function()
	local A1 = "Aldric Vane-Realm"
	local w = CW.New({ apostles = { A1 } })
	local c = { author = w:Client(CW.AUTHOR), a1 = w:Client(A1), m1 = w:Client("Mira Wells"), wes = w:Client("Wes Brook") }
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Run(8 * 3600)
	w:Presence()
	-- A recruit credited to Mira on the desk (Aldric's ledger, as tests/church-count.lua gives one).
	w:As(c.a1, c.a1.Count.MergeIn, "r aa:mira wells", { n = "R Aa", bn = "Mira Wells", g = CW.GUILD, kind = "i", tc = w.clock - 7200,
		tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:Presence()
	w:Tick()
	-- Her row shown, the author opens the public ranking; she registers a friend; her Mine page's ask.
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick()
	w:Act(c.m1, c.m1.Count.Register, "Quiet Friend")
	w:As(c.m1, c.m1.Count.Ask, "me", "a")
	w:Run(30)
	local Get = ChurchBridge(w, c.m1)
	local d = assert(Get("church"), "the Church's section")
	Shape(d, { open = "boolean", public = "table", own = "table" }, { "open", "public", "own" }, "church")
	eq(d.open, true, "the public ranking open")
	assert(#d.public >= 1, "her public row")
	local hers
	for i, r in ipairs(d.public) do
		Shape(r, PUBLIC_ROW, { "list", "place", "name", "points", "allTime" }, "church.public[" .. i .. "]")
		if r.name == "Mira Wells" then hers = r end
	end
	assert(hers, "her row by name, as the page shows it"); eq(hers.list, "missionaries"); eq(hers.place, 1)
	local own = d.own
	Shape(own, CHURCH_OWN, { "role", "windows", "registrations", "publicRow" }, "church.own")
	eq(own.role, "missionary"); eq(own.apostle, "Aldric Vane", "her Apostle, as the page names him")
	eq(own.registrations, 1, "her registration counted"); eq(own.publicRow, true)
	assert(#own.windows >= 1, "the window her ask brought back")
	local all
	for i, n in ipairs(own.windows) do
		Shape(n, CHURCH_WINDOW, { "window", "points" }, "church.own.windows[" .. i .. "]")
		if n.window == "a" then all = n end
	end
	assert(all, "all time's numbers")
	-- Her page's own line: the points of the "s" line (her own and her levels), the "j" line's recruits.
	local lines = w:As(c.m1, c.m1.Count.DetailView, c.m1.name, "a")
	for _, l in ipairs(lines) do
		if l[1] == "s" then eq(all.ownPoints, l[2]); eq(all.points, l[2] + l[3] + l[4] + l[5]) end
		if l[1] == "j" then eq(all.recruits, l[2]); eq(all.pending, l[3]); eq(all.stays, l[4]); eq(all.transfers, l[5]) end
	end
	assert(all.points > 0, "the credited recruit's points")
	for _, s in ipairs({ "Quiet Friend", "R Aa" }) do
		local function Walk(v)
			if type(v) == "string" then assert(not v:find(s, 1, true), "a name of her own list: " .. v)
			elseif type(v) == "table" then for _, x in pairs(v) do Walk(x) end end
		end
		Walk(d)
	end
	-- A plain member: the public rows, no numbers of his own.
	local plain = assert(ChurchBridge(w, c.wes)("church"))
	eq(plain.own, nil, "no Church place: nothing of his own"); eq(#plain.public, #d.public)
end)

---------------------------------------------------------------------------
-- churchRanking (2026-11-09, the author: "Sim, só local"): the whole Church ranking, kept on the
-- computer of the author, the King or a signed High Councillor alone
---------------------------------------------------------------------------

-- The Ranking page's rows for one list and window as this client's tab draws them (ChurchView.Build):
-- { place, name, points } from each row's columns, the gold of his own row taken off.
local function PageRows(w, cl, list, window)
	cl.View.list, cl.View.window, cl.View.page = list, window, "ranking"
	local out = {}
	for _, line in ipairs(w:As(cl, cl.View.Build)) do
		if line.cols and line.player then
			local text = line.cols[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			local place, name = text:match("^(%d+)%.  (.+)$")
			out[#out + 1] = { place = tonumber(place), name = name, points = line.cols[2] }
		end
	end
	return out
end

-- A number as the page prints points: whole, else to the tenth.
local function Printed(v)
	if v == math.floor(v) then return tostring(math.floor(v)) end
	return ("%.1f"):format(v)
end

local RANKING = { at = "number", boards = "table" }
local RANKING_BOARD = { list = "string", window = "string", rows = "table" }
local RANKING_ROW = { place = "number", name = "string", points = "number" }
local LIST_KEY = { apostles = "a", missionaries = "m" }

-- Each board of the section, row for row, is the page's own list and window on that client.
local function SameAsPage(w, cl, d, who)
	Shape(d, RANKING, { "at", "boards" }, who)
	for _, b in ipairs(d.boards) do
		local label = who .. " " .. tostring(b.list) .. " " .. tostring(b.window)
		Shape(b, RANKING_BOARD, { "list", "window", "rows" }, label)
		local page = PageRows(w, cl, assert(LIST_KEY[b.list], label .. ": a list the page has"), b.window)
		eq(#b.rows, #page, label .. ": as many rows as the page")
		for j, r in ipairs(b.rows) do
			Shape(r, RANKING_ROW, { "place", "name", "points" }, label .. " row " .. j)
			eq(r.place, page[j].place, label .. " row " .. j .. ": place")
			eq(r.name, page[j].name, label .. " row " .. j .. ": name")
			eq(Printed(r.points), page[j].points, label .. " row " .. j .. ": points")
		end
	end
end

-- The boards as one text (their lists, windows and rows), to tell two copies apart.
local function BoardsText(d)
	local out = {}
	for _, b in ipairs(d.boards) do
		out[#out + 1] = b.list .. ":" .. b.window
		for _, r in ipairs(b.rows) do out[#out + 1] = ("%d %s %s"):format(r.place, r.name, Printed(r.points)) end
	end
	return table.concat(out, "\n")
end

local function RowOf(d, list, window, name)
	for _, b in ipairs(d.boards) do
		if b.list == list and b.window == window then
			for _, r in ipairs(b.rows) do if r.name == name then return r end end
		end
	end
	return nil
end

test("bridge people (real modules): churchRanking: the whole Church ranking on the author's, the King's and a signed councillor's client, each board row for row as their Ranking page shows it, open or closed to the public; none on another client, nor while moderation hides him or before the Accord; never a recruit's or a registration's name", function()
	local A1, A2 = "Aldric Vane-Realm", "Bera Stone-Realm"
	local w = CW.New({ apostles = { A1, A2 } })
	local c = { author = w:Client(CW.AUTHOR, { view = true }), king = w:Client(CW.KING, { view = true }),
		councillor = w:Client(CW.COUNCILLOR, { view = true }), a1 = w:Client(A1, { view = true }), a2 = w:Client(A2, { view = true }),
		m1 = w:Client("Mira Wells", { view = true }), member = w:Client("Plain Member", { view = true }) }
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Presence()
	-- Credited recruits on every keeper's ledger (tests/church-view.lua's GiveAll): Mira's this week and
	-- three weeks ago, Aldric's this week, so the windows differ.
	local function Credit(by, recruit, hoursAgo)
		for _, k in ipairs({ c.a1, c.a2, c.author }) do
			w:As(k, k.Count.MergeIn, CW.Key(recruit) .. ":" .. CW.Key(by), { n = recruit, bn = H.ns.ShortName(by), g = CW.GUILD, kind = "i",
				tc = w.clock - (hoursAgo + 1) * 3600, tj = w.clock - hoursAgo * 3600, ws = { "wes brook" } }, false)
		end
	end
	Credit("Mira Wells", "R Aa", 1); Credit("Mira Wells", "R Ab", 21 * 24); Credit(A1, "R Ac", 2)
	w:Act(c.m1, c.m1.Count.Register, "Quiet Friend")
	w:Presence()
	w:Tick()
	local get = {}
	for k, cl in pairs(c) do get[k] = ChurchBridge(w, cl) end

	-- The author (a keeper: his own ledger): every board, live.
	local d = assert(get.author("churchRanking"), "the author's client")
	eq(#d.boards, 6, "the Apostles' and the missionaries', this week, the last 30 days and all time")
	eq(d.at, w.clock, "his own numbers are as of now")
	SameAsPage(w, c.author, d, "author")
	local week, all = RowOf(d, "missionaries", "w", "Mira Wells"), RowOf(d, "missionaries", "a", "Mira Wells")
	assert(week and all, "Mira on the missionaries' boards")
	assert(all.points > week.points, "her older recruit counts for all time, not this week")
	assert(RowOf(d, "apostles", "w", "Aldric Vane"), "Aldric on the Apostles' board")
	-- Open or closed to the public: the same whole ranking.
	local closed = BoardsText(d)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick()
	eq(w:As(c.member, c.member.Church.Public), true, "the public ranking open")
	eq(BoardsText(assert(get.author("churchRanking"))), closed, "the same boards while the public ranking is open")
	w:Act(c.author, c.author.Church.SetPublic, false)
	eq(BoardsText(assert(get.author("churchRanking"))), closed, "and closed again")

	-- The King (no ledger of his own): nothing held before his page asked; then the board a keeper
	-- answered his page with, as of that answer.
	d = assert(get.king("churchRanking"), "the King's client")
	eq(#d.boards, 0, "no answer held yet"); eq(d.at, w.clock)
	PageRows(w, c.king, "m", "a")
	w:Run(30)
	d = assert(get.king("churchRanking"))
	eq(#d.boards, 1, "the board his page fetched"); eq(d.boards[1].list, "missionaries"); eq(d.boards[1].window, "a")
	SameAsPage(w, c.king, d, "King")
	assert(RowOf(d, "missionaries", "a", "Mira Wells"), "Mira on it")
	local _, asOf = w:As(c.king, c.king.Count.RankingView, "m", "a")
	eq(d.at, asOf, "as of the keeper's answer")
	w:Run(600)
	eq(assert(get.king("churchRanking")).at, asOf, "still as of that answer, ten minutes on")
	eq(assert(get.author("churchRanking")).at, w.clock, "the author's own: now")

	-- A signed High Councillor: the same, the Apostles' this week.
	PageRows(w, c.councillor, "a", "w")
	w:Run(30)
	d = assert(get.councillor("churchRanking"), "a signed councillor's client")
	eq(#d.boards, 1); eq(d.boards[1].list, "apostles"); eq(d.boards[1].window, "w")
	SameAsPage(w, c.councillor, d, "councillor")
	assert(RowOf(d, "apostles", "w", "Aldric Vane"), "Aldric on it")

	-- Nobody else: an Apostle (a keeper), a missionary, a plain member.
	for _, k in ipairs({ "a1", "a2", "m1", "member" }) do eq(get[k]("churchRanking"), nil, k .. ": nothing") end
	-- Moderation hides the author: nothing; and before the Olympus Accord.
	w.off[c.author.key] = true
	eq(get.author("churchRanking"), nil, "while moderation hides him")
	w.off[c.author.key] = nil
	assert(get.author("churchRanking"), "back once it no longer does")
	rawset(c.author.c, "AccordAccepted", function() return false end)
	eq(get.author("churchRanking"), nil, "before the Olympus Accord")
	rawset(c.author.c, "AccordAccepted", nil)

	-- Never a recruit's or a registration's name.
	for _, k in ipairs({ "author", "king", "councillor" }) do
		local text = BoardsText(assert(get[k]("churchRanking")))
		for _, never in ipairs({ "R Aa", "R Ab", "R Ac", "Quiet Friend" }) do
			assert(not text:find(never, 1, true), k .. ": " .. never)
		end
	end
end)
