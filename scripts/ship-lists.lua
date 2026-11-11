-- 1.5.5: the signed lists a release carries (Workshop.TakeShipped takes them at login). It signs nothing: it copies
-- lists the author already signed (scripts/council-sign.py) into the file scripts/package.sh puts in the zip,
-- Olympus/SignedLists.lua (ns.SHIPPED_LISTS: a { names, titles } pair for each realm group), after checking each one
-- with the key the addon carries.
--
--   luajit scripts/ship-lists.lua [--addon <Olympus folder>] [--group <realm group>]... <source>... <out.lua>
--     <source>: a CouncilList.lua as council-sign.py writes it (ns.COUNCIL_SIGNED, ns.COUNCIL_TITLES and
--     ns.COUNCIL_BY_GROUP; never ns.COUNCIL_AUTHORITY, whose leadership sets expire), or a text file holding signed
--     lists one a line (HS1~... or HT1~..., as the signer prints the titles to paste). Of each realm group (each
--     list's own field) it keeps the newest names and the newest titles; with --group, the groups named alone,
--     each of which must have a list. The newest pair comes first in the file: a client takes the newest list of
--     its group first and leaves an older one of it unchecked (only a newer list is checked).
--   luajit scripts/ship-lists.lua --check [--addon <Olympus folder>] <SignedLists.lua>
--     reads a written file back as the game loads it (sandboxed: no global, nothing in ns but ns.SHIPPED_LISTS) and
--     checks every list again. scripts/package.sh runs it on the stage before it puts the file in a package.
--
-- The key is the one in <Olympus folder>/Sign.lua: the repository's Olympus/ unless --addon names another
-- (package.sh: the staged folder, the one that ships; the tests: a copy carrying their throwaway key). A list the
-- addon would refuse is refused here (its form, its size, its signature), and nothing is written. It prints realm
-- groups, times and counts, never a name. The file names players: write it under dist/ (ignored by git), never in
-- an addon folder, and never commit it.
local function Fail(msg)
	io.stderr:write("ship-lists: " .. msg .. "\n")
	os.exit(1)
end

local ROOT = (arg[0] or ""):match("^(.*)[/\\]scripts[/\\]ship%-lists%.lua$") or "."
local addon, check, groups, files = nil, false, nil, {}
do
	local i = 1
	while i <= #arg do
		local a = arg[i]
		if a == "--check" then check = true
		elseif a == "--addon" or a == "--group" then
			local v = arg[i + 1]
			if not v or v == "" then Fail(a .. " needs a value") end
			if a == "--addon" then addon = v else groups = groups or {}; groups[#groups + 1] = v end
			i = i + 1
		elseif a:sub(1, 2) == "--" then Fail("unknown option " .. a)
		else files[#files + 1] = a end
		i = i + 1
	end
end
addon = (addon or (ROOT .. "/Olympus")):gsub("[/\\]$", "")
if check and (#files ~= 1 or groups) then Fail("usage: ship-lists.lua --check [--addon <Olympus folder>] <SignedLists.lua>") end
if not check and #files < 2 then
	Fail("usage: ship-lists.lua [--addon <Olympus folder>] [--group <realm group>]... <source>... <out.lua>")
end

-- The key, as the addon checks with it.
bit = bit or require("bit")
local S = {}
do
	local chunk, err = loadfile(addon .. "/Sign.lua")
	if not chunk then Fail("cannot read the key: " .. tostring(err)) end
	chunk("Olympus", S)
end
local Sign = S.Sign
if type(Sign) ~= "table" or type(Sign.Verify) ~= "function" then Fail(addon .. "/Sign.lua defines no Sign.Verify") end

-- The forms the addon reads (Workshop.TakeCouncil and TakeTitles) and the sizes it takes: names 2000 bytes, titles
-- Workshop.TITLES_BLOB (3000).
local KINDS = {
	HS = { pattern = "^(HS1~(%d+)~([^~]*)~([^~]*))~(%x+)$", max = 2000, what = "names" },
	HT = { pattern = "^(HT1~(%d+)~([^~]*)~[01]~([^~]*))~(%x+)$", max = 3000, what = "titles" },
}
local function Read(blob, where)
	local kind = type(blob) == "string" and blob:match("^(H[ST])1~")
	local k = kind and KINDS[kind]
	if not k then Fail(where .. ": not a signed names (HS1) or titles (HT1) list") end
	local text, at, group, body, sig = blob:match(k.pattern)
	if not text then Fail(where .. ": a " .. kind .. "1 list not in its signed form") end
	if #blob > k.max then Fail(("%s: the %s list is %d bytes, more than the addon takes (%d)"):format(where, k.what, #blob, k.max)) end
	if not Sign.Plausible(sig) or not Sign.Verify(text, sig) then
		Fail(("%s: the %s list of %s (%s) fails its signature with the key in %s/Sign.lua"):format(where, k.what,
			group ~= "" and group or "any realm group", at, addon))
	end
	return { kind = kind, at = tonumber(at), group = group, body = body, blob = blob }
end

-- What a list holds, counted: never a name.
local function Count(list)
	if not list then return "-" end
	if list.kind == "HS" then
		local n = 0
		for _ in list.body:gmatch("[^,]+") do n = n + 1 end
		return ("%d (%d name%s)"):format(list.at, n, n == 1 and "" or "s")
	end
	local apostles = {}
	for side, names in list.body:gmatch("%^apostles%^(%a+)%^([^;]*)") do
		local n = 0
		for _ in names:gmatch("[^,]+") do n = n + 1 end
		apostles[#apostles + 1] = side .. " " .. n
	end
	return ("%d (Apostles: %s)"):format(list.at, #apostles > 0 and table.concat(apostles, ", ") or "none")
end
local function Say(group, hs, ht)
	print(("%s: names %s, titles %s"):format(group ~= "" and group or "(any realm group)", Count(hs), Count(ht)))
end

-- A written file, as the game loads it: (addon name, the addon's table), no global of its own.
local function CheckFile(path)
	local chunk, err = loadfile(path)
	if not chunk then Fail(path .. ": " .. tostring(err)) end
	local env, ns = {}, {}
	setfenv(chunk, env)
	local ok, e = pcall(chunk, "Olympus", ns)
	if not ok then Fail(path .. ": " .. tostring(e)) end
	if next(env) ~= nil then Fail(path .. ": it sets the global " .. tostring((next(env)))) end
	for k in pairs(ns) do
		if k ~= "SHIPPED_LISTS" then Fail(path .. ": it sets ns." .. tostring(k) .. ", not only ns.SHIPPED_LISTS") end
	end
	local L = ns.SHIPPED_LISTS
	if type(L) ~= "table" or #L == 0 then Fail(path .. ": no ns.SHIPPED_LISTS") end
	for k in pairs(L) do
		if type(k) ~= "number" or k < 1 or k > #L or k % 1 ~= 0 then Fail(path .. ": ns.SHIPPED_LISTS is not a list of pairs") end
	end
	local out, seen = {}, {}
	for i, pair in ipairs(L) do
		local where = ("%s: pair %d"):format(path, i)
		if type(pair) ~= "table" then Fail(where .. " is not a { names, titles } pair") end
		for k in pairs(pair) do if k ~= 1 and k ~= 2 then Fail(where .. " is not a { names, titles } pair") end end
		local hs = pair[1] ~= nil and Read(pair[1], where .. ", names") or nil
		local ht = pair[2] ~= nil and Read(pair[2], where .. ", titles") or nil
		if (hs and hs.kind ~= "HS") or (ht and ht.kind ~= "HT") then Fail(where .. ": names first, titles second") end
		if not hs and not ht then Fail(where .. " is empty") end
		if hs and ht and hs.group ~= ht.group then Fail(where .. ": names and titles of two realm groups") end
		local group = (hs or ht).group
		if seen[group] then Fail(where .. ": a second pair for " .. group) end
		seen[group] = true
		out[#out + 1] = { group = group, HS = hs, HT = ht }
	end
	return out
end

if check then
	for _, p in ipairs(CheckFile(files[1])) do Say(p.group, p.HS, p.HT) end
	print(("ship-lists: %s holds good lists for the key in %s/Sign.lua"):format(files[1], addon))
	os.exit(0)
end

local out = table.remove(files)
if out:match("^Olympus[%w_]*[/\\]") or out:match("[/\\]Olympus[%w_]*[/\\]") then
	Fail(out .. ": write it under dist/, never into an addon folder (the package adds it, the repository never holds it)")
end

-- Every signed list in the sources.
local found = {}
local function Add(blob, where) if type(blob) == "string" then found[#found + 1] = Read(blob, where) end end
for _, path in ipairs(files) do
	local f = io.open(path, "rb")
	if not f then Fail("cannot read " .. path) end
	local content = f:read("*a")
	f:close()
	local before = #found
	if content:find("ns%.COUNCIL_") then
		local chunk, err = loadstring(content, "=" .. path)
		if not chunk then Fail(path .. ": " .. tostring(err)) end
		setfenv(chunk, {})
		local t = {}
		local ok, e = pcall(chunk, "Olympus", t)
		if not ok then Fail(path .. ": " .. tostring(e)) end
		Add(t.COUNCIL_SIGNED, path .. " (ns.COUNCIL_SIGNED)")
		Add(t.COUNCIL_TITLES, path .. " (ns.COUNCIL_TITLES)")
		if type(t.COUNCIL_BY_GROUP) == "table" then
			for g, pair in pairs(t.COUNCIL_BY_GROUP) do
				if type(pair) == "table" then
					Add(pair[1], ("%s (ns.COUNCIL_BY_GROUP of %s, names)"):format(path, tostring(g)))
					Add(pair[2], ("%s (ns.COUNCIL_BY_GROUP of %s, titles)"):format(path, tostring(g)))
				end
			end
		end
	else
		local n = 0
		for line in (content .. "\n"):gmatch("([^\n]*)\n") do
			n = n + 1
			line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
			if line:match("^H[ST]1~") then Add(line, ("%s, line %d"):format(path, n)) end
		end
	end
	if #found == before then Fail("no signed list in " .. path) end
end

-- The newest names and the newest titles of each realm group.
local best = {}
for _, list in ipairs(found) do
	local b = best[list.group] or {}
	best[list.group] = b
	local held = b[list.kind]
	if held and held.at == list.at and held.blob ~= list.blob then
		Fail(("two different %s lists of %s with one time (%d)"):format(KINDS[list.kind].what, list.group, list.at))
	end
	if not held or list.at > held.at then b[list.kind] = list end
end
local chosen = {}
if groups then
	for _, g in ipairs(groups) do
		if not best[g] then Fail("no signed list of the realm group " .. g .. " in the sources") end
		if not chosen[g] then chosen[g] = true; chosen[#chosen + 1] = g end
	end
else
	for g in pairs(best) do chosen[#chosen + 1] = g end
end
local function Newest(g) return math.max(best[g].HS and best[g].HS.at or 0, best[g].HT and best[g].HT.at or 0) end
table.sort(chosen, function(a, b)
	if Newest(a) ~= Newest(b) then return Newest(a) > Newest(b) end
	return a < b
end)

-- A Lua string of s, byte for byte (Lua 5.1 has no \u escapes), as council-sign.py writes its lists.
local function Quote(s)
	return '"' .. s:gsub('[%c"\\\128-\255]', function(c) return ("\\%03d"):format(c:byte()) end) .. '"'
end
local lines = {
	"-- Written by scripts/ship-lists.lua for scripts/package.sh: the High Council's lists as the author signed them,",
	"-- for a release zip alone (Olympus/SignedLists.lua, named in its TOC; Workshop.TakeShipped takes them at login).",
	"-- It names players: never commit it. Every client checks each list again with the key in Sign.lua.",
	"local _, ns = ...",
	"ns.SHIPPED_LISTS = {",
}
for _, g in ipairs(chosen) do
	local b = best[g]
	lines[#lines + 1] = (" { %s, %s },"):format(b.HS and Quote(b.HS.blob) or "nil", b.HT and Quote(b.HT.blob) or "nil")
end
lines[#lines + 1] = "}"
local tmp = out .. ".tmp"
local f = io.open(tmp, "wb")
if not f then Fail("cannot write " .. tmp) end
f:write(table.concat(lines, "\n"), "\n")
f:close()
-- What was written, read back as the game reads it: the same bytes, the same checks.
local back = CheckFile(tmp)
if #back ~= #chosen then os.remove(tmp); Fail("the file written does not read back whole") end
for i, p in ipairs(back) do
	local b = best[chosen[i]]
	if (p.HS and p.HS.blob) ~= (b.HS and b.HS.blob) or (p.HT and p.HT.blob) ~= (b.HT and b.HT.blob) then
		os.remove(tmp)
		Fail("the file written does not read back byte for byte")
	end
end
local ok, err = os.rename(tmp, out)
if not ok then os.remove(tmp); Fail("cannot write " .. out .. ": " .. tostring(err)) end
for _, g in ipairs(chosen) do Say(g, best[g].HS, best[g].HT) end
print(("ship-lists: %d realm group(s) written to %s"):format(#chosen, out))
