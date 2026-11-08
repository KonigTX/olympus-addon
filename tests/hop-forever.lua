-- The layer hop on WoW: Forever, where an addon's channel words are never delivered and every
-- channel word goes by a relay (Relay.lua): the real Comm.lua, Relay.lua and Hop.lua, with the
-- measured Forever facts (the server stamps each sender with the reader's own sub-realm, the guild
-- roster names every member bare).
local ns, test, eq, extra = ...

local function Saved()
	return { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild,
		realm = ns.realm, group = IsInGroup, raid = IsInRaid,
		dialogs = { request = StaticPopupDialogs.OLYMPUS_HOP_REQUEST, leave = StaticPopupDialogs.OLYMPUS_HOP_LEAVE } }
end
local function Restore(s)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = s.channel, s.member, s.guild, s.inGuild
	ns.realm, IsInGroup, IsInRaid = s.realm, s.group, s.raid
	StaticPopupDialogs.OLYMPUS_HOP_REQUEST, StaticPopupDialogs.OLYMPUS_HOP_LEAVE = s.dialogs.request, s.dialogs.leave
	C_ChatInfo = nil
end

-- Each relay world points the game's send API at its own list (RelayWorld): back to this one.
local function Bind(sent)
	C_ChatInfo.SendAddonMessage = function(_, msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, target = target, logged = false } return 0 end
	C_ChatInfo.SendAddonMessageLogged = function(_, msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, target = target, logged = true } return 0 end
end

