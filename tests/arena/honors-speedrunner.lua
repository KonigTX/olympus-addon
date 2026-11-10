-- 1.5.5 (the owner's call): the level race is off. HonorsNet.LEVEL_RACE_LAUNCHED ships false (its code and
-- the saved book stay, dormant); its bronze and silver comets are retired: never held, shown or worn again,
-- a pick that wore one falls back; whoever was told of a comet, remembered one or wore one gets the race's
-- apology once; and the Olympus Speedrunner, the character the author's signed titles list names in a
-- ^speedrunner^ entry, holds the gold comet (level-race-60) and its title with the race off and no arena
-- data: the King's letter once, frame and title worn unless his pick is locked. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local APOLOGY = "apology@level-race"

local function Kept(w, c)
	w:Logout(c)
	w:Login(c)
	W3.Rules(w, c)
	return c
end
local function Find(held, key)
	for _, h in ipairs(held or {}) do if h.key == key then return h end end
	return nil
end
-- The letters kept in his profile for `key`.
local function Count(c, key)
	local n = 0
	for _, x in ipairs(c.ns.HonorsNet.Letters()) do if x.key == key then n = n + 1 end end
	return n
end
-- The signed titles list's word as ns.SignedPins reads it from a list this client took (the signed path
-- itself: tests/launch-identity.lua; the signer's: tests/launch-sign.sh): its entries' text.
local function Pins(c, text)
	local pins = c.ns.ReadPins(text)
	rawset(c.ns, "SignedPins", function() return pins end)
