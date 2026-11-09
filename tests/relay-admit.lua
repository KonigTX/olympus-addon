-- 1.5.4: the presentation and the relay's admission (Relay.lua). A relay served whoever whispered
-- it; now a client answered by a relay presents itself to it with its version (RI~<version>, a word
-- no older relay has a handler for), a relay answers a ping RY~<version> once it holds that
-- presentation ("RY~", which every version takes, otherwise), a reporter's registration names its
-- version to a relay that named its own (RR~<guild>~<version>), and from the deadline on a relay
-- serves only the clients that presented themselves with a published version. The deadline, its
-- switch and the versions are the relay rules (RU), made by the author's client and carried among
-- the relays. The 1.5.3 file (tests/fixtures/relay-1.5.3.lua) stands for the relays and clients that
-- did not update. Every test here is named "relay admission (1.5.4): ...".
local ns, test, eq, extra = ...
local RelayWorld, FreshComm, ROOT = extra.RelayWorld, extra.FreshComm, extra.ROOT
local V = ns.VERSION

-- The world's globals as the relay tests set them, put back after.
local function Scene(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		fn()
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end

-- One client's world, its sends recorded in its own list however many worlds a test makes (the
-- game's C_ChatInfo is one global: each pump points it at this world first).
local function Wrap(cns, Deliver, sent, heard, Pump, Sent)
	local w = { ns = cns, Deliver = Deliver, sent = sent, heard = heard, Sent = Sent }
	function w.Use()
		C_ChatInfo.SendAddonMessage = function(_, msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, target = target, logged = false } return 0 end
		C_ChatInfo.SendAddonMessageLogged = function(_, msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, target = target, logged = true } return 0 end
	end
	function w.Pump(n) w.Use() Pump(n) end
	-- Where in the order of sends the first one starting with `prefix` (to `target`, when named) is.
	function w.At(prefix, target)
		for i, x in ipairs(sent) do
			if x.msg:sub(1, #prefix) == prefix and (target == nil or x.target == target) then return i end
		end
	end
	return w
end
local function World(me, guild) return Wrap(RelayWorld(me, guild)) end
-- A 1.5.3 client or relay: the Relay.lua that version shipped, in a world like RelayWorld's.
local function OldWorld(me)
	local cns, Deliver = FreshComm()
	cns.me, cns.splitNames = me, true
	cns.rdb = { council = { names = { ["max ran"] = "Max Ran", ["hildryn payne"] = "Hildryn Payne" }, realm = "Realm" } }
	cns.KingCharacter, cns.TreasurerPins, cns.AuthorCharacters = function() return nil end, function() return {} end, function() return {} end
	assert(loadfile(ROOT .. "tests/fixtures/relay-1.5.3.lua"))("Olympus", cns)
	cns.Relay.Reset()
	local sent, heard = {}, {}
	cns.Comm.Handle("X1", function(dist, sender, text) heard[#heard + 1] = { dist = dist, sender = sender, text = text } end)
	local function Pump(n) for _ = 1, n or 30 do cns.Comm.Pump() end end
	local function Sent(prefix) local out = {} for _, x in ipairs(sent) do if x.msg:sub(1, #prefix) == prefix then out[#out + 1] = x end end return out end
	return Wrap(cns, Deliver, sent, heard, Pump, Sent)
end
-- The author's character, as the world knows him (a relay too).
local function Author(w, name)
	w.ns.AuthorCharacters = function() return { name } end
	w.ns.IsAuthorName = function(n) return ns.ShortName(n or "") == name end
end

test("relay admission (1.5.4): a relay answers a ping with one whisper, \"RY~\" to a client it holds no presentation of and RY~<version> to one it does; a presentation (RI) is kept and answered with the version once", function()
	Scene(function()
		local R = World("Hildryn Payne-Realm", "Olympus II")
		R.Deliver("WHISPER", "Orig Inal-Realm", "RL~P~RP~")
		R.Pump()
		local ry = R.Sent("RY~")
		eq(#ry, 1, "one whisper answers the ping"); eq(ry[1].msg, "RY~", "the text every version takes"); eq(ry[1].target, "Orig Inal")
		R.Deliver("WHISPER", "Orig Inal-Realm", "RI~" .. V)
		eq(R.ns.Relay.Presented("Orig Inal-Realm"), V, "the presentation kept")
		R.Pump()
		ry = R.Sent("RY~")
		eq(#ry, 2, "answered once"); eq(ry[2].msg, "RY~" .. V, "with the relay's version"); eq(ry[2].target, "Orig Inal")
		R.Deliver("WHISPER", "Orig Inal-Realm", "RI~" .. V)
		R.Pump()
		eq(#R.Sent("RY~"), 2, "a presentation held already is not answered again")
		R.Deliver("WHISPER", "Orig Inal-Realm", "RL~P~RP~")
		R.Pump()
		ry = R.Sent("RY~")
		eq(#ry, 3, "the next ping: one whisper again"); eq(ry[3].msg, "RY~" .. V, "the version, to a client presented")
		eq(#R.Sent("RM~"), 0, "a presentation is fanned out to nobody"); eq(#R.heard, 0)
		R.Deliver("WHISPER", "Odd One-Realm", "RI~latest")
		eq(R.ns.Relay.Presented("Odd One-Realm"), nil, "what is no release's version presents nothing")
		eq(R.ns.Relay.Stats().dropped, 1)
	end)
end)

test("relay admission (1.5.4): a client presents itself (RI) to each relay that answers it, before what waited goes to that relay, once a PRESENT_GAP; it learns a relay's version from RY~<version> alone", function()
	Scene(function()
		local O = World("Orig Inal-Realm", "Olympus II")
		eq(O.ns.Comm.Send("CHANNEL", "X1~hello"), true)
		O.Pump()
		eq(#O.Sent("RL~P~RP~"), 2, "held, every relay pinged")
		O.Deliver("WHISPER", "Hildryn Payne-Realm", "RY~")
		O.Pump()
		local ri, word = O.At("RI~", "Hildryn Payne"), O.At("RL~P~X1~", "Hildryn Payne")
		assert(ri and word, "both sent to the relay that answered")
		eq(O.sent[ri].msg, "RI~" .. V)
		eq(ri < word, true, "the presentation goes before what waited")
		eq(O.ns.Relay.RelayVersion("Hildryn Payne"), nil, "a bare answer names no version")
		-- The relay's answer to the presentation names its version: learned, nothing presented again.
		O.Deliver("WHISPER", "Hildryn Payne-Realm", "RY~" .. V)
		O.Pump()
		eq(O.ns.Relay.RelayVersion("Hildryn Payne"), V)
		eq(#O.Sent("RI~"), 1, "once a PRESENT_GAP")
		O.Deliver("WHISPER", "Max Ran-Realm", "RY~" .. V)
		O.Pump()
		local toMax = O.At("RI~", "Max Ran")
		assert(toMax, "presented to the other relay that answered"); eq(O.ns.Relay.RelayVersion("Max Ran"), V)
		O.ns.clock = O.ns.clock + O.ns.Relay.PRESENT_GAP
		O.Deliver("WHISPER", "Max Ran-Realm", "RY~not a version")
		O.Pump()
		eq(#O.Sent("RI~"), 3, "past the gap, presented again on any answer")
		eq(O.ns.Relay.RelayVersion("Max Ran"), V, "what is no version changes nothing")
	end)
end)

test("relay admission (1.5.4): a reporter's registration names its version to a relay that named its own, the bare guild to any other, and one held for the first answer takes the form of the relay that answered", function()
	Scene(function()
		local A = World("Rep Orter-Realm", "Olympus II")
		A.Deliver("WHISPER", "Max Ran-Realm", "RY~" .. V)
		eq(A.ns.Relay.Register(true), true)
		A.Pump()
		local rr = A.Sent("RL~P~RR~")
		eq(#rr, 1); eq(rr[1].target, "Max Ran"); eq(rr[1].msg, "RL~P~RR~Olympus II~" .. V, "our version named to the relay that named its own")
		local B = World("Rep Orter-Realm", "Olympus II")
		B.Deliver("WHISPER", "Hildryn Payne-Realm", "RY~")
		eq(B.ns.Relay.Register(true), true)
		B.Pump()
		rr = B.Sent("RL~P~RR~")
		eq(#rr, 1); eq(rr[1].target, "Hildryn Payne"); eq(rr[1].msg, "RL~P~RR~Olympus II", "the bare guild to a relay that named none")
		local C = World("Rep Orter-Realm", "Olympus II")
		eq(C.ns.Relay.Register(true), true)
		C.Pump()
		eq(#C.Sent("RL~P~RR~"), 0, "held: no relay answered yet"); eq(C.ns.Relay.Stats().pending, 1)
		C.Deliver("WHISPER", "Max Ran-Realm", "RY~" .. V)
		C.Pump()
		rr = C.Sent("RL~P~RR~")
		eq(#rr, 1); eq(rr[1].target, "Max Ran"); eq(rr[1].msg, "RL~P~RR~Olympus II~" .. V, "flushed in the form of the relay that answered")
	end)
end)

test("relay admission (1.5.4): before the deadline a relay serves every client as before: a bare registration kept, an unpresented client's word passed on and heard, nothing refused", function()
	Scene(function()
		local R = World("Hildryn Payne-Realm", "Olympus II")
		eq(R.ns.Relay.Required(), false, "the code's deadline is ahead")
		R.Deliver("WHISPER", "Zed Far-Realm", "RL~P~RR~Olympus Zeus")
		eq(R.ns.Relay.Stats().reporters, 1)
		R.Deliver("WHISPER", "Stranger Here-Realm", "RL~P~X1~hello")
		R.Pump()
		local rm = R.Sent("RM~")
		eq(#rm, 1); eq(rm[1].target, "Zed Far")
		eq(#R.heard, 1, "heard here")
		local s = R.ns.Relay.Stats()
		eq(s.refused, 0); eq(s.unpresented, 0); eq(s.unserved, 0); eq(s.required, false); eq(s.rules, 0)
	end)
end)

test("relay admission (1.5.4): from the deadline on a bare registration is refused and one held from before goes when it renews, an unpresented client's word is dropped and counted, nothing is handed to an unpresented reporter, a presented client is served, and the presentations outlast the relay's /reload", function()
	Scene(function()
		local R = World("Hildryn Payne-Realm", "Olympus II")
		local Relay = R.ns.Relay
		R.Deliver("WHISPER", "Old Rep-Realm", "RL~P~RR~Olympus Old")
		eq(Relay.Stats().reporters, 1, "registered before the deadline")
		Relay.PRESENT_REQUIRED_AT = R.ns.clock - 1
		eq(Relay.Required(), true)
		R.Deliver("WHISPER", "New Rep-Realm", "RL~P~RR~Olympus New~" .. V)
		eq(Relay.Stats().reporters, 2, "a registration naming a published version is kept")
		eq(Relay.Presented("New Rep-Realm"), V, "and presents its reporter")
		-- A client that presented itself: served, its word handed to the presented reporter alone.
		R.Deliver("WHISPER", "Pres Ent-Realm", "RI~" .. V)
		R.Deliver("WHISPER", "Pres Ent-Realm", "RL~P~X1~hello")
		R.Pump()
		local rm = R.Sent("RM~")
		eq(#rm, 1, "to the presented reporter alone"); eq(rm[1].target, "New Rep")
		eq(#R.heard, 1, "heard here")
		eq(Relay.Stats().unserved, 1, "the unpresented reporter counted")
		-- The held registration renews bare: refused, and dropped.
		R.Deliver("WHISPER", "Old Rep-Realm", "RL~P~RR~Olympus Old")
		eq(Relay.Stats().reporters, 1, "the held registration went with the refused renewal")
		-- An unpresented client's word: dropped, answered by nobody.
		R.Deliver("WHISPER", "Stranger Here-Realm", "RL~P~X1~yo")
		R.Pump()
		eq(#R.Sent("RM~"), 1, "nothing more sent"); eq(#R.heard, 1, "not heard here either")
		-- A registration naming what is no release's version: unpresented.
		R.Deliver("WHISPER", "Odd Rep-Realm", "RL~P~RR~Olympus Odd~1.5")
		eq(Relay.Stats().reporters, 1)
		local s = Relay.Stats()
		eq(s.refused, 3); eq(s.unpresented, 3); eq(s.presented, 2)
		-- A presentation past PRESENT_FOR is gone.
		R.ns.clock = R.ns.clock + Relay.PRESENT_FOR
		eq(Relay.Presented("Pres Ent-Realm"), nil, "too long ago")
		R.ns.clock = R.ns.clock - Relay.PRESENT_FOR
		-- The relay's /reload: the store alone carries them.
		local kept = R.ns.rdb
		local R2 = World("Hildryn Payne-Realm", "Olympus II")
		R2.ns.rdb, R2.ns.clock = kept, R.ns.clock
		eq(R2.ns.Relay.Presented("Pres Ent-Realm"), V, "kept through a reload")
		R2.ns.Relay.PRESENT_REQUIRED_AT = R.ns.clock - 1
		R2.Deliver("WHISPER", "Pres Ent-Realm", "RL~P~X1~again")
		eq(#R2.heard, 1, "served at once after it")
		-- Bounded: the oldest presentation leaves for a new one past MAX_PRESENTED.
		Relay.MAX_PRESENTED = 2
		R.Deliver("WHISPER", "Third One-Realm", "RI~" .. V)
		eq(Relay.Stats().presented, 2); eq(Relay.Presented("Third One-Realm"), V)
	end)
end)

test("relay admission (1.5.4): the relay's own words, the King's (his crown too) and a signed relay's are never refused, deadline or not; none reaches a reporter that did not present", function()
	Scene(function()
		local R = World("Hildryn Payne-Realm", "Olympus II")
		R.Deliver("WHISPER", "Old Rep-Realm", "RL~P~RR~Olympus Old") -- (bare, before the deadline)
		R.ns.Relay.PRESENT_REQUIRED_AT = R.ns.clock - 1
		R.Deliver("WHISPER", "New Rep-Realm", "RL~P~RR~Olympus New~" .. V)
		R.ns.IsKingCharacter = function(name) return ns.ShortName(name) == "Kingly One" end
		R.ns.Relay.HandleIn("WHISPER", R.ns.me, "RL~P~X1~own")
		R.Deliver("WHISPER", "Kingly One-Realm", "RL~P~X1~king")
		R.Deliver("WHISPER", "Max Ran-Realm", "RL~P~X1~relay")
		R.Deliver("WHISPER", "Kingly One-Realm", "RL~P~T1~P~1~2~3")
		R.Pump()
		local rm = R.Sent("RM~")
		eq(#rm, 4, "each passed on, the King's crown too")
		for _, x in ipairs(rm) do eq(x.target, "New Rep", "to the presented reporter alone") end
		eq(#R.heard, 2, "the King's and the relay's heard here (a client never hears its own word again: Comm's echo)")
		local s = R.ns.Relay.Stats()
		eq(s.refused, 0); eq(s.unserved, 4, "the unpresented reporter passed over for each, the crown's own loop included")
	end)
end)

test("relay admission (1.5.4): Admit replaced by a stub refuses a chosen character alone, his registration and his words; Observe sees every word a relay hears, and a failing Observe stops nothing", function()
	Scene(function()
		local R = World("Hildryn Payne-Realm", "Olympus II")
		local seen = {}
		R.ns.Relay.Observe = function(kind, sender) seen[#seen + 1] = kind .. ":" .. ns.ShortName(sender) end
		R.ns.Relay.Admit = function(kind, sender) if ns.ShortName(sender) == "Grab Ber" then return false, "test rule" end return true end
		R.Deliver("WHISPER", "Grab Ber-Realm", "RL~P~RR~Olympus Grab")
		R.Deliver("WHISPER", "Zed Far-Realm", "RL~P~RR~Olympus Zeus")
		eq(R.ns.Relay.Stats().reporters, 1, "Grab Ber's registration refused, Zed's kept")
		R.Deliver("WHISPER", "Grab Ber-Realm", "RL~P~X1~mine")
		R.Deliver("WHISPER", "Zed Far-Realm", "RL~P~X1~yours")
		R.Deliver("WHISPER", "Zed Far-Realm", "RI~" .. V)
		R.Pump()
		eq(#R.Sent("RM~"), 1, "Zed's word alone passed on"); eq(#R.heard, 1)
		local s = R.ns.Relay.Stats()
		eq(s.refused, 2); eq(s.unpresented, 0, "the stub's own reason, not the presentation's")
		eq(R.ns.Relay.Refusals()[1].why, "test rule")
		eq(table.concat(seen, " "), "RR:Grab Ber RR:Zed Far RL:Grab Ber RL:Zed Far RI:Zed Far")
		R.ns.Relay.Observe = function() error("watching failed") end
		R.Deliver("WHISPER", "Orig Inal-Realm", "RL~P~RP~")
		R.Pump()
		eq(#R.Sent("RY~"), 2, "the ping answered all the same (Zed's presentation was answered first)")
	end)
end)

test("relay admission (1.5.4): a character handed to Relay.SetDenied is refused at once, deadline or not, nothing is handed to him and his held registration goes when it renews; the set cleared, he is served again", function()
	Scene(function()
		local R = World("Hildryn Payne-Realm", "Olympus II")
		local Relay = R.ns.Relay
		eq(Relay.Required(), false)
		R.Deliver("WHISPER", "Zed Far-Realm", "RL~P~RR~Olympus Zeus")
		R.Deliver("WHISPER", "Bad Guy-Realm", "RL~P~RR~Olympus Bad~" .. V)
		eq(Relay.Stats().reporters, 2)
		Relay.SetDenied({ ["bad guy"] = true })
		eq(Relay.IsDenied("Bad Guy-Realm"), true); eq(Relay.IsDenied("Zed Far-Realm"), false)
		R.Deliver("WHISPER", "Bad Guy-Realm", "RL~P~X1~mine")
		R.Pump()
		eq(#R.Sent("RM~"), 0, "dropped, presented or not"); eq(Relay.Stats().denied, 1)
		R.Deliver("WHISPER", "Zed Far-Realm", "RL~P~X1~yours")
		R.Pump()
		local rm = R.Sent("RM~")
		eq(#rm, 1, "to Zed alone: nothing is handed to the denied reporter"); eq(rm[1].target, "Zed Far")
		R.Deliver("WHISPER", "Bad Guy-Realm", "RL~P~RR~Olympus Bad~" .. V)
		eq(Relay.Stats().reporters, 1, "his held registration went")
		Relay.SetDenied(nil)
		R.Deliver("WHISPER", "Bad Guy-Realm", "RL~P~RR~Olympus Bad")
		eq(Relay.Stats().reporters, 2, "served again")
	end)
end)

test("relay admission (1.5.4): the relay rules: a new revision is taken from the author, a newer copy from a signed relay; an older or the same revision changes nothing; a stranger's and a malformed word are dropped; a newer revision is handed on to every other relay once", function()
	Scene(function()
		local R = World("Hildryn Payne-Realm", "Olympus II")
		Author(R, "Dev Elopus")
		local Relay = R.ns.Relay
		eq(Relay.Rules().rev, 0); eq(Relay.Rules().versions, Relay.PUBLISHED, "the code's own rules")
		local word = "RU~1~2~0~1794787200~1.5.3,1.5.4"
		R.Deliver("WHISPER", "Bob Stranger-Realm", word)
		eq(Relay.Rules().rev, 0, "a stranger cannot make rules"); eq(Relay.Stats().dropped, 1)
		R.Deliver("WHISPER", "Dev Elopus-Realm", word)
		local r = Relay.Rules()
		eq(r.rev, 2); eq(r.on, false); eq(r.at, 1794787200); eq(table.concat(r.versions, ","), "1.5.3,1.5.4")
		eq(R.ns.rdb.relayRules, r, "kept in the realm group's store"); eq(r.from, "Dev Elopus"); eq(r.t, R.ns.clock)
		R.Pump()
		local out = R.Sent("RU~1~2~")
		eq(#out, 1, "handed on to the other relay (not back to the author, not to itself)"); eq(out[1].target, "Max Ran"); eq(out[1].msg, word)
		R.Deliver("WHISPER", "Max Ran-Realm", "RU~1~1~1~1794787200~1.5.4")
		eq(Relay.Rules().rev, 2, "an older revision is ignored")
		R.Deliver("WHISPER", "Max Ran-Realm", "RU~1~2~1~1794787200~1.5.4")
		eq(Relay.Rules().rev, 2); eq(Relay.Rules().on, false, "the same revision changes nothing")
		R.Deliver("WHISPER", "Max Ran-Realm", "RU~1~3~1~1794000000~1.5.4")
		r = Relay.Rules()
		eq(r.rev, 3, "a newer copy from a signed relay is taken"); eq(r.on, true); eq(r.at, 1794000000); eq(r.from, "Max Ran")
		R.Pump()
		out = R.Sent("RU~1~3~")
		eq(#out, 1, "handed on once, to the relay it did not come from"); eq(out[1].target, "Dev Elopus")
		R.Deliver("WHISPER", "Max Ran-Realm", "RU~1~3~1~1794000000~1.5.4")
		R.Pump()
		eq(#R.Sent("RU~1~3~"), 1, "a second copy is handed on to nobody")
		for _, bad in ipairs({ "RU~1~4~1~abc~1.5.4", "RU~1~4~2~1794000000~1.5.4", "RU~1~4~1~1794000000~latest",
			"RU~1~4~1~1794000000~" .. string.rep("1.0.0,", 40) .. "1.0.1", "RU~1~x~1~1~", "RU~2~4~1~1794000000~1.5.4" }) do
			R.Deliver("WHISPER", "Dev Elopus-Realm", bad)
			eq(Relay.Rules().rev, 3, "malformed: " .. bad:sub(1, 40))
		end
		eq(Relay.Stats().dropped, 1 + 5, "(a word of another format version is not even read)")
	end)
end)

test("relay admission (1.5.4): the relay rules: after the deadline a version outside their list is refused though it has a release's form, the switch pauses the requirement, and a moved deadline is obeyed", function()
	Scene(function()
		local R = World("Hildryn Payne-Realm", "Olympus II")
		Author(R, "Dev Elopus")
		local Relay, now = R.ns.Relay, R.ns.clock
		R.Deliver("WHISPER", "Dev Elopus-Realm", ("RU~1~1~1~%d~1.5.4"):format(now - 10))
		eq(Relay.Required(), true)
		R.Deliver("WHISPER", "Old Ver-Realm", "RL~P~RR~Olympus Old~1.5.3")
		eq(Relay.Stats().reporters, 0, "1.5.3 has a release's form and is not on the list")
		eq(Relay.Refusals()[1].why, "version 1.5.3")
		R.Deliver("WHISPER", "New Ver-Realm", "RL~P~RR~Olympus New~1.5.4")
		eq(Relay.Stats().reporters, 1)
		R.Deliver("WHISPER", "Test Er-Realm", "RL~P~RR~Olympus Test~1.5.4-test.3")
		eq(Relay.Stats().reporters, 2, "an arena test build of a listed version")
		R.Deliver("WHISPER", "Dev Elopus-Realm", ("RU~1~2~0~%d~1.5.4"):format(now - 10))
		eq(Relay.Required(), false, "paused")
		R.Deliver("WHISPER", "Old Ver-Realm", "RL~P~RR~Olympus Old")
		eq(Relay.Stats().reporters, 3, "served while paused")
		R.Deliver("WHISPER", "Dev Elopus-Realm", ("RU~1~3~1~%d~1.5.4"):format(now + 1000))
		eq(Relay.Required(), false, "the deadline moved ahead")
		R.ns.clock = now + 1000
		eq(Relay.Required(), true, "and reached")
		R.Deliver("WHISPER", "Dev Elopus-Realm", ("RU~1~4~1~%d~"):format(now))
		eq(Relay.Published("1.5.3"), true, "a list left empty admits every release's form"); eq(Relay.Published("latest"), false)
	end)
end)

test("relay admission (1.5.4): the relay rules: a relay that logs in after the author left gets them from another relay (its ask, answered with the newer copy); a stale copy never replaces a newer one; a non-relay is neither answered nor believed; they survive a reload", function()
	Scene(function()
		local A = World("Hildryn Payne-Realm", "Olympus II")
		Author(A, "Dev Elopus")
		A.Deliver("WHISPER", "Dev Elopus-Realm", "RU~1~2~1~1794787200~1.5.4")
		eq(A.ns.Relay.Rules().rev, 2)
		-- The author gone; Max's client logs in and asks.
		local B = World("Max Ran-Realm", "Olympus II")
		Author(B, "Dev Elopus")
		eq(B.ns.Relay.AskRules(true), true)
		B.Pump()
		local asks = B.Sent("RU~1~Q~")
		eq(#asks, 2, "every other relay asked"); eq(asks[1].msg, "RU~1~Q~0")
		eq(B.ns.Relay.AskRules(), false, "not again within RULES_EVERY")
		A.Deliver("WHISPER", "Max Ran-Realm", asks[1].msg)
		A.Pump()
		local answer = A.Sent("RU~1~2~")
		eq(#answer, 1, "answered with the newer copy"); eq(answer[1].target, "Max Ran")
		B.Deliver("WHISPER", "Hildryn Payne-Realm", answer[1].msg)
		eq(B.ns.Relay.Rules().rev, 2, "taken from a signed relay"); eq(B.ns.Relay.Rules().from, "Hildryn Payne")
		-- An ask naming a revision as new as ours is not answered; a stranger's never.
		A.Deliver("WHISPER", "Max Ran-Realm", "RU~1~Q~2")
		A.Deliver("WHISPER", "Bob Stranger-Realm", "RU~1~Q~0")
		A.Pump()
		eq(#A.Sent("RU~1~2~"), 1, "no more answers")
		-- A stale copy (a relay that missed revision 2) never replaces the newer one; a stranger's
		-- newer word is not believed.
		B.Deliver("WHISPER", "Hildryn Payne-Realm", "RU~1~1~0~1794787200~1.5.3")
		B.Deliver("WHISPER", "Bob Stranger-Realm", "RU~1~9~0~1794787200~1.5.3")
		eq(B.ns.Relay.Rules().rev, 2); eq(B.ns.Relay.Rules().on, true)
		-- The next login: the store alone carries the rules.
		local kept = B.ns.rdb
		local B2 = World("Max Ran-Realm", "Olympus II")
		B2.ns.rdb = kept
		eq(B2.ns.Relay.Rules().rev, 2, "applied after a reload with nothing arriving")
		eq(B2.ns.Relay.Required(), false, "its deadline ahead of the clock")
		eq(B2.ns.Relay.Stats().rules, 2)
	end)
end)

test("relay admission (1.5.4): the relay rules: the author's /oly relay rules makes a new revision, keeps it and hands it to every relay it knows at once and again every RULES_EVERY, in pieces when longer than a whisper; anyone else is told only the author makes them; the date forms", function()
	Scene(function()
		local D = World("Dev Elopus-Realm", "Olympus II")
		Author(D, "Dev Elopus")
		local Relay = D.ns.Relay
		local said = {}
		D.ns.Print = function(m) said[#said + 1] = m end
		eq(Relay.Epoch("2026-11-16"), 1794787200); eq(Relay.Epoch("1794787200"), 1794787200); eq(Relay.Epoch("now", 5), 5)
		eq(Relay.Epoch("soon"), nil); eq(Relay.Epoch("2026-13-01"), nil)
		eq(Relay.Slash("rules on 2026-11-16 1.5.3,1.5.4 1.5.4-test.1"), true)
		local r = D.ns.rdb.relayRules
		eq(r.rev, 1); eq(r.on, true); eq(r.at, 1794787200); eq(table.concat(r.versions, ","), "1.5.3,1.5.4,1.5.4-test.1"); eq(r.from, "Dev Elopus")
		eq(said[#said], ns.L.RELAY_RULES_SET:format(1))
		D.Pump()
		local out = D.Sent("RU~1~1~")
		eq(#out, 2, "to every relay it knows, at once")
		table.sort(out, function(a, b) return a.target < b.target end)
		eq(out[1].target, "Hildryn Payne"); eq(out[2].target, "Max Ran"); eq(out[1].msg, "RU~1~1~1~1794787200~1.5.3,1.5.4,1.5.4-test.1")
		eq(Relay.SendRules(), false, "within RULES_EVERY: nothing more")
		D.ns.clock = D.ns.clock + Relay.RULES_EVERY
		eq(Relay.SendRules(), true)
		D.Pump()
		eq(#D.Sent("RU~1~1~"), 4, "again every RULES_EVERY")
		eq(Relay.Slash("rules off"), true)
		r = D.ns.rdb.relayRules
		eq(r.rev, 2); eq(r.on, false); eq(r.at, 1794787200, "the deadline kept"); eq(#r.versions, 3, "the list kept")
		eq(Relay.Slash("rules maybe"), false); eq(said[#said], ns.L.RELAY_USAGE)
		eq(Relay.Slash("rules on soon"), false, "a date that is none")
		eq(Relay.Slash("rules on now 1.5"), false, "a version that is no release's")
		eq(D.ns.rdb.relayRules.rev, 2)
		eq(Relay.Slash("rules"), true); eq(said[#said], Relay.RulesLine())
		assert(said[#said]:find("revision 2 (from Dev Elopus", 1, true) and said[#said]:find("not required (paused)", 1, true), said[#said])
		-- Forty versions: longer than one whisper, in pieces a relay puts together; forty-one refused.
		local forty = {}
		for i = 1, 40 do forty[i] = ("1.%d.%d"):format(math.floor(i / 10), i % 10) end
		local mark = #D.sent
		eq(Relay.Slash("rules on 2026-11-16 " .. table.concat(forty, ",")), true)
		D.Pump()
		local pieces = {}
		for i = mark + 1, #D.sent do
			if D.sent[i].target == "Hildryn Payne" then pieces[#pieces + 1] = D.sent[i].msg end
		end
		eq(#pieces, 2, "two whispers")
		for _, p in ipairs(pieces) do eq(#p <= 255, true, "each within a whisper") end
		local R = World("Hildryn Payne-Realm", "Olympus II")
		Author(R, "Dev Elopus")
		for _, p in ipairs(pieces) do R.Deliver("WHISPER", "Dev Elopus-Realm", p) end
		eq(R.ns.Relay.Rules().rev, 3, "put together and taken"); eq(#R.ns.Relay.Rules().versions, 40)
		forty[41] = "2.0.0"
		eq(Relay.Slash("rules on 2026-11-16 " .. table.concat(forty, ",")), false, "forty-one versions refused")
		eq(D.ns.rdb.relayRules.rev, 3)
		-- Anyone else: told only the author makes them.
		R.ns.Print = function(m) said[#said + 1] = m end
		eq(R.ns.Relay.Slash("rules off"), false); eq(said[#said], ns.L.RELAY_RULES_AUTHOR)
		eq(R.ns.Relay.Rules().rev, 3, "nothing changed")
	end)
end)

test("relay admission (1.5.4): /oly relay admitted opens the copy window with the presented, the refused and why, the denied, and the rules revision in force", function()
	Scene(function()
		local R = World("Hildryn Payne-Realm", "Olympus II")
		local Relay = R.ns.Relay
		Relay.PRESENT_REQUIRED_AT = R.ns.clock - 1
		R.Deliver("WHISPER", "Pres Ent-Realm", "RI~" .. V)
		R.Deliver("WHISPER", "Stranger Here-Realm", "RL~P~X1~yo")
		Relay.SetDenied({ ["bad guy"] = true })
		R.Deliver("WHISPER", "Bad Guy-Realm", "RL~P~X1~me")
		local got
		R.ns.UI = { ShowCopy = function(title, text) got = { title = title, text = text } end }
		eq(Relay.Slash("admitted"), true)
		eq(got.title, ns.L.RELAY_REPORT_TITLE)
		local text = got.text
		assert(text:find("Hildryn Payne-Realm (Olympus " .. V .. "), a relay", 1, true), text)
		assert(text:find("Relay rules: revision 0 (the code's own); presentation required since", 1, true), text)
		assert(text:find("Presented (1)", 1, true) and text:find("\n  Pres Ent  " .. V .. "  0 min", 1, true), text)
		assert(text:find("Refused (2)", 1, true) and text:find("\n  Stranger Here  unpresented  0 min", 1, true)
			and text:find("\n  Bad Guy  denied  0 min", 1, true), text)
		assert(text:find("Denied (1): bad guy", 1, true), text)
		-- Without the copy window: the lines printed.
		R.ns.UI = false
		local said = {}
		R.ns.Print = function(m) said[#said + 1] = m end
		Relay.Slash("admitted")
		assert(#said >= 6, "printed line by line")
		Relay.Slash("")
		eq(said[#said], ns.L.RELAY_USAGE)
	end)
end)

test("relay admission (1.5.4): its lines in both languages, with the same format arguments", function()
	local pt = { L = setmetatable({}, { __index = ns.L }) }
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", pt) end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
	local function Codes(s) local out = {} for c in s:gmatch("%%[%-%d%.]*%a") do out[#out + 1] = c end return table.concat(out, " ") end
	for _, k in ipairs({ "HELP_RELAY", "RELAY_USAGE", "RELAY_RULES_AUTHOR", "RELAY_RULES_SET", "RELAY_RULES_LINE", "RELAY_RULES_CODE",
		"RELAY_RULES_FROM_AUTHOR", "RELAY_RULES_PAUSED", "RELAY_RULES_SINCE", "RELAY_RULES_FROM", "RELAY_RULES_ANY", "RELAY_REPORT_TITLE",
		"RELAY_REPORT_HEAD", "RELAY_REPORT_RELAY", "RELAY_REPORT_NOT_RELAY", "RELAY_REPORT_PRESENTED", "RELAY_REPORT_REFUSED",
		"RELAY_REPORT_DENIED", "RELAY_AGO" }) do
		local en, p = rawget(ns.L, k), rawget(pt.L, k)
		assert(type(en) == "string" and en ~= k, "English: " .. k)
		assert(type(p) == "string", "pt-BR: " .. k)
		eq(Codes(p), Codes(en), "the same format arguments: " .. k)
	end
end)

test("relay admission (1.5.4): a 1.5.3 relay answers a 1.5.4 client's ping with \"RY~\", ignores its presentation, registers the bare guild it is sent and fans nothing out; a 1.5.3 client gets one \"RY~\" from a 1.5.4 relay, takes it, registers bare, and is served until the deadline", function()
	Scene(function()
		-- The 1.5.3 relay (the file it shipped) with a 1.5.4 client.
		local OR = OldWorld("Hildryn Payne-Realm")
		OR.Deliver("WHISPER", "Orig Inal-Realm", "RL~P~RP~")
		OR.Pump()
		eq(#OR.sent, 1, "one whisper"); eq(OR.sent[1].msg, "RY~", "the old answer")
		local O = World("Orig Inal-Realm", "Olympus II")
		O.Deliver("WHISPER", "Hildryn Payne-Realm", OR.sent[1].msg)
		eq(select(2, O.ns.Relay.Pick()), true, "answered")
		O.Pump()
		local ri = O.Sent("RI~")
		eq(#ri, 1, "the client presents itself"); eq(ri[1].target, "Hildryn Payne")
		OR.Deliver("WHISPER", "Orig Inal-Realm", ri[1].msg)
		OR.Pump()
		eq(#OR.sent, 1, "the 1.5.3 relay ignores the presentation and fans nothing out")
		eq(OR.ns.Relay.Stats().forwarded, 0); eq(OR.ns.Relay.Stats().reporters, 0)
		eq(O.ns.Relay.Register(true), true)
		O.Pump()
		local rr = O.Sent("RL~P~RR~")
		eq(#rr, 1); eq(rr[1].msg, "RL~P~RR~Olympus II", "the bare form to a relay that named no version")
		OR.Deliver("WHISPER", "Orig Inal-Realm", rr[1].msg)
		eq(OR.ns.Relay.Stats().reporters, 1, "registered as Olympus II's reporter")
		OR.Pump()
		eq(#OR.sent, 1, "nothing fanned out")
		OR.Deliver("WHISPER", "Max Ran-Realm", "RU~1~Q~0")
		OR.Deliver("WHISPER", "Max Ran-Realm", "RU~1~1~1~1794787200~1.5.4")
		OR.Pump()
		eq(#OR.sent, 1, "the rules mean nothing to it")
		-- The 1.5.3 client with a 1.5.4 relay.
		local OC = OldWorld("Old Cli-Realm")
		eq(OC.ns.Comm.Send("CHANNEL", "X1~hello"), true)
		OC.Pump()
		eq(#OC.Sent("RL~P~RP~"), 2, "pinged every relay, the message held")
		local R = World("Max Ran-Realm", "Olympus II")
		R.Deliver("WHISPER", "Old Cli-Realm", "RL~P~RP~")
		R.Pump()
		local ry = R.Sent("RY~")
		eq(#ry, 1, "one whisper"); eq(ry[1].msg, "RY~", "the text a 1.5.3 client takes")
		OC.Deliver("WHISPER", "Max Ran-Realm", "RY~" .. V)
		eq(select(2, OC.ns.Relay.Pick()), false, "(RY~<version> would be no answer to it: it is never sent one)")
		OC.Deliver("WHISPER", "Max Ran-Realm", ry[1].msg)
		eq(select(2, OC.ns.Relay.Pick()), true, "\"RY~\" is")
		OC.Pump()
		eq(#OC.Sent("RL~P~X1~"), 1, "the held word went")
		eq(OC.ns.Relay.Register(true), true)
		OC.Pump()
		local orr = OC.Sent("RL~P~RR~")
		eq(#orr, 1); eq(orr[1].msg, "RL~P~RR~Olympus II", "bare: a 1.5.3 client names no version")
		R.Deliver("WHISPER", "Old Cli-Realm", orr[1].msg)
		eq(R.ns.Relay.Stats().reporters, 1, "served before the deadline")
		R.ns.Relay.PRESENT_REQUIRED_AT = R.ns.clock - 1
		R.Deliver("WHISPER", "Old Cli-Realm", orr[1].msg)
		eq(R.ns.Relay.Stats().reporters, 0, "and no longer from the deadline on")
	end)
end)
