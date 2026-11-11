-- 1.5.5 (the players' /oly bug of 11-08 and 11-09): Forever's client hands addons a chat line, its
-- sender or a channel's name as a secret value while chat is locked down (an instance, an
-- encounter, a battleground). Its type() is still "string", so `type(text) == "string"` lets it
-- through, and the first text:match, #text or comparison raises ("attempt to index local 'text' (a
-- secret string value, while execution tainted by 'Olympus')": 96 at Relay.lua:455 on 1.4.6, 33 at
-- Relay.lua:619 and 3 at ChatHall.lua:72 on 1.5.3, one at ChatHall.lua:60 on 1.5.4). Every reader of
-- a chat event's text, sender or channel name asks ns.Secret first and reads nothing of it.
-- Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT, "tests/run.lua hands ROOT to this file")
local ADDON_DIR = ROOT .. "Olympus/"
local Secret = assert(loadfile(ROOT .. "tests/arena/lib/secret.lua"))()
local ffi = require("ffi")
local SecretType = ffi.typeof("olympus_secret_t")

-- The client's secret string, as near as LuaJIT allows: a value every index, length, comparison,
-- join or tostring raises on (tests/arena/lib/secret.lua), which type() calls a "string" (the
-- client's answer) and issecretvalue knows. fn runs with both in place; errors captured by the
-- addon (ns.SafeCall, Comm.Inject) are collected and returned, and all is put back after.
local function WithSecrets(fn)
	local realType, savedCheck, savedCapture = type, rawget(_G, "issecretvalue"), ns.CaptureError
	local function IsSecret(v) return realType(v) == "cdata" and ffi.istype(SecretType, v) end
	local captured = {}
	_G.type = function(v) if IsSecret(v) then return "string" end return realType(v) end
	_G.issecretvalue = IsSecret
	ns.CaptureError = function(where, err) captured[#captured + 1] = tostring(where) .. ": " .. tostring(err) end
	local ok, err = pcall(fn, captured)
	_G.type, _G.issecretvalue, ns.CaptureError = realType, savedCheck, savedCapture
	if not ok then error(err, 0) end
	return captured
end

-- One protected call: the error (a secret was read) or nil.
local function Raised(fn, ...)
	local ok, err = pcall(fn, ...)
	return not ok and tostring(err) or nil
end

test("1.5.5 secret chat: the relay's not-found reader and its chat filter leave a secret system line unread (Relay.lua:455/619 in the players' /oly bug)", function()
	local savedNotFound = ERR_CHAT_PLAYER_NOT_FOUND_S
	local ok, err = pcall(function()
		ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
		-- Relay.lua in a namespace of its own, where names split (Forever), as tests/launch-identity.lua loads it.
		local cns = setmetatable({ On = function() end, RegisterEvent = function() end, After = function() end, Every = function() end,
			Comm = setmetatable({ Handle = function() end, RelayPieces = function() end }, { __index = ns.Comm }),
			splitNames = true, rdb = {} }, { __index = ns })
		assert(loadfile(ADDON_DIR .. "Relay.lua"))("Olympus", cns)
		local R = cns.Relay
		assert(R.On(), "the relay runs where names split")
		assert(type(ns.Treasury.NotFoundPattern()) == "string", "the server's line has a pattern here")
		ns.ResetSecretSkips()
		WithSecrets(function()
			local line = Secret.New()
			eq(Raised(R.NotFound, line), nil, "Relay.NotFound reads nothing of a secret line")
			eq(R.NotFound(line), false)
			-- (The chat filter, as the game's chat code calls it: frame, event, text.)
			eq(Raised(R.QuietLine, {}, "CHAT_MSG_SYSTEM", line), nil, "the filter reads nothing of it either")
			eq(R.QuietLine({}, "CHAT_MSG_SYSTEM", line), false, "and the line shows as the game's own")
		end)
		local skips = ns.SecretSkips()
		eq(skips["relay not found"], 2); eq(skips["relay quiet line"], 2)
		-- A plain line is still read: a name no relay has is no relay's.
		eq(R.NotFound("No player named 'Nobody Here' is currently playing."), false)
		eq(R.QuietLine({}, "CHAT_MSG_SYSTEM", "No player named 'Nobody Here' is currently playing."), false)
	end)
	ERR_CHAT_PLAYER_NOT_FOUND_S = savedNotFound
	if not ok then error(err, 0) end
end)

test("1.5.5 secret chat: the Olympus channel's text (ChatHall) leaves a secret line, sender or channel name unread, and still takes a plain line", function()
	local received = {}
	local cns = setmetatable({
		splitNames = true, me = "Me-Realm", clock = 5000,
		Comm = { ChannelIndex = function() return 6 end, ChannelName = function() return "OlympusNet1" end,
			Inject = function(dist, sender, text) received[#received + 1] = { dist = dist, sender = sender, text = text } end },
		Gate = { Allowed = function() return true end },
		On = function() end, RegisterEvent = function() end, After = function() end,
		SafeCall = function(_, fn, ...) return fn(...) end,
	}, { __index = ns })
	cns.Now = function() return cns.clock end
	assert(loadfile(ADDON_DIR .. "ChatHall.lua"))("Olympus", cns)
	local H = cns.ChatHall
	ns.ResetSecretSkips()
	WithSecrets(function()
		local s = Secret.New()
		eq(Raised(H.OnChannel, s, "Far Away-Realm", "", "", "", "", 0, 6, "OlympusNet1"), nil, "a secret line (ChatHall.lua:60/72)")
		eq(Raised(H.OnChannel, "M1~A~Olympus V~3~~hi", s, "", "", "", "", 0, 6, "OlympusNet1"), nil, "a secret sender")
		eq(Raised(H.OnChannel, "M1~A~Olympus V~3~~hi", "Far Away-Realm", "", "", "", "", 0, 6, s), nil, "a secret channel name")
		eq(#received, 0, "nothing secret is handed on")
	end)
	eq(ns.SecretSkips()["chat hall"], 3)
	eq(H.OnChannel("M1~A~Olympus V~3~~hi all", "Far Away-Realm", "", "", "", "", 0, 6, "OlympusNet1"), true, "a plain line is taken")
	eq(#received, 1); eq(received[1].text, "M1~A~Olympus V~3~~hi all")
end)

test("1.5.5 secret chat: an addon message or a channel notice with a secret prefix, text, sender or channel name is dropped before anything reads it", function()
	local events, login = {}, {}
	local savedChat = C_ChatInfo
	local ok, err = pcall(function()
		local cns = setmetatable({}, { __index = ns })
		cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
		cns.On = function(name, fn) if name == "LOGIN" then table.insert(login, fn) end end
		cns.After, cns.Every = function() end, function() end
		cns.clock = 100000
		cns.Now = function() return cns.clock end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
		assert(loadfile(ADDON_DIR .. "Comm.lua"))("Olympus", cns)
		for _, fn in ipairs(login) do fn() end
		local function Fire(event, ...)
			for _, fn in ipairs(events[event] or {}) do
				local raised = Raised(fn, ...)
				if raised then return raised end
			end
			return nil
		end
		ns.ResetSecretSkips()
		local before = cns.Comm.Stats().recv
		local captured = WithSecrets(function()
			local s = Secret.New()
			eq(Fire("CHAT_MSG_ADDON", s, "H1~1.5.5", "GUILD", "Mate-Realm"), nil, "a secret prefix (any addon's)")
			-- (The independent check: a secret prefix may be any addon's, so it is not counted as
			-- Olympus's; nor is another addon's message with a secret text.)
			eq(ns.SecretSkips()["addon message"], nil, "a secret prefix is not counted as ours")
			eq(Fire("CHAT_MSG_ADDON", "OtherAddon", s, "GUILD", "Mate-Realm"), nil, "another addon's secret text")
			eq(ns.SecretSkips()["addon message"], nil, "another addon's message is not counted")
			eq(Fire("CHAT_MSG_ADDON", ns.PREFIX, s, "GUILD", "Mate-Realm"), nil, "a secret text")
			eq(Fire("CHAT_MSG_ADDON", ns.PREFIX, "H1~1.5.5", "GUILD", s), nil, "a secret sender")
			eq(Fire("CHAT_MSG_ADDON", ns.PREFIX, "H1~1.5.5", "CHANNEL", "Mate-Realm", "", 0, 5, s), nil, "a secret channel name")
			eq(Fire("CHAT_MSG_ADDON_LOGGED", ns.PREFIX, s, "CHANNEL", "Mate-Realm"), nil, "the logged event too")
			-- The relay's way in (Comm.Inject: a line ChatHall heard) is the same reader.
			eq(cns.Comm.Inject("CHANNEL", s, "M1~A~Olympus V~3~~hi", true), true, "Inject reads nothing of a secret sender")
			-- A channel notice: its players and the channel's names (Comm.OnChannelNotice).
			eq(Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", s, "", "", 0, 5, "OlympusNet"), nil, "a secret channel name in a notice")
			eq(Fire("CHAT_MSG_CHANNEL_NOTICE_USER", "OWNER_CHANGED", s, "", "5. OlympusNet", "", "", 0, 5, "OlympusNet"), nil, "a secret player in a notice")
			eq(Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "5. OlympusNet", "", "", 0, 5, s), nil, "a secret base name")
		end)
		eq(#captured, 0, "no error caught either: " .. table.concat(captured, " | "))
		eq(cns.Comm.Stats().recv, before, "nothing secret counted as heard")
		local skips = ns.SecretSkips()
		eq(skips["addon message"], 5, "ours alone: 4 events and Inject"); eq(skips["channel notice"], 3)
	end)
	C_ChatInfo = savedChat
	if not ok then error(err, 0) end
end)

test("1.5.5 secret chat: an officer's loot line in a dungeon (a chat lockdown) is left unread", function()
	local saved = { inGroup = rawget(_G, "IsInGroup"), officer = ns.Loot.IsOfficer }
	local ok, err = pcall(function()
		IsInGroup = function() return true end
		ns.Loot.IsOfficer = function() return true end
		ns.ResetSecretSkips()
		WithSecrets(function()
			eq(Raised(ns.Loot.OnLootMessage, Secret.New()), nil, "Loot.OnLootMessage reads nothing of a secret line")
		end)
		eq(ns.SecretSkips()["loot line"], 1)
		eq(Raised(ns.Loot.OnLootMessage, "You receive loot: nothing"), nil, "a plain line is read as before")
	end)
	IsInGroup, ns.Loot.IsOfficer = saved.inGroup, saved.officer
	if not ok then error(err, 0) end
end)

test("1.5.5 secret chat: ns.Secret counts each place apart, a bounded number of places, and a client without issecretvalue keeps none", function()
	local savedCheck = rawget(_G, "issecretvalue")
	local ok, err = pcall(function()
		ns.ResetSecretSkips()
		issecretvalue = nil
		eq(ns.Secret("x", "plain"), false, "no issecretvalue: nothing is secret")
		issecretvalue = function(v) return v == "S" end
		eq(ns.Secret("a", "plain", nil, "S"), true, "any of the values")
		eq(ns.Secret("a", "plain"), false)
		issecretvalue = function() error("the check failed") end
		eq(ns.Secret("b", "plain"), true, "a check that fails reads nothing")
		issecretvalue = function() return true end
		for i = 1, ns.SECRET_WHERE_MAX + 5 do ns.Secret("place" .. i, "v") end
		local skips, places = ns.SecretSkips(), 0
		for _ in pairs(skips) do places = places + 1 end
		eq(places, ns.SECRET_WHERE_MAX + 1, "the bounded places and the rest as other")
		assert((skips.other or 0) >= 5, "the rest counted as other")
		eq(skips.a, 1); eq(skips.b, 1)
	end)
	issecretvalue = savedCheck
	ns.ResetSecretSkips()
	if not ok then error(err, 0) end
end)
