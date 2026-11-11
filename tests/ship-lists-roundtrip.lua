-- 1.5.5: the signed lists a release carries, end to end (tests/sign-roundtrip.sh runs this). scripts/council-sign.py
-- signed a council with the Twelve Apostles with a throwaway key, and scripts/ship-lists.lua wrote from it the file a
-- package carries (Olympus/SignedLists.lua). Loaded as the game loads it, the addon's own code takes it at login
-- (Workshop.TakeShipped) when the key is the one that signed it, and the Church then holds twelve Apostles; with the
-- author's key, nothing. Every name is invented.
--   luajit tests/ship-lists-roundtrip.lua <repo root> <key file> <SignedLists.lua>
local root, keyPath, shipped = arg[1], arg[2], arg[3]

-- The addon's files that take the lists and read the Apostles, with the few game functions they touch while loading
-- (as tests/sign-roundtrip.lua loads them: no frame is shown, nothing is sent).
local function stub() end
CreateFrame = function() return setmetatable({}, { __index = function() return stub end }) end
StaticPopupDialogs, SlashCmdList = {}, {}
IsInGuild = function() return false end
GetGuildInfo = function() return nil end
GetLocale = function() return "enUS" end
time, date = os.time, os.date
local ns = {}
for _, file in ipairs({ "Locales", "Core", "Codec", "Sign", "Authority", "Workshop", "Church" }) do
	if file == "Workshop" then ns.Comm = { Handle = stub } end
	assert(loadfile(root .. "/Olympus/" .. file .. ".lua"))("Olympus", ns)
end
local W, Church = ns.Workshop, ns.Church

local failed = 0
local function check(cond, what)
	if cond then print("ok: " .. what) else print("FAIL: " .. what); failed = failed + 1 end
end

-- The public half of the test key (the private half stays in the file).
local f = assert(io.open(keyPath, "r"))
local keyText = f:read("*a")
f:close()
local n, mu = keyText:match('"n"%s*:%s*"0x(%x+)"'), keyText:match('"mu"%s*:%s*"0x(%x+)"')
local k = tonumber(keyText:match('"k"%s*:%s*(%d+)'))
assert(n and mu and k, "the key file has n, mu and k")

ns.realm, ns.group, ns.me, ns.rdb, ns.db, ns.faction = "Realm", "Realm", "Tester-Realm", {}, { log = {} }, "Alliance"
-- As the game loads the file: (addon name, the addon's table).
assert(loadfile(shipped))("Olympus", ns)
check(type(ns.SHIPPED_LISTS) == "table" and #ns.SHIPPED_LISTS == 1, "the file sets ns.SHIPPED_LISTS: one realm group")
check(ns.COUNCIL_SIGNED == nil and ns.COUNCIL_TITLES == nil, "and not the author's own lists")

check(W.TakeShipped() == 0 and ns.rdb.council == nil and ns.rdb.councilTitles == nil, "the author's key takes none of the test key's lists")
check(#Church.SignedApostles() == 0, "no Apostle without a list")
ns.Sign.WithKey(n, mu, k, function()
	check(W.TakeShipped() == 2, "the names and the titles, taken with the key that signed them")
	check(W.TakeShipped() == 0, "taken once: the lists held are not checked again")
end)
local apostles = Church.SignedApostles()
check(#apostles == 12, "twelve Apostles: " .. #apostles)
check(Church.Role("Saint Ca-Realm") == "A" and Church.Role("saint la") == "A", "each of them an Apostle, whatever the case")
check(Church.Role("Saint Ma-Realm") == nil, "nobody else")
check(ns.IsHighCouncillor("Test Councillor-Realm"), "the council's names too")
check(ns.COUNCIL_SIGNED == nil and ns.COUNCIL_TITLES == nil, "still not the author's lists")

if failed > 0 then
	print(("%d check(s) of the lists a release carries failed"):format(failed))
	os.exit(1)
end
print("the lists a release carries: round trip passed")
