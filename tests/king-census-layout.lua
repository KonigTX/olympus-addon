-- The King's initial Census keeps the guilds before his verification desk. These tests exercise
-- Views.Build, retaining the supplied notice tables and their actions rather than copying them.
local ns, test, eq, h = ...

local function WithCensus(fn)
	h.WithThrone(function(_, K)
		local saved = { verify = ns.Verify, recruit = ns.Recruit, guard = ns.PartyGuard, court = ns.Court,
			hop = ns.Hop, stats = ns.CensusStats, record = ns.Record, evening = ns.Data.Evening,
			rebuilding = ns.Data.Rebuilding, public = ns.Comm.IsPublic, status = ns.Who.StatusLines,
			author = ns.Workshop.AuthorOnline, behind = ns.Workshop.BehindLine, filter = ns.Views.Filter("census") }
		local notice = { text = "Guild verification notice", onClick = function() end }
		local summary = { text = "Guild verification summary", tooltip = function() end }
		local recruit, footer, record = { text = "Recruit request" }, { text = "Version footer" }, { text = "Record mode" }
		local s = { total = 30, characters = 30, online = 3, zones = {}, zoneList = {},
			guilds = {
				{ name = "Olympus II", fresh = true, g = { total = 20, online = 2 } },
				{ name = "Olympus III", fresh = true, g = { total = 10, online = 1 } },
			}, seen = { { name = "Olympus IV", online = 4 } } }
		local ok, err = pcall(function()
			ns.Verify = { Mark = function() return "" end, Lines = function() return { notice, summary } end }
			ns.Recruit = { RequestLines = function() return { recruit } end }
			ns.PartyGuard, ns.Court, ns.Hop, ns.CensusStats = nil, nil, nil, nil
			ns.Record = { Line = function() return record end }
			ns.Data.Evening, ns.Data.Rebuilding = function() end, function() end
			ns.Comm.IsPublic = function() return false end
			ns.Who.StatusLines = function() return { "Who footer" } end
			ns.Workshop.AuthorOnline = function() return false end
			ns.Workshop.BehindLine = function() return footer end
			ns.Views.SetFilter("census", "")
			fn(K, s, notice, summary, recruit, footer, record)
		end)
		ns.Verify, ns.Recruit, ns.PartyGuard, ns.Court = saved.verify, saved.recruit, saved.guard, saved.court
		ns.Hop, ns.CensusStats, ns.Record = saved.hop, saved.stats, saved.record
		ns.Data.Evening, ns.Data.Rebuilding, ns.Comm.IsPublic = saved.evening, saved.rebuilding, saved.public
		ns.Who.StatusLines, ns.Workshop.AuthorOnline, ns.Workshop.BehindLine = saved.status, saved.author, saved.behind
		ns.Views.SetFilter("census", saved.filter)
		if not ok then error(err, 0) end
	end)
end

local function Index(lines, wanted)
	for i, line in ipairs(lines) do if line == wanted then return i end end
end

local function AssertBottom(s, notice, summary, recruit, footer, record)
	local lines = ns.Views.Build("census", s)
	eq(lines[2], record, "record mode retains its place immediately after search")
	local lastGuild, guilds = 0, 0
	for i, line in ipairs(lines) do if line.cols then lastGuild, guilds = i, guilds + 1 end end
	eq(guilds, 3, "every reported and seen guild remains")
	assert(lastGuild < Index(lines, notice), "verification follows every reported and seen guild")
	eq(lines[3], recruit, "requests retain their place above the guilds")
	assert(Index(lines, footer) < Index(lines, notice), "verification is at the bottom, after the status footers")
	eq(lines[#lines - 1], notice, "the original notice and its click action are retained")
	eq(lines[#lines], summary, "the original summary and its tooltip are retained")
end

test("King Census verification: the actual King's notices follow every guild and the footers", function()
	WithCensus(function(K, s, notice, summary, recruit, footer, record)
		h.AsKing()
		eq(K.IsKing(), true); eq(K.Preview(), false)
		AssertBottom(s, notice, summary, recruit, footer, record)
		eq(K.IsKing(), true, "building the Census preserves his actual authority")
	end)
end)

test("King Census verification: Asmon's preview uses the same order without becoming the King", function()
	WithCensus(function(K, s, notice, summary, recruit, footer, record)
		h.AsSoldier("Previewer"); ns.devThrone = true
		eq(K.IsKing(), false); eq(K.Preview(), true)
		AssertBottom(s, notice, summary, recruit, footer, record)
		eq(K.IsKing(), false, "presentation grants no royal authority")
	end)
end)

test("King Census verification: other viewers retain notices above requests and guilds", function()
	WithCensus(function(K, s, notice, summary, recruit)
		h.AsSoldier()
		eq(K.IsKing(), false); eq(K.Preview(), false)
		local lines = ns.Views.Build("census", s)
		eq(lines[3], notice); eq(lines[4], summary); eq(lines[5], recruit)
		for i, line in ipairs(lines) do if line.cols then assert(i > 5, "verification remains above each guild") end end
	end)
end)

test("King Census verification: searching remains guild-only and an empty initial Census keeps its existing notice state", function()
	WithCensus(function(_, s, notice, summary)
		h.AsKing()
		ns.Views.SetFilter("census", "Olympus")
		local lines = ns.Views.Build("census", s)
		eq(Index(lines, notice), nil); eq(Index(lines, summary), nil)
		eq(#lines, 4, "the search box and its three matching guilds")
		ns.Views.SetFilter("census", "")
		s.guilds, s.seen = {}, {}
		ns.Recruit = nil
		lines = ns.Views.Build("census", s)
		for _, line in ipairs(lines) do eq(line.text == ns.Views.Grey(ns.L.EMPTY), false, "notices still prevent a spurious no-reports message") end
		eq(lines[#lines - 1], notice); eq(lines[#lines], summary)
	end)
end)
