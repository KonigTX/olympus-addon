-- 1.5.5: an install that does not fit the game (a player: "an install in the wrong flavor folder
-- changes the counts"; the CurseForge app's installation for Forever's folder left on Classic installs
-- an old Olympus) is told at login and heads /oly bug, and /oly bug carries a bounded debug section:
-- per kind of message in pieces, the relay and the reporter, the census's sources per realm group,
-- the signed lists, the install. No other player's name or data, no BattleTag. Diagnostics.lua,
-- Codec.lua (Codec.PieceStats). Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT, "tests/run.lua hands ROOT to this file")

-- The game and the installed files as fn's world: toc (GetBuildInfo's interface), the TOC versions
-- (C_AddOns.GetAddOnMetadata), the guildmates' versions (Comm.PeerVersions) and the author's released
-- version as Workshop.Behind answers. All put back after.
local function WithInstall(w, fn)
	local saved = { build = GetBuildInfo, addons = C_AddOns, peers = ns.Comm.PeerVersions, behind = ns.Workshop.Behind,
		author = ns.Workshop.AuthorVersion }
	local ok, err = pcall(function()
		GetBuildInfo = function() return w.game or "1.60.1", "70888", "Oct 1 2026", w.toc or 16001 end
		local meta = { Olympus = w.tocVersion or ns.VERSION, Olympus_Arena = w.arena, OlympusSiteAggregate = w.site }
		C_AddOns = setmetatable({ GetAddOnMetadata = function(addon, field)
			if field ~= "Version" then return nil end
			return meta[addon]
		end }, { __index = saved.addons })
		ns.Comm.PeerVersions = function() return w.peers or { [ns.VERSION] = 1 } end
		ns.Workshop.Behind = function() return w.behind end
		ns.Workshop.AuthorVersion = function() return w.behind end
		ns.ResetInstallWarnings()
		fn()
	end)
	GetBuildInfo, C_AddOns, ns.Comm.PeerVersions, ns.Workshop.Behind, ns.Workshop.AuthorVersion =
		saved.build, saved.addons, saved.peers, saved.behind, saved.author
	ns.ResetInstallWarnings()
	if not ok then error(err, 0) end
end
local function Has(list, value) for _, v in ipairs(list) do if v == value then return true end end return false end
local NEWER = "99.0.0" -- (newer than any version this file will run on)

