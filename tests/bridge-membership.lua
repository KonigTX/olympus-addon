-- The Companion's membership section and the Wanted list's realm (Olympus/BridgeSections.lua,
-- ns.REALM_KIND and ns.RealmPvP in Olympus/Core.lua): the Companion shows a PvP realm group's
-- Wanted list to the PvE realms' players with a line saying it comes from PvP, so both sections
-- carry this character's census realm group and, for a realm Olympus names, whether it is a PvP
-- realm. The launch realms are not known yet, so the table ships empty and pvp is absent for every
-- realm (the relay then falls back to its own list). membership names nobody: it is given before
-- either Accord and outside Olympus, with the faction the Companion pairs with self's character and
-- guild. The Wanted list carries no GUID. Loaded by tests/run.lua.
-- Run alone: luajit tests/run.lua "bridge membership"
local ns, test, eq = ...
local B = OlympusBridge

local NOW = 1800000000

-- fn with this realm, faction, realm kinds and Wanted rows, the clock at NOW, then all as it was.
local function With(o, fn)
	o = o or {}
	local saved = { realm = ns.realm, group = ns.group, faction = ns.faction, me = ns.me, now = ns.Now, api = ns.API,
		kinds = ns.REALM_KIND, pvp = ns.RealmPvP, accord = ns.db.accord, companion = ns.db.companionAccord,
		links = ns.db.links, guildInfo = GetGuildInfo }
	ns.realm, ns.group, ns.faction, ns.me = o.realm or "Realm", o.realm or "Realm", o.faction or "Alliance", "Tester-" .. (o.realm or "Realm")
	ns.Now = function() return NOW end
	ns.db.accord = { v = ns.ACCORD_VERSION, yes = true, at = 0 }
	ns.db.links = o.links
	if o.kinds ~= nil then ns.REALM_KIND = o.kinds end
	ns.API = {
		Wanted = function()
			local rows = {}
			for i = 1, o.wanted or 3 do
				rows[i] = { place = i, name = "Hordie" .. i, guid = ("Player-4619-%08X"):format(i), bounty = 50, kills = 3, cycle = 1,
					victims = { "Victim" }, addedBy = "A Mod" }
			end
			return rows
		end,
	}
	local ok, err = pcall(fn)
	ns.realm, ns.group, ns.faction, ns.me, ns.Now, ns.API = saved.realm, saved.group, saved.faction, saved.me, saved.now, saved.api
	ns.REALM_KIND, ns.RealmPvP, ns.db.accord, ns.db.companionAccord = saved.kinds, saved.pvp, saved.accord, saved.companion
	ns.db.links, GetGuildInfo = saved.links, saved.guildInfo
	if not ok then error(err, 0) end
end

local function Data(name) return assert(B.GetSection(name), name .. ": the section").data end