end
-- A world (the release's switch as it ships) whose clients hold that list from their files' loading on,
-- before INIT and LOGIN, as a list kept in the saved variables is (W3.LevelRaceWorld's way); a reload
-- gets it again.
local function ListWorld(text, opts)
	local w = World.New(opts)
	local as, seen = w.As, {}
	local function Loaded(c, ...)
		c = type(c) == "table" and c or w:Find(c)
		local core = c and c.ns
		if type(core) == "table" and seen[c] ~= core and type(rawget(core, "ReadPins")) == "function" then
			seen[c] = core
			Pins(c, text)
		end
		return ...
	end
	function w:As(c, fn, ...) return Loaded(c, as(self, c, fn, ...)) end
	return w
end

print("HonorsNet: the level race off, the Olympus Speedrunner (1.5.5)")

test("1.5.5 the level race off: the release's switch is false; even on a launch realm a shipped client watches no level-up, sends no claim, and its saved book awards no comet", function()
	local w = W3.LevelRaceWorld({ compliance = "shipped", clock = 2000000000, raceOff = true })
	local c = w:Client("Brisa Vale", { level = 19 })
	local net = c.ns.HonorsNet
	eq(net.LEVEL_RACE_LAUNCHED, false, "the release's switch")
	eq(w:As(c, c.ns.LaunchRealm), true, "a launch realm all the same")
	eq(w:As(c, net.LevelRaceActive), false, "the race does not run there")
	eq(w:Events(c, true).PLAYER_LEVEL_UP, nil, "no level-up watched")
	w:Fire(c, "PLAYER_LEVEL_UP", 20)
	w:Run(3700)
	eq(#w:Sent{ from = c, type = "IL" }, 0, "no claim")
	local ok, why = w:As(c, net.SendClaim, 20)
	eq(ok, false); eq(why, "level-race-off")
	-- A saved book's places (the gold one too) award nothing: the gold comet is the Speedrunner's alone.
	local s = w:As(c, net.Store, true)
	s.levels[20] = { { guid = c.guid, name = c.name, t = w.clock - 300, place = 1 } }
	s.levels[60] = { { guid = c.guid, name = c.name, t = w.clock - 100, place = 1 } }
	eq(#w:As(c, net.Holdings, c.name, c.guid), 0, "no comet")
	eq(s.levels[60][1].name, c.name, "the book kept")
	W3.NoErrors(w)
end)

test("1.5.5 bronze and silver retired: a pick wearing either (frame and title, locked or not) falls back at the next look to his rank's frame and no title; nobody is shown with one; the book's places award none", function()
	-- (A shipped release's world: the test world wears every family's frame otherwise.)
	local w, cast = W3.New({ levelRace = false, world = { compliance = "shipped" } })
	local c, viewer = cast.spectator, cast.A
	Kept(w, c); Kept(w, viewer)
	local P = c.ns.ArenaProfile
	local m = w:As(c, P.Mine, true)
	m.frame, m.title = "level-race-20", "level-race-40"
	m.seen = { ["level-20"] = { place = 1, frame = "level-race-20", title = "level-race-20" },
		["level-40"] = { place = 1, frame = "level-race-40", title = "level-race-40" } }
	w:As(c, c.ns.HonorsNet.Refresh)
	eq(P.Pick().frame, "rank", "the bronze frame falls back to his rank's")
	eq(P.Pick().title, nil, "the silver title is gone")
	eq(P.Pick().seen["level-20"], nil); eq(P.Pick().seen["level-40"], nil)
	local v = w:As(c, c.ns.HonorsNet.Verified, c.name)
	eq(v.frame, "rank"); eq(v.title, nil)
	-- Locked: the frame falls back all the same (a frame this release does not wear); the title is shown
	-- on nobody.
	m = w:As(c, P.Mine, true)
	m.frame, m.title, m.locked = "level-race-40", "level-race-20", true
	w:As(c, c.ns.HonorsNet.Refresh)
	eq(P.Pick().frame, "rank", "locked: the silver frame falls back too")
	v = w:As(c, c.ns.HonorsNet.Verified, c.name)
	eq(v.frame, "rank"); eq(v.title, nil, "no retired title shown")
	-- A viewer told he wears them shows none; nobody can pick one.
	w:Run(5)
	local seen = w:As(viewer, viewer.ns.HonorsNet.Verified, c.name)
	eq(seen.frame, "rank"); eq(seen.title, nil)
	eq(c.ns.Honors.Choose(nil, {}, "level-race-20", nil), nil, "never picked")
	-- Even where the dormant race runs (switched on), its bronze and silver places award nothing.
	local r = W3.LevelRaceWorld({ compliance = "shipped", clock = 2000000000 })
	local f = r:Client("Corin Ash", { level = 41 })
	local s = r:As(f, f.ns.HonorsNet.Store, true)
	s.levels[20] = { { guid = f.guid, name = f.name, t = r.clock - 300, place = 1 } }
	s.levels[40] = { { guid = f.guid, name = f.name, t = r.clock - 200, place = 1 } }
	eq(r:As(f, f.ns.HonorsNet.LevelRaceActive), true)
	eq(#r:As(f, f.ns.HonorsNet.Holdings, f.name, f.guid), 0, "bronze and silver never held")
	W3.NoErrors(w); W3.NoErrors(r)
end)

test("1.5.5 the level race's apology: once, to a character told of a comet, one that remembered one and one that wore one, never to one with none nor to the Speedrunner; the race's own letters leave his list; never again after a look or a reload", function()
	local w = ListWorld("^speedrunner^Alliance^Fenra Swift-Emberfall", { compliance = "shipped" })
	local told, saw, wore = w:Client("Brisa Vale"), w:Client("Corin Ash"), w:Client("Dovan Quell")
	local none, fast = w:Client("Elsa Thornby"), w:Client("Fenra Swift")
	local all = { told, saw, wore, none, fast }
	-- (After a reload: a first session's save has not come back, and its letters never open by themselves.)
	for _, c in ipairs(all) do Kept(w, c) end
	local function Mine(c) return w:As(c, c.ns.ArenaProfile.Mine, true) end
	local m = Mine(told)
	m.lettered = { ["level-race-20"] = true }
	m.letters = { { key = "level-race-20", t = w.clock - 86400, read = true }, { key = "donor-top-1", t = w.clock - 3600, read = true } }
	m = Mine(saw)
	m.seen = { ["level-40"] = { place = 1, frame = "level-race-40", title = "level-race-40" } }
	m = Mine(wore)
	m.title = "level-race-60"
	m = Mine(fast)
	m.seen = { ["level-60"] = { place = 1, frame = "level-race-60", title = "level-race-60" } }
	m.lettered = { ["level-race-60"] = true }
	for _, c in ipairs(all) do w:As(c, c.ns.HonorsNet.Refresh) end
	eq(Count(told, APOLOGY), 1, "told of the bronze comet")
	eq(Count(saw, APOLOGY), 1, "remembered the silver one")
	eq(Count(wore, APOLOGY), 1, "wore the gold one's title")
	eq(Count(none, APOLOGY), 0, "nothing of the race")
	eq(Count(fast, APOLOGY), 0, "the Speedrunner's gold comet is his")
	-- The race's own letter leaves his list (never read again in the gold comet's words); the rest stay.
	eq(Count(told, "level-race-20"), 0); eq(Count(told, "donor-top-1"), 1)
	-- Shown as the King's letters are, his rank's frame round his portrait, nothing to wear: Close.
	local f = told.ns.HonorsNet.LetterFrame()
	eq(f ~= nil and f:IsShown(), true, "the letter shows")
	eq(f.body:GetText(), (told.ns.HonorsNet.LetterText(APOLOGY)))
	eq(f.wear:GetText(), told.ns.L.LETTERS_CLOSE)
	eq(told.ns.HonorsNet.TitleText(APOLOGY), told.ns.L.HONOR_APOLOGY_TITLE, "its line's name in the lists")
	local pick = told.ns.ArenaProfile.Pick()
	eq(w:As(told, told.ns.HonorsNet.CloseLetter, true), true)
	eq(told.ns.ArenaProfile.Pick().frame, pick.frame, "Close wears nothing"); eq(told.ns.ArenaProfile.Pick().title, pick.title)
	-- Once: another look, a reload, a newer look.
	for _, c in ipairs(all) do w:As(c, c.ns.HonorsNet.Refresh) end
	for _, c in ipairs({ told, saw, wore }) do
		Kept(w, c)
		w:Run(70)
		w:As(c, c.ns.HonorsNet.Refresh)
		eq(Count(c, APOLOGY), 1, c.name .. ": once")
		eq(c.ns.HonorsNet.ApologyDue(), false)
	end
	W3.NoErrors(w)
end)

test("1.5.5 the level race's apology at login: a character whose saved profile shows a comet, with no arena data saved, gets it a minute after his login", function()
	local w = World.New({ compliance = "shipped" })
	local c = w:Client("Brisa Vale")
	W3.Rules(w, c)
	local m = w:As(c, c.ns.ArenaProfile.Mine, true)
	m.frame = "level-race-20"
	Kept(w, c)
	eq(c.ns.HonorsNet.Store(), nil, "no arena honours saved")
	eq(Count(c, APOLOGY), 0)
	w:Run(c.ns.HonorsNet.REFRESH_DELAY + 1)
	eq(Count(c, APOLOGY), 1, "after the login's look")
	eq(c.ns.ArenaProfile.Pick().frame, "rank", "his bronze frame fallen back")
	W3.NoErrors(w)
end)

test("1.5.5 the Olympus Speedrunner: the signed list's ^speedrunner^ entry gives his character the gold comet and its title with the race off and no arena data; switched on at his login, the King's letter once; every client shows it on him; a namesake elsewhere, another character or a newer list without him hold nothing", function()
	local w = ListWorld("^speedrunner^Alliance^Fenra Swift-Emberfall", { compliance = "shipped" })
	local fast, viewer = w:Client("Fenra Swift"), w:Client("Brisa Vale")
	W3.Rules(w, fast); W3.Rules(w, viewer)
	local net = fast.ns.HonorsNet
	eq(net.LevelRaceActive(), false, "the race off")
	eq(net.Store(), nil, "no arena honours saved")
	eq(w:As(viewer, viewer.ns.IsSpeedrunnerName, fast.name), true)
	eq(w:As(viewer, viewer.ns.IsSpeedrunnerName, "fenra swift"), true, "a name without a realm is ours, any case")
	eq(w:As(viewer, viewer.ns.IsSpeedrunnerName, "Fenra Swift-Farrealm"), false, "a namesake on another realm group")
	eq(w:As(viewer, viewer.ns.IsSpeedrunnerName, viewer.name), false)
	-- His login's look, a minute after: the gold comet and its title, switched on, the letter once.
	w:Run(net.REFRESH_DELAY + 1)
	local held = w:As(fast, net.Holdings, fast.name)
	local h = Find(held, "level-race-60")
	assert(h, "the gold comet held")
	eq(h.art, "comet-gold"); eq(h.family, "level-60"); eq(h.milestone, 60); eq(h.title, "level-race-60")
	eq(net.TitleText("level-race-60"), "The Olympus Speedrunner")
	local pick = fast.ns.ArenaProfile.Pick()
	eq(pick.frame, "level-race-60", "worn by default"); eq(pick.title, "level-race-60")
	eq(Count(fast, "level-race-60"), 1, "the King's letter")
	local text = net.LetterText("level-race-60")
	assert(text:find("The Olympus Speedrunner", 1, true), text)
	assert(not text:find("Fenra", 1, true), "no name in the letter")
	eq(Count(fast, APOLOGY), 0, "no apology for him")
	-- Every client shows it on him once his pick is heard.
	w:Run(5)
	local v = w:As(viewer, viewer.ns.HonorsNet.Verified, fast.name)
	eq(v.frame, "level-race-60"); eq(v.title, "level-race-60"); eq(v.art, "comet-gold")
	eq(Find(w:As(viewer, viewer.ns.HonorsNet.Holdings, viewer.name), "level-race-60"), nil, "nobody else")
	-- Once: a reload and another look.
	Kept(w, fast)
	w:Run(net.REFRESH_DELAY + 1)
	w:As(fast, fast.ns.HonorsNet.Refresh)
	eq(Count(fast, "level-race-60"), 1, "never twice")
	-- A newer list without him (DATA_CHANGED): held no more; his pick stands in.
	Pins(fast, "^author^Alliance^Quill Maker-Emberfall"); Pins(viewer, "^author^Alliance^Quill Maker-Emberfall")
	w:As(fast, function() fast.ns.Fire("DATA_CHANGED") end)
	w:Run(3)
	eq(Find(w:As(fast, fast.ns.HonorsNet.Holdings, fast.name), "level-race-60"), nil)
	eq(fast.ns.ArenaProfile.Pick().frame, "rank"); eq(fast.ns.ArenaProfile.Pick().title, nil)
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, fast.name).frame, "rank")
	W3.NoErrors(w)
end)

test("1.5.5 the Olympus Speedrunner: a list taken after his login names him (DATA_CHANGED): switched on a moment later; a locked pick stays as he set it, the letter still tells", function()
	local w, cast = W3.New({ levelRace = false, world = { compliance = "shipped" }, more = { { "fast", "Fenra Swift" }, { "lock", "Gale Runner" } } })
	local fast, lock = cast.fast, cast.lock
	Kept(w, fast); Kept(w, lock)
	eq(w:As(fast, fast.ns.IsSpeedrunnerName, fast.name), false, "no list naming him yet")
	local P = lock.ns.ArenaProfile
	local m = w:As(lock, P.Mine, true)
	m.frame, m.title, m.locked = "rank", nil, true
	Pins(fast, "^speedrunner^Alliance^" .. fast.name)
	w:As(fast, function() fast.ns.Fire("DATA_CHANGED") end)
	w:Run(3)
	eq(fast.ns.ArenaProfile.Pick().frame, "level-race-60"); eq(fast.ns.ArenaProfile.Pick().title, "level-race-60")
	eq(Count(fast, "level-race-60"), 1)
	-- Locked: his pick stays; the letter tells; he can pick it himself.
	Pins(lock, "^speedrunner^Alliance^" .. lock.name)
	w:As(lock, function() lock.ns.Fire("DATA_CHANGED") end)
	w:Run(3)
	eq(P.Pick().frame, "rank", "a locked pick stays"); eq(P.Pick().title, nil)
	eq(Count(lock, "level-race-60"), 1, "the letter still tells")
	eq(w:As(lock, P.SetPick, "level-race-60", "level-race-60") ~= false, true)
	eq(P.Pick().frame, "level-race-60")
	W3.NoErrors(w)
end)

test("1.5.5 the signed list's ^speedrunner^ entry: one name a side, lower case kind, a name with its realm; older kinds read as before", function()
	local ns = H.ns
	local p = ns.ReadPins("^speedrunner^Alliance^Fenra Swift-Emberfall,Other Runner-Emberfall;^speedrunner^Horde^Tusk Swift-Emberfall;"
		.. "^Speedrunner^Alliance^Upper Case-Emberfall;^speedrunner^Neutral^Nobody Here-Emberfall;^author^Alliance^Quill Maker-Emberfall")
	eq(#p.speedrunner.Alliance, 1, "one a side"); eq(p.speedrunner.Alliance[1], "Fenra Swift-Emberfall")
	eq(p.speedrunner.Horde[1], "Tusk Swift-Emberfall")
	eq(p.speedrunner.Neutral, nil)
	eq(p.author.Alliance[1], "Quill Maker-Emberfall", "the author's as before")
	eq(next(ns.ReadPins("^speedrunner^Alliance^Fenra Swift").speedrunner), nil, "a name without its realm is refused")
	eq(ns.PINS_MAX.speedrunner, 1)
end)
