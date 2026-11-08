-- 1.5.4: modified builds (Builds.lua) at the arena's door (ArenaNet.lua's wrapper, Arena.Handle): a
-- client this one saw announce a version that is no release has its arena words refused before any
-- handler; an unmarked client's are taken as ever; our own client is never marked; a release announced
-- clears the mark. On the test world (tests/arena/lib/world.lua); every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World

print("1.5.4: modified builds, the arena's gate")

test("1.5.4 modified builds arena: a marked client's arena words are refused at the wrapper (dropped as build), an unmarked client's are taken, our own client is never marked, and a release announced clears the mark", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local b = w:Client("Parric Stowe")
	local c = w:Client("Wenna Crale")
	local function Dropped() return w:As(a, function() return a.ns.Arena.Stats().dropped.build or 0 end) end
	w:As(a, a.ns.Builds.Hello, b.name, "1.5.1-onn.12", w.clock)
	eq(w:As(a, a.ns.Builds.Quarantined, b.name), true, "marked by the hello")
	eq(w:As(a, a.ns.Builds.Quarantined, c.name), false)
	local before = Dropped()
	w:As(a, a.ns.Arena.Inject, "CHANNEL", b.name, "AF~L1~x")
	eq(Dropped(), before + 1, "a marked client's word: refused as build")
	w:As(a, a.ns.Arena.Inject, "WHISPER", b.name, "KN~L1~x")
	eq(Dropped(), before + 2, "by whisper too, whatever the type")
	w:As(a, a.ns.Arena.Inject, "CHANNEL", c.name, "AF~L1~x")
	eq(Dropped(), before + 2, "an unmarked client's: never as build")
	w:As(a, a.ns.Builds.Hello, a.name, "1.5.1-onn.12", w.clock)
	eq(w:As(a, a.ns.Builds.Quarantined, a.name), false, "our own client is never marked")
	w:As(a, a.ns.Builds.Hello, b.name, "1.5.4", w.clock)
	eq(w:As(a, a.ns.Builds.Quarantined, b.name), false, "a release announced clears the mark")
	w:As(a, a.ns.Arena.Inject, "CHANNEL", b.name, "AF~L1~x")
	eq(Dropped(), before + 2, "taken again")
	for _, e in ipairs(w:Errors(a)) do error(e) end
end)