-- Every string of a section, keys and values, at any depth (to look for what must never be there).
local function Strings(v, out)
	out = out or {}
	if type(v) == "string" then out[#out + 1] = v
	elseif type(v) == "table" then for k, x in pairs(v) do Strings(k, out) Strings(x, out) end end
	return out
end
local function Never(data, needle, what)
	for _, s in ipairs(Strings(data)) do assert(not s:find(needle, 1, true), (what or needle) .. " in " .. s) end
end

test("bridge membership: the realm kinds ship empty, so every realm is unknown until the author names the launch realms", function()
	eq(type(ns.REALM_KIND), "table")
	eq(next(ns.REALM_KIND), nil, "no realm is named yet: the launch realms are not known")
	-- (The beta's realms included: they are no launch realm, and naming them would tell the relay a
	-- realm group's kind from a test realm.)
	for _, realm in ipairs({ "ClassicBetaPvP", "ClassicBetaPvP2", "Realm", "" }) do eq(ns.RealmPvP(realm), nil, realm) end
	eq(ns.RealmPvP(nil), nil); eq(ns.RealmPvP(42), nil)
	With({ kinds = { Bloodmoon = "pvp", Quietvale = "pve", Oddity = "rp" } }, function()
		eq(ns.RealmPvP("Bloodmoon"), true)
		eq(ns.RealmPvP("Quietvale"), false)
		eq(ns.RealmPvP("Oddity"), nil, "a kind it does not know is unknown")
		eq(ns.RealmPvP("bloodmoon"), nil, "the realm's own name, as in Name-Realm")
		ns.REALM_KIND = nil
		eq(ns.RealmPvP("Bloodmoon"), nil, "no table: unknown, no error")
	end)
end)

test("bridge membership: realmGroup, faction and pvp only where the realm is named; never a character, guild or BattleTag", function()
	With({}, function()
		local d = Data("membership")
		eq(d.olympus, true); eq(d.realmGroup, "Realm"); eq(d.faction, "Alliance")
		eq(d.pvp, nil, "an unknown realm: no pvp, the relay's own list decides")
		for k in pairs(d) do
			assert(({ olympus = true, accord = true, realmGroup = true, pvp = true, faction = true })[k], "membership field " .. k)
		end
	end)
	With({ realm = "Bloodmoon", kinds = { Bloodmoon = "pvp" }, links = { Bloodmoon = "Bloodmoon+Ironhold" } }, function()
		local d = Data("membership")
		eq(d.realmGroup, "Bloodmoon+Ironhold", "a linked realm's census group")
		eq(d.pvp, true)
	end)
	With({ realm = "Quietvale", faction = "Horde", kinds = { Quietvale = "pve" } }, function()
		local d = Data("membership")
		eq(d.pvp, false, "a PvE realm says so"); eq(d.faction, "Horde")
	end)
	With({ faction = "Neutral" }, function()
		eq(Data("membership").faction, nil, "only Alliance or Horde")
	end)
	-- It names nobody, so it goes before either Accord and outside Olympus too; after the Companion
	-- Accord it still names nobody (self carries the character and guild, tests/run.lua).
	With({ realm = "Bloodmoon", kinds = { Bloodmoon = "pvp" } }, function()
		ns.db.accord, ns.db.companionAccord = nil, nil
		local d = Data("membership")
		eq(d.olympus, false, "before the Olympus Accord he is no member yet"); eq(d.accord, false)
		eq(d.realmGroup, "Bloodmoon"); eq(d.pvp, true); eq(d.faction, "Alliance")
		ns.db.accord = { v = ns.ACCORD_VERSION, yes = true, at = 0 }
		ns.db.companionAccord = { version = 1, accepted = true, at = 0 }
		GetGuildInfo = function() return "Horde Pals", "Member", 3 end
		d = Data("membership")
		eq(d.olympus, false); eq(d.accord, true); eq(d.pvp, true, "outside Olympus too")
		Never(d, "Tester"); Never(d, "Horde Pals", "the guild"); Never(d, "#", "a BattleTag")
	end)
	-- A realm-kind check that fails leaves pvp out; the rest is whole.
	With({}, function()
		ns.RealmPvP = function() error("boom") end
		local d = Data("membership")
		eq(d.pvp, nil); eq(d.realmGroup, "Realm"); eq(d.olympus, true)
		ns.RealmPvP = function() return "pvp" end
		eq(Data("membership").pvp, nil, "only a true or false counts")
	end)
end)

test("bridge membership: the Wanted list carries its realm group and pvp beside the targets, and never a GUID", function()
	With({ wanted = 3 }, function()
		local d = Data("wanted")
		eq(#d.targets, 3); eq(d.targets[1].name, "Hordie1"); eq(d.targets[1].place, 1)
		eq(d.realmGroup, "Realm"); eq(d.pvp, nil, "an unknown realm: the relay's own list decides")
		for _, t in ipairs(d.targets) do
			eq(t.guid, nil, "no GUID")
			for k in pairs(t) do assert(({ place = true, name = true, bounty = true, kills = true, cycle = true })[k], "target field " .. k) end
		end
		for k in pairs(d) do assert(({ targets = true, realmGroup = true, pvp = true })[k], "wanted field " .. k) end
		Never(d, "Player-4619-", "a GUID"); Never(d, "Victim"); Never(d, "A Mod")
	end)
	With({ realm = "Bloodmoon", kinds = { Bloodmoon = "pvp" }, links = { Bloodmoon = "Bloodmoon+Ironhold" } }, function()
		local d = Data("wanted")
		eq(d.realmGroup, "Bloodmoon+Ironhold"); eq(d.pvp, true, "the PvP realm's list says so")
	end)
	With({ realm = "Quietvale", kinds = { Quietvale = "pve" } }, function()
		eq(Data("wanted").pvp, false)
	end)
	-- Still nothing before the Olympus Accord (1.2.6).
	With({}, function()
		ns.db.accord = nil
		eq(B.GetSection("wanted"), nil)
	end)
end)

-- 1.5.5 (the audit of 11-10): ns.REALM_KIND ships empty, so ns.RealmPvP was nil on every Forever realm
-- and no section said PvP: the Companion could not keep the PvP group's Wanted list and Slayers apart
-- from the PvE group's. A Forever realm names its ruleset (Core.lua's ForeverFamily): PvP and RP-PvP
-- realms are PvP realms, PvE and RP realms are not; the code's table still comes first. The wanted and
-- membership sections carry it, and so do the rankings and each of its Slayers boards, with the realm
-- group (the family). Before: pvp absent everywhere, the rankings and boards with no group at all.
test("bridge membership (1.5.5): a Forever realm's ruleset gives pvp (PvP and RP-PvP true, PvE and RP false, Hardcore unknown); wanted, membership, the rankings and each Slayers board carry the family and pvp", function()
	for realm, want in pairs({ CAMWOWUS2Realm7PvP = true, CAMWOWUS1Realm9RPPvP = true, CAMWOWUS2Realm7PvE = false, CAMWOWEU1Realm3RP = false }) do
		eq(ns.RealmPvP(realm), want, realm)
	end
	eq(ns.RealmPvP("CAMWOWUS1Realm4Hardcore"), nil, "a Hardcore realm: unknown")
	eq(ns.RealmPvP("CAMWOWUS2Realm7"), nil, "no ruleset in its name")
	With({ kinds = { CAMWOWUS2Realm7PvP = "pve" } }, function()
		eq(ns.RealmPvP("CAMWOWUS2Realm7PvP"), false, "the code's table first")
	end)
	-- Each section on a PvP and a PvE character. (The harness's Wanted is Core's stand-in: here a board
	-- of one Slayer each period, as Wanted.Rankings gives it.)
	local function Sections(case)
		With({ realm = case.realm }, function()
			local label = case.realm .. ": "
			local d = Data("wanted")
			eq(d.realmGroup, case.group, label .. "wanted"); eq(d.pvp, case.pvp, label .. "wanted")
			local m = Data("membership")
			eq(m.realmGroup, case.group, label .. "membership"); eq(m.pvp, case.pvp, label .. "membership")
			local r = Data("rankings")
			eq(r.realmGroup, case.group, label .. "rankings"); eq(r.pvp, case.pvp, label .. "rankings")
			local boards = 0
			for _, b in ipairs(r.boards) do
				if b.board == "wanted" then
					boards = boards + 1
					eq(b.realmGroup, case.group, label .. b.period); eq(b.pvp, case.pvp, label .. b.period)
				end
			end
			eq(boards, 2, label .. "this month's and all time's Slayers")
		end)
	end
	local savedWanted = ns.Wanted
	ns.Wanted = { Rankings = function()
		local row = { place = 1, name = "Slayer One-Realm", points = 12, claims = 1 }
		return { month = { row }, all = { row } }
	end }
	local ok, err = pcall(function()
		Sections({ realm = "CAMWOWUS2Realm7PvP", group = "ForeverPvP", pvp = true })
		Sections({ realm = "CAMWOWUS2Realm5PvE", group = "ForeverPvE", pvp = false })
	end)
	ns.Wanted = savedWanted
	if not ok then error(err, 0) end
end)