-- Hop.lua in a relay world's namespace, its surroundings stubbed as tests/hop.lua does.
local function LoadHop(cns, w)
	w.printed, w.byName = {}, {}
	cns.db = { layerHelp = true, blocked = {} }
	cns.L = ns.L
	cns.Print = function(msg) w.printed[#w.printed + 1] = tostring(msg) end
	cns.Fire, cns.Log, cns.PlayAlert, cns.ShowDialog = function() end, function() end, function() end, function() end
	cns.SafeCall = function(label, f, ...) local ok, why = pcall(f, ...) if not ok then error(label .. ": " .. tostring(why)) end end
	cns.Alert = function(_, _, alert) if alert.open() then alert.show() end end
	cns.GamepadUI = function() return false end
	cns.QuietPresence = function() return w.quiet == true end
	cns.Moderation = { Blocks = function() return false end, Hides = function() return nil end,
		SelfOff = function() return nil end, GuildOf = function() return nil end }
	cns.Roster = { RankOf = function(name) return w.byName[ns.FullName(name)] end, MyRank = function() return 3 end,
		IsOfficer = function() return false end }
	cns.Layers = { CurrentMap = function() return 1453 end, Sharing = function() return true end, ForMap = function() return {} end,
		Mine = function() return { mapID = 1453, zoneUID = w.zoneUID or 7, t = cns.clock, confirmedAt = cns.clock } end }
	cns.Data = { Summary = function() return { guilds = {} } end }
	assert(loadfile(extra.addon .. "Hop.lua"))("Olympus", cns)
	cns.Hop.after = function(_, _, fn) fn() end
	cns.Hop.random = function(a) if a then return 1 end return 0 end
end

test("Forever layer hop: the ask goes to the asker's own guild at once over GUILD, by his plain name, and to no relay; a 1.5.3 guildmate on another sub-realm offers by whisper", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end -- (Forever: the channel delivers nothing; the relay carries it)
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		IsInGroup, IsInRaid = function() return false end, function() return false end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		-- The asker, on one sub-realm.
		ns.realm = "CAMWOWUS2Realm5PvE"
		local O, odeliver, osent, _, opump, osentOf = extra.RelayWorld("Asker Name-CAMWOWUS2Realm5PvE", "Olympus II")
		local ow = {}
		LoadHop(O, ow)
		ow.byName["Helper One-CAMWOWUS2Realm5PvE"] = 3
		O.Hop.Ask(1453, 9, "Layer of someone")
		opump()
		local rg = osentOf("RG~")
		eq(#rg, 1, "the ask goes to the guild at once")
		eq(rg[1].dist, "GUILD"); eq(rg[1].msg, ("RG~P~Asker Name~LQ~%d~1453~9"):format(O.Hop.State().id))
		eq(#osentOf("RL~"), 0, "no relay pinged, nothing whispered to one")
		eq(O.Relay.Stats().pending, 0, "nothing held for a relay")
		eq(O.Hop.State().phase, "asking", "the offers' window starts once the guild copy left")
		-- The helper, a guildmate on another sub-realm, with 1.5.3's Hop.lua and Relay.lua: the server
		-- names the asker bare, and the roster files him under the helper's own sub-realm.
		ns.realm = "CAMWOWUS2Realm1PvE"
		local H, hdeliver, _, _, hpump, hsentOf = extra.RelayWorld("Helper One-CAMWOWUS2Realm1PvE", "Olympus II")
		local hw = {}
		LoadHop(H, hw)
		hw.zoneUID = 9
		hw.byName["Asker Name-CAMWOWUS2Realm1PvE"] = 3
		hdeliver("GUILD", "Asker Name", rg[1].msg)
		hpump()
		local lo = hsentOf("LO~")
		eq(#lo, 1, "the guildmate on the asked layer offers"); eq(lo[1].dist, "WHISPER"); eq(lo[1].target, "Asker Name")
		-- Back at the asker: the offer is a guildmate's, and his request goes to him by whisper.
		ns.realm = "CAMWOWUS2Realm5PvE"
		Bind(osent)
		odeliver("WHISPER", "Helper One", lo[1].msg)
		eq(O.Hop.State().count, 1, "the offer is taken")
		O.clock = O.clock + O.Hop.WINDOW
		O.Hop.Tick()
		opump()
		local lr = osentOf("LR~")
		eq(#lr, 1); eq(lr[1].target, "Helper One"); eq(lr[1].dist, "WHISPER")
		eq(#osentOf("RL~"), 0, "the whole hop used no relay")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: the King-sighting query goes to the guild alone, a layer word to the guild at once and still to the relay; a word that is no hop's goes by the relay alone, as before", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.realm = "CAMWOWUS2Realm5PvE"
		local O, odeliver, osent, _, opump, osentOf = extra.RelayWorld("Asker Name-CAMWOWUS2Realm5PvE", "Olympus II")
		eq(O.Comm.Send("CHANNEL", "LY~Q~1~4~77~1453"), true)
		opump()
		eq(#osentOf("RG~P~Asker Name~LY~Q~1~4~77~1453"), 1, "the sighting query to the guild")
		eq(O.Relay.Stats().pending, 0, "and not held for a relay")
		eq(O.Comm.Send("CHANNEL", "L1~1453~7~3~Olympus II", "layer"), true)
		opump()
		local rg = osentOf("RG~P~Asker Name~L1~")
		eq(#rg, 1, "the layer to the guild at once"); eq(rg[1].dist, "GUILD")
		eq(O.Relay.Stats().pending, 1, "and held for the relay, as before")
		odeliver("WHISPER", "Max Ran", "RY~")
		opump()
		eq(#osentOf("RL~P~L1~1453~7~3~Olympus II"), 1, "then to the relay")
		eq(#osentOf("RG~P~Asker Name~L1~"), 1, "the guild no second time")
		wipe(osent)
		eq(O.Comm.Send("CHANNEL", "X1~census"), true)
		opump()
		eq(#osentOf("RG~"), 0, "any other word: the relay alone")
		eq(#osentOf("RL~P~X1~census"), 1)
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: quiet presence or net-off turned on while the guild copy waits keeps it home; a guarded ask whose guard fails is not sent", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.realm = "CAMWOWUS2Realm5PvE"
		local O, _, osent, _, opump, osentOf = extra.RelayWorld("Asker Name-CAMWOWUS2Realm5PvE", "Olympus II")
		local quiet, blocked = false, false
		O.QuietPresence = function() return quiet end
		O.Moderation = { Blocks = function(msg) return blocked and msg:find("^L1~") ~= nil end }
		eq(O.Comm.Send("CHANNEL", "L1~1453~7~3~Olympus II", "layer"), true)
		quiet = true
		opump()
		eq(#osentOf("RG~"), 0, "quiet presence since: the layer stays home")
		quiet = false
		eq(O.Comm.Send("CHANNEL", "L1~1453~8~3~Olympus II", "layer"), true)
		blocked = true
		opump()
		eq(#osentOf("RG~"), 0, "net-off since: the layer stays home")
		blocked = false
		local allowed, told = false, nil
		eq(O.Comm.Send("CHANNEL", "LQ~3~1453~9", nil, true, nil, function(sent) told = sent end,
			{ owner = "ask", guard = function() return allowed end }), true)
		opump()
		eq(#osentOf("RG~P~Asker Name~LQ~"), 0, "the ask's own guard refused it at the send")
		eq(told, false, "and its sender is told")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)