test("1.5.5 install: the interfaces Diagnostics checks are Olympus.toc's Interface line, the same in the arena's and the site reporter's TOC", function()
	local function Interfaces(path)
		for line in io.lines(path) do
			local list = line:match("^## Interface:%s*(.-)%s*$")
			if list then
				local out = {}
				for n in list:gmatch("%d+") do out[#out + 1] = tonumber(n) end
				return out
			end
		end
	end
	local toc = assert(Interfaces(ROOT .. "Olympus/Olympus.toc"))
	eq(#ns.TOC_INTERFACES, #toc, "as many interfaces")
	for i, n in ipairs(toc) do eq(ns.TOC_INTERFACES[i], n, "interface " .. i) end
	for _, other in ipairs({ "Olympus_Arena/Olympus_Arena.toc", "OlympusSiteAggregate/OlympusSiteAggregate.toc" }) do
		local list = assert(Interfaces(ROOT .. other), other)
		eq(table.concat(list, ","), table.concat(toc, ","), other)
	end
end)

test("1.5.5 install: a Forever client this copy lists, its files of one version, nobody newer: no problem, nothing said, /oly bug starts as before", function()
	WithInstall({ toc = 16001, arena = ns.VERSION, site = ns.VERSION .. "-site.1", peers = { [ns.VERSION] = 4, ["1.4.6"] = 2 } }, function()
		local s = ns.Install()
		eq(s.client, "Forever"); eq(s.declared, true); eq(#s.problems, 0, table.concat(s.problems, ","))
		eq(#ns.InstallWarnings(), 0, "nothing said")
		local line = ns.InstallLine()
		assert(line:find("client Forever (toc 16001", 1, true) and line:find("problems: none", 1, true), line)
		local report = ns.BuildBugReport()
		assert(not report:find("INSTALL PROBLEM", 1, true), "no install line on top")
		assert(report:find("\ndebug (1.5.5):\ninstall: client Forever", 1, true), "the debug section, its install line first")
	end)
	-- Era and Anniversary are clients this copy lists too.
	WithInstall({ toc = 11510 }, function() eq(ns.Install().client, "Era"); eq(#ns.Install().problems, 0) end)
	WithInstall({ toc = 20507 }, function() eq(ns.Install().client, "Anniversary"); eq(#ns.Install().problems, 0) end)
end)

test("1.5.5 install: a newer release on two guildmates' clients is told once a session, with the CurseForge app's installation to pick; one guildmate's hello is not enough", function()
	WithInstall({ peers = { [ns.VERSION] = 3, [NEWER] = 1 } }, function()
		eq(#ns.Install().problems, 0, "one hello naming a newer version could be anyone's")
	end)
	WithInstall({ peers = { [ns.VERSION] = 3, [NEWER .. "-mod"] = 5, ["?"] = 4 } }, function()
		eq(#ns.Install().problems, 0, "no release's form, no version")
	end)
	WithInstall({ peers = { [ns.VERSION] = 3, [NEWER] = 2 } }, function()
		local s = ns.Install()
		assert(Has(s.problems, "behind"), "behind"); eq(s.peers, NEWER); eq(s.peersCount, 2)
		local said = ns.InstallWarnings()
		eq(#said, 2)
		eq(said[1], ns.L.INSTALL_BEHIND:format(NEWER, 2, ns.VERSION))
		eq(said[2], ns.L.INSTALL_FLAVOR)
		eq(#ns.InstallWarnings(), 0, "once a session")
		local report = ns.BuildBugReport()
		assert(report:find("^```\nINSTALL PROBLEM: behind %(Olympus " .. ns.VERSION:gsub("%.", "%%.")), report:sub(1, 200))
		assert(ns.InstallLine():find("guild " .. NEWER .. " x2", 1, true), ns.InstallLine())
	end)
	-- The author's released version newer: his own line says so (Workshop), this adds the app's installation.
	WithInstall({ behind = NEWER }, function()
		local said = ns.InstallWarnings()
		eq(#said, 1); eq(said[1], ns.L.INSTALL_FLAVOR)
		assert(ns.InstallLine():find("author " .. NEWER, 1, true), ns.InstallLine())
	end)
end)

test("1.5.5 install: a client this copy does not list, and files of two versions (an arena or a site reporter left from another install), are told and head /oly bug", function()
	WithInstall({ toc = 16200 }, function()
		local s = ns.Install()
		eq(s.client, "Forever"); eq(s.declared, false); assert(Has(s.problems, "toc"))
		local said = ns.InstallWarnings()
		eq(said[1], ns.L.INSTALL_TOC:format(ns.VERSION, "16200")); eq(said[2], ns.L.INSTALL_FLAVOR)
		assert(ns.BuildBugReport():find("INSTALL PROBLEM: toc", 1, true))
		assert(ns.InstallLine():find("listed in Olympus.toc: NO", 1, true))
	end)
	WithInstall({ arena = "1.4.6" }, function()
		assert(Has(ns.Install().problems, "mixed"), "an old arena folder")
		eq(ns.InstallWarnings()[1], ns.L.INSTALL_MIXED:format(ns.VERSION, "1.4.6"))
	end)
	WithInstall({ tocVersion = "1.4.6" }, function() assert(Has(ns.Install().problems, "mixed"), "an old TOC over new files") end)
	WithInstall({ site = "1.4.6-site.1" }, function() assert(Has(ns.Install().problems, "mixed"), "an old site reporter") end)
	WithInstall({ site = ns.VERSION .. "-site.3" }, function() eq(#ns.Install().problems, 0, "the site reporter's own build number") end)
	WithInstall({ tocVersion = ns.VERSION .. "-test.3" }, function() eq(#ns.Install().problems, 0, "an arena test build's TOC (scripts/package.sh --test)") end)
	WithInstall({ arena = ns.VERSION .. "-test.3" }, function() assert(Has(ns.Install().problems, "mixed"), "the arena module's version is ours alone") end)
	-- The message in every language keeps the English one's codes (tests/locales-full.lua checks the rest).
	for _, k in ipairs({ "INSTALL_BEHIND", "INSTALL_TOC", "INSTALL_MIXED", "INSTALL_FLAVOR" }) do
		assert(type(ns.L[k]) == "string" and ns.L[k] ~= k, k)
	end
end)

test("1.5.5 /oly bug debug: per kind of message in pieces, what was put together, dropped incomplete (stale, old) or refused (full, bad, restart)", function()
	local C = ns.Codec
	C.ResetPieceStats()
	local asm, now = C.NewAssembler(), 1000
	-- A list in two pieces, put together.
	eq(C.Feed(asm, "A-Realm", "C1:1:2:CX~1~", now), nil)
	eq(C.Feed(asm, "A-Realm", "C1:2:2:rest", now), "CX~1~rest")
	-- A report whose second and third pieces never come: dropped after a minute (stale).
	eq(C.Feed(asm, "B-Realm", "C2:1:3:R2^Olympus", now), nil)
	-- A piece whose first piece never came: its kind unknown.
	eq(C.Feed(asm, "B-Realm", "C3:2:2:tail", now), nil)
	-- A piece out of bounds, and a first piece of another length under an open id (the pieces before lost).
	eq(C.Feed(asm, "D-Realm", "C4:3:2:LS~x", now), nil)
	eq(C.Feed(asm, "E-Realm", "C5:1:3:WK~a", now), nil)
	eq(C.Feed(asm, "E-Realm", "C5:1:2:WK~b", now), nil)
	-- A sender holding OPEN_PER_SENDER open messages: the next one finds no room.
	for i = 1, C.OPEN_PER_SENDER do C.Feed(asm, "F-Realm", ("C9%d:1:2:H3~%d"):format(i, i), now) end
	eq(C.Feed(asm, "F-Realm", "C99:1:2:H3~full", now), nil)
	C.Gc(asm, now + 61)
	local st = C.PieceStats()
	eq(st.pieces, 8 + C.OPEN_PER_SENDER)
	local k = st.kinds
	eq(k.CX.a, 1); eq(k.CX.p, 2); eq(k.CX.i, 0); eq(k.CX.d, 0)
	eq(k.R2.i, 1, "the report dropped incomplete"); eq(k.R2.p, 1)
	eq(k["?"].i, 1, "the piece whose first never came"); eq(k["?"].d, 1, "and the one out of bounds")
	eq(k.WK.d, 1, "the restarted one"); eq(k.WK.i, 1, "then its new one dropped")
	eq(k.H3.d, 1, "no room"); eq(k.H3.i, C.OPEN_PER_SENDER)
	eq(st.why.stale, 3 + C.OPEN_PER_SENDER); eq(st.why.full, 1); eq(st.why.bad, 1); eq(st.why.restart, 1); eq(st.why.old, nil)
	-- Open longer than ASM_MAX_AGE, its pieces still coming: "old".
	local asm2 = C.NewAssembler()
	C.Feed(asm2, "G-Realm", "C7:1:3:RG~1", now)
	C.Feed(asm2, "G-Realm", "C7:2:3:2", now + C.ASM_MAX_AGE)
	C.Gc(asm2, now + C.ASM_MAX_AGE + 1)
	eq(C.PieceStats().why.old, 1); eq(C.PieceStats().kinds.RG.i, 1)
	-- Bounded: KINDS_MAX kinds, the rest as "other".
	local asm3 = C.NewAssembler()
	for i = 1, C.KINDS_MAX + 10 do C.Feed(asm3, "H" .. i .. "-Realm", ("C1:1:1:%s~"):format(("%02d"):format(i):gsub("%d", function(d) return string.char(65 + tonumber(d)) end)), now) end
	local kinds = 0
	for _ in pairs(C.PieceStats().kinds) do kinds = kinds + 1 end
	eq(kinds, C.KINDS_MAX + 1, "the bounded kinds and other")
	assert(C.PieceStats().kinds.other.a >= 10, "the rest counted as other")
	-- /oly bug's line: the kinds with the most pieces, and the reasons.
	local pieces
	for _, line in ipairs(ns.DebugLines()) do if line:find("^pieces: ") then pieces = line end end
	assert(pieces and pieces:find("why: ", 1, true) and pieces:find("stale=", 1, true), tostring(pieces))
	assert(#pieces <= ns.DEBUG_LINE, "one bounded line")
	C.ResetPieceStats()
end)

test("1.5.5 /oly bug debug: the relay, the reporter, the census's sources per realm group, the signed lists and the secret values left unread; bounded, and no other player's name or BattleTag", function()
	local R, Cm = ns.Relay, ns.Comm
	local saved = { guilds = ns.rdb.guilds, census = ns.db.groupCensus, heard = ns.db.groupHeard, commStats = Cm.Stats,
		check = rawget(_G, "issecretvalue"), relay = R, group = ns.group }
	local ok, err = pcall(function()
		local now = ns.Now()
		ns.group = "ForeverPvE"
		ns.rdb.guilds = {
			["Olympus Far"] = { guild = "Olympus Far", leader = "Faraway Leaderperson", t = now - 90, from = "CAMWOWUS2Realm3PvE", by = "Reporting Personname" },
			["Olympus Near"] = { guild = "Olympus Near", leader = "Nearby Leaderperson", t = now - 7200 },
		}
		ns.db.groupCensus = { ["Alliance|ForeverPvP"] = { group = "ForeverPvP", faction = "Alliance", people = 2000, characters = 2400, observed = now - 3 * 3600 } }
		ns.db.groupHeard = { ["Alliance|ForeverRP"] = { group = "ForeverRP", faction = "Alliance", people = 300, observed = now - 600, by = "Witness Personname" } }
		ns.Relay = setmetatable({ Stats = function()
			return { on = true, relay = "Relaying Personname", sure = true, reporters = 3, pending = 1, out = 4, delivered = 5, dead = 2, dropped = 0, trickled = 7 }
		end, IsRelay = function() return false end, Rules = function() return { rev = 2 } end }, { __index = R })
		Cm.Stats = function() return { isReporter = false, reporter = "Elected Personname", peers = 7, reports = 12, bad = 1, partial = 3 } end
		issecretvalue = function(v) return v == "SECRET" end
		ns.ResetSecretSkips()
		ns.Secret("relay not found", "SECRET")
		local lines = ns.DebugLines()
		local text = table.concat(lines, "\n")
		eq(lines[1], "debug (1.5.5):")
		local size = 0
		for _, line in ipairs(lines) do
			assert(#line <= ns.DEBUG_LINE, "a bounded line: " .. line)
			size = size + #line + 1
		end
		assert(size <= ns.DEBUG_MAX + #"(debug cut)" + 1, "bounded in all: " .. size)
		assert(text:find("relay: picked, answered, relay here: no, reporters 3, pending 1, out 4 delivered 5 dead 2 dropped 0 trickled 7", 1, true), text)
		assert(text:find("reporter: this client no, guild's known yes, guild peers 7, reports heard 12, bad 1, incomplete 3", 1, true), text)
		assert(text:find("census: group ForeverPvE: 2 guild reports, newest 90s, oldest 2h", 1, true), text)
		assert(text:find("by realm CAMWOWUS2Realm3PvE=1 old=1", 1, true), text)
		assert(text:find("census: other groups Alliance|ForeverRP heard 10m (300), Alliance|ForeverPvP look 3h (2000)", 1, true), text)
		assert(text:find("signed: titles ", 1, true) and text:find("relay rules rev 2", 1, true), text)
		assert(text:find("secret values left unread: relay not found=1", 1, true), text)
		-- No other player's name or data: neither the relay's, the reporter's, a leader's nor a witness's.
		for _, name in ipairs({ "Personname", "Leaderperson", "Olympus Far", "Olympus Near" }) do
			assert(not text:find(name, 1, true), "no other player's data: " .. name)
		end
		assert(not text:find("%a#%d%d%d%d"), "no BattleTag")
	end)
	ns.rdb.guilds, ns.db.groupCensus, ns.db.groupHeard, Cm.Stats, issecretvalue, ns.Relay, ns.group =
		saved.guilds, saved.census, saved.heard, saved.commStats, saved.check, saved.relay, saved.group
	ns.ResetSecretSkips()
	if not ok then error(err, 0) end
end)

test("1.5.5 /oly bug debug: the whole section is cut at DEBUG_MAX, said so, and /oly bug still builds when a part fails", function()
	local savedMax, savedLine = ns.DEBUG_MAX, ns.InstallLine
	local ok, err = pcall(function()
		ns.DEBUG_MAX = 120
		local lines = ns.DebugLines()
		eq(lines[#lines], "(debug cut)")
		local size = 0
		for i = 1, #lines - 1 do size = size + #lines[i] + 1 end
		assert(size <= 120, "within the bound: " .. size)
		ns.DEBUG_MAX = savedMax
		ns.InstallLine = function() error("broken") end
		local report = ns.BuildBugReport()
		assert(report:find("\ndebug (1.5.5):\ninstall: ?\n", 1, true), "a part that fails says so, the rest stays")
	end)
	ns.DEBUG_MAX, ns.InstallLine = savedMax, savedLine
	if not ok then error(err, 0) end
end)
